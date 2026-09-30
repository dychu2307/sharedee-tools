import AppKit

@MainActor
final class CleanupMenuTool: MenuBarTool {
    private unowned let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    var title: String { L10n.tr("Dọn dẹp") }
    var symbol: String { "sparkles" }

    func populate(_ menu: NSMenu) {
        let cleanup = runtime.cleanup
        switch cleanup.phase {
        case .scanning:
            menu.addDisabledItem(L10n.format("Đang quét… %@", ByteCountText.format(cleanup.found)))
        case .cleaning:
            menu.addDisabledItem(L10n.format("Đang dọn… %@", ByteCountText.format(cleanup.freed)))
        case .results:
            menu.addDisabledItem(L10n.format("Có thể dọn %@", ByteCountText.format(cleanup.totalSize)))
        case .done:
            menu.addDisabledItem(L10n.format("Đã giải phóng %@", ByteCountText.format(cleanup.freed)))
        case .idle:
            break
        }
        menu.addItem(ActionMenuItem(L10n.tr("Quét rác ngay"), symbol: "magnifyingglass",
                                    enabled: !cleanup.isBusy) { [runtime] in
            runtime.showCleanup(scan: true)
        })
        menu.addItem(ActionMenuItem(L10n.tr("Mở Dọn dẹp…"), symbol: "sparkles") { [runtime] in
            runtime.showCleanup(scan: false)
        })
    }
}
