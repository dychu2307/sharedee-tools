import AppKit
import XCTest
@testable import SharedeCapture

@MainActor
final class QuickAccessTests: XCTestCase {
    func testEnglishDefaultAndVietnameseSelection() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "appLanguage")
        let previousSelection = LanguageSettings.shared.selection
        defer {
            LanguageSettings.shared.selection = previousSelection
            if let previous { defaults.set(previous, forKey: "appLanguage") }
            else { defaults.removeObject(forKey: "appLanguage") }
        }

        defaults.removeObject(forKey: "appLanguage")
        XCTAssertEqual(L10n.tr("Chụp ảnh"), "Capture")
        LanguageSettings.shared.selection = .vietnamese
        XCTAssertEqual(L10n.tr("Chụp ảnh"), "Chụp ảnh")
        LanguageSettings.shared.selection = .english
        XCTAssertEqual(L10n.tr("Chụp ảnh"), "Capture")
    }

    func testThumbnailCanOpenAndDismissWithoutEditor() {
        let controller = QuickAccessController()
        let image = NSImage(size: CGSize(width: 640, height: 360))
        let first = UUID()
        let second = UUID()

        controller.show(id: first, image: image, status: "Ảnh đầu tiên", onCopy: {},
                        onEdit: {}, onSave: {}, onUpload: nil, onDismiss: {})
        controller.show(id: second, image: image, status: "Ảnh thứ hai", onCopy: {},
                        onEdit: {}, onSave: {}, onUpload: nil, onDismiss: {})
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.count, 2)

        controller.hideAll()
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(controller.count, 2)
        controller.restoreAll()
        XCTAssertTrue(controller.isVisible)

        controller.dismiss(first)
        XCTAssertEqual(controller.count, 1)
        XCTAssertTrue(controller.isVisible)
        controller.dismiss(second)
        XCTAssertEqual(controller.count, 0)
        XCTAssertFalse(controller.isVisible)
    }

    func testEditOpensImageSizedPanel() {
        let runtime = AppRuntime.shared
        runtime.state.image = NSImage(size: CGSize(width: 640, height: 360))

        runtime.showEditor()
        defer { runtime.closeEditor() }

        let panel = NSApp.windows.first { $0 is NSPanel && $0.title == "Sharedee Tools" && $0.isVisible }
        XCTAssertTrue(panel is NSPanel)
        XCTAssertTrue(panel?.styleMask.contains(.borderless) == true)
        XCTAssertEqual(panel?.contentView?.bounds.width ?? 0, 640, accuracy: 1)
        XCTAssertEqual(panel?.contentView?.bounds.height ?? 0, 508, accuracy: 1)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
    }

    func testSettingsOpenInsideMainWindow() {
        let runtime = AppRuntime.shared
        runtime.closeEditor()
        runtime.showSettings()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertEqual(runtime.navigation.page, .settings(.general))

        let main = NSApp.windows.first { $0.title == "Sharedee Tools" && !($0 is NSPanel) && $0.isVisible }
        XCTAssertNotNil(main)
        XCTAssertFalse(NSApp.windows.contains { $0.title == "Cài đặt Sharedee Tools" && $0.isVisible })
        main?.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testMainWindowCanReopenFromMenuBar() {
        let runtime = AppRuntime.shared
        runtime.closeEditor()

        runtime.showMainWindow()
        let main = NSApp.windows.first { $0.title == "Sharedee Tools" && !($0 is NSPanel) && $0.isVisible }
        XCTAssertNotNil(main)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)

        main?.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        runtime.showMainWindow()
        XCTAssertTrue(main?.isVisible == true)
        main?.close()
    }
}
