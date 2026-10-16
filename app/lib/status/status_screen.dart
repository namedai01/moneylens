import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../capture/capture_log.dart';
import '../capture/captured_notification.dart';
import '../capture/listener.dart';

/// Android-only screen: listener health plus the raw VCB notifications seen.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen>
    with WidgetsBindingObserver {
  bool _hasAccess = false;
  bool _batteryUnrestricted = false;
  Map<String, int> _counts = {};
  List<CapturedNotification> _recent = [];
  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _port = registerCaptureUiPort();
    _sub = _port!.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _port?.close();
    super.dispose();
  }

  // Coming back from system settings: permissions may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final hasAccess = await hasNotificationAccess();
    if (hasAccess) await initListener();
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final log = CaptureLog(await captureLogFile());
    final counts = await log.packageCounts();
    final recent = await log.recentVcb();
    if (!mounted) return;
    setState(() {
      _hasAccess = hasAccess;
      _batteryUnrestricted = battery;
      _counts = counts;
      _recent = recent;
    });
  }

  Future<void> _grantAccess() async {
    await Permission.notification.request();
    await openNotificationAccessSettings();
  }

  Future<void> _copyAll() async {
    final log = CaptureLog(await captureLogFile());
    final all = await log.recentVcb(limit: CaptureLog.maxVcbEntries);
    final lines = all.map((n) => jsonEncode(n.toJson())).join('\n');
    await Clipboard.setData(ClipboardData(text: lines));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép ${all.length} thông báo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedCounts = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Trạng thái')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CheckTile(
              ok: _hasAccess,
              title: 'Quyền đọc thông báo',
              actionLabel: 'Mở cài đặt',
              onAction: _grantAccess,
              note:
                  'Nếu nút bật bị mờ: Cài đặt → Ứng dụng → MoneyLens → ⋮ → '
                  'Cho phép cài đặt bị hạn chế.',
            ),
            _CheckTile(
              ok: _batteryUnrestricted,
              title: 'Tắt tối ưu pin',
              actionLabel: 'Cho phép',
              onAction: () async {
                await Permission.ignoreBatteryOptimizations.request();
                await _refresh();
              },
              note: 'Xiaomi/Oppo/Vivo: bật thêm "Tự khởi chạy" cho MoneyLens.',
            ),
            const SizedBox(height: 16),
            Text(
              'Package đã thấy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (sortedCounts.isEmpty) const Text('Chưa có thông báo nào.'),
            for (final e in sortedCounts)
              Text(
                '${e.key}: ${e.value}',
                style: TextStyle(
                  fontWeight: isVcbPackage(e.key) ? FontWeight.bold : null,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '20 thông báo VCB gần nhất',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _recent.isEmpty ? null : _copyAll,
                  child: const Text('Sao chép tất cả'),
                ),
              ],
            ),
            for (final n in _recent)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    '${_formatTime(n.postedAt)} · ${n.packageName}\n'
                    '${n.title ?? ''}\n${n.body}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} '
      '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

class _CheckTile extends StatelessWidget {
  final bool ok;
  final String title;
  final String actionLabel;
  final Future<void> Function() onAction;
  final String note;

  const _CheckTile({
    required this.ok,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(ok ? '✅' : '❌'),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
                if (!ok)
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
            if (!ok) ...[
              const SizedBox(height: 4),
              Text(note, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
