import AppKit

@MainActor
final class CaptureMenuTool: MenuBarTool {
    private unowned let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    var title: String { L10n.tr("Chụp màn hình") }
    var symbol: String { "camera.viewfinder" }

    func populate(_ menu: NSMenu) {
        let state = runtime.state
        let idle = !state.isCapturing
        menu.addItem(ActionMenuItem(L10n.tr("Chụp vùng chọn"), enabled: idle) { [runtime] in
            Task { await runtime.state.capture(.area) }
        })
        menu.addItem(ActionMenuItem(L10n.tr("Chụp cửa sổ"), enabled: idle) { [runtime] in
            Task { await runtime.state.capture(.window) }
        })
        menu.addItem(ActionMenuItem(L10n.tr("Chụp toàn màn hình"), enabled: idle) { [runtime] in
            Task { await runtime.state.capture(.fullScreen) }
        })
        menu.addItem(ActionMenuItem(L10n.tr("Chụp cuộn"), enabled: idle) { [runtime] in
            Task { await runtime.state.captureScrolling() }
        })
        menu.addItem(ActionMenuItem(L10n.tr("Chụp và sao chép chữ"), enabled: idle) { [runtime] in
            Task { await runtime.state.captureText() }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L10n.tr("Mở ảnh…")) { [runtime] in runtime.openImage() })
        menu.addItem(ActionMenuItem(L10n.tr("Chỉnh sửa ảnh gần nhất"), enabled: state.image != nil) { [runtime] in
            runtime.showEditor()
        })
        menu.addItem(ActionMenuItem(L10n.tr("Sao chép ảnh gần nhất"), enabled: state.image != nil) { [runtime] in
            runtime.state.copyImage()
        })
        if !state.recent.isEmpty {
            let recentMenu = NSMenu()
            for capture in state.recent {
                let time = DateFormatter.localizedString(from: capture.capturedAt,
                                                         dateStyle: .none, timeStyle: .short)
                recentMenu.addItem(ActionMenuItem("\(capture.mode.title) · \(time)") { [runtime] in
                    runtime.openRecent(capture)
                })
            }
            let recentItem = NSMenuItem(title: L10n.tr("Ảnh vừa chụp"), action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }
    }
}
