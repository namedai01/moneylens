import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/settings_store.dart';
import '../sync/backup_actions.dart';

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
    final error = await BackupActions(widget.services).connect();
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Dữ liệu của bạn ở đâu?', style: text.headlineSmall),
              const SizedBox(height: 16),
              const Text('• Giao dịch chỉ lưu trên điện thoại này.'),
              const Text(
                '• Bản sao lưu là một Google Sheet trong Drive của chính bạn.',
              ),
              const Text(
                '• App chỉ thấy file nó tự tạo, không đọc được file khác. '
                'Không ai khác — kể cả người làm app — xem được dữ liệu.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Đang kết nối…' : 'Kết nối Google Sheet'),
              ),
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
