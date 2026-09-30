import AppKit
import SwiftUI

/// What the cleanup tool looks for. Junk kinds hold files apps rebuild on their own, so they
/// are deleted outright (moving them to the Trash would not free any space). Large files are
/// the user's own documents, so they only ever go to the Trash and are never picked by default.
enum CleanupKind: String, CaseIterable, Identifiable {
    case userCaches, logs, xcode, devCaches, trash, largeFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: L10n.tr("Bộ nhớ đệm ứng dụng")
        case .logs: L10n.tr("Nhật ký hệ thống")
        case .xcode: L10n.tr("Dữ liệu Xcode")
        case .devCaches: L10n.tr("Bộ nhớ đệm lập trình")
        case .trash: L10n.tr("Thùng rác")
        case .largeFiles: L10n.tr("File lớn")
        }
    }

    var detail: String {
        switch self {
        case .userCaches: L10n.tr("Ứng dụng sẽ tự tạo lại khi cần")
        case .logs: L10n.tr("Nhật ký và báo cáo lỗi cũ")
        case .xcode: L10n.tr("DerivedData, DeviceSupport, cache simulator")
        case .devCaches: L10n.tr("npm, Gradle, Yarn, Bun")
        case .trash: L10n.tr("Xoá vĩnh viễn các mục trong Thùng rác")
        case .largeFiles: L10n.tr("Từ 200 MB trong Downloads, Desktop, Documents, Movies · chuyển vào Thùng rác")
        }
    }

    var symbol: String {
        switch self {
        case .userCaches: "shippingbox"
        case .logs: "doc.text.magnifyingglass"
        case .xcode: "hammer"
        case .devCaches: "terminal"
        case .trash: "trash"
        case .largeFiles: "doc.richtext"
        }
    }

    var color: Color {
        switch self {
        case .userCaches: Color(red: 0.31, green: 0.87, blue: 0.78)
        case .logs: .orange
        case .xcode: Color(red: 0.35, green: 0.6, blue: 1)
        case .devCaches: .purple
        case .trash: .pink
        case .largeFiles: .yellow
        }
    }

    /// Apps whose data lives in this kind even though the items aren't named after them.
    var ownerBundleIDs: Set<String> {
        switch self {
        case .xcode: ["com.apple.dt.xcode", "com.apple.iphonesimulator"]
        default: []
        }
    }

    var deletesPermanently: Bool { self != .largeFiles }
    var selectedByDefault: Bool { self != .trash && self != .largeFiles }
}

struct CleanupItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    var id: URL { url }
    var name: String { FileManager.default.displayName(atPath: url.path) }
    var displayPath: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
}

struct DiskUsage: Equatable {
    let name: String
    let total: Int64
    let available: Int64
    var used: Int64 { max(0, total - available) }
}

struct CleanupCategory: Identifiable {
    let kind: CleanupKind
    var items: [CleanupItem] = []
    var accessDenied = false
    var id: CleanupKind { kind }
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

@MainActor
final class CleanupModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var categories: [CleanupCategory] = []
    @Published var selection: Set<URL> = []
    /// Bytes found so far while scanning.
    @Published private(set) var found: Int64 = 0
    @Published private(set) var currentPath = ""
    @Published private(set) var activeKind: CleanupKind?
    @Published private(set) var finishedKinds: Set<CleanupKind> = []
    @Published private(set) var freed: Int64 = 0
    @Published private(set) var cleanProgress: Double = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var disk: DiskUsage?
    private var task: Task<Void, Never>?

    var isBusy: Bool { phase == .scanning || phase == .cleaning }
    var totalSize: Int64 { categories.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 {
        categories.flatMap(\.items).reduce(0) { selection.contains($1.url) ? $0 + $1.size : $0 }
    }

    func scan() {
        guard !isBusy else { return }
        phase = .scanning
        categories = []
        selection = []
        found = 0
        currentPath = ""
        finishedKinds = []
        let model = self
        task = Task {
            let started = Date()
            for kind in CleanupKind.allCases {
                if Task.isCancelled { break }
                activeKind = kind
                let base = found
                let kindStarted = Date()
                var category = await CleanupScanner.scan(kind) { bytes, path in
                    Task { @MainActor in model.reportScan(found: base + bytes, path: path) }
                }
                category.items.sort { $0.size > $1.size }
                // Give each step a beat so the scan reads as progress instead of a flash.
                await Self.pause(until: kindStarted.addingTimeInterval(0.35))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    categories.append(category)
                    finishedKinds.insert(kind)
                }
                found = base + category.size
                if kind.selectedByDefault { selection.formUnion(category.items.map(\.url)) }
            }
            await Self.pause(until: started.addingTimeInterval(1.8))
            activeKind = nil
            currentPath = ""
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = Task.isCancelled && categories.isEmpty ? .idle : .results
            }
        }
    }

    func cancelScan() {
        task?.cancel()
    }

    func clean() {
        guard phase == .results else { return }
        let targets = categories.flatMap { category in
            category.items.filter { selection.contains($0.url) }.map { ($0, category.kind) }
        }
        guard !targets.isEmpty else { return }
        let totalBytes = max(1, targets.reduce(0) { $0 + $1.0.size })
        phase = .cleaning
        freed = 0
        cleanProgress = 0
        failedCount = 0
        finishedKinds = []
        task = Task {
            let started = Date()
            var processed: Int64 = 0
            var removed: Set<URL> = []
            for (item, kind) in targets {
                activeKind = kind
                if await CleanupScanner.remove(item.url, permanently: kind.deletesPermanently) {
                    removed.insert(item.url)
                    freed += item.size
                } else {
                    failedCount += 1
                }
                processed += item.size
                cleanProgress = Double(processed) / Double(totalBytes)
                if targets.last(where: { $0.1 == kind })?.0 == item { finishedKinds.insert(kind) }
            }
            await Self.pause(until: started.addingTimeInterval(1.5))
            activeKind = nil
            for index in categories.indices {
                categories[index].items.removeAll { removed.contains($0.url) }
            }
            selection.subtract(removed)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phase = .done
            }
            refreshDisk()
        }
    }

    func refreshDisk() {
        Task {
            let usage = await Self.readDiskUsage()
            withAnimation(.easeInOut(duration: 0.6)) { disk = usage }
        }
    }

    /// Running apps whose data is selected for cleaning in this category. Clearing a cache
    /// under a running app can lose what it is doing, so the page suggests quitting them first.
    func runningOwners(of category: CleanupCategory, among running: [NSRunningApplication]) -> [NSRunningApplication] {
        let selectedNames = Set(category.items.filter { selection.contains($0.url) }
            .map { $0.url.lastPathComponent.lowercased() })
        guard !selectedNames.isEmpty else { return [] }
        return running.filter { app in
            guard let id = app.bundleIdentifier?.lowercased() else { return false }
            return selectedNames.contains(id) || category.kind.ownerBundleIDs.contains(id)
        }
    }

    nonisolated private static func readDiskUsage() async -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskUsage(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total), available: available)
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
        categories = []
        selection = []
    }

    // MARK: Selection

    enum SelectionState { case all, some, none }

    func selectionState(of category: CleanupCategory) -> SelectionState {
        let count = category.items.filter { selection.contains($0.url) }.count
        if count == 0 { return .none }
        return count == category.items.count ? .all : .some
    }

    func toggle(_ category: CleanupCategory) {
        let urls = category.items.map(\.url)
        if selectionState(of: category) == .all {
            selection.subtract(urls)
        } else {
            selection.formUnion(urls)
        }
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.url) {
            selection.remove(item.url)
        } else {
            selection.insert(item.url)
        }
    }

    private func reportScan(found bytes: Int64, path: String) {
        guard phase == .scanning, bytes >= found else { return }
        found = bytes
        currentPath = path
    }

    private static func pause(until date: Date) async {
        let remaining = date.timeIntervalSinceNow
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
    }
}

/// File system work for the cleanup tool. Its async functions are not tied to the main actor,
/// so the scan and delete run in the background.
enum CleanupScanner {
    private struct Root {
        let path: String
        /// List each child as its own item (e.g. one DerivedData folder per project) instead of the folder as a whole.
        var listChildren = true
    }

    static let largeFileThreshold: Int64 = 200 * 1024 * 1024
    /// Caches that belong to iCloud sync; clearing them forces a full resync.
    private static let skippedNames: Set<String> = ["com.apple.bird", "CloudKit", "com.apple.cloudd"]
    private static let sizeKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    private static func roots(for kind: CleanupKind) -> [Root] {
        switch kind {
        case .userCaches: [Root(path: "Library/Caches")]
        case .logs: [Root(path: "Library/Logs")]
        case .xcode: [Root(path: "Library/Developer/Xcode/DerivedData"),
                      Root(path: "Library/Developer/Xcode/iOS DeviceSupport"),
                      Root(path: "Library/Developer/Xcode/watchOS DeviceSupport"),
                      Root(path: "Library/Developer/CoreSimulator/Caches", listChildren: false)]
        case .devCaches: [Root(path: ".npm/_cacache", listChildren: false),
                          Root(path: ".gradle/caches", listChildren: false),
                          Root(path: ".yarn/berry/cache", listChildren: false),
                          Root(path: ".bun/install/cache", listChildren: false)]
        case .trash: [Root(path: ".Trash")]
        case .largeFiles: ["Downloads", "Desktop", "Documents", "Movies"].map { Root(path: $0) }
        }
    }

    static func scan(_ kind: CleanupKind,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     largeFileThreshold: Int64 = largeFileThreshold,
                     report: @escaping @Sendable (Int64, String) -> Void = { _, _ in }) async -> CleanupCategory {
        var category = CleanupCategory(kind: kind)
        let throttle = Throttle()
        var total: Int64 = 0
        for root in roots(for: kind) {
            let url = home.appendingPathComponent(root.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if kind == .largeFiles {
                category.items += largeFiles(in: url, threshold: largeFileThreshold) { path in
                    if throttle.ready() { report(total, path) }
                }
                continue
            }
            let targets: [URL]
            if root.listChildren {
                do {
                    targets = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                } catch {
                    category.accessDenied = true
                    continue
                }
            } else {
                targets = [url]
            }
            for target in targets where !skippedNames.contains(target.lastPathComponent) {
                if Task.isCancelled { return category }
                let base = total
                let size = allocatedSize(of: target) { bytes, path in
                    if throttle.ready() { report(base + bytes, path) }
                }
                total += size
                if size > 0 { category.items.append(CleanupItem(url: target, size: size)) }
            }
        }
        return category
    }

    static func remove(_ url: URL, permanently: Bool) async -> Bool {
        do {
            if permanently {
                try FileManager.default.removeItem(at: url)
            } else {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            return true
        } catch {
            return false
        }
    }

    static func allocatedSize(of url: URL, progress: (Int64, String) -> Void = { _, _ in }) -> Int64 {
        if let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys),
                                                              options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? file.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            progress(total, file.path)
        }
        return total
    }

    /// Regular files at or above the threshold. Packages such as Photos libraries and apps are
    /// skipped whole, so the tool never offers to break one apart.
    private static func largeFiles(in url: URL, threshold: Int64, progress: (String) -> Void) -> [CleanupItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return [] }
        var items: [CleanupItem] = []
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            progress(file.path)
            guard let values = try? file.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= threshold { items.append(CleanupItem(url: file, size: size)) }
        }
        return items
    }

    /// Limits progress reports to about 20 a second so the UI isn't flooded.
    private final class Throttle: @unchecked Sendable {
        private var last: TimeInterval = 0

        func ready() -> Bool {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - last >= 0.05 else { return false }
            last = now
            return true
        }
    }
}
