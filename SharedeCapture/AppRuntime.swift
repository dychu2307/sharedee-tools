import AppKit
import SwiftUI

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let state = CaptureState()
    let shortcuts = ShortcutSettings()
    private let quickAccess = QuickAccessController()
    private var statusMenu: StatusMenuController?
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var editorWasVisibleBeforeCapture = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        NSApp.setActivationPolicy(.accessory)
        statusMenu = StatusMenuController(runtime: self)
        state.preferences = shortcuts
        state.willCapture = { [weak self] in self?.prepareForCapture() }
        state.didCapture = { [weak self] in self?.showQuickAccess() }
        state.captureFailed = { [weak self] in self?.restoreEditorIfNeeded() }
        shortcuts.activate { [weak self] action in
            guard let self else { return }
            Task { await self.state.perform(action) }
        }
    }

    func showEditor() {
        guard state.image != nil else { return }
        quickAccess.dismiss()
        if editorWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1120, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Sharedee Tools"
            window.minSize = CGSize(width: 980, height: 650)
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView:
                ContentView()
                    .environmentObject(state)
                    .environmentObject(shortcuts)
                    .frame(minWidth: 980, minHeight: 650)
                    .preferredColorScheme(.dark)
            )
            editorWindow = window
        }
        editorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 614, height: 464),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Cài đặt Sharedee Tools"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView:
                SettingsView()
                    .environmentObject(shortcuts)
                    .preferredColorScheme(.dark)
            )
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        if state.openImage() { showEditor() }
    }

    func openRecent(_ capture: RecentCapture) {
        if state.openRecent(capture) { showEditor() }
    }

    func dismissQuickAccess() {
        quickAccess.dismiss()
    }

    private func prepareForCapture() {
        editorWasVisibleBeforeCapture = editorWindow?.isVisible ?? false
        editorWindow?.orderOut(nil)
        quickAccess.dismiss()
    }

    private func restoreEditorIfNeeded() {
        if editorWasVisibleBeforeCapture { showEditor() }
        editorWasVisibleBeforeCapture = false
    }

    private func showQuickAccess() {
        editorWasVisibleBeforeCapture = false
        guard let image = state.image else { return }
        quickAccess.show(image: image,
                         onCopy: { [weak self] in
                             self?.state.copyImage()
                             self?.quickAccess.dismiss()
                         },
                         onEdit: { [weak self] in self?.showEditor() },
                         onSave: { [weak self] in
                             guard let self else { return }
                             NSApp.activate(ignoringOtherApps: true)
                             guard self.state.saveImage() else { return }
                             self.quickAccess.dismiss()
                         },
                         onDismiss: { [weak self] in self?.quickAccess.dismiss() })
    }
}
