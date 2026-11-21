import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'update_logic.dart';

const _channel = MethodChannel('simvault/update');

/// Android (platform channel in MainActivity) and Windows (PowerShell +
/// Explorer) implementation.
class PlatformUpdateHost implements UpdateHost {
  @override
  UpdatePlatform get platform => Platform.isAndroid
      ? UpdatePlatform.android
      : Platform.isWindows
          ? UpdatePlatform.windows
          : UpdatePlatform.other;

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'SIMVault-updater';

  @override
  Future<String> getString(Uri uri) async {
    final client = _client();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw UpdateHttpError(res.statusCode, 'GitHub API');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> latestTagFromWeb() async {
    final client = _client();
    try {
      final req = await client.headUrl(Uri.parse(releasesPage));
      req.followRedirects = false;
      final res = await req.close();
      await res.drain<void>();
      final location = res.headers.value(HttpHeaders.locationHeader);
      final segs = location == null
          ? const <String>[]
          : Uri.parse(location).pathSegments;
      if (!res.isRedirect ||
          segs.length < 2 ||
          segs[segs.length - 2] != 'tag') {
        throw UpdateHttpError(res.statusCode, 'GitHub Release 页');
      }
      return Uri.decodeComponent(segs.last);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<String>> deviceAbis() async {
    if (!Platform.isAndroid) return const [];
    final abis = await _channel.invokeListMethod<String>('abis');
    return abis ?? const [];
  }

  Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      final cache = await _channel.invokeMethod<String>('cacheDir');
      return Directory('$cache/updates');
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return Directory('$home${Platform.pathSeparator}Downloads');
  }

  @override
  Future<String> download(String url, String fileName,
      {void Function(int received, int? total)? onProgress,
      CancelToken? cancel}) async {
    final dir = await _downloadDir();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    final part = File('${file.path}.part');
    final client = _client();
    cancel?.onCancel(() => client.close(force: true));
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) {
        throw UpdateHttpError(res.statusCode, '下载');
      }
      final total = res.contentLength > 0 ? res.contentLength : null;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (total != null && received != total) {
        throw HttpException('下载不完整（$received / $total 字节）');
      }
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      return file.path;
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<InstallOutcome> install(String path) async {
    try {
      if (Platform.isAndroid) {
        final r =
            await _channel.invokeMethod<String>('install', {'path': path});
        return InstallOutcome(switch (r) {
          'started' => InstallStatus.started,
          'needsPermission' => InstallStatus.needsPermission,
          _ => InstallStatus.failed,
        });
      }
      if (Platform.isWindows) {
        // Extract next to the zip and show it; the running exe is never
        // replaced in place.
        final zip = File(path);
        final dest = zip.parent.path;
        // Paths go through the environment, never into the script text, so
        // no character in them needs PowerShell quoting.
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Expand-Archive -LiteralPath $env:SIMVAULT_ZIP '
              r'-DestinationPath $env:SIMVAULT_DEST -Force',
        ], environment: {
          'SIMVAULT_ZIP': path,
          'SIMVAULT_DEST': dest
        });
        if (r.exitCode != 0) {
          return InstallOutcome(InstallStatus.failed, error: r.stderr);
        }
        final name = zip.uri.pathSegments.last;
        final stem = Directory(
            '$dest${Platform.pathSeparator}${name.substring(0, name.length - 4)}');
        final folder = await stem.exists() ? stem.path : dest;
        await Process.start('explorer.exe', [folder]);
        return InstallOutcome(InstallStatus.extracted, path: folder);
      }
      return const InstallOutcome(InstallStatus.failed);
    } catch (e) {
      return InstallOutcome(InstallStatus.failed, error: e);
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
            false;
      }
      if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
