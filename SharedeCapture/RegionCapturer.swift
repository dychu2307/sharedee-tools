import AppKit
import ScreenCaptureKit

/// Captures one screen area repeatedly while leaving out the scrolling-capture overlay windows.
@MainActor
final class RegionCapturer {
    private let rect: CGRect
    private let screen: NSScreen
    private let excludedWindows: [NSWindow]
    private var filter: AnyObject?

    /// - Parameters:
    ///   - rect: The area in AppKit screen coordinates.
    ///   - excludedWindows: This app's windows to keep out of the image. On macOS 12 and 13 the
    ///     first one must be the lowest of them; everything below it is captured.
    init(rect: CGRect, screen: NSScreen, excluding excludedWindows: [NSWindow]) {
        self.rect = rect
        self.screen = screen
        self.excludedWindows = excludedWindows
    }

    var scale: CGFloat { screen.backingScaleFactor }

    func capture() async throws -> CGImage {
        if #available(macOS 14.0, *) { return try await captureWithScreenCaptureKit() }
        return try captureBelowOverlay()
    }

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit() async throws -> CGImage {
        let filter: SCContentFilter
        if let cached = self.filter as? SCContentFilter {
            filter = cached
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
            else { throw ScrollingCaptureError.captureFailed }
            let ids = Set(excludedWindows.map { CGWindowID($0.windowNumber) })
            filter = SCContentFilter(display: display,
                                     excludingWindows: content.windows.filter { ids.contains($0.windowID) })
            self.filter = filter
        }
        let configuration = SCStreamConfiguration()
        // sourceRect is in the display's points with a top-left origin.
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                          y: screen.frame.maxY - rect.maxY,
                                          width: rect.width, height: rect.height)
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func captureBelowOverlay() throws -> CGImage {
        // Core Graphics uses a top-left origin at the main display.
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let area = CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        let below = CGWindowID(excludedWindows.first?.windowNumber ?? 0)
        guard let image = CGWindowListCreateImage(area, .optionOnScreenBelowWindow, below,
                                                  [.bestResolution, .boundsIgnoreFraming])
        else { throw ScrollingCaptureError.captureFailed }
        return image
    }
}
