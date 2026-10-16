import '../data/txn.dart';
import '../data/vn_time.dart';

const txTabTitle = 'Giao dịch';
const summaryTabTitle = 'Tổng hợp';

const txNotice =
    'Tab này do app MoneyLens ghi đè mỗi lần đồng bộ — đừng sửa ở đây, '
    'hãy tạo tab riêng để phân tích.';

/// Enough columns to restore the ledger from the Sheet later.
const txHeader = [
  'ref',
  'thời gian',
  'tháng',
  'chiều',
  'số tiền',
  'số dư sau',
  'nội dung',
  'ẩn khỏi thống kê',
  'tài khoản',
  'nguồn',
  'id',
  'ngân hàng',
];

/// Sheets written before the bank column existed only had VCB.
const legacyBankCode = 'VCB';

/// The whole "Giao dịch" tab: notice, header, then every transaction by time.
List<List<Object?>> transactionRows(List<Txn> txns) {
  final sorted = [...txns]
    ..sort((a, b) {
      final c = a.occurredAt.compareTo(b.occurredAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return [
    [txNotice],
    txHeader,
    for (final t in sorted)
      [
        t.ref,
        vnIso(t.occurredAt),
        monthKeyOf(t.occurredAt),
        t.direction == Direction.incoming ? 'vào' : 'ra',
        t.signedAmount,
        t.balanceAfter,
        t.description,
        t.excluded,
        t.accountLast4,
        t.source,
        t.id,
        t.accountBank,
      ],
  ];
}

/// One transaction read back from the "Giao dịch" tab.
class SheetTxn {
  final String? ref;
  final DateTime occurredAt;
  final Direction direction;

  /// Always positive; the sign lives in [direction].
  final int amount;
  final int? balanceAfter;
  final String description;
  final bool excluded;
  final String bankCode;
  final String? accountLast4;
  final String source;

  const SheetTxn({
    required this.ref,
    required this.occurredAt,
    required this.direction,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.excluded,
    required this.bankCode,
    required this.accountLast4,
    required this.source,
  });
}

/// Reads back what [transactionRows] wrote. Throws [FormatException], with a
/// message fit to show the user, when the header is not ours or a row cannot
/// be read.
List<SheetTxn> parseTransactionRows(List<List<Object?>> rows) {
  if (rows.length < 2 || !_isOurHeader(rows[1])) {
    throw const FormatException('tab "$txTabTitle" không đúng mẫu MoneyLens');
  }
  return [
    for (var i = 2; i < rows.length; i++)
      if (rows[i].any((c) => c != null && c != ''))
        ?_parseNumbered(rows[i], sheetRow: i + 1),
  ];
}

/// Names the Sheet row (1-based, as the user sees it) in any error.
SheetTxn? _parseNumbered(List<Object?> row, {required int sheetRow}) {
  try {
    return parseTransactionRow(row);
  } on FormatException catch (e) {
    throw FormatException('dòng $sheetRow, ${e.message}');
  }
}

/// Accepts headers from before the bank column was added.
bool _isOurHeader(List<Object?> row) {
  const required = 11;
  if (row.length < required) return false;
  for (var i = 0; i < row.length && i < txHeader.length; i++) {
    if (row[i] != txHeader[i]) return false;
  }
  return true;
}

/// Cell [i] of [row], or null when missing or blank. The Sheets API drops
/// trailing empty cells, so rows can be shorter than the header.
Object? cellAt(List<Object?> row, int i) {
  final v = i < row.length ? row[i] : null;
  return v == '' ? null : v;
}

/// One data row, columns in [txHeader] order. Values arrive unformatted:
/// numbers as num, booleans as bool, everything else as String. The sign of
/// the amount decides the direction, as the summary formulas do.
SheetTxn? parseTransactionRow(List<Object?> row) {
  String? text(int i) {
    final v = cellAt(row, i);
    return v == null ? null : '$v';
  }

  final time = cellAt(row, 1);
  final occurredAt = time is String ? DateTime.tryParse(time)?.toUtc() : null;
  if (occurredAt == null) return badRow(row, 'thời gian');
  final signed = cellAt(row, 4);
  if (signed is! num || signed == 0) return badRow(row, 'số tiền');
  final balance = cellAt(row, 5);
  return SheetTxn(
    ref: text(0),
    occurredAt: occurredAt,
    direction: signed > 0 ? Direction.incoming : Direction.outgoing,
    amount: signed.abs().toInt(),
    balanceAfter: balance is num ? balance.toInt() : null,
    description: text(6) ?? '',
    excluded: cellAt(row, 7) == true,
    bankCode: text(11) ?? legacyBankCode,
    accountLast4: text(8),
    source: text(9) ?? 'sheet',
  );
}

/// A row whose [column] cannot be read, usually because the user typed over
/// it. Aborts the whole restore rather than silently dropping a transaction:
/// the user fixes that cell in the Sheet and tries again.
SheetTxn? badRow(List<Object?> row, String column) =>
    throw FormatException('cột "$column" không đọc được');

/// "Tổng hợp" tab, written once when the Sheet is created; the user owns it
/// afterwards. Months come from the transactions tab; each month's income and
/// expense are summed per row with MAP/LAMBDA (SUMIFS would not expand over
/// an array of months) using an exact text match on the month column, and
/// skipping rows hidden from the totals.
List<List<Object?>> summaryRows() {
  const tx = "'$txTabTitle'";
  const month = '$tx!C3:C';
  const amount = '$tx!E3:E';
  const hidden = '$tx!H3:H';
  String perMonth(String sign, String body) =>
      '=MAP(A2:A,LAMBDA(m,IF(m="",,$sign$body)))';
  String sumWhere(String test) =>
      'IFERROR(SUM(FILTER($amount,$month=m,$hidden=FALSE,$amount$test)),0)';
  return [
    ['tháng', 'tổng thu', 'tổng chi', 'chênh lệch'],
    [
      '=SORT(UNIQUE(FILTER($month,$month<>"")),1,FALSE)',
      perMonth('', sumWhere('>0')),
      perMonth('-', sumWhere('<0')),
      '=MAP(A2:A,B2:B,C2:C,LAMBDA(m,i,e,IF(m="",,i-e)))',
    ],
  ];
}
