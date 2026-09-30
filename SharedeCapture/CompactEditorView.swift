import AppKit
import SwiftUI

/// The focused editor shown after choosing Edit from the capture thumbnail.
struct CompactEditorView: View {
    @EnvironmentObject private var state: CaptureState
    @EnvironmentObject private var drive: GoogleDriveService
    @ObservedObject private var language = LanguageSettings.shared
    @State private var isUploading = false
    /// Snapshot shown while Live Text is on; nil when the annotation canvas is active.
    @State private var liveTextImage: NSImage?
    @State private var liveTextFound: Bool?
    @State private var isCopyingText = false
    let onFinish: () -> Void

    private let accent = Color(red: 0.31, green: 0.87, blue: 0.78)
    private let chrome = Color(red: 0.11, green: 0.125, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            controls
        }
        .background(Color(red: 0.075, green: 0.088, blue: 0.108))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)))
        .onExitCommand(perform: onFinish)
    }

    @ViewBuilder private var canvas: some View {
        if #available(macOS 13.0, *), let liveTextImage {
            LiveTextView(image: liveTextImage) { liveTextFound = $0 }
        } else {
            EditorCanvas(state: state)
        }
    }

    private var isLiveTextOn: Bool { liveTextImage != nil }

    private var supportsLiveText: Bool {
        if #available(macOS 13.0, *) { return LiveTextView.isSupported }
        return false
    }

    private func toggleLiveText() {
        if isLiveTextOn {
            liveTextImage = nil
        } else {
            liveTextFound = nil
            liveTextImage = state.renderedImage()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    liveTextImage = nil
                    state.tool = tool
                    if tool != .crop { state.cropRect = nil }
                } label: {
                    let active = state.tool == tool && !isLiveTextOn
                    Image(systemName: tool.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 34)
                        .foregroundStyle(active ? accent : .white.opacity(0.8))
                        .background(active ? accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(tool.title)
                .accessibilityLabel(tool.title)
            }

            if supportsLiveText {
                Divider().frame(height: 22).padding(.horizontal, 4)
                Button(action: toggleLiveText) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 34)
                        .foregroundStyle(isLiveTextOn ? accent : .white.opacity(0.8))
                        .background(isLiveTextOn ? accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Chọn chữ trên ảnh (Live Text)"))
                .accessibilityLabel(L10n.tr("Chọn chữ trên ảnh (Live Text)"))
            }

            Spacer(minLength: 4)

            if state.cropRect != nil {
                Button(L10n.tr("Cắt ảnh")) { state.applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            Button { state.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 30)
            }
            .disabled(!state.canUndo)
            .help(L10n.tr("Hoàn tác"))
            Button { state.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 30)
            }
            .disabled(!state.canRedo)
            .help(L10n.tr("Làm lại"))
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 30)
            }
            .help(L10n.tr("Đóng"))
            .accessibilityLabel(L10n.tr("Đóng cửa sổ chỉnh sửa"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(chrome)
    }

    private var liveTextControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.viewfinder").foregroundStyle(accent)
            Group {
                switch liveTextFound {
                case nil: Text(L10n.tr("Đang tìm chữ trong ảnh…"))
                case true?: Text(L10n.tr("Bôi đen chữ trên ảnh để sao chép một phần."))
                case false?: Text(L10n.tr("Không tìm thấy chữ trong ảnh"))
                }
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                isCopyingText = true
                Task {
                    let result = await state.copyRecognizedText()
                    isCopyingText = false
                    AppRuntime.shared.showToast(for: result)
                }
            } label: {
                Label(L10n.tr("Sao chép toàn bộ chữ"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .disabled(isCopyingText || liveTextFound == false)
            Button(L10n.tr("Xong")) { liveTextImage = nil }
                .buttonStyle(.bordered)
        }
        .font(.system(size: 12))
        .frame(height: 42)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if isLiveTextOn {
                liveTextControls
            } else {
            HStack(spacing: 12) {
                ColorPicker(L10n.tr("Màu"), selection: Binding(
                    get: { Color(nsColor: state.color) },
                    set: { state.color = NSColor($0) }
                ), supportsOpacity: false)
                .fixedSize()

                Slider(value: $state.lineWidth, in: 2...16)
                    .frame(width: 108)
                    .help(L10n.tr("Độ dày nét vẽ"))
                Text("\(Int(state.lineWidth)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                if state.selectedAnnotation?.tool == .text {
                    TextField(L10n.tr("Nội dung chữ"), text: Binding(
                        get: { state.selectedAnnotation?.text ?? "" },
                        set: { state.setSelectedText($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                }

                if state.selectedID != nil {
                    Button(L10n.tr("Xóa")) { state.deleteSelected() }
                        .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .frame(height: 42)
            }

            HStack(spacing: 10) {
                Text(state.imageDimensions)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                if drive.isConnected {
                    Button {
                        isUploading = true
                        Task {
                            let uploaded = await state.uploadImageToDrive()
                            isUploading = false
                            if uploaded { onFinish() }
                        }
                    } label: {
                        if isUploading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr("Đang tải…"))
                            }
                        } else {
                            Label(L10n.tr("Tải lên Drive"), systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading)
                }
                Button {
                    if state.copyImage() { onFinish() }
                } label: {
                    Label(L10n.tr("Sao chép"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                Button {
                    if state.saveImage() { onFinish() }
                } label: {
                    Label(L10n.tr("Lưu ảnh"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            .font(.system(size: 12))
            .frame(height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
        .background(chrome)
    }
}
