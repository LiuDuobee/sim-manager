import 'dart:convert';
import 'dart:math' as math;

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

/// How a number is kept alive: by any billable activity inside the cycle
/// (giffgaff, povo) or by topping up before a validity date (Club SIM).
enum KeepAliveType { activity, validity }

extension KeepAliveTypeLabel on KeepAliveType {
  String get label => switch (this) {
        KeepAliveType.activity => '活跃度型',
        KeepAliveType.validity => '有效期型',
      };

  /// The action the radar asks for.
  String get verb => switch (this) {
        KeepAliveType.activity => '需活跃',
        KeepAliveType.validity => '需充值',
      };

  String get wireName => switch (this) {
        KeepAliveType.activity => 'Activity',
        KeepAliveType.validity => 'Validity',
      };

  static KeepAliveType parse(String? raw) => switch (raw?.toLowerCase()) {
        'validity' => KeepAliveType.validity,
        _ => KeepAliveType.activity,
      };
}

/// Where the next cycle starts after a keep-alive action.
enum RenewalBasis { fromAction, fromDeadline }

extension RenewalBasisLabel on RenewalBasis {
  String get label => switch (this) {
        RenewalBasis.fromAction => '按操作当天重算',
        RenewalBasis.fromDeadline => '按原到期日顺延',
      };

  String get wireName => switch (this) {
        RenewalBasis.fromAction => 'FromAction',
        RenewalBasis.fromDeadline => 'FromDeadline',
      };

  static RenewalBasis parse(String? raw) => switch (raw?.toLowerCase()) {
        'fromdeadline' => RenewalBasis.fromDeadline,
        _ => RenewalBasis.fromAction,
      };
}

/// Next deadline after a keep-alive action on [today]. "顺延" extends the
/// current deadline, but an already lapsed deadline restarts from today.
DateTime renewedDeadline({
  required RenewalBasis basis,
  required DateTime deadline,
  required DateTime today,
  required int cycleDays,
}) {
  final base = basis == RenewalBasis.fromDeadline && !deadline.isBefore(today)
      ? deadline
      : today;
  return addDays(base, cycleDays);
}

enum CardEventType { create, checkIn, topUp, edit, archive, restore }

extension CardEventTypeLabel on CardEventType {
  String get label => switch (this) {
        CardEventType.create => '建卡',
        CardEventType.checkIn => '活跃打卡',
        CardEventType.topUp => '充值续期',
        CardEventType.edit => '编辑',
        CardEventType.archive => '归档',
        CardEventType.restore => '恢复',
      };

  String get wireName => switch (this) {
        CardEventType.create => 'Create',
        CardEventType.checkIn => 'CheckIn',
        CardEventType.topUp => 'TopUp',
        CardEventType.edit => 'Edit',
        CardEventType.archive => 'Archive',
        CardEventType.restore => 'Restore',
      };

  static CardEventType? parse(String? raw) {
    for (final t in CardEventType.values) {
      if (t.wireName.toLowerCase() == raw?.toLowerCase()) return t;
    }
    return null;
  }
}

/// One entry of a card's renewal passport (续费护照).
class CardEvent {
  const CardEvent({
    required this.at,
    required this.type,
    this.amount,
    this.currency = '',
    this.deadline,
    this.note = '',
  });

  final DateTime at;
  final CardEventType type;

  /// Money spent on this action (top-ups), in [currency]. Never negative.
  final double? amount;
  final String currency;

  /// The deadline after this event, for check-ins / top-ups / edits.
  final DateTime? deadline;
  final String note;

  Map<String, dynamic> toJson() => {
        'at': _ymd(at),
        'type': type.wireName,
        if (amount != null) 'amount': amount,
        if (currency.isNotEmpty) 'currency': currency,
        if (deadline != null) 'deadline': _ymd(deadline!),
        if (note.isNotEmpty) 'note': note,
      };

  factory CardEvent.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('护照事件必须是 JSON 对象');
    final at = _parseDate(raw['at']);
    if (at == null) throw const FormatException('护照事件缺少日期 at');
    final type = CardEventTypeLabel.parse(raw['type'] as String?);
    if (type == null) throw FormatException('未知护照事件类型 ${raw['type']}');
    final amount = raw['amount'];
    if (amount != null && amount is! num) {
      throw const FormatException('护照事件金额 amount 必须是数字');
    }
    final error = feeError(amount as num?, '护照事件金额 amount ');
    if (error != null) throw FormatException(error);
    return CardEvent(
      at: at,
      type: type,
      amount: amount?.toDouble(),
      currency: raw['currency'] as String? ?? '',
      deadline: _parseDate(raw['deadline']),
      note: raw['note'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardEvent &&
      other.at == at &&
      other.type == type &&
      other.amount == amount &&
      other.currency == currency &&
      other.deadline == deadline &&
      other.note == note;

  @override
  int get hashCode => Object.hash(at, type, amount, currency, deadline, note);
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

/// Fee fields (cycle cost, legacy monthly fee) must be finite and ≥ 0.
/// Returns a user-facing error, or null when [value] is acceptable.
String? feeError(num? value, String label) {
  if (value == null) return null;
  if (!value.isFinite) return '$label必须是有限数字';
  if (value < 0) return '$label不能为负数（当前 $value）';
  return null;
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
  'THB': 0.2,
};

/// Sums each card's estimated yearly keep-alive cost per currency.
Map<String, double> annualCostByCurrency(Iterable<SimCard> cards) {
  final out = <String, double>{};
  for (final c in cards) {
    final cost = c.annualCost;
    if (cost <= 0) continue;
    out.update(c.currency, (v) => v + cost, ifAbsent: () => cost);
  }
  return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

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
    this.keepAliveType = KeepAliveType.activity,
    this.renewalBasis = RenewalBasis.fromAction,
    this.carrierPresetId = '',
    this.rechargeUrl = '',
    this.events = const [],
    this.archivedAt,
    this.tags = const [],
    this.reminderOffsets = defaultReminderOffsets,
    this.profileName = '',
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
  final KeepAliveType keepAliveType;
  final RenewalBasis renewalBasis;

  /// Id of the carrier preset the rules came from ('' = custom).
  final String carrierPresetId;
  final String rechargeUrl;

  /// Renewal passport, newest first.
  final List<CardEvent> events;

  /// Set while the card sits in the archive.
  final DateTime? archivedAt;

  /// Free-form labels such as 主力 / 备用 / 收藏.
  final List<String> tags;

  /// Days before the deadline to remind (0 = on the day), largest first.
  final List<int> reminderOffsets;

  /// Nickname of the eSTK slot profile this card occupies (e.g. 工作号).
  final String profileName;

  static const defaultReminderOffsets = [3];
  static const maxReminderOffset = 365;

  static const maxEvents = 100;

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
      // One payment per keep-alive cycle, spread over the months it covers.
      BillingCycle.payGo => annualCost * rate / 12,
    };
  }

  /// Estimated keep-alive cost per year in [currency]. Monthly / yearly
  /// plans use their price; PayGo pays [cycleCost] once per keep-alive cycle.
  double get annualCost => switch (billingCycle) {
        BillingCycle.monthly => cycleCost * 12,
        BillingCycle.yearly => cycleCost,
        BillingCycle.payGo => cycleCost * 365 / math.max(keepAliveCycleDays, 1),
      };

  double get annualCny => annualCost * (exchangeRatesToCny[currency] ?? 1);

  /// Records a top-up confirmed by the user (e.g. parsed from an SMS).
  /// [deadline] is the validity date the carrier reported; without it the
  /// card's renewal rule decides, as for a check-in.
  SimCard recordTopUp({double? amount, DateTime? deadline, DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final next = deadline != null
        ? dateOnly(deadline)
        : renewedDeadline(
            basis: renewalBasis,
            deadline: nextDeadlineDate,
            today: today,
            cycleDays: keepAliveCycleDays);
    return copyWith(
      lastKeepAliveDate: today,
      nextDeadlineDate: next,
      keepAliveLog: [today, ...keepAliveLog].take(20).toList(),
    ).withEvent(CardEvent(
      at: today,
      type: CardEventType.topUp,
      amount: amount,
      currency: amount == null ? '' : currency,
      deadline: next,
      note: '短信录入',
    ));
  }

  /// Prepends [event] to the passport.
  SimCard withEvent(CardEvent event) =>
      copyWith(events: [event, ...events].take(maxEvents).toList());

  /// Records a keep-alive action today and moves the deadline by the card's
  /// renewal rule. Validity cards log a top-up of one cycle's cost.
  SimCard checkIn({DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final next = renewedDeadline(
        basis: renewalBasis,
        deadline: nextDeadlineDate,
        today: today,
        cycleDays: keepAliveCycleDays);
    final topUp = keepAliveType == KeepAliveType.validity;
    return copyWith(
      lastKeepAliveDate: today,
      nextDeadlineDate: next,
      keepAliveLog: [today, ...keepAliveLog].take(20).toList(),
    ).withEvent(CardEvent(
      at: today,
      type: topUp ? CardEventType.topUp : CardEventType.checkIn,
      amount: topUp ? cycleCost : null,
      currency: topUp ? currency : '',
      deadline: next,
    ));
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
    KeepAliveType? keepAliveType,
    RenewalBasis? renewalBasis,
    String? carrierPresetId,
    String? rechargeUrl,
    List<CardEvent>? events,
    DateTime? Function()? archivedAt,
    List<String>? tags,
    List<int>? reminderOffsets,
    String? profileName,
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
        keepAliveType: keepAliveType ?? this.keepAliveType,
        renewalBasis: renewalBasis ?? this.renewalBasis,
        carrierPresetId: carrierPresetId ?? this.carrierPresetId,
        rechargeUrl: rechargeUrl ?? this.rechargeUrl,
        events: events ?? this.events,
        archivedAt: archivedAt != null ? archivedAt() : this.archivedAt,
        tags: tags ?? this.tags,
        reminderOffsets: reminderOffsets ?? this.reminderOffsets,
        profileName: profileName ?? this.profileName,
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
        'keepAliveType': keepAliveType.wireName,
        'renewalBasis': renewalBasis.wireName,
        'carrierPresetId': carrierPresetId,
        'rechargeUrl': rechargeUrl,
        'events': events.map((e) => e.toJson()).toList(),
        'archivedAt': archivedAt == null ? null : _ymd(archivedAt!),
        'tags': tags,
        'reminderOffsets': reminderOffsets,
        'profileName': profileName,
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
    for (final (key, label) in const [
      ('cycleCost', '周期费用 cycleCost '),
      ('monthlyFee', '月费 monthlyFee '),
    ]) {
      final raw = json[key];
      if (raw != null && raw is! num) throw FormatException('$label必须是数字');
      final error = feeError(raw as num?, label);
      if (error != null) throw FormatException(error);
    }
    final savedCost = (json['cycleCost'] as num?)?.toDouble();
    final monthlyFee = (json['monthlyFee'] as num?)?.toDouble();
    // v1 editors saved cycleCost 0 by default next to the real monthlyFee.
    final cycleCost =
        (savedCost == null || savedCost == 0) && monthlyFee != null
            ? monthlyFee
            : savedCost ?? 0;
    final keepAliveLog = (json['keepAliveLog'] as List? ?? const [])
        .map(_parseDate)
        .whereType<DateTime>()
        .toList();
    final rawEvents = json['events'];
    if (rawEvents != null && rawEvents is! List) {
      throw const FormatException('护照 events 必须是数组');
    }
    // Cards saved before the passport existed: their check-in log becomes
    // the first passport entries.
    final events = rawEvents == null
        ? [
            for (final d in keepAliveLog)
              CardEvent(at: d, type: CardEventType.checkIn)
          ]
        : [for (final e in rawEvents as List) CardEvent.fromJson(e)];
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
      keepAliveLog: keepAliveLog,
      iccid: json['iccid'] as String? ?? '',
      pin1: json['pin1'] as String? ?? '',
      puk1: json['puk1'] as String? ?? '',
      esimLpaCode: json['esimLpaCode'] as String? ?? '',
      boundServices: (json['boundServices'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      notes: notes,
      keepAliveType: KeepAliveTypeLabel.parse(json['keepAliveType'] as String?),
      renewalBasis: RenewalBasisLabel.parse(json['renewalBasis'] as String?),
      carrierPresetId: json['carrierPresetId'] as String? ?? '',
      rechargeUrl: json['rechargeUrl'] as String? ?? '',
      events: events,
      archivedAt: _parseDate(json['archivedAt']),
      tags: _parseTags(json['tags']),
      reminderOffsets: _parseOffsets(json['reminderOffsets']),
      profileName: json['profileName'] as String? ?? '',
    );
  }

  static List<String> _parseTags(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.any((t) => t is! String)) {
      throw const FormatException('标签 tags 必须是字符串数组');
    }
    return normalizeTags(raw.cast<String>());
  }

  static List<int> _parseOffsets(Object? raw) {
    if (raw == null) return defaultReminderOffsets;
    if (raw is! List) {
      throw const FormatException('提醒偏移 reminderOffsets 必须是数组');
    }
    final out = <int>[];
    for (final v in raw) {
      final error = reminderOffsetError(v);
      if (error != null) throw FormatException(error);
      out.add((v as num).toInt());
    }
    return normalizeOffsets(out);
  }

  static String encodeList(List<SimCard> cards, {bool redactSecrets = false}) =>
      const JsonEncoder.withIndent('  ').convert(
          cards.map((c) => c.toJson(redactSecrets: redactSecrets)).toList());

  /// Accepts a bare array or `{ "cards": [...] }`.
  static List<SimCard> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map<String, dynamic> ? decoded['cards'] : decoded;
    if (list is! List) throw const FormatException('JSON 顶层必须是卡片数组');
    return [
      for (var i = 0; i < list.length; i++)
        _indexed(i, () => SimCard.fromJson(_asMap(list[i], i))),
    ];
  }

  /// Like [decodeList] but keeps going past invalid records, returning them
  /// (raw) with their errors so callers can quarantine instead of dropping.
  static ({List<SimCard> cards, List<Object?> rejected, List<String> errors})
      decodeListPartial(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map<String, dynamic> ? decoded['cards'] : decoded;
    if (list is! List) throw const FormatException('JSON 顶层必须是卡片数组');
    final cards = <SimCard>[], rejected = <Object?>[], errors = <String>[];
    for (var i = 0; i < list.length; i++) {
      try {
        cards.add(_indexed(i, () => SimCard.fromJson(_asMap(list[i], i))));
      } on FormatException catch (e) {
        rejected.add(list[i]);
        errors.add(e.message);
      }
    }
    return (cards: cards, rejected: rejected, errors: errors);
  }

  static Map<String, dynamic> _asMap(Object? e, int i) => e is Map
      ? Map<String, dynamic>.from(e)
      : throw FormatException('第 ${i + 1} 张卡片不是 JSON 对象');

  /// Runs [decode] for record [i], prefixing any error with the record index.
  static SimCard _indexed(int i, SimCard Function() decode) {
    try {
      return decode();
    } on FormatException catch (e) {
      if (e.message.startsWith('第 ')) rethrow;
      throw FormatException('第 ${i + 1} 张卡片: ${e.message}');
    } on TypeError catch (e) {
      throw FormatException('第 ${i + 1} 张卡片字段类型错误: $e');
    }
  }
}

/// Null when [v] is a whole number of days in 0..[SimCard.maxReminderOffset].
String? reminderOffsetError(Object? v) {
  if (v is! num || !v.isFinite || v != v.roundToDouble()) {
    return '提醒偏移必须是整数天数';
  }
  if (v < 0) return '提醒偏移不能为负数';
  if (v > SimCard.maxReminderOffset) {
    return '提醒偏移不能超过 ${SimCard.maxReminderOffset} 天';
  }
  return null;
}

/// Unique offsets, largest (earliest reminder) first.
List<int> normalizeOffsets(Iterable<int> offsets) =>
    offsets.toSet().toList()..sort((a, b) => b.compareTo(a));

/// Trimmed, non-empty, unique tags in their original order.
List<String> normalizeTags(Iterable<String> tags) =>
    tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList();

/// Only the last four digits of [phone], for privacy mode.
String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  final tail =
      digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  return '尾号 $tail';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : dateOnly(parsed);
}
