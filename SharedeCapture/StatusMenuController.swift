import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private unowned let runtime: AppRuntime
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let tools: [MenuBarTool]
    /// Each tool's submenu, so `menuNeedsUpdate` knows which tool to ask for items.
    private var toolMenus: [ObjectIdentifier: MenuBarTool] = [:]

    init(runtime: AppRuntime) {
        self.runtime = runtime
        tools = [
            CaptureMenuTool(runtime: runtime),
            QuitAppsMenuTool(quitter: runtime.quitter),
            CleanupMenuTool(runtime: runtime),
            UninstallerMenuTool(runtime: runtime),
        ]
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
        if menu === self.menu {
            rebuildMenu()
        } else if let tool = toolMenus[ObjectIdentifier(menu)] {
            menu.removeAllItems()
            tool.populate(menu)
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        toolMenus.removeAll()
        for tool in tools {
            let submenu = NSMenu(title: tool.title)
            submenu.autoenablesItems = false
            submenu.delegate = self
            toolMenus[ObjectIdentifier(submenu)] = tool
            let item = NSMenuItem(title: tool.title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L10n.tr("Mở Sharedee Tools")) { [runtime] in runtime.showMainWindow() })
        menu.addItem(ActionMenuItem(L10n.tr("Cài đặt…")) { [runtime] in runtime.showSettings() })
        menu.addItem(ActionMenuItem(L10n.tr("Giới thiệu Sharedee Tools")) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addDisabledItem(runtime.state.status)
        menu.addItem(ActionMenuItem(L10n.tr("Thoát Sharedee Tools")) { NSApp.terminate(nil) })
    }
}
