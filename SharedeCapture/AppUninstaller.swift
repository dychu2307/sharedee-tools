import AppKit

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    var size: Int64?
    var lastUsed: Date?
    var id: URL { url }
}

/// A file an app left behind in the user's Library.
struct AppLeftover: Identifiable, Hashable {
    let url: URL
    let size: Int64
    /// True when only the folder name matched the app's name, not its bundle ID. Those could
    /// belong to another app with the same name, so they are never selected by default.
    let matchedByName: Bool
    var id: URL { url }
    var location: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

/// Finds installed apps and the files they leave in ~/Library. Kept free of UI and of the
/// real home folder so tests can run it against a throwaway one.
enum AppUninstaller {
    private enum Match {
        /// A file or folder named exactly after the bundle ID.
        case bundleID
        /// The bundle ID followed by a suffix, e.g. `.plist`, `.savedState`, or `.helper` for a helper app.
        case bundleIDPrefixed(suffix: String?)
        /// A group container: `<TEAMID>.<bundleID>` or `group.<bundleID>…`.
        case groupContainer
        /// A folder named after the app. Weaker evidence, so it is flagged.
        case appName
    }

    private static let locations: [(path: String, matches: [Match])] = [
        ("Library/Application Support", [.bundleID, .appName]),
        ("Library/Caches", [.bundleID, .appName]),
        ("Library/Logs", [.bundleID, .appName]),
        ("Library/Preferences", [.bundleIDPrefixed(suffix: ".plist")]),
        ("Library/Preferences/ByHost", [.bundleIDPrefixed(suffix: ".plist")]),
        ("Library/Containers", [.bundleID, .bundleIDPrefixed(suffix: nil)]),
        ("Library/Group Containers", [.groupContainer]),
        ("Library/Application Scripts", [.bundleID, .bundleIDPrefixed(suffix: nil)]),
        ("Library/Saved Application State", [.bundleIDPrefixed(suffix: ".savedState")]),
        ("Library/HTTPStorages", [.bundleID, .bundleIDPrefixed(suffix: ".binarycookies")]),
        ("Library/WebKit", [.bundleID]),
        ("Library/Cookies", [.bundleIDPrefixed(suffix: ".binarycookies")]),
        ("Library/LaunchAgents", [.bundleIDPrefixed(suffix: ".plist")]),
    ]

    // MARK: Installed apps

    static func installedApps(in folders: [URL] = defaultAppFolders) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen: Set<String> = []
        for folder in folders {
            for url in appBundles(in: folder) {
                guard let app = installedApp(at: url), seen.insert(app.bundleID).inserted else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var defaultAppFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    static func installedApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
              canUninstall(bundleID: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return InstalledApp(url: url, name: name, bundleID: bundleID, version: version)
    }

    /// macOS apps and Sharedee Tools itself are never offered.
    static func canUninstall(bundleID: String) -> Bool {
        bundleID.contains(".") && !bundleID.hasPrefix("com.apple.") && !bundleID.hasPrefix("com.sharedecapture.")
    }

    /// `.app` bundles in a folder and one level of subfolders (e.g. /Applications/Adobe X/X.app).
    private static func appBundles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var bundles: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                bundles.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let nested = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) {
                bundles += nested.filter { $0.pathExtension == "app" }
            }
        }
        return bundles
    }

    static func lastUsedDate(of url: URL) -> Date? {
        NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
    }

    // MARK: Leftovers

    static func leftovers(for app: InstalledApp,
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AppLeftover] {
        guard canUninstall(bundleID: app.bundleID) else { return [] }
        let fm = FileManager.default
        let bundleID = app.bundleID.lowercased()
        // Very short or generic names ("Go", "Notes") are too likely to hit another app's folder.
        let appName = app.name.count >= 4 ? app.name.lowercased() : nil
        var found: [AppLeftover] = []
        for location in locations {
            let folder = home.appendingPathComponent(location.path, isDirectory: true)
            guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }
            for child in children {
                let name = child.lastPathComponent.lowercased()
                var byBundleID = false
                var byName = false
                for match in location.matches {
                    switch match {
                    case .bundleID:
                        byBundleID = byBundleID || name == bundleID
                    case .bundleIDPrefixed(let suffix):
                        if let suffix = suffix?.lowercased() {
                            byBundleID = byBundleID || name == bundleID + suffix
                                || (name.hasPrefix(bundleID + ".") && name.hasSuffix(suffix))
                        } else {
                            byBundleID = byBundleID || name.hasPrefix(bundleID + ".")
                        }
                    case .groupContainer:
                        byBundleID = byBundleID || name.hasSuffix("." + bundleID)
                            || name == "group." + bundleID || name.hasPrefix("group." + bundleID + ".")
                    case .appName:
                        byName = byName || (appName != nil && name == appName)
                    }
                }
                guard byBundleID || byName else { continue }
                found.append(AppLeftover(url: child, size: CleanupScanner.allocatedSize(of: child),
                                         matchedByName: !byBundleID))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}
