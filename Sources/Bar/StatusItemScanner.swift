import AppKit
import ApplicationServices

/// Finds other apps' menu bar icons through the Accessibility API.
///
/// Each app exposes its status items under `AXExtrasMenuBar`. On macOS 27 they
/// carry no useful title, so all we learn is the owning app and the position.
/// Requires the Accessibility permission and an unsandboxed app.
enum StatusItemScanner {
    struct Icon {
        let bundleID: String
        /// Global coordinates with a top-left origin (x matches AppKit's).
        let frame: CGRect
        var midX: CGFloat { frame.midX }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Apps whose icons are macOS's own controls (clock, Wi-Fi, Control Center…).
    /// They can't be hidden per app, so hidnr leaves them alone.
    static func isSystemOwned(_ bundleID: String) -> Bool {
        ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent"].contains(bundleID)
    }

    /// Shows the system "allow Accessibility" prompt.
    static func askForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Scans off the main thread (it messages every running app) and delivers
    /// the result on the main queue. hidnr's own icon is included, so callers
    /// can compare positions in one coordinate space (with several displays,
    /// AppKit window frames and Accessibility positions can disagree).
    static func scan(_ completion: @escaping ([Icon]) -> Void) {
        // Only real app bundles own status items; skipping helpers and XPC
        // services makes the scan several times faster.
        let apps: [(pid_t, String)] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleURL?.pathExtension == "app",
                  let id = app.bundleIdentifier else { return nil }
            return (app.processIdentifier, id)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let icons = apps.flatMap { icons(pid: $0.0, bundleID: $0.1) }
            DispatchQueue.main.async { completion(icons) }
        }
    }

    private static func icons(pid: pid_t, bundleID: String) -> [Icon] {
        let app = AXUIElementCreateApplication(pid)
        // A frozen app would otherwise stall the scan for seconds.
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar: AXUIElement = attribute(app, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
        return children.compactMap { child in
            guard let posValue: AXValue = attribute(child, kAXPositionAttribute),
                  let sizeValue: AXValue = attribute(child, kAXSizeAttribute) else { return nil }
            var pos = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            // Accessibility uses a top-left origin; x is the same as AppKit's.
            return Icon(bundleID: bundleID, frame: CGRect(origin: pos, size: size))
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
