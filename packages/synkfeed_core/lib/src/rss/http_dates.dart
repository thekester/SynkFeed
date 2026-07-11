/// RFC 1123 HTTP date helpers that work on the VM and on the web, where
/// `dart:io`'s HttpDate is unavailable at runtime.
library;

const List<String> _weekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [date] as an RFC 1123 date, e.g. `Fri, 11 Jul 2026 08:00:00 GMT`.
String formatHttpDate(DateTime date) {
  final utc = date.toUtc();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${_weekdays[utc.weekday - 1]}, ${pad(utc.day)} '
      '${_months[utc.month - 1]} ${utc.year} '
      '${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)} GMT';
}

final RegExp _rfc1123 = RegExp(
  r'^\w{3}, (\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
);

/// Parses an RFC 1123 date, falling back to [DateTime.tryParse].
DateTime? parseHttpDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final raw = value.trim();
  final match = _rfc1123.firstMatch(raw);
  if (match == null) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  final month = _months.indexOf(match.group(2)!) + 1;
  if (month == 0) {
    return null;
  }
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
