import Foundation
import ServiceManagement

/// hidnr's stored preferences. The SwiftUI settings view binds to the same keys
/// with `@AppStorage`; `BarController` reacts through `UserDefaults.didChangeNotification`.
enum Settings {
    enum Key {
        static let hideOnLaunch = "hideOnLaunch"
        static let autoHide = "autoHide"
        static let autoHideDelay = "autoHideDelay"
    }

    private static var store: UserDefaults { .standard }

    static func registerDefaults() {
        store.register(defaults: [
            Key.hideOnLaunch: true,
            Key.autoHide: true,
            Key.autoHideDelay: 10.0,
        ])
    }

    static var hideOnLaunch: Bool {
        get { store.bool(forKey: Key.hideOnLaunch) }
        set { store.set(newValue, forKey: Key.hideOnLaunch) }
    }

    static var autoHide: Bool {
        get { store.bool(forKey: Key.autoHide) }
        set { store.set(newValue, forKey: Key.autoHide) }
    }

    static var autoHideDelay: TimeInterval {
        get { max(2, store.double(forKey: Key.autoHideDelay)) }
        set { store.set(newValue, forKey: Key.autoHideDelay) }
    }
}

/// Start hidnr when the user logs in, via the macOS 13+ login item API.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("hidnr: couldn't change the login item: \(error.localizedDescription)")
        }
    }
}
