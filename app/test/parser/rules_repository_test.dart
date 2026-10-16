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
  final bundled =
      (jsonDecode(bundledJson) as Map<String, dynamic>)['version'] as int;

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
    cache.writeAsStringSync(withVersion(bundled + 4));
    expect((await repo(never).load()).version, bundled + 4);
  });

  test('ignores a stale or corrupt cache', () async {
    cache.writeAsStringSync('{');
    expect((await repo(never).load()).version, bundled);
    cache.writeAsStringSync(withVersion(bundled - 1));
    expect((await repo(never).load()).version, bundled);
  });

  for (final (name, client) in [
    ('broken json', MockClient((_) async => http.Response('{', 200))),
    ('404', MockClient((_) async => http.Response('nope', 404))),
    (
      'same version',
      MockClient((_) async => http.Response(withVersion(bundled), 200)),
    ),
    (
      'older version',
      MockClient((_) async => http.Response(withVersion(bundled - 1), 200)),
    ),
    ('offline', MockClient((_) async => throw http.ClientException('offline'))),
  ]) {
    test('keeps current rules on bad remote: $name', () async {
      final r = repo(client);
      await r.load();
      expect(await r.refresh(), isFalse);
      expect(r.current.version, bundled);
      expect(cache.existsSync(), isFalse);
    });
  }

  test('adopts newer remote and caches it', () async {
    final r = repo(
      MockClient(
        (_) async =>
            http.Response.bytes(utf8.encode(withVersion(bundled + 1)), 200),
      ),
    );
    await r.load();
    expect(await r.refresh(), isTrue);
    expect(r.current.version, bundled + 1);
    expect((await repo(never).load()).version, bundled + 1);
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
