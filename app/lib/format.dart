import 'data/vn_time.dart';

/// `1.500.000 ₫`; negative amounts use a real minus sign, [signed] adds `+`.
String formatVnd(int amount, {bool signed = false}) {
  final digits = amount.abs().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final sign = amount < 0 ? '−' : (signed && amount > 0 ? '+' : '');
  return '$sign$digits ₫';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `dd/MM HH:mm` in Vietnam time.
String formatVnTime(DateTime t) {
  final l = t.toUtc().add(vnOffset);
  return '${_two(l.day)}/${_two(l.month)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// `10/2026` for `2026-10`.
String formatMonth(String monthKey) {
  final parts = monthKey.split('-');
  return '${int.parse(parts[1])}/${parts[0]}';
}
