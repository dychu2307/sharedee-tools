import AppKit
import SwiftUI
import Vision

struct RecentCapture: Identifiable {
    let id = UUID()
    let url: URL
    let capturedAt: Date
    let mode: CaptureMode
}

@MainActor
final class CaptureState: ObservableObject {
    weak var preferences: ShortcutSettings?
    var willCapture: (() -> Void)?
    var didCapture: (() -> Void)?
    var captureFailed: (() -> Void)?
    @Published var image: NSImage?
    @Published var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var tool: EditorTool = .pen
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 5
    @Published var cropRect: CGRect?
    @Published var recent: [RecentCapture] = []
    @Published var status = "Sẵn sàng chụp"
    @Published var isCapturing = false

    private struct Snapshot {
        let image: NSImage?
        let annotations: [Annotation]
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var pinnedWindows: [NSPanel] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedAnnotation: Annotation? { annotations.first { $0.id == selectedID } }
    var imageDimensions: String {
        guard let image else { return "Chưa có ảnh" }
        return "\(Int(image.size.width)) × \(Int(image.size.height)) px"
    }

    func perform(_ action: ShortcutAction) async {
        switch action {
        case .area: await capture(.area)
        case .window: await capture(.window)
        case .fullScreen: await capture(.fullScreen)
        case .scrolling: await captureScrolling()
        case .captureText: await captureText()
        }
    }

    @discardableResult
    func capture(_ mode: CaptureMode) async -> Bool {
        guard !isCapturing else { return false }
        isCapturing = true
        status = "Đang chụp: \(mode.title.lowercased())…"
        willCapture?()
        NSApp.hide(nil)
        try? await Task.sleep(nanoseconds: UInt64(350 + (preferences?.captureDelay ?? 0) * 1000) * 1_000_000)
        do {
            let url = try await ScreenshotService.capture(mode,
                                                          includeCursor: preferences?.includeCursor ?? false)
            NSApp.unhideWithoutActivation()
            try loadImage(at: url)
            recent.insert(RecentCapture(url: url, capturedAt: .now, mode: mode), at: 0)
            recent = Array(recent.prefix(8))
            status = "Đã chụp \(mode.title.lowercased()) · \(imageDimensions)"
            if preferences?.autoCopy == true { copyImage() }
            didCapture?()
            isCapturing = false
            return true
        } catch {
            NSApp.unhideWithoutActivation()
            status = error.localizedDescription
            captureFailed?()
            isCapturing = false
            return false
        }
    }

    func captureText() async {
        guard await capture(.area) else { return }
        await copyRecognizedText()
    }

    func captureScrolling() async {
        guard !isCapturing else { return }
        isCapturing = true
        status = "Đang chụp cuộn…"
        willCapture?()
        NSApp.hide(nil)
        try? await Task.sleep(nanoseconds: UInt64(350 + (preferences?.captureDelay ?? 0) * 1000) * 1_000_000)
        do {
            let url = try await ScrollingCaptureService.capture(
                maxFrames: preferences?.maxScrollFrames ?? 10)
            NSApp.unhideWithoutActivation()
            try loadImage(at: url)
            recent.insert(RecentCapture(url: url, capturedAt: .now, mode: .scrolling), at: 0)
            recent = Array(recent.prefix(8))
            status = "Đã chụp cuộn · \(imageDimensions)"
            if preferences?.autoCopy == true { copyImage() }
            didCapture?()
        } catch {
            NSApp.unhideWithoutActivation()
            status = error.localizedDescription
            captureFailed?()
        }
        isCapturing = false
    }

    func copyRecognizedText() async {
        guard let data = renderedPNG(), let bitmap = NSBitmapImageRep(data: data),
              let image = bitmap.cgImage else { return }
        status = "Đang nhận dạng chữ…"
        do {
            let recognized = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = true
                        try VNImageRequestHandler(cgImage: image).perform([request])
                        let text = (request.results ?? [])
                            .compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: "\n")
                        continuation.resume(returning: text)
                    } catch { continuation.resume(throwing: error) }
                }
            }
            guard !recognized.isEmpty else {
                status = "Không tìm thấy chữ trong ảnh"
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recognized, forType: .string)
            status = "Đã sao chép chữ nhận dạng vào clipboard"
        } catch { status = error.localizedDescription }
    }

    func pinImage() {
        guard let data = renderedPNG(), let image = NSImage(data: data) else { return }
        let width: CGFloat = min(520, image.size.width)
        let height = width * image.size.height / image.size.width
        let panel = NSPanel(contentRect: CGRect(x: 180, y: 180, width: width,
                                                height: min(height, 640)),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Ảnh ghim"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = CGSize(width: 180, height: 120)
        let imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        panel.contentView = imageView
        panel.makeKeyAndOrderFront(nil)
        pinnedWindows.removeAll { !$0.isVisible }
        pinnedWindows.append(panel)
        status = "Đã ghim ảnh lên màn hình"
    }

    @discardableResult
    func openImage() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try loadImage(at: url)
            status = "Đã mở \(url.lastPathComponent)"
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func openRecent(_ capture: RecentCapture) -> Bool {
        do {
            try loadImage(at: capture.url)
            status = "Đã mở ảnh \(capture.mode.title.lowercased())"
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    private func loadImage(at url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let bitmap = NSBitmapImageRep(data: data), let cgImage = bitmap.cgImage else {
            throw CocoaError(.fileReadCorruptFile)
        }
        image = NSImage(cgImage: cgImage, size: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        annotations = []
        selectedID = nil
        cropRect = nil
        tool = .pen
        undoStack = []
        redoStack = []
    }

    private func checkpoint() {
        undoStack.append(Snapshot(image: image, annotations: annotations))
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        selectedID = annotation.tool == .text ? annotation.id : nil
        if annotation.tool == .text { tool = .select }
        status = "Đã thêm \(annotation.tool.title.lowercased())"
    }

    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        checkpoint()
        annotations[index] = annotation
        status = "Đã di chuyển chú thích"
    }

    func setSelectedText(_ text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .text,
              annotations[index].text != text else { return }
        checkpoint()
        annotations[index].text = text
        status = "Đã sửa chữ"
    }

    func deleteSelected() {
        guard selectedID != nil else { return }
        checkpoint()
        annotations.removeAll { $0.id == selectedID }
        selectedID = nil
        status = "Đã xóa chú thích"
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: image, annotations: annotations))
        image = previous.image
        annotations = previous.annotations
        selectedID = nil
        cropRect = nil
        status = "Đã hoàn tác"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: image, annotations: annotations))
        image = next.image
        annotations = next.annotations
        selectedID = nil
        cropRect = nil
        status = "Đã làm lại"
    }

    func applyCrop() {
        guard let image, let cropRect, cropRect.width >= 10, cropRect.height >= 10,
              let data = renderedPNG(), let bitmap = NSBitmapImageRep(data: data),
              let renderedImage = bitmap.cgImage else { return }
        let pixelBounds = CGRect(x: 0, y: 0, width: renderedImage.width, height: renderedImage.height)
        let topOrigin = CGRect(x: cropRect.minX,
                               y: image.size.height - cropRect.maxY,
                               width: cropRect.width, height: cropRect.height)
        let rect = topOrigin.integral.intersection(pixelBounds)
        guard let cropped = renderedImage.cropping(to: rect), !rect.isEmpty else { return }
        checkpoint()
        self.image = NSImage(cgImage: cropped, size: rect.size)
        annotations = []
        selectedID = nil
        self.cropRect = nil
        tool = .select
        status = "Đã cắt ảnh còn \(imageDimensions)"
    }

    func copyImage() {
        guard let data = renderedPNG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        status = "Đã sao chép ảnh vào clipboard"
    }

    @discardableResult
    func saveImage() -> Bool {
        guard let data = renderedPNG() else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "Capture-\(formatter.string(from: .now)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            status = "Đã lưu \(url.lastPathComponent)"
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    private func renderedPNG() -> Data? {
        guard let image else { return nil }
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                            pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                            bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height),
                   from: .zero, operation: .copy, fraction: 1)
        annotations.forEach { $0.draw(over: image) }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
