import 'package:google_sign_in/google_sign_in.dart';

import '../app_services.dart';
import '../data/settings_store.dart';
import 'sheets_gateway.dart';
import 'sync_service.dart';

/// User-initiated Google Sheet actions shared by onboarding and status screen.
/// Each returns a short Vietnamese message to show, or null on success.
class BackupActions {
  final AppServices services;

  BackupActions(this.services);

  SettingsStore get _settings => services.settings;

  /// Sign in, create the spreadsheet if needed, then sync once.
  Future<String?> connect() async {
    final auth = services.auth;
    if (auth == null) return 'Đăng nhập Google không khả dụng.';
    try {
      final email = await auth.signIn();
      await _settings.set(SettingKeys.googleEmail, email);
      await services.sync.connect();
    } on GoogleSignInException catch (e) {
      return e.code == GoogleSignInExceptionCode.canceled
          ? 'Đã huỷ đăng nhập.'
          : 'Đăng nhập Google lỗi (${e.code.name}).';
    } on AuthRequired {
      return 'Chưa cấp quyền cho app tạo Sheet.';
    } catch (e) {
      return 'Không tạo được Sheet (${e.runtimeType}).';
    }
    return _message(await services.sync.sync());
  }

  /// Sync now; after an auth error, ask Google for consent first.
  Future<String?> syncNow() async {
    final auth = services.auth;
    if (auth != null &&
        await _settings.get(SettingKeys.lastSyncError) == 'auth_required') {
      try {
        await auth.headers(interactive: true);
      } on AuthRequired {
        return 'Cần đăng nhập lại Google.';
      }
    }
    return _message(await services.sync.sync());
  }

  Future<String?> recreateSheet() async {
    try {
      await services.sync.connect(recreate: true);
    } on AuthRequired {
      return 'Cần đăng nhập lại Google.';
    } catch (e) {
      return 'Không tạo được Sheet (${e.runtimeType}).';
    }
    return _message(await services.sync.sync());
  }

  /// Keeps local data and the spreadsheet id; revokes the app's Drive access.
  Future<void> signOut() async {
    await services.auth?.signOut();
    await _settings.set(SettingKeys.googleEmail, null);
  }

  static String? _message(SyncResult r) => switch (r) {
    SyncResult.ok => null,
    SyncResult.notConnected => 'Chưa kết nối Google Sheet.',
    SyncResult.authRequired => 'Cần đăng nhập lại Google.',
    SyncResult.sheetMissing => 'Không tìm thấy Sheet.',
    SyncResult.failed => 'Đồng bộ chưa được, sẽ thử lại sau.',
  };
}
