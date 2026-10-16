import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../capture/listener.dart';
import '../capture/raw_event.dart';
import '../data/settings_store.dart';
import '../sync/background.dart';
import '../sync/backup_actions.dart';
import '../sync/sync_status.dart';

/// Android-only screen: listener health, Google Sheet backup, and the raw
/// VCB notifications seen.
class StatusScreen extends StatefulWidget {
  final AppServices services;

  const StatusScreen({super.key, required this.services});

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
  _Backup _backup = const _Backup();
  bool _busy = false;
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
    final source = widget.services.source;
    final backup = await _Backup.read(widget.services);
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
      _backup = backup;
    });
  }

  Future<void> _run(Future<String?> Function(BackupActions a) action) async {
    setState(() => _busy = true);
    final message = await action(BackupActions(widget.services));
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    await _refresh();
  }

  /// Debug builds: a synthetic transaction the bundled rules can read.
  Future<void> _injectFake() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    String two(int v) => v.toString().padLeft(2, '0');
    final time =
        '${two(now.day)}-${two(now.month)}-${now.year} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    await debugInjectVcb(
      title: 'Thông báo VCB',
      bigText:
          'Số dư TK VCB 0011004123456 -45,000 VND lúc $time. '
          'Số dư 1,000,000 VND. Ref MBVCB.${now.millisecondsSinceEpoch}.ca phe',
    );
    await _refresh();
  }

  Future<void> _grantAccess() async {
    await openNotificationAccessSettings();
  }

  Future<void> _copyAll() async {
    final all = await widget.services.source.recent(limit: 50);
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
            _BackupCard(
              backup: _backup,
              busy: _busy,
              onConnect: () => _run((a) => a.connect()),
              onSyncNow: () => _run((a) => a.syncNow()),
              onRecreate: () => _run((a) => a.recreateSheet()),
              onSignOut: () => _run((a) async {
                await a.signOut();
                return null;
              }),
            ),
            const SizedBox(height: 16),
            Text('Listener kết nối lần cuối: ${_formatOptional(_connectedAt)}'),
            Text('Thông báo VCB gần nhất: ${_formatOptional(_lastVcbAt)}'),
            if (kDebugMode)
              TextButton(
                onPressed: _injectFake,
                child: const Text('Chèn thông báo VCB giả'),
              ),
            if (kDebugMode)
              TextButton(
                onPressed: debugRunBackgroundSyncNow,
                child: const Text('Chạy sync nền ngay'),
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

/// Snapshot of the backup settings shown on the status screen.
class _Backup {
  final String? email;
  final String? spreadsheetId;
  final DateTime? lastSyncAt;
  final String? error;
  final int unsynced;

  const _Backup({
    this.email,
    this.spreadsheetId,
    this.lastSyncAt,
    this.error,
    this.unsynced = 0,
  });

  static Future<_Backup> read(AppServices s) async {
    DateTime? time(String? v) => v == null ? null : DateTime.parse(v);
    final syncedChange = time(
      await s.settings.get(SettingKeys.lastSyncedChangeAt),
    );
    final lastSyncAt = time(await s.settings.get(SettingKeys.lastSyncAt));
    return _Backup(
      email: await s.settings.get(SettingKeys.googleEmail),
      spreadsheetId: await s.settings.get(SettingKeys.spreadsheetId),
      lastSyncAt: lastSyncAt,
      error: await s.settings.get(SettingKeys.lastSyncError),
      unsynced: lastSyncAt == null
          ? await s.ledger.changedSince(null)
          : await s.ledger.changedSince(syncedChange),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final _Backup backup;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onSyncNow;
  final VoidCallback onRecreate;
  final VoidCallback onSignOut;

  const _BackupCard({
    required this.backup,
    required this.busy,
    required this.onConnect,
    required this.onSyncNow,
    required this.onRecreate,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = backup.spreadsheetId;
    final error = describeSyncError(backup.error);
    final connected = backup.email != null && id != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sao lưu Google Sheet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (backup.lastSyncAt == null)
              Text(
                'Chưa có bản sao lưu — gỡ app là mất dữ liệu.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (backup.email != null) Text('Tài khoản: ${backup.email}'),
            if (backup.lastSyncAt != null)
              Text('Đồng bộ lần cuối: ${_formatTime(backup.lastSyncAt!)}'),
            Text('Thay đổi chưa đồng bộ: ${backup.unsynced}'),
            if (error != null)
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (!connected)
                  FilledButton(
                    onPressed: busy ? null : onConnect,
                    child: const Text('Kết nối Google Sheet'),
                  ),
                if (connected)
                  FilledButton(
                    onPressed: busy ? null : onSyncNow,
                    child: Text(busy ? 'Đang đồng bộ…' : 'Đồng bộ ngay'),
                  ),
                if (id != null)
                  OutlinedButton(
                    onPressed: () => launchUrl(
                      sheetUrl(id),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Mở Sheet'),
                  ),
                if (backup.error == 'sheet_missing')
                  OutlinedButton(
                    onPressed: busy ? null : onRecreate,
                    child: const Text('Tạo lại Sheet'),
                  ),
                if (backup.email != null)
                  TextButton(
                    onPressed: busy ? null : onSignOut,
                    child: const Text('Đăng xuất'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
