import AppKit

/// Which kind of Space each display is showing, through the private window
/// server call macOS uses for Mission Control. Looked up at runtime; if it's
/// missing, every display counts as a normal desktop.
enum Spaces {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let connection: ConnectionFn? = symbol("CGSMainConnectionID")
    private static let copySpaces: CopySpacesFn? = symbol("CGSCopyManagedDisplaySpaces")

    private static func symbol<T>(_ name: String) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }  // RTLD_DEFAULT
        return unsafeBitCast(pointer, to: T.self)
    }

    /// True when `screen` is showing a full-screen app (or Split View) right now.
    /// Its menu bar is hidden then, so nothing of hidnr's should float there.
    static func isFullScreen(_ screen: NSScreen) -> Bool {
        guard let connection, let copySpaces,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]],
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return false }
        let uuid = CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(number).takeRetainedValue()) as String
        // With "Displays have separate Spaces" off, all displays share "Main".
        let display = displays.first { ($0["Display Identifier"] as? String) == uuid }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
        let current = display?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == 4   // 0 = desktop, 4 = full screen
    }
}
