import CoreGraphics
import XCTest
@testable import SharedeCapture

final class ScrollingCaptureTests: XCTestCase {
    private let width = 320
    private let viewport = 400

    func testStitchesScrolledFramesIntoTheOriginalPage() throws {
        let page = makePage(height: 1500)
        let stitcher = ScrollStitcher(first: frame(of: page, at: 0), maxHeight: 10_000)
        for offset in [120, 121, 300, 520, 700, 1000] {
            XCTAssertEqual(stitcher.add(frame(of: page, at: offset)), .appended(offset - lastOffset))
            lastOffset = offset
        }
        let image = try XCTUnwrap(stitcher.render())
        XCTAssertEqual(image.height, 1000 + viewport)
        XCTAssertEqual(rows(of: image), Array(page[0..<(1000 + viewport)]))
    }

    func testIgnoresStillFramesAndScrollingBack() {
        let page = makePage(height: 1500)
        let stitcher = ScrollStitcher(first: frame(of: page, at: 0), maxHeight: 10_000)
        XCTAssertEqual(stitcher.add(frame(of: page, at: 0)), .unchanged)
        XCTAssertEqual(stitcher.add(frame(of: page, at: 200)), .appended(200))
        XCTAssertEqual(stitcher.add(frame(of: page, at: 100)), .noMatch)
        XCTAssertEqual(stitcher.add(frame(of: page, at: 250)), .appended(50))
    }

    func testKeepsStickyHeaderAndFooterOnce() throws {
        let page = makePage(height: 1500)
        let header = (0..<40).map { row(seed: 90_000 + $0) }
        let footer = (0..<30).map { row(seed: 80_000 + $0) }
        func sticky(_ offset: Int) -> PixelFrame {
            let content = Array(page[offset..<(offset + viewport - 70)])
            return makeFrame(header + content + footer)
        }
        let stitcher = ScrollStitcher(first: sticky(0), maxHeight: 10_000)
        XCTAssertEqual(stitcher.add(sticky(150)), .appended(150))
        XCTAssertEqual(stitcher.add(sticky(400)), .appended(250))
        let image = try XCTUnwrap(stitcher.render())
        XCTAssertEqual(rows(of: image), header + Array(page[0..<(400 + viewport - 70)]) + footer)
    }

    func testStopsAtTheHeightLimit() {
        let page = makePage(height: 1500)
        let stitcher = ScrollStitcher(first: frame(of: page, at: 0), maxHeight: 500)
        XCTAssertEqual(stitcher.add(frame(of: page, at: 250)), .limitReached)
        XCTAssertEqual(stitcher.height, 500)
    }

    func testMatchesFramesWithAPlayingVideo() throws {
        let page = makePage(height: 1500)
        // The left 60% of the viewport is a video that shows new noise in every frame.
        var seed = 1_000_000
        func withVideo(_ offset: Int) -> PixelFrame {
            let rows: [[UInt8]] = (0..<viewport).map { y in
                var bytes = page[offset + y]
                let noise = row(seed: seed + y)
                bytes.replaceSubrange(0..<(width * 6 / 10 * 4), with: noise[0..<(width * 6 / 10 * 4)])
                return bytes
            }
            seed += 10_000
            return makeFrame(rows)
        }
        let stitcher = ScrollStitcher(first: withVideo(0), maxHeight: 10_000)
        XCTAssertEqual(stitcher.add(withVideo(0)), .unchanged)
        XCTAssertEqual(stitcher.add(withVideo(180)), .appended(180))
        XCTAssertEqual(stitcher.add(withVideo(360)), .appended(180))
        let image = try XCTUnwrap(stitcher.render())
        XCTAssertEqual(image.height, 360 + viewport)
        // Outside the video, the result is the page itself.
        let right = width * 6 / 10 * 4
        XCTAssertEqual(rows(of: image).map { Array($0[right...]) },
                       page[0..<(360 + viewport)].map { Array($0[right...]) })
    }

    // MARK: Helpers

    private var lastOffset = 0

    /// A page of rows; every fifth row is blank, like the spacing between lines of text.
    private func makePage(height: Int) -> [[UInt8]] {
        (0..<height).map { $0 % 5 == 4 ? [UInt8](repeating: 255, count: width * 4) : row(seed: $0) }
    }

    private func row(seed: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            // splitmix64, so every row and pixel is distinct like real content.
            var z = UInt64(bitPattern: Int64(seed)) &* 0x1_0000 &+ UInt64(x) &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            let value = UInt8(truncatingIfNeeded: z ^ (z >> 31))
            bytes[x * 4] = value
            bytes[x * 4 + 1] = value &+ 40
            bytes[x * 4 + 2] = value &+ 90
        }
        return bytes
    }

    private func frame(of page: [[UInt8]], at offset: Int) -> PixelFrame {
        makeFrame(Array(page[offset..<(offset + viewport)]))
    }

    private func makeFrame(_ rows: [[UInt8]]) -> PixelFrame {
        PixelFrame(width: width, height: rows.count, pixels: rows.flatMap { $0 })
    }

    private func rows(of image: CGImage) -> [[UInt8]] {
        let data = image.dataProvider!.data! as Data
        return (0..<image.height).map { y in
            Array(data[(y * image.bytesPerRow)..<(y * image.bytesPerRow + width * 4)])
        }
    }
}
