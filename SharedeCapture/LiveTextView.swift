import AppKit
import SwiftUI
import VisionKit

/// Shows the edited image with Apple's Live Text overlay, so text can be selected and copied
/// directly on the capture, like in Preview.
@available(macOS 13.0, *)
struct LiveTextView: NSViewRepresentable {
    let image: NSImage
    var onAnalyzed: (Bool) -> Void = { _ in }

    static var isSupported: Bool { ImageAnalyzer.isSupported }

    func makeNSView(context: Context) -> LiveTextContainerView {
        LiveTextContainerView()
    }

    func updateNSView(_ view: LiveTextContainerView, context: Context) {
        view.onAnalyzed = onAnalyzed
        view.show(image)
    }
}

@available(macOS 13.0, *)
final class LiveTextContainerView: NSView {
    var onAnalyzed: (Bool) -> Void = { _ in }

    private let imageView = NSImageView()
    private let overlay = ImageAnalysisOverlayView()
    private let analyzer = ImageAnalyzer()
    private var shownImage: NSImage?
    private var analysisTask: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        overlay.frame = imageView.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.trackingImageView = imageView
        overlay.preferredInteractionTypes = .textSelection
        imageView.addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { analysisTask?.cancel() }

    func show(_ image: NSImage) {
        guard image !== shownImage else { return }
        shownImage = image
        imageView.image = image
        overlay.analysis = nil
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            var configuration = ImageAnalyzer.Configuration([.text])
            configuration.locales = TextRecognizer.recognitionLanguages(
                supported: ImageAnalyzer.supportedTextRecognitionLanguages)
            let analysis = try? await self.analyzer.analyze(image, orientation: .up, configuration: configuration)
            guard !Task.isCancelled else { return }
            self.overlay.analysis = analysis
            self.onAnalyzed(analysis?.hasResults(for: .text) ?? false)
        }
    }
}
