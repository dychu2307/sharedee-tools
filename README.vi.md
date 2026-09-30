# Sharedee Tools

[English](README.md)

App chụp và chú thích ảnh màn hình dành cho macOS 12 trở lên, gồm cả máy Mac dùng chip Intel (x86_64) và Apple Silicon (arm64). Mở `Sharedee Tools.app` để dùng ngay hoặc mở `SharedeCapture.xcodeproj` để chỉnh sửa bằng Xcode. Khi khởi động, app mở cửa sổ chính với menu công cụ và đồng thời chạy trên thanh menu. Đóng cửa sổ chính không thoát app; chọn **Mở Sharedee Tools** trên thanh menu để mở lại.

Sau khi chụp, thumbnail xuất hiện ở góc dưới bên phải màn hình. Nếu chụp nhiều ảnh, các thumbnail xếp thành danh sách theo thứ tự chụp, ảnh mới nhất ở dưới cùng; có thể cuộn để xem ảnh cũ. Mỗi thumbnail có nút **Sao chép**, **Chỉnh sửa**, **Lưu** và **Drive** dành riêng cho ảnh đó. Khi tải lên Drive, thumbnail hiện trạng thái đang tải, đã tải hoặc lỗi, và mỗi lần bấm chỉ tải một lần. Bấm dấu × để đóng từng thumbnail. **Chỉnh sửa** mở bảng nổi gọn theo kích thước ảnh, chỉ gồm ảnh và công cụ chú thích. Cài đặt nằm trong cửa sổ chính; chọn **Chung**, **Phím tắt** hoặc **Google Drive** ở sidebar. Mục **Chung** có ngôn ngữ, tùy chọn **Mở Sharedee Tools khi đăng nhập** và phiên bản app trong phần **Thông tin**; menu trên thanh menu cũng có **Giới thiệu Sharedee Tools**. Khi cửa sổ chính hoặc bảng biên tập đang mở, Sharedee Tools xuất hiện trong Dock và ⌘Tab; cửa sổ vẫn mở khi chuyển sang app khác. Trang Cài đặt giữ nguyên khi chụp, nên có thể chụp chính trang đó. Bảng biên tập tự đóng sau khi **Sao chép**, **Lưu** hoặc **Tải lên Drive** thành công; nếu hủy hộp thoại lưu, bảng vẫn mở.

## Tính năng

- Chụp vùng chọn, cửa sổ, toàn màn hình và chụp cuộn một vùng tùy chọn (cuộn tay hoặc tự cuộn).
- Thêm mũi tên, hình chữ nhật, hình elip, bút vẽ, tô sáng, chữ, vùng làm mờ hoặc vùng che kín.
- Chọn và di chuyển chú thích; cắt ảnh; hoàn tác và làm lại.
- Sao chép hoặc lưu ảnh PNG đầy đủ độ phân giải.
- **Chụp và sao chép chữ:** chọn một vùng, chữ trong vùng đó được đưa thẳng vào clipboard. Chữ được nhận dạng ngay trên máy bằng Vision của Apple (tiếng Việt, tiếng Anh và ngôn ngữ hệ thống). Một thông báo nhỏ cho biết đã sao chép gì; ảnh chụp để lấy chữ không được giữ lại, tải lên hay lưu. Từ macOS 13, nút **Live Text** trong cửa sổ chỉnh sửa cho phép bôi đen và sao chép một phần chữ trên ảnh.
- Cài đặt phím tắt toàn hệ thống, hẹn giờ chụp, hành động mặc định sau khi chụp và giới hạn chiều dài ảnh cuộn. Mặc định ảnh được sao chép vào clipboard.
- Chọn thư mục lưu trên Mac; có thể kết nối Google Drive bằng OAuth Client ID riêng, tạo thư mục mới hoặc đổi thư mục tải lên ngay trong Cài đặt.
- Tự mở khi đăng nhập (macOS 13 trở lên); giao diện tiếng Anh hoặc tiếng Việt.

## Phím tắt mặc định

| Tác vụ | Phím tắt |
| --- | --- |
| Chụp vùng chọn | ⌘⇧4 |
| Chụp cửa sổ | ⌘⇧5 |
| Chụp toàn màn hình | ⌘⇧3 |
| Chụp cuộn | ⌃⌥⌘S |
| Chụp vùng và sao chép chữ | ⌃⌥⌘O |

Vào **Cài đặt…** từ biểu tượng trên thanh menu để đổi tổ hợp. Nhấp vào ô phím tắt rồi bấm tổ hợp mới. Nếu macOS hoặc app khác đang dùng tổ hợp đó, app sẽ báo xung đột; nút **Dùng phím thay thế** chọn một bộ ít trùng hơn.

## Chụp cuộn

Gọi **Chụp cuộn** bằng menu bar hoặc phím tắt, kéo chọn vùng có nội dung cần cuộn rồi bấm **Chụp**. Sau đó tự cuộn trong vùng bằng chuột hoặc trackpad, hoặc bấm **Tự cuộn** ngay trong vùng chọn (cần quyền Trợ năng) rồi đặt chuột lên phần cần cuộn: giống lăn chuột, app cuộn đúng chỗ con trỏ đang chỉ. Tự cuộn sẽ dừng khi hết nội dung và tự hoàn tất. Bấm **Xong** (Return) để kết thúc hoặc **Hủy** (Esc) để bỏ. Ảnh được ghép ngay khi cuộn; thanh tiêu đề và chân trang cố định chỉ xuất hiện một lần, cuộn ngược lên sẽ được bỏ qua. Video đang chạy hoặc hiệu ứng động trong vùng chọn vẫn ghép được, miễn là phần còn lại của vùng có đủ chi tiết để khớp; nếu không khớp được, app sẽ nhắc cuộn chậm lại hoặc tạm dừng video. Chiều dài tối đa chỉnh trong **Cài đặt → Chung → Chụp cuộn**.

## Build

Chạy scheme **SharedeCapture** trong Xcode. Bản chạy từ Xcode được ký bằng Apple Development để giữ quyền qua các lần build. Nếu fork dự án, đổi **Development Team** trong phần Signing của Xcode sang tài khoản của bạn. File `project.yml` là cấu hình XcodeGen; nếu chỉnh file này, chạy `xcodegen generate` trước khi build.

### Giữ quyền Ghi màn hình qua nhiều phiên bản

Hãy ký các bản chạy bằng **cùng một chứng chỉ** và giữ bundle ID `com.sharedecapture.app`. Bản ký ad hoc làm macOS coi mỗi lần build là app mới nên có thể hỏi lại quyền. Để tạo bản chạy ký ổn định tại máy:

```sh
security find-identity -v -p codesigning
SHAREDEE_SIGNING_IDENTITY="Apple Development: Tên của bạn (TEAMID)" ./scripts/build-signed-app.sh
```

Script ghi `Sharedee Tools.app` ở thư mục gốc dự án. Dùng cùng Apple Development certificate cho các bản chạy tại máy hoặc cùng Developer ID certificate cho các bản phát hành. Nếu đổi loại chứng chỉ, macOS sẽ cần cấp quyền lại một lần. Sau khi bật quyền, dùng **Cài đặt → Khởi động lại Sharedee Tools** để macOS áp dụng quyền mới. Tránh mở các bản build cũ hoặc bản ký ad hoc.

Nếu mục **SharedeCapture** cũ đang bật mà app vẫn báo thiếu quyền, đó là quyền của bản ký tạm. Trong **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Ghi màn hình & Âm thanh hệ thống**, thêm đúng file `Sharedee Tools.app` ở thư mục gốc dự án, bật quyền cho mục **Sharedee Tools**, rồi khởi động lại app. Sau đó có thể bỏ mục cũ.

## Google Drive

Vào **Cài đặt → Google Drive**, dán OAuth Client ID loại **Desktop app** cùng client secret của nó. Mỗi ô được kiểm tra với Google ngay khi dán và hiện dấu tích xanh nếu hợp lệ; sau đó bấm **Lưu Client ID**. Sau đó bấm **Kết nối Google Drive**, đăng nhập và cấp quyền. App sẽ tạo hoặc dùng lại thư mục **Sharedee Tools** trong My Drive. Trong mục **Thư mục tải ảnh lên**, bạn có thể chuyển giữa các thư mục app đang dùng được, tạo thư mục mới bên trong thư mục hiện tại hoặc ở My Drive, hoặc chọn thư mục có sẵn khác bằng **Chọn thư mục khác trên Google Drive…** (cửa sổ chọn của Google không tạo được thư mục). Sau khi cấp quyền, trang trình duyệt báo kết nối thành công, thử tự đóng tab, và Sharedee Tools được đưa lên phía trước.

**Tạo Client ID:** Bật **Google Drive API** và **Google Picker API** trong Google Cloud, cấu hình màn hình đồng ý OAuth và tạo Client ID loại **Desktop app**. Sao chép cả Client ID và client secret; Google yêu cầu secret khi lấy token kể cả với app desktop. Nếu ứng dụng OAuth còn ở chế độ Testing, Google chỉ cho tài khoản trong danh sách test users đăng nhập. Người tạo bản fork có thể dùng Google Cloud project riêng.

**Tùy chọn cho người phát hành:** Nếu muốn người dùng kết nối mà không phải nhập ID riêng, đặt build setting `SHAREDEE_GOOGLE_CLIENT_ID` và `SHAREDEE_GOOGLE_CLIENT_SECRET` trước khi build. Có thể truyền `SHAREDEE_GOOGLE_CLIENT_ID=your-id.apps.googleusercontent.com SHAREDEE_GOOGLE_CLIENT_SECRET=GOCSPX-…` cho `xcodebuild`, hoặc thêm giá trị vào `project.yml` rồi tạo lại Xcode project. Không commit các giá trị này lên repository công khai.

Client ID, client secret do người dùng nhập và refresh token được lưu trong macOS Keychain. App dùng quyền `drive.file`; ảnh chỉ tải lên khi bạn chọn nút **Drive** hoặc đặt đó làm hành động mặc định. Client ID và secret đưa vào lúc build sẽ hiện trong bundle.

## Phiên bản và icon

Phiên bản theo chuẩn [Semantic Versioning](https://semver.org) và được tính tự động từ git lúc build: lấy tag `vX.Y.Z` gần nhất, rồi tăng theo các commit [Conventional Commits](https://www.conventionalcommits.org) sau đó (`feat:` tăng số giữa, `fix:` và loại khác tăng số cuối, `feat!:` tăng số đầu). Số build là tổng số commit. Chạy `scripts/version.sh` để xem phiên bản hiện tại; phiên bản hiển thị ở **Cài đặt → Chung → Thông tin**. Xem [CONTRIBUTING.md](CONTRIBUTING.md) và [CHANGELOG.md](CHANGELOG.md). Icon app và icon thanh menu được vẽ bằng các script trong `scripts/app-icon/`; xem chú thích đầu mỗi script để tạo lại.

## Đóng góp và giấy phép

Mọi issue và pull request đều được chào đón; xem [CONTRIBUTING.md](CONTRIBUTING.md). Bản quyền 2026 Duy Chu, phát hành theo [Apache License 2.0](LICENSE). Xem thêm [NOTICE](NOTICE).
