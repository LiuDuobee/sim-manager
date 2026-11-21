import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/hud/hud_theme.dart';
import '../models/medium.dart';
import '../models/sim_card.dart';
import '../services/file_export.dart';

class BackupPage extends StatefulWidget {
  const BackupPage(
      {super.key,
      required this.cards,
      required this.onImport,
      this.media = const []});

  final List<SimCard> cards;

  /// Returns false when the import could not be saved.
  /// The second argument is the backup's medium list, or null for a
  /// pre-v3.4 backup that has none.
  final Future<bool> Function(List<SimCard>, List<Medium>?) onImport;

  /// Exported next to the cards as `{"cards": [...], "media": [...]}`.
  final List<Medium> media;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _redact = false;
  final _import = TextEditingController();

  String get _json {
    final cards = SimCard.encodeList(widget.cards, redactSecrets: _redact);
    if (widget.media.isEmpty) return cards;
    return const JsonEncoder.withIndent('  ').convert({
      'cards': jsonDecode(cards),
      'media': [for (final m in widget.media) m.toJson()],
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _doImport() async {
    final List<SimCard> cards;
    List<Medium>? media;
    try {
      cards = SimCard.decodeList(_import.text);
      final decoded = jsonDecode(_import.text);
      if (decoded is Map && decoded['media'] is List) {
        media = Medium.decodeList(decoded['media']);
      }
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
    final saved = await widget.onImport(cards, media);
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
              color: context.hud.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.hud.line),
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
          HudLabel('导入（覆盖当前金库）', color: context.hud.amber),
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
