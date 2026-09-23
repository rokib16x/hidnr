import AppKit

/// A copy of the hidnr "h" drawn in a tiny floating window on top of the menu
/// bar, used while icons are hidden on macOS 27.
///
/// macOS 27's allow-list doesn't keep hidnr's own status item visible when hidnr
/// is signed ad hoc (it does keep apps signed by a registered developer), so
/// without this the user would have nothing to click to get their icons back.
/// One window per display, since the menu bar repeats on each.
final class StandInGlyph {
    /// Called on click; `true` for a right-click or control-click.
    var onClick: (_ secondary: Bool, _ anchor: NSView) -> Void = { _, _ in }

    /// One panel per display, keyed by the display's id.
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var timer: Timer?
    private var image = NSImage()
    private var width: CGFloat = 30
    private var appearance: NSAppearance?
    /// Apps whose icons are hidden; their parked windows must be ignored.
    private var hiddenApps: Set<String> = []

    var isShown: Bool { timer != nil }

    /// Shows the glyph and keeps it snug against the visible icons, re-checking
    /// every second: icons come and go (AirPods connecting, an app launching)
    /// while hidnr is hiding, and the stand-in must move with them.
    func start(image: NSImage, width: CGFloat, appearance: NSAppearance?, hiddenApps: Set<String>) {
        self.image = image
        self.width = width
        self.appearance = appearance
        self.hiddenApps = hiddenApps
        rightInset = nil
        appsWithIcons = []
        ticks = 0
        reposition()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reposition() }
    }

    func update(hiddenApps: Set<String>) {
        self.hiddenApps = hiddenApps
        fullScansOwed = 4
        if timer != nil { reposition() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    /// The anchor for popovers: the stand-in on the screen under the pointer.
    var anchorUnderPointer: NSView? {
        let point = NSEvent.mouseLocation
        let panel = panels.values.first { $0.screen?.frame.contains(point) ?? false } ?? panels.values.first
        return panel?.contentView
    }

    // MARK: Placement

    /// Distance from the screen's right edge to the leftmost visible icon.
    /// The bar is right-aligned and shows the same icons on every display, so
    /// one inset positions the stand-in everywhere.
    private var rightInset: CGFloat?
    /// Apps seen with an icon on the last full scan; the frequent checks only
    /// ask these (plus macOS's own items), which keeps them cheap.
    private var appsWithIcons: Set<String> = []
    private var ticks = 0
    private var isScanning = false
    /// Full scans still owed after something changed (an app launched), since a
    /// new app's icon can take a moment to show up.
    private var fullScansOwed = 0

    func reposition() {
        placePanels()
        guard StatusItemScanner.isTrusted, !isScanning else { return }
        ticks += 1
        let full = appsWithIcons.isEmpty || ticks % 10 == 0 || fullScansOwed > 0
        if fullScansOwed > 0 { fullScansOwed -= 1 }
        let visibleApps = appsWithIcons.subtracting(hiddenApps).union(StatusItemScanner.systemOwners)
        isScanning = true
        StatusItemScanner.scan(only: full ? nil : visibleApps) { [weak self] icons in
            guard let self else { return }
            self.isScanning = false
            if full { self.appsWithIcons = Set(icons.map(\.bundleID)) }
            self.measure(icons)
            self.placePanels()
        }
    }

    private func measure(_ icons: [StatusItemScanner.Icon]) {
        let me = Bundle.main.bundleIdentifier
        let visible = icons.filter { $0.bundleID != me && !hiddenApps.contains($0.bundleID) && $0.frame.width > 0 }
        // Accessibility uses a top-left origin on the primary display. Anchor on
        // the rightmost icon (the clock) to find which display these are on.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let rightmost = visible.max(by: { $0.frame.maxX < $1.frame.maxX }) else { return }
        let anchor = NSPoint(x: rightmost.frame.midX, y: primaryTop - rightmost.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) else { return }
        let sameRow = visible.filter { abs($0.frame.midY - rightmost.frame.midY) < 8 }
        guard let left = sameRow.map(\.frame.minX).min() else { return }
        rightInset = screen.frame.maxX - left
    }

    private func placePanels() {
        guard let rightInset else { return }
        var seen = Set<CGDirectDisplayID>()
        for bar in MenuBarWindows.bars() {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: bar.midX, y: bar.midY)) }),
                  let id = screen.displayID else { continue }
            var x = bar.maxX - rightInset - width
            if let notch = screen.notchRange, x + width > notch.lowerBound, x < notch.upperBound {
                x = notch.lowerBound - width
            }
            let frame = NSRect(x: x, y: bar.minY, width: width, height: bar.height).integral
            seen.insert(id)
            if let panel = panels[id] {
                if panel.frame != frame { panel.setFrame(frame, display: true) }
            } else {
                panels[id] = makePanel(frame: frame)
            }
        }
        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = appearance
        let view = GlyphView(frame: NSRect(origin: .zero, size: frame.size), image: image)
        view.autoresizingMask = [.width, .height]
        view.onClick = { [weak self, weak view] secondary in
            guard let self, let view else { return }
            self.onClick(secondary, view)
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }

    private final class GlyphView: NSView {
        var onClick: (Bool) -> Void = { _ in }
        private let image: NSImage
        private var isPressed = false { didSet { needsDisplay = true } }

        init(frame: NSRect, image: NSImage) {
            self.image = image
            super.init(frame: frame)
            setAccessibilityRole(.button)
            setAccessibilityLabel("hidnr, icons hidden")
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func draw(_ dirtyRect: NSRect) {
            if isPressed {
                NSColor.labelColor.withAlphaComponent(0.15).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 5, yRadius: 5).fill()
            }
            let size = image.size
            let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height).integral
            // Tint the template glyph with the menu bar's text color.
            let tinted = NSImage(size: size, flipped: false) { [image] r in
                image.draw(in: r)
                NSColor.labelColor.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }

        override func mouseDown(with event: NSEvent) { isPressed = true }

        override func mouseUp(with event: NSEvent) {
            isPressed = false
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick(event.modifierFlags.contains(.control))
        }

        override func rightMouseDown(with event: NSEvent) { isPressed = true }

        override func rightMouseUp(with event: NSEvent) {
            isPressed = false
            onClick(true)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Reads the menu bar strips from the window server: one window per display,
/// so this also says which displays show a menu bar right now.
enum MenuBarWindows {
    /// Menu bar rects in AppKit coordinates.
    static func bars() -> [CGRect] {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == menuLevel,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict),
                  cg.width > 200, cg.height > 10, cg.height < 60 else { return nil }
            // Window server rects use a top-left origin on the primary display.
            return CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The x range the camera housing covers, on displays that have one.
    var notchRange: ClosedRange<CGFloat>? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        let lower = frame.minX + left.maxX, upper = frame.minX + right.minX
        return lower < upper ? lower...upper : nil
    }
}
