/// Vietnam time is a fixed UTC+07:00 (no daylight saving), so month keys and
/// boundaries are computed by offset, independent of the phone's time zone.
const vnOffset = Duration(hours: 7);

DateTime _local(DateTime t) => t.toUtc().add(vnOffset);

String _two(int v) => v.toString().padLeft(2, '0');

/// `YYYY-MM` of [t] in Vietnam time.
String monthKeyOf(DateTime t) {
  final l = _local(t);
  return '${l.year}-${_two(l.month)}';
}

/// UTC instants of the first moment of [monthKey] and of the next month.
({DateTime start, DateTime end}) monthRangeUtc(String monthKey) {
  final parts = monthKey.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  return (
    start: DateTime.utc(year, month).subtract(vnOffset),
    end: DateTime.utc(year, month + 1).subtract(vnOffset),
  );
}

/// The month key [delta] months away from [monthKey].
String shiftMonth(String monthKey, int delta) {
  final parts = monthKey.split('-');
  final d = DateTime.utc(int.parse(parts[0]), int.parse(parts[1]) + delta);
  return '${d.year}-${_two(d.month)}';
}

/// ISO 8601 in Vietnam time, e.g. `2026-10-16T10:24:27+07:00`.
String vnIso(DateTime t) {
  final l = _local(t);
  return '${l.year}-${_two(l.month)}-${_two(l.day)}'
      'T${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}+07:00';
}
