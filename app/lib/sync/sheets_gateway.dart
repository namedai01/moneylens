/// Writes to the user's own spreadsheet. The real implementation talks to the
/// Sheets API with a token that never leaves the phone.
abstract interface class SheetsGateway {
  /// Creates the spreadsheet with the transactions and summary tabs, writes
  /// [summary] into the summary tab, and returns its id.
  Future<String> createSpreadsheet({
    required String title,
    required List<List<Object?>> summary,
  });

  /// Clears the transactions tab and writes [rows] from A1.
  Future<void> replaceTransactions(
    String spreadsheetId,
    List<List<Object?>> rows,
  );

  /// Spreadsheets this app created, newest first. With the `drive.file`
  /// scope Drive lists nothing else, even across reinstalls.
  Future<List<SheetFile>> findSpreadsheets();

  /// The transactions tab as unformatted values, from A1.
  Future<List<List<Object?>>> readTransactions(String spreadsheetId);
}

class SheetFile {
  final String id;
  final String name;
  final DateTime? modifiedAt;

  const SheetFile({required this.id, required this.name, this.modifiedAt});
}

/// The user must sign in (again) interactively before syncing.
class AuthRequired implements Exception {}

/// The spreadsheet was deleted or is no longer accessible.
class SheetMissing implements Exception {}
