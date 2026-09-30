import XCTest
@testable import SharedeCapture

/// Leftover matching decides which Library files go to the Trash with an app, so these tests
/// pin down what counts as a match, using a throwaway home folder.
final class AppUninstallerTests: XCTestCase {
    private var home: URL!
    private let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Example Editor.app"),
                                   name: "Example Editor", bundleID: "com.example.editor", version: "1.0")

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppUninstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testFindsFilesNamedAfterTheBundleIDAcrossTheLibrary() throws {
        let expected = [
            "Library/Application Support/com.example.editor",
            "Library/Caches/com.example.editor",
            "Library/Logs/com.example.editor",
            "Library/Preferences/com.example.editor.plist",
            "Library/Preferences/com.example.editor.helper.plist",
            "Library/Preferences/ByHost/com.example.editor.0A1B2C.plist",
            "Library/Containers/com.example.editor",
            "Library/Containers/com.example.editor.ShareExtension",
            "Library/Group Containers/ABCDE12345.com.example.editor",
            "Library/Group Containers/group.com.example.editor.shared",
            "Library/Application Scripts/com.example.editor",
            "Library/Saved Application State/com.example.editor.savedState",
            "Library/HTTPStorages/com.example.editor",
            "Library/WebKit/com.example.editor",
            "Library/Cookies/com.example.editor.binarycookies",
            "Library/LaunchAgents/com.example.editor.updater.plist",
        ]
        try expected.forEach { try write($0) }

        let found = AppUninstaller.leftovers(for: app, home: home)

        XCTAssertEqual(Set(found.map(relativePath)), Set(expected))
        XCTAssertTrue(found.allSatisfy { !$0.matchedByName })
    }

    func testIgnoresOtherAppsWithASimilarBundleID() throws {
        try write("Library/Application Support/com.example.editor2")
        try write("Library/Application Support/com.example.editorial")
        try write("Library/Caches/com.example")
        try write("Library/Preferences/com.example.editor-backup.plist")
        try write("Library/Containers/com.example.editorkit")
        try write("Library/Group Containers/group.com.example.editorial")

        XCTAssertTrue(AppUninstaller.leftovers(for: app, home: home).isEmpty)
    }

    func testFoldersNamedAfterTheAppAreFlagged() throws {
        try write("Library/Application Support/Example Editor")
        // A name match counts only where apps use their name as a folder, not everywhere.
        try write("Library/Containers/Example Editor")

        let found = AppUninstaller.leftovers(for: app, home: home)

        XCTAssertEqual(found.map(relativePath), ["Library/Application Support/Example Editor"])
        XCTAssertEqual(found.first?.matchedByName, true)
    }

    func testShortAppNamesAreNotMatchedByName() throws {
        let short = InstalledApp(url: URL(fileURLWithPath: "/Applications/Go.app"),
                                 name: "Go", bundleID: "com.example.go", version: nil)
        try write("Library/Application Support/Go")

        XCTAssertTrue(AppUninstaller.leftovers(for: short, home: home).isEmpty)
    }

    func testFilesOutsideTheLibraryAreNeverMatched() throws {
        try write("Documents/com.example.editor")
        try write("Library/Mail/com.example.editor")
        try write("Library/Keychains/com.example.editor")

        XCTAssertTrue(AppUninstaller.leftovers(for: app, home: home).isEmpty)
    }

    func testAppleAndOwnAppsCannotBeUninstalled() {
        XCTAssertFalse(AppUninstaller.canUninstall(bundleID: "com.apple.Safari"))
        XCTAssertFalse(AppUninstaller.canUninstall(bundleID: "com.sharedecapture.app"))
        XCTAssertFalse(AppUninstaller.canUninstall(bundleID: "com.sharedecapture.app.dev"))
        XCTAssertFalse(AppUninstaller.canUninstall(bundleID: "nodots"))
        XCTAssertTrue(AppUninstaller.canUninstall(bundleID: "com.example.editor"))

        let apple = InstalledApp(url: URL(fileURLWithPath: "/Applications/Safari.app"),
                                 name: "Safari", bundleID: "com.apple.Safari", version: nil)
        XCTAssertTrue(AppUninstaller.leftovers(for: apple, home: home).isEmpty)
    }

    func testInstalledAppsReadsBundlesAndNestedFolders() throws {
        let folder = home.appendingPathComponent("Applications")
        try makeApp(folder.appendingPathComponent("Zeta.app"), bundleID: "com.example.zeta")
        try makeApp(folder.appendingPathComponent("Suite/Alpha.app"), bundleID: "com.example.alpha")
        try makeApp(folder.appendingPathComponent("Safari.app"), bundleID: "com.apple.Safari")
        // The same bundle ID twice (e.g. an old copy) is listed once.
        try makeApp(folder.appendingPathComponent("Suite/Zeta copy.app"), bundleID: "com.example.zeta")

        let apps = AppUninstaller.installedApps(in: [folder])

        XCTAssertEqual(apps.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(apps.first?.version, "2.1")
    }

    // MARK: Helpers

    private func relativePath(_ leftover: AppLeftover) -> String {
        String(leftover.url.standardizedFileURL.path.dropFirst(home.standardizedFileURL.path.count + 1))
    }

    private func write(_ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func makeApp(_ url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": "2.1",
                                   "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
