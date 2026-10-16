import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'parser_rules.dart';

/// Same file as the bundled asset, served from the project's public repo.
const rulesUrl =
    'https://raw.githubusercontent.com/namedai01/moneylens/main/app/assets/parser-rules.json';

/// Picks the newest parser rules among the bundled asset, a cached download
/// and the copy on GitHub. Fetching is a plain GET: nothing about the user
/// leaves the phone.
class RulesRepository {
  final Future<String> Function() loadBundled;
  final File cacheFile;
  final http.Client client;
  final Uri remote;

  ParserRules? _current;

  RulesRepository({
    required this.loadBundled,
    required this.cacheFile,
    required this.client,
    Uri? remote,
  }) : remote = remote ?? Uri.parse(rulesUrl);

  ParserRules get current => _current!;

  Future<ParserRules> load() async {
    var best = ParserRules.tryParse(await loadBundled())!;
    try {
      final cached = ParserRules.tryParse(await cacheFile.readAsString());
      if (cached != null && cached.version > best.version) best = cached;
    } on FileSystemException {
      // No cache yet.
    }
    return _current = best;
  }

  /// True when a newer, valid rules file was adopted. Never throws.
  Future<bool> refresh() async {
    try {
      final res = await client.get(remote).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final body = utf8.decode(res.bodyBytes);
      final rules = ParserRules.tryParse(body);
      if (rules == null || rules.version <= current.version) return false;
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(body);
      _current = rules;
      return true;
    } catch (_) {
      return false;
    }
  }
}
