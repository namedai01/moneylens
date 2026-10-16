import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/settings_store.dart';
import '../sync/backup_actions.dart';
import '../theme.dart';
import 'restore_dialog.dart';

/// First launch: explain where data lives, offer to connect Google Sheet.
class ConnectScreen extends StatefulWidget {
  final AppServices services;
  final VoidCallback onDone;

  const ConnectScreen({
    super.key,
    required this.services,
    required this.onDone,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _busy = false;

  Future<void> _finish() async {
    await widget.services.settings.set(SettingKeys.onboardingDone, '1');
    widget.onDone();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final error = await BackupActions(
      widget.services,
    ).connect(pickRestore: (found) => pickRestoreSheet(context, found));
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'Dữ liệu của bạn ở đâu?',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),
              const _Point(
                Icons.smartphone_rounded,
                'Giao dịch chỉ lưu trên điện thoại này.',
              ),
              const _Point(
                Icons.table_chart_outlined,
                'Bản sao lưu là một Google Sheet trong Drive của chính bạn.',
              ),
              const _Point(
                Icons.lock_outline_rounded,
                'App chỉ thấy file nó tự tạo, không đọc được file khác. '
                'Không ai khác — kể cả người làm app — xem được dữ liệu.',
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Đang kết nối…' : 'Kết nối Google Sheet'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : _finish,
                child: const Text('Để sau'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Point(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: MoneyColors.of(context).income),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
}
