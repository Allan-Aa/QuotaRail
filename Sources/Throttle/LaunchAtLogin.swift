import ServiceManagement

/// Wraps SMAppService so the app can register/unregister itself as a login
/// item without System Settings — requires the built .app (not the raw
/// debug binary) to have a stable bundle identifier, which it does.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Best-effort — surfaced to the user only via the Settings toggle
            // reflecting whatever the actual status ends up being.
        }
    }
}
