import AppKit

enum CaptureMode: String {
    case area, window, fullScreen, scrolling

    var title: String {
        switch self {
        case .area: L10n.tr("Chọn vùng")
        case .window: L10n.tr("Cửa sổ")
        case .fullScreen: L10n.tr("Toàn màn hình")
        case .scrolling: L10n.tr("Chụp cuộn")
        }
    }

    var symbol: String {
        switch self {
        case .area: "selection.pin.in.out"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .scrolling: "scroll"
        }
    }
}

enum CaptureError: LocalizedError {
    case cancelled
    case permissionRequired
    case restartRequired
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: L10n.tr("Đã hủy chụp ảnh")
        case .permissionRequired:
            L10n.tr("Sharedee Tools chưa có quyền Ghi màn hình. Hãy bật quyền cho Sharedee Tools trong Cài đặt hệ thống.")
        case .restartRequired:
            L10n.tr("Đã cấp quyền Ghi màn hình. Hãy khởi động lại Sharedee Tools để quyền có hiệu lực.")
        case .failed: L10n.tr("Không thể chụp màn hình. Hãy thử lại khi màn hình đang mở khóa.")
        }
    }
}

enum ScreenshotService {
    static func ensurePermission() throws {
        if CGPreflightScreenCaptureAccess() { return }
        guard CGRequestScreenCaptureAccess() else { throw CaptureError.permissionRequired }
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.restartRequired }
    }

    static func capture(_ mode: CaptureMode, includeCursor: Bool = false) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedeCapture-\(UUID().uuidString).png")
        let arguments: [String]
        switch mode {
        case .area: arguments = ["-i", "-s", "-x", "-t", "png", url.path]
        case .window: arguments = ["-i", "-W", "-x", "-t", "png", url.path]
        case .fullScreen:
            arguments = ["-m", "-x"] + (includeCursor ? ["-C"] : []) + ["-t", "png", url.path]
        case .scrolling:
            throw CaptureError.failed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0,
                   FileManager.default.fileExists(atPath: url.path) {
                    continuation.resume()
                } else {
                    let permissionMissing = !CGPreflightScreenCaptureAccess()
                    continuation.resume(throwing: permissionMissing ? CaptureError.permissionRequired
                        : mode == .fullScreen ? CaptureError.failed : CaptureError.cancelled)
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        return url
    }
}
