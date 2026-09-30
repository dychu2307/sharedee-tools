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
