import 'dart:convert';

/// Storage medium of a card, matching the v3.2 reference `cardType`.
enum MediaType { physical, esim, programmable }

extension MediaTypeLabel on MediaType {
  String get label => switch (this) {
        MediaType.physical => '实体 SIM',
        MediaType.esim => 'eSIM',
        MediaType.programmable => '5ber·eSTK 写卡器',
      };

  String get wireName => switch (this) {
        MediaType.physical => 'Physical',
        MediaType.esim => 'eSIM',
        MediaType.programmable => 'Programmable_eSIM',
      };

  static MediaType parse(String? raw) => switch (raw) {
        'eSIM' || 'esim' => MediaType.esim,
        'Programmable_eSIM' || 'programmable' => MediaType.programmable,
        _ => MediaType.physical,
      };
}

/// Where the card physically lives.
enum LocationType { device, smartCard, drawer }

extension LocationTypeLabel on LocationType {
  String get label => switch (this) {
        LocationType.device => '手机卡槽',
        LocationType.smartCard => 'eSTK/5ber 写卡器',
        LocationType.drawer => '抽屉/卡包',
      };

  String get wireName => switch (this) {
        LocationType.device => 'Device',
        LocationType.smartCard => 'SmartCard',
        LocationType.drawer => 'Drawer',
      };

  static LocationType parse(String? raw) => switch (raw?.toLowerCase()) {
        'smartcard' => LocationType.smartCard,
        'drawer' || 'binder' => LocationType.drawer,
        _ => LocationType.device,
      };
}

enum BillingCycle { monthly, yearly, payGo }

extension BillingCycleLabel on BillingCycle {
  String get label => switch (this) {
        BillingCycle.monthly => '月付',
        BillingCycle.yearly => '年付',
        BillingCycle.payGo => '按量 PayGo',
      };

  String get wireName => switch (this) {
        BillingCycle.monthly => 'Monthly',
        BillingCycle.yearly => 'Yearly',
        BillingCycle.payGo => 'PayGo',
      };

  static BillingCycle parse(String? raw) => switch (raw?.toLowerCase()) {
        'yearly' => BillingCycle.yearly,
        'paygo' => BillingCycle.payGo,
        _ => BillingCycle.monthly,
      };
}

/// P1 ≤ 15 days, P2 ≤ 60 days, otherwise OK (same tiers as the reference).
enum UrgencyTier { p1, p2, ok }

extension UrgencyTierLabel on UrgencyTier {
  String get code => switch (this) {
        UrgencyTier.p1 => 'P1',
        UrgencyTier.p2 => 'P2',
        UrgencyTier.ok => 'OK',
      };

  String get label => switch (this) {
        UrgencyTier.p1 => 'P1 紧急',
        UrgencyTier.p2 => 'P2 关注',
        UrgencyTier.ok => 'OK 安全',
      };
}

UrgencyTier urgencyTierFor(int days) {
  if (days <= 15) return UrgencyTier.p1;
  if (days <= 60) return UrgencyTier.p2;
  return UrgencyTier.ok;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic that stays at local midnight across DST changes.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [now] to [deadline]; negative when overdue.
int remainingDays(DateTime deadline, {DateTime? now}) {
  final from = dateOnly(now ?? DateTime.now());
  final to = dateOnly(deadline);
  return (to.difference(from).inHours / 24).round();
}

const exchangeRatesToCny = <String, double>{
  'CNY': 1.0,
  'HKD': 0.92,
  'GBP': 9.15,
  'USD': 7.24,
  'JPY': 0.048,
  'EUR': 7.8,
  'AUD': 4.7,
  'SGD': 5.4,
};

class SimCard {
  const SimCard({
    required this.id,
    required this.carrierName,
    required this.phoneNumber,
    required this.countryCode,
    required this.mediaType,
    required this.nextDeadlineDate,
    this.locationType = LocationType.device,
    this.hostName = '',
    this.slotDetail = '',
    this.estkSlotNumber,
    this.isActive = true,
    this.planName = '',
    this.balance = 0,
    this.currency = 'CNY',
    this.billingCycle = BillingCycle.monthly,
    this.cycleCost = 0,
    this.keepAliveCycleDays = 180,
    this.keepAliveAction = '',
    this.lastKeepAliveDate,
    this.keepAliveLog = const [],
    this.iccid = '',
    this.pin1 = '',
    this.puk1 = '',
    this.esimLpaCode = '',
    this.boundServices = const [],
    this.notes = '',
  });

  final String id;
  final String carrierName;
  final String phoneNumber;
  final String countryCode;
  final MediaType mediaType;
  final LocationType locationType;
  final String hostName;
  final String slotDetail;

  /// 1..15 when the profile lives in an eSTK.me / 5ber programmable card.
  final int? estkSlotNumber;
  final bool isActive;
  final String planName;
  final double balance;
  final String currency;
  final BillingCycle billingCycle;
  final double cycleCost;
  final int keepAliveCycleDays;
  final String keepAliveAction;
  final DateTime? lastKeepAliveDate;
  final DateTime nextDeadlineDate;
  final List<DateTime> keepAliveLog;
  final String iccid;
  final String pin1;
  final String puk1;
  final String esimLpaCode;
  final List<String> boundServices;
  final String notes;

  /// Cards whose profile is hosted on a programmable eSTK/5ber medium.
  bool get onProgrammableMedium =>
      mediaType == MediaType.programmable ||
      locationType == LocationType.smartCard;

  int daysRemaining({DateTime? now}) =>
      remainingDays(nextDeadlineDate, now: now);

  UrgencyTier urgency({DateTime? now}) =>
      urgencyTierFor(daysRemaining(now: now));

  double get monthlyCny {
    final rate = exchangeRatesToCny[currency] ?? 1;
    return switch (billingCycle) {
      BillingCycle.monthly => cycleCost * rate,
      BillingCycle.yearly => cycleCost * rate / 12,
      BillingCycle.payGo => cycleCost > 0 ? cycleCost * rate / 6 : 0,
    };
  }

  /// Records a keep-alive action today and pushes the deadline one cycle out.
  SimCard checkIn({DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    return copyWith(
      lastKeepAliveDate: today,
      nextDeadlineDate: addDays(today, keepAliveCycleDays),
      keepAliveLog: [today, ...keepAliveLog].take(20).toList(),
    );
  }

  SimCard copyWith({
    String? id,
    String? carrierName,
    String? phoneNumber,
    String? countryCode,
    MediaType? mediaType,
    LocationType? locationType,
    String? hostName,
    String? slotDetail,
    int? Function()? estkSlotNumber,
    bool? isActive,
    String? planName,
    double? balance,
    String? currency,
    BillingCycle? billingCycle,
    double? cycleCost,
    int? keepAliveCycleDays,
    String? keepAliveAction,
    DateTime? lastKeepAliveDate,
    DateTime? nextDeadlineDate,
    List<DateTime>? keepAliveLog,
    String? iccid,
    String? pin1,
    String? puk1,
    String? esimLpaCode,
    List<String>? boundServices,
    String? notes,
  }) =>
      SimCard(
        id: id ?? this.id,
        carrierName: carrierName ?? this.carrierName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        countryCode: countryCode ?? this.countryCode,
        mediaType: mediaType ?? this.mediaType,
        locationType: locationType ?? this.locationType,
        hostName: hostName ?? this.hostName,
        slotDetail: slotDetail ?? this.slotDetail,
        estkSlotNumber:
            estkSlotNumber != null ? estkSlotNumber() : this.estkSlotNumber,
        isActive: isActive ?? this.isActive,
        planName: planName ?? this.planName,
        balance: balance ?? this.balance,
        currency: currency ?? this.currency,
        billingCycle: billingCycle ?? this.billingCycle,
        cycleCost: cycleCost ?? this.cycleCost,
        keepAliveCycleDays: keepAliveCycleDays ?? this.keepAliveCycleDays,
        keepAliveAction: keepAliveAction ?? this.keepAliveAction,
        lastKeepAliveDate: lastKeepAliveDate ?? this.lastKeepAliveDate,
        nextDeadlineDate: nextDeadlineDate ?? this.nextDeadlineDate,
        keepAliveLog: keepAliveLog ?? this.keepAliveLog,
        iccid: iccid ?? this.iccid,
        pin1: pin1 ?? this.pin1,
        puk1: puk1 ?? this.puk1,
        esimLpaCode: esimLpaCode ?? this.esimLpaCode,
        boundServices: boundServices ?? this.boundServices,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson({bool redactSecrets = false}) => {
        'id': id,
        'carrierName': carrierName,
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
        'cardType': mediaType.wireName,
        'locationType': locationType.wireName,
        'hostName': hostName,
        'slotDetail': slotDetail,
        'estkSlotNumber': estkSlotNumber,
        'isActive': isActive,
        'planName': planName,
        'balance': balance,
        'currency': currency,
        'billingCycle': billingCycle.wireName,
        'cycleCost': cycleCost,
        'keepAliveCycleDays': keepAliveCycleDays,
        'keepAliveAction': keepAliveAction,
        'lastKeepAliveDate':
            lastKeepAliveDate == null ? null : _ymd(lastKeepAliveDate!),
        'nextDeadlineDate': _ymd(nextDeadlineDate),
        'keepAliveLog': keepAliveLog.map(_ymd).toList(),
        'iccid': iccid,
        'pin1': redactSecrets ? '' : pin1,
        'puk1': redactSecrets ? '' : puk1,
        'esimLpaCode': redactSecrets ? '' : esimLpaCode,
        'boundServices': boundServices,
        'notes': notes,
      };

  factory SimCard.fromJson(Map<String, dynamic> json) {
    // Legacy v1 records track renewal and card expiry separately; the
    // keep-alive deadline is whichever comes first.
    final candidates = [
      _parseDate(json['nextDeadlineDate']),
      _parseDate(json['nextRenewalDate']),
      _parseDate(json['expiryDate']),
    ].whereType<DateTime>().toList()
      ..sort();
    if (candidates.isEmpty) {
      throw const FormatException('nextDeadlineDate 缺失');
    }
    final deadline = candidates.first;
    final legacyExpiry = _parseDate(json['expiryDate']);
    var notes = json['notes'] as String? ?? '';
    if (legacyExpiry != null && legacyExpiry != deadline) {
      final tag = '卡片有效期 ${_ymd(legacyExpiry)}';
      if (!notes.contains(tag)) notes = notes.isEmpty ? tag : '$notes\n$tag';
    }
    final savedCost = (json['cycleCost'] as num?)?.toDouble();
    final monthlyFee = (json['monthlyFee'] as num?)?.toDouble();
    // v1 editors saved cycleCost 0 by default next to the real monthlyFee.
    final cycleCost =
        (savedCost == null || savedCost == 0) && monthlyFee != null
            ? monthlyFee
            : savedCost ?? 0;
    return SimCard(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      carrierName: json['carrierName'] as String? ??
          json['operatorName'] as String? ??
          json['nickname'] as String? ??
          '未命名',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      countryCode: (json['countryCode'] as String? ?? 'CN').toUpperCase(),
      mediaType:
          MediaTypeLabel.parse(json['cardType'] as String? ?? json['type']),
      locationType: LocationTypeLabel.parse(json['locationType'] as String?),
      hostName: json['hostName'] as String? ?? '',
      slotDetail: json['slotDetail'] as String? ?? '',
      estkSlotNumber: (json['estkSlotNumber'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
      planName: json['planName'] as String? ?? '',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'CNY',
      billingCycle: BillingCycleLabel.parse(json['billingCycle'] as String?),
      cycleCost: cycleCost,
      keepAliveCycleDays: (json['keepAliveCycleDays'] as num?)?.toInt() ?? 180,
      keepAliveAction: json['keepAliveAction'] as String? ?? '',
      lastKeepAliveDate: _parseDate(json['lastKeepAliveDate']),
      nextDeadlineDate: deadline,
      keepAliveLog: (json['keepAliveLog'] as List? ?? const [])
          .map(_parseDate)
          .whereType<DateTime>()
          .toList(),
      iccid: json['iccid'] as String? ?? '',
      pin1: json['pin1'] as String? ?? '',
      puk1: json['puk1'] as String? ?? '',
      esimLpaCode: json['esimLpaCode'] as String? ?? '',
      boundServices: (json['boundServices'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      notes: notes,
    );
  }

  static String encodeList(List<SimCard> cards, {bool redactSecrets = false}) =>
      const JsonEncoder.withIndent('  ').convert(
          cards.map((c) => c.toJson(redactSecrets: redactSecrets)).toList());

  /// Accepts a bare array or `{ "cards": [...] }`.
  static List<SimCard> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map<String, dynamic> ? decoded['cards'] : decoded;
    if (list is! List) throw const FormatException('JSON 顶层必须是卡片数组');
    return list
        .map((e) => SimCard.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : dateOnly(parsed);
}
