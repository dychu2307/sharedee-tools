import AppKit
import CoreImage

enum EditorTool: String, CaseIterable, Identifiable {
    case select, pen, arrow, rectangle, ellipse, highlight, blur, redact, text, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: L10n.tr("Chọn")
        case .pen: L10n.tr("Bút vẽ")
        case .arrow: L10n.tr("Mũi tên")
        case .rectangle: L10n.tr("Hình chữ nhật")
        case .ellipse: L10n.tr("Hình elip")
        case .highlight: L10n.tr("Tô sáng")
        case .blur: L10n.tr("Làm mờ")
        case .redact: L10n.tr("Che kín")
        case .text: L10n.tr("Chữ")
        case .crop: L10n.tr("Cắt ảnh")
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .blur: "drop.halffull"
        case .redact: "rectangle.fill"
        case .text: "textformat"
        case .crop: "crop.rotate"
        }
    }
}

struct Annotation: Identifiable {
    var id = UUID()
    var tool: EditorTool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text = L10n.tr("Nhập chữ")

    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: textAttributes)
            return CGRect(origin: first, size: size)
        }
        let minX = points.map(\.x).min() ?? first.x
        let maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(22, lineWidth * 6), weight: .semibold),
         .foregroundColor: color]
    }

    func translated(by offset: CGSize) -> Annotation {
        var result = self
        result.points = points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        return result
    }

    func draw(over sourceImage: NSImage? = nil) {
        guard let first = points.first else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch tool {
        case .pen:
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            if points.count == 1 { path.line(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1)) }
            path.stroke()
        case .arrow:
            guard let last = points.last else { return }
            path.move(to: first)
            path.line(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = max(14, lineWidth * 4)
            for turn in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last)
                path.line(to: CGPoint(x: last.x - head * cos(angle + turn),
                                      y: last.y - head * sin(angle + turn)))
            }
            path.stroke()
        case .rectangle:
            NSBezierPath(rect: bounds).withLineWidth(lineWidth).stroke()
        case .ellipse:
            NSBezierPath(ovalIn: bounds).withLineWidth(lineWidth).stroke()
        case .highlight:
            color.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        case .blur:
            drawBlur(over: sourceImage)
        case .redact:
            NSColor.black.setFill()
            NSBezierPath(rect: bounds).fill()
        case .text:
            (text as NSString).draw(at: first, withAttributes: textAttributes)
        case .select, .crop:
            break
        }
    }

    private func drawBlur(over sourceImage: NSImage?) {
        guard let sourceImage,
              let source = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let imageBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let topOrigin = CGRect(x: bounds.minX, y: CGFloat(source.height) - bounds.maxY,
                               width: bounds.width, height: bounds.height)
            .integral.intersection(imageBounds)
        guard topOrigin.width >= 2, topOrigin.height >= 2,
              let cropped = source.cropping(to: topOrigin),
              let filter = CIFilter(name: "CIGaussianBlur") else { return }
        let input = CIImage(cgImage: cropped)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(12, lineWidth * 5), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let result = Self.ciContext.createCGImage(output, from: input.extent) else { return }
        NSImage(cgImage: result, size: topOrigin.size)
            .draw(in: CGRect(x: topOrigin.minX,
                             y: CGFloat(source.height) - topOrigin.maxY,
                             width: topOrigin.width, height: topOrigin.height),
                  from: .zero, operation: .copy, fraction: 1)
    }

    private static let ciContext = CIContext()
}

private extension NSBezierPath {
    func withLineWidth(_ width: CGFloat) -> NSBezierPath {
        lineWidth = width
        return self
    }
}
