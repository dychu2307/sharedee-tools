import AppKit
import SwiftUI

final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppRuntime.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in AppRuntime.shared.showMainWindow() } }
        return true
    }
}

@main
struct SharedeCaptureApp: App {
    @NSApplicationDelegateAdaptor(CaptureAppDelegate.self) private var appDelegate
    @ObservedObject private var language = LanguageSettings.shared
    private let runtime = AppRuntime.shared

    init() {
        if ProcessInfo.processInfo.arguments.contains("--sharedee-permission-probe") {
            let report = "\(Bundle.main.bundleURL.path)\n\(CGPreflightScreenCaptureAccess())\n"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sharedee-screen-permission-probe.txt")
            try? report.write(to: url, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("Cài đặt…")) {
                    runtime.showSettings()
                }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
