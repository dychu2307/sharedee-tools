import AppKit
import SwiftUI

private final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickAccessController {
    private var panel: QuickAccessPanel?
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(image: NSImage,
              onCopy: @escaping () -> Void,
              onEdit: @escaping () -> Void,
              onSave: @escaping () -> Void,
              onDismiss: @escaping () -> Void) {
        dismiss()
        let size = CGSize(width: 338, height: 248)
        let panel = QuickAccessPanel(contentRect: CGRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            QuickAccessView(image: image, onCopy: onCopy, onEdit: onEdit,
                            onSave: onSave, onDismiss: onDismiss)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(CGPoint(x: visible.maxX - size.width - 22,
                                    y: visible.minY + 22))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct QuickAccessView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.31, green: 0.87, blue: 0.78))
                Text("Đã chụp ảnh")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Đóng thumbnail")
            }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 153)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.1)))

            HStack(spacing: 7) {
                actionButton("Sao chép", symbol: "doc.on.doc", prominent: true, action: onCopy)
                actionButton("Chỉnh sửa", symbol: "pencil", action: onEdit)
                actionButton("Lưu", symbol: "square.and.arrow.down", action: onSave)
            }
        }
        .padding(12)
        .background(Color(red: 0.13, green: 0.15, blue: 0.18),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.13)))
    }

    private func actionButton(_ title: String, symbol: String, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color(red: 0.08, green: 0.13, blue: 0.14) : .white)
        .background(prominent ? Color(red: 0.31, green: 0.87, blue: 0.78)
                             : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}
