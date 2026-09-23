import Foundation

/// Which apps the user wants hidden, chosen on the Icons page of Settings.
///
/// Stored by bundle identifier because macOS 27 hides per app. Apps that aren't
/// listed stay visible, so a newly installed app never disappears on its own.
enum IconLayout {
    static let didChange = Notification.Name("hidnr.iconLayoutDidChange")
    private static let key = "hiddenApps"

    /// False until the user (or the first hide) has decided anything.
    static var isConfigured: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static var hiddenApps: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set {
            UserDefaults.standard.set(newValue.sorted(), forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func isHidden(_ bundleID: String) -> Bool {
        hiddenApps.contains(bundleID)
    }

    static func setHidden(_ bundleID: String, _ hidden: Bool) {
        var apps = hiddenApps
        if hidden { apps.insert(bundleID) } else { apps.remove(bundleID) }
        hiddenApps = apps
    }
}
