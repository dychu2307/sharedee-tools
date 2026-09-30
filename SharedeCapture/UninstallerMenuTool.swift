import AppKit

@MainActor
final class UninstallerMenuTool: MenuBarTool {
    private unowned let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    var title: String { L10n.tr("Gỡ ứng dụng") }
    var symbol: String { "xmark.bin" }

    func populate(_ menu: NSMenu) {
        menu.addItem(ActionMenuItem(L10n.tr("Chọn ứng dụng để gỡ…"), symbol: "square.grid.2x2") { [runtime] in
            runtime.showUninstaller()
        })
    }
}
