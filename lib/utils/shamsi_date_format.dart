import 'package:shamsi_date/shamsi_date.dart';

const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Converts ASCII digits in [s] to Persian (Farsi) digits.
String toPersianDigits(String s) {
  return s.replaceAllMapped(
    RegExp(r'[0-9]'),
    (m) => _persianDigits[int.parse(m.group(0)!)],
  );
}

String _toPersianDigits(String s) => toPersianDigits(s);

/// Formats [date] as Shamsi (Jalali) date string for display.
/// Returns empty string for null. Uses Persian digits.
String formatShamsiDate(DateTime? date) {
  if (date == null) return '';
  final j = Jalali.fromDateTime(date);
  final s = '${j.formatter.yyyy}/${j.formatter.mm}/${j.formatter.dd}';
  return _toPersianDigits(s);
}
