# Sharedee Tools

[English](README.md)

App chụp và chú thích ảnh màn hình dành cho macOS 12 trở lên, gồm cả máy Mac dùng chip Intel (x86_64) và Apple Silicon (arm64). Mở `Sharedee Tools.app` để dùng ngay hoặc mở `SharedeCapture.xcodeproj` để chỉnh sửa bằng Xcode. App chạy trên thanh menu và không mở cửa sổ biên tập khi khởi động.

Sau khi chụp, một thumbnail xuất hiện ở góc dưới bên phải màn hình. Chọn **Sao chép** để đưa ảnh vào clipboard, **Chỉnh sửa** để mở cửa sổ chú thích, hoặc **Lưu** để xuất PNG. Bấm dấu × để đóng thumbnail. Cửa sổ biên tập chỉ mở khi bạn chọn chỉnh sửa hoặc mở một ảnh có sẵn.

## Tính năng

- Chụp vùng chọn, cửa sổ, toàn màn hình và chụp cuộn cửa sổ phía trước.
- Thêm mũi tên, hình chữ nhật, hình elip, bút vẽ, tô sáng, chữ, vùng làm mờ hoặc vùng che kín.
- Chọn và di chuyển chú thích; cắt ảnh; hoàn tác và làm lại.
- Sao chép ảnh PNG, lưu ảnh PNG đầy đủ độ phân giải, ghim ảnh nổi trên màn hình.
- Nhận dạng chữ trên ảnh bằng Vision của macOS và sao chép kết quả vào clipboard.
- Cài đặt phím tắt toàn hệ thống, hẹn giờ chụp, tự động sao chép sau khi chụp và giới hạn chiều dài ảnh cuộn.

## Phím tắt mặc định

| Tác vụ | Phím tắt |
| --- | --- |
| Chụp vùng chọn | ⌘⇧4 |
| Chụp cửa sổ | ⌘⇧5 |
| Chụp toàn màn hình | ⌘⇧3 |
| Chụp cuộn | ⌃⌥⌘S |
| Chụp vùng và sao chép chữ | ⌃⌥⌘O |

Vào **Cài đặt & phím tắt…** trong thanh bên hoặc biểu tượng trên menu bar để đổi tổ hợp. Nhấp vào ô phím tắt rồi bấm tổ hợp mới. Nếu macOS hoặc app khác đang dùng tổ hợp đó, app sẽ báo xung đột; nút **Dùng phím thay thế** chọn một bộ ít trùng hơn.

## Chụp cuộn

Đưa cửa sổ cần chụp ra phía trước và cuộn lên đầu nội dung. Gọi **Chụp cuộn** bằng menu bar hoặc phím tắt. App sẽ ẩn đi, chụp từng khung, tự cuộn xuống và ghép phần mới. Có thể chỉnh số khung tối đa trong Cài đặt. Chức năng này cần quyền **Ghi màn hình** và **Trợ năng** của macOS. Một số app hoặc trang có nội dung thay đổi liên tục có thể ghép chưa chính xác.

## Build

Chạy scheme **SharedeCapture** trong Xcode. File `project.yml` là cấu hình XcodeGen; nếu chỉnh file này, chạy `xcodegen generate` trước khi build.

Mã nguồn được cấp phép theo [Apache License 2.0](LICENSE). Xem [CONTRIBUTING.md](CONTRIBUTING.md) nếu bạn muốn đóng góp.
