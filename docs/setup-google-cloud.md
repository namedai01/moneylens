# Setup Google Cloud cho MoneyLens (làm 1 lần)

Người làm: chủ dự án. Thời gian: ~30 phút. Kết quả: app đăng nhập Google và ghi được vào Sheet **trong Drive của từng người dùng**. Không có server nào nhận token.

## 1. Project + API

1. Vào <https://console.cloud.google.com/> → tạo project `moneylens`.
2. *APIs & Services → Library* → bật **Google Sheets API**.

## 2. OAuth consent screen

1. *Google Auth Platform → Branding*: tên app `MoneyLens`, email hỗ trợ của bạn.
2. *Audience*: **External**.
3. *Data access → Add or remove scopes*: chỉ thêm `.../auth/drive.file` ("See, edit, create, and delete only the specific Google Drive files you use with this app"). **Không** thêm `spreadsheets` hay `drive`.
4. *Audience → Publish app* → **In production**.
   - Lý do: ở chế độ *Testing*, refresh token hết hạn sau 7 ngày → mọi người phải đăng nhập lại mỗi tuần.
   - `drive.file` là scope không nhạy cảm → không cần Google xác minh. Nếu khi đăng nhập vẫn thấy màn "Google chưa xác minh ứng dụng này", ghi lại và báo (rủi ro spec mục 9.2).

## 3. OAuth clients

Tạo ở *Clients → Create client*:

| Loại | Dùng cho | Thông tin |
|---|---|---|
| Android | máy dev (debug) | package `vn.moneylens.app`, SHA-1 debug |
| Android | APK release | package `vn.moneylens.app`, SHA-1 keystore release (Task 12) |
| Web application | `serverClientId` mà plugin `google_sign_in` trên Android bắt buộc | chỉ lấy **Client ID**. Không dùng client secret ở đâu cả. |

Lấy SHA-1 debug:

```bash
cd app/android && ./gradlew signingReport | grep -A3 "Variant: debug" | grep SHA1
```

## 4. Đưa Client ID (Web) vào build

Client ID không phải bí mật. Truyền lúc build:

```bash
cd app
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

## 5. Kiểm tra

1. Mở app → "Kết nối Google Sheet" → chọn tài khoản → đồng ý quyền.
2. Drive có file **MoneyLens** với 2 tab `Giao dịch`, `Tổng hợp`.
3. Lỗi thường gặp:
   - `clientConfigurationError` hoặc bị "canceled" ngay sau khi chọn tài khoản → sai SHA-1 / package / Web client ID.
   - Release chạy được nhưng debug thì không (hoặc ngược lại) → thiếu client Android cho SHA-1 của bản đó.
