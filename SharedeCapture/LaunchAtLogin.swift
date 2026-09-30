import Foundation
import ServiceManagement

/// Registers the app as a login item. The state lives in macOS (System Settings → Login Items),
/// so it is re-read instead of being stored in UserDefaults.
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    private init() {
        refresh()
    }

    func refresh() {
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = L10n.format("Không thể cập nhật mục đăng nhập: %@", error.localizedDescription)
        }
        refresh()
    }

    func openLoginItemsSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
