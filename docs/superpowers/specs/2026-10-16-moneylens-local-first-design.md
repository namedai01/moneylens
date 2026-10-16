# MoneyLens — Thiết kế local-first (thay kiến trúc Supabase)

Ngày: 2026-10-16 · Tác giả: dainguyen (+ Claude)

Tài liệu này **thay thế** mục 3–5, 7, 8b, 8c, 10, 11 của [`2026-10-16-moneylens-design.md`](2026-10-16-moneylens-design.md). Phần còn giá trị của tài liệu cũ (mẫu tin VCB ở mục 8, quy tắc parse ở mục 6, rủi ro Android ở mục 7) được nhắc lại hoặc trỏ tới ở đây. Plan [`phase1-mvp`](../plans/2026-10-16-phase1-mvp.md) (Supabase) bị bỏ.

## 1. Lý do đổi

Chủ dự án lo về **quyền riêng tư dữ liệu ngân hàng của từng người** trong nhóm. Kiến trúc cũ gửi nguyên văn mọi thông báo lên Supabase do chủ dự án vận hành → chủ dự án đọc được giao dịch của cả nhóm.

Kiến trúc mới: **không có server nào giữ dữ liệu giao dịch, kể cả server của chủ dự án.** Mỗi người giữ dữ liệu trên điện thoại của mình và sao lưu sang Google Sheet trong tài khoản Google của chính họ.

## 2. Goals / Non-goals / Anti-goals

**Goals (MVP)**
- Android: tự bắt thông báo biến động số dư VCB Digibank, ghi nhận giao dịch kể cả khi app không mở (đã làm ở phase 0: `VcbNotificationListener`).
- Lưu toàn bộ dữ liệu **trên máy** (SQLite). App dùng được đầy đủ khi không có mạng và khi chưa đăng nhập Google.
- Đăng nhập bằng Google (Gmail) để **đồng bộ một chiều app → Google Sheet** của chính người dùng. Có nút "Đồng bộ ngay" + đồng bộ tự động.
- Dashboard trong app: tổng thu, tổng chi, chênh lệch theo tháng; danh sách giao dịch; biểu đồ nhiều tháng; nút "Ẩn khỏi thống kê" (`excluded`).
- Xem trên máy tính = mở Google Sheet (không làm web).
- Sửa parser khi VCB đổi mẫu tin **mà không phải phát APK mới**.
- ~5 người dùng, mỗi người cài APK, dữ liệu của ai nằm ở máy + Sheet của người đó.

**Non-goals (MVP)**
- Backend của riêng dự án (không Supabase, không server). Heartbeat / thống kê sử dụng: làm sau nếu cần, và khi làm thì chỉ gửi thời điểm, không gửi giao dịch.
- Flutter web, iOS.
- Đồng bộ hai chiều (sửa trên Sheet không về app).
- **Khôi phục từ Sheet sang máy mới** — làm ngay sau MVP. MVP phải ghi đủ cột lên Sheet để sau này khôi phục được (mục 6).
- Ngân hàng khác, tiền mặt nhập tay, danh mục, ngân sách — schema để sẵn chỗ như tài liệu cũ.
- Danh sách email được phép dùng app (không có dữ liệu chung nên không có gì để chặn).
- Nguồn email Gmail (V2) — cần thiết kế lại cho kiến trúc này (mục 10).

**Anti-goals (làm vậy là hỏng dù "chạy được")**
- **Bất kỳ dữ liệu giao dịch / nội dung thông báo nào rời khỏi máy, trừ khi đi thẳng vào Google Sheet của chính người dùng, hoặc do người dùng tự bấm gửi (mục 7).**
- **Token có quyền truy cập Sheets/Drive nằm ở bất kỳ đâu ngoài điện thoại của người dùng.** Không có bước đổi OAuth code ở server.
- App có quyền đọc file Drive/Sheet mà app không tạo ra.
- Lưu username/password ngân hàng, cào iBanking.
- Mất giao dịch âm thầm (parser không hiểu, đồng bộ lỗi, listener chết) mà người dùng không biết.
- Đếm trùng một giao dịch.

## 3. Ràng buộc

- Flutter (Dart) + Kotlin cho phần nền Android. Chủ dự án đang học Flutter.
- Miễn phí: Google Cloud project (OAuth + Sheets API) gói miễn phí, file luật parser host tĩnh trên GitHub.
- Tiền VND, số nguyên. Gom tháng theo `Asia/Ho_Chi_Minh`.
- Phân phối APK cài tay, **một keystore release cố định** (OAuth client Android gắn với package name + SHA-1 chứng chỉ ký; đổi keystore = đăng nhập Google hỏng).
- Rủi ro Android giữ nguyên từ tài liệu cũ mục 7: Restricted Settings (Android 13+), ẩn thông báo OTP (Android 15+), tối ưu pin hãng.

## 4. Kiến trúc

```
┌──────────────────────── Điện thoại người dùng ────────────────────────┐
│                                                                        │
│  VcbNotificationListener (Kotlin, hệ thống bind)                       │
│    lọc package VCB → INSERT vào capture.db (append-only, Kotlin sở hữu)│
│                                   │                                    │
│                                   v (Dart mở read-only)                │
│  Dart: Ingest                                                          │
│    đọc raw mới → parse bằng luật (JSON) → ghi moneylens.db             │
│                                   │                                    │
│  Dart: UI (dashboard, trạng thái, debug)   Dart: Sync                  │
│                                   │          ghi đè tab "Giao dịch"    │
│  Google Sign-In: token Sheets CHỈ ở đây      │                         │
└──────────────────────────────────────────────┼─────────────────────────┘
          ▲ GET (không gửi gì)                  │ HTTPS, token của user
          │                                     v
  parser-rules.json (GitHub, tĩnh)     Google Sheet trong Drive của user
```

### Quyết định chính

| Quyết định | Lý do |
|---|---|
| **Hai file SQLite tách chủ sở hữu.** `capture.db`: Kotlin tạo + migrate, chỉ có bảng `raw_events`, chỉ INSERT. `moneylens.db`: Dart sở hữu, mọi bảng còn lại. Dart mở `capture.db` read-only. | Listener chạy khi không có Flutter engine, phải tự ghi được. Một bên sở hữu một schema → không có hai nơi cùng migrate một file. |
| **Parse ở Dart, trên máy.** Kotlin chỉ bắt và lưu nguyên văn. | Parser test bằng fixture Dart; chủ dự án học Flutter. Raw giữ nguyên văn → parse lại được khi luật đổi. |
| **Luật parser = file JSON tĩnh** (regex có named group + định dạng số), host trên GitHub repo của dự án. App có bản đóng gói sẵn; tải bản mới khi mở app / khi sync, dùng bản `version` cao hơn. | Sửa mẫu tin không cần APK mới, không cần backend. Request chỉ là GET, không gửi dữ liệu người dùng. |
| **Google Sign-In trên máy, scope `drive.file`** (không dùng `spreadsheets`). App tự tạo Sheet → chỉ đụng được Sheet đó. | Anti-goal về token + quyền. `drive.file` là scope không nhạy cảm → publish OAuth consent screen ở chế độ **Production** mà không cần Google xác minh (chế độ Testing làm refresh token hết hạn sau 7 ngày). |
| **Sync = ghi đè toàn bộ tab "Giao dịch"** mỗi lần (clear + write), không append. | Không có upsert trên Sheets. Ghi đè thì idempotent: chạy lại không trùng, đổi `excluded` sau khi sync vẫn lên đúng. Vài nghìn dòng/năm → một request là đủ. |
| Không có backend. | Mục 1. |

## 5. Dữ liệu trên máy

**`capture.db` (Kotlin)**
- `raw_events`: `id INTEGER PK, source ('android_notif'), package_name, title, text, big_text, posted_at (epoch ms), received_at, dedup_hash UNIQUE`.
- `dedup_hash` = sha256(package + posted_at + (big_text ?: text)). INSERT OR IGNORE.
- Thay `capture_log.json` của phase 0: màn debug đọc 20 dòng mới nhất từ đây. Bộ đếm thông báo của app khác: không còn cần, bỏ.
- **Migrate một lần (Claude quyết):** lần đầu `capture.db` được tạo, Kotlin import các mục VCB trong `capture_log.json` (nếu có) vào `raw_events` rồi xoá file. Mục đã rơi khỏi giới hạn 50 thì mất, chấp nhận.

**`moneylens.db` (Dart)**
- `raw_parse`: `raw_event_id PK, parse_status (parsed|ignored|failed), parse_error, rules_version, parsed_at`. Raw chưa có dòng ở đây = chưa xử lý.
- `accounts`: `id, bank_code, kind (bank|cash), name, last4, created_at`. Tạo tự động khi gặp số TK mới.
- `transactions`: `id, account_id, raw_event_id NULL, ref NULL, source, occurred_at, amount (>0), direction (in|out), balance_after NULL, description, excluded (default false), created_at, updated_at`. `UNIQUE(account_id, ref)`; không có `ref` → fallback `(account_id, occurred_at, amount, balance_after)` như tài liệu cũ mục 8b.
- `settings` (key/value): `spreadsheet_id`, `google_email`, `rules_version`, `last_sync_at`, `last_sync_error`, `last_synced_change_at`.

**Bảo vệ dữ liệu trên máy (Claude quyết)**
- Không mã hoá thêm (SQLCipher): dựa vào sandbox app + mã hoá theo file của Android.
- **Tắt Android Auto Backup** cho cả hai DB (`allowBackup=false` hoặc `dataExtractionRules` loại trừ), để dữ liệu chỉ đi đúng một đường: Sheet do người dùng chọn.
- Gỡ app = mất dữ liệu trên máy. Màn trạng thái nói rõ điều này nếu chưa từng sync.

## 6. Hành vi

**Bắt thông báo** — như tài liệu cũ mục 6. Chỉ package VCB; không lưu gì của app khác.

**Ingest / parse**
- Chạy khi: mở app, quay lại app (resume), trước mỗi lần sync, và sau khi tải được luật mới.
- Raw chưa xử lý → áp luật. Không khớp luật nào và trông như biến động số dư → `failed`. Không phải biến động số dư → `ignored`.
- Luật mới (`version` cao hơn): parse lại mọi raw `failed`. Không đụng giao dịch đã có.
- Kiểm tra liên tục số dư (tài liệu cũ mục 8b) chạy local, hiện cảnh báo trong app.

**Google Sign-In + Sheet**
- Lần đầu: màn chào có nút "Kết nối Google Sheet" và "Để sau". Bỏ qua vẫn dùng app bình thường; màn trạng thái nhắc "Chưa có bản sao lưu".
- Kết nối xong → app tạo spreadsheet `MoneyLens` trong Drive của người dùng, lưu `spreadsheet_id`. Sheet bị xoá/không truy cập được → báo lỗi, cho tạo lại.
- Đăng xuất: xoá token, giữ dữ liệu local và `spreadsheet_id`.

**Cấu trúc Sheet**
- Tab **"Giao dịch"** — app sở hữu, ghi đè mỗi lần sync. Dòng 1 ghi chú "Tab này do app ghi đè, đừng sửa — tạo tab riêng để phân tích". Cột (đủ để khôi phục sau này): `ref, thời gian (ISO, +07:00), tháng (YYYY-MM), chiều, số tiền (âm nếu chi), số dư sau, nội dung, ẩn khỏi thống kê, tài khoản (last4), nguồn, id`.
- Tab **"Tổng hợp"** — app tạo **một lần** khi tạo Sheet, dùng công thức (`SUMIFS` theo cột tháng, bỏ dòng ẩn). Sau đó người dùng tự sửa thoải mái, app không đụng lại.
- Không đưa nguyên văn thông báo (raw) lên Sheet.

**Đồng bộ**
- **Độ trễ chấp nhận được (chủ dự án chốt):** Sheet cập nhật khi người dùng mở app, hoặc chậm nhất ~6h. **Không** cần lên Sheet trong vài phút khi app đang tắt. Kotlin không kích hoạt job nào khi có thông báo mới; nó chỉ INSERT.
- Kích hoạt: nút "Đồng bộ ngay"; khi mở / quay lại app; khi app đang mở mà có giao dịch mới hoặc đổi `excluded` (gộp trong ~1 phút); định kỳ ~6h bằng WorkManager khi có mạng (job này chạy ingest + sync).
- Một lần sync: ingest → đọc mọi transaction → clear tab "Giao dịch" → ghi toàn bộ → lưu `last_sync_at`. Thất bại → lưu `last_sync_error`, lần sau thử lại.
- Màn hình hiện: lần sync gần nhất, số thay đổi chưa sync (`updated_at > last_synced_change_at`), lỗi gần nhất.
- Sync nền không lấy được token im lặng (cần người dùng bấm lại) → không hỏng gì, hiện thông báo "Mở app để đồng bộ". Xem rủi ro mục 9.

**Dashboard** — như tài liệu cũ mục 6 (tháng, danh sách, ẩn khỏi thống kê, biểu đồ 6–12 tháng, badge khi có `failed`), chỉ trên app Android.

**Màn trạng thái** — như tài liệu cũ mục 6, đổi phần "đang chờ gửi" thành trạng thái sync. Thêm: lần cuối listener kết nối (`onListenerConnected`) và thời điểm thông báo VCB gần nhất, thay cho heartbeat server.

## 7. Báo lỗi parser mà không lộ dữ liệu

Chủ dự án không còn thấy raw của người khác. Thay bằng:
- Raw `failed` có nút **"Gửi mẫu lỗi"**: app hiện nội dung đã **che sẵn** (số TK, số dư, tên người, số tiền → ký tự thay thế, giữ nguyên cấu trúc câu), người dùng xem/sửa, rồi gửi qua Android share sheet (Zalo, email…). App không tự gửi.
- Chủ dự án viết luật mới từ mẫu đã che, đẩy `parser-rules.json` lên GitHub; máy người dùng tự lấy.

## 8. Phân phối & setup một lần (chủ dự án)

- Google Cloud project: bật Sheets API (+ Drive API nếu cần để tạo file), OAuth consent screen **External → Production**, scope `drive.file`, OAuth client loại Android với package **`vn.moneylens.app`** (`applicationId` trong `build.gradle.kts`; `vn.moneylens.moneylens` chỉ là namespace Kotlin) + SHA-1 keystore release (thêm client debug cho máy dev).
- Keystore release lưu an toàn ngoài repo.
- `parser-rules.json` ở đường dẫn cố định trên GitHub (raw URL), repo public hoặc file public.
- APK + hướng dẫn cài (Restricted Settings, tắt tối ưu pin, bật thông báo VCB) như tài liệu cũ mục 7.

## 9. Rủi ro / phải xác nhận khi build

1. **Token trong sync nền.** `google_sign_in` mới (Credential Manager + AuthorizationClient) có lấy được access token im lặng trong isolate nền của WorkManager không — chưa chắc. Nếu không: sync nền chuyển sang chỉ nhắc người dùng; nút + sync khi mở app vẫn đủ cho MVP.
2. **Màn "ứng dụng chưa được xác minh"** khi chỉ dùng scope không nhạy cảm ở chế độ Production — kỳ vọng không có; xác nhận khi setup.
3. **Hai kết nối SQLite cùng process** (Kotlin ghi `capture.db`, Dart đọc) — bật WAL; kiểm tra burst nhiều thông báo khi app đang mở.
4. Luật regex đủ diễn tả mẫu tin VCB thật (tiền vào từ NH khác, định dạng số) — kiểm bằng fixture từ phase 0.
5. Phase 0 Task 3 (test máy thật: tắt app, reboot, qua đêm) vẫn còn chờ. **Chỉ chặn phần parser (Claude quyết):** plan làm trước `capture.db`, ingest khung, Sign-In, sync, dashboard với fixture tổng hợp từ mẫu ở tài liệu cũ mục 8; luật parser thật + package id chính xác làm sau cùng, khi có mẫu từ máy thật.

## 10. V2: nguồn email (cần thiết kế lại)

Ý tưởng cũ (Apps Script POST lên server) không còn chỗ gửi. Hướng khả dĩ: Apps Script trong Gmail của người dùng ghi giao dịch từ email vào **một tab riêng** của chính Sheet đó; app (khi có tính năng khôi phục/đọc Sheet) gộp vào, chống trùng bằng `Ref`. Đây cũng là đường cho iOS. Chưa chốt.

## 11. Để builder tự quyết

- Package Dart: SQLite (sqflite / drift), state management, chart, HTTP, WorkManager plugin.
- Định dạng chi tiết của `parser-rules.json` (miễn là: có `version`, regex named group, khai báo định dạng số, phân biệt "biến động số dư" vs "bỏ qua").
- Thuật toán che dữ liệu ở mục 7.
- UI chi tiết, theme. Ngôn ngữ UI tiếng Việt.

## 12. Lựa chọn Claude tự đưa ra (chưa được xác nhận riêng)

- Hai file SQLite tách chủ sở hữu Kotlin / Dart.
- Parse ở Dart thay vì Kotlin.
- Sync ghi đè toàn bộ tab thay vì append.
- Tab "Tổng hợp" tạo một lần bằng công thức.
- Đăng nhập Google là tuỳ chọn ("Để sau"), không bắt buộc ngay lần đầu.
- Tắt Android Auto Backup; không dùng SQLCipher.
- Không đưa nguyên văn thông báo lên Sheet.
- Khôi phục từ Sheet là việc ngay sau MVP, không nằm trong MVP.
