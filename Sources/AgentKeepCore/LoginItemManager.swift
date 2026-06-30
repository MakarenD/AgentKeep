import AppKit
import Foundation
import ServiceManagement

struct LoginItemManager {
    enum State {
        case enabled
        case notRegistered
        case requiresApproval
        case notFound
        case unknown
    }

    private let preferenceKey = "LaunchAtLoginPreferred"
    private let loginItemsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")

    var isLaunchAtLoginPreferred: Bool {
        if UserDefaults.standard.object(forKey: preferenceKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: preferenceKey)
    }

    func registerIfPreferred() throws {
        guard isLaunchAtLoginPreferred else {
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval, .notFound:
            return
        default:
            try SMAppService.mainApp.register()
        }
    }

    func setLaunchAtLoginPreferred(_ isEnabled: Bool) throws {
        UserDefaults.standard.set(isEnabled, forKey: preferenceKey)

        if isEnabled {
            try registerIfPreferred()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    func currentState() -> State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    func openLoginItemsSettings() {
        guard let loginItemsSettingsURL else {
            return
        }

        NSWorkspace.shared.open(loginItemsSettingsURL)
    }
}
