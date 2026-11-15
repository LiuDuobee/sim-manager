import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/atlas_globe.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimManagerApp());
}

class SimManagerApp extends StatelessWidget {
  const SimManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIM 卡管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5CAEFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF07090E),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SimHomePage(),
    );
  }
}

enum SimType { physical, esim, programmable }

enum SimStatus { normal, renewing, expired }

enum LocationType { device, smartCard, binder }

enum BillingCycle { monthly, yearly, payGo }

class SimCard {
  const SimCard({
    required this.id,
    required this.nickname,
    required this.operatorName,
    required this.type,
    required this.planName,
    required this.monthlyFee,
    required this.renewalCycle,
    required this.nextRenewalDate,
    required this.expiryDate,
    this.phoneNumber = '',
    this.countryCode = 'CN',
    this.themeColor = 'ocean',
    this.locationType = LocationType.device,
    this.hostName = '',
    this.slotDetail = '',
    this.isActive = false,
    this.balance = 0,
    this.currency = 'CNY',
    this.billingCycle = BillingCycle.monthly,
    this.cycleCost = 0,
    this.cnyMonthlyEstimate = 0,
    this.keepAliveCycleDays = 180,
    this.keepAliveAction = '',
    this.lastKeepAliveDate,
    this.nextDeadlineDate,
    this.keepAliveLog = const [],
    this.iccid = '',
    this.pin1 = '',
    this.puk1 = '',
    this.esimLpaCode = '',
    this.boundServices = const [],
    this.notes = '',
  });

  final String id;
  final String nickname;
  final String phoneNumber;
  final String countryCode;
  final String themeColor;
  final LocationType locationType;
  final String hostName;
  final String slotDetail;
  final bool isActive;
  final double balance;
  final String currency;
  final BillingCycle billingCycle;
  final double cycleCost;
  final double cnyMonthlyEstimate;
  final int keepAliveCycleDays;
  final String keepAliveAction;
  final DateTime? lastKeepAliveDate;
  final DateTime? nextDeadlineDate;
  final List<String> keepAliveLog;
  final String iccid;
  final String pin1;
  final String puk1;
  final String esimLpaCode;
  final List<String> boundServices;
  final String operatorName;
  final SimType type;
  final String notes;
  final String planName;
  final double monthlyFee;
  final String renewalCycle;
  final DateTime nextRenewalDate;
  final DateTime expiryDate;

  SimStatus get status {
    final now = DateTime.now();
    final deadline = nextDeadlineDate ?? nextRenewalDate;
    if (expiryDate.isBefore(now) || deadline.isBefore(now)) {
      return SimStatus.expired;
    }
    if (deadline.difference(now).inDays <= 7) {
      return SimStatus.renewing;
    }
    return SimStatus.normal;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
        'themeColor': themeColor,
        'locationType': locationType.name,
        'hostName': hostName,
        'slotDetail': slotDetail,
        'isActive': isActive,
        'balance': balance,
        'currency': currency,
        'billingCycle': billingCycle.name,
        'cycleCost': cycleCost,
        'cnyMonthlyEstimate': cnyMonthlyEstimate,
        'keepAliveCycleDays': keepAliveCycleDays,
        'keepAliveAction': keepAliveAction,
        'lastKeepAliveDate': lastKeepAliveDate?.toIso8601String(),
        'nextDeadlineDate': nextDeadlineDate?.toIso8601String(),
        'keepAliveLog': keepAliveLog,
        'iccid': iccid,
        'pin1': pin1,
        'puk1': puk1,
        'esimLpaCode': esimLpaCode,
        'boundServices': boundServices,
        'operatorName': operatorName,
        'type': type.name,
        'notes': notes,
        'planName': planName,
        'monthlyFee': monthlyFee,
        'renewalCycle': renewalCycle,
        'nextRenewalDate': nextRenewalDate.toIso8601String(),
        'expiryDate': expiryDate.toIso8601String(),
      };

  factory SimCard.fromJson(Map<String, dynamic> json) => SimCard(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        phoneNumber: json['phoneNumber'] as String? ?? '',
        countryCode: (json['countryCode'] as String? ?? 'CN').toUpperCase(),
        themeColor: json['themeColor'] as String? ?? 'ocean',
        locationType: _locationType(json['locationType']),
        hostName: json['hostName'] as String? ?? '',
        slotDetail: json['slotDetail'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'CNY',
        billingCycle: _billingCycle(json['billingCycle']),
        cycleCost: (json['cycleCost'] as num?)?.toDouble() ??
            (json['monthlyFee'] as num?)?.toDouble() ??
            0,
        cnyMonthlyEstimate:
            (json['cnyMonthlyEstimate'] as num?)?.toDouble() ?? 0,
        keepAliveCycleDays: json['keepAliveCycleDays'] as int? ?? 180,
        keepAliveAction: json['keepAliveAction'] as String? ?? '',
        lastKeepAliveDate: _dateTime(json['lastKeepAliveDate']),
        nextDeadlineDate: _dateTime(json['nextDeadlineDate']),
        keepAliveLog:
            (json['keepAliveLog'] as List?)?.whereType<String>().toList() ??
                const [],
        iccid: json['iccid'] as String? ?? '',
        pin1: json['pin1'] as String? ?? '',
        puk1: json['puk1'] as String? ?? '',
        esimLpaCode: json['esimLpaCode'] as String? ?? '',
        boundServices:
            (json['boundServices'] as List?)?.whereType<String>().toList() ??
                const [],
        operatorName: json['operatorName'] as String,
        type: SimType.values.byName(json['type'] as String),
        notes: json['notes'] as String? ?? '',
        planName: json['planName'] as String,
        monthlyFee: (json['monthlyFee'] as num).toDouble(),
        renewalCycle: json['renewalCycle'] as String,
        nextRenewalDate: DateTime.parse(json['nextRenewalDate'] as String),
        expiryDate: DateTime.parse(json['expiryDate'] as String),
      );
}

LocationType _locationType(Object? value) => LocationType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => LocationType.device,
    );

BillingCycle _billingCycle(Object? value) => BillingCycle.values.firstWhere(
      (item) => item.name == value,
      orElse: () => BillingCycle.monthly,
    );

DateTime? _dateTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

class SimStorage {
  static const _key = 'sim_cards';

  Future<List<SimCard>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => SimCard.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<SimCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(cards.map((e) => e.toJson()).toList()));
  }
}

class SimHomePage extends StatefulWidget {
  const SimHomePage({super.key});

  @override
  State<SimHomePage> createState() => _SimHomePageState();
}

class _SimHomePageState extends State<SimHomePage> {
  final _storage = SimStorage();
  List<SimCard> _cards = [];
  bool _loading = true;
  String _filter = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await _storage.load();
    if (mounted) {
      setState(() =>
          _cards = cards..sort((a, b) => a.expiryDate.compareTo(b.expiryDate)));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([SimCard? card]) async {
    final result = await Navigator.of(context).push<SimCard>(
      MaterialPageRoute(builder: (_) => SimFormPage(initial: card)),
    );
    if (result == null) return;
    final next = [..._cards];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    await _storage.save(next);
    if (mounted) setState(() => _cards = next);
  }

  Future<void> _delete(SimCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除卡片？'),
        content: Text('确定删除“${card.nickname}”吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final next = _cards.where((item) => item.id != card.id).toList();
    await _storage.save(next);
    if (mounted) setState(() => _cards = next);
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => BackupPage(cards: _cards, onImport: _importCards)),
    );
  }

  Future<void> _importCards(List<SimCard> cards) async {
    await _storage.save(cards);
    if (mounted) setState(() => _cards = cards);
  }

  @override
  Widget build(BuildContext context) {
    final countryCodes =
        _cards.map((card) => card.countryCode).toSet().toList();
    final visibleCards = switch (_filter) {
      '即将续费' =>
        _cards.where((card) => card.status == SimStatus.renewing).toList(),
      '已过期' =>
        _cards.where((card) => card.status == SimStatus.expired).toList(),
      'eSIM' => _cards.where((card) => card.type != SimType.physical).toList(),
      _ => _cards,
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: const Color(0xFF07090E),
        titleSpacing: 18,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SIMVAULT',
                style:
                    TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4)),
            SizedBox(height: 3),
            Text('WORLD CARD ATLAS  ·  LOCAL-FIRST',
                style: TextStyle(
                    color: Color(0xFF6F8BA4), fontSize: 9, letterSpacing: 1.1)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 19),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: const Color(0x1B53D2B0),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x5553D2B0)),
            ),
            child: const Center(
              child: Text('LOCAL',
                  style: TextStyle(
                      color: Color(0xFF66E6C6),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
              onPressed: _settings,
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置')
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('添加 SIM 卡'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _EmptyState(onAdd: () => _edit())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sensors,
                            color: Color(0xFF64D9C3), size: 15),
                        const SizedBox(width: 6),
                        const Text('OMAPI READY',
                            style: TextStyle(
                                color: Color(0xFF6E9F9F),
                                fontSize: 10,
                                letterSpacing: 1.2)),
                        const Spacer(),
                        Text('${_cards.length} ACTIVE RECORDS',
                            style: const TextStyle(
                                color: Color(0xFF66819A),
                                fontSize: 9,
                                letterSpacing: 1)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 350,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B111B),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0x3A3F82B8)),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x441A70A2),
                              blurRadius: 28,
                              spreadRadius: -12)
                        ],
                      ),
                      child: Stack(
                        children: [
                          const Positioned(
                            left: 18,
                            top: 16,
                            child: Text(
                              'WORLD CARD ATLAS  /  LIVE TELEMETRY',
                              style: TextStyle(
                                color: Color(0xFF9AB4D0),
                                fontSize: 12,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Positioned(
                            right: 18,
                            top: 16,
                            child: Text('DRAG · ZOOM · TAP NODE',
                                style: TextStyle(
                                    color: Color(0xFF5C7890),
                                    fontSize: 9,
                                    letterSpacing: 1)),
                          ),
                          AtlasGlobe(
                            countryCodes: countryCodes,
                            onCountrySelected: (code) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已聚焦 $code 地区')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _MetricCard(label: '藏卡总数', value: '${_cards.length}'),
                        const SizedBox(width: 8),
                        _MetricCard(
                          label: '需关注',
                          value:
                              '${_cards.where((card) => card.status != SimStatus.normal).length}',
                          accent: const Color(0xFFFFB45C),
                        ),
                        const SizedBox(width: 8),
                        _MetricCard(
                          label: '地区',
                          value: '${countryCodes.length}',
                          accent: const Color(0xFF67D5C2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _RadarPanel(cards: _cards),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'MY COLLECTION',
                          style: TextStyle(
                            color: Color(0xFF9AB4D0),
                            fontSize: 12,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text('${visibleCards.length} / ${_cards.length}',
                            style: const TextStyle(
                                color: Color(0xFF66819A), fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: ['全部', '即将续费', '已过期', 'eSIM']
                          .map((item) => ChoiceChip(
                                label: Text(item),
                                selected: _filter == item,
                                onSelected: (_) =>
                                    setState(() => _filter = item),
                                labelStyle: TextStyle(
                                    color: _filter == item
                                        ? const Color(0xFF07111A)
                                        : const Color(0xFF86A5BC),
                                    fontSize: 11),
                                selectedColor: const Color(0xFF8FD8FF),
                                backgroundColor: const Color(0xFF101A26),
                                side:
                                    const BorderSide(color: Color(0x334A789B)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    if (visibleCards.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('当前筛选没有匹配的卡片',
                                style: TextStyle(color: Color(0xFF718CA5)))),
                      ),
                    ...visibleCards.map((card) => _SimCardTile(
                        card: card,
                        onEdit: () => _edit(card),
                        onDelete: () => _delete(card))),
                  ],
                ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.accent = const Color(0xFF7AB8FF),
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D141F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1F8DB7DE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF8A9DB4), fontSize: 11)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPanel extends StatelessWidget {
  const _RadarPanel({required this.cards});

  final List<SimCard> cards;

  @override
  Widget build(BuildContext context) {
    final urgent = cards
        .where((card) => card.status != SimStatus.normal)
        .toList()
      ..sort((a, b) => a.nextRenewalDate.compareTo(b.nextRenewalDate));
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0B121C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x334A789B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Color(0xFFFFB45C), size: 18),
              const SizedBox(width: 8),
              const Text('KEEP-ALIVE RADAR',
                  style: TextStyle(
                      color: Color(0xFFF0C889),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const Spacer(),
              Text('${urgent.length} ALERTS',
                  style: const TextStyle(
                      color: Color(0xFFB78865), fontSize: 9, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          if (urgent.isEmpty)
            const Text('所有卡片都在安全窗口内',
                style: TextStyle(color: Color(0xFF718CA5), fontSize: 12))
          else
            ...urgent.take(3).map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: card.status == SimStatus.expired
                                    ? const Color(0xFFFF6378)
                                    : const Color(0xFFFFB45C))),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(card.nickname,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFFB9C9D8), fontSize: 12)),
                        ),
                        Text(
                            card.status == SimStatus.expired
                                ? 'EXPIRED'
                                : 'RENEW ${_date(card.nextRenewalDate)}',
                            style: TextStyle(
                                color: card.status == SimStatus.expired
                                    ? const Color(0xFFFF6378)
                                    : const Color(0xFFFFB45C),
                                fontSize: 9,
                                letterSpacing: .5)),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sim_card_outlined,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('还没有 SIM 卡',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('添加你的第一张实体 SIM 或 eSIM，开始管理套餐和到期日期。',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('添加 SIM 卡')),
            ],
          ),
        ),
      );
}

class _SimCardTile extends StatelessWidget {
  const _SimCardTile(
      {required this.card, required this.onEdit, required this.onDelete});
  final SimCard card;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = switch (card.status) {
      SimStatus.normal => ('正常', Colors.green),
      SimStatus.renewing => ('即将续费', Colors.orange),
      SimStatus.expired => ('已过期', Colors.red),
    };
    return Card(
      color: const Color(0xFF0D141F),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: const BorderSide(color: Color(0x2F4A789B))),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: const Color(0xFF17334A),
                  child: Icon(
                      card.type == SimType.esim
                          ? Icons.contactless
                          : Icons.sim_card,
                      color: const Color(0xFF8FD8FF))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(card.nickname,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(
                        '${card.operatorName} · ${switch (card.type) {
                          SimType.physical => '实体 SIM',
                          SimType.esim => 'eSIM',
                          SimType.programmable => '可编程 eSIM',
                        }} · ${card.countryCode}',
                        style: const TextStyle(
                            color: Color(0xFF7892A8), fontSize: 12)),
                  ])),
              PopupMenuButton<String>(
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ]),
            const Divider(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                  side: BorderSide.none,
                  backgroundColor: status.$2.withOpacity(.14),
                  label: Text(status.$1),
                  avatar: Icon(Icons.circle, size: 10, color: status.$2)),
              Chip(
                  side: BorderSide.none,
                  backgroundColor: const Color(0xFF162333),
                  label: Text(card.planName)),
              Chip(
                  side: BorderSide.none,
                  backgroundColor: const Color(0xFF162333),
                  label: Text(
                      '¥${card.monthlyFee.toStringAsFixed(2)}/${card.renewalCycle}')),
            ]),
            const SizedBox(height: 8),
            Text(
                '下次续费：${_date(card.nextRenewalDate)}    到期：${_date(card.expiryDate)}'),
            if (card.phoneNumber.isNotEmpty) Text('手机号：${card.phoneNumber}'),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) => DateFormat('yyyy年M月d日').format(value);

class SimFormPage extends StatefulWidget {
  const SimFormPage({super.key, this.initial});
  final SimCard? initial;

  @override
  State<SimFormPage> createState() => _SimFormPageState();
}

class _SimFormPageState extends State<SimFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _phone;
  late final TextEditingController _countryCode;
  late final TextEditingController _operator;
  late final TextEditingController _notes;
  late final TextEditingController _plan;
  late final TextEditingController _fee;
  SimType _type = SimType.physical;
  String _cycle = '月';
  late DateTime _renewal;
  late DateTime _expiry;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _nickname = TextEditingController(text: c?.nickname ?? '');
    _phone = TextEditingController(text: c?.phoneNumber ?? '');
    _countryCode = TextEditingController(text: c?.countryCode ?? 'CN');
    _operator = TextEditingController(text: c?.operatorName ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _plan = TextEditingController(text: c?.planName ?? '');
    _fee =
        TextEditingController(text: c == null ? '' : c.monthlyFee.toString());
    _type = c?.type ?? SimType.physical;
    _cycle = c?.renewalCycle ?? '月';
    _renewal =
        c?.nextRenewalDate ?? DateTime.now().add(const Duration(days: 30));
    _expiry = c?.expiryDate ?? DateTime.now().add(const Duration(days: 365));
  }

  @override
  void dispose() {
    for (final controller in [
      _nickname,
      _phone,
      _countryCode,
      _operator,
      _notes,
      _plan,
      _fee
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool renewal) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: renewal ? _renewal : _expiry,
    );
    if (picked == null) return;
    setState(() => renewal ? _renewal = picked : _expiry = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final fee = double.tryParse(_fee.text.trim());
    if (fee == null || fee < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入有效月费')));
      return;
    }
    if (_expiry.isBefore(_renewal)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('到期日期不能早于下次续费日期')));
      return;
    }
    Navigator.pop(
      context,
      SimCard(
        id: widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        nickname: _nickname.text.trim(),
        phoneNumber: _phone.text.trim(),
        countryCode: _countryCode.text.trim().toUpperCase(),
        operatorName: _operator.text.trim(),
        type: _type,
        notes: _notes.text.trim(),
        planName: _plan.text.trim(),
        monthlyFee: fee,
        renewalCycle: _cycle,
        nextRenewalDate: _renewal,
        expiryDate: _expiry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.initial == null ? '添加 SIM 卡' : '编辑 SIM 卡')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('基本资料', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _nickname,
                  decoration: const InputDecoration(labelText: '昵称 *'),
                  validator: _required),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '手机号（可选）')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _countryCode,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 2,
                  decoration: const InputDecoration(labelText: '国家代码（如 CN）'),
                  validator: (value) =>
                      value == null || value.trim().length != 2
                          ? '请输入 2 位国家代码'
                          : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _operator,
                  decoration: const InputDecoration(labelText: '运营商 *'),
                  validator: _required),
              const SizedBox(height: 12),
              DropdownButtonFormField<SimType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: '卡类型'),
                items: const [
                  DropdownMenuItem(
                      value: SimType.physical, child: Text('实体 SIM')),
                  DropdownMenuItem(value: SimType.esim, child: Text('eSIM')),
                  DropdownMenuItem(
                      value: SimType.programmable, child: Text('可编程 eSIM')),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '备注')),
              const SizedBox(height: 24),
              Text('套餐信息', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _plan,
                  decoration: const InputDecoration(labelText: '套餐名称 *'),
                  validator: _required),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _fee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: '月费 *', prefixText: '¥ '),
                  validator: _required),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _cycle,
                decoration: const InputDecoration(labelText: '续费周期'),
                items: const ['月', '季度', '半年', '年']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) => setState(() => _cycle = value!),
              ),
              const SizedBox(height: 12),
              _DateField(
                  label: '下次续费日期',
                  date: _renewal,
                  onTap: () => _pickDate(true)),
              const SizedBox(height: 12),
              _DateField(
                  label: '到期日期', date: _expiry, onTap: () => _pickDate(false)),
              const SizedBox(height: 28),
              FilledButton(onPressed: _save, child: const Text('保存')),
            ],
          ),
        ),
      );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '请填写此字段' : null;

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.calendar_today_outlined)),
          child: Text(_date(date)),
        ),
      );
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.cards, required this.onImport});
  final List<SimCard> cards;
  final Future<void> Function(List<SimCard>) onImport;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final TextEditingController _json;

  @override
  void initState() {
    super.initState();
    _json = TextEditingController(
        text: const JsonEncoder.withIndent('  ')
            .convert(widget.cards.map((e) => e.toJson()).toList()));
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final list = (jsonDecode(_json.text) as List)
          .map((item) => SimCard.fromJson(item as Map<String, dynamic>))
          .toList();
      await widget.onImport(list);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导入成功')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('JSON 格式无效，请检查备份内容')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置与备份')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('JSON 备份', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('复制下方内容保存到安全位置；导入时粘贴完整 JSON 后点击“导入”。'),
            const SizedBox(height: 12),
            TextField(
                controller: _json,
                minLines: 14,
                maxLines: 24,
                decoration:
                    const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.download),
                label: const Text('导入 JSON')),
          ],
        ),
      );
}
