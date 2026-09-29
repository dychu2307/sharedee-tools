import AppKit
import XCTest
@testable import SharedeCapture

final class AnnotationTests: XCTestCase {
    func testBlurChangesOnlySelectedRegion() {
        let sourceBitmap = makeStripedImage()
        let source = NSImage(cgImage: sourceBitmap.cgImage!, size: CGSize(width: 100, height: 100))
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100,
                                      pixelsHigh: 100, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                      bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: output)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: CGRect(x: 0, y: 0, width: 100, height: 100),
                    from: .zero, operation: .copy, fraction: 1)
        Annotation(tool: .blur, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)],
                   color: .red, lineWidth: 5).draw(over: source)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let outside = output.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
        let originalOutside = sourceBitmap.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(outside.redComponent, originalOutside.redComponent, accuracy: 0.01)

        let center = output.colorAt(x: 52, y: 50)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(center.redComponent, 0.1)
        XCTAssertLessThan(center.redComponent, 0.9)
    }

    private func makeStripedImage() -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100,
                                      pixelsHigh: 100, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                      bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 100, height: 100).fill()
        NSColor.black.setFill()
        for x in stride(from: 5, to: 100, by: 10) {
            CGRect(x: x, y: 0, width: 5, height: 100).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
