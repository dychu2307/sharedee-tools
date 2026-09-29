import AppKit
import ApplicationServices

enum ScrollingCaptureError: LocalizedError {
    case accessibilityPermission
    case noWindow
    case captureFailed
    case noScrollDetected

    var errorDescription: String? {
        switch self {
        case .accessibilityPermission:
            "Hãy cấp quyền Trợ năng cho Sharedee Tools trong Cài đặt hệ thống, rồi thử lại."
        case .noWindow:
            "Không tìm thấy cửa sổ để chụp cuộn. Hãy mở cửa sổ cần chụp trước."
        case .captureFailed:
            "Không thể chụp cửa sổ đang hoạt động."
        case .noScrollDetected:
            "Không thấy nội dung cuộn. Hãy đưa phần cần chụp vào giữa cửa sổ và thử lại."
        }
    }
}

enum ScrollingCaptureService {
    private struct WindowTarget {
        let id: CGWindowID
        let bounds: CGRect
    }

    private struct Frame {
        let image: CGImage
        let addedHeight: Int
    }

    static func capture(maxFrames: Int) async throws -> URL {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw ScrollingCaptureError.accessibilityPermission
        }
        guard let window = frontWindow() else { throw ScrollingCaptureError.noWindow }
        var frames: [Frame] = []
        var previous: NSBitmapImageRep?
        let count = max(2, min(maxFrames, 30))

        for index in 0..<count {
            let image = try await captureWindow(window.id)
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let previous {
                guard bitmap.pixelsWide == previous.pixelsWide,
                      bitmap.pixelsHigh == previous.pixelsHigh else { break }
                let shift = estimatedScroll(from: previous, to: bitmap)
                if shift < 20 { break }
                frames.append(Frame(image: image, addedHeight: shift))
            } else {
                frames.append(Frame(image: image, addedHeight: 0))
            }
            previous = bitmap
            guard index + 1 < count else { break }
            scrollDown(in: window.bounds)
            try await Task.sleep(nanoseconds: 550_000_000)
        }

        guard frames.count > 1 else { throw ScrollingCaptureError.noScrollDetected }
        guard let data = stitchedPNG(frames) else { throw ScrollingCaptureError.captureFailed }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedeCapture-Scroll-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func frontWindow() -> WindowTarget? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != getpid(),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsData = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsData),
                  bounds.width >= 300, bounds.height >= 250 else { continue }
            return WindowTarget(id: id, bounds: bounds)
        }
        return nil
    }

    private static func captureWindow(_ id: CGWindowID) async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedeCapture-Frame-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l\(id)", "-o", "-x", "-t", "png", url.path]
            process.terminationHandler = { process in
                if process.terminationStatus == 0,
                   FileManager.default.fileExists(atPath: url.path) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ScrollingCaptureError.captureFailed)
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        let data = try Data(contentsOf: url)
        guard let image = NSBitmapImageRep(data: data)?.cgImage else {
            throw ScrollingCaptureError.captureFailed
        }
        return image
    }

    private static func scrollDown(in bounds: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let amount = Int32(min(420, max(120, bounds.height * 0.45)))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: -amount, wheel2: 0, wheel3: 0) else { return }
        event.location = center
        event.post(tap: .cghidEventTap)
    }

    static func estimatedScroll(from old: NSBitmapImageRep,
                                to new: NSBitmapImageRep) -> Int {
        guard let oldData = old.bitmapData, let newData = new.bitmapData else { return 0 }
        let width = old.pixelsWide
        let height = old.pixelsHigh
        let bytesPerPixel = max(1, old.bitsPerPixel / 8)
        let oldStride = old.bytesPerRow
        let newStride = new.bytesPerRow
        let left = width / 6
        let right = width * 5 / 6
        let margin = max(35, height / 10)

        func difference(_ shift: Int) -> Double {
            let end = height - margin - shift
            guard end > margin + 20 else { return .infinity }
            var total = 0
            var samples = 0
            for y in stride(from: margin, to: end, by: 13) {
                for x in stride(from: left, to: right, by: 17) {
                    let a = oldData + (y + shift) * oldStride + x * bytesPerPixel
                    let b = newData + y * newStride + x * bytesPerPixel
                    total += abs(Int(a[0]) - Int(b[0]))
                    total += abs(Int(a[1]) - Int(b[1]))
                    total += abs(Int(a[2]) - Int(b[2]))
                    samples += 3
                }
            }
            return samples == 0 ? .infinity : Double(total) / Double(samples)
        }

        if difference(0) < 2.5 { return 0 }
        var bestShift = 0
        var bestScore = Double.infinity
        for shift in 20...max(20, height * 7 / 10) {
            let score = difference(shift)
            if score < bestScore { bestScore = score; bestShift = shift }
            if score < 0.5 { break }
        }
        return bestScore < 32 ? bestShift : 0
    }

    private static func stitchedPNG(_ frames: [Frame]) -> Data? {
        guard let first = frames.first else { return nil }
        let width = first.image.width
        let height = first.image.height + frames.dropFirst().reduce(0) { $0 + $1.addedHeight }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                            pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                            bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let firstImage = NSImage(cgImage: first.image,
                                 size: CGSize(width: width, height: first.image.height))
        firstImage.draw(in: CGRect(x: 0, y: height - first.image.height,
                                   width: width, height: first.image.height),
                        from: .zero, operation: .copy, fraction: 1)
        var usedHeight = first.image.height
        for frame in frames.dropFirst() {
            let stripHeight = frame.addedHeight
            guard let strip = frame.image.cropping(to: CGRect(x: 0,
                                                              y: frame.image.height - stripHeight,
                                                              width: width, height: stripHeight)) else { continue }
            let image = NSImage(cgImage: strip,
                                size: CGSize(width: width, height: stripHeight))
            image.draw(in: CGRect(x: 0, y: height - usedHeight - stripHeight,
                                  width: width, height: stripHeight),
                       from: .zero, operation: .copy, fraction: 1)
            usedHeight += stripHeight
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
