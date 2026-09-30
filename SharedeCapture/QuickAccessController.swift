import AppKit
import SwiftUI

private final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

fileprivate struct QuickAccessItem: Identifiable {
    let id: UUID
    let image: NSImage
    let status: String
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onUpload: (() -> Void)?
    let onDismiss: () -> Void
}

enum QuickAccessUploadState: Equatable {
    case idle
    case uploading
    case uploaded(URL)
    case failed(String)
}

@MainActor
final class QuickAccessController: ObservableObject {
    @Published private var items: [QuickAccessItem] = []
    @Published private var uploads: [UUID: QuickAccessUploadState] = [:]
    private var panel: QuickAccessPanel?
    private let cardSize = CGSize(width: 405, height: 248)
    private let spacing: CGFloat = 10

    var isVisible: Bool { panel?.isVisible ?? false }
    var count: Int { items.count }

    func show(id: UUID, image: NSImage, status: String,
              onCopy: @escaping () -> Void,
              onEdit: @escaping () -> Void,
              onSave: @escaping () -> Void,
              onUpload: (() -> Void)?,
              onDismiss: @escaping () -> Void) {
        if panel == nil { createPanel() }
        items.append(QuickAccessItem(id: id, image: image, status: status,
                                     onCopy: onCopy, onEdit: onEdit, onSave: onSave,
                                     onUpload: onUpload, onDismiss: onDismiss))
        layoutPanel()
        panel?.orderFrontRegardless()
    }

    func uploadState(for id: UUID) -> QuickAccessUploadState { uploads[id] ?? .idle }

    func setUploadState(_ state: QuickAccessUploadState, for id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        uploads[id] = state
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        uploads[id] = nil
        if items.isEmpty { panel?.orderOut(nil) }
        else { layoutPanel() }
    }

    func hideAll() { panel?.orderOut(nil) }

    func restoreAll() {
        guard !items.isEmpty else { return }
        layoutPanel()
        panel?.orderFrontRegardless()
    }

    private func createPanel() {
        let panel = QuickAccessPanel(contentRect: CGRect(origin: .zero, size: cardSize),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            QuickAccessStackView(controller: self, cardSize: cardSize, spacing: spacing)
                .preferredColorScheme(.dark)
        )
        self.panel = panel
    }

    private func layoutPanel() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let contentHeight = CGFloat(items.count) * cardSize.height
            + CGFloat(max(0, items.count - 1)) * spacing
        let height = min(contentHeight, visible.height - 44)
        panel.setContentSize(CGSize(width: cardSize.width, height: height))
        panel.setFrameOrigin(CGPoint(x: visible.maxX - cardSize.width - 22,
                                    y: visible.minY + 22))
    }

    fileprivate var visibleItems: [QuickAccessItem] { items }
}

private struct QuickAccessStackView: View {
    @ObservedObject var controller: QuickAccessController
    let cardSize: CGSize
    let spacing: CGFloat

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical) {
                VStack(spacing: spacing) {
                    ForEach(controller.visibleItems) { item in
                        QuickAccessView(item: item, upload: controller.uploadState(for: item.id))
                            .frame(width: cardSize.width, height: cardSize.height)
                            .id(item.id)
                    }
                }
            }
            .onChange(of: controller.count) { _ in
                if let newest = controller.visibleItems.last {
                    scroll.scrollTo(newest.id, anchor: .bottom)
                }
            }
        }
        .frame(width: cardSize.width)
    }
}

private struct QuickAccessView: View {
    let item: QuickAccessItem
    let upload: QuickAccessUploadState
    @ObservedObject private var language = LanguageSettings.shared

    private var headerText: String {
        switch upload {
        case .idle: item.status
        case .uploading: L10n.tr("Đang tải lên Google Drive…")
        case .uploaded: L10n.tr("Đã tải lên Google Drive")
        case .failed(let message): message
        }
    }

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                headerIcon
                Text(headerText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int(item.image.size.width)) × \(Int(item.image.size.height))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: item.onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Đóng thumbnail"))
            }

            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 153)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.1)))

            HStack(spacing: 7) {
                actionButton(L10n.tr("Sao chép"), symbol: "doc.on.doc", prominent: true, action: item.onCopy)
                actionButton(L10n.tr("Chỉnh sửa"), symbol: "pencil", action: item.onEdit)
                actionButton(L10n.tr("Lưu"), symbol: "square.and.arrow.down", action: item.onSave)
                if let onUpload = item.onUpload {
                    driveButton(action: onUpload)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.13, green: 0.15, blue: 0.18),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.13)))
    }

    @ViewBuilder private var headerIcon: some View {
        switch upload {
        case .uploading:
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle, .uploaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.31, green: 0.87, blue: 0.78))
        }
    }

    @ViewBuilder private func driveButton(action: @escaping () -> Void) -> some View {
        switch upload {
        case .idle:
            actionButton("Drive", symbol: "arrow.up.doc", action: action)
        case .uploading:
            Button(action: {}) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text(L10n.tr("Đang tải…"))
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .disabled(true)
        case .uploaded:
            actionButton(L10n.tr("Mở"), symbol: "checkmark.circle.fill", tint: .green, action: action)
                .help(L10n.tr("Mở ảnh trên Google Drive"))
        case .failed:
            actionButton(L10n.tr("Thử lại"), symbol: "arrow.clockwise", tint: .orange, action: action)
        }
    }

    private func actionButton(_ title: String, symbol: String, prominent: Bool = false,
                              tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color(red: 0.08, green: 0.13, blue: 0.14) : tint ?? .white)
        .background(prominent ? Color(red: 0.31, green: 0.87, blue: 0.78)
                             : (tint ?? .white).opacity(tint == nil ? 0.1 : 0.18),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}
