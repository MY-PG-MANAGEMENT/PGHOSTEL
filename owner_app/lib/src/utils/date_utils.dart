import 'package:flutter/services.dart';

// Auto-inserts hyphens as the user types digits: dd-mm-yyyy
// Strips every non-digit, limits to 8 digits, then inserts '-' after position 2 and 4.
class DateDmyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits =
        newValue.text.replaceAll(RegExp(r'[^0-9]'), '').substring(
            0,
            newValue.text.replaceAll(RegExp(r'[^0-9]'), '').length.clamp(0, 8));
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buf.write('-');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Today formatted as dd-mm-yyyy.
String todayDmy() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.year}';
}

/// dd-mm-yyyy → yyyy-MM-dd for API calls.
/// Returns the input unchanged when it doesn't match the expected pattern
/// (e.g. empty string, partial entry).
String dmyToIso(String dmy) {
  final p = dmy.split('-');
  if (p.length == 3 && p[0].length == 2 && p[1].length == 2 && p[2].length == 4) {
    return '${p[2]}-${p[1]}-${p[0]}';
  }
  return dmy;
}

/// yyyy-MM-dd → dd-mm-yyyy for display (used when pre-filling from API data).
/// Returns the input unchanged when it doesn't match.
String isoToDmy(String iso) {
  final p = iso.split('-');
  if (p.length == 3 && p[0].length == 4 && p[1].length == 2 && p[2].length == 2) {
    return '${p[2]}-${p[1]}-${p[0]}';
  }
  return iso;
}
