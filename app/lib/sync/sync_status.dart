/// User-facing hint for a stored `last_sync_error` code.
String? describeSyncError(String? code) {
  if (code == null) return null;
  if (code == 'auth_required') {
    return 'Cần đăng nhập lại Google — bấm "Đồng bộ ngay".';
  }
  if (code == 'sheet_missing') {
    return 'Không tìm thấy Sheet (đã bị xoá hoặc mất quyền). Có thể tạo lại.';
  }
  return 'Đồng bộ chưa được (mạng?). App sẽ tự thử lại.';
}

Uri sheetUrl(String spreadsheetId) =>
    Uri.parse('https://docs.google.com/spreadsheets/d/$spreadsheetId');
