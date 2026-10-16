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
];

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
      ],
  ];
}

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
