# Phase 0 — Spike bắt thông báo VCB Digibank — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App Flutter Android tối thiểu bắt thông báo VCB Digibank (kể cả khi app bị kill / sau reboot), hiện trên màn debug, xuất được mẫu để làm fixture cho parser.

**Architecture:** Project Flutter ở `app/`. Plugin `flutter_notification_listener_plus` gọi Dart background callback → lọc package → ghi vào log local (file JSON trong app documents). Màn debug đọc log. Code này **giữ lại** làm nền cho MVP (listener + màn trạng thái), không phải throwaway.

**Tech Stack:** Flutter 3.32 / Dart 3.8, `flutter_notification_listener_plus`, `path_provider`, `permission_handler`.

**Spec:** `docs/superpowers/specs/2026-10-16-moneylens-design.md` (mục 4, 6 "Màn hình trạng thái", 7, 8)

## Global Constraints

- Android package id: `vn.moneylens.app`. Tên app hiển thị: `MoneyLens`.
- minSdk 26 (Android 8). targetSdk theo mặc định Flutter 3.32.
- Chỉ lưu **nội dung** thông báo của package khớp VCB; package khác chỉ đếm tên package, không lưu nội dung.
- UI tiếng Việt.
- Không gửi gì lên mạng trong phase 0.

## Review Focus

1. App bị vuốt tắt khỏi recent apps → thông báo VCB đến sau đó vẫn phải được ghi. (Kiểm tra thủ công, Task 3.)
2. Máy reboot, chưa mở app → thông báo vẫn được ghi. (Task 3.)
3. 2–3 giao dịch liên tiếp trong vài giây → mỗi giao dịch 1 bản ghi, không bị gộp/mất. (Task 3 + test `appends multiple entries` ở Task 1.)
4. Thông báo cập nhật lại (cùng key, cùng nội dung) → log không phình vô hạn: giới hạn 50 bản ghi VCB gần nhất. (Test `caps at 50` ở Task 1.)
5. File log hỏng / rỗng → màn debug hiện rỗng, không crash. (Test `corrupt file returns empty` ở Task 1.)

---

### Task 1: Project Flutter + model + log local

**Files:**
- Create: `app/` (via `flutter create`)
- Create: `app/lib/capture/captured_notification.dart`
- Create: `app/lib/capture/capture_log.dart`
- Test: `app/test/capture/captured_notification_test.dart`, `app/test/capture/capture_log_test.dart`

**Interfaces:**
- Produces:
  - `class CapturedNotification { final String packageName; final String? title; final String? text; final String? bigText; final DateTime postedAt; String get body; Map<String,dynamic> toJson(); factory CapturedNotification.fromJson(Map<String,dynamic>); }` — `body` = `bigText` nếu không rỗng, ngược lại `text ?? ''`.
  - `bool isVcbPackage(String packageName)` — true nếu chứa `vcb` hoặc `vietcombank` (không phân biệt hoa thường).
  - `class CaptureLog { CaptureLog(File file); Future<void> record(CapturedNotification n); Future<List<CapturedNotification>> recentVcb({int limit = 20}); Future<Map<String,int>> packageCounts(); }` — `record` với package VCB thì lưu toàn bộ (giữ tối đa 50, bỏ cũ nhất); package khác chỉ tăng đếm.

- [ ] **Step 1: Cài công cụ & tạo project**

```bash
cd /Applications/Me/git-prjs/moneylens
flutter create --org vn.moneylens --project-name moneylens --platforms android,web,ios app
cd app && flutter pub add path_provider permission_handler flutter_notification_listener_plus
flutter doctor   # Android toolchain phải ✓ (cài Android SDK + adb nếu thiếu)
```

Sửa `app/android/app/build.gradle(.kts)`: `applicationId = "vn.moneylens.app"`, `minSdk = 26`. Label app trong `AndroidManifest.xml`: `MoneyLens`.

- [ ] **Step 2: Viết test thất bại**

```dart
// captured_notification_test.dart
test('body prefers bigText', () {
  final n = CapturedNotification(packageName: 'com.VCB', title: 't', text: 'short', bigText: 'long', postedAt: DateTime.utc(2026,10,16));
  expect(n.body, 'long');
});
test('body falls back to text', () { /* bigText: null → 'short'; bigText: '' → 'short' */ });
test('json roundtrip keeps postedAt to the millisecond', () { /* fromJson(toJson()) == fields */ });
test('isVcbPackage', () {
  expect(isVcbPackage('com.VCB'), isTrue);
  expect(isVcbPackage('com.vietcombank.digibank'), isTrue);
  expect(isVcbPackage('com.google.android.gm'), isFalse);
});

// capture_log_test.dart  (dùng File trong Directory.systemTemp.createTempSync())
test('stores vcb content, only counts others', ...);  // recentVcb().length==1, packageCounts()['com.zing']==1
test('appends multiple entries newest first', ...);   // 3 record → recentVcb() theo postedAt giảm dần
test('caps at 50', ...);                               // 60 record → file chứa 50, mất 10 cũ nhất
test('corrupt file returns empty', ...);               // file chứa 'not json' → recentVcb()==[] , packageCounts()=={}
```

- [ ] **Step 3: Chạy test → FAIL**

Run: `cd app && flutter test test/capture`
Expected: FAIL (chưa có class).

- [ ] **Step 4: Implement `CapturedNotification`, `isVcbPackage`, `CaptureLog`**

`CaptureLog` lưu 1 file JSON `{ "vcb": [...], "counts": {...} }`; đọc lỗi parse → coi như rỗng. Ghi atomically (ghi file tạm rồi `rename`).

- [ ] **Step 5: Chạy test → PASS**

Run: `cd app && flutter test test/capture`
Expected: PASS hết.

- [ ] **Step 6: Commit**

```bash
git add app && git commit -m "feat(app): scaffold Flutter app with notification capture log"
```

---

### Task 2: Nối listener + màn debug

**Files:**
- Create: `app/lib/capture/listener.dart`
- Create: `app/lib/status/status_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml` (khai báo service/permission theo README plugin)

**Interfaces:**
- Consumes: `CapturedNotification`, `CaptureLog`, `isVcbPackage` (Task 1).
- Produces:
  - `Future<void> initListener()` — khởi tạo plugin, đăng ký background callback `@pragma('vm:entry-point') void onNotificationEvent(...)` (top-level) chuyển event plugin → `CapturedNotification` → `CaptureLog.record`.
  - `Future<bool> hasNotificationAccess()`, `Future<void> openNotificationAccessSettings()`.
  - `Future<File> captureLogFile()` — `<app documents>/capture_log.json`.
  - `StatusScreen` widget.

- [ ] **Step 1: Wiring plugin theo README `flutter_notification_listener_plus`**

Làm đúng hướng dẫn của plugin cho: manifest service, khởi tạo, background callback, auto-start sau reboot. Callback top-level, có `@pragma('vm:entry-point')`. Map field của event plugin → `title`, `text`, `bigText` (nếu plugin có), `postTime` → `postedAt`.

- [ ] **Step 2: `StatusScreen`**

Nội dung (tiếng Việt), kéo xuống để refresh:
1. "Quyền đọc thông báo": ✅/❌ + nút "Mở cài đặt". Dưới nút là ghi chú: *"Nếu nút bật bị mờ: Cài đặt → Ứng dụng → MoneyLens → ⋮ → Cho phép cài đặt bị hạn chế."*
2. "Tối ưu pin": trạng thái từ `Permission.ignoreBatteryOptimizations` + nút xin quyền.
3. "Package đã thấy": danh sách `packageCounts()` (để tìm package id thật của VCB Digibank).
4. "20 thông báo VCB gần nhất": thời gian `dd/MM HH:mm:ss` + `title` + `body` nguyên văn, chữ chọn được (SelectableText).
5. Nút "Sao chép tất cả" → clipboard dạng JSON lines (`toJson` mỗi dòng).

`main.dart`: `MaterialApp(home: StatusScreen())`, gọi `initListener()` khi khởi động trên Android (`!kIsWeb && Platform.isAndroid`).

- [ ] **Step 3: Kiểm tra build**

Run: `cd app && flutter analyze && flutter test && flutter build apk --debug`
Expected: không lỗi analyze, test PASS, ra `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Smoke test trên máy thật**

Cài APK (`flutter install` hoặc gửi file). Cấp quyền (kể cả "Cho phép cài đặt bị hạn chế"). Nhờ ai chuyển 1.000đ hoặc tự chuyển → thông báo xuất hiện trong mục 4 trong ≤5 giây.

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): wire notification listener and status/debug screen"
```

---

### Task 3: Chạy thử trên máy thật + ghi kết quả (thủ công, 1–2 ngày)

**Files:**
- Create: `docs/spike/2026-10-vcb-notification-findings.md`
- Create: `supabase/functions/_shared/parser/fixtures/vcb_notif/*.txt` (mỗi file 1 thông báo, **đã che** số TK bằng `0000000000`-style giữ nguyên độ dài, tên người thành `NGUYEN VAN A`)

- [ ] **Step 1: Chạy kịch bản, mỗi kịch bản ít nhất 1 giao dịch**

| # | Kịch bản | Kỳ vọng |
|---|---|---|
| K1 | App đang mở | ghi nhận |
| K2 | Vuốt tắt app khỏi recent | ghi nhận |
| K3 | Reboot máy, **không** mở app | ghi nhận |
| K4 | Để máy idle qua đêm, giao dịch sáng hôm sau | ghi nhận |
| K5 | 3 giao dịch liên tiếp trong 1 phút | 3 bản ghi |
| K6 | Tiền **vào** (nhờ người khác chuyển, từ VCB và từ ngân hàng khác) | ghi nhận, lấy mẫu |

- [ ] **Step 2: Ghi `docs/spike/2026-10-vcb-notification-findings.md`**

Bắt buộc có: package id VCB Digibank; kết quả K1–K6 (đạt/không); định dạng số tiền (dấu phân cách); mẫu Ref tiền vào; field nào nằm ở `title` vs `text` vs `bigText`; hãng/đời máy + phiên bản Android; kết luận **giữ plugin** hay **chuyển Kotlin** (chuyển nếu K2, K3 hoặc K4 không đạt).

- [ ] **Step 3: Lưu fixture** — tối thiểu: `out_mbvcb_1.txt`, `out_mbvcb_2.txt`, `in_vcb_1.txt`, `in_other_bank_1.txt`, `non_transaction_1.txt` (thông báo VCB không phải biến động số dư, nếu có).

- [ ] **Step 4: Commit**

```bash
git add docs/spike supabase/functions/_shared/parser/fixtures
git commit -m "docs: record VCB notification spike findings and fixtures"
```

**Cổng quyết định:** K2–K4 không đạt → thử `smart_notification_listener` (lặp lại Task 2–3); vẫn không đạt → cập nhật Plan 1 Task 7 sang Kotlin `NotificationListenerService`.
