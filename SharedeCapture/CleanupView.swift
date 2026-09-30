import AppKit
import SwiftUI

/// The Cleanup page of the main window: scan → review → clean, with an animated ring hero.
struct CleanupView: View {
    @EnvironmentObject private var model: CleanupModel
    @EnvironmentObject private var quitter: AppQuitter
    let accent: Color
    let muted: Color
    @State private var expanded: Set<CleanupKind> = []

    private static let colors = ToolStyle.colors
    private static let gradient = ToolStyle.gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let disk = model.disk {
                DiskUsageBar(disk: disk, reclaimable: model.phase == .results ? model.selectedSize : 0,
                             muted: muted)
            }
            hero
                .frame(maxWidth: .infinity)
            if model.phase != .idle {
                categoryList
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase)
        .onAppear { model.refreshDisk() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                CleanupRing(phase: model.phase, progress: model.cleanProgress, colors: Self.colors)
                    .frame(width: 196, height: 196)
                centerContent
                if model.phase == .done {
                    SparkleBurst(colors: Self.colors + [.yellow])
                }
            }
            .frame(width: 280, height: 260)

            statusLine
                .frame(maxWidth: 460)
                .frame(height: 16)
            actions
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Self.gradient)
                Text(L10n.tr("Sẵn sàng quét"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(muted)
            }
        case .scanning:
            ringLabel(bytes: model.found, caption: L10n.tr("Đang quét…"))
        case .results:
            ringLabel(bytes: model.selectedSize, caption: L10n.tr("đã chọn để dọn"))
        case .cleaning:
            ringLabel(bytes: model.freed, caption: L10n.tr("Đang dọn…"))
        case .done:
            VStack(spacing: 6) {
                CheckmarkPop(gradient: Self.gradient)
                ByteCountText(bytes: Double(model.freed))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(L10n.tr("đã được giải phóng"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
    }

    private func ringLabel(bytes: Int64, caption: String) -> some View {
        VStack(spacing: 4) {
            ByteCountText(bytes: Double(bytes))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            switch model.phase {
            case .idle:
                Text(L10n.tr("Tìm bộ nhớ đệm, nhật ký, dữ liệu Xcode và file lớn có thể dọn"))
            case .scanning:
                Text((model.currentPath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .truncationMode(.middle)
            case .results:
                Text(L10n.format("Tìm thấy %@ · chọn mục cần dọn bên dưới",
                                 ByteCountText.format(model.totalSize)))
            case .cleaning:
                Text(model.activeKind.map { L10n.format("Đang dọn %@", $0.title) } ?? "")
            case .done:
                Text(model.failedCount == 0
                     ? L10n.tr("Máy của bạn đã gọn gàng hơn")
                     : L10n.format("%ld mục không xoá được vì đang được dùng hoặc được hệ thống bảo vệ",
                                   model.failedCount))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(muted)
        .lineLimit(1)
    }

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .idle:
            Button(L10n.tr("Quét")) { model.scan() }
                .buttonStyle(GradientButtonStyle(gradient: Self.gradient))
        case .scanning:
            Button(L10n.tr("Dừng")) { model.cancelScan() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        case .results:
            HStack(spacing: 10) {
                Button(L10n.tr("Quét lại")) { model.scan() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button(L10n.format("Dọn dẹp %@", ByteCountText.format(model.selectedSize))) { model.clean() }
                    .buttonStyle(GradientButtonStyle(gradient: Self.gradient))
                    .disabled(model.selection.isEmpty)
            }
        case .cleaning:
            EmptyView()
        case .done:
            Button(L10n.tr("Quét lại")) { model.scan() }
                .buttonStyle(GradientButtonStyle(gradient: Self.gradient))
        }
    }

    // MARK: Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.tr("KẾT QUẢ"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(muted)
                .padding(.bottom, 8)
            ForEach(CleanupKind.allCases) { kind in
                let category = model.categories.first { $0.kind == kind }
                categoryRow(kind: kind, category: category)
                if let category, expanded.contains(kind), model.phase == .results {
                    itemList(category)
                        .transition(.opacity)
                }
                Divider().background(.white.opacity(0.06))
            }
        }
    }

    private func categoryRow(kind: CleanupKind, category: CleanupCategory?) -> some View {
        let reviewing = model.phase == .results
        let hasItems = !(category?.items.isEmpty ?? true)
        return HStack(spacing: 12) {
            if reviewing {
                Button { if let category { model.toggle(category) } } label: {
                    selectionIcon(category.map(model.selectionState(of:)) ?? .none)
                }
                .buttonStyle(.plain)
                .disabled(!hasItems)
                .opacity(hasItems ? 1 : 0.3)
            }
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(kind.color)
                .frame(width: 34, height: 34)
                .background(kind.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if category?.accessDenied == true {
                    HStack(spacing: 6) {
                        Text(L10n.tr("Cần quyền Truy cập toàn bộ ổ đĩa"))
                        Button(L10n.tr("Mở Cài đặt")) { Self.openFullDiskAccessSettings() }
                            .buttonStyle(.link)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                } else {
                    Text(kind.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                if reviewing, let category {
                    runningWarning(model.runningOwners(of: category, among: quitter.apps))
                }
            }
            Spacer(minLength: 12)
            trailing(kind: kind, category: category)
            if reviewing && hasItems {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(muted)
                        .rotationEffect(.degrees(expanded.contains(kind) ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Xem chi tiết"))
            }
        }
        .padding(.vertical, 11)
        .opacity(model.phase == .scanning && category == nil && model.activeKind != kind ? 0.45 : 1)
    }

    @ViewBuilder
    private func trailing(kind: CleanupKind, category: CleanupCategory?) -> some View {
        let active = model.activeKind == kind
        if model.phase == .scanning && category == nil {
            if active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle.dotted").foregroundStyle(muted.opacity(0.6))
            }
        } else if model.phase == .cleaning && active {
            ProgressView().controlSize(.small)
        } else if model.phase == .cleaning && model.finishedKinds.contains(kind) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(kind.color)
                .transition(.scale.combined(with: .opacity))
        } else if let category {
            Text(category.items.isEmpty ? L10n.tr("Sạch") : ByteCountText.format(category.size))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(category.items.isEmpty ? muted : .white)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func runningWarning(_ apps: [NSRunningApplication]) -> some View {
        if !apps.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(L10n.format("Đang chạy: %@", apps.compactMap(\.localizedName).joined(separator: ", ")))
                    .lineLimit(1)
                Button(L10n.tr("Thoát trước khi dọn")) { quitter.quit(apps) }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .transition(.opacity)
        }
    }

    private func itemList(_ category: CleanupCategory) -> some View {
        let visible = category.items.prefix(60)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { item in
                HStack(spacing: 10) {
                    Button { model.toggle(item) } label: {
                        selectionIcon(model.selection.contains(item.url) ? .all : .none)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item.displayPath)
                            .font(.system(size: 10))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 10)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(muted)
                    .help(L10n.tr("Hiện trong Finder"))
                    Text(ByteCountText.format(item.size))
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
            if category.items.count > visible.count {
                Text(L10n.format("và %ld mục nhỏ hơn", category.items.count - visible.count))
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .padding(.vertical, 6)
            }
        }
        .padding(.leading, 34)
        .padding(.bottom, 8)
    }

    private func selectionIcon(_ state: CleanupModel.SelectionState) -> some View {
        let name = switch state {
        case .all: "checkmark.square.fill"
        case .some: "minus.square.fill"
        case .none: "square"
        }
        return Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(state == .none ? muted : accent)
    }

    private static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Animated pieces

/// How full the startup disk is, with the space the current selection would free shown as a
/// lighter tail on the used bar.
private struct DiskUsageBar: View {
    let disk: DiskUsage
    let reclaimable: Int64
    let muted: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(disk.name, systemImage: "internaldrive")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L10n.format("Đã dùng %@ / %@", ByteCountText.format(disk.used), ByteCountText.format(disk.total)))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(muted)
            }
            GeometryReader { proxy in
                let total = max(1, Double(disk.total))
                let used = Double(disk.used) / total
                let freeable = min(Double(reclaimable), Double(disk.used)) / total
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule()
                        .fill(ToolStyle.gradient)
                        .frame(width: proxy.size.width * used)
                    Capsule()
                        .fill(.white.opacity(0.55))
                        .frame(width: proxy.size.width * freeable)
                        .offset(x: proxy.size.width * (used - freeable))
                        .opacity(freeable > 0 ? 1 : 0)
                }
            }
            .frame(height: 8)
            if reclaimable > 0 {
                Text(L10n.format("Dọn phần đã chọn sẽ trống thêm %@", ByteCountText.format(reclaimable)))
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.4), value: reclaimable)
    }
}

/// Colours shared by the tool pages' hero animations and primary buttons.
enum ToolStyle {
    static let colors = [Color(red: 0.31, green: 0.87, blue: 0.78),
                         Color(red: 0.35, green: 0.6, blue: 1),
                         Color(red: 0.72, green: 0.45, blue: 1)]
    static let gradient = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The hero ring: soft pulses while idle, a spinning gradient arc while scanning, a filling
/// arc while cleaning, and a glowing full ring once there is a result.
private struct CleanupRing: View {
    let phase: CleanupModel.Phase
    let progress: Double
    let colors: [Color]

    private var moving: Bool { phase == .idle || phase == .scanning }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if moving {
                    ForEach(0..<3, id: \.self) { index in
                        let cycle = phase == .scanning ? 1.6 : 3.2
                        let wave = (time / cycle + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(colors[index % colors.count].opacity((1 - wave) * (phase == .scanning ? 0.5 : 0.22)),
                                    lineWidth: 2)
                            .scaleEffect(0.8 + wave * 0.55)
                    }
                }
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 14)
                switch phase {
                case .idle:
                    Circle()
                        .stroke(ringGradient, lineWidth: 14)
                        .opacity(0.35)
                case .scanning:
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(ringGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(time * 260))
                        .shadow(color: colors[0].opacity(0.6), radius: 10)
                case .cleaning:
                    Circle()
                        .trim(from: 0, to: max(0.01, progress))
                        .stroke(ringGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: colors[1].opacity(0.6), radius: 10)
                        .animation(.easeOut(duration: 0.35), value: progress)
                case .results, .done:
                    Circle()
                        .stroke(ringGradient, lineWidth: 14)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: colors[0].opacity(phase == .done ? 0.7 : 0.4), radius: phase == .done ? 18 : 10)
                }
            }
        }
    }

    private var ringGradient: AngularGradient {
        AngularGradient(colors: colors + [colors[0]], center: .center)
    }
}

/// A byte count that rolls smoothly from its old value to the new one.
struct ByteCountText: View {
    let bytes: Double

    var body: some View {
        RollingBytes(bytes: bytes)
            .animation(.easeOut(duration: 0.35), value: bytes)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct RollingBytes: View, Animatable {
    var bytes: Double

    var animatableData: Double {
        get { bytes }
        set { bytes = newValue }
    }

    var body: some View {
        Text(ByteCountText.format(Int64(bytes)))
            .monospacedDigit()
    }
}

struct CheckmarkPop: View {
    let gradient: LinearGradient
    @State private var shown = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(gradient)
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { shown = true }
            }
    }
}

/// Sparkles that fly out from the ring when cleaning finishes.
struct SparkleBurst: View {
    let colors: [Color]
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) / 16 * 2 * .pi
                let distance: Double = index.isMultiple(of: 2) ? 135 : 115
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 13 : 5))
                    .foregroundStyle(colors[index % colors.count])
                    .offset(x: fired ? cos(angle) * distance : cos(angle) * 60,
                            y: fired ? sin(angle) * distance : sin(angle) * 60)
                    .scaleEffect(fired ? 0.3 : 1.2)
                    .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { fired = true }
        }
    }
}

struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .frame(height: 38)
            .background(gradient, in: Capsule())
            .shadow(color: Color(red: 0.35, green: 0.6, blue: 1).opacity(isEnabled ? 0.45 : 0), radius: 12, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
