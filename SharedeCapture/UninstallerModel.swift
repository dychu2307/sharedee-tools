import AppKit
import SwiftUI

@MainActor
final class UninstallerModel: ObservableObject {
    enum Phase: Equatable { case browsing, reviewing, removing, done }

    @Published private(set) var phase: Phase = .browsing
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    @Published private(set) var selectedApp: InstalledApp?
    @Published private(set) var leftovers: [AppLeftover] = []
    @Published private(set) var isFindingLeftovers = false
    @Published var leftoverSelection: Set<URL> = []
    @Published private(set) var freed: Int64 = 0
    @Published private(set) var errorMessage: String?
    private var loadTask: Task<Void, Never>?

    var selectedSize: Int64 {
        (selectedApp?.size ?? 0) + leftovers.reduce(0) { leftoverSelection.contains($1.url) ? $0 + $1.size : $0 }
    }

    func loadApps() {
        guard loadTask == nil, !isLoadingApps else { return }
        isLoadingApps = true
        loadTask = Task {
            let found = await Self.findApps()
            withAnimation(.easeOut(duration: 0.25)) {
                apps = found
                isLoadingApps = false
            }
            // Bundle sizes can take a while for big apps, so fill them in as they arrive.
            for app in found {
                let (size, lastUsed) = await Self.details(of: app.url)
                if let index = apps.firstIndex(where: { $0.url == app.url }) {
                    apps[index].size = size
                    apps[index].lastUsed = lastUsed
                }
                if selectedApp?.url == app.url {
                    selectedApp?.size = size
                    selectedApp?.lastUsed = lastUsed
                }
            }
            loadTask = nil
        }
    }

    func reloadApps() {
        loadTask?.cancel()
        loadTask = nil
        isLoadingApps = false
        loadApps()
    }

    func select(_ app: InstalledApp) {
        guard phase == .browsing || phase == .done else { return }
        selectedApp = apps.first { $0.url == app.url } ?? app
        leftovers = []
        leftoverSelection = []
        errorMessage = nil
        isFindingLeftovers = true
        withAnimation(.easeInOut(duration: 0.3)) { phase = .reviewing }
        Task {
            let found = await Self.findLeftovers(for: app)
            guard selectedApp?.url == app.url else { return }
            if selectedApp?.size == nil { selectedApp?.size = await Self.details(of: app.url).0 }
            withAnimation(.easeOut(duration: 0.3)) {
                leftovers = found
                leftoverSelection = Set(found.filter { !$0.matchedByName }.map(\.url))
                isFindingLeftovers = false
            }
        }
    }

    /// Opens a dropped or chosen `.app` bundle, even one outside the Applications folders.
    func select(appAt url: URL) {
        guard let app = AppUninstaller.installedApp(at: url) else {
            errorMessage = L10n.tr("Không thể gỡ ứng dụng này. Ứng dụng của macOS được hệ thống bảo vệ.")
            return
        }
        select(app)
    }

    func back() {
        guard phase != .removing else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .browsing
            selectedApp = nil
            errorMessage = nil
        }
    }

    func toggle(_ leftover: AppLeftover) {
        if leftoverSelection.contains(leftover.url) {
            leftoverSelection.remove(leftover.url)
        } else {
            leftoverSelection.insert(leftover.url)
        }
    }

    func uninstall() {
        guard phase == .reviewing, let app = selectedApp else { return }
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.45)) { phase = .removing }
        Task {
            let started = Date()
            if !(await Self.quitIfRunning(app)) {
                errorMessage = L10n.format("%@ vẫn đang chạy. Hãy thoát ứng dụng rồi thử lại.", app.name)
                withAnimation { phase = .reviewing }
                return
            }
            let targets = [app.url] + leftovers.filter { leftoverSelection.contains($0.url) }.map(\.url)
            var moved: Set<URL> = []
            do {
                moved = Set(try await NSWorkspace.shared.recycle(targets).keys)
            } catch {
                // Some items may still have moved; see which ones are gone.
                moved = Set(targets.filter { !FileManager.default.fileExists(atPath: $0.path) })
            }
            let remaining = started.addingTimeInterval(1.2).timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }

            guard moved.contains(app.url) else {
                errorMessage = L10n.format("Không thể chuyển %@ vào Thùng rác. macOS có thể đã chặn thao tác này.", app.name)
                withAnimation { phase = .reviewing }
                return
            }
            freed = (app.size ?? 0) + leftovers.filter { moved.contains($0.url) }.reduce(0) { $0 + $1.size }
            apps.removeAll { $0.url == app.url }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { phase = .done }
        }
    }

    // MARK: Background work (nonisolated, so it runs off the main thread)

    nonisolated private static func findApps() async -> [InstalledApp] {
        AppUninstaller.installedApps()
    }

    nonisolated private static func details(of url: URL) async -> (Int64, Date?) {
        (CleanupScanner.allocatedSize(of: url), AppUninstaller.lastUsedDate(of: url))
    }

    nonisolated private static func findLeftovers(for app: InstalledApp) async -> [AppLeftover] {
        AppUninstaller.leftovers(for: app)
    }

    /// Asks the app to quit and waits up to ten seconds; the app may ask to save work first.
    private static func quitIfRunning(_ app: InstalledApp) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if running.allSatisfy(\.isTerminated) { return true }
        }
        return false
    }
}
