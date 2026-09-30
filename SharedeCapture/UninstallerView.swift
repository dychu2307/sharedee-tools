import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Uninstall page: pick an app (or drop one), review the files it left behind, and move
/// everything to the Trash in one go.
struct UninstallerView: View {
    @EnvironmentObject private var model: UninstallerModel
    let accent: Color
    let muted: Color
    @State private var query = ""
    @State private var sort = SortOrder.name
    @State private var dropTargeted = false

    enum SortOrder: String, CaseIterable, Identifiable {
        case name, size, lastUsed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: L10n.tr("Tên")
            case .size: L10n.tr("Dung lượng")
            case .lastUsed: L10n.tr("Lần dùng cuối")
            }
        }
    }

    var body: some View {
        Group {
            switch model.phase {
            case .browsing: browser
            case .reviewing: review
            case .removing: removing
            case .done: done
            }
        }
        .onAppear { model.loadApps() }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
    }

    // MARK: Browse

    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(muted)
                    TextField(L10n.tr("Tìm ứng dụng"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Picker("", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack(spacing: 10) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 18))
                    .foregroundStyle(dropTargeted ? accent : muted)
                Text(L10n.tr("Kéo một ứng dụng vào đây để gỡ"))
                    .font(.system(size: 12))
                    .foregroundStyle(dropTargeted ? .white : muted)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropTargeted ? accent : .white.opacity(0.12),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .animation(.easeOut(duration: 0.15), value: dropTargeted)

            if let message = model.errorMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.orange)
            }

            if model.isLoadingApps {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("Đang tìm ứng dụng…")).font(.system(size: 12)).foregroundStyle(muted)
                }
                .padding(.top, 20)
            } else {
                Text(L10n.format("ỨNG DỤNG · %ld", visibleApps.count))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(muted)
                    .padding(.top, 6)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleApps) { app in
                        appRow(app)
                        Divider().background(.white.opacity(0.06))
                    }
                }
            }
        }
    }

    private var visibleApps: [InstalledApp] {
        let filtered = query.isEmpty ? model.apps : model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .name: return filtered
        case .size: return filtered.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .lastUsed: return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Button { model.select(app) } label: {
            HStack(spacing: 12) {
                AppIcon(url: app.url, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(lastUsedText(app.lastUsed))
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                }
                Spacer()
                if let size = app.size {
                    Text(ByteCountText.format(size))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lastUsedText(_ date: Date?) -> String {
        guard let date else { return L10n.tr("Chưa rõ lần dùng cuối") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: LanguageSettings.shared.selection.rawValue)
        return L10n.format("Dùng lần cuối %@", formatter.localizedString(for: date, relativeTo: Date()))
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { model.back() } label: {
                Label(L10n.tr("Tất cả ứng dụng"), systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)

            if let app = model.selectedApp {
                HStack(spacing: 16) {
                    AppIcon(url: app.url, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.system(size: 20, weight: .bold))
                        Text([app.version.map { L10n.format("Phiên bản %@", $0) }, app.bundleID]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                        Text((app.url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }

                HStack {
                    Text(L10n.tr("FILE SẼ ĐƯỢC GỠ"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(muted)
                    Spacer()
                    if model.isFindingLeftovers { ProgressView().controlSize(.small) }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 0) {
                    fileRow(icon: AnyView(AppIcon(url: app.url, size: 18)), name: app.name + ".app",
                            location: (app.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                            size: app.size, selected: true, locked: true, byName: false) {}
                    ForEach(model.leftovers) { leftover in
                        Divider().background(.white.opacity(0.06))
                        fileRow(icon: AnyView(Image(nsImage: NSWorkspace.shared.icon(forFile: leftover.url.path))
                                    .resizable().frame(width: 18, height: 18)),
                                name: leftover.url.lastPathComponent, location: leftover.location,
                                size: leftover.size, selected: model.leftoverSelection.contains(leftover.url),
                                locked: false, byName: leftover.matchedByName) {
                            model.toggle(leftover)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if !model.isFindingLeftovers && model.leftovers.isEmpty {
                        Divider().background(.white.opacity(0.06))
                        Text(L10n.tr("Không tìm thấy file sót lại"))
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                            .padding(.vertical, 10)
                    }
                }

                if let message = model.errorMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(.orange)
                }

                HStack {
                    Text(L10n.tr("Mọi thứ được chuyển vào Thùng rác, bạn vẫn khôi phục được."))
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                    Spacer()
                    Button(L10n.format("Gỡ cài đặt · %@", ByteCountText.format(model.selectedSize))) {
                        model.uninstall()
                    }
                    .buttonStyle(GradientButtonStyle(gradient: LinearGradient(
                        colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .disabled(model.isFindingLeftovers)
                }
                .padding(.top, 6)
            }
        }
    }

    private func fileRow(icon: AnyView, name: String, location: String, size: Int64?,
                         selected: Bool, locked: Bool, byName: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? accent : muted)
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .opacity(locked ? 0.5 : 1)
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if byName {
                        Text(L10n.tr("Khớp theo tên"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .help(L10n.tr("Chỉ trùng tên thư mục, có thể thuộc ứng dụng khác. Hãy kiểm tra trước khi chọn."))
                    }
                }
                Text(location)
                    .font(.system(size: 10))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Text(size.map(ByteCountText.format) ?? "…")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(muted)
        }
        .padding(.vertical, 7)
    }

    // MARK: Remove

    private var removing: some View {
        VStack(spacing: 18) {
            if let app = model.selectedApp {
                IntoTrashAnimation(appURL: app.url)
                    .frame(height: 220)
                Text(L10n.format("Đang gỡ %@…", app.name))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private var done: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AngularGradient(colors: ToolStyle.colors + [ToolStyle.colors[0]], center: .center),
                            lineWidth: 12)
                    .frame(width: 150, height: 150)
                    .shadow(color: ToolStyle.colors[0].opacity(0.6), radius: 16)
                CheckmarkPop(gradient: ToolStyle.gradient)
                SparkleBurst(colors: ToolStyle.colors + [.yellow])
            }
            .frame(height: 230)
            Text(L10n.format("Đã gỡ %@", model.selectedApp?.name ?? ""))
                .font(.system(size: 18, weight: .bold))
            ByteCountText(bytes: Double(model.freed))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(muted)
            HStack(spacing: 10) {
                Button(L10n.tr("Mở Thùng rác")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".Trash"))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(L10n.tr("Gỡ ứng dụng khác")) { model.back() }
                    .buttonStyle(GradientButtonStyle(gradient: ToolStyle.gradient))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.phase == .browsing || model.phase == .done,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "app" else { return }
            Task { @MainActor in model.select(appAt: url) }
        }
        return true
    }
}

// MARK: - Pieces

private struct AppIcon: View {
    let url: URL
    let size: CGFloat
    private static var cache: [URL: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private static func icon(for url: URL) -> NSImage {
        if let cached = cache[url] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[url] = icon
        return icon
    }
}

/// The app icon shrinks, tilts and drops into a trash can that bounces as it lands.
private struct IntoTrashAnimation: View {
    let appURL: URL
    @State private var dropped = false
    @State private var landed = false
    @State private var filled = false

    var body: some View {
        VStack(spacing: 0) {
            AppIcon(url: appURL, size: 96)
                .scaleEffect(dropped ? 0.15 : 1)
                .rotationEffect(.degrees(dropped ? 35 : 0))
                .offset(y: dropped ? 118 : 0)
                .opacity(dropped ? 0 : 1)
                .zIndex(1)
            Image(systemName: filled ? "trash.fill" : "trash")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom))
                .scaleEffect(landed ? 1.18 : 1)
                .padding(.top, 36)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.7).delay(0.15)) { dropped = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4).delay(0.8)) {
                landed = true
                filled = true
            }
            withAnimation(.easeOut(duration: 0.25).delay(1.05)) { landed = false }
        }
    }
}
