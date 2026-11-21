import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/hud/hud_theme.dart';
import '../models/sim_card.dart';

class SimFormPage extends StatefulWidget {
  const SimFormPage(
      {super.key, this.initial, this.presetSlot, this.existing = const []});

  final SimCard? initial;
  final int? presetSlot;
  final List<SimCard> existing;

  @override
  State<SimFormPage> createState() => _SimFormPageState();
}

class _SimFormPageState extends State<SimFormPage> {
  final _form = GlobalKey<FormState>();
  late final SimCard? _init = widget.initial;
  late final _carrier = TextEditingController(text: _init?.carrierName);
  late final _phone = TextEditingController(text: _init?.phoneNumber);
  late final _country = TextEditingController(text: _init?.countryCode ?? 'CN');
  late final _host = TextEditingController(
      text: _init?.hostName ?? (widget.presetSlot != null ? 'eSTK.me #1' : ''));
  late final _slotDetail = TextEditingController(
      text: _init?.slotDetail ??
          (widget.presetSlot != null ? 'Profile #${widget.presetSlot}' : ''));
  late final _estkSlot = TextEditingController(
      text: (_init?.estkSlotNumber ?? widget.presetSlot)?.toString() ?? '');
  late final _plan = TextEditingController(text: _init?.planName);
  late final _balance =
      TextEditingController(text: (_init?.balance ?? 0).toString());
  late final _currency = TextEditingController(text: _init?.currency ?? 'CNY');
  late final _cost =
      TextEditingController(text: (_init?.cycleCost ?? 0).toString());
  late final _cycleDays = TextEditingController(
      text: (_init?.keepAliveCycleDays ?? 180).toString());
  late final _action = TextEditingController(text: _init?.keepAliveAction);
  late final _iccid = TextEditingController(text: _init?.iccid);
  late final _pin = TextEditingController(text: _init?.pin1);
  late final _puk = TextEditingController(text: _init?.puk1);
  late final _lpa = TextEditingController(text: _init?.esimLpaCode);
  late final _services =
      TextEditingController(text: _init?.boundServices.join(', '));
  late final _notes = TextEditingController(text: _init?.notes);

  late MediaType _media = _init?.mediaType ??
      (widget.presetSlot != null ? MediaType.programmable : MediaType.physical);
  late LocationType _location = _init?.locationType ??
      (widget.presetSlot != null
          ? LocationType.smartCard
          : LocationType.device);
  late BillingCycle _billing = _init?.billingCycle ?? BillingCycle.monthly;
  late DateTime _deadline = _init?.nextDeadlineDate ??
      dateOnly(DateTime.now()).add(const Duration(days: 30));
  late bool _active = _init?.isActive ?? true;

  bool get _slotEnabled =>
      _media == MediaType.programmable || _location == LocationType.smartCard;

  String? _validateSlot(String? v) {
    if (!_slotEnabled || v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null || n < 1 || n > 15) return '槽位号需为 1-15';
    final clash = widget.existing.where((c) =>
        c.id != _init?.id && c.onProgrammableMedium && c.estkSlotNumber == n);
    if (clash.isNotEmpty) return '槽位 #$n 已被 ${clash.first.carrierName} 占用';
    return null;
  }

  String? _validateNumber(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || !n.isFinite ? '请输入数字' : null;
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final slotText = _estkSlot.text.trim();
    final card = SimCard(
      id: _init?.id ?? 'sim-${DateTime.now().microsecondsSinceEpoch}',
      carrierName: _carrier.text.trim(),
      phoneNumber: _phone.text.trim(),
      countryCode: _country.text.trim().toUpperCase(),
      mediaType: _media,
      locationType: _location,
      hostName: _host.text.trim(),
      slotDetail: _slotDetail.text.trim(),
      estkSlotNumber:
          _slotEnabled && slotText.isNotEmpty ? int.parse(slotText) : null,
      isActive: _active,
      planName: _plan.text.trim(),
      balance: double.parse(_balance.text.trim()),
      currency: _currency.text.trim().toUpperCase(),
      billingCycle: _billing,
      cycleCost: double.parse(_cost.text.trim()),
      keepAliveCycleDays: int.parse(_cycleDays.text.trim()),
      keepAliveAction: _action.text.trim(),
      lastKeepAliveDate: _init?.lastKeepAliveDate,
      nextDeadlineDate: _deadline,
      keepAliveLog: _init?.keepAliveLog ?? const [],
      iccid: _iccid.text.trim(),
      pin1: _pin.text.trim(),
      puk1: _puk.text.trim(),
      esimLpaCode: _lpa.text.trim(),
      boundServices: _services.text
          .split(RegExp(r'[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      notes: _notes.text.trim(),
    );
    Navigator.pop(context, card);
  }

  Widget _field(TextEditingController c, String label,
          {Key? key,
          String? Function(String?)? validator,
          TextInputType? type,
          bool enabled = true}) =>
      SizedBox(
        width: 260,
        child: TextFormField(
          key: key,
          controller: c,
          enabled: enabled,
          keyboardType: type,
          validator: validator,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _dropdown<T>(String label, T value, List<T> values,
          String Function(T) text, ValueChanged<T> onChanged,
          {Key? key}) =>
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<T>(
          key: key,
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(text(v)))
          ],
          onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HudLabel(title),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 12, children: children),
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_init == null ? '新增 SIM 卡' : '编辑 ${_init.carrierName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
                key: const Key('save-card'),
                onPressed: _submit,
                child: const Text('保存')),
          ),
        ],
      ),
      body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('基础信息', [
                    _field(_carrier, '运营商 *',
                        key: const Key('field-carrier'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? '必填' : null),
                    _field(_phone, '号码', key: const Key('field-phone')),
                    _field(_country, '国家/地区代码 (ISO-2)',
                        key: const Key('field-country'),
                        validator: (v) =>
                            RegExp(r'^[A-Za-z]{2}$').hasMatch((v ?? '').trim())
                                ? null
                                : '两位字母代码'),
                    _dropdown('介质类型', _media, MediaType.values, (m) => m.label,
                        (m) => _media = m,
                        key: const Key('field-media')),
                    SizedBox(
                      width: 260,
                      child: SwitchListTile(
                        title: const Text('在线启用'),
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ),
                  ]),
                  section('存放位置 / eSTK 槽位', [
                    _dropdown('存放位置', _location, LocationType.values,
                        (l) => l.label, (l) => _location = l),
                    _field(_host, '宿主设备'),
                    _field(_slotDetail, '槽位描述'),
                    _field(_estkSlot, 'eSTK 槽位号 (1-15)',
                        key: const Key('field-estk-slot'),
                        enabled: _slotEnabled,
                        type: TextInputType.number,
                        validator: _validateSlot),
                  ]),
                  section('资费', [
                    _field(_plan, '套餐名称'),
                    _field(_balance, '余额',
                        validator: _validateNumber, type: TextInputType.number),
                    _field(_currency, '币种 (CNY/USD/HKD/GBP/JPY…)'),
                    _dropdown('计费周期', _billing, BillingCycle.values,
                        (b) => b.label, (b) => _billing = b),
                    _field(_cost, '周期费用',
                        validator: _validateNumber, type: TextInputType.number),
                  ]),
                  section('保号规则', [
                    _field(_cycleDays, '保号周期 (天)',
                        key: const Key('field-cycle'),
                        type: TextInputType.number,
                        validator: (v) =>
                            (int.tryParse((v ?? '').trim()) ?? 0) > 0
                                ? null
                                : '正整数'),
                    SizedBox(
                      width: 260,
                      child: OutlinedButton.icon(
                        key: const Key('field-deadline'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _deadline,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _deadline = dateOnly(picked));
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: Text(
                            '下次死线 ${DateFormat('yyyy-MM-dd').format(_deadline)}'),
                      ),
                    ),
                    SizedBox(width: 532, child: _field(_action, '保号动作')),
                  ]),
                  section('卡背机密', [
                    _field(_iccid, 'ICCID', key: const Key('field-iccid')),
                    _field(_pin, 'PIN1'),
                    _field(_puk, 'PUK1'),
                    _field(_lpa, 'eSIM LPA 激活串'),
                    SizedBox(
                        width: 532, child: _field(_services, '绑定服务 (逗号分隔)')),
                    SizedBox(width: 532, child: _field(_notes, '备注')),
                  ]),
                ]),
          )),
    );
  }
}
