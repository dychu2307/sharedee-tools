import AppKit
import SwiftUI

final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppRuntime.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SharedeCaptureApp: App {
    @NSApplicationDelegateAdaptor(CaptureAppDelegate.self) private var appDelegate
    private let runtime = AppRuntime.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(runtime.shortcuts)
                .preferredColorScheme(.dark)
        }
    }
}
