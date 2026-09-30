import AppKit
import SwiftUI

/// The Quit Apps page of the main window: the same list as the menu bar, with room for
/// a select-all toggle and a clear Quit button on every row.
struct QuitAppsView: View {
    @EnvironmentObject private var quitter: AppQuitter
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
                }
                .padding(.bottom, 8)

                ForEach(quitter.apps, id: \.processIdentifier) { app in
                    row(for: app)
                    Divider().background(.white.opacity(0.06))
                }
            }
        }
        .onAppear { quitter.refresh() }
    }

    private func row(for app: NSRunningApplication) -> some View {
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
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
            Spacer()
            Button(L10n.tr("Thoát")) { quitter.quit([app]) }
                .buttonStyle(.bordered)
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

    var body: some View {
        HStack(spacing: 8) {
            Button { quitter.quitSelected() } label: {
                Label(L10n.format("Thoát đã chọn (%ld)", quitter.selection.count), systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(quitter.selection.isEmpty)
            Button { quitter.quitAll() } label: {
                Label(L10n.tr("Thoát tất cả"), systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(quitter.apps.isEmpty)
        }
    }
}
