# MoneyLens — Thiết kế MVP

Ngày: 2026-10-16 · Tác giả: dainguyen (+ Claude)

## 1. Mục đích & lý do

App quản lý thu chi cá nhân. Vấn đề: chuyển khoản qua Vietcombank (VCB) hằng ngày nhưng không biết mỗi tháng tổng thu / tổng chi bao nhiêu.

VCB không có API công khai cho tài khoản cá nhân, người dùng không đăng ký SMS Banking, chưa muốn dùng dịch vụ trung gian (SePay/Casso). → Cách lấy dữ liệu: **đọc thông báo đẩy (push notification) của app VCB Digibank trên Android**, gửi realtime về server.

Người dùng: chủ dự án + nhóm nhỏ ~5 người. Mỗi người chỉ xem dữ liệu của mình.

Mục tiêu phụ: chủ dự án học Flutter.

## 2. Goals / Non-goals / Anti-goals

**Goals (MVP)**
- Android: tự bắt thông báo biến động số dư VCB Digibank → ghi nhận giao dịch realtime, kể cả khi app không mở.
- Xem tổng thu, tổng chi, chênh lệch theo tháng + danh sách giao dịch + biểu đồ nhiều tháng.
- Xem được trên cả app Android và web.
- Nhiều người dùng, dữ liệu tách biệt.
- Host miễn phí.

**Non-goals (MVP, làm sau)**
- iOS (sẽ build sau từ cùng codebase Flutter; nguồn dữ liệu iOS thiết kế riêng sau).
- Ngân hàng khác, tiền mặt nhập tay — *schema phải sẵn sàng*, chưa làm UI/parser.
- Danh mục chi tiêu, ngân sách, cảnh báo.
- Xem chung dữ liệu nhóm / quỹ chung.
- Phát hành Play Store (phân phối APK cài tay).
- SMS, SePay/Casso, import sao kê.

**Anti-goals (làm vậy là hỏng dù "chạy được")**
- Lưu username/password ngân hàng hoặc cào web iBanking.
- Mất giao dịch âm thầm (mất mạng, server lỗi, parser không hiểu mẫu tin) mà người dùng không biết.
- Người dùng này xem được dữ liệu người dùng kia qua app/web. (Chủ dự án — người vận hành Supabase — **được phép** đọc dữ liệu thô của mọi người; nhóm đã đồng ý. Không cần mã hoá phía client.)
- Đếm trùng một giao dịch.

## 3. Ràng buộc

- Stack: **Flutter** (Dart) cho app Android + web; dễ build iOS sau.
- Backend & host: gói miễn phí (Supabase free, hosting web tĩnh miễn phí).
- Tiền tệ VND, số nguyên (không dùng float). Múi giờ gom tháng: `Asia/Ho_Chi_Minh`.
- **Chưa biết nội dung chính xác thông báo VCB Digibank** (có ghi số tiền / số dư / nội dung CK không). → Bước đầu tiên của plan là spike bắt thông báo thật (mục 8).

## 4. Kiến trúc (đã chốt)

```
┌────────────── Flutter app (Android) ───────────────┐
│  Kotlin NotificationListenerService (native)        │
│   - lọc package VCB Digibank                        │
│   - lấy title/text/bigText/postTime                 │
│   - xếp hàng đợi local → gửi lên ingest (retry)     │
│  Flutter UI: đăng nhập, dashboard, màn debug        │
└───────────────┬─────────────────────────────────────┘
                │ HTTPS + device key
                v
┌──────────────── Supabase ───────────────────────────┐
│  Edge Function `ingest`: xác thực device key →      │
│    lưu raw_events → parse → upsert transactions     │
│  Postgres + RLS (mỗi user chỉ thấy dòng của mình)   │
│  Auth (email + password)                            │
└───────────────┬─────────────────────────────────────┘
                v
        Flutter web (dashboard) trên hosting tĩnh
```

### Quyết định chính

| Quyết định | Lý do |
|---|---|
| Listener viết **Kotlin native** trong thư mục `android/` của project Flutter, tự gửi HTTP, không cần Dart engine chạy | Android hay kill app nền; service native được hệ thống bind độc lập, không phụ thuộc Flutter engine còn sống. Flutter chỉ dùng MethodChannel để cấu hình (bật/tắt, lưu device key, đọc log). |
| Gửi **nguyên văn** thông báo lên server, **parse ở server** | VCB đổi mẫu tin → sửa parser server + parse lại dữ liệu cũ, không phải phát APK mới cho 5 người. |
| **Device key** dài hạn cho service native, không dùng JWT Supabase | Access token Supabase hết hạn ~1h, service native khó refresh. Khi đăng nhập, app gọi đăng ký thiết bị → server sinh key ngẫu nhiên, lưu hash, trả key một lần; app lưu ở EncryptedSharedPreferences. Thu hồi được từng máy. |
| Dashboard viết **1 lần bằng Flutter**, chạy cả app lẫn web | Đáp ứng "xem cả 2 nơi" + một codebase + iOS sau. |
| Hàng đợi local + retry (WorkManager) | Anti-goal "mất giao dịch khi mất mạng". |

## 5. Mô hình dữ liệu (Postgres)

Mọi bảng có `user_id uuid` + RLS `user_id = auth.uid()`.

- **accounts**: `id, user_id, bank_code (VCB, ... | null), kind (bank|cash), name, last4, created_at`. Tạo tự động lần đầu gặp số TK mới từ thông báo.
- **devices**: `id, user_id, name, key_hash, created_at, last_seen_at, revoked_at`.
- **raw_events**: `id, user_id, device_id, source ('android_notif'), package_name, title, body, posted_at, received_at, dedup_hash UNIQUE(user_id, dedup_hash), parse_status (parsed|ignored|failed), parse_error, parser_version`.
- **transactions**: `id, user_id, account_id, raw_event_id UNIQUE NULL, source (android_notif|manual|...), occurred_at timestamptz, amount bigint (>0), direction (in|out), balance_after bigint NULL, description text, excluded boolean default false, created_at`.

`excluded = true` → giao dịch vẫn hiện trong danh sách (mờ) nhưng không tính vào tổng thu/chi. Dùng cho chuyển khoản giữa TK của mình, mở/tất toán tiết kiệm, trả nợ thẻ/vay — người dùng tự bật/tắt.

`dedup_hash` = sha256(package + posted_at + body). Chống trùng thêm ở mức giao dịch: nếu mẫu tin có số dư, (account, occurred_at, amount, balance_after) là duy nhất.

`source` + `kind=cash` + `raw_event_id NULL` để sau này thêm ngân hàng / nhập tay không phải đổi schema.

## 6. Hành vi

**Bắt thông báo**
- Chỉ lấy thông báo của package VCB Digibank (package id xác nhận ở spike). Bỏ qua thông báo khác — không gửi lên server.
- Lấy `EXTRA_TITLE`, `EXTRA_TEXT`, `EXTRA_BIG_TEXT` (ưu tiên big text), `postTime`.

**Parse**
- Parser theo phiên bản (`parser_version`). Không hiểu mẫu → `parse_status=failed`, lưu lỗi, **không** tạo giao dịch.
- Thông báo không phải biến động số dư (khuyến mãi, OTP, ...) → `ignored`.
- Có chức năng parse lại toàn bộ `failed` (+ tuỳ chọn tất cả) sau khi sửa parser.
- Parser có unit test bằng fixture từ thông báo thật (đã che số TK).

**Dashboard (app + web)**
- Chọn tháng: tổng thu, tổng chi, chênh lệch.
- Danh sách giao dịch trong tháng (thời gian, +/- số tiền, nội dung). Mỗi dòng có nút **"Ẩn khỏi thống kê"** (bật/tắt `excluded`). MVP không có sửa/xoá giao dịch.
- Tổng thu/chi chỉ tính giao dịch `excluded = false`. Mặc định mọi giao dịch đều được tính.
- Biểu đồ cột thu/chi 6–12 tháng gần nhất.
- Badge cảnh báo nếu có `raw_events` `failed` → người dùng biết có giao dịch chưa ghi nhận.

**Màn hình trạng thái (chỉ Android)**
- Quyền đọc thông báo đã cấp chưa (nút mở cài đặt).
- Tối ưu pin đã tắt chưa (hướng dẫn Xiaomi/Oppo/Samsung).
- Số sự kiện đang chờ gửi, lần gửi thành công gần nhất.
- Debug: 20 thông báo VCB gần nhất (nguyên văn) — phục vụ spike + sửa parser.

## 7. Phân phối & host

- APK build release, chia sẻ link tải (GitHub Releases hoặc Drive). Mỗi máy phải cho phép "cài từ nguồn không xác định".
- Supabase free (lưu ý: project tạm dừng sau 7 ngày không hoạt động; giao dịch đều đặn sẽ giữ project hoạt động).
- Flutter web: hosting tĩnh miễn phí.

## 8. Bước đầu tiên bắt buộc: spike thông báo

Trước khi viết parser: build listener tối thiểu + màn debug, chạy vài ngày trên máy thật, thu ≥5 mẫu (tiền vào, tiền ra, nhiều thông báo liên tiếp). Kiểm tra:
1. Package id thật của VCB Digibank.
2. Thông báo có số tiền, dấu +/-, số dư, số TK, nội dung không — hay chỉ "Quý khách có biến động số dư"?
3. Nhiều giao dịch liên tiếp có bị gộp nhóm / ghi đè thông báo không.

**Nếu thông báo không có số tiền → cách B không khả thi, dừng lại bàn lại nguồn dữ liệu.**

Tiêu chí đi tiếp:

- **Bắt buộc:** số tiền + chiều (vào/ra). Thiếu → dừng.
- **Nên có:** số dư sau GD (dedup chính xác + phát hiện hụt), số TK (tự tạo account), nội dung CK.
- Thiếu số TK → mỗi user 1 account VCB mặc định.
- Thiếu số dư → bỏ kiểm tra liên tục số dư, chỉ dựa heartbeat.

## 8b. Chống mất / trùng dữ liệu (Claude quyết)

- **1 thiết bị nghe active / user.** Đăng ký máy mới → thu hồi device key máy cũ. Tránh 2 máy cùng gửi 1 giao dịch.
- **Heartbeat:** service gửi heartbeat mỗi ~6h (WorkManager). Dashboard cảnh báo nếu thiết bị im > 48h ("có thể đang bỏ sót giao dịch — kiểm tra quyền / tối ưu pin").
- **Kiểm tra liên tục số dư** (nếu thông báo có số dư): `số dư trước ± số tiền ≠ số dư sau` → cảnh báo "có thể thiếu giao dịch giữa X và Y".
- **Ưu tiên không mất hơn không trùng:** khi không chắc là trùng (khác `postTime`, không có số dư) → vẫn ghi nhận; người dùng tự ẩn nếu trùng.

## 8c. Đăng ký & vận hành (Claude quyết)

- **Chỉ mời:** tắt đăng ký công khai trên Supabase; chủ dự án mời 5 người qua email.
- **Parse lại:** chỉ chủ dự án chạy (script dùng service role). Mặc định chỉ parse lại `failed`. Parse lại toàn bộ: cập nhật transaction gắn `raw_event_id`, **không** đụng transaction người dùng đã sửa/ẩn.

## 9. Để builder tự quyết

- Package Flutter: state management, routing, chart, HTTP client.
- Hosting tĩnh cụ thể cho Flutter web (Cloudflare Pages / Firebase Hosting / Vercel).
- Cấu trúc thư mục, cách tổ chức migration Supabase.
- UI chi tiết, theme.
- Ngôn ngữ UI: tiếng Việt.

## 10. Lựa chọn Claude tự đưa ra (chưa được người dùng xác nhận riêng)

- Listener native Kotlin thay vì plugin Flutter thuần.
- Device key thay cho JWT ở service nền.
- Parse ở Supabase Edge Function (TypeScript/Deno).
- Đăng nhập email + password.
- Màn trạng thái/debug trong app.
