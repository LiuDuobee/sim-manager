import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where releases come from and where users can always fetch them by hand.
const updateRepo = 'LiuDuobee/sim-manager';
final latestReleaseApi =
    Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest');
const releasesPage = 'https://github.com/$updateRepo/releases/latest';

/// Semantic version (major.minor.patch[-pre][+build]); build metadata is
/// ignored for ordering, a pre-release sorts before its release.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch, [this.pre = const []]);

  final int major, minor, patch;
  final List<String> pre;

  static final _re = RegExp(
      r'^[vV]?(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$');

  static SemVer? tryParse(String raw) {
    final m = _re.firstMatch(raw.trim());
    if (m == null) return null;
    return SemVer(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3) ?? '0'), m.group(4)?.split('.') ?? const []);
  }

  @override
  int compareTo(SemVer o) {
    for (final (a, b) in [
      (major, o.major),
      (minor, o.minor),
      (patch, o.patch)
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (pre.isEmpty || o.pre.isEmpty) {
      return pre.isEmpty == o.pre.isEmpty ? 0 : (pre.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < pre.length && i < o.pre.length; i++) {
      final a = int.tryParse(pre[i]), b = int.tryParse(o.pre[i]);
      final c = a != null && b != null
          ? a.compareTo(b)
          : a != null
              ? -1
              : b != null
                  ? 1
                  : pre[i].compareTo(o.pre[i]);
      if (c != 0) return c;
    }
    return pre.length.compareTo(o.pre.length);
  }

  bool operator >(SemVer o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, pre.join('.'));

  @override
  String toString() =>
      '$major.$minor.$patch${pre.isEmpty ? '' : '-${pre.join('.')}'}';
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);

  final String name;
  final String url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.htmlUrl,
    this.name = '',
    this.body = '',
    this.assets = const [],
    this.draft = false,
    this.prerelease = false,
  });

  final String tag;
  final SemVer version;
  final String name;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final bool draft;
  final bool prerelease;

  /// GitHub REST `GET /repos/{owner}/{repo}/releases/latest` payload.
  static ReleaseInfo fromJson(Map<String, dynamic> j) {
    final tag = j['tag_name'];
    final version = tag is String ? SemVer.tryParse(tag) : null;
    if (version == null) throw FormatException('无法识别的版本号: $tag');
    return ReleaseInfo(
      tag: tag as String,
      version: version,
      name: j['name'] as String? ?? '',
      body: j['body'] as String? ?? '',
      htmlUrl: j['html_url'] as String? ?? releasesPage,
      draft: j['draft'] == true,
      prerelease: j['prerelease'] == true,
      assets: [
        for (final a in (j['assets'] as List? ?? const []))
          if (a is Map &&
              a['name'] is String &&
              a['browser_download_url'] is String)
            ReleaseAsset(
                a['name'] as String,
                a['browser_download_url'] as String,
                (a['size'] as num?)?.toInt() ?? 0),
      ],
    );
  }

  /// The first lines of the release notes, Markdown markers stripped.
  String summary({int maxLines = 8, int maxChars = 400}) {
    final lines = body
        .split(RegExp(r'\r?\n'))
        .map((l) => l
            .replaceAll(RegExp(r'^#+\s*'), '')
            .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
            .replaceAll('**', '')
            .trimRight())
        .where((l) => l.trim().isNotEmpty)
        .take(maxLines)
        .join('\n');
    return lines.length <= maxChars
        ? lines
        : '${lines.substring(0, maxChars).trimRight()}…';
  }
}

enum UpdatePlatform { android, windows, other }

/// Windows: the windows .zip. Android: the APK for the device's most
/// preferred supported ABI. Null when nothing fits (the UI then offers the
/// release page).
ReleaseAsset? pickAsset(List<ReleaseAsset> assets, UpdatePlatform platform,
    {List<String> abis = const []}) {
  switch (platform) {
    case UpdatePlatform.windows:
      final zips = assets
          .where((a) =>
              a.name.toLowerCase().endsWith('.zip') &&
              a.name.toLowerCase().contains('windows'))
          .toList();
      return zips.where((a) => a.name.contains('x64')).firstOrNull ??
          zips.firstOrNull;
    case UpdatePlatform.android:
      final apks =
          assets.where((a) => a.name.toLowerCase().endsWith('.apk')).toList();
      for (final abi in abis) {
        // Whole token only: "x86" must not match "x86_64".
        final token =
            RegExp('(?<![A-Za-z0-9_])${RegExp.escape(abi)}(?![A-Za-z0-9_])');
        final hit = apks.where((a) => token.hasMatch(a.name)).firstOrNull;
        if (hit != null) return hit;
      }
      return null;
    case UpdatePlatform.other:
      return null;
  }
}

enum UpdateStatus { available, upToDate, failed }

class UpdateCheckResult {
  const UpdateCheckResult(this.status, this.current,
      {this.release, this.error});

  final UpdateStatus status;
  final String current;
  final ReleaseInfo? release;
  final Object? error;
}

/// Asks GitHub for the latest published release and compares it with the
/// running app. The network call is injected so tests never go online.
class UpdateChecker {
  UpdateChecker({
    required this.fetch,
    required this.currentVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<String> Function(Uri uri) fetch;
  final Future<String> Function() currentVersion;
  final DateTime Function() _clock;

  static const lastCheckKey = 'simvault.update.lastCheck';
  static const notifiedKey = 'simvault.update.notifiedTag';
  static const autoInterval = Duration(days: 1);

  /// Manual check: always reports a result, including failures.
  Future<UpdateCheckResult> check() async {
    var current = '';
    try {
      current = await currentVersion();
      final mine = SemVer.tryParse(current);
      if (mine == null) throw FormatException('当前版本号无法识别: $current');
      final json = jsonDecode(await fetch(latestReleaseApi));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Release 数据格式不对');
      }
      final release = ReleaseInfo.fromJson(json);
      // /releases/latest already skips these; never offer one regardless.
      if (release.draft || release.prerelease) {
        return UpdateCheckResult(UpdateStatus.upToDate, current);
      }
      return UpdateCheckResult(
          release.version > mine
              ? UpdateStatus.available
              : UpdateStatus.upToDate,
          current,
          release: release);
    } catch (e) {
      return UpdateCheckResult(UpdateStatus.failed, current, error: e);
    }
  }

  /// Launch check: at most once a day, silent on failure, and each new
  /// version is offered only once. Returns the release to offer, if any.
  Future<UpdateCheckResult?> autoCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = _clock();
      final last = prefs.getInt(lastCheckKey);
      if (last != null) {
        final since = now.difference(DateTime.fromMillisecondsSinceEpoch(last));
        if (!since.isNegative && since < autoInterval) return null;
      }
      await prefs.setInt(lastCheckKey, now.millisecondsSinceEpoch);
      final r = await check();
      if (r.status != UpdateStatus.available) return null;
      if (prefs.getString(notifiedKey) == r.release!.tag) return null;
      await prefs.setString(notifiedKey, r.release!.tag);
      return r;
    } catch (_) {
      return null;
    }
  }
}

/// Cancels an in-flight download.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void onCancel(void Function() f) => _listeners.add(f);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final f in _listeners) {
      f();
    }
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => '已取消下载';
}

enum InstallStatus { started, needsPermission, extracted, failed }

class InstallOutcome {
  const InstallOutcome(this.status, {this.path, this.error});

  final InstallStatus status;

  /// Windows: the folder the new version was extracted to.
  final String? path;
  final Object? error;
}

/// Platform side of updating: network, files, installer, browser.
abstract class UpdateHost {
  UpdatePlatform get platform;

  Future<String> getString(Uri uri);

  Future<List<String>> deviceAbis();

  /// Downloads [url] and returns the saved file path.
  Future<String> download(String url, String fileName,
      {void Function(int received, int? total)? onProgress,
      CancelToken? cancel});

  Future<InstallOutcome> install(String path);

  Future<bool> openUrl(String url);
}
