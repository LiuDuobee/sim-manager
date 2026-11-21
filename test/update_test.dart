import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/services/update/update_logic.dart';
import 'package:sim_manager/services/update/update_services.dart';

const _assets = [
  ReleaseAsset('SIMVault-v3.4.0-arm64-v8a.apk', 'https://x/arm64.apk', 100),
  ReleaseAsset('SIMVault-v3.4.0-armeabi-v7a.apk', 'https://x/v7a.apk', 90),
  ReleaseAsset('SIMVault-v3.4.0-x86_64.apk', 'https://x/x86_64.apk', 110),
  ReleaseAsset('SIMVault-v3.4.0-windows-x64.zip', 'https://x/win.zip', 200),
];

String releaseJson(
        {String tag = 'v3.4.0',
        bool draft = false,
        bool prerelease = false,
        String body = '## SIMVault v3.4.0\n\n- **自动更新**\n- 修复'}) =>
    jsonEncode({
      'tag_name': tag,
      'name': 'SIMVault $tag',
      'body': body,
      'html_url': 'https://github.com/LiuDuobee/sim-manager/releases/tag/$tag',
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final a in _assets)
          {'name': a.name, 'browser_download_url': a.url, 'size': a.size}
      ],
    });

class FakeHost implements UpdateHost {
  FakeHost(
      {this.platform = UpdatePlatform.android,
      this.abis = const ['arm64-v8a']});

  @override
  final UpdatePlatform platform;
  final List<String> abis;
  final opened = <String>[];
  final downloads = <String>[];
  Completer<String>? pending;
  void Function(int, int?)? progress;
  InstallOutcome outcome = const InstallOutcome(InstallStatus.started);
  Object? downloadError;

  @override
  Future<String> getString(Uri uri) async => releaseJson();

  @override
  Future<String> latestTagFromWeb() async => 'v3.4.0';

  @override
  Future<List<String>> deviceAbis() async => abis;

  @override
  Future<String> download(String url, String fileName,
      {void Function(int received, int? total)? onProgress,
      CancelToken? cancel}) {
    downloads.add(url);
    if (downloadError != null) return Future.error(downloadError!);
    progress = onProgress;
    final c = pending = Completer<String>();
    cancel?.onCancel(() {
      if (!c.isCompleted) c.completeError(const DownloadCancelled());
    });
    return c.future;
  }

  @override
  Future<InstallOutcome> install(String path) async => outcome;

  @override
  Future<bool> openUrl(String url) async {
    opened.add(url);
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('version comparison', () {
    SemVer v(String s) => SemVer.tryParse(s)!;

    test('semantic ordering, v prefix and build metadata', () {
      expect(v('v3.3.0') > v('3.2.1'), isTrue);
      expect(v('3.10.0') > v('3.9.9'), isTrue);
      expect(v('4.0.0') > v('3.99.99'), isTrue);
      expect(v('3.3.0+7'), v('3.3.0'));
      expect(v('3.3'), v('3.3.0'));
      expect(v('3.3.0') > v('3.3.0-beta.2'), isTrue);
      expect(v('3.3.0-beta.10') > v('3.3.0-beta.2'), isTrue);
      expect(v('3.3.0-rc') > v('3.3.0-beta'), isTrue);
      expect(v('3.2.1') > v('3.3.0'), isFalse);
      expect(SemVer.tryParse('latest'), isNull);
      expect(SemVer.tryParse(''), isNull);
    });
  });

  group('asset selection', () {
    test('Windows takes the windows zip', () {
      expect(
          pickAsset(_assets, UpdatePlatform.windows)!.url, 'https://x/win.zip');
    });

    test('Android takes the APK for the first supported ABI', () {
      String? pick(List<String> abis) =>
          pickAsset(_assets, UpdatePlatform.android, abis: abis)?.url;
      expect(
          pick(['arm64-v8a', 'armeabi-v7a', 'armeabi']), 'https://x/arm64.apk');
      expect(pick(['armeabi-v7a', 'armeabi']), 'https://x/v7a.apk');
      expect(pick(['x86_64', 'arm64-v8a']), 'https://x/x86_64.apk');
      expect(pick(['x86']), isNull);
      expect(pick([]), isNull);
    });

    test('no asset for other platforms or a release without one', () {
      expect(pickAsset(_assets, UpdatePlatform.other), isNull);
      expect(
          pickAsset(_assets.take(3).toList(), UpdatePlatform.windows), isNull);
    });
  });

  group('checker', () {
    UpdateChecker checker(Future<String> Function(Uri) fetch,
            {String current = '3.3.0', DateTime Function()? clock}) =>
        UpdateChecker(
            fetch: fetch, currentVersion: () async => current, clock: clock);

    test('reports available, up to date and failures', () async {
      final r = await checker((_) async => releaseJson()).check();
      expect(r.status, UpdateStatus.available);
      expect(r.release!.version, SemVer.tryParse('3.4.0'));
      expect(r.release!.assets, hasLength(4));
      expect(r.release!.summary(), 'SIMVault v3.4.0\n- 自动更新\n- 修复');

      expect(
          (await checker((_) async => releaseJson(tag: 'v3.3.0')).check())
              .status,
          UpdateStatus.upToDate);
      expect(
          (await checker((_) async => releaseJson(), current: '3.5.0').check())
              .status,
          UpdateStatus.upToDate);
      final failed =
          await checker((_) async => throw const SocketException('offline'))
              .check();
      expect(failed.status, UpdateStatus.failed);
      expect(failed.error, isA<SocketException>());
      expect((await checker((_) async => '<html>').check()).status,
          UpdateStatus.failed);
    });

    test('only published releases are offered; queries releases/latest',
        () async {
      Uri? asked;
      final r = await checker((u) async {
        asked = u;
        return releaseJson(prerelease: true);
      }).check();
      expect(asked.toString(),
          'https://api.github.com/repos/LiuDuobee/sim-manager/releases/latest');
      expect(r.status, UpdateStatus.upToDate);
      expect(
          (await checker((_) async => releaseJson(draft: true)).check()).status,
          UpdateStatus.upToDate);
    });

    test('auto check: once a day, each version offered once, silent on failure',
        () async {
      var now = DateTime(2026, 11, 21, 9);
      var calls = 0;
      var tag = 'v3.4.0';
      var offline = false;
      final c = checker((_) async {
        calls++;
        if (offline) throw const SocketException('offline');
        return releaseJson(tag: tag);
      }, clock: () => now);

      expect((await c.autoCheck())!.release!.tag, 'v3.4.0');
      expect(calls, 1);
      now = now.add(const Duration(hours: 23));
      expect(await c.autoCheck(), isNull);
      expect(calls, 1, reason: 'throttled within a day');

      now = now.add(const Duration(hours: 2));
      expect(await c.autoCheck(), isNull, reason: 'v3.4.0 already offered');
      expect(calls, 2);

      tag = 'v3.5.0';
      now = now.add(const Duration(days: 1));
      expect((await c.autoCheck())!.release!.tag, 'v3.5.0');

      offline = true;
      now = now.add(const Duration(days: 1));
      expect(await c.autoCheck(), isNull);
      expect(calls, 4);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getInt(UpdateChecker.lastCheckKey), now.millisecondsSinceEpoch,
          reason: 'a failed attempt still counts for the day');
    });

    test('API failure falls back to the release-page redirect', () async {
      final c = UpdateChecker(
          fetch: (_) async => throw const UpdateHttpError(403, 'GitHub API'),
          latestTagFallback: () async => 'v3.4.0',
          currentVersion: () async => '3.3.0');
      final r = await c.check();
      expect(r.status, UpdateStatus.available);
      expect(r.release!.htmlUrl,
          'https://github.com/LiuDuobee/sim-manager/releases/tag/v3.4.0');
      expect(
          pickAsset(r.release!.assets, UpdatePlatform.android,
                  abis: ['armeabi-v7a'])!
              .url,
          'https://github.com/LiuDuobee/sim-manager/releases/download/v3.4.0/SIMVault-v3.4.0-armeabi-v7a.apk');
      expect(pickAsset(r.release!.assets, UpdatePlatform.windows)!.name,
          'SIMVault-v3.4.0-windows-x64.zip');

      final both = await UpdateChecker(
          fetch: (_) async => throw const UpdateHttpError(403, 'GitHub API'),
          latestTagFallback: () async => throw const SocketException('x'),
          currentVersion: () async => '3.3.0').check();
      expect(both.status, UpdateStatus.failed);
      expect(both.error.toString(), contains('访问次数超限'));
    });

    test('manual check ignores throttle and "offered once"', () async {
      final c = checker((_) async => releaseJson());
      await c.autoCheck();
      expect((await c.check()).status, UpdateStatus.available);
      expect((await c.check()).status, UpdateStatus.available);
    });
  });

  group('update UI', () {
    final atlas = decodeWorldAtlas(
        File('assets/geo/countries-110m.json').readAsStringSync());

    Future<void> frames(WidgetTester tester, [int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    UpdateServices services(FakeHost host,
            {Future<String> Function(Uri)? fetch, String current = '3.3.0'}) =>
        UpdateServices(
            host: host,
            checker: UpdateChecker(
                fetch: fetch ?? host.getString,
                currentVersion: () async => current));

    Future<void> pumpHome(WidgetTester tester, UpdateServices s) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SimVaultApp(
          home: HomePage(atlasLoader: () async => atlas, updates: s)));
      await frames(tester);
    }

    testWidgets('launch prompt appears once per version', (tester) async {
      final host = FakeHost();
      await pumpHome(tester, services(host));
      expect(find.byKey(const Key('update-dialog')), findsOneWidget);
      expect(find.text('发现新版本 v3.4.0'), findsOneWidget);
      expect(find.textContaining('自动更新'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-later')));
      await frames(tester);
      expect(find.byKey(const Key('update-dialog')), findsNothing);

      // Next launch the next day: same version, no prompt.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(UpdateChecker.lastCheckKey, 0);
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, services(host));
      expect(find.byKey(const Key('update-dialog')), findsNothing);
    });

    testWidgets('launch check stays silent offline', (tester) async {
      await pumpHome(
          tester,
          services(FakeHost(),
              fetch: (_) async => throw const SocketException('offline')));
      expect(find.byKey(const Key('update-dialog')), findsNothing);
      expect(find.byKey(const Key('update-result')), findsNothing);
      expect(find.textContaining('失败'), findsNothing);
    });

    Future<void> manualCheck(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('open-settings')));
      await frames(tester);
      expect(find.text('当前版本 v3.3.0 · 启动时每天自动检查一次 GitHub Releases'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('check-update')));
      await frames(tester);
    }

    testWidgets('manual check reports "up to date" and errors', (tester) async {
      final host = FakeHost();
      var offline = false;
      final s = services(host, current: '3.3.0', fetch: (_) async {
        if (offline) throw const SocketException('offline');
        return releaseJson(tag: 'v3.3.0');
      });
      await pumpHome(tester, s);
      await manualCheck(tester);
      expect(find.text('已是最新版本'), findsOneWidget);
      await tester.tap(find.text('好'));
      await frames(tester);

      offline = true;
      await manualCheck(tester);
      expect(find.text('检查更新失败'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-open-page')));
      expect(host.opened, [releasesPage]);
    });

    testWidgets('download shows progress, installs, can cancel and retry',
        (tester) async {
      final host = FakeHost(abis: ['x86_64', 'arm64-v8a']);
      await pumpHome(tester, services(host));
      await tester.tap(find.byKey(const Key('update-download')));
      await frames(tester);
      expect(host.downloads, ['https://x/x86_64.apk']);
      host.progress!(55, 110);
      await frames(tester, 2);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byKey(const Key('update-progress')))
              .value,
          .5);

      // Cancel closes the dialog.
      await tester.tap(find.byKey(const Key('update-cancel')));
      await frames(tester);
      expect(find.byKey(const Key('update-download-dialog')), findsNothing);

      // Manual check → download → failure → retry → install.
      await manualCheck(tester);
      host.downloadError = const SocketException('reset');
      await tester.tap(find.byKey(const Key('update-download')));
      await frames(tester);
      expect(find.textContaining('下载失败'), findsOneWidget);
      host.downloadError = null;
      await tester.tap(find.byKey(const Key('update-retry')));
      await frames(tester);
      host.pending!.complete('/cache/updates/x.apk');
      await frames(tester);
      expect(find.text('已打开系统安装器，按提示完成安装。'), findsOneWidget);
    });

    testWidgets('denied install permission falls back to the release page',
        (tester) async {
      final host = FakeHost()
        ..outcome = const InstallOutcome(InstallStatus.needsPermission);
      await pumpHome(tester, services(host));
      await tester.tap(find.byKey(const Key('update-download')));
      await frames(tester);
      host.pending!.complete('/cache/updates/x.apk');
      await frames(tester);
      expect(find.textContaining('安装未知应用'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-open-page')));
      expect(host.opened.single, contains('/releases/tag/v3.4.0'));
    });

    testWidgets('Windows extracts the zip and says so; no asset → page',
        (tester) async {
      final win = FakeHost(platform: UpdatePlatform.windows)
        ..outcome = const InstallOutcome(InstallStatus.extracted,
            path: r'C:\Users\me\Downloads\SIMVault-v3.4.0-windows-x64');
      await pumpHome(tester, services(win));
      await tester.tap(find.byKey(const Key('update-download')));
      await frames(tester);
      expect(win.downloads, ['https://x/win.zip']);
      win.pending!.complete(r'C:\Users\me\Downloads\x.zip');
      await frames(tester);
      expect(find.textContaining('不会自动替换当前程序'), findsOneWidget);
    });

    testWidgets('no matching APK offers the release page', (tester) async {
      final host = FakeHost(abis: ['mips']);
      await pumpHome(tester, services(host));
      await tester.tap(find.byKey(const Key('update-download')));
      await frames(tester);
      expect(host.downloads, isEmpty);
      expect(find.textContaining('没有适合本机的安装包'), findsOneWidget);
      expect(find.byKey(const Key('update-open-page')), findsOneWidget);
    });
  });
}
