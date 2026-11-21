import 'package:flutter/material.dart';

import '../../services/update/update_logic.dart';

/// "新版本可用" prompt: version, release-note summary, 下载更新 / 稍后.
Future<void> showUpdateAvailable(BuildContext context,
    {required ReleaseInfo release,
    required String current,
    required UpdateHost host}) async {
  final download = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('update-dialog'),
      title: Text('发现新版本 v${release.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前 v$current → 最新 ${release.tag}',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(release.summary().isEmpty ? '（本次发布没有说明）' : release.summary(),
                key: const Key('update-summary')),
          ],
        ),
      ),
      actions: [
        TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后')),
        FilledButton.icon(
            key: const Key('update-download'),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('下载更新')),
      ],
    ),
  );
  if (download == true && context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDownloadDialog(release: release, host: host),
    );
  }
}

/// Result of a manual check that found nothing to install.
Future<void> showUpdateResult(
    BuildContext context, UpdateCheckResult r, UpdateHost host) {
  final failed = r.status == UpdateStatus.failed;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('update-result'),
      title: Text(failed ? '检查更新失败' : '已是最新版本'),
      content: Text(failed
          ? '无法连接 GitHub Releases（${r.error}）。请检查网络后重试，或打开 Release 页手动下载。'
          : '当前 v${r.current} 已是最新${r.release == null ? '' : '（最新发布 ${r.release!.tag}）'}。'),
      actions: [
        if (failed)
          TextButton(
              key: const Key('update-open-page'),
              onPressed: () => host.openUrl(releasesPage),
              child: const Text('打开 Release 页')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('好')),
      ],
    ),
  );
}

/// Picks the asset for this device, downloads it with progress and cancel,
/// then hands it to the installer (Android) or extracts it (Windows).
class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog(
      {super.key, required this.release, required this.host});

  final ReleaseInfo release;
  final UpdateHost host;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

enum _Phase { downloading, failed, done }

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  _Phase _phase = _Phase.downloading;
  int _received = 0;
  int? _total;
  String _message = '';
  CancelToken? _cancel;
  ReleaseAsset? _asset;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = null;
    });
    final host = widget.host;
    try {
      final abis = await host.deviceAbis();
      final asset = pickAsset(widget.release.assets, host.platform, abis: abis);
      if (asset == null) {
        return _fail('这个版本没有适合本机的安装包'
            '${abis.isEmpty ? '' : '（${abis.join(' / ')}）'}，请到 Release 页手动下载。');
      }
      _asset = asset;
      final cancel = _cancel = CancelToken();
      final path = await host.download(asset.url, asset.name, cancel: cancel,
          onProgress: (r, t) {
        if (mounted) {
          setState(() {
            _received = r;
            _total = t ?? (asset.size > 0 ? asset.size : null);
          });
        }
      });
      if (!mounted) return;
      final out = await host.install(path);
      if (!mounted) return;
      switch (out.status) {
        case InstallStatus.started:
          _done('已打开系统安装器，按提示完成安装。');
        case InstallStatus.extracted:
          _done('新版已解压到 ${out.path}，并已打开该文件夹。'
              '请关闭当前 SIMVault，运行文件夹里的 sim_manager.exe（不会自动替换当前程序）。');
        case InstallStatus.needsPermission:
          _fail('需要允许 SIMVault「安装未知应用」。已打开系统设置，开启后点「重试」；'
              '也可以到 Release 页手动下载。');
        case InstallStatus.failed:
          _fail('安装包已下载（$path），但无法自动打开，请到 Release 页手动下载安装。');
      }
    } on DownloadCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _fail('下载失败：$e');
    }
  }

  void _fail(String m) {
    if (mounted) {
      setState(() {
        _phase = _Phase.failed;
        _message = m;
      });
    }
  }

  void _done(String m) => setState(() {
        _phase = _Phase.done;
        _message = m;
      });

  String _mb(int b) => (b / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final progress = _total == null ? null : _received / _total!;
    return AlertDialog(
      key: const Key('update-download-dialog'),
      title: Text(switch (_phase) {
        _Phase.downloading => '正在下载 ${widget.release.tag}',
        _Phase.failed => '更新未完成',
        _Phase.done => '下载完成',
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_phase == _Phase.downloading) ...[
            if (_asset != null)
              Text(_asset!.name, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                key: const Key('update-progress'), value: progress),
            const SizedBox(height: 8),
            Text(_total == null
                ? '${_mb(_received)} MB'
                : '${_mb(_received)} / ${_mb(_total!)} MB · '
                    '${(progress! * 100).toStringAsFixed(0)}%'),
          ] else
            Text(_message, key: const Key('update-message')),
        ],
      ),
      actions: switch (_phase) {
        _Phase.downloading => [
            TextButton(
                key: const Key('update-cancel'),
                onPressed: () => _cancel?.cancel(),
                child: const Text('取消')),
          ],
        _Phase.failed => [
            TextButton(
                key: const Key('update-open-page'),
                onPressed: () => widget.host.openUrl(widget.release.htmlUrl),
                child: const Text('打开 Release 页')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
            FilledButton(
                key: const Key('update-retry'),
                onPressed: _start,
                child: const Text('重试')),
          ],
        _Phase.done => [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('好')),
          ],
      },
    );
  }
}
