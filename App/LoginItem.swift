import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+, App Store friendly).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem: failed to \(on ? "register" : "unregister"): \(error)")
        }
    }

    /// Register once on first run; after that the user's choice wins.
    static func setupOnFirstRun() {
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
