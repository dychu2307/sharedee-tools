import AppKit
import XCTest
@testable import SharedeCapture

/// The scanner decides what Cleanup may delete, so these tests pin down exactly what it
/// picks up, using a throwaway home folder instead of the real one.
final class CleanupScannerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanupScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testCachesAreListedPerFolderWithTheirSize() async throws {
        try write("Library/Caches/com.example.one/data.bin", bytes: 64 * 1024)
        try write("Library/Caches/com.example.one/nested/more.bin", bytes: 64 * 1024)
        try write("Library/Caches/com.example.two/data.bin", bytes: 16 * 1024)

        let category = await CleanupScanner.scan(.userCaches, home: home)

        let sizes = Dictionary(uniqueKeysWithValues: category.items.map { ($0.url.lastPathComponent, $0.size) })
        XCTAssertEqual(Set(sizes.keys), ["com.example.one", "com.example.two"])
        XCTAssertGreaterThanOrEqual(sizes["com.example.one"] ?? 0, 128 * 1024)
        XCTAssertGreaterThanOrEqual(sizes["com.example.two"] ?? 0, 16 * 1024)
        XCTAssertFalse(category.accessDenied)
    }

    func testICloudCachesAreSkipped() async throws {
        try write("Library/Caches/com.apple.bird/state.db", bytes: 4096)
        try write("Library/Caches/CloudKit/state.db", bytes: 4096)
        try write("Library/Caches/com.example.app/data.bin", bytes: 4096)

        let category = await CleanupScanner.scan(.userCaches, home: home)

        XCTAssertEqual(category.items.map(\.url.lastPathComponent), ["com.example.app"])
    }

    func testEmptyFoldersAreNotOffered() async throws {
        try FileManager.default.createDirectory(at: url("Library/Caches/com.example.empty"),
                                                withIntermediateDirectories: true)

        let category = await CleanupScanner.scan(.userCaches, home: home)

        XCTAssertTrue(category.items.isEmpty)
    }

    func testDeveloperCachesAreOfferedAsOneFolder() async throws {
        try write(".npm/_cacache/index-v5/aa/entry", bytes: 4096)
        try write(".npm/_cacache/content-v2/bb/blob", bytes: 4096)
        // The rest of ~/.npm (config, logs) is not a cache and must be left alone.
        try write(".npm/_logs/debug.log", bytes: 4096)

        let category = await CleanupScanner.scan(.devCaches, home: home)

        XCTAssertEqual(category.items.map(\.url.standardizedFileURL),
                       [url(".npm/_cacache").standardizedFileURL])
    }

    func testMissingFoldersGiveAnEmptyResult() async {
        for kind in CleanupKind.allCases {
            let category = await CleanupScanner.scan(kind, home: home)
            XCTAssertTrue(category.items.isEmpty, "\(kind)")
            XCTAssertFalse(category.accessDenied, "\(kind)")
        }
    }

    func testLargeFilesOnlyIncludeVisibleFilesAboveTheThreshold() async throws {
        try write("Downloads/big.mov", bytes: 2 * 1024 * 1024)
        try write("Documents/Projects/archive.zip", bytes: 2 * 1024 * 1024)
        try write("Downloads/small.txt", bytes: 1024)
        try write("Downloads/.hidden.bin", bytes: 2 * 1024 * 1024)
        // Packages are skipped whole, so Cleanup never breaks one apart.
        try write("Movies/Library.photoslibrary/originals/photo.heic", bytes: 2 * 1024 * 1024)
        try write("Downloads/Tool.app/Contents/MacOS/Tool", bytes: 2 * 1024 * 1024)
        // Folders outside the four scanned ones are never touched.
        try write("Pictures/huge.raw", bytes: 2 * 1024 * 1024)

        let category = await CleanupScanner.scan(.largeFiles, home: home, largeFileThreshold: 1024 * 1024)

        XCTAssertEqual(Set(category.items.map(\.url.lastPathComponent)), ["big.mov", "archive.zip"])
    }

    func testEveryItemStaysInsideItsScannedFolders() async throws {
        try write("Library/Caches/com.example.app/data.bin", bytes: 4096)
        try write("Library/Logs/DiagnosticReports/crash.ips", bytes: 4096)
        try write("Library/Developer/Xcode/DerivedData/App-abc/Build/out.o", bytes: 4096)
        try write("Library/Developer/CoreSimulator/Caches/dyld/cache", bytes: 4096)
        try write(".gradle/caches/modules/jar", bytes: 4096)
        try write(".Trash/old.txt", bytes: 4096)
        try write("Downloads/big.bin", bytes: 2 * 1024 * 1024)
        try write("Library/Application Support/App/important.db", bytes: 4096)
        try write("Library/Preferences/com.example.app.plist", bytes: 4096)

        let allowed = ["Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData",
                       "Library/Developer/CoreSimulator/Caches", ".gradle/caches", ".Trash", "Downloads"]
            .map { url($0).standardizedFileURL.path }
        var found: [URL] = []
        for kind in CleanupKind.allCases {
            found += await CleanupScanner.scan(kind, home: home, largeFileThreshold: 1024 * 1024).items.map(\.url)
        }

        XCTAssertEqual(found.count, 7)
        for item in found {
            let path = item.standardizedFileURL.path
            XCTAssertTrue(allowed.contains { path == $0 || path.hasPrefix($0 + "/") }, path)
        }
    }

    func testPermanentRemoveDeletesTheItem() async throws {
        try write("Library/Caches/com.example.app/data.bin", bytes: 4096)
        let target = url("Library/Caches/com.example.app")

        let removed = await CleanupScanner.remove(target, permanently: true)

        XCTAssertTrue(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testRemoveReportsFailureInsteadOfThrowing() async {
        let removed = await CleanupScanner.remove(url("Library/Caches/missing"), permanently: true)
        XCTAssertFalse(removed)
    }

    func testInstallersAreFoundAndNotCountedAgainAsLargeFiles() async throws {
        try write("Downloads/Tool-1.2.dmg", bytes: 2 * 1024 * 1024)
        try write("Downloads/Old/Driver.PKG", bytes: 4096)
        try write("Downloads/Xcode_16.xip", bytes: 4096)
        try write("Downloads/notes.txt", bytes: 4096)
        try write("Desktop/Other.dmg", bytes: 4096)

        let installers = await CleanupScanner.scan(.installers, home: home)
        let large = await CleanupScanner.scan(.largeFiles, home: home, largeFileThreshold: 1024 * 1024)

        XCTAssertEqual(Set(installers.items.map(\.url.lastPathComponent)), ["Tool-1.2.dmg", "Driver.PKG", "Xcode_16.xip"])
        XCTAssertTrue(large.items.isEmpty)
    }

    func testOnlyNodeModulesOfStaleProjectsAreOffered() async throws {
        try write("Developer/old-app/package.json", bytes: 100)
        try write("Developer/old-app/node_modules/left-pad/index.js", bytes: 4096)
        try write("Developer/old-app/node_modules/left-pad/node_modules/dep/index.js", bytes: 4096)
        try write("Developer/new-app/package.json", bytes: 100)
        try write("Developer/new-app/node_modules/react/index.js", bytes: 4096)
        try write("Projects/group/legacy/package.json", bytes: 100)
        try write("Projects/group/legacy/node_modules/lodash/index.js", bytes: 4096)
        let longAgo = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        for path in ["Developer/old-app/package.json", "Projects/group/legacy/package.json"] {
            try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: url(path).path)
        }

        let category = await CleanupScanner.scan(.nodeModules, home: home)

        XCTAssertEqual(Set(category.items.map { $0.url.standardizedFileURL.path }),
                       Set(["Developer/old-app/node_modules", "Projects/group/legacy/node_modules"]
                            .map { url($0).standardizedFileURL.path }))
        XCTAssertEqual(Set(category.items.map(\.name)), ["old-app / node_modules", "legacy / node_modules"])
    }

    func testBackupsAreLabelledWithTheDeviceName() async throws {
        try write("Library/Application Support/MobileSync/Backup/00008101-ABC/Manifest.db", bytes: 4096)
        let info: NSDictionary = ["Device Name": "Test iPhone"]
        info.write(to: url("Library/Application Support/MobileSync/Backup/00008101-ABC/Info.plist"), atomically: true)

        let category = await CleanupScanner.scan(.iosBackups, home: home)

        XCTAssertEqual(category.items.map(\.name), ["Test iPhone"])
    }

    func testOnlyJunkIsSelectedByDefaultAndOnlyJunkIsDeletedOutright() {
        let junk: Set<CleanupKind> = [.userCaches, .logs, .xcode, .devCaches]
        for kind in CleanupKind.allCases {
            XCTAssertEqual(kind.selectedByDefault, junk.contains(kind), "\(kind)")
        }
        for kind: CleanupKind in [.installers, .iosBackups, .largeFiles] {
            XCTAssertFalse(kind.deletesPermanently, "\(kind)")
        }
    }

    @MainActor
    func testRunningAppsAreFoundOnlyForSelectedCaches() {
        // The test host is itself a running app, so its cache folder stands in for any app's.
        let current = NSRunningApplication.current
        let ownCache = CleanupItem(url: url("Library/Caches/\(current.bundleIdentifier ?? "")"), size: 1)
        let otherCache = CleanupItem(url: url("Library/Caches/com.example.other"), size: 1)
        let category = CleanupCategory(kind: .userCaches, items: [ownCache, otherCache])
        let model = CleanupModel()

        model.selection = [otherCache.url]
        XCTAssertTrue(model.runningOwners(of: category, among: [current]).isEmpty)

        model.selection = [ownCache.url, otherCache.url]
        XCTAssertEqual(model.runningOwners(of: category, among: [current]), [current])
    }

    // MARK: Helpers

    private func url(_ path: String) -> URL {
        home.appendingPathComponent(path)
    }

    private func write(_ path: String, bytes: Int) throws {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Random bytes so the file really takes up disk space (zeros could be stored sparsely).
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            arc4random_buf(buffer.baseAddress, bytes)
        }
        try data.write(to: file)
    }
}
