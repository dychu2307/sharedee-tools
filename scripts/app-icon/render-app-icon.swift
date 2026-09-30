// Renders the 1024 x 1024 app icon: a teal tile with capture-frame corners and a crossed
// pencil and wrench.
//
//   swift scripts/app-icon/render-app-icon.swift icon-1024.png
//
// Downscale the result into SharedeCapture/Assets.xcassets/AppIcon.appiconset (for example with
// `sips -z <size> <size>`).
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Canvas uses a y-down coordinate system, 1024 x 1024.
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    var v: UInt64 = 0
    Scanner(string: s.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func gradient(_ stops: [(CGFloat, String)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { hex($0.1) } as CFArray,
               locations: stops.map { $0.0 })!
}

func fillLinear(_ path: CGPath, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func fill(_ path: CGPath, _ c: CGColor) {
    ctx.addPath(path); ctx.setFillColor(c); ctx.fillPath()
}

func withShadow(_ offset: CGSize, _ blur: CGFloat, _ c: CGColor, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: offset, blur: blur, color: c)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// Inner highlight along the top edge and inner shade along the bottom edge.
func bevel(_ path: CGPath, light: CGColor, dark: CGColor, width: CGFloat, shift: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setLineWidth(width)
    var down = CGAffineTransform(translationX: 0, y: shift)
    ctx.addPath(path.copy(using: &down)!)
    ctx.setStrokeColor(light); ctx.strokePath()
    var up = CGAffineTransform(translationX: 0, y: -shift)
    ctx.addPath(path.copy(using: &up)!)
    ctx.setStrokeColor(dark); ctx.strokePath()
    ctx.restoreGState()
}

func transformed(_ p: CGPath, _ t: CGAffineTransform) -> CGPath {
    var t = t
    return p.copy(using: &t)!
}

// MARK: - Tile (macOS icon grid: 824pt body inset 100pt)

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: tileRect, cornerWidth: 186, cornerHeight: 186, transform: nil)
let face = CGPath(roundedRect: tileRect.insetBy(dx: 26, dy: 26), cornerWidth: 162, cornerHeight: 162, transform: nil)

withShadow(CGSize(width: 0, height: -18), 36, hex("#00262e", 0.45)) {
    fillLinear(tile, gradient([(0, "#19c6c8"), (0.4, "#019297"), (1, "#003a47")]),
               CGPoint(x: 150, y: 110), CGPoint(x: 880, y: 930))
}
bevel(tile, light: hex("#ffffff", 0.35), dark: hex("#002a33", 0.35), width: 6, shift: 3)

withShadow(CGSize(width: 0, height: -6), 14, hex("#00303a", 0.55)) {
    fillLinear(face, gradient([(0, "#1ca3b3"), (0.4, "#08788c"), (1, "#004f63")]),
               CGPoint(x: 200, y: 130), CGPoint(x: 820, y: 900))
}
// Soft top sheen on the face.
ctx.saveGState()
ctx.addPath(face); ctx.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [hex("#8ae3ea", 0.22), hex("#8ae3ea", 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawRadialGradient(sheen,
                       startCenter: CGPoint(x: 330, y: 220), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 220), endRadius: 560, options: [])
ctx.restoreGState()
bevel(face, light: hex("#bff4f7", 0.45), dark: hex("#00303a", 0.4), width: 5, shift: 2.5)

// MARK: - Capture frame brackets

func extrude(_ path: CGPath, depth: Int, color: CGColor) {
    for k in stride(from: depth, through: 1, by: -1) {
        fill(transformed(path, CGAffineTransform(translationX: CGFloat(k) * 0.35, y: CGFloat(k))), color)
    }
}

let frameInset: CGFloat = 238, arm: CGFloat = 150, thick: CGFloat = 50
let frame = CGMutablePath()
for (sx, sy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
    let x = sx == 0 ? frameInset : 1024 - frameInset
    let y = sy == 0 ? frameInset : 1024 - frameInset
    let dx: CGFloat = sx == 0 ? 1 : -1, dy: CGFloat = sy == 0 ? 1 : -1
    let l = CGMutablePath()
    l.move(to: CGPoint(x: x, y: y + dy * arm))
    l.addLine(to: CGPoint(x: x, y: y))
    l.addLine(to: CGPoint(x: x + dx * arm, y: y))
    frame.addPath(l.copy(strokingWithWidth: thick, lineCap: .round, lineJoin: .round, miterLimit: 10))
}
let frameShape = frame.normalized()
withShadow(CGSize(width: 0, height: -16), 24, hex("#00222a", 0.45)) {
    extrude(frameShape, depth: 12, color: hex("#b9cdd2"))
    fillLinear(frameShape, gradient([(0, "#ffffff"), (1, "#e3ecee")]), CGPoint(x: 0, y: 200), CGPoint(x: 0, y: 820))
}
bevel(frameShape, light: hex("#ffffff", 0.9), dark: hex("#9fb6bc", 0.5), width: 4, shift: 2)

// MARK: - 3D tools

struct Part { let path: CGPath; let top: CGGradient; let side: CGColor; let span: CGFloat }

func drawTool(_ parts: [Part], at center: CGPoint, angle: CGFloat, scale: CGFloat, depth: Int) {
    let base = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle).scaledBy(x: scale, y: scale)
    // Extrusion goes straight down in screen space.
    for k in stride(from: depth, through: 1, by: -1) {
        for p in parts {
            let t = base.concatenating(CGAffineTransform(translationX: CGFloat(k) * 0.35, y: CGFloat(k)))
            fill(transformed(p.path, t), p.side)
        }
    }
    for p in parts {
        ctx.saveGState()
        ctx.concatenate(base)
        ctx.addPath(p.path); ctx.clip()
        ctx.drawLinearGradient(p.top, start: CGPoint(x: 0, y: -p.span), end: CGPoint(x: 0, y: p.span),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    for p in parts {
        bevel(transformed(p.path, base), light: hex("#ffffff", 0.55), dark: hex("#000000", 0.18), width: 3, shift: 1.5)
    }
}

// Wrench: open jaw on the right, box ring on the left. Local axis +x.
let wrenchPath: CGPath = {
    let handle = CGPath(roundedRect: CGRect(x: -170, y: -25, width: 340, height: 50), cornerWidth: 25, cornerHeight: 25, transform: nil)
    let jaw = CGPath(ellipseIn: CGRect(x: 118, y: -74, width: 148, height: 148), transform: nil)
    let ring = CGPath(ellipseIn: CGRect(x: -252, y: -62, width: 124, height: 124), transform: nil)
    var shape = handle.union(jaw).union(ring)
    let slot = CGMutablePath()
    slot.addRect(CGRect(x: 196, y: -29, width: 120, height: 58))
    slot.addEllipse(in: CGRect(x: 166, y: -29, width: 58, height: 58))
    shape = shape.subtracting(slot)
    // Hexagonal box opening.
    let hexHole = CGMutablePath()
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 6
        let pt = CGPoint(x: -190 + cos(a) * 32, y: sin(a) * 32)
        i == 0 ? hexHole.move(to: pt) : hexHole.addLine(to: pt)
    }
    hexHole.closeSubpath()
    return shape.subtracting(hexHole)
}()

let chrome = gradient([(0, "#ffffff"), (0.22, "#e3e9ef"), (0.5, "#9aa6b3"), (0.62, "#c2cbd4"), (1, "#eef2f6")])
let wrench = [Part(path: wrenchPath, top: chrome, side: hex("#56616e"), span: 74)]

// Pencil: eraser on the left, graphite tip on the right. Local axis +x.
func rect(_ x0: CGFloat, _ x1: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(rect: CGRect(x: x0, y: -h, width: x1 - x0, height: h * 2), transform: nil)
}
let eraser = CGPath(roundedRect: CGRect(x: -236, y: -34, width: 60, height: 68), cornerWidth: 20, cornerHeight: 20, transform: nil)
    .union(rect(-206, -176, 34))
let ferrule = rect(-182, -140, 35)
let body = rect(-142, 128, 34)
let cone: CGPath = {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 126, y: -34)); p.addLine(to: CGPoint(x: 226, y: 0)); p.addLine(to: CGPoint(x: 126, y: 34))
    p.closeSubpath(); return p
}()
let lead: CGPath = {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 190, y: -12.2)); p.addLine(to: CGPoint(x: 226, y: 0)); p.addLine(to: CGPoint(x: 190, y: 12.2))
    p.closeSubpath(); return p
}()
let ferruleRidges = CGMutablePath()
for x in stride(from: CGFloat(-172), through: -150, by: 11) { ferruleRidges.addRect(CGRect(x: x, y: -35, width: 3.5, height: 70)) }

let pencil = [
    Part(path: eraser, top: gradient([(0, "#ffc2cc"), (0.5, "#ff8fa3"), (1, "#e0667e")]), side: hex("#a8475a"), span: 34),
    Part(path: body, top: gradient([(0, "#ffd08a"), (0.33, "#ffb347"), (0.34, "#ff8a3d"), (0.66, "#ff7a2e"), (0.67, "#e25a1c"), (1, "#c94a12")]), side: hex("#8d3510"), span: 34),
    Part(path: cone, top: gradient([(0, "#ffe9cc"), (0.5, "#f3c893"), (1, "#d49a5e")]), side: hex("#9c6a37"), span: 34),
    Part(path: lead, top: gradient([(0, "#6b7280"), (1, "#23272f")]), side: hex("#15181d"), span: 13),
    Part(path: ferrule, top: gradient([(0, "#ffffff"), (0.3, "#dfe5ea"), (0.55, "#8d99a6"), (1, "#e7ecf0")]), side: hex("#4f5a66"), span: 35),
]

let toolCenter = CGPoint(x: 512, y: 500)
let toolScale: CGFloat = 0.92
withShadow(CGSize(width: 0, height: -26), 30, hex("#001a20", 0.55)) {
    drawTool(wrench, at: toolCenter, angle: -.pi / 4, scale: toolScale, depth: 22)
}
// Ridges on the ferrule are drawn with the pencil so they stay aligned.
withShadow(CGSize(width: 0, height: -24), 26, hex("#001a20", 0.5)) {
    drawTool(pencil, at: toolCenter, angle: .pi / 4, scale: toolScale, depth: 22)
    ctx.saveGState()
    ctx.concatenate(CGAffineTransform(translationX: toolCenter.x, y: toolCenter.y).rotated(by: .pi / 4).scaledBy(x: toolScale, y: toolScale))
    ctx.addPath(ferruleRidges); ctx.setFillColor(hex("#6b7784", 0.55)); ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - Export

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
