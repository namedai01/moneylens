import 'package:sqflite/sqflite.dart';

abstract final class SettingKeys {
  static const spreadsheetId = 'spreadsheet_id';
  static const googleEmail = 'google_email';
  static const lastSyncAt = 'last_sync_at';
  static const lastSyncError = 'last_sync_error';
  static const lastSyncedChangeAt = 'last_synced_change_at';
  static const onboardingDone = 'onboarding_done';
}

class SettingsStore {
  final Database db;

  SettingsStore(this.db);

  Future<String?> get(String key) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// A null [value] removes the key.
  Future<void> set(String key, String? value) async {
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
