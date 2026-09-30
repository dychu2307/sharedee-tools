import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private unowned let runtime: AppRuntime
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(runtime: AppRuntime) {
        self.runtime = runtime
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let icon = NSImage(named: "MenuBarIcon")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Sharedee Tools"
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "Sharedee Tools"
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let state = runtime.state
        add(L10n.tr("Mở Sharedee Tools"), action: #selector(showMainWindow))
        menu.addItem(.separator())
        add(L10n.tr("Chụp vùng chọn"), action: #selector(captureArea), enabled: !state.isCapturing)
        add(L10n.tr("Chụp cửa sổ"), action: #selector(captureWindow), enabled: !state.isCapturing)
        add(L10n.tr("Chụp toàn màn hình"), action: #selector(captureFullScreen), enabled: !state.isCapturing)
        add(L10n.tr("Chụp cuộn"), action: #selector(captureScrolling), enabled: !state.isCapturing)
        add(L10n.tr("Chụp và sao chép chữ"), action: #selector(captureText), enabled: !state.isCapturing)
        menu.addItem(.separator())
        add(L10n.tr("Mở ảnh…"), action: #selector(openImage))
        add(L10n.tr("Chỉnh sửa ảnh gần nhất"), action: #selector(showEditor), enabled: state.image != nil)
        add(L10n.tr("Sao chép ảnh gần nhất"), action: #selector(copyImage), enabled: state.image != nil)
        if !state.recent.isEmpty {
            let recentMenu = NSMenu()
            for (index, capture) in state.recent.enumerated() {
                let time = DateFormatter.localizedString(from: capture.capturedAt,
                                                         dateStyle: .none, timeStyle: .short)
                let item = NSMenuItem(title: "\(capture.mode.title) · \(time)",
                                      action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                recentMenu.addItem(item)
            }
            let recentItem = NSMenuItem(title: L10n.tr("Ảnh vừa chụp"), action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }
        menu.addItem(.separator())
        add(L10n.tr("Cài đặt…"), action: #selector(showSettings))
        add(L10n.tr("Giới thiệu Sharedee Tools"), action: #selector(showAbout))
        let status = NSMenuItem(title: state.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        add(L10n.tr("Thoát Sharedee Tools"), action: #selector(quit))
    }

    private func add(_ title: String, action: Selector, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func captureArea() { Task { await runtime.state.capture(.area) } }
    @objc private func captureWindow() { Task { await runtime.state.capture(.window) } }
    @objc private func captureFullScreen() { Task { await runtime.state.capture(.fullScreen) } }
    @objc private func captureScrolling() { Task { await runtime.state.captureScrolling() } }
    @objc private func captureText() { Task { await runtime.state.captureText() } }
    @objc private func openImage() { runtime.openImage() }
    @objc private func showEditor() { runtime.showEditor() }
    @objc private func copyImage() { runtime.state.copyImage() }
    @objc private func showSettings() { runtime.showSettings() }
    @objc private func showMainWindow() { runtime.showMainWindow() }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openRecent(_ item: NSMenuItem) {
        let captures = runtime.state.recent
        guard captures.indices.contains(item.tag) else { return }
        runtime.openRecent(captures[item.tag])
    }
}
