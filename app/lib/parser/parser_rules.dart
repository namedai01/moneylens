import 'dart:convert';

import '../capture/raw_event.dart';
import '../data/txn.dart';

/// A transaction read out of one notification. Times are UTC.
class ParsedTxn {
  final String bankCode;
  final String? accountLast4;
  final Direction direction;
  final int amount;
  final DateTime occurredAt;
  final int? balanceAfter;
  final String? ref;
  final String description;

  const ParsedTxn({
    required this.bankCode,
    required this.accountLast4,
    required this.direction,
    required this.amount,
    required this.occurredAt,
    required this.balanceAfter,
    required this.ref,
    required this.description,
  });
}

sealed class ParseOutcome {
  const ParseOutcome();
}

class Parsed extends ParseOutcome {
  final ParsedTxn txn;
  const Parsed(this.txn);
}

/// Not a balance change (promo, OTP, other app): nothing to record.
class Ignored extends ParseOutcome {
  final String reason;
  const Ignored(this.reason);
}

/// Looks like a balance change but no rule could read it: the user must know.
class Failed extends ParseOutcome {
  final String reason;
  const Failed(this.reason);
}

RegExp _re(String pattern) =>
    RegExp(pattern, caseSensitive: false, dotAll: true, unicode: true);

sealed class _Rule {
  final String id;
  final RegExp pattern;
  _Rule(this.id, this.pattern);
}

class _IgnoreRule extends _Rule {
  _IgnoreRule(super.id, super.pattern);
}

class _TxRule extends _Rule {
  final String bankCode;
  final _TimeFormat time;
  final String thousandsSeparator;

  _TxRule(
    super.id,
    super.pattern, {
    required this.bankCode,
    required this.time,
    required this.thousandsSeparator,
  });
}

/// Parser rules loaded from `parser-rules.json` (bundled asset or a newer
/// copy fetched from GitHub), so message formats can change without an APK.
class ParserRules {
  final int version;
  final RegExp _package;
  final RegExp _hint;
  final List<_Rule> _rules;

  ParserRules._(this.version, this._package, this._hint, this._rules);

  /// Null when [json] is not a complete, valid rules file.
  static ParserRules? tryParse(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final rules = [
        for (final r in (m['rules'] as List).cast<Map<String, dynamic>>())
          _ruleFrom(r),
      ];
      return ParserRules._(
        m['version'] as int,
        _re(m['packagePattern'] as String),
        _re(m['transactionHint'] as String),
        rules,
      );
    } catch (_) {
      return null;
    }
  }

  static _Rule _ruleFrom(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final source = r['pattern'] as String;
    final pattern = _re(source);
    switch (r['kind']) {
      case 'ignore':
        return _IgnoreRule(id, pattern);
      case 'transaction':
        for (final g in const ['sign', 'amount', 'time']) {
          if (!source.contains('(?<$g>')) {
            throw FormatException('rule $id lacks group $g');
          }
        }
        return _TxRule(
          id,
          pattern,
          bankCode: r['bankCode'] as String,
          time: _TimeFormat(r['timeFormat'] as String),
          thousandsSeparator: r['thousandsSeparator'] as String,
        );
      default:
        throw FormatException('rule $id: unknown kind ${r['kind']}');
    }
  }

  ParseOutcome parse(RawEvent e) {
    if (!_package.hasMatch(e.packageName)) return const Ignored('package');
    final text = _normalize('${e.title ?? ''}\n${e.body}');
    for (final rule in _rules) {
      final m = rule.pattern.firstMatch(text);
      if (m == null) continue;
      return switch (rule) {
        _IgnoreRule() => Ignored(rule.id),
        _TxRule() => _transaction(rule, m),
      };
    }
    return _hint.hasMatch(text)
        ? const Failed('no-rule')
        : const Ignored('no-match');
  }

  static final _invisible = RegExp(r'\p{Cf}', unicode: true);
  static final _spaces = RegExp(r'\s+');

  /// Drops invisible format marks and folds every whitespace run (newlines,
  /// no-break spaces) into one space, so rules can be written with plain
  /// spaces whatever the bank app puts between words.
  static String _normalize(String text) =>
      text.replaceAll(_invisible, '').replaceAll(_spaces, ' ');

  ParseOutcome _transaction(_TxRule rule, RegExpMatch m) {
    String? group(String name) =>
        m.groupNames.contains(name) ? m.namedGroup(name) : null;

    final amount = _number(group('amount'), rule.thousandsSeparator);
    if (amount == null) return Failed('bad-amount:${rule.id}');
    if (amount == 0) return const Failed('zero-amount');
    final occurredAt = rule.time.parse(group('time') ?? '');
    if (occurredAt == null) return Failed('bad-time:${rule.id}');
    final balanceText = group('balance');
    final balance = _number(balanceText, rule.thousandsSeparator);
    if (balanceText != null && balance == null) {
      return Failed('bad-balance:${rule.id}');
    }
    final account = group('account');
    final ref = group('ref');
    return Parsed(
      ParsedTxn(
        bankCode: rule.bankCode,
        accountLast4: account == null || account.isEmpty
            ? null
            : account.substring(account.length < 4 ? 0 : account.length - 4),
        direction: group('sign') == '-'
            ? Direction.outgoing
            : Direction.incoming,
        amount: amount,
        occurredAt: occurredAt,
        balanceAfter: balance,
        ref: ref == null || ref.isEmpty ? null : ref,
        description: (group('desc') ?? '').trim(),
      ),
    );
  }

  /// Digits with [separator] between thousands; anything else is rejected
  /// rather than guessed.
  static int? _number(String? text, String separator) {
    if (text == null) return null;
    final digits = separator.isEmpty ? text : text.replaceAll(separator, '');
    if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
    return int.tryParse(digits);
  }
}

/// `dd MM yyyy HH mm ss` tokens with literal separators; read as UTC+07:00.
class _TimeFormat {
  static const _tokens = ['yyyy', 'dd', 'MM', 'HH', 'mm', 'ss'];

  final RegExp _re;
  final List<String> _order = [];

  _TimeFormat(String format) : _re = _compile(format, []) {
    _compile(format, _order);
  }

  static RegExp _compile(String format, List<String> order) {
    final b = StringBuffer('^');
    var i = 0;
    outer:
    while (i < format.length) {
      for (final t in _tokens) {
        if (format.startsWith(t, i)) {
          b.write('(\\d{${t.length}})');
          order.add(t);
          i += t.length;
          continue outer;
        }
      }
      b.write(RegExp.escape(format[i]));
      i++;
    }
    b.write(r'$');
    return RegExp(b.toString());
  }

  DateTime? parse(String text) {
    final m = _re.firstMatch(text.trim());
    if (m == null) return null;
    final v = <String, int>{};
    for (var i = 0; i < _order.length; i++) {
      v[_order[i]] = int.parse(m.group(i + 1)!);
    }
    final local = DateTime.utc(
      v['yyyy'] ?? 1970,
      v['MM'] ?? 1,
      v['dd'] ?? 1,
      v['HH'] ?? 0,
      v['mm'] ?? 0,
      v['ss'] ?? 0,
    );
    // Reject impossible dates that DateTime would silently roll over.
    if (local.month != (v['MM'] ?? 1) || local.day != (v['dd'] ?? 1)) {
      return null;
    }
    return local.subtract(const Duration(hours: 7));
  }
}
