import '../models/sim_card.dart';

/// Built-in keep-alive rules for common carriers. Values are editable
/// starting points (cycle, cost and top-up page as published by each carrier
/// at the time of writing); always check the carrier's current terms.
class CarrierPreset {
  const CarrierPreset({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.type,
    required this.renewal,
    required this.cycleDays,
    required this.currency,
    required this.cycleCost,
    required this.billingCycle,
    required this.action,
    required this.rechargeUrl,
  });

  final String id;
  final String name;
  final String countryCode;
  final KeepAliveType type;
  final RenewalBasis renewal;
  final int cycleDays;
  final String currency;
  final double cycleCost;
  final BillingCycle billingCycle;
  final String action;
  final String rechargeUrl;

  /// Same formula as [SimCard.annualCost].
  double get annualCost => SimCard(
        id: '',
        carrierName: name,
        phoneNumber: '',
        countryCode: countryCode,
        mediaType: MediaType.physical,
        nextDeadlineDate: DateTime(2000),
        currency: currency,
        cycleCost: cycleCost,
        billingCycle: billingCycle,
        keepAliveCycleDays: cycleDays,
      ).annualCost;

  /// Applies the preset's rules to [card], keeping identity and history.
  SimCard applyTo(SimCard card) => card.copyWith(
        carrierPresetId: id,
        keepAliveType: type,
        renewalBasis: renewal,
        keepAliveCycleDays: cycleDays,
        currency: currency,
        cycleCost: cycleCost,
        billingCycle: billingCycle,
        keepAliveAction: action,
        rechargeUrl: rechargeUrl,
      );
}

const carrierPresets = <CarrierPreset>[
  CarrierPreset(
    id: 'giffgaff',
    name: 'giffgaff UK',
    countryCode: 'GB',
    type: KeepAliveType.activity,
    renewal: RenewalBasis.fromAction,
    cycleDays: 180,
    currency: 'GBP',
    cycleCost: 0.3,
    billingCycle: BillingCycle.payGo,
    action: '每 180 天内一次计费活动（发 1 条短信 £0.30 / 通话 / 充值）',
    rechargeUrl: 'https://www.giffgaff.com/top-up',
  ),
  CarrierPreset(
    id: 'club-sim',
    name: 'Club SIM (CSL)',
    countryCode: 'HK',
    type: KeepAliveType.validity,
    renewal: RenewalBasis.fromDeadline,
    cycleDays: 365,
    currency: 'HKD',
    cycleCost: 6,
    billingCycle: BillingCycle.yearly,
    action: '到期前充值 / 购买年度通行证，有效期顺延 365 天',
    rechargeUrl: 'https://www.hkcsl.com/',
  ),
  CarrierPreset(
    id: 'povo2',
    name: 'povo 2.0',
    countryCode: 'JP',
    type: KeepAliveType.activity,
    renewal: RenewalBasis.fromAction,
    cycleDays: 180,
    currency: 'JPY',
    cycleCost: 220,
    billingCycle: BillingCycle.payGo,
    action: '180 天内购买一次付费 Topping（或产生通话/短信计费）',
    rechargeUrl: 'https://povo.jp/',
  ),
  CarrierPreset(
    id: 'tmobile-paygo',
    name: 'T-Mobile PayGo',
    countryCode: 'US',
    type: KeepAliveType.validity,
    renewal: RenewalBasis.fromAction,
    cycleDays: 30,
    currency: 'USD',
    cycleCost: 3,
    billingCycle: BillingCycle.monthly,
    action: r'每 30 天扣 $3 月租，保持余额充足',
    rechargeUrl: 'https://www.t-mobile.com/',
  ),
  CarrierPreset(
    id: 'vodafone-uk',
    name: 'Vodafone UK PAYG',
    countryCode: 'GB',
    type: KeepAliveType.activity,
    renewal: RenewalBasis.fromAction,
    cycleDays: 180,
    currency: 'GBP',
    cycleCost: 0.3,
    billingCycle: BillingCycle.payGo,
    action: '周期内一次计费活动（短信 / 通话 / 充值）',
    rechargeUrl: 'https://www.vodafone.co.uk/',
  ),
  CarrierPreset(
    id: 'ais',
    name: 'AIS 1-2-Call',
    countryCode: 'TH',
    type: KeepAliveType.validity,
    renewal: RenewalBasis.fromDeadline,
    cycleDays: 30,
    currency: 'THB',
    cycleCost: 10,
    billingCycle: BillingCycle.payGo,
    action: '到期前充值延长有效期（金额对应天数以官方为准）',
    rechargeUrl: 'https://www.ais.th/',
  ),
  CarrierPreset(
    id: 'cmcc',
    name: '中国移动 CMCC',
    countryCode: 'CN',
    type: KeepAliveType.validity,
    renewal: RenewalBasis.fromAction,
    cycleDays: 30,
    currency: 'CNY',
    cycleCost: 8,
    billingCycle: BillingCycle.monthly,
    action: '月租自动扣费，保持余额不欠费',
    rechargeUrl: 'https://www.10086.cn/',
  ),
];

CarrierPreset? presetById(String id) {
  for (final p in carrierPresets) {
    if (p.id == id) return p;
  }
  return null;
}
