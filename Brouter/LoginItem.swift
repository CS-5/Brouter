import AppKit
import ServiceManagement

@MainActor
enum LoginItem {
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
}
