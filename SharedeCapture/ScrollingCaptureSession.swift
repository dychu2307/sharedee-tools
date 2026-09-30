import AppKit
import ApplicationServices
import SwiftUI

/// Interactive scrolling capture: select an area, press Capture, then scroll by hand or let the
/// app scroll for you. Frames are stitched as they arrive.
@MainActor
final class ScrollingCaptureSession: ObservableObject {
    enum Phase { case selecting, ready, capturing, ended }

    @Published private(set) var phase = Phase.selecting
    @Published private(set) var isAutoScrolling = false
    @Published private(set) var capturedHeight = 0
    @Published private(set) var hint: String?

    private let maxHeight: Int
    private let screen: NSScreen
    private var region: CGRect?
    private var overlay: OverlayPanel!
    private var controls: FloatingPanel!
    private var scrollButton: FloatingPanel!
    private var captureTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stitcher: ScrollStitcher?
    private let stitchQueue = DispatchQueue(label: "SharedeCapture.stitch", qos: .userInitiated)

    /// Whether auto-scroll has moved the content since it was turned on.
    private var autoScrollMoved = false
    private var stillFrames = 0
    /// Frames in a row that could not be matched; auto-scroll waits for a match before moving on.
    private var unmatchedFrames = 0

    /// Runs a session on the screen under the pointer and returns the stitched image.
    static func run(maxHeight: Int) async throws -> CGImage {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        else { throw ScrollingCaptureError.captureFailed }
        let session = ScrollingCaptureSession(screen: screen, maxHeight: maxHeight)
        return try await withCheckedThrowingContinuation { continuation in
            session.continuation = continuation
            session.present()
        }
    }

    private init(screen: NSScreen, maxHeight: Int) {
        self.screen = screen
        self.maxHeight = maxHeight
    }

    // MARK: Windows

    private func present() {
        let overlay = OverlayPanel(screen: screen)
        overlay.selectionView.session = self
        self.overlay = overlay
        controls = FloatingPanel(rootView: AnyView(ScrollingControlBar(session: self)))
        scrollButton = FloatingPanel(rootView: AnyView(AutoScrollButton(session: self)))
        overlay.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    private func closeWindows() {
        NSCursor.pop()
        overlay?.orderOut(nil)
        controls?.orderOut(nil)
        scrollButton?.orderOut(nil)
    }

    private func placeControls() {
        guard phase != .ended, let region else { return }
        let visible = screen.visibleFrame
        let size = controls.fittedSize()
        var y = region.minY - size.height - 12
        if y < visible.minY + 8 { y = region.maxY + 12 }
        if y + size.height > visible.maxY - 8 { y = region.minY + 12 }
        let x = min(max(region.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        controls.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        controls.orderFront(nil)
    }

    private func placeScrollButton() {
        guard phase != .ended, let region else { return }
        let size = scrollButton.fittedSize()
        let y = region.height > size.height + 40 ? region.minY + 18 : region.minY - size.height - 60
        scrollButton.setFrame(CGRect(x: region.midX - size.width / 2, y: y,
                                     width: size.width, height: size.height), display: true)
        scrollButton.orderFront(nil)
    }

    // MARK: Selection

    fileprivate func selectionChanged(_ rect: CGRect?, finished: Bool) {
        guard phase == .selecting || phase == .ready else { return }
        guard let rect, rect.width >= 40, rect.height >= 40 else {
            if finished && region == nil { phase = .selecting }
            controls.orderOut(nil)
            return
        }
        region = rect
        if finished {
            phase = .ready
            placeControls()
        } else {
            controls.orderOut(nil)
        }
    }

    fileprivate var selectedRegion: CGRect? { region }

    // MARK: Capture

    func startCapture() {
        guard phase == .ready, let region else { return }
        phase = .capturing
        overlay.ignoresMouseEvents = true
        overlay.selectionView.needsDisplay = true
        placeControls()
        placeScrollButton()
        let capturer = RegionCapturer(rect: region, screen: screen,
                                      excluding: [overlay, controls, scrollButton])
        captureTask = Task { [weak self] in await self?.captureLoop(capturer) }
    }

    private func captureLoop(_ capturer: RegionCapturer) async {
        do {
            guard let first = PixelFrame(try await capturer.capture()) else { throw ScrollingCaptureError.captureFailed }
            let stitcher = ScrollStitcher(first: first, maxHeight: maxHeight)
            self.stitcher = stitcher
            capturedHeight = stitcher.height
            while !Task.isCancelled && phase == .capturing {
                if isAutoScrolling {
                    if unmatchedFrames == 0 {
                        // Scrolling on before the last frame matched would lose the thread.
                        scrollOnce()
                    }
                    try await Task.sleep(nanoseconds: 280_000_000)
                } else {
                    try await Task.sleep(nanoseconds: 90_000_000)
                }
                let image = try await capturer.capture()
                let result = await stitch(image, into: stitcher)
                guard !Task.isCancelled, phase == .capturing else { return }
                switch result {
                case .appended:
                    stillFrames = 0
                    unmatchedFrames = 0
                    if isAutoScrolling { autoScrollMoved = true }
                    capturedHeight = stitcher.height
                case .unchanged:
                    unmatchedFrames = 0
                    guard isAutoScrolling else { break }
                    stillFrames += 1
                    if autoScrollMoved {
                        // Still frames after the content has been moving: the end is reached.
                        if stillFrames >= 3 { finish(); return }
                    } else if stillFrames == 4 {
                        showHint(L10n.tr("Đặt con trỏ chuột lên phần nội dung cần cuộn trong vùng chọn."), seconds: 4)
                    }
                case .noMatch:
                    unmatchedFrames += 1
                    if isAutoScrolling && unmatchedFrames >= 5 {
                        isAutoScrolling = false
                        unmatchedFrames = 0
                        showHint(L10n.tr("Nội dung thay đổi liên tục nên không ghép được. Hãy tạm dừng video hoặc cuộn bằng tay."), seconds: 5)
                    } else if !isAutoScrolling {
                        showHint(L10n.tr("Cuộn chậm lại một chút để ảnh ghép khớp."))
                    }
                case .limitReached:
                    capturedHeight = stitcher.height
                    finish()
                    return
                }
            }
        } catch is CancellationError {
        } catch {
            fail(error)
        }
    }

    private func stitch(_ image: CGImage, into stitcher: ScrollStitcher) async -> ScrollStitcher.Result {
        await withCheckedContinuation { continuation in
            stitchQueue.async {
                guard let frame = PixelFrame(image) else { return continuation.resume(returning: .noMatch) }
                continuation.resume(returning: stitcher.add(frame))
            }
        }
    }

    func toggleAutoScroll() {
        guard phase == .capturing else { return }
        if isAutoScrolling {
            isAutoScrolling = false
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            showHint(L10n.tr("Tự cuộn cần quyền Trợ năng. Bạn vẫn có thể tự cuộn bằng chuột."), seconds: 5)
            return
        }
        autoScrollMoved = false
        stillFrames = 0
        unmatchedFrames = 0
        isAutoScrolling = true
        showHint(L10n.tr("Tự cuộn tại vị trí con trỏ chuột. Đặt chuột lên nội dung cần cuộn."), seconds: 3)
    }

    /// Scrolls wherever the pointer is, exactly like turning the mouse wheel, so the user picks
    /// what scrolls by pointing at it. Skipped while the pointer is over our own controls.
    private func scrollOnce() {
        guard let region else { return }
        let pointer = NSEvent.mouseLocation
        if controls.frame.contains(pointer) || scrollButton.frame.contains(pointer) { return }
        let amount = Int32(min(520, max(80, region.height * 0.45)))
        CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState), units: .pixel,
                wheelCount: 1, wheel1: -amount, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func showHint(_ text: String, seconds: Double = 2.5) {
        hint = text
        placeControls()
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.hint = nil
            self.placeControls()
        }
    }

    // MARK: Ending

    func finish() {
        guard let continuation else { return }
        guard phase == .capturing, let stitcher else { return startCapture() }
        end()
        stitchQueue.async {
            let image = stitcher.render()
            DispatchQueue.main.async {
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: ScrollingCaptureError.captureFailed) }
            }
        }
    }

    func cancel() {
        fail(ScrollingCaptureError.cancelled)
    }

    private func fail(_ error: Error) {
        guard let continuation else { return }
        end()
        continuation.resume(throwing: error)
    }

    /// Stops all work and removes the session's windows for good; nothing can show them again.
    private func end() {
        continuation = nil
        phase = .ended
        isAutoScrolling = false
        captureTask?.cancel()
        hintTask?.cancel()
        closeWindows()
    }
}

// MARK: - Overlay

/// Full-screen panel that dims everything but the selected area and handles the selection drag.
private final class OverlayPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    weak var session: ScrollingCaptureSession?
    private var dragOrigin: CGPoint?
    private var draft: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The selection in this view's coordinates.
    private var shownRect: CGRect? {
        if let draft { return draft }
        guard let region = session?.selectedRegion, let window else { return nil }
        return region.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        let capturing = session?.phase == .capturing
        NSColor.black.withAlphaComponent(capturing ? 0.28 : 0.38).setFill()
        let dim = NSBezierPath(rect: bounds)
        if let rect = shownRect {
            dim.append(NSBezierPath(rect: rect))
            dim.windingRule = .evenOdd
        }
        dim.fill()
        guard let rect = shownRect else {
            drawLabel(L10n.tr("Kéo để chọn vùng cần chụp cuộn · Esc để hủy"),
                      at: CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }
        let border = NSBezierPath(rect: rect.insetBy(dx: -1.5, dy: -1.5))
        border.lineWidth = 2
        NSColor(red: 0.31, green: 0.87, blue: 0.78, alpha: 1).setStroke()
        border.stroke()
        if !capturing {
            let scale = window?.backingScaleFactor ?? 2
            drawLabel("\(Int(rect.width * scale)) × \(Int(rect.height * scale))",
                      at: CGPoint(x: rect.midX, y: rect.maxY + 16))
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: point.x - size.width / 2 - 8, y: point.y - size.height / 2 - 4,
                         width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 8, y: box.minY + 4), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        draft = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        draft = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                       width: abs(point.x - origin.x), height: abs(point.y - origin.y)).integral
        session?.selectionChanged(globalRect(draft), finished: false)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = globalRect(draft)
        draft = nil
        dragOrigin = nil
        session?.selectionChanged(rect, finished: true)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: session?.cancel()                // Esc
        case 36, 76: session?.finish()            // Return, Enter
        default: super.keyDown(with: event)
        }
    }

    private func globalRect(_ rect: CGRect?) -> CGRect? {
        guard let rect, let window else { return nil }
        return rect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
    }
}

// MARK: - Floating controls

private final class FloatingPanel: NSPanel {
    init(rootView: AnyView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: rootView.environment(\.colorScheme, .dark))
    }

    func fittedSize() -> CGSize {
        contentView?.layoutSubtreeIfNeeded()
        return contentView?.fittingSize ?? .zero
    }
}

private struct ScrollingControlBar: View {
    @ObservedObject var session: ScrollingCaptureSession
    private let accent = Color(red: 0.31, green: 0.87, blue: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if session.phase == .capturing {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(L10n.format("Đã ghép %@ px", session.capturedHeight.formatted()))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 110, alignment: .leading)
                    Button(L10n.tr("Xong")) { session.finish() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Text(L10n.tr("Kéo lại để đổi vùng"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        session.startCapture()
                    } label: {
                        Label(L10n.tr("Chụp"), systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
                }
                Button(L10n.tr("Hủy")) { session.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
            if session.phase == .capturing && session.hint == nil {
                Text(L10n.tr("Cuộn trong vùng chọn, hoặc bấm Tự cuộn."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hint = session.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14)))
        .fixedSize()
    }
}

private struct AutoScrollButton: View {
    @ObservedObject var session: ScrollingCaptureSession

    var body: some View {
        Button { session.toggleAutoScroll() } label: {
            Label(session.isAutoScrolling ? L10n.tr("Dừng tự cuộn") : L10n.tr("Tự cuộn"),
                  systemImage: session.isAutoScrolling ? "pause.fill" : "arrow.down.to.line")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .overlay(Capsule().stroke(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
