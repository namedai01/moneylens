import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../capture/listener.dart';
import '../capture/raw_event.dart';
import '../capture/raw_event_source.dart';

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
  DateTime? _connectedAt;
  DateTime? _lastVcbAt;
  List<RawEvent> _recent = [];
  RawEventSource? _source;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The native listener writes the log; poll it while this screen is open.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Coming back from system settings: permissions may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final hasAccess = await hasNotificationAccess();
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final source = await _openSource();
    final connectedAt = await source.listenerConnectedAt();
    final lastVcbAt = await source.lastVcbAt();
    final recent = await source.recent();
    if (!mounted) return;
    setState(() {
      _hasAccess = hasAccess;
      _batteryUnrestricted = battery;
      _connectedAt = connectedAt;
      _lastVcbAt = lastVcbAt;
      _recent = recent;
    });
  }

  Future<RawEventSource> _openSource() async =>
      _source ??= await RawEventSource.open(await captureDbPath());

  Future<void> _grantAccess() async {
    await openNotificationAccessSettings();
  }

  Future<void> _copyAll() async {
    final all = await (await _openSource()).recent(limit: 50);
    final lines = all.map((n) => jsonEncode(n.toJson())).join('\n');
    await Clipboard.setData(ClipboardData(text: lines));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép ${all.length} thông báo')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Listener kết nối lần cuối: ${_formatOptional(_connectedAt)}'),
            Text('Thông báo VCB gần nhất: ${_formatOptional(_lastVcbAt)}'),
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

String _formatOptional(DateTime? t) => t == null ? 'chưa có' : _formatTime(t);

/// Vietnam time (fixed UTC+07:00), independent of the phone's time zone.
String _formatTime(DateTime t) {
  final l = t.toUtc().add(const Duration(hours: 7));
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
