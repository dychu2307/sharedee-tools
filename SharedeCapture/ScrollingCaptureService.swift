import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ScrollingCaptureError: LocalizedError {
    case cancelled
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: L10n.tr("Đã hủy chụp ảnh")
        case .captureFailed: L10n.tr("Không thể chụp vùng đã chọn.")
        }
    }
}

enum ScrollingCaptureService {
    /// Runs an interactive scrolling capture and writes the stitched image to a temporary PNG.
    @MainActor
    static func capture(maxHeight: Int) async throws -> URL {
        let image = try await ScrollingCaptureSession.run(maxHeight: maxHeight)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedeCapture-Scroll-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ScrollingCaptureError.captureFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScrollingCaptureError.captureFailed }
        return url
    }
}
