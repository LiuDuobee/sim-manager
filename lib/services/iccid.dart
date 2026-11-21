/// Finds an ICCID (ITU-T E.118: "89" + 17–18 digits, Luhn check digit) in a
/// scanned barcode payload. Returns null when none passes the check.
String? extractIccid(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  // A whole digit run must be the ICCID; never shorten one to pass Luhn.
  for (final m in RegExp(r'(?<!\d)89\d{17,18}(?!\d)').allMatches(digits)) {
    if (luhnValid(m.group(0)!)) return m.group(0);
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
