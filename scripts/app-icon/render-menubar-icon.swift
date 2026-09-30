import AppKit
import ImageIO
import UniformTypeIdentifiers

// Renders the menu bar template glyph (capture-frame corners with a crossed pencil and wrench)
// in an 18 x 18 pt, y-down coordinate space, at the given pixel scale.
//
//   swift scripts/app-icon/render-menubar-icon.swift menubar_1x.png 1
//   swift scripts/app-icon/render-menubar-icon.swift menubar_2x.png 2
//
// Copy the results into SharedeCapture/Assets.xcassets/MenuBarIcon.imageset.
let pt: CGFloat = 18
let scale = CGFloat(Double(CommandLine.arguments[2])!)
let px = Int(pt * scale)
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(px))
ctx.scaleBy(x: scale, y: -scale)
let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

func stroke(_ p: CGPath, _ w: CGFloat, cap: CGLineCap = .round) -> CGPath {
    p.copy(strokingWithWidth: w, lineCap: cap, lineJoin: .round, miterLimit: 10)
}

// Capture frame corners.
let inset: CGFloat = 1.6, arm: CGFloat = 4.0, frameWidth: CGFloat = 1.9
let frame = CGMutablePath()
for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (pt - inset, inset, -1.0, 1.0),
                       (inset, pt - inset, 1.0, -1.0), (pt - inset, pt - inset, -1.0, -1.0)] {
    let l = CGMutablePath()
    l.move(to: CGPoint(x: x, y: y + dy * arm))
    l.addLine(to: CGPoint(x: x, y: y))
    l.addLine(to: CGPoint(x: x + dx * arm, y: y))
    frame.addPath(stroke(l, frameWidth))
}

// Wrench: lower-left to upper-right, open jaw at the top right.
let wrench: CGPath = {
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: 5.6, y: 12.4)); handle.addLine(to: CGPoint(x: 11.2, y: 6.8))
    var shape = stroke(handle, 2.0)
    let head = CGPath(ellipseIn: CGRect(x: 10.0, y: 3.4, width: 4.6, height: 4.6), transform: nil)
    shape = shape.union(head)
    // Jaw opening aimed at the top-right corner.
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: 12.3, y: 5.7)); slot.addLine(to: CGPoint(x: 15.5, y: 2.5))
    shape = shape.subtracting(stroke(slot, 1.4, cap: .round))
    return shape
}()

// Pencil: upper-left to lower-right, tip at the bottom right.
let pencilBody: CGPath = {
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 5.2, y: 5.2)); body.addLine(to: CGPoint(x: 10.6, y: 10.6))
    return stroke(body, 2.6, cap: .butt)
}()
let pencilTip: CGPath = {
    // Triangle from the body end to the point.
    let d: CGFloat = 1.3 / 2.squareRoot() * 2 / 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 10.6 - d, y: 10.6 + d))
    p.addLine(to: CGPoint(x: 10.6 + d, y: 10.6 - d))
    p.addLine(to: CGPoint(x: 13.3, y: 13.3))
    p.closeSubpath()
    return p
}()
let pencilCap: CGPath = {
    let c = CGMutablePath()
    c.move(to: CGPoint(x: 4.3, y: 4.3)); c.addLine(to: CGPoint(x: 4.6, y: 4.6))
    return stroke(c, 2.6, cap: .round)
}()
let pencil = pencilBody.union(pencilTip).union(pencilCap)

// Pencil sits on top of the wrench with a clear gap around it.
let gap = stroke(pencil, 1.4).union(pencil)
let glyph = frame.union(wrench.subtracting(gap)).union(pencil)

ctx.addPath(glyph)
ctx.setFillColor(black)
ctx.fillPath()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
