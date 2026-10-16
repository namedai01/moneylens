# Cài MoneyLens trên Android

MoneyLens tự ghi lại các giao dịch Vietcombank từ thông báo của app VCB Digibank, rồi tính tổng thu, tổng chi mỗi tháng cho bạn. Bạn chỉ cần cài một lần, khoảng 10 phút.

## Dữ liệu của bạn ở đâu?

- Giao dịch **chỉ lưu trên điện thoại của bạn**.
- Bản sao lưu là **một Google Sheet trong Google Drive của chính bạn**. App chỉ đọc và ghi được file do nó tạo, không đọc được file nào khác trong Drive.
- **Không ai khác xem được**, kể cả người làm app. Không có server nào nhận giao dịch của bạn.
- ⚠️ Nếu gỡ app khi chưa kết nối Google Sheet, dữ liệu sẽ mất hẳn.

## Các bước

1. **Tải APK** từ link được gửi cho bạn rồi mở file. Nếu máy hỏi, cho phép **"Cài ứng dụng không rõ nguồn gốc"** cho trình duyệt hoặc Zalo (ứng dụng bạn dùng để tải).
2. **Mở MoneyLens một lần** rồi đóng lại.
3. **Chỉ áp dụng cho Android 13 trở lên.** Vào *Cài đặt → Ứng dụng → MoneyLens*, bấm dấu **⋮** ở góc trên → **"Cho phép cài đặt bị hạn chế"**. Nếu không làm bước này, nút bật quyền ở bước 4 sẽ bị mờ.
4. Mở lại MoneyLens → biểu tượng ⚙️ → **"Quyền đọc thông báo"** → *Mở cài đặt* → bật cho **MoneyLens**.
5. Cùng màn đó → **"Tắt tối ưu pin"** → *Cho phép*.
   - Xiaomi, Oppo, Vivo: vào thêm *Cài đặt → Ứng dụng → MoneyLens* và bật **"Tự khởi chạy"** (Autostart).
   - Samsung: *Cài đặt → Pin → Giới hạn sử dụng nền* → không để MoneyLens trong danh sách "ngủ".
6. Trong **VCB Digibank**: *Cài đặt → Quản lý thông báo* → bật **"Nhận thông báo từ ngân hàng"**. Giữ VCB Digibank luôn đăng nhập.
7. Trong MoneyLens: bấm **"Kết nối Google Sheet"** → chọn tài khoản Gmail của bạn → *Cho phép*. Sau bước này, Drive của bạn sẽ có file **MoneyLens**.

## Kiểm tra

- Chuyển hoặc nhận một khoản tiền bất kỳ → mở MoneyLens → giao dịch hiện ở màn chính.
- ⚙️ → *Sao lưu Google Sheet* → bấm **"Đồng bộ ngay"** → mục **"Đồng bộ lần cuối"** cập nhật giờ mới.

## Khi có vấn đề

- **Màn chính báo "N thông báo chưa đọc được"**: bấm vào thông báo đó → kiểm tra lại đoạn chữ (số tiền, số tài khoản và tên đã được che) → bấm **"Gửi mẫu lỗi"** gửi qua Zalo cho người làm app. App không tự gửi gì.
- **App báo "cần đăng nhập lại Google"**: ⚙️ → **"Đồng bộ ngay"**.
- **Không thấy giao dịch mới**: kiểm tra lại bước 4 và 5. Một số máy tự tắt quyền sau khi cập nhật hệ điều hành.
