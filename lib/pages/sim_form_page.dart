import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/hud/hud_theme.dart';
import '../features/hud/motion.dart';
import '../models/medium.dart';
import '../models/sim_card.dart';
import '../features/cards/iccid_scanner.dart';
import '../services/carrier_presets.dart';
import '../services/region_catalog.dart';
import '../features/cards/region_flag.dart';
import 'form_pickers.dart';

class SimFormPage extends StatefulWidget {
  const SimFormPage(
      {super.key,
      this.initial,
      this.presetSlot,
      this.existing = const [],
      this.media = const [legacyEstkMedium],
      this.presetMediumId});

  final SimCard? initial;
  final int? presetSlot;
  final List<SimCard> existing;

  /// Slot-bearing media the card can be assigned to.
  final List<Medium> media;

  /// Medium of [presetSlot] when opened from an empty matrix slot.
  final String? presetMediumId;

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
      text: _init?.hostName ??
          (widget.presetSlot == null
              ? ''
              : widget.presetMediumId == null ||
                      widget.presetMediumId == legacyMediumId
                  ? 'eSTK.me #1'
                  : _mediumById(widget.presetMediumId)?.name ?? ''));
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
  late final _rechargeUrl = TextEditingController(text: _init?.rechargeUrl);
  late final _profileName = TextEditingController(text: _init?.profileName);
  final _newTag = TextEditingController();
  late List<String> _tags = [...?_init?.tags];
  late Set<int> _offsets =
      (_init?.reminderOffsets ?? SimCard.defaultReminderOffsets).toSet();

  static const tagPresets = ['主力', '备用', '收藏'];
  static const offsetPresets = [30, 14, 7, 3, 1, 0];
  late String _presetId = _init?.carrierPresetId ?? '';
  late KeepAliveType _kaType = _init?.keepAliveType ?? KeepAliveType.activity;
  late RenewalBasis _renewal = _init?.renewalBasis ?? RenewalBasis.fromAction;

  late MediaType _media = _init?.mediaType ??
      (widget.presetSlot == null
          ? MediaType.physical
          : _presetBuiltin
              ? MediaType.esim
              : MediaType.programmable);
  late LocationType _location = _init?.locationType ??
      (widget.presetSlot != null && !_presetBuiltin
          ? LocationType.smartCard
          : LocationType.device);

  bool get _presetBuiltin =>
      _mediumById(widget.presetMediumId)?.kind == MediumKind.builtinEsim;
  late BillingCycle _billing = _init?.billingCycle ?? BillingCycle.monthly;
  late DateTime _deadline =
      _init?.nextDeadlineDate ?? addDays(dateOnly(DateTime.now()), 30);
  late bool _active = _init?.isActive ?? true;
  late PlanType _planType = _init?.planType ?? PlanType.prepaid;
  late bool _kaEnabled = _init?.keepAliveEnabled ?? true;
  late CardKind _kind = _init?.kind ?? CardKind.voice;
  late final _customKind = TextEditingController(text: _init?.customKind);
  late final _source = TextEditingController(text: _init?.source);
  late final _dataGb = TextEditingController(
      text: _init?.dataTotalGb == null ? '' : _fmtNum(_init!.dataTotalGb!));
  late bool _unlimited = _init?.dataUnlimited ?? false;
  late DateTime? _planStart = _init?.planStartDate;
  late final _planDays =
      TextEditingController(text: _init?.planDays?.toString() ?? '');
  late DateTime? _planEnd = _init?.planEndDate;

  static const cycleChips = [30, 60, 90, 180, 360];

  static String _fmtNum(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  /// Postpaid contracts and data / travel plans start without a keep-alive
  /// rule; it can still be switched back on by hand.
  void _syncRuleDefault() {
    _kaEnabled = _planType == PlanType.prepaid && !_kind.hasDataPlan;
  }

  /// Picking a region fills its default currency and, when the carrier is
  /// still empty or one of the previous region's presets, its first carrier.
  void _selectRegion(RegionInfo r) {
    final old = regionFor(_country.text);
    final carrier = _carrier.text.trim();
    _country.text = r.code;
    _currency.text = r.currency;
    if (r.carriers.isNotEmpty &&
        (carrier.isEmpty ||
            _init == null && old.carriers.any((c) => c.name == carrier))) {
      _selectCarrier(r.carriers.first);
    }
  }

  /// Fills the carrier name and, when it is in the rule library, its rule.
  void _selectCarrier(RegionCarrier c) {
    _carrier.text = c.name;
    if (c.presetId.isNotEmpty && presetById(c.presetId) != null) {
      _applyPreset(c.presetId);
      if (_planType == PlanType.prepaid && !_kind.hasDataPlan) {
        _kaEnabled = true;
      }
    } else if (_presetId.isNotEmpty) {
      _presetId = '';
    }
  }

  String? _validateOptionalGb(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty || _unlimited) return null;
    final n = double.tryParse(t);
    return n == null || !n.isFinite || n < 0 ? '非负数字' : null;
  }

  String? _validateOptionalDays(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n <= 0 ? '正整数' : null;
  }

  /// Explicitly chosen medium; null lets a programmable card fall back to
  /// the default eUICC medium (the legacy eSTK for old data).
  late String? _mediumId = _init?.mediumId ??
      (widget.presetSlot != null ? widget.presetMediumId : null);

  Medium? _mediumById(String? id) {
    if (id == null) return null;
    for (final m in widget.media) {
      if (m.id == id) return m;
    }
    return id == legacyMediumId ? legacyEstkMedium : null;
  }

  String get _defaultMediumId => widget.media.any((m) => m.id == legacyMediumId)
      ? legacyMediumId
      : (widget.media.where((m) => m.kind == MediumKind.euicc).firstOrNull ??
              widget.media.firstOrNull ??
              legacyEstkMedium)
          .id;

  bool get _programmable =>
      _media == MediaType.programmable || _location == LocationType.smartCard;

  bool get _slotEnabled => _mediumId != null || _programmable;

  String? get _effectiveMediumId =>
      _mediumId ?? (_programmable ? _defaultMediumId : null);

  int get _capacity => _mediumById(_effectiveMediumId)?.capacity ?? estkSlots;

  static const estkSlots = 15;

  String? _validateSlot(String? v) {
    if (!_slotEnabled || v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    final cap = _capacity;
    if (n == null || n < 1 || n > cap) return '槽位号需为 1-$cap';
    final mid = _effectiveMediumId;
    final clash = widget.existing.where((c) =>
        c.id != _init?.id &&
        c.resolvedMediumId == mid &&
        c.estkSlotNumber == n);
    if (clash.isNotEmpty) return '槽位 #$n 已被 ${clash.first.carrierName} 占用';
    return null;
  }

  String? _validateNumber(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || !n.isFinite ? '请输入数字' : null;
  }

  String? _validateFee(String? v) =>
      _validateNumber(v) ?? feeError(double.parse(v!.trim()), '周期费用');

  /// Fills the rule, cost and top-up fields from a carrier preset; the
  /// carrier name and country only when still empty / default.
  void _applyPreset(String id) {
    _presetId = id;
    final p = presetById(id);
    if (p == null) return;
    if (_carrier.text.trim().isEmpty) _carrier.text = p.name;
    if (_init == null) _country.text = p.countryCode;
    _currency.text = p.currency;
    _cost.text = p.cycleCost.toString();
    _cycleDays.text = p.cycleDays.toString();
    _action.text = p.action;
    _rechargeUrl.text = p.rechargeUrl;
    _billing = p.billingCycle;
    _kaType = p.type;
    _renewal = p.renewal;
  }

  /// Live annual-cost preview from the current form values.
  String _annualPreview() {
    final cost = double.tryParse(_cost.text.trim());
    final days = int.tryParse(_cycleDays.text.trim());
    if (cost == null ||
        !cost.isFinite ||
        cost < 0 ||
        days == null ||
        days <= 0) {
      return '预估年成本 —';
    }
    final probe = SimCard(
      id: '',
      carrierName: '',
      phoneNumber: '',
      countryCode: 'CN',
      mediaType: MediaType.physical,
      nextDeadlineDate: _deadline,
      currency: _currency.text.trim().toUpperCase(),
      cycleCost: cost,
      billingCycle: _billing,
      keepAliveCycleDays: days,
    );
    return '预估年成本 ${probe.currency} ${probe.annualCost.toStringAsFixed(2)}'
        ' ≈ ¥${probe.annualCny.toStringAsFixed(0)}';
  }

  int _shake = 0;

  void _submit() {
    if (!_form.currentState!.validate()) {
      Haptics.error();
      setState(() => _shake++);
      return;
    }
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
      // Programmable cards on the legacy eSTK keep mediumId null, as before.
      mediumId: !_slotEnabled ||
              (_effectiveMediumId == legacyMediumId && _programmable)
          ? null
          : _effectiveMediumId,
      isActive: _active,
      planName: _plan.text.trim(),
      balance: double.parse(_balance.text.trim()),
      currency: _currency.text.trim().toUpperCase(),
      billingCycle: _billing,
      cycleCost: double.parse(_cost.text.trim()),
      // The cycle field is hidden (and unvalidated) while the rule is off.
      keepAliveCycleDays: _kaEnabled
          ? int.parse(_cycleDays.text.trim())
          : int.tryParse(_cycleDays.text.trim()) ??
              _init?.keepAliveCycleDays ??
              180,
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
      keepAliveType: _kaType,
      renewalBasis: _renewal,
      carrierPresetId: _presetId,
      rechargeUrl: _rechargeUrl.text.trim(),
      events: _init?.events ?? const [],
      archivedAt: _init?.archivedAt,
      tags: normalizeTags(_tags),
      reminderOffsets: normalizeOffsets(_offsets),
      profileName: _slotEnabled ? _profileName.text.trim() : '',
      planType: _planType,
      keepAliveEnabled: _kaEnabled,
      kind: _kind,
      customKind: _kind == CardKind.other ? _customKind.text.trim() : '',
      source: _kind.hasDataPlan ? _source.text.trim() : '',
      dataTotalGb: _kind.hasDataPlan && !_unlimited
          ? double.tryParse(_dataGb.text.trim())
          : null,
      dataUnlimited: _kind.hasDataPlan && _unlimited,
      planStartDate: _kind.hasDataPlan ? _planStart : null,
      planDays: _kind.hasDataPlan ? int.tryParse(_planDays.text.trim()) : null,
      planEndDate: _kind.hasDataPlan ? _planEnd : null,
    );
    Navigator.pop(context, card);
  }

  // Field widths: two 260dp columns on wide screens; on phones every field
  // takes the full content width instead of leaving a dead right margin.
  double _w = 260, _wide = 532;

  void _fitFields(double contentWidth) {
    if (contentWidth < 532) {
      _w = _wide = contentWidth;
    } else {
      _w = 260;
      _wide = 532;
    }
  }

  Widget _field(TextEditingController c, String label,
          {Key? key,
          String? Function(String?)? validator,
          TextInputType? type,
          Widget? suffix,
          bool enabled = true}) =>
      SizedBox(
        width: _w,
        child: TextFormField(
          key: key,
          controller: c,
          enabled: enabled,
          keyboardType: type,
          validator: validator,
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: suffix,
              border: const OutlineInputBorder()),
        ),
      );

  Future<void> _scanIccid() async {
    final iccid = await scanIccid(context);
    if (iccid != null && mounted) setState(() => _iccid.text = iccid);
  }

  Widget _tagsEditor() {
    final all = normalizeTags([...tagPresets, ..._tags]);
    return SizedBox(
      width: _wide,
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in all)
              FilterChip(
                key: Key('form-tag-$t'),
                label: Text('#$t'),
                selected: _tags.contains(t),
                onSelected: (on) => setState(
                    () => on ? _tags = [..._tags, t] : _tags.remove(t)),
              ),
            SizedBox(
              width: 160,
              child: TextField(
                key: const Key('form-tag-new'),
                controller: _newTag,
                decoration: const InputDecoration(
                    hintText: '自定义标签，回车添加', isDense: true),
                onSubmitted: (v) => setState(() {
                  _tags = normalizeTags([..._tags, v]);
                  _newTag.clear();
                }),
              ),
            ),
          ]),
    );
  }

  Widget _offsetsEditor() => SizedBox(
        width: _wide,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in offsetPresets)
            FilterChip(
              key: Key('form-offset-$o'),
              label: Text(o == 0 ? '当天' : '提前 $o 天'),
              selected: _offsets.contains(o),
              onSelected: (on) => setState(() {
                if (on) {
                  _offsets = {..._offsets, o};
                } else if (_offsets.length > 1) {
                  _offsets = {..._offsets}..remove(o);
                }
              }),
            ),
        ]),
      );

  Future<void> _pickRegion() async {
    final r = await showRegionPicker(context);
    if (r != null && mounted) setState(() => _selectRegion(r));
  }

  Future<void> _pickCurrency() async {
    final c = await showCurrencyPicker(context);
    if (c != null && mounted) setState(() => _currency.text = c.code);
  }

  /// Carrier presets of the selected region; typing any other name works too.
  Widget _carrierChips() => ListenableBuilder(
        listenable: _country,
        builder: (context, _) {
          final r = regionFor(_country.text);
          if (r.carriers.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            width: _wide,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in r.carriers)
                ActionChip(
                  key: Key('carrier-chip-${c.name}'),
                  avatar: c.presetId.isEmpty
                      ? null
                      : Icon(Icons.rule, size: 16, color: context.hud.emerald),
                  label: Text(c.name),
                  tooltip: c.presetId.isEmpty ? null : '带保号规则',
                  onPressed: () => setState(() => _selectCarrier(c)),
                ),
            ]),
          );
        },
      );

  Widget _cycleChipsRow() => SizedBox(
        width: _wide,
        child: ListenableBuilder(
          listenable: _cycleDays,
          builder: (context, _) => Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in cycleChips)
              ChoiceChip(
                key: Key('cycle-chip-$d'),
                label: Text('$d 天'),
                selected: _cycleDays.text.trim() == '$d',
                onSelected: (_) => _cycleDays.text = '$d',
              ),
            ChoiceChip(
              key: const Key('cycle-chip-custom'),
              label: Text(
                  cycleChips.map((d) => '$d').contains(_cycleDays.text.trim())
                      ? '自定义'
                      : '自定义 · ${_cycleDays.text.trim()} 天'),
              selected:
                  !cycleChips.map((d) => '$d').contains(_cycleDays.text.trim()),
              onSelected: (_) {},
            ),
          ]),
        ),
      );

  Widget _dateButton(String label, DateTime? value, Key key,
          ValueChanged<DateTime?> onChanged) =>
      SizedBox(
        width: _w,
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: key,
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value ?? dateOnly(DateTime.now()),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => onChanged(dateOnly(picked)));
              },
              icon: const Icon(Icons.event),
              label: Text(value == null
                  ? label
                  : '$label ${DateFormat('yyyy-MM-dd').format(value)}'),
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: '清除',
              onPressed: () => setState(() => onChanged(null)),
              icon: const Icon(Icons.close),
            ),
        ]),
      );

  List<Widget> _dataPlanFields() {
    final sources = [
      if (_country.text.trim().toUpperCase() == 'CN' && _kind == CardKind.data)
        ...domesticDataSources,
      ...travelSources,
    ];
    return [
      _field(_source, '来源平台（可自定义）', key: const Key('field-source')),
      SizedBox(
        width: _wide,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final src in sources)
            ChoiceChip(
              key: Key('source-chip-$src'),
              label: Text(src),
              selected: _source.text.trim() == src,
              onSelected: (_) => setState(() => _source.text = src),
            ),
        ]),
      ),
      _field(_dataGb, '总流量 (GB)',
          key: const Key('field-data-gb'),
          enabled: !_unlimited,
          type: TextInputType.number,
          validator: _validateOptionalGb),
      SizedBox(
        width: _w,
        child: SwitchListTile(
          key: const Key('field-unlimited'),
          title: const Text('不限量'),
          value: _unlimited,
          onChanged: (v) => setState(() => _unlimited = v),
        ),
      ),
      _dateButton('激活日期', _planStart, const Key('field-plan-start'),
          (d) => _planStart = d),
      _field(_planDays, '套餐天数',
          key: const Key('field-plan-days'),
          type: TextInputType.number,
          validator: _validateOptionalDays),
      _dateButton(
          '或固定到期日', _planEnd, const Key('field-plan-end'), (d) => _planEnd = d),
    ];
  }

  Widget _dropdown<T>(String label, T value, List<T> values,
          String Function(T) text, ValueChanged<T> onChanged,
          {Key? key}) =>
      SizedBox(
        width: _w,
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

  double _pad(BuildContext context) => Hud.isCompact(context) ? 16 : 24;

  @override
  Widget build(BuildContext context) {
    _fitFields(MediaQuery.sizeOf(context).width - 2 * _pad(context));
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
      body: Shake(
        trigger: _shake,
        child: Form(
            key: _form,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_pad(context)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section('基础信息', [
                      _field(_carrier, '运营商 *',
                          key: const Key('field-carrier'),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '必填' : null),
                      _carrierChips(),
                      _field(_phone, '号码', key: const Key('field-phone')),
                      _field(_country, '国家/地区代码 (ISO-2，可自定义)',
                          key: const Key('field-country'),
                          suffix: ListenableBuilder(
                            listenable: _country,
                            builder: (context, _) => TextButton.icon(
                              key: const Key('pick-region'),
                              onPressed: _pickRegion,
                              icon: FlagText(_country.text.trim(), size: 18),
                              label: Text(regionName(_country.text.trim())),
                            ),
                          ),
                          validator: (v) => RegExp(r'^[A-Za-z]{2}$')
                                  .hasMatch((v ?? '').trim())
                              ? null
                              : '两位字母代码'),
                      _dropdown('用途类型', _kind, CardKind.values, (k) => k.label,
                          (k) {
                        _kind = k;
                        _syncRuleDefault();
                      }, key: const Key('field-kind')),
                      if (_kind == CardKind.other)
                        _field(_customKind, '类型名称（自定义）',
                            key: const Key('field-custom-kind')),
                      _dropdown('预付 / 上台', _planType, PlanType.values,
                          (t) => t == PlanType.postpaid ? '上台（合约）' : '预付', (t) {
                        _planType = t;
                        _syncRuleDefault();
                      }, key: const Key('field-plan-type')),
                      KeyedSubtree(
                        key: ValueKey(_media),
                        child: _dropdown('载体类型', _media, MediaType.values,
                            (m) => m.mediumLabel, (m) => _media = m,
                            key: const Key('field-media')),
                      ),
                      SizedBox(
                        width: _w,
                        child: SwitchListTile(
                          title: const Text('在线启用'),
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ),
                    ]),
                    if (_kind.hasDataPlan) section('流量套餐', _dataPlanFields()),
                    section('存放位置 / 载体槽位', [
                      _dropdown('存放位置', _location, LocationType.values,
                          (l) => l.label, (l) => _location = l),
                      KeyedSubtree(
                        key: ValueKey('medium-${_effectiveMediumId ?? ''}'),
                        child: _dropdown<String>(
                            '所在载体',
                            _effectiveMediumId ?? '',
                            [
                              '',
                              for (final m in widget.media) m.id,
                              if (_effectiveMediumId != null &&
                                  !widget.media
                                      .any((m) => m.id == _effectiveMediumId))
                                _effectiveMediumId!,
                            ],
                            (id) => id.isEmpty
                                ? '不占槽位（运营商实体卡）'
                                : () {
                                    final m = _mediumById(id);
                                    return m == null
                                        ? id
                                        : '${m.name} · ${m.capacity} 槽';
                                  }(), (id) {
                          _mediumId = id.isEmpty ? null : id;
                          final m = _mediumById(_mediumId);
                          if (m == null) {
                            if (_media == MediaType.programmable) {
                              _media = MediaType.physical;
                            }
                            if (_location == LocationType.smartCard) {
                              _location = LocationType.device;
                            }
                          } else {
                            _media = m.kind == MediumKind.builtinEsim
                                ? MediaType.esim
                                : MediaType.programmable;
                          }
                        }, key: const Key('field-medium')),
                      ),
                      _field(_host, '宿主设备'),
                      _field(_slotDetail, '槽位描述'),
                      _field(_estkSlot,
                          '${_mediumById(_effectiveMediumId)?.name ?? 'eSTK'} 槽位号 (1-$_capacity)',
                          key: const Key('field-estk-slot'),
                          enabled: _slotEnabled,
                          type: TextInputType.number,
                          validator: _validateSlot),
                      _field(_profileName, 'Profile 昵称 (如 工作号)',
                          key: const Key('field-profile-name'),
                          enabled: _slotEnabled),
                    ]),
                    section('资费', [
                      _field(_plan, '套餐名称'),
                      _field(_balance, '余额',
                          validator: _validateNumber,
                          type: TextInputType.number),
                      _field(_currency, '币种 (ISO 代码，可自定义)',
                          key: const Key('field-currency'),
                          suffix: ListenableBuilder(
                            listenable: _currency,
                            builder: (context, _) {
                              final c = currencyFor(_currency.text.trim());
                              return TextButton(
                                key: const Key('pick-currency'),
                                onPressed: _pickCurrency,
                                child: Text(
                                    c == null ? '选择' : '${c.symbol} ${c.name}'),
                              );
                            },
                          )),
                      _dropdown('计费周期', _billing, BillingCycle.values,
                          (b) => b.label, (b) => _billing = b),
                      _field(_cost, '周期费用',
                          key: const Key('field-cost'),
                          validator: _validateFee,
                          type: TextInputType.number),
                    ]),
                    section('保号规则', [
                      SizedBox(
                        width: _wide,
                        child: SwitchListTile(
                          key: const Key('field-ka-enabled'),
                          title: const Text('启用保号规则'),
                          subtitle: Text(_kaEnabled
                              ? '按规则计算死线，进入雷达、时间河与 ICS'
                              : '无保号规则：不进雷达与紧急度'
                                  '${_kind.hasDataPlan ? '，卡面倒计时显示套餐到期' : ''}'),
                          value: _kaEnabled,
                          onChanged: (v) => setState(() => _kaEnabled = v),
                        ),
                      ),
                      if (_kaEnabled) ...[
                        SizedBox(
                            width: _wide,
                            child: _dropdown<String>(
                                '运营商预设（自动带出规则，可改）',
                                _presetId,
                                ['', for (final p in carrierPresets) p.id],
                                (id) {
                              final p = presetById(id);
                              return p == null
                                  ? '自定义'
                                  : '${p.name} · ${p.cycleDays} 天 · ${p.type.label}';
                            }, _applyPreset, key: const Key('field-preset'))),
                        _dropdown('保号类型', _kaType, KeepAliveType.values,
                            (t) => t.label, (t) => _kaType = t,
                            key: const Key('field-ka-type')),
                        _dropdown('续期算法', _renewal, RenewalBasis.values,
                            (r) => r.label, (r) => _renewal = r,
                            key: const Key('field-renewal')),
                        _field(_cycleDays, '保号周期 (天)',
                            key: const Key('field-cycle'),
                            type: TextInputType.number,
                            validator: (v) =>
                                (int.tryParse((v ?? '').trim()) ?? 0) > 0
                                    ? null
                                    : '正整数'),
                        if (_kaType == KeepAliveType.validity) _cycleChipsRow(),
                        SizedBox(
                          width: _w,
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
                        SizedBox(width: _wide, child: _field(_action, '保号动作')),
                        SizedBox(
                            width: _wide,
                            child: _field(_rechargeUrl, '官方充值链接',
                                key: const Key('field-recharge-url'))),
                        SizedBox(
                          width: _wide,
                          child: ListenableBuilder(
                            listenable: Listenable.merge(
                                [_cost, _cycleDays, _currency]),
                            builder: (context, _) => Text(_annualPreview(),
                                key: const Key('annual-preview'),
                                style: Hud.mono.copyWith(
                                    fontSize: 12, color: context.hud.emerald)),
                          ),
                        ),
                      ],
                    ]),
                    section('提醒与标签', [
                      _offsetsEditor(),
                      _tagsEditor(),
                    ]),
                    section('卡背机密', [
                      _field(_iccid, 'ICCID',
                          key: const Key('field-iccid'),
                          suffix: IconButton(
                              key: const Key('scan-iccid'),
                              tooltip: '扫描卡托条码',
                              onPressed: _scanIccid,
                              icon: const Icon(Icons.qr_code_scanner))),
                      _field(_pin, 'PIN1'),
                      _field(_puk, 'PUK1'),
                      _field(_lpa, 'eSIM LPA 激活串'),
                      SizedBox(
                          width: _wide,
                          child: _field(_services, '绑定服务 (逗号分隔)')),
                      SizedBox(width: _wide, child: _field(_notes, '备注')),
                    ]),
                  ]),
            )),
      ),
    );
  }
}
