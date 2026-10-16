import 'dart:io';

import 'package:moneylens/parser/parser_rules.dart';

/// Synthetic VCB texts that the bundled rules (v1) understand.
String vcbOut({
  required String ref,
  int amount = 1500000,
  int balance = 8500000,
  String time = '16-10-2026 10:24:27',
}) =>
    'Số dư TK VCB 0011004123456 -${_n(amount)} VND lúc $time. '
    'Số dư ${_n(balance)} VND. Ref $ref.chuyen tien';

const otpText = 'Mã OTP của Quý khách là 123456.';
const unknownBalanceText = 'Quý khách có biến động số dư. Mở app để xem.';

String _n(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

ParserRules bundledRules() =>
    ParserRules.tryParse(File('assets/parser-rules.json').readAsStringSync())!;
