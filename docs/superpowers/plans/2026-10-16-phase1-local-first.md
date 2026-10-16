# Phase 1 — MoneyLens local-first MVP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Giao dịch VCB được bắt, parse và lưu hoàn toàn trên máy; dashboard trong app; đồng bộ một chiều lên Google Sheet trong Drive của chính người dùng; không có backend.

**Architecture:** Kotlin listener INSERT nguyên văn vào `capture.db` (Kotlin sở hữu). Dart mở `capture.db` read-only, parse bằng luật JSON (đóng gói sẵn + bản mới hơn tải từ GitHub), ghi `moneylens.db` (Dart sở hữu). Sync ghi đè tab "Giao dịch" của spreadsheet do app tạo, dùng token Google chỉ nằm trên máy (scope `drive.file`).

**Tech Stack:** Flutter 3.47 / Dart 3.13, Kotlin, `sqflite` (+ `sqflite_common_ffi` cho test), `http`, `google_sign_in` 7.x, `googleapis` (Sheets v4), `fl_chart`, `workmanager`, `share_plus`, Robolectric (test Kotlin).

**Spec:** `docs/superpowers/specs/2026-10-16-moneylens-local-first-design.md` (đọc kèm tài liệu cũ mục 6–8 khi spec trỏ tới).

## Global Constraints

- Android `applicationId` = `vn.moneylens.app`; namespace Kotlin `vn.moneylens.moneylens`. minSdk 26.
- **Không** gửi dữ liệu giao dịch / nội dung thông báo đi đâu ngoài Google Sheet của người dùng. Request mạng duy nhất khác: GET file luật.
- Token Google chỉ trên máy. Scope duy nhất: `https://www.googleapis.com/auth/drive.file`.
- Tiền VND kiểu `int`, `amount > 0`, chiều tách riêng. Không dùng `double`.
- Thời gian lưu epoch ms UTC. Gom tháng theo `Asia/Ho_Chi_Minh` = UTC+07:00 cố định (không DST).
- `capture.db`: chỉ Kotlin tạo/migrate/ghi. Dart chỉ mở read-only.
- Không lưu/ghi log nội dung thông báo của app không phải VCB. Không `print`/`Log` nội dung thông báo.
- UI tiếng Việt.
- Thêm package bằng `flutter pub add <tên>` (lấy bản mới nhất), không tự đoán version.
- Commit: một dòng Conventional Commits ngắn, **không** có dòng `Co-Authored-By` / attribution Claude.

## Review Focus

1. VCB đăng lại cùng một thông báo (cùng `postTime` + nội dung) → 1 raw, 1 giao dịch. (Task 1 `duplicate notification inserts once`, Task 5 `rerun is idempotent`.)
2. Cùng giao dịch đến 2 lần với `postTime` khác nhau (cùng `Ref`) → 1 giao dịch. (Task 3 `same ref twice keeps one`.)
3. Giao dịch 23:30 ngày 31/10 giờ VN (16:30Z) → thuộc tháng 10, không phải 11; 00:30 ngày 1/11 giờ VN (17:30Z ngày 31/10) → tháng 11. (Task 3 `month boundary uses +07:00`.)
4. Đổi "Ẩn khỏi thống kê" sau khi đã sync, hoặc sync chạy 2 lần liên tiếp → Sheet phản ánh trạng thái hiện tại, không trùng dòng. (Task 7 `sync writes full current state every time`.)
5. File luật trên mạng lỗi JSON / 404 / `version` thấp hơn / mất mạng → giữ luật đang dùng, không crash. (Task 6 `keeps current rules on bad remote`.)

---

### Task 1: Kotlin `capture.db` thay `capture_log.json`

**Files:**
- Create: `app/android/app/src/main/kotlin/vn/moneylens/moneylens/CaptureDb.kt`
- Modify: `app/android/app/src/main/kotlin/vn/moneylens/moneylens/VcbNotificationListener.kt`, `MainActivity.kt`, `CaptureLogStore.kt` (đổi tên thành `CapturedNotification.kt`, chỉ còn `CapturedNotification`, `isVcbPackage`)
- Modify: `app/android/app/build.gradle.kts` (Robolectric), `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/android/app/src/test/kotlin/vn/moneylens/moneylens/CaptureDbTest.kt` (thay `CaptureLogStoreTest.kt`)

**Interfaces:**
- Produces (schema Dart đọc ở Task 2 — giữ đúng tên cột):

```sql
CREATE TABLE raw_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL DEFAULT 'android_notif',
  package_name TEXT NOT NULL,
  title TEXT, text TEXT, big_text TEXT,
  posted_at INTEGER NOT NULL,      -- epoch ms
  received_at INTEGER NOT NULL,    -- epoch ms
  dedup_hash TEXT NOT NULL UNIQUE
);
CREATE TABLE listener_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
-- keys: 'connected_at', 'last_vcb_at' (epoch ms)
```

- `class CaptureDb(context: Context, name: String = "capture.db") : SQLiteOpenHelper` — version 1, bật WAL (`setWriteAheadLoggingEnabled(true)`); `companion fun get(context): CaptureDb` (singleton per process).
- `fun CaptureDb.insert(n: CapturedNotification, receivedAt: Long): Boolean` — `INSERT OR IGNORE`, true nếu dòng mới. Chỉ gọi cho package VCB.
- `fun CaptureDb.setState(key: String, value: Long)`
- `fun dedupHash(n: CapturedNotification): String` — sha256 hex của `"${packageName}\n${postedAt}\n${body}"`, `body` = `bigText` nếu khác rỗng, không thì `text ?: ""`.
- `fun CaptureDb.importLegacyLog(file: File): Int` — đọc mảng `vcb` của `capture_log.json`, insert từng mục, xoá file; file không có/hỏng → 0, vẫn xoá file hỏng.
- MethodChannel `moneylens/listener`: thêm `"captureDbPath"` (mở DB writable một lần để chắc file tồn tại, trả `getDatabasePath("capture.db").path`); giữ `"hasAccess"`, `"openSettings"`; bỏ `"logPath"`.
- Chỉ khi `BuildConfig.DEBUG`: `"debugInjectVcb"` nhận `{title, bigText}` → `insert` một `CapturedNotification(packageName = "debug.vcb", postedAt = now)`. Bản release trả `notImplemented`. Dùng để kiểm tay ở Task 8–9.

- [ ] **Step 1: Thêm Robolectric**: `testImplementation("org.robolectric:robolectric:<bản mới nhất>")`, `android.testOptions.unitTests.isIncludeAndroidResources = true`. Test class dùng `@RunWith(RobolectricTestRunner::class)`.
- [ ] **Step 2: Viết test fail** trong `CaptureDbTest`:
  - `duplicate notification inserts once` — insert cùng `n` 2 lần → lần 1 `true`, lần 2 `false`, `COUNT(*) = 1`.
  - `hash uses bigText when present` — `dedupHash` của n(text="a", bigText="b") == của n(text="x", bigText="b").
  - `stores all columns` — đọc lại dòng: `package_name`, `title`, `text`, `big_text`, `posted_at`, `received_at` đúng giá trị đưa vào.
  - `imports legacy log then deletes it` — file JSON 3 mục `vcb` (định dạng của `CaptureLogStore` cũ) → trả 3, file không còn; gọi lại → 0.
  - `corrupt legacy log is dropped` — file nội dung `"{"` → trả 0, file bị xoá.
  - `burst of inserts from threads keeps all` — 20 thread × 1 notification khác `postedAt` → `COUNT(*) = 20`.
- [ ] **Step 3: Chạy** `cd app/android && ./gradlew :app:testDebugUnitTest --tests '*CaptureDbTest*'` → FAIL (chưa có class).
- [ ] **Step 4: Implement** `CaptureDb.kt`. Listener: `onNotificationPosted` → nếu `isVcbPackage` thì `insert` + `setState("last_vcb_at", postTime)` trên executor hiện có; không VCB → bỏ qua hoàn toàn (bộ đếm package bỏ). `onListenerConnected` → `importLegacyLog(VcbNotificationListener.legacyLogFile(this))` rồi `setState("connected_at", now)`. `MainActivity` `"captureDbPath"` cũng gọi `importLegacyLog` trước khi trả path. Xoá `CaptureLogStore` class + test cũ, giữ `CapturedNotification`, `isVcbPackage` (đổi tên file thành `CapturedNotification.kt`).
- [ ] **Step 5: Manifest**: `<application android:allowBackup="false" android:fullBackupContent="false" ...>`.
- [ ] **Step 6: Chạy lại test** → PASS. `cd app && flutter build apk --debug` → exit 0.
- [ ] **Step 7: Commit** `feat(android): store VCB notifications in capture.db`

### Task 2: Dart đọc `capture.db` + màn debug chuyển sang DB

**Files:**
- Create: `app/lib/capture/raw_event.dart`, `app/lib/capture/raw_event_source.dart`
- Modify: `app/lib/capture/listener.dart`, `app/lib/status/status_screen.dart`
- Delete: `app/lib/capture/capture_log.dart`, `app/lib/capture/captured_notification.dart`, `app/test/capture/capture_log_test.dart`, `app/test/capture/captured_notification_test.dart`
- Test: `app/test/capture/raw_event_source_test.dart`, `app/test/support/capture_db_fixture.dart`

**Interfaces:**
- Consumes: schema Task 1.
- Produces:
  - `class RawEvent { final int id; final String packageName; final String? title, text, bigText; final DateTime postedAt /* UTC */; String get body; }` (`body` như `CapturedNotification.body` cũ).
  - `class RawEventSource { RawEventSource(Database db); static Future<RawEventSource> open(String path, {DatabaseFactory? factory}); Future<List<RawEvent>> after(int afterId, {int limit = 500}); Future<List<RawEvent>> byIds(List<int> ids); Future<List<RawEvent>> recent({int limit = 20}); Future<DateTime?> listenerConnectedAt(); Future<DateTime?> lastVcbAt(); }` — `open` dùng `readOnly: true`.
  - `listener.dart`: `Future<String> captureDbPath()` thay `captureLogFile()`.
  - Test helper `Future<String> createCaptureDb(String dir, List<Map<String, Object?>> rows)` — tạo file bằng **đúng SQL Task 1** (copy nguyên văn, kèm comment "phải khớp CaptureDb.kt").

- [ ] **Step 1: `flutter pub add sqflite` và `flutter pub add --dev sqflite_common_ffi`.** Test gọi `sqfliteFfiInit()` + `databaseFactoryFfi`.
- [ ] **Step 2: Viết test fail** `raw_event_source_test.dart`:
  - `after returns rows with id greater than cursor, ascending` — 3 dòng id 1..3, `after(1)` → id [2, 3].
  - `after respects limit` — `after(0, limit: 2)` → 2 dòng.
  - `recent returns newest posted first` — `recent(limit: 2)` → theo `posted_at` giảm dần.
  - `body prefers bigText` — `bigText: ''`, `text: 't'` → `body == 't'`.
  - `listener state reads epoch ms as UTC` — ghi `connected_at = DateTime.utc(2026,10,16,3).millisecondsSinceEpoch` → `listenerConnectedAt() == DateTime.utc(2026,10,16,3)`; không có key → `null`.
  - `open is read-only` — `db.insert(...)` qua connection của source ném `DatabaseException`.
- [ ] **Step 3: Chạy** `cd app && flutter test test/capture/raw_event_source_test.dart` → FAIL.
- [ ] **Step 4: Implement** hai file + `captureDbPath()`. `StatusScreen`: debug list đọc `RawEventSource.recent()`; bỏ khối đếm package; thêm 2 dòng "Listener kết nối lần cuối" / "Thông báo VCB gần nhất" (định dạng giờ VN).
- [ ] **Step 5: Chạy** `flutter test && flutter analyze` → PASS, không warning.
- [ ] **Step 6: Commit** `feat(app): read raw events from capture.db`

### Task 3: `moneylens.db` + Ledger

**Files:**
- Create: `app/lib/data/app_db.dart`, `app/lib/data/txn.dart`, `app/lib/data/ledger.dart`, `app/lib/data/parse_log.dart`, `app/lib/data/settings_store.dart`, `app/lib/data/vn_time.dart`
- Test: `app/test/data/ledger_test.dart`, `app/test/data/parse_log_test.dart`, `app/test/data/vn_time_test.dart`

**Interfaces:**
- Produces:
  - `Future<Database> openAppDb(String path, {DatabaseFactory? factory})` — version 1, schema:

```sql
CREATE TABLE accounts (id INTEGER PRIMARY KEY, bank_code TEXT, kind TEXT NOT NULL,
  name TEXT NOT NULL, last4 TEXT, created_at INTEGER NOT NULL, UNIQUE(bank_code, last4));
CREATE TABLE transactions (id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id),
  raw_event_id INTEGER UNIQUE, ref TEXT, source TEXT NOT NULL, occurred_at INTEGER NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0), direction TEXT NOT NULL CHECK (direction IN ('in','out')),
  balance_after INTEGER, description TEXT NOT NULL DEFAULT '', excluded INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(account_id, ref));
CREATE UNIQUE INDEX tx_noref_dedup ON transactions(account_id, occurred_at, amount, balance_after) WHERE ref IS NULL;
CREATE TABLE raw_parse (raw_event_id INTEGER PRIMARY KEY, parse_status TEXT NOT NULL
  CHECK (parse_status IN ('parsed','ignored','failed')), parse_error TEXT, rules_version INTEGER NOT NULL, parsed_at INTEGER NOT NULL);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
```

  (Không có `ref` + `balance_after` NULL → SQLite coi NULL khác nhau → vẫn ghi, đúng "ưu tiên không mất hơn không trùng".)
  - `enum Direction { incoming, outgoing }` + `String get db` (`'in'`/`'out'`) + `static Direction fromDb(String)`.
  - `class NewTxn { int accountId; int? rawEventId; String? ref; String source; DateTime occurredAt; int amount; Direction direction; int? balanceAfter; String description; }`
  - `class Txn` = các cột `transactions` + `String? accountLast4` (join) — tên field camelCase của cột.
  - `class MonthSummary { final String month /* 'YYYY-MM' */; final int income, expense; int get net => income - expense; }`
  - `class ContinuityGap { final Txn before, after; }`
  - `vn_time.dart`: `String monthKeyOf(DateTime t)`, `({DateTime start, DateTime end}) monthRangeUtc(String monthKey)`, `String vnIso(DateTime t)` → `2026-10-16T10:24:27+07:00`.
  - `class Ledger { Ledger(Database db, {DateTime Function()? clock}); Future<int> accountIdFor({required String bankCode, String? last4}); Future<bool> insertTxn(NewTxn t); Future<void> setExcluded(int txnId, bool excluded); Future<List<Txn>> monthTxns(String monthKey); Future<MonthSummary> monthSummary(String monthKey); Future<List<MonthSummary>> lastMonths(int n, {required DateTime now}); Future<List<Txn>> all(); Future<DateTime?> latestUpdate(); Future<int> changedSince(DateTime? t); Future<List<ContinuityGap>> continuityGaps(); }`
    - `accountIdFor` tạo account `kind='bank'`, `name='$bankCode ${last4 ?? ''}'.trim()` khi chưa có.
    - `insertTxn` → `false` khi vi phạm unique (dùng `ConflictAlgorithm.ignore`, kiểm số dòng).
    - `setExcluded` cập nhật `updated_at`.
    - `monthSummary` chỉ cộng `excluded = 0`.
    - `continuityGaps`: theo từng account, sắp `occurred_at`, xét cặp liên tiếp đều có `balance_after`: `before.balanceAfter ± after.amount != after.balanceAfter` → gap.
  - `class ParseLog { ParseLog(Database db); Future<int> maxRawId(); Future<void> record(int rawId, String status, {String? error, required int rulesVersion}); Future<List<int>> failedIds(); Future<int> failedCount(); }` — `record` là upsert.
  - `class SettingsStore { SettingsStore(Database db); Future<String?> get(String key); Future<void> set(String key, String? value); }` + hằng `SettingKeys.spreadsheetId, googleEmail, lastSyncAt, lastSyncError, lastSyncedChangeAt, onboardingDone`.

- [ ] **Step 1: Viết test fail**:
  - `vn_time_test`: `month boundary uses +07:00` — `monthKeyOf(DateTime.utc(2026,10,31,16,30)) == '2026-10'`, `monthKeyOf(DateTime.utc(2026,10,31,17,30)) == '2026-11'`; `monthRangeUtc('2026-11').start == DateTime.utc(2026,10,31,17)`; `vnIso(DateTime.utc(2026,10,16,3,24,27)) == '2026-10-16T10:24:27+07:00'`.
  - `ledger_test`:
    - `same ref twice keeps one` — insert 2 `NewTxn` cùng account + ref, `occurredAt` khác → `[true, false]`, `all().length == 1`.
    - `no ref, no balance keeps both` — 2 bản giống nhau, `ref: null`, `balanceAfter: null` → cả hai `true`.
    - `no ref, same balance dedups` — `ref: null`, cùng `occurredAt/amount/balanceAfter` → `[true, false]`.
    - `summary skips excluded` — in 1.000.000, out 300.000, out 200.000 (excluded) → `income 1000000, expense 300000, net 700000`.
    - `setExcluded bumps updatedAt` — clock giả tăng 1s → `latestUpdate()` đổi, `changedSince(trước đó) == 1`.
    - `lastMonths fills empty months with zeros` — dữ liệu chỉ tháng 08 và 10, `lastMonths(3, now: 2026-10-16)` → `['2026-08','2026-09','2026-10']`, tháng 09 = 0/0.
    - `continuity gap detected` — số dư 1.000.000 → out 100.000, số dư sau 850.000 → 1 gap; khi số dư sau 900.000 → 0 gap.
    - `accountIdFor reuses existing` — gọi 2 lần cùng (VCB, '1234') → cùng id.
  - `parse_log_test`: `maxRawId` rỗng = 0; `record` 2 lần cùng id → 1 dòng, status mới; `failedIds` chỉ trả `failed`.
- [ ] **Step 2: Chạy** `flutter test test/data` → FAIL.
- [ ] **Step 3: Implement** các file trên.
- [ ] **Step 4: Chạy** `flutter test test/data` → PASS.
- [ ] **Step 5: Commit** `feat(app): add local ledger database`

### Task 4: Luật parser JSON + bộ parse

**Files:**
- Create: `app/lib/parser/parser_rules.dart`, `app/assets/parser-rules.json`
- Modify: `app/pubspec.yaml` (khai báo asset)
- Test: `app/test/parser/parser_rules_test.dart`, `app/test/parser/fixtures/synthetic_vcb.json`

**Interfaces:**
- Consumes: `RawEvent`, `Direction`.
- Produces:
  - Định dạng file (bản `version: 1`, **tổng hợp** từ mẫu ở tài liệu cũ mục 8; Task 13 thay bằng luật thật):

```json
{
  "version": 1,
  "packagePattern": "vcb|vietcombank",
  "transactionHint": "Số dư TK|biến động số dư",
  "rules": [
    {
      "id": "vcb-balance-change",
      "kind": "transaction",
      "bankCode": "VCB",
      "pattern": "Số dư TK VCB (?<account>\\d+) (?<sign>[+-])(?<amount>[\\d.,]+) VND lúc (?<time>\\d{2}-\\d{2}-\\d{4} \\d{2}:\\d{2}:\\d{2})\\. Số dư (?<balance>[\\d.,]+) VND\\. Ref (?<ref>[A-Z0-9]+\\.[^.\\s]+)\\.?(?<desc>.*)",
      "timeFormat": "dd-MM-yyyy HH:mm:ss",
      "thousandsSeparator": ","
    },
    { "id": "otp-promo", "kind": "ignore", "pattern": "OTP|khuyến mãi|ưu đãi" }
  ]
}
```

  - Named group bắt buộc với `transaction`: `sign`, `amount`, `time`. Tuỳ chọn: `account`, `balance`, `ref`, `desc`. `timeFormat` chỉ cần hỗ trợ token `dd MM yyyy HH mm ss`; giờ hiểu là +07:00. Regex compile với `caseSensitive: false, dotAll: true, unicode: true`. `pattern` match trên `"${title ?? ''}\n${body}"`.
  - `class ParserRules { final int version; static ParserRules? tryParse(String json); ParseOutcome parse(RawEvent e); }` — `tryParse` trả `null` khi JSON sai / thiếu trường / regex không compile.
  - `sealed class ParseOutcome`; `class Parsed extends ParseOutcome { final ParsedTxn txn; }`; `class Ignored extends ParseOutcome { final String reason; }`; `class Failed extends ParseOutcome { final String reason; }`.
  - `class ParsedTxn { String bankCode; String? accountLast4; Direction direction; int amount; DateTime occurredAt /* UTC */; int? balanceAfter; String? ref; String description; }`
  - Thứ tự: package không khớp `packagePattern` → `Ignored('package')`; luật đầu tiên khớp thắng; không luật nào khớp → `transactionHint` khớp ? `Failed('no-rule')` : `Ignored('no-match')`; khớp `transaction` nhưng số/giờ không parse được → `Failed(<lý do>)`; `amount == 0` → `Failed('zero-amount')`.

- [ ] **Step 1: Viết fixture** `synthetic_vcb.json`: danh sách `{title, bigText, expect}` — ít nhất: tiền ra có `Ref MBVCB.<mã>.<nội dung>`, tiền vào, số có `,` hàng nghìn, nội dung nhiều dòng, OTP, thông báo đăng nhập không có số tiền.
- [ ] **Step 2: Viết test fail**:
  - `parses outgoing transfer` — `-1,500,000 VND lúc 16-10-2026 10:24:27 … Số dư 8,500,000` → outgoing, `amount 1500000`, `balanceAfter 8500000`, `occurredAt == DateTime.utc(2026,10,16,3,24,27)`, `accountLast4` = 4 số cuối, `ref == 'MBVCB.<mã>'`, `description` = phần sau.
  - `parses incoming` — dấu `+` → incoming.
  - `dot thousands separator when configured` — luật `thousandsSeparator: "."`, `1.500.000` → 1500000.
  - `ignored package` / `otp is ignored` / `unknown VCB balance text fails with no-rule` / `login notice is ignored`.
  - `bundled asset parses` — đọc `assets/parser-rules.json` từ đĩa → `tryParse != null`, `version >= 1`.
  - `tryParse rejects bad regex and missing version` → `null`.
- [ ] **Step 3: Chạy** `flutter test test/parser` → FAIL.
- [ ] **Step 4: Implement** `parser_rules.dart` + asset.
- [ ] **Step 5: Chạy** → PASS.
- [ ] **Step 6: Commit** `feat(app): add JSON-driven VCB parser`

### Task 5: Ingest

**Files:**
- Create: `app/lib/ingest/ingest.dart`
- Test: `app/test/ingest/ingest_test.dart`

**Interfaces:**
- Consumes: `RawEventSource`, `Ledger`, `ParseLog`, `ParserRules`.
- Produces: `class Ingest { Ingest({required RawEventSource source, required Ledger ledger, required ParseLog parseLog, required ParserRules Function() rules}); Future<IngestReport> run(); Future<IngestReport> reparseFailed(); }`, `class IngestReport { final int parsed, ignored, failed, duplicates; }`.
  - `run`: lấy `source.after(parseLog.maxRawId())` theo lô đến hết; mỗi raw: `Parsed` → `accountIdFor` + `insertTxn(rawEventId: raw.id, source: 'android_notif')` (trả `false` → `duplicates++`, vẫn ghi `parsed`); ghi `ParseLog.record(..., rulesVersion: rules().version)`. Mỗi raw trong một `db.transaction`.
  - `reparseFailed`: `source.byIds(parseLog.failedIds())` → parse lại bằng luật hiện tại, cập nhật `raw_parse`. Không sửa giao dịch đã có.
  - Một `Ingest` không chạy song song với chính nó: lần gọi thứ 2 khi đang chạy trả lại cùng `Future`.

- [ ] **Step 1: Viết test fail** (capture fixture Task 2 + app DB in-memory):
  - `parses new raws and advances cursor` — 3 raw (1 GD, 1 OTP, 1 lỗi) → report `1/1/1`, `maxRawId == 3`.
  - `rerun is idempotent` — gọi `run()` 2 lần → lần 2 report `0/0/0/0`, `ledger.all().length == 1`.
  - `same transaction from two raws counts once` — 2 raw cùng Ref, khác `posted_at` → `duplicates == 1`.
  - `reparseFailed uses new rules` — raw lỗi với luật v1, đổi sang luật v2 khớp → `parsed == 1`, `failedCount() == 0`.
  - `concurrent run calls share one pass` — `Future.wait([run(), run()])` → tổng giao dịch vẫn 1.
- [ ] **Step 2: Chạy** `flutter test test/ingest` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(app): ingest raw events into ledger`

### Task 6: Tải luật mới từ GitHub

**Files:**
- Create: `app/lib/parser/rules_repository.dart`
- Test: `app/test/parser/rules_repository_test.dart`

**Interfaces:**
- Consumes: `ParserRules.tryParse`.
- Produces: `const rulesUrl = 'https://raw.githubusercontent.com/namedai01/moneylens/main/app/assets/parser-rules.json';` và `class RulesRepository { RulesRepository({required Future<String> Function() loadBundled, required File cacheFile, required http.Client client, Uri? remote}); Future<ParserRules> load(); ParserRules get current; Future<bool> refresh(); }`
  - `load`: chọn bản `version` cao nhất giữa asset và `cacheFile` (cache hỏng → bỏ qua).
  - `refresh`: GET, timeout 10s, không gửi header/query nào ngoài mặc định; JSON hợp lệ **và** `version > current.version` → ghi `cacheFile`, đổi `current`, trả `true`; mọi trường hợp khác → `false`, không ném lỗi.

- [ ] **Step 1: `flutter pub add http`.** Test dùng `MockClient` của `package:http/testing.dart`.
- [ ] **Step 2: Viết test fail**:
  - `picks higher version between bundled and cache`.
  - `keeps current rules on bad remote` — lần lượt: body `"{"`, status 404, `version` bằng/thấp hơn, `ClientException` → `refresh() == false`, `current.version` không đổi, `cacheFile` không đổi.
  - `adopts newer remote and caches it` → `true`; `RulesRepository` mới đọc lại từ cache có `version` mới.
  - `request carries no user data` — `MockClient` kiểm `request.url == rulesUrl`, `request.method == 'GET'`, `request.body.isEmpty`.
- [ ] **Step 3: Chạy** `flutter test test/parser/rules_repository_test.dart` → FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Chạy** → PASS.
- [ ] **Step 6: Commit** `feat(app): fetch newer parser rules from GitHub`

### Task 7: Lõi sync (gateway giả)

**Files:**
- Create: `app/lib/sync/sheet_layout.dart`, `app/lib/sync/sheets_gateway.dart`, `app/lib/sync/sync_service.dart`
- Test: `app/test/sync/sheet_layout_test.dart`, `app/test/sync/sync_service_test.dart`, `app/test/support/fake_sheets_gateway.dart`

**Interfaces:**
- Consumes: `Ledger`, `SettingsStore`, `Ingest`, `vnIso`, `monthKeyOf`.
- Produces:
  - `sheet_layout.dart`:
    - `const txTabTitle = 'Giao dịch'; const summaryTabTitle = 'Tổng hợp';`
    - `const txNotice = 'Tab này do app MoneyLens ghi đè mỗi lần đồng bộ — đừng sửa ở đây, hãy tạo tab riêng để phân tích.';`
    - `const txHeader = ['ref', 'thời gian', 'tháng', 'chiều', 'số tiền', 'số dư sau', 'nội dung', 'ẩn khỏi thống kê', 'tài khoản', 'nguồn', 'id'];`
    - `List<List<Object?>> transactionRows(List<Txn> txns)` → `[[txNotice], txHeader, ...]`, dòng dữ liệu theo `occurredAt` tăng dần; `chiều` = `'vào'`/`'ra'`; `số tiền` âm khi ra; `ẩn khỏi thống kê` = `true/false`; `thời gian` = `vnIso`; `tháng` = `monthKeyOf`.
    - `List<List<Object?>> summaryRows()` — công thức `SUMIFS` theo cột `tháng` (C) và `ẩn khỏi thống kê` (H) = FALSE, cho cột thu (E>0) và chi (E<0); builder chọn bố cục, miễn mở Sheet thấy tổng thu/chi theo tháng.
  - `sheets_gateway.dart`: `abstract interface class SheetsGateway { Future<String> createSpreadsheet({required String title, required List<List<Object?>> summary}); Future<void> replaceTransactions(String spreadsheetId, List<List<Object?>> rows); }` + `class AuthRequired implements Exception {}` + `class SheetMissing implements Exception {}`. `createSpreadsheet` tạo 2 tab tên như trên, ghi `summary` vào tab Tổng hợp.
  - `sync_service.dart`: `enum SyncResult { ok, notConnected, authRequired, sheetMissing, failed }`; `class SyncService { SyncService({required Ledger ledger, required SettingsStore settings, required Ingest ingest, required SheetsGateway Function() gateway, DateTime Function()? clock}); Future<void> connect({bool recreate = false}); Future<SyncResult> sync(); }`
    - `connect({bool recreate = false})`: chưa có `spreadsheetId` hoặc `recreate` → `createSpreadsheet(title: 'MoneyLens', summary: summaryRows())`, lưu id mới. Đã có và không `recreate` → không tạo mới.
    - `sync`: `ingest.run()` → không có `spreadsheetId` → `notConnected` → `replaceTransactions(id, transactionRows(ledger.all()))` → lưu `lastSyncAt`, `lastSyncedChangeAt = ledger.latestUpdate()`, xoá `lastSyncError`. `AuthRequired` → lưu `lastSyncError='auth_required'`; `SheetMissing` → `'sheet_missing'`; lỗi khác → `'failed: <type>'` (không đưa nội dung giao dịch vào chuỗi lỗi). Single-flight như `Ingest`.

- [ ] **Step 1: Viết `FakeSheetsGateway`** ghi lại mọi lời gọi, có cờ `throwOnNext`.
- [ ] **Step 2: Viết test fail**:
  - `sheet_layout_test`: dòng 1 = `[txNotice]`, dòng 2 = `txHeader`; GD ra 300.000 → `số tiền == -300000`, `chiều == 'ra'`; `thời gian` dạng `+07:00`; sắp tăng dần.
  - `sync writes full current state every time` — 2 GD, sync → fake nhận 4 dòng; `setExcluded(id1, true)` rồi sync → lần gọi 2 chứa đủ 4 dòng, cột H của id1 = `true`; tổng số lần `replaceTransactions` = 2, không có lời gọi append.
  - `not connected skips network` — chưa `connect` → `notConnected`, fake 0 lời gọi.
  - `connect creates spreadsheet once` — gọi 2 lần → 1 lần `createSpreadsheet`; `connect(recreate: true)` → lần 2, `spreadsheetId` đổi.
  - `auth required is recorded` / `sheet missing is recorded` — `lastSyncError` đúng mã, `lastSyncAt` không đổi.
  - `sync runs ingest first` — raw mới trong capture fixture xuất hiện trên Sheet ngay lần sync đó.
- [ ] **Step 3: Chạy** `flutter test test/sync` → FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Chạy** → PASS.
- [ ] **Step 6: Commit** `feat(app): add one-way sheet sync core`

### Task 8: Composition root + Dashboard

**Files:**
- Create: `app/lib/app_services.dart`, `app/lib/dashboard/dashboard_screen.dart`, `app/lib/dashboard/month_chart.dart`, `app/lib/format.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/format_test.dart`, `app/test/dashboard/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: mọi class Task 2–7.
- Produces:
  - `class AppServices { static Future<AppServices> open({SheetsGateway Function()? gateway}); final RawEventSource source; final Ledger ledger; final ParseLog parseLog; final SettingsStore settings; final RulesRepository rules; final Ingest ingest; final SyncService sync; }` — `moneylens.db` trong `getDatabasesPath()`, `cacheFile` = `<app support>/parser-rules.json`. Task 9 truyền gateway thật; tới lúc đó gateway mặc định ném `AuthRequired`.
  - `String formatVnd(int amount, {bool signed = false})` → `1.500.000 ₫`, signed: `+1.500.000 ₫` / `−300.000 ₫`.
  - `DashboardScreen(services: AppServices)` — chọn tháng (trước/sau), 3 ô thu/chi/chênh lệch, biểu đồ cột 12 tháng (`fl_chart`), danh sách GD tháng (giờ VN, số tiền có dấu, nội dung); dòng `excluded` hiện mờ; nhấn giữ hoặc menu → "Ẩn khỏi thống kê"/"Tính lại vào thống kê". Badge "N thông báo chưa đọc được" khi `failedCount() > 0`, banner khi `continuityGaps()` không rỗng ("Có thể thiếu giao dịch giữa X và Y"). AppBar có nút sang `StatusScreen`.
  - `main.dart`: `AppServices.open()` → `rules.load()` → `ingest.run()` → `DashboardScreen`; `rules.refresh()` chạy nền, `true` → `ingest.reparseFailed()`.

- [ ] **Step 1: `flutter pub add fl_chart`.**
- [ ] **Step 2: Viết test fail**: `format_test` (`formatVnd(1500000) == '1.500.000 ₫'`, `formatVnd(300000, signed: true)` có dấu trừ); `dashboard_screen_test` với `AppServices` dựng từ DB in-memory: hiện đúng tổng tháng; nhấn "Ẩn khỏi thống kê" → tổng chi giảm; có raw `failed` → thấy badge.
- [ ] **Step 3: Chạy** `flutter test test/format_test.dart test/dashboard` → FAIL.
- [ ] **Step 4: Implement** (`AppServices.open` nhận override factory/path để test dựng được).
- [ ] **Step 5: Chạy** `flutter test && flutter analyze` → PASS.
- [ ] **Step 6: Kiểm tay** trên emulator: `flutter run`; màn trạng thái có nút "Chèn thông báo VCB giả" chỉ hiện khi `kDebugMode` (gọi `debugInjectVcb` với mẫu tổng hợp Task 4) → quay lại dashboard thấy giao dịch, tổng tháng đúng.
- [ ] **Step 7: Commit** `feat(app): add monthly dashboard`

### Task 9: Google Sign-In + Sheets gateway thật + onboarding

**Files:**
- Create: `app/lib/auth/google_auth.dart`, `app/lib/sync/google_sheets_gateway.dart`, `app/lib/onboarding/connect_screen.dart`, `docs/setup-google-cloud.md`
- Modify: `app/lib/app_services.dart`, `app/lib/main.dart`, `app/lib/status/status_screen.dart`
- Test: `app/test/sync/google_sheets_gateway_test.dart`

**Interfaces:**
- Consumes: `SheetsGateway`, `AuthRequired`, `SheetMissing`, `SettingKeys`.
- Produces:
  - `const driveFileScope = 'https://www.googleapis.com/auth/drive.file';`
  - `class GoogleAuth { Future<void> init(); Future<String?> signIn(); Future<void> signOut(); Future<Map<String, String>> headers({required bool interactive}); }` — bọc `google_sign_in` 7.x: `GoogleSignIn.instance.initialize(...)`, `authenticate()`, `authorizationClient.authorizationHeaders([driveFileScope], promptIfNecessary: interactive)`. Không lấy được header khi `interactive: false` → ném `AuthRequired`. **Không** gọi `authorizeServer` / không lấy server auth code.
  - `class GoogleSheetsGateway implements SheetsGateway { GoogleSheetsGateway(Future<Map<String, String>> Function() headers, {http.Client? inner}); }` — `SheetsApi` của `googleapis/sheets/v4`. `replaceTransactions`: `values.clear('$txTabTitle')` rồi `values.update(range: '$txTabTitle!A1', valueInputOption: 'RAW')`. `createSpreadsheet`: `spreadsheets.create` với 2 sheet, rồi `values.update` tab Tổng hợp với `USER_ENTERED`. HTTP 401/403 → `AuthRequired`; 404 → `SheetMissing`.
  - `ConnectScreen` — hiện khi `onboardingDone` chưa set: giải thích 3 dòng (dữ liệu ở máy; Sheet trong Drive của bạn; app chỉ thấy file nó tạo), nút "Kết nối Google Sheet" (`signIn` → `sync.connect()` → `sync.sync()`), nút "Để sau". Cả hai set `onboardingDone`.
  - `StatusScreen` thêm mục "Sao lưu Google Sheet": email, lần sync gần nhất, số thay đổi chưa sync (`ledger.changedSince(lastSyncedChangeAt)`), lỗi gần nhất (mã → câu tiếng Việt), nút "Đồng bộ ngay", "Mở Sheet" (URL `https://docs.google.com/spreadsheets/d/<id>`), "Đăng xuất", và "Tạo lại Sheet" (`sync.connect(recreate: true)` rồi `sync()`) khi lỗi `sheet_missing`. Chưa từng sync → dòng đỏ "Chưa có bản sao lưu — gỡ app là mất dữ liệu".

- [ ] **Step 1: `flutter pub add google_sign_in googleapis url_launcher`.** Đọc README `google_sign_in` 7.x trên pub.dev, xác nhận tên API ở trên; lệch thì theo README, giữ nguyên interface `GoogleAuth`.
- [ ] **Step 2: Viết `docs/setup-google-cloud.md`** (người làm: chủ dự án): tạo project → bật Google Sheets API → OAuth consent screen External, scope `drive.file`, **Publish to Production** → OAuth client Android `vn.moneylens.app` + SHA-1 debug (`cd app/android && ./gradlew signingReport`) và SHA-1 release (Task 12) → nếu plugin yêu cầu `serverClientId` thì tạo thêm client loại Web **chỉ để lấy client ID**, không tạo/lưu secret ở đâu. Ghi lại client ID vào `app/lib/auth/google_config.dart` (không phải bí mật).
- [ ] **Step 3: Viết test fail** `google_sheets_gateway_test` bằng `MockClient`: `replaceTransactions` gửi `:clear` rồi `PUT values/Giao dịch!A1?valueInputOption=RAW` với đúng body; 401 → `AuthRequired`; 404 → `SheetMissing`; mọi request đi tới `sheets.googleapis.com` và mang header `Authorization` từ hàm `headers`.
- [ ] **Step 4: Chạy** `flutter test test/sync/google_sheets_gateway_test.dart` → FAIL.
- [ ] **Step 5: Implement** các file; `AppServices.open` dùng `GoogleSheetsGateway(() => auth.headers(interactive: false))`; nút "Đồng bộ ngay" gọi `headers(interactive: true)` một lần trước khi `sync()` khi lỗi trước đó là `auth_required`.
- [ ] **Step 6: Chạy** `flutter test && flutter analyze` → PASS.
- [ ] **Step 7: Kiểm tay** trên máy/emulator có Google account: Kết nối → Drive có file "MoneyLens" với 2 tab; tab Giao dịch có dòng ghi chú + header + giao dịch; đổi "Ẩn khỏi thống kê" → Đồng bộ ngay → cột H đổi, số dòng không tăng; tab Tổng hợp ra đúng tổng; xoá file trên Drive → Đồng bộ → thấy "Tạo lại Sheet". Ghi kết quả vào commit body nếu có điều bất thường.
- [ ] **Step 8: Commit** `feat(app): sync to user's Google Sheet`

### Task 10: Gửi mẫu lỗi (đã che)

**Files:**
- Create: `app/lib/report/mask.dart`, `app/lib/report/failed_events_screen.dart`
- Modify: `app/lib/dashboard/dashboard_screen.dart` (badge mở màn này)
- Test: `app/test/report/mask_test.dart`

**Interfaces:**
- Consumes: `ParseLog.failedIds`, `RawEventSource.byIds`.
- Produces: `String maskSample(String text)`; `FailedEventsScreen(services)` — liệt kê raw `failed`, mỗi mục hiện bản đã che trong `TextField` cho người dùng sửa, nút "Gửi mẫu lỗi" → `Share.share(text)` (`share_plus`). Không có đường gửi nào khác.

- [ ] **Step 1: `flutter pub add share_plus`.**
- [ ] **Step 2: Viết test fail** `mask_test` trên mẫu tổng hợp Task 4:
  - không còn chuỗi ≥ 3 chữ số liên tiếp của bản gốc (số TK, số tiền, số dư, mã Ref);
  - giữ dấu phân cách và độ dài nhóm số (`1,500,000` → `9,999,999`) để còn viết được regex;
  - giữ nguyên `Số dư TK VCB`, `VND`, `lúc`, `Ref`, dấu `+`/`-`, định dạng ngày giờ (chữ số ngày giờ cũng bị che nhưng giữ `dd-MM-yyyy HH:mm:ss`);
  - tên người (từ viết HOA ≥ 2 chữ cái trong phần nội dung sau `Ref`) → `XXXX`; từ thường như `chuyen tien` giữ nguyên.
- [ ] **Step 3: Chạy** `flutter test test/report` → FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Chạy** `flutter test && flutter analyze` → PASS.
- [ ] **Step 6: Commit** `feat(app): share masked samples of unparsed notifications`

### Task 11: Sync tự động

**Files:**
- Create: `app/lib/sync/auto_sync.dart`, `app/lib/sync/background.dart`
- Modify: `app/lib/main.dart`, `app/lib/dashboard/dashboard_screen.dart`
- Test: `app/test/sync/auto_sync_test.dart`

**Interfaces:**
- Consumes: `AppServices`, `SyncService`, `RulesRepository.refresh`.
- Produces:
  - `class AutoSync { AutoSync(Future<SyncResult> Function() sync, {Duration debounce = const Duration(minutes: 1)}); void onAppResumed(); void onLocalChange(); void dispose(); }` — `onAppResumed` sync ngay; `onLocalChange` gộp trong `debounce`.
  - `background.dart`: `@pragma('vm:entry-point') void callbackDispatcher()` cho `workmanager`; task `'moneylens.periodicSync'`, `frequency: Duration(hours: 6)`, `constraints: Constraints(networkType: NetworkType.connected)`, `ExistingPeriodicWorkPolicy.keep`. Trong job: `AppServices.open()` → `rules.load()` → `rules.refresh()` (→ `reparseFailed` nếu true) → `sync.sync()`. Mọi lỗi nuốt, trả `true` (lỗi đã nằm trong `lastSyncError`).
  - Khi `lastSyncError == 'auth_required'`: dashboard + màn trạng thái hiện banner "Mở app và bấm Đồng bộ ngay để đăng nhập lại Google". (Claude quyết: banner trong app, không thêm thông báo hệ thống.)
  - Kotlin **không** kích hoạt job nào (spec mục 6, phương án A).

- [ ] **Step 1: `flutter pub add workmanager`** + cấu hình Android theo README.
- [ ] **Step 2: Viết test fail** `auto_sync_test` (dùng `fake_async`): 3 lần `onLocalChange` trong 30s → sync 1 lần sau 1 phút; `onAppResumed` → sync ngay; `dispose` huỷ hẹn giờ.
- [ ] **Step 3: Chạy** `flutter test test/sync/auto_sync_test.dart` → FAIL.
- [ ] **Step 4: Implement**; `main.dart` gắn `AutoSync` vào `WidgetsBindingObserver` resume + sau mỗi `setExcluded` / mỗi lần `ingest.run()` có `parsed > 0`; đăng ký periodic task lúc khởi động.
- [ ] **Step 5: Chạy** `flutter test && flutter analyze` → PASS.
- [ ] **Step 6: Kiểm tay**: `adb shell cmd jobscheduler run -f vn.moneylens.app <job id>` (lấy id bằng `adb shell dumpsys jobscheduler | grep moneylens`) khi app đã bị vuốt tắt → `lastSyncAt` trên màn trạng thái đổi, **hoặc** thấy banner `auth_required` (rủi ro spec mục 9.1 — cả hai đều đạt, ghi kết quả nào xảy ra vào commit body).
- [ ] **Step 7: Commit** `feat(app): auto sync on resume, on change and every 6h`

### Task 12: Ký release + APK + hướng dẫn cài

**Files:**
- Modify: `app/android/app/build.gradle.kts`
- Create: `docs/install-guide.md`

**Interfaces:**
- Consumes: SHA-1 release đăng ký ở `docs/setup-google-cloud.md`.

- [ ] **Step 1: Signing config** đọc `app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); file không có → build release dùng debug key như hiện tại và in cảnh báo Gradle. `key.properties` + `*.jks` đã nằm trong `.gitignore` gốc — kiểm `git check-ignore app/android/key.properties`.
- [ ] **Step 2: Chủ dự án tạo keystore** (`keytool -genkey -v -keystore ~/moneylens-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias moneylens`), cất ngoài repo, thêm SHA-1 release vào OAuth client Android.
- [ ] **Step 3: Build** `cd app && flutter build apk --release` → exit 0; `apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk` → SHA-1 khớp keystore release.
- [ ] **Step 4: Viết `docs/install-guide.md`** (người đọc: 5 người trong nhóm, không rành kỹ thuật): tải APK → cho phép cài nguồn không xác định → mở app → Thông tin ứng dụng → ⋮ → "Cho phép cài đặt bị hạn chế" (Android 13+) → cấp quyền đọc thông báo → tắt tối ưu pin (Xiaomi/Oppo/Samsung) → VCB Digibank bật "Nhận thông báo từ ngân hàng" → Kết nối Google Sheet. Một đoạn "Dữ liệu của bạn ở đâu": máy + Sheet của bạn; chủ dự án không xem được; gỡ app khi chưa sync là mất.
- [ ] **Step 5: Kiểm tay** trên máy thật bằng APK release: cài, đăng nhập Google thành công (sai SHA-1 sẽ lỗi `DEVELOPER_ERROR` ngay bước này).
- [ ] **Step 6: Commit** `build(android): release signing and install guide`

### Task 13: Luật parser thật (chặn bởi phase 0 Task 3)

**Điều kiện bắt đầu:** phase 0 Task 3 xong trên máy thật, có ≥ 5 mẫu (tiền vào, tiền ra, tiền vào từ NH khác, nhiều GD liên tiếp) và package id VCB Digibank chính xác.

**Files:**
- Modify: `app/assets/parser-rules.json`, `app/lib/capture/raw_event.dart` / Kotlin `isVcbPackage` (khớp chính xác package id)
- Create: `app/test/parser/fixtures/real_vcb_masked.json`
- Modify: `app/test/parser/parser_rules_test.dart`

- [ ] **Step 1: Lấy mẫu** từ màn debug, che bằng `maskSample` (Task 10) + kiểm mắt, lưu vào `real_vcb_masked.json` kèm `expect`.
- [ ] **Step 2: Viết test fail** `real samples parse as expected` chạy qua toàn bộ fixture.
- [ ] **Step 3: Chạy** `flutter test test/parser` → FAIL.
- [ ] **Step 4: Sửa luật** (tăng `version` lên 2), sửa `isVcbPackage` (Kotlin) thành so khớp package id chính xác; `packagePattern` trong luật cũng vậy.
- [ ] **Step 5: Chạy** `flutter test` + `cd app/android && ./gradlew :app:testDebugUnitTest` → PASS.
- [ ] **Step 6: Commit + push `main`** `feat(app): parser rules from real VCB samples` — sau khi lên `main`, máy đã cài tự lấy luật v2 ở lần mở app kế tiếp (Task 6), không cần APK mới.
