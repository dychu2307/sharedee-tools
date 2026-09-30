import AppKit
import Vision

/// On-device text recognition with Apple's Vision framework (the engine behind Live Text).
enum TextRecognizer {
    /// Languages to recognize, most preferred first: the user's system languages, then
    /// Vietnamese and English, limited to what Vision supports on this macOS version.
    static func recognitionLanguages(supported: [String]) -> [String] {
        let wanted = Locale.preferredLanguages + ["vi-VT", "en-US"]
        var result: [String] = []
        for language in wanted {
            let code = language.replacingOccurrences(of: "_", with: "-")
            let base = code.split(separator: "-").first.map(String.init) ?? code
            let match = supported.first { $0.caseInsensitiveCompare(code) == .orderedSame }
                ?? supported.first { $0.split(separator: "-").first.map(String.init) == base }
            if let match, !result.contains(match) { result.append(match) }
        }
        return result
    }

    /// Recognized lines in reading order, or an empty array when the image has no text.
    static func recognize(_ image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    let supported = (try? request.supportedRecognitionLanguages()) ?? []
                    let languages = recognitionLanguages(supported: supported)
                    if !languages.isEmpty { request.recognitionLanguages = languages }
                    if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func cgImage(from data: Data) -> CGImage? {
        NSBitmapImageRep(data: data)?.cgImage
    }
}
