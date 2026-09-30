import Foundation

/// Version and project details read from Info.plist (set in project.yml).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    static var versionDescription: String {
        L10n.format("Phiên bản %@ (%@)", version, build)
    }

    static var repositoryURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SharedeeRepositoryURL") as? String).flatMap(URL.init(string:))
    }

    static var licenseURL: URL? {
        repositoryURL?.appendingPathComponent("blob/main/LICENSE")
    }

    static var issuesURL: URL? {
        repositoryURL?.appendingPathComponent("issues")
    }
}
