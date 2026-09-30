import AppKit
import SwiftUI

private final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let state = CaptureState()
    let shortcuts = ShortcutSettings()
    let drive = GoogleDriveService()
    let navigation = MainNavigation()
    let quitter = AppQuitter()
    let cleanup = CleanupModel()
    private let quickAccess = QuickAccessController()
    private let toast = ToastController()
    private var statusMenu: StatusMenuController?
    private var mainWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var mainCloseObserver: NSObjectProtocol?
    private var editorWasVisibleBeforeCapture = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        NSApp.setActivationPolicy(.accessory)
        statusMenu = StatusMenuController(runtime: self)
        state.preferences = shortcuts
        state.driveService = drive
        state.willCapture = { [weak self] in self?.prepareForCapture() }
        state.didCapture = { [weak self] in self?.showQuickAccess() }
        state.uploadHandler = { [weak self] capture in self?.uploadFromThumbnail(capture) }
        state.captureFailed = { [weak self] in self?.restoreEditorIfNeeded() }
        state.textCaptureFinished = { [weak self] result in
            self?.restoreEditorIfNeeded()
            self?.showToast(for: result)
        }
        shortcuts.activate { [weak self] action in
            guard let self else { return }
            Task { await self.state.perform(action) }
        }
        showMainWindow()
    }

    func showMainWindow() {
        if mainWindow == nil {
            let visible = NSScreen.main?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let size = CGSize(width: min(940, visible.width - 60),
                              height: min(620, visible.height - 60))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Sharedee Tools"
            window.isReleasedWhenClosed = false
            window.minSize = CGSize(width: min(700, size.width), height: min(460, size.height))
            window.center()
            window.contentView = NSHostingView(rootView:
                ContentView()
                    .environmentObject(state)
                    .environmentObject(shortcuts)
                    .environmentObject(drive)
                    .environmentObject(navigation)
                    .environmentObject(quitter)
                    .environmentObject(cleanup)
                    .preferredColorScheme(.dark)
            )
            mainCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateActivationPolicy(closing: window)
                }
            }
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showEditor() {
        guard let image = state.image else { return }
        if editorWindow == nil {
            let window = EditorPanel(contentRect: .zero,
                                  styleMask: [.borderless, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Sharedee Tools"
            window.minSize = CGSize(width: 560, height: 300)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView:
                CompactEditorView { [weak self] in self?.closeEditor() }
                    .environmentObject(state)
                    .environmentObject(drive)
                    .frame(minWidth: 560, minHeight: 300)
                    .preferredColorScheme(.dark)
            )
            editorWindow = window
        }
        editorWindow?.setContentSize(editorSize(for: image))
        editorWindow?.center()
        NSApp.setActivationPolicy(.regular)
        editorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func editorSize(for image: NSImage) -> CGSize {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let chromeHeight: CGFloat = 148
        let maxWidth = max(560, min(1400, visible.width - 72))
        let maxCanvasHeight = max(180, min(1000, visible.height - 72) - chromeHeight)
        let imageWidth = max(1, image.size.width)
        let imageHeight = max(1, image.size.height)
        let scale = min(1, maxWidth / imageWidth, maxCanvasHeight / imageHeight)
        return CGSize(width: max(560, imageWidth * scale),
                      height: max(180, imageHeight * scale) + chromeHeight)
    }

    func closeEditor() {
        editorWindow?.orderOut(nil)
        updateActivationPolicy()
    }

    func showCleanup(scan: Bool) {
        navigation.page = .cleanup
        showMainWindow()
        if scan { cleanup.scan() }
    }

    func showSettings() {
        navigation.page = .settings(.general)
        showMainWindow()
    }

    private func updateActivationPolicy(closing: NSWindow? = nil) {
        let windows = [mainWindow, editorWindow].compactMap { $0 }
        let hasOpenWindow = windows.contains { window in
            if let closing, window === closing { return false }
            return window.isVisible
        }
        let policy: NSApplication.ActivationPolicy = hasOpenWindow ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        if state.openImage() { showEditor() }
    }

    func openRecent(_ capture: RecentCapture) {
        if state.openRecent(capture) { showEditor() }
    }

    func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-a", Bundle.main.bundleURL.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            state.status = L10n.format("Không thể khởi động lại: %@", error.localizedDescription)
        }
    }

    func showToast(for result: TextCaptureResult) {
        switch result {
        case .copied(let lines):
            let preview = lines.joined(separator: " ")
            toast.show(lines.count == 1 ? L10n.tr("Đã sao chép 1 dòng chữ")
                                        : L10n.format("Đã sao chép %ld dòng chữ", lines.count),
                       detail: preview.count > 140 ? String(preview.prefix(140)) + "…" : preview)
        case .noText:
            toast.show(L10n.tr("Không tìm thấy chữ trong vùng đã chọn"), style: .warning)
        case .failed(let message):
            toast.show(L10n.tr("Không nhận dạng được chữ"), detail: message, style: .warning, duration: 3.5)
        case .cancelled:
            break
        }
    }

    private func prepareForCapture() {
        editorWasVisibleBeforeCapture = editorWindow?.isVisible ?? false
        editorWindow?.orderOut(nil)
        updateActivationPolicy()
        quickAccess.hideAll()
    }

    private func restoreEditorIfNeeded() {
        if editorWasVisibleBeforeCapture { showEditor() }
        quickAccess.restoreAll()
        editorWasVisibleBeforeCapture = false
    }

    /// Uploads a capture once, reporting progress on its thumbnail. Repeated clicks while an
    /// upload runs are ignored; after success the button opens the uploaded file instead.
    private func uploadFromThumbnail(_ capture: RecentCapture) {
        switch quickAccess.uploadState(for: capture.id) {
        case .uploading:
            return
        case .uploaded(let url):
            NSWorkspace.shared.open(url)
            return
        case .idle, .failed:
            break
        }
        quickAccess.setUploadState(.uploading, for: capture.id)
        Task { [weak self] in
            guard let self else { return }
            if let url = await self.state.uploadImageToDrive(capture) {
                self.quickAccess.setUploadState(.uploaded(url), for: capture.id)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .uploaded = self.quickAccess.uploadState(for: capture.id) {
                    self.quickAccess.dismiss(capture.id)
                }
            } else {
                self.quickAccess.setUploadState(.failed(self.state.status), for: capture.id)
            }
        }
    }

    private func showQuickAccess() {
        editorWasVisibleBeforeCapture = false
        guard let image = state.image, let capture = state.recent.first else { return }
        quickAccess.show(id: capture.id, image: image, status: state.status,
                         onCopy: { [weak self] in
                             guard self?.state.copyImage(capture) == true else { return }
                             self?.quickAccess.dismiss(capture.id)
                         },
                         onEdit: { [weak self] in
                             guard let self, self.state.openRecent(capture) else { return }
                             self.quickAccess.dismiss(capture.id)
                             self.showEditor()
                         },
                         onSave: { [weak self] in
                             guard let self else { return }
                             NSApp.activate(ignoringOtherApps: true)
                             guard self.state.saveImage(capture) else { return }
                             self.quickAccess.dismiss(capture.id)
                         },
                         onUpload: drive.isConnected ? { [weak self] in
                             self?.uploadFromThumbnail(capture)
                         } : nil,
                         onDismiss: { [weak self] in self?.quickAccess.dismiss(capture.id) })
    }
}
