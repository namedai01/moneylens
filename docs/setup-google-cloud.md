# Setup Google Cloud cho MoneyLens (làm 1 lần)

Người làm: chủ dự án. Thời gian: ~30 phút. Kết quả: app đăng nhập Google và ghi được vào Sheet **trong Drive của từng người dùng**. Không có server nào nhận token.

## 1. Project + API

1. Vào <https://console.cloud.google.com/> → tạo project `moneylens`.
2. *APIs & Services → Library* → bật **Google Sheets API**.

## 2. OAuth consent screen

1. *Google Auth Platform → Branding*: tên app `MoneyLens`, **User support email** và **Developer contact email** (thiếu một trong hai thì consent screen chưa hoàn chỉnh, đăng nhập sẽ bị từ chối).
2. *Audience*: **External**.
3. *Data access → Add or remove scopes*: chỉ thêm `.../auth/drive.file` ("See, edit, create, and delete only the specific Google Drive files you use with this app"). **Không** thêm `spreadsheets` hay `drive`.
4. *Audience → Publish app* → **In production**.
   - Lý do: ở chế độ *Testing*, refresh token hết hạn sau 7 ngày → mọi người phải đăng nhập lại mỗi tuần.
   - `drive.file` là scope không nhạy cảm → không cần Google xác minh. Nếu khi đăng nhập vẫn thấy màn "Google chưa xác minh ứng dụng này", ghi lại và báo (rủi ro spec mục 9.2).
   - Nếu tạm để *Testing*: thêm từng Gmail vào *Test users*, nếu không đăng nhập sẽ thất bại (xem mục 5).

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
3. Tab `Tổng hợp` phải ra số (tháng, tổng thu, tổng chi, chênh lệch), không phải `#ERROR!`.

### Lỗi thường gặp

| App báo / logcat | Nguyên nhân | Sửa |
|---|---|---|
| "Đăng nhập Google lỗi (clientConfigurationError)" | Build thiếu `--dart-define=GOOGLE_SERVER_CLIENT_ID`, hoặc Client ID không phải loại **Web** | Build lại với đúng Web Client ID (mục 4) |
| "Đã huỷ đăng nhập" ngay sau khi chọn tài khoản; logcat `Auth.Api.Credentials: [16] Account reauth failed` | Consent screen chưa xong: app đang *Testing* mà Gmail chưa nằm trong *Test users*, hoặc thiếu email ở *Branding* | Publish *In production* (hoặc thêm Test user), điền đủ email; đợi ~5 phút rồi thử lại, không cần build lại |
| "Đã huỷ đăng nhập" chỉ ở bản debug hoặc chỉ ở bản release | Thiếu client Android cho SHA-1 của bản đó | Thêm client Android với SHA-1 tương ứng (mục 3) |
| Tab `Tổng hợp` toàn `#ERROR!` | Sheet tạo bằng bản app trước PR #3, lấy locale `vi_VN` (công thức cần `;` thay vì `,`) | Xoá vĩnh viễn file MoneyLens (cả trong Thùng rác) → app *Đồng bộ ngay* → *Tạo lại Sheet*. Hoặc đổi *File → Settings → Locale* sang United States rồi nhập lại 4 ô A2:D2 |

Xem lỗi chi tiết: `adb logcat | grep -E "Auth.Api.Credentials|flutter"`.
