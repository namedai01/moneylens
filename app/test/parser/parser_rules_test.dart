import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/raw_event.dart';
import 'package:moneylens/data/txn.dart';
import 'package:moneylens/parser/parser_rules.dart';

RawEvent raw(String? title, String body, {String pkg = 'com.VCB.digibank'}) =>
    RawEvent(
      id: 1,
      packageName: pkg,
      title: title,
      text: body,
      bigText: body,
      postedAt: DateTime.utc(2026, 10, 16),
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
