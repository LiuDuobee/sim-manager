import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/hud/hud_theme.dart';
import '../models/sim_card.dart';
import '../services/file_export.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.cards, required this.onImport});

  final List<SimCard> cards;

  /// Returns false when the import could not be saved.
  final Future<bool> Function(List<SimCard>) onImport;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _redact = false;
  final _import = TextEditingController();

  String get _json => SimCard.encodeList(widget.cards, redactSecrets: _redact);

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _doImport() async {
    final List<SimCard> cards;
    try {
      cards = SimCard.decodeList(_import.text);
    } on Object catch (e) {
      _toast('导入失败: $e');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('覆盖导入'),
        content:
            Text('将用 ${cards.length} 张卡覆盖当前 ${widget.cards.length} 张卡，继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              key: const Key('confirm-import'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    final saved = await widget.onImport(cards);
    if (!mounted) return;
    if (!saved) {
      _toast('导入未保存，当前卡库保持不变');
      return;
    }
    _toast('已导入 ${cards.length} 张卡');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('JSON 备份 / 导入')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const HudLabel('导出'),
          SwitchListTile(
            key: const Key('redact-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('导出时脱敏 PIN / PUK / LPA'),
            value: _redact,
            onChanged: (v) => setState(() => _redact = v),
          ),
          Container(
            height: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Hud.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Hud.line),
            ),
            child: SingleChildScrollView(
              child: SelectableText(_json,
                  key: const Key('backup-json'),
                  style: Hud.mono.copyWith(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, children: [
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _json));
                _toast('已复制 ${widget.cards.length} 张卡的 JSON');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制 JSON'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final stamp = DateTime.now().toIso8601String().substring(0, 10);
                final path =
                    await saveTextFile('SIMVault_backup_$stamp.json', _json);
                _toast(path == null ? '当前平台不支持写文件，请使用复制' : '已保存到 $path');
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('保存 .json 文件'),
            ),
          ]),
          const SizedBox(height: 28),
          const HudLabel('导入（覆盖当前金库）', color: Hud.amber),
          const SizedBox(height: 10),
          TextField(
            key: const Key('import-field'),
            controller: _import,
            maxLines: 8,
            style: Hud.mono.copyWith(fontSize: 11),
            decoration: const InputDecoration(
              hintText: '粘贴 SIMVault JSON（数组或 {"cards": [...]}）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('do-import'),
              onPressed: _doImport,
              icon: const Icon(Icons.upload, size: 16),
              label: const Text('导入 JSON'),
            ),
          ),
        ]),
      );
}
