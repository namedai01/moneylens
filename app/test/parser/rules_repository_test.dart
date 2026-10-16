import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylens/parser/rules_repository.dart';

void main() {
  late Directory dir;
  late File cache;
  final bundledJson = File('assets/parser-rules.json').readAsStringSync();

  String withVersion(int v) {
    final m = jsonDecode(bundledJson) as Map<String, dynamic>;
    m['version'] = v;
    return jsonEncode(m);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rules');
    cache = File('${dir.path}/parser-rules.json');
  });

  tearDown(() => dir.delete(recursive: true));

  RulesRepository repo(http.Client client) => RulesRepository(
    loadBundled: () async => bundledJson,
    cacheFile: cache,
    client: client,
  );

  final never = MockClient(
    (_) async => throw StateError('no network in this test'),
  );

  test('picks higher version between bundled and cache', () async {
    cache.writeAsStringSync(withVersion(5));
    expect((await repo(never).load()).version, 5);
  });

  test('ignores a stale or corrupt cache', () async {
    cache.writeAsStringSync('{');
    expect((await repo(never).load()).version, 1);
    cache.writeAsStringSync(withVersion(0));
    expect((await repo(never).load()).version, 1);
  });

  for (final (name, client) in [
    ('broken json', MockClient((_) async => http.Response('{', 200))),
    ('404', MockClient((_) async => http.Response('nope', 404))),
    (
      'same version',
      MockClient((_) async => http.Response(withVersion(1), 200)),
    ),
    (
      'older version',
      MockClient((_) async => http.Response(withVersion(0), 200)),
    ),
    ('offline', MockClient((_) async => throw http.ClientException('offline'))),
  ]) {
    test('keeps current rules on bad remote: $name', () async {
      final r = repo(client);
      await r.load();
      expect(await r.refresh(), isFalse);
      expect(r.current.version, 1);
      expect(cache.existsSync(), isFalse);
    });
  }

  test('adopts newer remote and caches it', () async {
    final r = repo(
      MockClient(
        (_) async => http.Response.bytes(utf8.encode(withVersion(2)), 200),
      ),
    );
    await r.load();
    expect(await r.refresh(), isTrue);
    expect(r.current.version, 2);
    expect((await repo(never).load()).version, 2);
  });

  test('request carries no user data', () async {
    late http.BaseRequest seen;
    final r = repo(
      MockClient((req) async {
        seen = req;
        return http.Response('{', 200);
      }),
    );
    await r.load();
    await r.refresh();
    expect(seen.url, Uri.parse(rulesUrl));
    expect(seen.method, 'GET');
    expect((seen as http.Request).body, isEmpty);
    expect(seen.url.query, isEmpty);
  });
}
