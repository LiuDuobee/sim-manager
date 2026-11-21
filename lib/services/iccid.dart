/// Finds an ICCID (ITU-T E.118: "89" + 17–18 digits, Luhn check digit) in a
/// scanned barcode payload. Returns null when none passes the check.
String? extractIccid(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  for (final m in RegExp(r'89\d{17,18}').allMatches(digits)) {
    final candidate = m.group(0)!;
    // Try the longest form first, then the 19-digit one.
    for (final len in [20, 19]) {
      if (candidate.length >= len && luhnValid(candidate.substring(0, len))) {
        return candidate.substring(0, len);
      }
    }
  }
  return null;
}

bool luhnValid(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = digits.codeUnitAt(digits.length - 1 - i) - 48;
    if (d < 0 || d > 9) return false;
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}
