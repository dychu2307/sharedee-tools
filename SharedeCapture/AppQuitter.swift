import AppKit

/// Lists the apps the user can quit and quits them the normal way, so each app still asks
/// to save unsaved work before it closes. Shared by the menu bar and the main window, so a
/// selection made in one shows up in the other.
@MainActor
final class AppQuitter: ObservableObject {
    /// Apps that are never quit: quitting Finder just relaunches it and empties the desktop.
    private static let protectedBundleIDs: Set<String> = ["com.apple.finder"]
    private static let excludedKey = "quitAppsExcludedBundleIDs"

    /// Regular (Dock) apps other than Sharedee Tools itself, sorted by name.
    @Published private(set) var apps: [NSRunningApplication] = []
    /// Apps picked for "quit selected", keyed by process ID.
    @Published private(set) var selection: Set<pid_t> = []
    /// Bundle IDs that "Quit All" always leaves running. They can still be quit one by one.
    @Published private(set) var excludedBundleIDs: Set<String>
    /// The app the user was last working in, other than Sharedee Tools.
    @Published private(set) var lastActiveApp: NSRunningApplication?
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        excludedBundleIDs = Set(defaults.stringArray(forKey: Self.excludedKey) ?? [])
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.noteActivated(app) }
        })
        noteActivated(NSWorkspace.shared.frontmostApplication)
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
        if let last = lastActiveApp, last.isTerminated { lastActiveApp = nil }
    }

    private func noteActivated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              !Self.protectedBundleIDs.contains(app.bundleIdentifier ?? "") else { return }
        lastActiveApp = app
    }

    // MARK: Selection

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

    // MARK: Exclusions

    func isExcluded(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier.map(excludedBundleIDs.contains) ?? false
    }

    func setExcluded(_ excluded: Bool, for app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        if excluded {
            excludedBundleIDs.insert(id)
        } else {
            excludedBundleIDs.remove(id)
        }
        defaults.set(excludedBundleIDs.sorted(), forKey: Self.excludedKey)
    }

    // MARK: Quitting

    /// What "Quit All" closes: every listed app except excluded ones and, optionally, one to keep.
    static func quitAllTargets(_ apps: [NSRunningApplication], excluded: Set<String>,
                               keeping kept: NSRunningApplication? = nil) -> [NSRunningApplication] {
        apps.filter { app in
            !excluded.contains(app.bundleIdentifier ?? "") && app.processIdentifier != kept?.processIdentifier
        }
    }

    func quitAllTargets(keeping kept: NSRunningApplication? = nil) -> [NSRunningApplication] {
        Self.quitAllTargets(apps, excluded: excludedBundleIDs, keeping: kept)
    }

    func quitAll(keeping kept: NSRunningApplication? = nil, force: Bool = false) {
        quit(quitAllTargets(keeping: kept), force: force)
    }

    func quitSelected(force: Bool = false) {
        let apps = selectedApps
        selection.removeAll()
        quit(apps, force: force)
    }

    /// A normal quit lets each app ask to save; force quit ends it at once, like ⌥⌘⎋.
    func quit(_ apps: [NSRunningApplication], force: Bool = false) {
        for app in apps {
            if force { app.forceTerminate() } else { app.terminate() }
        }
    }
}

/// Publishes whether ⌥ is held, so Quit buttons can turn into Force Quit while it is.
@MainActor
final class OptionKeyMonitor: ObservableObject {
    @Published private(set) var isDown = NSEvent.modifierFlags.contains(.option)
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        isDown = NSEvent.modifierFlags.contains(.option)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let down = event.modifierFlags.contains(.option)
            MainActor.assumeIsolated {
                if self?.isDown != down { self?.isDown = down }
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isDown = false
    }
}
