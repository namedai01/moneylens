import 'dart:convert';
import 'dart:io';

import 'captured_notification.dart';

/// Local debug log of captured notifications.
///
/// Keeps the full content of the latest [maxVcbEntries] VCB notifications and
/// only a per-package counter for everything else, so other apps' content is
/// never stored.
class CaptureLog {
  static const maxVcbEntries = 50;

  final File file;

  CaptureLog(this.file);

  /// Pending write per log path. The plugin fires callbacks without awaiting
  /// them, so read-modify-write cycles must be chained or they lose entries.
  static final Map<String, Future<void>> _tails = {};
  static var _tmpCounter = 0;

  Future<void> record(CapturedNotification n) {
    final tail = _tails[file.path] ?? Future<void>.value();
    final next = tail.then((_) => _record(n));
    _tails[file.path] = next.catchError((_) {});
    return next;
  }

  Future<void> _record(CapturedNotification n) async {
    final data = await _read();
    final counts = data.counts;
    counts[n.packageName] = (counts[n.packageName] ?? 0) + 1;

    final vcb = data.vcb;
    if (isVcbPackage(n.packageName)) {
      vcb.add(n);
      vcb.sort((a, b) => b.postedAt.compareTo(a.postedAt));
      if (vcb.length > maxVcbEntries) {
        vcb.removeRange(maxVcbEntries, vcb.length);
      }
    }
    await _write(vcb, counts);
  }

  Future<List<CapturedNotification>> recentVcb({int limit = 20}) async {
    final vcb = (await _read()).vcb;
    return vcb.take(limit).toList();
  }

  Future<Map<String, int>> packageCounts() async => (await _read()).counts;

  Future<({List<CapturedNotification> vcb, Map<String, int> counts})>
  _read() async {
    try {
      if (!await file.exists()) {
        return (vcb: <CapturedNotification>[], counts: <String, int>{});
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final vcb = (json['vcb'] as List)
          .map((e) => CapturedNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      final counts = (json['counts'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as int),
      );
      return (vcb: vcb, counts: counts);
    } catch (_) {
      // A corrupt log must never break capturing; start over.
      return (vcb: <CapturedNotification>[], counts: <String, int>{});
    }
  }

  Future<void> _write(
    List<CapturedNotification> vcb,
    Map<String, int> counts,
  ) async {
    final tmp = File('${file.path}.${pid}_${_tmpCounter++}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'vcb': vcb.map((n) => n.toJson()).toList(),
        'counts': counts,
      }),
    );
    await tmp.rename(file.path);
  }
}
