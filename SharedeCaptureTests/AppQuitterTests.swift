import AppKit
import XCTest
@testable import SharedeCapture

@MainActor
final class AppQuitterTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AppQuitterTests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testQuitAllSkipsExcludedAppsAndTheKeptApp() {
        // The test host is a real running app, so it stands in for any app in the list.
        let app = NSRunningApplication.current
        let id = app.bundleIdentifier ?? ""

        XCTAssertEqual(AppQuitter.quitAllTargets([app], excluded: []), [app])
        XCTAssertTrue(AppQuitter.quitAllTargets([app], excluded: [id]).isEmpty)
        XCTAssertTrue(AppQuitter.quitAllTargets([app], excluded: [], keeping: app).isEmpty)
    }

    func testExclusionsAreRememberedAcrossLaunches() {
        let app = NSRunningApplication.current
        let quitter = AppQuitter(defaults: defaults)
        XCTAssertFalse(quitter.isExcluded(app))

        quitter.setExcluded(true, for: app)
        XCTAssertTrue(AppQuitter(defaults: defaults).isExcluded(app))

        quitter.setExcluded(false, for: app)
        XCTAssertFalse(AppQuitter(defaults: defaults).isExcluded(app))
    }

    func testTheAppListNeverIncludesFinderOrItself() {
        let quitter = AppQuitter(defaults: defaults)
        let ids = quitter.apps.compactMap(\.bundleIdentifier)

        XCTAssertFalse(ids.contains("com.apple.finder"))
        XCTAssertFalse(quitter.apps.contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
    }
}
