import AppKit
import SwiftUI

/// The Quit Apps page of the main window: the same list as the menu bar, with room for
/// a select-all toggle, a pin to keep an app out of "Quit All", and a clear Quit button on
/// every row. Holding ⌥ turns every Quit into Force Quit.
struct QuitAppsView: View {
    @EnvironmentObject private var quitter: AppQuitter
    @EnvironmentObject private var optionKey: OptionKeyMonitor
    let accent: Color
    let muted: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if quitter.apps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(accent)
                    Text(L10n.tr("Không có ứng dụng nào đang mở"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.tr("Ứng dụng đang chạy sẽ xuất hiện ở đây."))
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                }
                .padding(.top, 50)
            } else {
                if let current = quitter.lastActiveApp, quitter.quitAllTargets().contains(current) {
                    keepCurrentBanner(current)
                        .padding(.bottom, 18)
                }
                HStack {
                    Toggle(isOn: Binding(
                        get: { !quitter.apps.isEmpty && quitter.selection.count == quitter.apps.count },
                        set: { quitter.setAllSelected($0) }
                    )) {
                        Text(L10n.format("ĐANG MỞ · %ld", quitter.apps.count))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(muted)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(L10n.tr("Giữ ⌥ để buộc thoát · ghim để Thoát tất cả bỏ qua"))
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                }
                .padding(.bottom, 8)

                ForEach(quitter.apps, id: \.processIdentifier) { app in
                    row(for: app)
                    Divider().background(.white.opacity(0.06))
                }
            }
        }
        .onAppear {
            quitter.refresh()
            optionKey.start()
        }
        .onDisappear { optionKey.stop() }
    }

    private func keepCurrentBanner(_ current: NSRunningApplication) -> some View {
        let others = quitter.quitAllTargets(keeping: current)
        return HStack(spacing: 12) {
            Image(nsImage: current.icon ?? NSImage())
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("Đang dùng %@", current.localizedName ?? ""))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.format("Đóng %ld ứng dụng còn lại và giữ nguyên ứng dụng này", others.count))
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            Spacer()
            Button(optionKey.isDown ? L10n.tr("Buộc thoát phần còn lại") : L10n.tr("Thoát phần còn lại")) {
                quitter.quitAll(keeping: current, force: optionKey.isDown)
            }
            .buttonStyle(.bordered)
            .tint(optionKey.isDown ? .red : nil)
            .disabled(others.isEmpty)
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(for app: NSRunningApplication) -> some View {
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        let excluded = quitter.isExcluded(app)
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { quitter.isSelected(app) },
                set: { quitter.setSelected($0, for: app) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(L10n.format("Chọn %@", name))
            Image(nsImage: app.icon ?? NSImage())
                .resizable()
                .frame(width: 28, height: 28)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            if app.processIdentifier == quitter.lastActiveApp?.processIdentifier {
                Text(L10n.tr("Đang dùng"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.15), in: Capsule())
            }
            Spacer()
            Button { quitter.setExcluded(!excluded, for: app) } label: {
                Image(systemName: excluded ? "pin.fill" : "pin")
                    .foregroundStyle(excluded ? accent : muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(excluded ? L10n.tr("Bỏ ghim: Thoát tất cả sẽ đóng cả ứng dụng này")
                           : L10n.tr("Ghim: Thoát tất cả luôn bỏ qua ứng dụng này"))
            Button(optionKey.isDown ? L10n.tr("Buộc thoát") : L10n.tr("Thoát")) {
                quitter.quit([app], force: optionKey.isDown)
            }
            .buttonStyle(.bordered)
            .tint(optionKey.isDown ? .red : nil)
            .accessibilityLabel(L10n.format("Thoát %@", name))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { quitter.setSelected(!quitter.isSelected(app), for: app) }
    }
}

/// Header buttons for the Quit Apps page.
struct QuitAppsHeaderActions: View {
    @EnvironmentObject private var quitter: AppQuitter
    @EnvironmentObject private var optionKey: OptionKeyMonitor

    var body: some View {
        let force = optionKey.isDown
        HStack(spacing: 8) {
            Button { quitter.quitSelected(force: force) } label: {
                Label(L10n.format(force ? "Buộc thoát đã chọn (%ld)" : "Thoát đã chọn (%ld)", quitter.selection.count),
                      systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(quitter.selection.isEmpty)
            Button { quitter.quitAll(force: force) } label: {
                Label(L10n.format(force ? "Buộc thoát tất cả (%ld)" : "Thoát tất cả (%ld)", quitter.quitAllTargets().count),
                      systemImage: force ? "bolt.circle" : "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(quitter.quitAllTargets().isEmpty)
        }
    }
}
