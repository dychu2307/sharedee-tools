import SwiftUI

private enum Palette {
    static let background = Color(red: 0.075, green: 0.088, blue: 0.108)
    static let sidebar = Color(red: 0.11, green: 0.125, blue: 0.15)
    static let panel = Color(red: 0.14, green: 0.16, blue: 0.19)
    static let accent = Color(red: 0.31, green: 0.87, blue: 0.78)
    static let muted = Color(red: 0.58, green: 0.62, blue: 0.67)
}

struct ContentView: View {
    @EnvironmentObject private var state: CaptureState
    @EnvironmentObject private var shortcuts: ShortcutSettings

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 238)
                .background(Palette.sidebar)
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
            workspace
        }
        .background(Palette.background)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 39, height: 39)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHAREDEE TOOLS")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(1.8)
                    Text("CHỤP & CHỈNH SỬA")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 36)

            sectionLabel("CHỤP ẢNH")
            VStack(spacing: 8) {
                captureButton(.area, shortcut: shortcuts.shortcut(for: .area).display, prominent: true)
                captureButton(.window, shortcut: shortcuts.shortcut(for: .window).display)
                captureButton(.fullScreen, shortcut: shortcuts.shortcut(for: .fullScreen).display)
                Button { Task { await state.captureScrolling() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "scroll")
                            .frame(width: 21)
                        Text("Chụp cuộn")
                        Spacer()
                        Text(shortcuts.shortcut(for: .scrolling).display)
                            .font(.system(size: 10))
                            .opacity(0.65)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 41)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(state.isCapturing)
            }
            .padding(.top, 12)

            sectionLabel("THƯ VIỆN")
                .padding(.top, 35)
            Button { state.openImage() } label: {
                Label("Mở ảnh…", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())
            .padding(.top, 10)
            Button { AppRuntime.shared.showSettings() } label: {
                Label("Cài đặt & phím tắt…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())

            if !state.recent.isEmpty {
                sectionLabel("ẢNH VỪA CHỤP")
                    .padding(.top, 31)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(state.recent) { item in
                            Button { state.openRecent(item) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.mode.symbol)
                                        .frame(width: 17)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.mode.title)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(item.capturedAt, style: .time)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SidebarButtonStyle())
                        }
                    }
                }
                .frame(maxHeight: 170)
                .padding(.top, 8)
            }

            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Palette.accent)
                Text("Chụp, ghi chú và chia sẻ chỉ trong một app.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 17)
        }
        .padding(.horizontal, 17)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Palette.muted)
    }

    private func captureButton(_ mode: CaptureMode, shortcut: String,
                               prominent: Bool = false) -> some View {
        Button { Task { await state.capture(mode) } } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 21)
                Text(mode.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.65)
            }
            .padding(.horizontal, 13)
            .frame(height: 41)
            .background(prominent ? Palette.accent : Palette.panel,
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(prominent ? Palette.background : .white)
        }
        .buttonStyle(.plain)
        .disabled(state.isCapturing)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            if state.image != nil {
                tools
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                EditorCanvas(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            statusBar
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.image == nil ? "Chào mừng" : "Chỉnh sửa ảnh")
                    .font(.system(size: 19, weight: .semibold))
                Text(state.image == nil ? "Bắt đầu với một ảnh chụp màn hình" : state.imageDimensions)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            if state.image != nil {
                Button { Task { await state.copyRecognizedText() } } label: {
                    Label("Lấy chữ", systemImage: "text.viewfinder")
                }
                .buttonStyle(QuietActionStyle())
                Button { state.pinImage() } label: {
                    Label("Ghim", systemImage: "pin")
                }
                .buttonStyle(QuietActionStyle())
                Button { state.copyImage() } label: {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
                .buttonStyle(QuietActionStyle())
                Button { state.saveImage() } label: {
                    Label("Lưu PNG", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(AccentActionStyle())
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 74)
    }

    private var tools: some View {
        HStack(spacing: 5) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    state.tool = tool
                    if tool != .crop { state.cropRect = nil }
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 37, height: 37)
                        .foregroundStyle(state.tool == tool ? Palette.accent : .white.opacity(0.75))
                        .background(state.tool == tool ? Palette.accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }
            Spacer(minLength: 10)
            if state.cropRect != nil {
                Button("Cắt ảnh") { state.applyCrop() }
                    .buttonStyle(AccentActionStyle())
            }
            Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolActionStyle())
                .disabled(!state.canUndo)
                .help("Hoàn tác")
            Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolActionStyle())
                .disabled(!state.canRedo)
                .help("Làm lại")
        }
        .padding(.horizontal, 19)
        .frame(height: 57)
    }

    private var inspector: some View {
        HStack(spacing: 16) {
            Text("NÉT VẼ")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Palette.muted)
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: state.color) },
                set: { state.color = NSColor($0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 42)
            Slider(value: $state.lineWidth, in: 2...16)
                .frame(width: 130)
            Text("\(Int(state.lineWidth)) px")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.muted)
                .frame(width: 36, alignment: .leading)
            if let selected = state.selectedAnnotation, selected.tool == .text {
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                TextField("Nội dung chữ", text: Binding(
                    get: { state.selectedAnnotation?.text ?? "" },
                    set: { state.setSelectedText($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }
            Spacer()
            if state.selectedID != nil {
                Button("Xóa") { state.deleteSelected() }
                    .buttonStyle(QuietActionStyle())
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 57)
        .background(Palette.sidebar)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "viewfinder")
                .font(.system(size: 47, weight: .ultraLight))
                .foregroundStyle(Palette.accent)
                .frame(width: 112, height: 112)
                .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.accent.opacity(0.18)))
            VStack(spacing: 7) {
                Text("Chụp điều bạn muốn chia sẻ")
                    .font(.system(size: 24, weight: .semibold))
                Text("Chọn một vùng, một cửa sổ hoặc toàn màn hình để bắt đầu.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 10) {
                Button { Task { await state.capture(.area) } } label: {
                    Label("Chụp vùng chọn", systemImage: "selection.pin.in.out")
                }
                .buttonStyle(AccentActionStyle())
                Button { state.openImage() } label: {
                    Label("Mở ảnh", systemImage: "folder")
                }
                .buttonStyle(QuietActionStyle())
            }
            .padding(.top, 7)
        }
        .padding(32)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(state.isCapturing ? Color.orange : Palette.accent)
                .frame(width: 6, height: 6)
            Text(state.status)
                .lineLimit(1)
            Spacer()
            Text(state.image == nil ? "macOS" : "PNG · Độ phân giải gốc")
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 24)
        .frame(height: 28)
        .background(Palette.sidebar)
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.82))
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(configuration.isPressed ? Palette.panel : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AccentActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.72 : 1),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuietActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToolActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.8))
            .frame(width: 34, height: 34)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
