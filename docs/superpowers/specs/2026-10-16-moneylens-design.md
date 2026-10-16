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
- iOS (sẽ build sau từ cùng codebase Flutter; nguồn dữ liệu iOS = email Gmail, mục 11).
- Ngân hàng khác, tiền mặt nhập tay — *schema phải sẵn sàng*, chưa làm UI/parser.
- Danh mục chi tiêu, ngân sách, cảnh báo.
- Xem chung dữ liệu nhóm / quỹ chung.
- Phát hành Play Store (phân phối APK cài tay).
- SMS, SePay/Casso, import sao kê.
- Nguồn email (làm ở V2 — xem mục 11; schema MVP phải sẵn sàng).


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
│  Kotlin NotificationListenerService (system-bound)  │
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
| Listener: **`NotificationListenerService` Kotlin tự viết** (`VcbNotificationListener`) trong `android/`, hệ thống bind trực tiếp, tự ghi dữ liệu; Flutter chỉ đọc/cấu hình qua MethodChannel `moneylens/listener`. Không cần foreground service. | Spike 2026-10-16: plugin `flutter_notification_listener_plus` mất thông báo khi vuốt app khỏi recent (gửi sự kiện vào engine UI đã huỷ), bản vá thì hỏng reboot, và plugin log nội dung mọi thông báo ra logcat. Bản Kotlin đạt cả 4 kịch bản trên emulator (mở app, vuốt khỏi recent, kill -9, reboot) + burst. |
| Gửi **nguyên văn** thông báo lên server, **parse ở server** | VCB đổi mẫu tin → sửa parser server + parse lại dữ liệu cũ, không phải phát APK mới cho 5 người. |
| **Device key** dài hạn cho service native, không dùng JWT Supabase | Access token Supabase hết hạn ~1h, service native khó refresh. Khi đăng nhập, app gọi đăng ký thiết bị → server sinh key ngẫu nhiên, lưu hash, trả key một lần; app lưu ở EncryptedSharedPreferences. Thu hồi được từng máy. |
| Dashboard viết **1 lần bằng Flutter**, chạy cả app lẫn web | Đáp ứng "xem cả 2 nơi" + một codebase + iOS sau. |
| Hàng đợi local + retry (WorkManager) | Anti-goal "mất giao dịch khi mất mạng". |

## 5. Mô hình dữ liệu (Postgres)

Mọi bảng có `user_id uuid` + RLS `user_id = auth.uid()`.

- **accounts**: `id, user_id, bank_code (VCB, ... | null), kind (bank|cash), name, last4, created_at`. Tạo tự động lần đầu gặp số TK mới từ thông báo.
- **devices**: `id, user_id, kind (android|gmail_script), name, key_hash, created_at, last_seen_at, revoked_at`.
- **raw_events**: `id, user_id, device_id, source ('android_notif'), package_name, title, body, posted_at, received_at, dedup_hash UNIQUE(user_id, dedup_hash), parse_status (parsed|ignored|failed), parse_error, parser_version`.
- **transactions**: `id, user_id, account_id, raw_event_id UNIQUE NULL, ref text NULL, source (android_notif|manual|...), occurred_at timestamptz, amount bigint (>0), direction (in|out), balance_after bigint NULL, description text, excluded boolean default false, created_at`.

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
- **Android 13+ Restricted Settings:** APK cài tay bị chặn cấp quyền đọc thông báo. Người dùng phải vào Thông tin ứng dụng → ⋮ → "Cho phép cài đặt bị hạn chế" rồi mới bật được. Màn trạng thái + hướng dẫn cài phải nêu bước này.
- **Android 15+:** hệ thống ẩn thông báo bị nhận diện là chứa OTP khỏi listener bên thứ 3. Thông báo biến động số dư thường không bị ảnh hưởng — xác nhận trong spike.
- VCB Digibank phải bật "Nhận thông báo từ ngân hàng" (Cài đặt → Quản lý thông báo) và giữ đăng nhập.
- Supabase free (lưu ý: project tạm dừng sau 7 ngày không hoạt động; giao dịch đều đặn sẽ giữ project hoạt động).
- Flutter web: hosting tĩnh miễn phí.

## 8. Bước đầu tiên bắt buộc: spike thông báo

Trước khi viết parser: build listener tối thiểu + màn debug, chạy vài ngày trên máy thật, thu ≥5 mẫu (tiền vào, tiền ra, nhiều thông báo liên tiếp). Kiểm tra:
1. Package id thật của VCB Digibank.
2. Thông báo có số tiền, dấu +/-, số dư, số TK, nội dung không — hay chỉ "Quý khách có biến động số dư"?
3. Nhiều giao dịch liên tiếp có bị gộp nhóm / ghi đè thông báo không.

**Nếu thông báo không có số tiền → cách B không khả thi, dừng lại bàn lại nguồn dữ liệu.**

**Kết quả sơ bộ (2026-10-16, từ Lịch sử thông báo Android):** mẫu tin VCB Digibank có đủ trường cần thiết → cách B khả thi.

```text
Số dư TK VCB <số TK> <+/-số tiền> VND lúc 16-10-2026 10:24:27. Số dư <số dư> VND. Ref MBVCB.<mã>.<nội dung CK>
ví dụ nội dung: TRAN A chuyen tien.CT tu <TK gửi> TRAN A toi <TK nhận> TRAN B
```

Còn phải xác nhận trong spike: định dạng số (dấu phân cách hàng nghìn), mẫu tin tiền **vào** (Ref từ ngân hàng khác có thể không bắt đầu bằng `MBVCB`), package id, hành vi listener khi app bị kill.

Tiêu chí đi tiếp:

- **Bắt buộc:** số tiền + chiều (vào/ra). Thiếu → dừng.
- **Nên có:** số dư sau GD (dedup chính xác + phát hiện hụt), số TK (tự tạo account), nội dung CK.
- Thiếu số TK → mỗi user 1 account VCB mặc định.
- Thiếu số dư → bỏ kiểm tra liên tục số dư, chỉ dựa heartbeat.

## 8b. Chống mất / trùng dữ liệu (Claude quyết)

- **Khoá chống trùng chính: mã `Ref`** của VCB — `UNIQUE(user_id, account_id, ref)` trên transactions. Dùng được xuyên nguồn (thông báo + email sau này). Không có Ref → fallback (account, occurred_at, amount, balance_after).
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

- Device key thay cho JWT ở service nền.
- Parse ở Supabase Edge Function (TypeScript/Deno).
- Đăng nhập email + password.
- Màn trạng thái/debug trong app.

## 11. V2: nguồn email Gmail qua Google Apps Script (đã chốt hướng)

VCB gửi email biến động số dư cùng nội dung như thông báo. Cả nhóm dùng Gmail.

- Mỗi user tự cài 1 Apps Script trong Gmail của mình (copy từ template + dán ingest key), trigger theo thời gian 1–5 phút.
- Script tìm email VCB chưa xử lý (theo người gửi + label), POST nguyên văn lên `ingest` với `source='gmail'`, gắn label đã xử lý.
- Parser riêng cho định dạng email; chống trùng với thông báo Android bằng `Ref`.
- Vai trò: nguồn dự phòng cho Android + **đường dữ liệu cho iOS** (không cần app chạy nền).
- MVP chuẩn bị sẵn: bảng `devices` có cột `kind (android|gmail_script)`; quy tắc "1 thiết bị active / user" chỉ áp cho `android`. `raw_events.source` nhận `'gmail'`.
