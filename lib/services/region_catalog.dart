import 'package:flutter/painting.dart';

import '../features/globe/country_codes.dart';

/// A carrier offered in a region; [presetId] links it to the keep-alive rule
/// library in carrier_presets.dart.
class RegionCarrier {
  const RegionCarrier(this.name, [this.presetId = '']);

  final String name;
  final String presetId;
}

/// One entry of the region picker: ISO-2 code, display name, default
/// currency, flag main colour and the carriers offered there.
class RegionInfo {
  const RegionInfo({
    required this.code,
    required this.name,
    required this.currency,
    required this.flagColor,
    this.carriers = const [],
  });

  final String code;
  final String name;
  final String currency;

  /// Main colour of the region's flag, used for the card's accent stripe.
  final Color flagColor;
  final List<RegionCarrier> carriers;

  String get flag => flagEmoji(code);
}

const _red = Color(0xFFDE2910);

/// 中国 and its four regions, always listed first. 台湾 is a region of
/// China and only ever appears here, under the Chinese flag.
const chinaRegions = <RegionInfo>[
  RegionInfo(
      code: 'CN',
      name: '中国大陆',
      currency: 'CNY',
      flagColor: _red,
      carriers: [
        RegionCarrier('中国移动', 'cmcc'),
        RegionCarrier('中国联通'),
        RegionCarrier('中国电信'),
        RegionCarrier('中国广电'),
      ]),
  RegionInfo(
      code: 'HK',
      name: '中国香港',
      currency: 'HKD',
      flagColor: _red,
      carriers: [
        RegionCarrier('csl'),
        RegionCarrier('3HK'),
        RegionCarrier('SmarTone'),
        RegionCarrier('中国移动香港'),
        RegionCarrier('Club SIM', 'club-sim'),
        RegionCarrier('SoSIM'),
        RegionCarrier('birdie'),
      ]),
  RegionInfo(
      code: 'MO',
      name: '中国澳门',
      currency: 'MOP',
      flagColor: Color(0xFF00785E),
      carriers: [
        RegionCarrier('CTM'),
        RegionCarrier('3澳门'),
        RegionCarrier('中国电信澳门'),
      ]),
  RegionInfo(
      code: 'TW',
      name: '中国台湾',
      currency: 'TWD',
      flagColor: _red,
      carriers: [
        RegionCarrier('中华电信'),
        RegionCarrier('远传'),
        RegionCarrier('台湾大哥大'),
      ]),
];

/// Frequently used countries, listed after China in this order.
const popularRegions = <RegionInfo>[
  RegionInfo(
      code: 'GB',
      name: '英国',
      currency: 'GBP',
      flagColor: Color(0xFF012169),
      carriers: [
        RegionCarrier('giffgaff', 'giffgaff'),
        RegionCarrier('EE'),
        RegionCarrier('Vodafone', 'vodafone-uk'),
        RegionCarrier('O2'),
        RegionCarrier('Three'),
        RegionCarrier('VOXI'),
        RegionCarrier('Lebara'),
      ]),
  RegionInfo(
      code: 'US',
      name: '美国',
      currency: 'USD',
      flagColor: Color(0xFFB22234),
      carriers: [
        RegionCarrier('T-Mobile', 'tmobile-paygo'),
        RegionCarrier('AT&T'),
        RegionCarrier('Verizon'),
        RegionCarrier('Ultra Mobile'),
        RegionCarrier('Google Fi'),
        RegionCarrier('Mint'),
        RegionCarrier('Tello'),
      ]),
  RegionInfo(
      code: 'JP',
      name: '日本',
      currency: 'JPY',
      flagColor: Color(0xFFBC002D),
      carriers: [
        RegionCarrier('povo', 'povo2'),
        RegionCarrier('楽天'),
        RegionCarrier('ahamo'),
        RegionCarrier('LINEMO'),
        RegionCarrier('IIJmio'),
        RegionCarrier('docomo'),
        RegionCarrier('au'),
        RegionCarrier('SoftBank'),
      ]),
  RegionInfo(
      code: 'SG',
      name: '新加坡',
      currency: 'SGD',
      flagColor: Color(0xFFEF3340),
      carriers: [
        RegionCarrier('Singtel'),
        RegionCarrier('StarHub'),
        RegionCarrier('M1'),
        RegionCarrier('SIMBA'),
      ]),
  RegionInfo(
      code: 'TH',
      name: '泰国',
      currency: 'THB',
      flagColor: Color(0xFF2D2A4A),
      carriers: [
        RegionCarrier('AIS', 'ais'),
      ]),
  RegionInfo(
      code: 'KR', name: '韩国', currency: 'KRW', flagColor: Color(0xFFCD2E3A)),
  RegionInfo(
      code: 'MY', name: '马来西亚', currency: 'MYR', flagColor: Color(0xFF010066)),
];

const _currencyByCountry = <String, String>{
  'DE': 'EUR',
  'FR': 'EUR',
  'IT': 'EUR',
  'ES': 'EUR',
  'NL': 'EUR',
  'IE': 'EUR',
  'PT': 'EUR',
  'FI': 'EUR',
  'AU': 'AUD',
  'CA': 'CAD',
  'NZ': 'NZD',
  'CH': 'CHF',
  'IN': 'INR',
  'VN': 'VND',
  'ID': 'IDR',
  'PH': 'PHP',
  'AE': 'AED',
  'RU': 'RUB',
  'TR': 'TRY',
  'BR': 'BRL',
  'MX': 'MXN',
  'SE': 'SEK',
  'NO': 'NOK',
  'PL': 'PLN',
  'ZA': 'ZAR',
  'SA': 'SAR',
  'EG': 'EGP',
  'AR': 'ARS',
  'UA': 'UAH',
  'KZ': 'KZT',
  'MN': 'MNT',
};

const _flagColorByCountry = <String, Color>{
  'DE': Color(0xFFDD0000),
  'FR': Color(0xFF002395),
  'IT': Color(0xFF009246),
  'ES': Color(0xFFAA151B),
  'NL': Color(0xFF21468B),
  'IE': Color(0xFF169B62),
  'PT': Color(0xFF006600),
  'FI': Color(0xFF002F6C),
  'AU': Color(0xFF012169),
  'CA': Color(0xFFD80621),
  'NZ': Color(0xFF012169),
  'CH': Color(0xFFDA291C),
  'IN': Color(0xFFFF9933),
  'VN': Color(0xFFDA251D),
  'ID': Color(0xFFCE1126),
  'PH': Color(0xFF0038A8),
  'AE': Color(0xFF00732F),
  'RU': Color(0xFF0039A6),
  'TR': Color(0xFFE30A17),
  'BR': Color(0xFF009C3B),
  'MX': Color(0xFF006847),
  'SE': Color(0xFF006AA7),
  'NO': Color(0xFFBA0C2F),
  'PL': Color(0xFFDC143C),
  'ZA': Color(0xFF007749),
  'SA': Color(0xFF006C35),
  'EG': Color(0xFFCE1126),
  'AR': Color(0xFF74ACDF),
  'UA': Color(0xFF0057B7),
  'KZ': Color(0xFF00AFCA),
  'MN': Color(0xFFC4272F),
};

const _fallbackFlagColor = Color(0xFF14B8A6);

/// Every other known country, sorted by ISO code (A–Z).
final List<RegionInfo> otherRegions = () {
  final listed = {
    for (final r in [...chinaRegions, ...popularRegions]) r.code
  };
  final codes = countryNamesZh.keys.where((c) => !listed.contains(c)).toList()
    ..sort();
  return [
    for (final c in codes)
      RegionInfo(
        code: c,
        name: countryNamesZh[c]!,
        currency: _currencyByCountry[c] ?? 'USD',
        flagColor: _flagColorByCountry[c] ?? _fallbackFlagColor,
      ),
  ];
}();

/// China's regions, then popular countries, then the rest A–Z.
final List<RegionInfo> allRegions = [
  ...chinaRegions,
  ...popularRegions,
  ...otherRegions,
];

/// The catalog entry for [code]; unknown (custom) codes get a neutral entry.
RegionInfo regionFor(String code) {
  final c = code.toUpperCase();
  for (final r in allRegions) {
    if (r.code == c) return r;
  }
  return RegionInfo(
      code: c, name: c, currency: 'USD', flagColor: _fallbackFlagColor);
}

/// Display name for a card's region (e.g. 中国香港), falling back to the code.
String regionName(String code) => regionFor(code).name;

/// Flag emoji for an ISO-2 code. 台湾 (TW) shows the Chinese flag.
String flagEmoji(String code) {
  final c = code.toUpperCase();
  if (c == 'TW') return flagEmoji('CN');
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🏳';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 0x41));
}

/// Regions matching [query] by name or code, keeping catalog order.
List<RegionInfo> searchRegions(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return allRegions;
  return [
    for (final r in allRegions)
      if (r.name.toLowerCase().contains(q) ||
          r.code.toLowerCase().contains(q) ||
          (r.code == 'CN' || chinaRegions.any((c) => c.code == r.code)) &&
              '中国china'.contains(q))
        r
  ];
}

/// An ISO 4217 currency for the currency picker.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name);

  final String code;
  final String symbol;
  final String name;
}

const currencies = <CurrencyInfo>[
  CurrencyInfo('CNY', '¥', '人民币'),
  CurrencyInfo('HKD', 'HK\$', '港币'),
  CurrencyInfo('MOP', 'MOP\$', '澳门元'),
  CurrencyInfo('TWD', 'NT\$', '新台币'),
  CurrencyInfo('USD', '\$', '美元'),
  CurrencyInfo('GBP', '£', '英镑'),
  CurrencyInfo('EUR', '€', '欧元'),
  CurrencyInfo('JPY', 'JP¥', '日元'),
  CurrencyInfo('KRW', '₩', '韩元'),
  CurrencyInfo('SGD', 'S\$', '新加坡元'),
  CurrencyInfo('THB', '฿', '泰铢'),
  CurrencyInfo('MYR', 'RM', '马来西亚林吉特'),
  CurrencyInfo('AUD', 'A\$', '澳元'),
  CurrencyInfo('CAD', 'C\$', '加元'),
  CurrencyInfo('NZD', 'NZ\$', '新西兰元'),
  CurrencyInfo('CHF', 'CHF', '瑞士法郎'),
  CurrencyInfo('INR', '₹', '印度卢比'),
  CurrencyInfo('VND', '₫', '越南盾'),
  CurrencyInfo('IDR', 'Rp', '印尼盾'),
  CurrencyInfo('PHP', '₱', '菲律宾比索'),
  CurrencyInfo('AED', 'AED', '阿联酋迪拉姆'),
  CurrencyInfo('SAR', 'SAR', '沙特里亚尔'),
  CurrencyInfo('RUB', '₽', '俄罗斯卢布'),
  CurrencyInfo('TRY', '₺', '土耳其里拉'),
  CurrencyInfo('BRL', 'R\$', '巴西雷亚尔'),
  CurrencyInfo('MXN', 'MX\$', '墨西哥比索'),
  CurrencyInfo('ARS', 'AR\$', '阿根廷比索'),
  CurrencyInfo('SEK', 'kr', '瑞典克朗'),
  CurrencyInfo('NOK', 'kr', '挪威克朗'),
  CurrencyInfo('PLN', 'zł', '波兰兹罗提'),
  CurrencyInfo('UAH', '₴', '乌克兰格里夫纳'),
  CurrencyInfo('ZAR', 'R', '南非兰特'),
  CurrencyInfo('EGP', 'E£', '埃及镑'),
  CurrencyInfo('KZT', '₸', '哈萨克斯坦坚戈'),
  CurrencyInfo('MNT', '₮', '蒙古图格里克'),
];

CurrencyInfo? currencyFor(String code) {
  final c = code.toUpperCase();
  for (final x in currencies) {
    if (x.code == c) return x;
  }
  return null;
}

List<CurrencyInfo> searchCurrencies(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return currencies;
  return [
    for (final c in currencies)
      if (c.code.toLowerCase().contains(q) ||
          c.name.contains(q) ||
          c.symbol.toLowerCase() == q)
        c
  ];
}

/// Where data-only / travel plans are bought; any other name can be typed.
const travelSources = <String>[
  'Airalo',
  'Holafly',
  'Nomad',
  'Saily',
  'aloSIM',
  'Yesim',
  'Ubigi',
  'Maya Mobile',
  'GigSky',
  'Jetpac',
  'Roamless',
  'FlexiRoam',
  'BNESIM',
  'MobiMatter',
  'SimOptions',
  'Orange Holiday',
  'Klook 客路',
  'KKday',
  'Trip.com 携程',
  '飞猪',
  'esim.cc',
  'Stellar',
  'RedteaGO',
  'Instabridge',
];

/// Sources for domestic (China) data-only cards.
const domesticDataSources = <String>['运营商官方', '电商平台', '线下卡商'];
