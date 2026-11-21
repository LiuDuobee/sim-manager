import 'update_logic.dart';

/// Web build: no downloads or installer; only the release page link.
class PlatformUpdateHost implements UpdateHost {
  @override
  UpdatePlatform get platform => UpdatePlatform.other;

  @override
  Future<String> getString(Uri uri) =>
      Future.error(UnsupportedError('当前平台不支持检查更新'));

  @override
  Future<String> latestTagFromWeb() =>
      Future.error(UnsupportedError('当前平台不支持检查更新'));

  @override
  Future<List<String>> deviceAbis() async => const [];

  @override
  Future<String> download(String url, String fileName,
          {void Function(int received, int? total)? onProgress,
          CancelToken? cancel}) =>
      Future.error(UnsupportedError('当前平台不支持下载更新'));

  @override
  Future<InstallOutcome> install(String path) async =>
      const InstallOutcome(InstallStatus.failed);

  @override
  Future<bool> openUrl(String url) async => false;
}
