import AppKit
import SwiftUI

private enum HomeStyle {
    static let background = Color(red: 0.075, green: 0.088, blue: 0.108)
    static let sidebar = Color(red: 0.105, green: 0.12, blue: 0.145)
    static let accent = Color(red: 0.31, green: 0.87, blue: 0.78)
    static let muted = Color(red: 0.59, green: 0.63, blue: 0.68)
}

enum HomePage: Hashable {
    case capture, recent, settings(SettingsPage)

    var title: String {
        switch self {
        case .capture: L10n.tr("Chụp ảnh")
        case .recent: L10n.tr("Ảnh gần đây")
        case .settings(let page): page.title
        }
    }

    var symbol: String {
        switch self {
        case .capture: "viewfinder"
        case .recent: "clock.arrow.circlepath"
        case .settings(let page): page.symbol
        }
    }

    var settingsPage: SettingsPage? {
        if case .settings(let page) = self { return page }
        return nil
    }
}

@MainActor
final class MainNavigation: ObservableObject {
    @Published var page: HomePage = .capture
}

struct ContentView: View {
    @EnvironmentObject private var state: CaptureState
    @EnvironmentObject private var shortcuts: ShortcutSettings
    @EnvironmentObject private var navigation: MainNavigation
    @ObservedObject private var language = LanguageSettings.shared

    private var page: HomePage { navigation.page }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 206)
                .background(HomeStyle.sidebar)
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
            VStack(spacing: 0) {
                if let settingsPage = page.settingsPage {
                    SettingsView(page: settingsPage)
                } else {
                    header
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    ScrollView {
                        Group {
                            switch page {
                            case .capture: capturePage
                            case .recent: recentPage
                            case .settings: EmptyView()
                            }
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                    }
                }
                statusBar
            }
        }
        .background(HomeStyle.background)
        .frame(minWidth: 700, minHeight: 460)
        .onChange(of: language.selection) { _ in
            if !state.isCapturing { state.status = L10n.tr("Sẵn sàng chụp") }
            AppRuntime.shared.drive.refreshLanguage()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                Text("Sharedee Tools")
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 27)
            .padding(.bottom, 35)

            Text(L10n.tr("CÔNG CỤ"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(HomeStyle.muted)
                .padding(.horizontal, 19)
                .padding(.bottom, 10)

            ForEach([HomePage.capture, .recent], id: \.self) { item in
                Button { navigation.page = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .frame(width: 18)
                        Text(item.title)
                        Spacer(minLength: 0)
                        if item == .recent && !state.recent.isEmpty {
                            Text("\(state.recent.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HomeStyle.muted)
                        }
                    }
                    .font(.system(size: 13, weight: page == item ? .semibold : .medium))
                    .foregroundStyle(page == item ? .white : HomeStyle.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 39)
                    .background(page == item ? HomeStyle.accent.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(page == item ? [.isSelected] : [])
            }

            Text(L10n.tr("CÀI ĐẶT"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(HomeStyle.muted)
                .padding(.horizontal, 19)
                .padding(.top, 30)
                .padding(.bottom, 10)

            ForEach(SettingsPage.allCases) { item in
                let destination = HomePage.settings(item)
                Button { navigation.page = destination } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: page == destination ? .semibold : .medium))
                        .foregroundStyle(page == destination ? .white : HomeStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 39)
                        .background(page == destination ? HomeStyle.accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(page == destination ? [.isSelected] : [])
            }

            Spacer(minLength: 18)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.system(size: 23, weight: .bold))
                Text(page == .capture ? L10n.tr("Chọn một thao tác để bắt đầu") : L10n.tr("Mở lại hoặc sao chép ảnh đã chụp"))
                    .font(.system(size: 12))
                    .foregroundStyle(HomeStyle.muted)
            }
            Spacer()
            Button { AppRuntime.shared.openImage() } label: {
                Label(L10n.tr("Mở ảnh…"), systemImage: "folder")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 28)
        .frame(height: 85)
    }

    private var capturePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.tr("CHẾ ĐỘ CHỤP"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(HomeStyle.muted)
                Spacer()
                Text(L10n.tr("PHÍM TẮT"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(HomeStyle.muted)
            }
            .padding(.bottom, 12)

            ForEach(ShortcutAction.allCases) { action in
                Button {
                    Task { await state.perform(action) }
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(HomeStyle.accent)
                            .frame(width: 42, height: 42)
                            .background(HomeStyle.accent.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(description(for: action))
                                .font(.system(size: 11))
                                .foregroundStyle(HomeStyle.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        Text(shortcuts.shortcut(for: action).display)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(HomeStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.isCapturing)
                Divider().background(.white.opacity(0.06))
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                Text(L10n.format("Mặc định: %@", shortcuts.postCaptureAction.title))
            }
            .font(.system(size: 11))
            .foregroundStyle(HomeStyle.muted)
            .padding(.top, 20)
        }
    }

    private var recentPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(HomeStyle.accent)
                    Text(L10n.tr("Chưa có ảnh gần đây"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.tr("Ảnh vừa chụp sẽ xuất hiện ở đây trong phiên làm việc này."))
                        .font(.system(size: 12))
                        .foregroundStyle(HomeStyle.muted)
                }
                .padding(.top, 50)
            } else {
                ForEach(state.recent) { item in
                    HStack(spacing: 14) {
                        Image(nsImage: NSImage(contentsOf: item.url) ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 78, height: 52)
                            .clipped()
                            .background(.black.opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.mode.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.capturedAt, style: .time)
                                .font(.system(size: 11))
                                .foregroundStyle(HomeStyle.muted)
                        }
                        Spacer()
                        Button(L10n.tr("Sao chép")) { state.copyImage(item) }
                            .buttonStyle(.bordered)
                        Button(L10n.tr("Chỉnh sửa")) { AppRuntime.shared.openRecent(item) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 12)
                    Divider().background(.white.opacity(0.06))
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isCapturing ? Color.orange : HomeStyle.accent)
                .frame(width: 6, height: 6)
            Text(state.status)
                .lineLimit(1)
            Spacer()
            Text("Sharedee Tools")
        }
        .font(.system(size: 10))
        .foregroundStyle(HomeStyle.muted)
        .padding(.horizontal, 20)
        .frame(height: 29)
        .background(HomeStyle.sidebar)
    }

    private func description(for action: ShortcutAction) -> String {
        switch action {
        case .area: L10n.tr("Kéo để chọn phần màn hình cần chụp")
        case .window: L10n.tr("Chọn một cửa sổ đang mở")
        case .fullScreen: L10n.tr("Chụp toàn bộ màn hình hiện tại")
        case .scrolling: L10n.tr("Chọn vùng, cuộn tay hoặc tự cuộn rồi ghép thành ảnh dài")
        case .captureText: L10n.tr("Nhận dạng chữ và đưa vào clipboard")
        }
    }
}
