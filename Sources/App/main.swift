import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bar: BarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        bar = BarController()
    }

    /// Opening hidnr again (from Finder or Spotlight) is the escape hatch: it
    /// brings every hidden icon back and opens settings, since the app has no
    /// Dock icon or main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bar?.showEverything()
        SettingsWindow.show(.icons)
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
