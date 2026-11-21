import '../models/sim_card.dart';

/// What a carrier top-up / validity SMS says. Every field is optional: the
/// renewal sheet shows what was found and the user confirms or corrects it.
class ParsedSms {
  const ParsedSms({
    this.success = false,
    this.amount,
    this.currency,
    this.deadline,
  });

  final bool success;
  final double? amount;
  final String? currency;
  final DateTime? deadline;

  bool get isEmpty => !success && amount == null && deadline == null;
}

const _successWords = [
  '充值成功',
  '充值已到账',
  '已到账',
  '缴费成功',
  '续费成功',
  '已成功充值',
  '储值成功',
  '增值成功',
  'チャージ',
  'top-up successful',
  'top up successful',
  'topped up',
  'recharge successful',
  'successfully recharged',
  'payment received',
  'credit added',
  'thank you for your top',
  'เติมเงินสำเร็จ',
];

const _currencySymbols = <String, String>{
  'HK\$': 'HKD',
  'US\$': 'USD',
  'S\$': 'SGD',
  'NT\$': 'TWD',
  '£': 'GBP',
  '€': 'EUR',
  '¥': 'CNY',
  '￥': 'CNY',
  '円': 'JPY',
  '฿': 'THB',
  '\$': 'USD',
  '元': 'CNY',
  '港币': 'HKD',
  '港幣': 'HKD',
  'บาท': 'THB',
};

const _codes = [
  'CNY',
  'RMB',
  'HKD',
  'USD',
  'GBP',
  'EUR',
  'JPY',
  'THB',
  'SGD',
  'TWD',
  'MOP'
];

/// Parses the amount, the new validity date and whether the message reports
/// a successful top-up. Day/month order follows the text: `2026年12月31日`,
/// `2026-12-31`, `31/12/2026` (UK/EU style, as used by GB/HK/TH carriers),
/// `12/31/2026` when the first number can't be a month, `31 Dec 2026`.
ParsedSms parseRenewalSms(String text, {DateTime? now}) {
  final lower = text.toLowerCase();
  final success = _successWords.any((w) => lower.contains(w.toLowerCase()));
  final (amount, currency) = _amount(text);
  return ParsedSms(
    success: success,
    amount: amount,
    currency: currency,
    deadline: _deadline(text, now ?? DateTime.now()),
  );
}

(double?, String?) _amount(String text) {
  const num = r'(\d{1,6}(?:[.,]\d{1,2})?)';
  // Symbol / code before the number: £10, HK$ 100, USD 3.
  final symbols = _currencySymbols.keys.map(RegExp.escape).join('|');
  final before =
      RegExp('($symbols|${_codes.join('|')})\\s?$num', caseSensitive: false);
  // Number before the unit: 100元, 300円, 50 HKD, 100 บาท.
  final after =
      RegExp('$num\\s?(${_codes.join('|')}|$symbols)', caseSensitive: false);
  for (final (re, numGroup, curGroup) in [(before, 2, 1), (after, 1, 2)]) {
    for (final m in re.allMatches(text)) {
      final value = double.tryParse(m.group(numGroup)!.replaceAll(',', '.'));
      if (value == null || !value.isFinite || value < 0) continue;
      return (value, _currencyOf(m.group(curGroup)!));
    }
  }
  return (null, null);
}

String _currencyOf(String raw) {
  final upper = raw.toUpperCase();
  if (upper == 'RMB') return 'CNY';
  if (_codes.contains(upper)) return upper;
  return _currencySymbols[raw] ?? 'CNY';
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

DateTime? _deadline(String text, DateTime now) {
  // Prefer a date that follows a validity keyword; else the latest date.
  final keyword = RegExp(
      r'(有效期至|有效期|到期日|到期|至|截止|valid until|valid till|valid to|expires? on|expiry|expiry date|有効期限|until)',
      caseSensitive: false);
  final dates = <(int, DateTime)>[];
  void add(int at, int y, int m, int d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return;
    final date = DateTime(y, m, d);
    if (date.month != m) return;
    dates.add((at, date));
  }

  for (final m in RegExp(r'(\d{4})\s*[年./-]\s*(\d{1,2})\s*[月./-]\s*(\d{1,2})')
      .allMatches(text)) {
    add(m.start, int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!));
  }
  for (final m in RegExp(r'(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?!\d)')
      .allMatches(text)) {
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    // Day first unless that is impossible.
    a > 12 || b <= 12 ? add(m.start, y, b, a) : add(m.start, y, a, b);
  }
  for (final m in RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{4})')
      .allMatches(text)) {
    final month = _months[m.group(2)!.toLowerCase()];
    if (month != null) {
      add(m.start, int.parse(m.group(3)!), month, int.parse(m.group(1)!));
    }
  }
  // 12月31日 without a year: the next such date from today.
  for (final m
      in RegExp(r'(?<![\d年./-])(\d{1,2})月(\d{1,2})日').allMatches(text)) {
    final month = int.parse(m.group(1)!), day = int.parse(m.group(2)!);
    var y = now.year;
    if (DateTime(y, month, day).isBefore(dateOnly(now))) y++;
    add(m.start, y, month, day);
  }
  if (dates.isEmpty) return null;
  final keys = keyword.allMatches(text).map((k) => k.end).toList();
  for (final (at, date) in dates) {
    if (keys.any((k) => at >= k && at - k <= 6)) return date;
  }
  dates.sort((x, y) => y.$2.compareTo(x.$2));
  return dates.first.$2;
}
