import XCTest
@testable import SharedeCapture

final class TextRecognizerTests: XCTestCase {
    func testRecognitionLanguagesKeepOnlySupportedOnes() {
        let languages = TextRecognizer.recognitionLanguages(supported: ["en-US", "fr-FR", "vi-VT"])
        XCTAssertTrue(languages.contains("vi-VT"))
        XCTAssertTrue(languages.contains("en-US"))
        XCTAssertEqual(Set(languages).count, languages.count)
        XCTAssertTrue(languages.allSatisfy { ["en-US", "fr-FR", "vi-VT"].contains($0) })
    }

    func testRecognitionLanguagesWithoutVietnameseSupport() {
        XCTAssertEqual(TextRecognizer.recognitionLanguages(supported: ["en-US"]), ["en-US"])
    }

    func testRecognizesRenderedText() async throws {
        let size = NSSize(width: 900, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("Sharedee Tools 2026" as NSString).draw(at: NSPoint(x: 20, y: 30),
                                                 withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let lines = try await TextRecognizer.recognize(cgImage)
        XCTAssertEqual(lines.joined(separator: " "), "Sharedee Tools 2026")
    }
}
