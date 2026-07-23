/// App-wide currency formatting in the Indian numbering system.
///
/// Groups the integer part as `x,xx,xxx` (thousand, then every two digits):
/// `1000 → ₹1,000`, `10000 → ₹10,000`, `120500 → ₹1,20,500`. Paise are kept
/// only when present (`8500.5 → ₹8,500.50`), and trailing `.00` is dropped.
///
/// Use [inr] for every rupee amount shown in the UI so the format is identical
/// on every screen.
library;

/// Formats [value] (a num or numeric string) as an Indian-grouped rupee string.
/// Returns [nullText] when [value] is null and the raw string when it isn't
/// numeric.
String inr(dynamic value, {String nullText = '—'}) {
  if (value == null) return nullText;
  final n = value is num ? value : num.tryParse(value.toString());
  if (n == null) return value.toString();
  final sign = n < 0 ? '-' : '';
  return '$sign₹${_group(n.abs())}';
}

/// Indian-grouped number without the ₹ symbol, e.g. `1,20,500`.
String inrPlain(dynamic value, {String nullText = '—'}) {
  if (value == null) return nullText;
  final n = value is num ? value : num.tryParse(value.toString());
  if (n == null) return value.toString();
  final sign = n < 0 ? '-' : '';
  return '$sign${_group(n.abs())}';
}

String _group(num v) {
  final intPart = v.truncate();
  final grouped = _groupInt(intPart.toString());
  if (v % 1 == 0) return grouped;
  // Keep up to two decimal places, dropping a trailing zero (8500.5 → .50, 8500.50 → .50).
  final frac = (v - intPart).toStringAsFixed(2).substring(2);
  return '$grouped.$frac';
}

String _groupInt(String s) {
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}
