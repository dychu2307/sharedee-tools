import AppKit
import SwiftUI

struct RecentCapture: Identifiable {
    let id = UUID()
    let url: URL
    let capturedAt: Date
    let mode: CaptureMode
}

@MainActor
final class CaptureState: ObservableObject {
    weak var preferences: ShortcutSettings?
    weak var driveService: GoogleDriveService?
    var willCapture: (() -> Void)?
    var didCapture: (() -> Void)?
    /// Handles the "upload to Drive" post-capture action so the thumbnail can show progress.
    var uploadHandler: ((RecentCapture) -> Void)?
    var captureFailed: (() -> Void)?
    /// Called when "Capture and copy text" ends, so the app can restore windows and report it.
    var textCaptureFinished: ((TextCaptureResult) -> Void)?
    @Published var image: NSImage?
    @Published var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var tool: EditorTool = .pen
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 5
    @Published var cropRect: CGRect?
    @Published var recent: [RecentCapture] = []
    @Published var status = L10n.tr("Sẵn sàng chụp")
    @Published var isCapturing = false

    private struct Snapshot {
        let image: NSImage?
        let annotations: [Annotation]
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedAnnotation: Annotation? { annotations.first { $0.id == selectedID } }
    var imageDimensions: String {
        guard let image else { return L10n.tr("Chưa có ảnh") }
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
        do { try ScreenshotService.ensurePermission() }
        catch {
            status = error.localizedDescription
            isCapturing = false
            return false
        }
        status = L10n.format("Đang chụp: %@…", mode.title.lowercased())
        willCapture?()
        try? await Task.sleep(nanoseconds: UInt64(350 + (preferences?.captureDelay ?? 0) * 1000) * 1_000_000)
        do {
            let url = try await ScreenshotService.capture(mode,
                                                          includeCursor: preferences?.includeCursor ?? false)
            try loadImage(at: url)
            recent.insert(RecentCapture(url: url, capturedAt: .now, mode: mode), at: 0)
            recent = Array(recent.prefix(8))
            status = L10n.format("Đã chụp %@ · %@", mode.title.lowercased(), imageDimensions)
            didCapture?()
            performPostCaptureAction()
            isCapturing = false
            return true
        } catch {
            status = error.localizedDescription
            captureFailed?()
            isCapturing = false
            return false
        }
    }

    /// Captures an area only to read its text. The screenshot is temporary: it does not replace
    /// the image being edited, run the post-capture action, show a thumbnail, or join Recent.
    func captureText() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do { try ScreenshotService.ensurePermission() }
        catch {
            status = error.localizedDescription
            textCaptureFinished?(.failed(status))
            return
        }
        status = L10n.tr("Kéo để chọn vùng có chữ")
        willCapture?()
        try? await Task.sleep(nanoseconds: 350_000_000)
        do {
            let url = try await ScreenshotService.capture(.area)
            defer { try? FileManager.default.removeItem(at: url) }
            guard let image = TextRecognizer.cgImage(from: try Data(contentsOf: url)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            status = L10n.tr("Đang nhận dạng chữ…")
            let result = copyText(try await TextRecognizer.recognize(image))
            textCaptureFinished?(result)
        } catch CaptureError.cancelled {
            status = L10n.tr("Đã hủy chụp ảnh")
            textCaptureFinished?(.cancelled)
        } catch {
            status = error.localizedDescription
            textCaptureFinished?(.failed(status))
        }
    }

    func captureScrolling() async {
        guard !isCapturing else { return }
        isCapturing = true
        do { try ScreenshotService.ensurePermission() }
        catch {
            status = error.localizedDescription
            isCapturing = false
            return
        }
        status = L10n.tr("Đang chụp cuộn…")
        willCapture?()
        // Give our own windows time to hide before the selection overlay appears.
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            let url = try await ScrollingCaptureService.capture(
                maxHeight: preferences?.maxScrollHeight ?? ShortcutSettings.defaultMaxScrollHeight)
            try loadImage(at: url)
            recent.insert(RecentCapture(url: url, capturedAt: .now, mode: .scrolling), at: 0)
            recent = Array(recent.prefix(8))
            status = L10n.format("Đã chụp cuộn · %@", imageDimensions)
            didCapture?()
            performPostCaptureAction()
        } catch {
            status = error.localizedDescription
            captureFailed?()
        }
        isCapturing = false
    }

    /// Recognizes the text in the image being edited (annotations included) and copies it.
    @discardableResult
    func copyRecognizedText() async -> TextCaptureResult {
        guard let data = renderedPNG(), let image = TextRecognizer.cgImage(from: data) else {
            return .failed(L10n.tr("Không thể đọc ảnh đã chụp"))
        }
        status = L10n.tr("Đang nhận dạng chữ…")
        do {
            return copyText(try await TextRecognizer.recognize(image))
        } catch {
            status = error.localizedDescription
            return .failed(status)
        }
    }

    private func copyText(_ lines: [String]) -> TextCaptureResult {
        guard !lines.isEmpty else {
            status = L10n.tr("Không tìm thấy chữ trong ảnh")
            return .noText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        status = L10n.tr("Đã sao chép chữ nhận dạng vào clipboard")
        return .copied(lines)
    }

    @discardableResult
    func openImage() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try loadImage(at: url)
            status = L10n.format("Đã mở %@", url.lastPathComponent)
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
            status = L10n.format("Đã mở ảnh %@", capture.mode.title.lowercased())
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
        status = L10n.format("Đã thêm %@", annotation.tool.title.lowercased())
    }

    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        checkpoint()
        annotations[index] = annotation
        status = L10n.tr("Đã di chuyển chú thích")
    }

    func setSelectedText(_ text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .text,
              annotations[index].text != text else { return }
        checkpoint()
        annotations[index].text = text
        status = L10n.tr("Đã sửa chữ")
    }

    func deleteSelected() {
        guard selectedID != nil else { return }
        checkpoint()
        annotations.removeAll { $0.id == selectedID }
        selectedID = nil
        status = L10n.tr("Đã xóa chú thích")
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: image, annotations: annotations))
        image = previous.image
        annotations = previous.annotations
        selectedID = nil
        cropRect = nil
        status = L10n.tr("Đã hoàn tác")
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: image, annotations: annotations))
        image = next.image
        annotations = next.annotations
        selectedID = nil
        cropRect = nil
        status = L10n.tr("Đã làm lại")
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
        status = L10n.format("Đã cắt ảnh còn %@", imageDimensions)
    }

    @discardableResult
    func copyImage() -> Bool {
        guard let data = renderedPNG() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(data, forType: .png)
        status = copied ? L10n.tr("Đã sao chép ảnh vào clipboard") : L10n.tr("Không thể sao chép ảnh vào clipboard")
        return copied
    }

    @discardableResult
    func copyImage(_ capture: RecentCapture) -> Bool {
        guard let data = try? Data(contentsOf: capture.url) else {
            status = L10n.tr("Không thể đọc ảnh đã chụp")
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(data, forType: .png)
        status = copied ? L10n.tr("Đã sao chép ảnh vào clipboard") : L10n.tr("Không thể sao chép ảnh vào clipboard")
        return copied
    }

    private func performPostCaptureAction() {
        switch preferences?.postCaptureAction ?? .copy {
        case .copy: copyImage()
        case .saveToFolder: _ = saveImageToFolder()
        case .uploadToDrive:
            if let uploadHandler, let capture = recent.first {
                uploadHandler(capture)
            } else if let data = renderedPNG() {
                let name = generatedFileName()
                Task { [weak self] in _ = await self?.uploadToDrive(data, name: name) }
            }
        case .thumbnailOnly: break
        }
    }

    @discardableResult
    func uploadImageToDrive() async -> Bool {
        guard let data = renderedPNG() else { return false }
        return await uploadToDrive(data, name: generatedFileName())
    }

    /// Uploads a capture and returns its Drive link, or nil with the reason left in `status`.
    func uploadImageToDrive(_ capture: RecentCapture) async -> URL? {
        guard let data = try? Data(contentsOf: capture.url) else {
            status = L10n.tr("Không thể đọc ảnh đã chụp")
            return nil
        }
        return await uploadFile(data, name: generatedFileName())
    }

    private func uploadToDrive(_ data: Data, name: String) async -> Bool {
        await uploadFile(data, name: name) != nil
    }

    private func uploadFile(_ data: Data, name: String) async -> URL? {
        guard let driveService else { return nil }
        status = L10n.tr("Đang tải ảnh lên Google Drive…")
        do {
            let url = try await driveService.uploadPNG(data, name: name)
            status = L10n.format("Đã tải ảnh lên Google Drive: %@", url.absoluteString)
            return url
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func saveImage() -> Bool {
        guard let data = renderedPNG() else { return false }
        if let folder = preferences?.saveFolderURL {
            return writeImage(data, to: folder.appendingPathComponent(generatedFileName()))
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = generatedFileName()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeImage(data, to: url)
    }

    @discardableResult
    func saveImage(_ capture: RecentCapture) -> Bool {
        guard let data = try? Data(contentsOf: capture.url) else {
            status = L10n.tr("Không thể đọc ảnh đã chụp")
            return false
        }
        if let folder = preferences?.saveFolderURL {
            return writeImage(data, to: folder.appendingPathComponent(generatedFileName()))
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = generatedFileName()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeImage(data, to: url)
    }

    @discardableResult
    func saveImageToFolder() -> Bool {
        guard let data = renderedPNG() else { return false }
        guard let folder = preferences?.saveFolderURL else {
            status = L10n.tr("Hãy chọn thư mục lưu trong Cài đặt trước.")
            return false
        }
        return writeImage(data, to: folder.appendingPathComponent(generatedFileName()))
    }

    private func generatedFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return "Sharedee-\(formatter.string(from: .now))-\(UUID().uuidString.prefix(6)).png"
    }

    private func writeImage(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            status = L10n.format("Đã lưu %@", url.lastPathComponent)
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    /// The image as it will be exported, with annotations drawn in.
    func renderedImage() -> NSImage? {
        renderedPNG().flatMap(NSImage.init(data:))
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

enum TextCaptureResult: Equatable {
    case copied([String])
    case noText
    case cancelled
    case failed(String)
}
