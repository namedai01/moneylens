import 'package:google_sign_in/google_sign_in.dart';

import '../sync/sheets_gateway.dart';
import 'google_config.dart';

/// Only lets the app see files it created itself.
const driveFileScope = 'https://www.googleapis.com/auth/drive.file';

/// Google sign-in on the phone. Access tokens stay inside Google Play
/// services and this process; no server auth code is ever requested.
class GoogleAuth {
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  Future<void>? _init;

  Future<void> init() => _init ??= _signIn.initialize(
    serverClientId: googleServerClientId.isEmpty ? null : googleServerClientId,
  );

  /// Interactive sign-in plus consent for [driveFileScope]; returns the email.
  Future<String?> signIn() async {
    await init();
    final account = await _signIn.authenticate();
    await account.authorizationClient.authorizeScopes([driveFileScope]);
    return account.email;
  }

  /// Signs out and revokes the app's access to the user's Drive.
  Future<void> signOut() async {
    await init();
    await _signIn.disconnect();
  }

  /// Authorization headers for Sheets. With [interactive] false, throws
  /// [AuthRequired] instead of showing any UI.
  Future<Map<String, String>> headers({required bool interactive}) async {
    await init();
    try {
      final h = await _signIn.authorizationClient.authorizationHeaders([
        driveFileScope,
      ], promptIfNecessary: interactive);
      if (h == null) throw AuthRequired();
      return h;
    } on GoogleSignInException {
      throw AuthRequired();
    }
  }
}
