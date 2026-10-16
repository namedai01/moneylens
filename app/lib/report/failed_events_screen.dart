import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_services.dart';
import '../capture/raw_event.dart';
import '../format.dart';
import 'mask.dart';

/// Notifications no rule could read. The user reviews a masked copy and
/// shares it themselves; the app never sends it anywhere on its own.
class FailedEventsScreen extends StatefulWidget {
  final AppServices services;

  const FailedEventsScreen({super.key, required this.services});

  @override
  State<FailedEventsScreen> createState() => _FailedEventsScreenState();
}

class _FailedEventsScreenState extends State<FailedEventsScreen> {
  List<RawEvent> _events = [];
  Map<int, String> _reasons = {};
  final _controllers = <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = widget.services;
    final events = await s.source.byIds(await s.parseLog.failedIds());
    final reasons = await s.parseLog.failureReasons();
    if (!mounted) return;
    setState(() {
      _events = events.reversed.toList();
      _reasons = reasons;
      for (final e in _events) {
        _controllers.putIfAbsent(
          e.id,
          () => TextEditingController(
            text: revealHidden(
              maskSample('${e.title ?? ''}\n${e.body}'.trim()),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo chưa đọc được')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'Số và tên đã được che. Kiểm tra lại, sửa nếu còn thông tin '
            'riêng, rồi gửi cho người làm app để thêm mẫu đọc.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final e in _events)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${formatVnTime(e.postedAt)} · ${_reasons[e.id] ?? '?'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _controllers[e.id],
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text:
                                '[${_reasons[e.id] ?? '?'}]\n'
                                '${_controllers[e.id]!.text}',
                          ),
                        ),
                        child: const Text('Gửi mẫu lỗi'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
