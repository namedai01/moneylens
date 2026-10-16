import 'package:flutter/material.dart';

import '../format.dart';
import '../sync/sheets_gateway.dart';

/// Asks whether to bring back a Sheet left by an earlier install. Returns the
/// chosen spreadsheet id, or null to start a new Sheet. Not dismissible: a
/// stray back press would silently create a second Sheet.
Future<String?> pickRestoreSheet(BuildContext context, List<SheetFile> found) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _RestoreDialog(found)),
    );

class _RestoreDialog extends StatefulWidget {
  final List<SheetFile> found;

  const _RestoreDialog(this.found);

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  late String _selected = widget.found.first.id;

  @override
  Widget build(BuildContext context) {
    final several = widget.found.length > 1;
    return AlertDialog(
      title: const Text('Khôi phục dữ liệu?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            several
                ? 'Drive của bạn có ${widget.found.length} Sheet MoneyLens từ '
                      'lần cài trước. Chọn một để khôi phục giao dịch.'
                : 'Drive của bạn có Sheet MoneyLens từ lần cài trước. '
                      'Khôi phục giao dịch từ Sheet này?',
          ),
          const SizedBox(height: 12),
          for (final f in widget.found)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                f.id == _selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: Text(f.name.isEmpty ? 'MoneyLens' : f.name),
              subtitle: f.modifiedAt == null
                  ? null
                  : Text('Sửa lần cuối ${formatVnTime(f.modifiedAt!)}'),
              onTap: several ? () => setState(() => _selected = f.id) : null,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tạo Sheet mới'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Khôi phục'),
        ),
      ],
    );
  }
}
