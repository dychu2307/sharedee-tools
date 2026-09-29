import AppKit
import XCTest
@testable import SharedeCapture

final class ScrollingCaptureTests: XCTestCase {
    func testDetectsVerticalOverlapAndStopsOnIdenticalFrame() {
        let first = frame(startingAt: 0)
        let second = frame(startingAt: 173)

        XCTAssertEqual(ScrollingCaptureService.estimatedScroll(from: first, to: second), 173)
        XCTAssertEqual(ScrollingCaptureService.estimatedScroll(from: first, to: first), 0)
    }

    private func frame(startingAt start: Int) -> NSBitmapImageRep {
        let width = 400
        let height = 700
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                     pixelsHigh: height, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0)!
        let data = image.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let globalY = y + start
                let hash = (UInt32(globalY) &* 1_103_515_245)
                    &+ (UInt32(x) &* 12_345)
                let offset = y * image.bytesPerRow + x * 4
                data[offset] = UInt8(truncatingIfNeeded: hash >> 16)
                data[offset + 1] = UInt8(truncatingIfNeeded: hash >> 8)
                data[offset + 2] = UInt8(truncatingIfNeeded: hash)
                data[offset + 3] = 255
            }
        }
        return image
    }
}
