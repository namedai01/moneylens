import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/raw_event.dart';
import 'package:moneylens/data/txn.dart';
import 'package:moneylens/parser/parser_rules.dart';

RawEvent raw(
  String? title,
  String body, {
  String pkg = 'com.VCB.digibank',
  DateTime? postedAt,
}) => RawEvent(
  id: 1,
  packageName: pkg,
  title: title,
  text: body,
  bigText: body,
  postedAt: postedAt ?? DateTime.utc(2026, 10, 16),
);

ParserRules bundled() =>
    ParserRules.tryParse(File('assets/parser-rules.json').readAsStringSync())!;

void main() {
  test('bundled asset parses', () {
    expect(bundled().version, greaterThanOrEqualTo(1));
  });

  final fixtures =
      (jsonDecode(
                File(
                  'test/parser/fixtures/synthetic_vcb.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  for (final f in fixtures) {
    test('synthetic: ${f['name']}', () {
      final outcome = bundled().parse(raw(f['title'], f['bigText']));
      final e = f['expect'] as Map<String, dynamic>;
      switch (e['status']) {
        case 'parsed':
          expect(outcome, isA<Parsed>());
          final t = (outcome as Parsed).txn;
          expect(t.bankCode, 'VCB');
          expect(t.direction.db, e['direction']);
          expect(t.amount, e['amount']);
          expect(t.balanceAfter, e['balanceAfter']);
          expect(t.occurredAt, DateTime.parse(e['occurredAt']));
          expect(t.occurredAt.isUtc, isTrue);
          expect(t.accountLast4, e['accountLast4']);
          expect(t.ref, e['ref']);
          expect(t.description, e['description']);
        case 'ignored':
          expect(outcome, isA<Ignored>());
        case 'failed':
          expect(outcome, isA<Failed>());
      }
    });
  }

  test('ignored package', () {
    final o = bundled().parse(
      raw('Zalo', 'Số dư TK VCB 1 -1 VND', pkg: 'com.zing.zalo'),
    );
    expect(o, isA<Ignored>());
    expect((o as Ignored).reason, 'package');
  });

  test('unknown VCB balance text fails with no-rule', () {
    final o = bundled().parse(raw('VCB', 'Quý khách có biến động số dư.'));
    expect((o as Failed).reason, 'no-rule');
  });

  group('SHB SAHA', () {
    const pkg = 'vn.shb.saha.mbanking';
    final posted = DateTime.utc(2026, 10, 16, 16, 57, 12);

    ParseOutcome shb(String body) =>
        bundled().parse(raw('SHB SAHA', body, pkg: pkg, postedAt: posted));

    test('outgoing: no time in text, so the post time is used', () {
      final t =
          (shb('Phát sinh -5,000 VND\nTài khoản 0905695976\nxp') as Parsed).txn;
      expect(t.bankCode, 'SHB');
      expect(t.direction, Direction.outgoing);
      expect(t.amount, 5000);
      expect(t.occurredAt, posted);
      expect(t.accountLast4, '5976');
      expect(t.balanceAfter, isNull);
      expect(t.ref, isNull);
      expect(t.description, 'xp');
    });

    test('incoming with a multi-line description', () {
      final t =
          (shb(
                    'Phát sinh +1,250,000 VND\nTài khoản 0905695976\n'
                    'NGUYEN VAN A chuyen tien\ntien nha',
                  )
                  as Parsed)
              .txn;
      expect(t.direction, Direction.incoming);
      expect(t.amount, 1250000);
      expect(t.description, 'NGUYEN VAN A chuyen tien tien nha');
    });

    test('empty description', () {
      final t =
          (shb('Phát sinh -20,000 VND\nTài khoản 0905695976') as Parsed).txn;
      expect(t.description, '');
    });

    test('unknown "Phát sinh" text fails with no-rule', () {
      expect((shb('Phát sinh giao dịch mới') as Failed).reason, 'no-rule');
    });

    test('only package ids with an shb segment are read', () {
      for (final p in ['vn.shb.mbanking', 'com.shbsaha.app']) {
        expect(
          bundled().parse(raw('SHB', 'Phát sinh -1 VND', pkg: p)),
          isNot(isA<Ignored>().having((i) => i.reason, 'reason', 'package')),
          reason: p,
        );
      }
      final o = bundled().parse(
        raw('Sổ thu chi', 'Phát sinh -5,000 VND', pkg: 'com.cashbook.app'),
      );
      expect((o as Ignored).reason, 'package');
    });
  });

  test('a rule without timeFormat must not declare a time group', () {
    String rules(Map<String, Object> rule) => jsonEncode({
      'version': 1,
      'packagePattern': 'x',
      'transactionHint': 'x',
      'rules': [
        {
          'id': 'r',
          'kind': 'transaction',
          'bankCode': 'X',
          'thousandsSeparator': ',',
          ...rule,
        },
      ],
    });
    expect(
      ParserRules.tryParse(
        rules({'pattern': r'(?<sign>[+-])(?<amount>\d+) (?<time>\d+)'}),
      ),
      isNull,
    );
    expect(
      ParserRules.tryParse(rules({'pattern': r'(?<sign>[+-])(?<amount>\d+)'})),
      isNotNull,
    );
  });

  ParserRules rulesWith(String separator) => ParserRules.tryParse(
    jsonEncode({
      'version': 3,
      'packagePattern': 'vcb',
      'transactionHint': 'Số dư',
      'rules': [
        {
          'id': 't',
          'kind': 'transaction',
          'bankCode': 'VCB',
          'pattern':
              r'(?<sign>[+-])(?<amount>[\d.,]+) VND lúc (?<time>\d{2}/\d{2}/\d{4} \d{2}:\d{2})',
          'timeFormat': 'dd/MM/yyyy HH:mm',
          'thousandsSeparator': separator,
        },
      ],
    }),
  )!;

  test('dot thousands separator when configured', () {
    final o = rulesWith(
      '.',
    ).parse(raw('VCB', 'Số dư -1.500.000 VND lúc 16/10/2026 10:24'));
    final t = (o as Parsed).txn;
    expect(t.amount, 1500000);
    expect(t.direction, Direction.outgoing);
    expect(t.occurredAt, DateTime.utc(2026, 10, 16, 3, 24));
    expect(t.balanceAfter, isNull);
    expect(t.ref, isNull);
    expect(t.description, '');
  });

  test('wrong separator fails instead of guessing', () {
    final o = rulesWith(
      ',',
    ).parse(raw('VCB', 'Số dư -1.500.000 VND lúc 16/10/2026 10:24'));
    expect(o, isA<Failed>());
  });

  test('zero amount fails', () {
    final o = rulesWith(
      ',',
    ).parse(raw('VCB', 'Số dư -0 VND lúc 16/10/2026 10:24'));
    expect((o as Failed).reason, 'zero-amount');
  });

  test('tryParse rejects bad regex and missing version', () {
    expect(ParserRules.tryParse('{'), isNull);
    expect(
      ParserRules.tryParse(
        jsonEncode({
          'packagePattern': 'vcb',
          'transactionHint': 'x',
          'rules': [],
        }),
      ),
      isNull,
    );
    expect(
      ParserRules.tryParse(
        jsonEncode({
          'version': 1,
          'packagePattern': 'vcb',
          'transactionHint': 'x',
          'rules': [
            {'id': 'bad', 'kind': 'ignore', 'pattern': '(unclosed'},
          ],
        }),
      ),
      isNull,
    );
    expect(
      ParserRules.tryParse(
        jsonEncode({
          'version': 1,
          'packagePattern': 'vcb',
          'transactionHint': 'x',
          'rules': [
            {
              'id': 'nogroups',
              'kind': 'transaction',
              'bankCode': 'VCB',
              'pattern': 'abc',
              'timeFormat': 'dd',
              'thousandsSeparator': ',',
            },
          ],
        }),
      ),
      isNull,
    );
  });
}
