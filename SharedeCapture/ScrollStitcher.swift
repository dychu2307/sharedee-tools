import CoreGraphics
import Foundation

/// An RGBA8 copy of a captured frame, with hashes of each row split into column bands.
///
/// Splitting rows into bands lets frames be matched even when part of the area keeps changing,
/// such as a playing video: the bands beside it still line up.
struct PixelFrame {
    static let bands = 8

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]
    /// `height * bands` hashes of sampled, quantized luminance, row by row.
    let cellHashes: [UInt64]
    /// Whether a cell has visible detail; blank cells match any offset, so they are not evidence.
    let cellHasDetail: [Bool]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.pixels = pixels
        // Sample away from the edges; overlay scroll bars on the right move with every scroll.
        let left = max(1, width * 3 / 100)
        let right = max(left + Self.bands, width - max(width * 4 / 100, 44))
        let bandWidth = max(1, (right - left) / Self.bands)
        let step = max(1, bandWidth / 12)
        var hashes = [UInt64](repeating: 0, count: height * Self.bands)
        var detail = [Bool](repeating: false, count: height * Self.bands)
        pixels.withUnsafeBufferPointer { data in
            for y in 0..<height {
                let row = y * width * 4
                for band in 0..<Self.bands {
                    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                    var low = 255, high = 0
                    var x = left + band * bandWidth
                    let end = min(right, x + bandWidth)
                    while x < end {
                        let offset = row + x * 4
                        let luma = (Int(data[offset]) * 3 + Int(data[offset + 1]) * 6 + Int(data[offset + 2])) / 10
                        low = min(low, luma)
                        high = max(high, luma)
                        hash = (hash ^ UInt64(luma >> 3)) &* 0x100_0000_01b3
                        x += step
                    }
                    hashes[y * Self.bands + band] = hash
                    detail[y * Self.bands + band] = high - low > 24
                }
            }
        }
        cellHashes = hashes
        cellHasDetail = detail
    }

    /// Whether every band of row `y` equals the same row of `other`.
    func rowEquals(_ other: PixelFrame, row y: Int) -> Bool {
        let start = y * Self.bands
        for index in start..<(start + Self.bands) where cellHashes[index] != other.cellHashes[index] {
            return false
        }
        return true
    }
}

/// Joins frames of a scrolling area into one tall image.
///
/// Each new frame is matched against the last accepted one to find how far the content moved.
/// Rows that stay put in both frames at the top and bottom (sticky headers and footers) are kept
/// out of the match; the bottom band is fixed after the first match so the strips line up, and
/// it is added once at the end.
final class ScrollStitcher {
    enum Result: Equatable {
        case appended(Int)
        case unchanged
        case noMatch
        case limitReached
    }

    let width: Int
    let maxHeight: Int
    private(set) var height: Int
    private var last: PixelFrame
    /// Output rows above the footer band.
    private var body: [UInt8]
    private var footerHeight: Int?

    init(first: PixelFrame, maxHeight: Int) {
        width = first.width
        self.maxHeight = maxHeight
        height = first.height
        last = first
        body = first.pixels
    }

    func add(_ frame: PixelFrame) -> Result {
        guard frame.width == width, frame.height == last.height else { return .noMatch }
        if height >= maxHeight { return .limitReached }
        let rows = frame.height

        let header = Self.staticRows(last, frame, fromTop: true)
        if header >= rows { return .unchanged }
        let footer = footerHeight ?? min(Self.staticRows(last, frame, fromTop: false), rows / 3)
        guard rows - header - footer > 60 else { return .noMatch }

        guard let shift = Self.bestShift(from: last, to: frame, top: header, bottom: rows - footer) else { return .noMatch }
        guard shift > 0 else { return .unchanged }

        let added = min(shift, maxHeight - height)
        // New content is the `shift` rows just above the footer band.
        let start = (rows - footer - shift) * frame.bytesPerRow
        if footerHeight == nil {
            footerHeight = footer
            body.removeLast(footer * frame.bytesPerRow)
        }
        body.append(contentsOf: frame.pixels[start..<(start + added * frame.bytesPerRow)])
        height += added
        last = frame
        return added < shift ? .limitReached : .appended(added)
    }

    func render() -> CGImage? {
        let footer = footerHeight ?? 0
        var output = body
        if footer > 0 {
            let start = (last.height - footer) * last.bytesPerRow
            output.append(contentsOf: last.pixels[start...])
        }
        let rows = output.count / (width * 4)
        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Rows that are identical at the same position in both frames, counted from one edge.
    static func staticRows(_ a: PixelFrame, _ b: PixelFrame, fromTop: Bool) -> Int {
        var count = 0
        for index in 0..<a.height {
            guard a.rowEquals(b, row: fromTop ? index : a.height - 1 - index) else { break }
            count += 1
        }
        return count
    }

    /// How many rows the content moved up between two frames within rows `top..<bottom`:
    /// 0 when nothing moved, nil when no offset matches clearly better than the others.
    ///
    /// Each offset is scored by the share of detailed cells that line up. Cells that keep
    /// changing, like a playing video, lower every offset alike, so the right offset is the one
    /// that stands out rather than one that reaches a fixed share.
    static func bestShift(from old: PixelFrame, to new: PixelFrame, top: Int, bottom: Int) -> Int? {
        let moving = bottom - top
        let maxShift = moving - max(30, moving / 8)
        guard maxShift > 0 else { return nil }
        let bands = PixelFrame.bands

        return old.cellHashes.withUnsafeBufferPointer { oldHashes in
            new.cellHashes.withUnsafeBufferPointer { newHashes in
                new.cellHasDetail.withUnsafeBufferPointer { newDetail -> Int? in
                    func score(_ shift: Int, rowStep: Int) -> (value: Double, evidence: Int) {
                        var matches = 0
                        var evidence = 0
                        var y = top
                        while y < bottom - shift {
                            let newRow = y * bands
                            let oldRow = (y + shift) * bands
                            for band in 0..<bands where newDetail[newRow + band] {
                                evidence += 1
                                if oldHashes[oldRow + band] == newHashes[newRow + band] { matches += 1 }
                            }
                            y += rowStep
                        }
                        return (evidence == 0 ? 0 : Double(matches) / Double(evidence), evidence)
                    }

                    // Coarse pass over every offset on every third row, then a full check of the
                    // leading candidates and their neighbours.
                    var coarse: [(shift: Int, value: Double)] = []
                    coarse.reserveCapacity(maxShift + 1)
                    for shift in 0...maxShift {
                        let result = score(shift, rowStep: 3)
                        if result.evidence >= 4 { coarse.append((shift, result.value)) }
                    }
                    var best: (shift: Int, value: Double)?
                    var checked = Set<Int>()
                    for leader in coarse.sorted(by: { $0.value > $1.value }).prefix(4) {
                        for shift in max(0, leader.shift - 2)...min(maxShift, leader.shift + 2)
                        where checked.insert(shift).inserted {
                            let result = score(shift, rowStep: 1)
                            guard result.evidence >= 8 else { continue }
                            if best == nil || result.value > best!.value { best = (shift, result.value) }
                        }
                    }
                    guard let best, best.value >= 0.15 else { return nil }
                    if best.value >= 0.97 { return best.shift }
                    // The best offset must clearly beat every offset away from it: by a margin,
                    // and at least twice the runner-up's score.
                    let runnerUp = coarse.filter { abs($0.shift - best.shift) > 3 }.map(\.value).max() ?? 0
                    return best.value - runnerUp >= 0.12 && best.value >= runnerUp * 2 ? best.shift : nil
                }
            }
        }
    }
}
