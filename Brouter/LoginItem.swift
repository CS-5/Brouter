import AppKit
import os
import ServiceManagement

private let log = Logger(subsystem: "com.carsonseese.Brouter", category: "login")

@MainActor
enum LoginItem {
    private static let enabledByDefaultKey = "LoginItemEnabledByDefault"

    /// Read fresh each time, since the user can change it in System Settings at any point.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Enables or disables launch at login. When macOS needs the user's approval first, opens the Login Items
    /// settings instead.
    static func toggle() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            NSAlert.show("Couldn't change Launch at Login", error.localizedDescription)
        }
    }

    /// Turns launch at login on the first time Brouter runs from `/Applications`, where macOS can register it.
    /// Done only once, so unchecking the menu item sticks. Fails quietly: the menu item still shows the state.
    static func enableByDefault() {
        let defaults = UserDefaults.standard
        let inApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        guard inApplications, !defaults.bool(forKey: enabledByDefaultKey) else { return }
        defaults.set(true, forKey: enabledByDefaultKey)
        guard SMAppService.mainApp.status == .notRegistered else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            log.error("Couldn't enable launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
