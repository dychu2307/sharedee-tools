import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var shortcuts: ShortcutSettings

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Chung", systemImage: "slider.horizontal.3") }
            shortcutsTab
                .tabItem { Label("Phím tắt", systemImage: "keyboard") }
        }
        .frame(width: 590, height: 440)
        .padding(12)
    }

    private var generalTab: some View {
        Form {
            Section("Sau khi chụp") {
                Toggle("Tự động sao chép ảnh vào clipboard", isOn: $shortcuts.autoCopy)
                Toggle("Hiện con trỏ khi chụp toàn màn hình", isOn: $shortcuts.includeCursor)
                Picker("Hẹn giờ chụp", selection: $shortcuts.captureDelay) {
                    Text("Không hẹn giờ").tag(0)
                    Text("3 giây").tag(3)
                    Text("5 giây").tag(5)
                    Text("10 giây").tag(10)
                }
            }
            Section("Chụp cuộn") {
                Stepper("Tối đa \(shortcuts.maxScrollFrames) khung hình",
                        value: $shortcuts.maxScrollFrames, in: 3...30)
                Text("App sẽ chụp cửa sổ phía trước, tự cuộn xuống và ghép các khung hình. macOS cần cấp quyền Trợ năng cho thao tác cuộn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Quyền macOS") {
                Button("Mở quyền Ghi màn hình") {
                    openPrivacySettings("Privacy_ScreenCapture")
                }
                Button("Mở quyền Trợ năng") {
                    openPrivacySettings("Privacy_Accessibility")
                }
            }
        }
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Phím tắt toàn hệ thống")
                .font(.title3.weight(.semibold))
            Text("Nhấp vào ô phím tắt rồi nhấn tổ hợp mới. Phím tắt hoạt động khi app đang mở, kể cả lúc bạn dùng app khác.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(ShortcutAction.allCases) { action in
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title)
                                .font(.system(size: 13, weight: .medium))
                            if let error = shortcuts.errors[action] {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        ShortcutRecorder(shortcut: shortcuts.shortcut(for: action)) {
                            shortcuts.set($0, for: action)
                        }
                        .frame(width: 142, height: 34)
                    }
                    .frame(minHeight: 53)
                    if action != ShortcutAction.allCases.last { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Button("Đặt lại phím tắt mặc định") { shortcuts.resetToDefaults() }
                Button("Dùng phím thay thế") { shortcuts.useConflictFreePreset() }
                Spacer()
            }
            Text("Phím mặc định là ⌘⇧3, ⌘⇧4 và ⌘⇧5. Nếu tổ hợp bị trùng với macOS hoặc app khác, hãy đổi phím tắt hoặc dùng bộ phím thay thế.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(22)
    }
}
