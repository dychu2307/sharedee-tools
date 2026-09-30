import AppKit

/// Lists the apps the user can quit and quits them the normal way, so each app still asks
/// to save unsaved work before it closes. Shared by the menu bar and the main window, so a
/// selection made in one shows up in the other.
@MainActor
final class AppQuitter: ObservableObject {
    /// Apps that are never quit: quitting Finder just relaunches it and empties the desktop.
    private static let protectedBundleIDs: Set<String> = ["com.apple.finder"]

    /// Regular (Dock) apps other than Sharedee Tools itself, sorted by name.
    @Published private(set) var apps: [NSRunningApplication] = []
    /// Apps picked for "quit selected", keyed by process ID.
    @Published private(set) var selection: Set<pid_t> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.processIdentifier != ownPID
                    && !app.isTerminated
                    && !Self.protectedBundleIDs.contains(app.bundleIdentifier ?? "")
            }
            .sorted {
                ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending
            }
        // Drop selections for apps that have quit.
        let running = Set(apps.map(\.processIdentifier))
        if !selection.isSubset(of: running) { selection.formIntersection(running) }
    }

    var selectedApps: [NSRunningApplication] { apps.filter(isSelected) }

    func isSelected(_ app: NSRunningApplication) -> Bool {
        selection.contains(app.processIdentifier)
    }

    func setSelected(_ selected: Bool, for app: NSRunningApplication) {
        if selected {
            selection.insert(app.processIdentifier)
        } else {
            selection.remove(app.processIdentifier)
        }
    }

    func setAllSelected(_ selected: Bool) {
        selection = selected ? Set(apps.map(\.processIdentifier)) : []
    }

    func quitAll() {
        quit(apps)
    }

    func quitSelected() {
        let apps = selectedApps
        selection.removeAll()
        quit(apps)
    }

    func quit(_ apps: [NSRunningApplication]) {
        for app in apps { app.terminate() }
    }
}
