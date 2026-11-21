import 'package:flutter/material.dart';

import '../features/hud/hud_theme.dart';
import '../models/medium.dart';
import '../models/sim_card.dart';

/// Add, edit and remove the media (eUICC cards, built-in eSIM) that cards
/// are assigned to. Pops the edited list, or null when nothing was saved.
class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.media, required this.cards});

  final List<Medium> media;

  /// Vault and archive cards: a medium holding any of them cannot be
  /// removed or shrunk below its highest used slot.
  final List<SimCard> cards;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  late List<Medium> _media = [...widget.media];

  List<SimCard> _on(Medium m) =>
      widget.cards.where((c) => c.resolvedMediumId == m.id).toList();

  Future<void> _edit([Medium? m]) async {
    final result = await showDialog<Medium>(
      context: context,
      builder: (_) => _MediumDialog(
          initial: m,
          minCapacity: m == null
              ? 1
              : _on(m).fold<int>(
                  1,
                  (v, c) => c.estkSlotNumber != null && c.estkSlotNumber! > v
                      ? c.estkSlotNumber!
                      : v)),
    );
    if (result == null) return;
    setState(() {
      final i = _media.indexWhere((x) => x.id == result.id);
      _media = i < 0
          ? [..._media, result]
          : [for (final x in _media) x.id == result.id ? result : x];
    });
  }

  void _remove(Medium m) {
    final n = _on(m).length;
    if (n > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.name} 上还有 $n 张卡，先把它们移到别的载体或清空槽位')));
      return;
    }
    if (_media.length == 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少保留一个载体')));
      return;
    }
    setState(() => _media = _media.where((x) => x.id != m.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Scaffold(
      appBar: AppBar(title: const Text('载体管理'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
              key: const Key('media-save'),
              onPressed: () => Navigator.pop(context, _media),
              child: const Text('保存')),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('media-add'),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新增载体'),
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
                '可复写 eUICC 卡（eSTK、9eSIM、XeSIM…）和手机内置 eSIM 各算一个载体，'
                '按容量渲染槽位；运营商实体卡不占槽位。',
                style: TextStyle(fontSize: 12, color: h.muted)),
            const SizedBox(height: 12),
            for (final m in _media)
              Card(
                key: Key('medium-row-${m.id}'),
                child: ListTile(
                  leading: Icon(
                      m.kind == MediumKind.builtinEsim
                          ? Icons.smartphone
                          : Icons.sim_card_outlined,
                      color: h.sky),
                  title: Text(m.name),
                  subtitle: Text([
                    m.kind.label,
                    if (m.model != null) m.model!.name,
                    '${m.capacity} 槽 · 已用 ${_on(m).length}',
                    if (m.model?.notRecommended ?? false) '⚠ ${m.model!.note}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        key: Key('medium-edit-${m.id}'),
                        tooltip: '编辑',
                        onPressed: () => _edit(m),
                        icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                        key: Key('medium-remove-${m.id}'),
                        tooltip: '删除',
                        onPressed: () => _remove(m),
                        icon: const Icon(Icons.delete_outline)),
                  ]),
                ),
              ),
          ]),
    );
  }
}

class _MediumDialog extends StatefulWidget {
  const _MediumDialog({this.initial, required this.minCapacity});

  final Medium? initial;
  final int minCapacity;

  @override
  State<_MediumDialog> createState() => _MediumDialogState();
}

class _MediumDialogState extends State<_MediumDialog> {
  final _form = GlobalKey<FormState>();
  late String _modelId = widget.initial?.modelId ?? '';
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _capacity =
      TextEditingController(text: widget.initial?.capacity.toString() ?? '');
  late MediumKind _kind = widget.initial?.kind ?? MediumKind.euicc;

  void _pickModel(String id) {
    final m = mediumModelById(id);
    setState(() {
      _modelId = id;
      if (m == null) return;
      _kind = m.kind;
      if (_name.text.trim().isEmpty ||
          mediumModels.any((x) => x.name == _name.text.trim())) {
        _name.text = m.name;
      }
      if (m.capacity != null) _capacity.text = '${m.capacity}';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = mediumModelById(_modelId);
    return AlertDialog(
      title: Text(widget.initial == null ? '新增载体' : '编辑载体'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                key: const Key('medium-model'),
                initialValue: _modelId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '品牌型号'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('自定义')),
                  for (final m in mediumModels)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(
                          '${m.name} · ${m.capacityLabel}'
                          '${m.notRecommended ? ' · 不推荐新购' : ''}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _pickModel(v ?? ''),
              ),
              if (model != null && model.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(model.note,
                      key: const Key('medium-model-note'),
                      style: TextStyle(
                          fontSize: 12,
                          color: model.notRecommended
                              ? context.hud.rose
                              : context.hud.muted)),
                ),
              DropdownButtonFormField<MediumKind>(
                key: const Key('medium-kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '类型'),
                items: [
                  for (final k in MediumKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              TextFormField(
                key: const Key('medium-name'),
                controller: _name,
                decoration: const InputDecoration(
                    labelText: '名称（如 eSTK Max、手机内置 eSIM）'),
                validator: (v) => (v ?? '').trim().isEmpty ? '必填' : null,
              ),
              TextFormField(
                key: const Key('medium-capacity'),
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: '容量（Profile 槽位数）',
                    helperText: model?.capacity == null && model != null
                        ? '该型号容量随 Profile 大小变化，请自填'
                        : model?.approx ?? false
                            ? '厂家标称 ${model!.capacityLabel}，可按实测修改'
                            : null),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > maxMediumCapacity) {
                    return '1–$maxMediumCapacity 的整数';
                  }
                  if (n < widget.minCapacity) {
                    return '槽位 #${widget.minCapacity} 已被占用，容量不能小于 ${widget.minCapacity}';
                  }
                  return null;
                },
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          key: const Key('medium-ok'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              Medium(
                id: widget.initial?.id ??
                    'medium-${DateTime.now().microsecondsSinceEpoch}',
                name: _name.text.trim(),
                kind: _kind,
                capacity: int.parse(_capacity.text.trim()),
                modelId: _modelId,
                note: widget.initial?.note ?? '',
              ),
            );
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
