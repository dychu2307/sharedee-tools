import AppKit

enum CaptureMode: String {
    case area, window, fullScreen, scrolling

    var title: String {
        switch self {
        case .area: "Chọn vùng"
        case .window: "Cửa sổ"
        case .fullScreen: "Toàn màn hình"
        case .scrolling: "Chụp cuộn"
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
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: "Đã hủy chụp ảnh"
        case .failed: "Không thể chụp màn hình. Hãy kiểm tra quyền Ghi màn hình trong Cài đặt hệ thống."
        }
    }
}

enum ScreenshotService {
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
                if FileManager.default.fileExists(atPath: url.path) {
                    continuation.resume()
                } else {
                    let permissionMissing = !CGPreflightScreenCaptureAccess()
                    continuation.resume(throwing: mode == .fullScreen || permissionMissing
                        ? CaptureError.failed : CaptureError.cancelled)
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        return url
    }
}
