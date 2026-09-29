import AppKit
import XCTest
@testable import SharedeCapture

@MainActor
final class QuickAccessTests: XCTestCase {
    func testThumbnailCanOpenAndDismissWithoutEditor() {
        let controller = QuickAccessController()
        let image = NSImage(size: CGSize(width: 640, height: 360))

        controller.show(image: image, onCopy: {}, onEdit: {}, onSave: {}, onDismiss: {})
        XCTAssertTrue(controller.isVisible)

        controller.dismiss()
        XCTAssertFalse(controller.isVisible)
    }
}
