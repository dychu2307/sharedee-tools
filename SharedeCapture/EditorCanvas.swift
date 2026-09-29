import AppKit
import SwiftUI

struct EditorCanvas: NSViewRepresentable {
    @ObservedObject var state: CaptureState

    func makeNSView(context: Context) -> DrawingView {
        let view = DrawingView()
        view.onCreate = { [weak state] in state?.add($0) }
        view.onSelect = { [weak state] in state?.selectedID = $0 }
        view.onUpdate = { [weak state] in state?.update($0) }
        view.onCrop = { [weak state] in state?.cropRect = $0 }
        view.onDelete = { [weak state] in state?.deleteSelected() }
        return view
    }

    func updateNSView(_ view: DrawingView, context: Context) {
        view.sourceImage = state.image
        view.annotations = state.annotations
        view.selectedID = state.selectedID
        view.tool = state.tool
        view.color = state.color
        view.lineWidth = state.lineWidth
        view.cropRect = state.cropRect
        view.needsDisplay = true
    }
}

final class DrawingView: NSView {
    var sourceImage: NSImage?
    var annotations: [Annotation] = []
    var selectedID: UUID?
    var tool: EditorTool = .pen
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 5
    var cropRect: CGRect?
    var onCreate: ((Annotation) -> Void)?
    var onSelect: ((UUID?) -> Void)?
    var onUpdate: ((Annotation) -> Void)?
    var onCrop: ((CGRect?) -> Void)?
    var onDelete: (() -> Void)?

    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var movingOriginal: Annotation?
    private var movedDraft: Annotation?
    private var draftCrop: CGRect?

    override var acceptsFirstResponder: Bool { true }

    private var imageRect: CGRect {
        guard let image = sourceImage, image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private var imageScale: CGFloat {
        guard let image = sourceImage else { return 1 }
        return imageRect.width / image.size.width
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        bounds.fill()
        guard let image = sourceImage else { return }
        let rect = imageRect
        NSColor.black.withAlphaComponent(0.25).setShadow(withBlurRadius: 24, xOffset: 0, yOffset: -4)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSShadow().set()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: imageScale, yBy: imageScale)
        transform.concat()

        for annotation in annotations {
            if let movedDraft, annotation.id == movedDraft.id {
                movedDraft.draw(over: image)
            } else {
                annotation.draw(over: image)
            }
        }
        draft?.draw(over: image)

        if let selected = movedDraft ?? annotations.first(where: { $0.id == selectedID }) {
            let selection = selected.bounds.insetBy(dx: -8 / imageScale, dy: -8 / imageScale)
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1.5 / imageScale
            outline.setLineDash([5 / imageScale, 4 / imageScale], count: 2, phase: 0)
            NSColor.systemTeal.setStroke()
            outline.stroke()
        }

        if let crop = draftCrop ?? cropRect {
            NSColor.black.withAlphaComponent(0.45).setFill()
            let overlay = NSBezierPath(rect: CGRect(origin: .zero, size: image.size))
            overlay.append(NSBezierPath(rect: crop))
            overlay.windingRule = .evenOdd
            overlay.fill()
            let outline = NSBezierPath(rect: crop)
            outline.lineWidth = 2 / imageScale
            outline.setLineDash([8 / imageScale, 4 / imageScale], count: 2, phase: 0)
            NSColor.white.setStroke()
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = imagePoint(for: event, clamp: false) else { return }
        dragStart = point
        switch tool {
        case .select:
            let tolerance = 10 / imageScale
            let hit = annotations.reversed().first {
                $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            movingOriginal = hit
            onSelect?(hit?.id)
        case .crop:
            draftCrop = CGRect(origin: point, size: .zero)
            onCrop?(nil)
        case .text:
            let annotation = Annotation(tool: .text, points: [point], color: color, lineWidth: lineWidth)
            onCreate?(annotation)
            dragStart = nil
        default:
            draft = Annotation(tool: tool, points: [point], color: color, lineWidth: lineWidth)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let point = imagePoint(for: event, clamp: true) else { return }
        switch tool {
        case .select:
            if let original = movingOriginal {
                movedDraft = original.translated(by: CGSize(width: point.x - start.x,
                                                            height: point.y - start.y))
            }
        case .crop:
            draftCrop = CGRect(x: start.x, y: start.y,
                               width: point.x - start.x, height: point.y - start.y).standardized
        case .pen:
            draft?.points.append(point)
        case .text:
            break
        default:
            if draft?.points.count == 1 { draft?.points.append(point) }
            else { draft?.points[1] = point }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            draft = nil
            movedDraft = nil
            movingOriginal = nil
            draftCrop = nil
            needsDisplay = true
        }
        if let movedDraft, let movingOriginal,
           movedDraft.points != movingOriginal.points {
            onUpdate?(movedDraft)
        }
        if let draft {
            let minimum = 3 / imageScale
            let isLargeEnough: Bool
            switch draft.tool {
            case .pen: isLargeEnough = true
            case .rectangle, .ellipse, .highlight, .blur, .redact:
                isLargeEnough = draft.bounds.width >= minimum && draft.bounds.height >= minimum
            default:
                isLargeEnough = draft.bounds.width >= minimum || draft.bounds.height >= minimum
            }
            if isLargeEnough {
                onCreate?(draft)
            }
        }
        if let draftCrop, draftCrop.width >= 10 / imageScale,
           draftCrop.height >= 10 / imageScale {
            onCrop?(draftCrop)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else if event.keyCode == 53 {
            onSelect?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func imagePoint(for event: NSEvent, clamp shouldClamp: Bool) -> CGPoint? {
        guard let image = sourceImage else { return nil }
        let local = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        if !shouldClamp && !rect.contains(local) { return nil }
        let x = (local.x - rect.minX) / imageScale
        let y = (local.y - rect.minY) / imageScale
        return CGPoint(x: min(max(x, 0), image.size.width),
                       y: min(max(y, 0), image.size.height))
    }
}

private extension NSColor {
    func setShadow(withBlurRadius radius: CGFloat, xOffset: CGFloat, yOffset: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = self
        shadow.shadowBlurRadius = radius
        shadow.shadowOffset = CGSize(width: xOffset, height: yOffset)
        shadow.set()
    }
}
