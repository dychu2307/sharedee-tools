import AppKit

/// One tool in the menu bar dropdown. Each tool gets its own top-level entry with a submenu,
/// so adding a feature means adding a tool rather than growing one long flat menu.
@MainActor
protocol MenuBarTool: AnyObject {
    var title: String { get }
    var symbol: String { get }
    /// Fills the tool's submenu. Called every time the submenu opens, so it can show live state.
    func populate(_ menu: NSMenu)
}

/// A menu item that runs a closure, so tools don't need an `@objc` method per action.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, enabled: Bool = true,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() { handler() }
}

extension NSMenu {
    func addDisabledItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
