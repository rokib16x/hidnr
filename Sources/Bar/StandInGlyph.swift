import AppKit

/// A copy of the hidnr "h" drawn in a tiny floating window on top of the menu
/// bar, used while icons are hidden on macOS 27.
///
/// macOS 27's allow-list hides hidnr's own status item along with the others,
/// even though hidnr is on the list (it keeps other allowed apps). Without this
/// the user would have nothing to click to get their icons back.
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

    /// Whether the stand-in knows where it goes. It may still be off screen on
    /// purpose, e.g. while a display is in full screen.
    var hasPlacement: Bool { contentWidth != nil }

    /// Shows the glyph and keeps it snug against the visible icons, re-checking
    /// every second: icons come and go (AirPods connecting, an app launching)
    /// while hidnr is hiding, and the stand-in must move with them.
    /// `baseline` is every icon's frame from just before hiding. Accessibility
    /// keeps reporting a hidden icon at exactly that frame, which is how the
    /// stand-in tells stale icons from visible ones.
    func start(image: NSImage, width: CGFloat, appearance: NSAppearance?, hiddenApps: Set<String>,
               baseline: [StatusItemScanner.Icon]) {
        self.image = image
        self.width = width
        self.appearance = appearance
        self.hiddenApps = hiddenApps
        self.baseline = Dictionary(Self.keyed(baseline), uniquingKeysWith: { first, _ in first })
        moved = []
        contentWidth = nil
        baselineClock = baseline.max(by: { $0.frame.maxX < $1.frame.maxX })?.frame
        // Until the first measurement, stand in exactly where the real h was.
        if let clock = baselineClock,
           let own = baseline.first(where: { $0.bundleID == Bundle.main.bundleIdentifier }) {
            contentWidth = max(0, Self.contentWidth(from: own.frame.maxX + 4, clock: clock))
        }
        if appsWithIcons.isEmpty { appsWithIcons = Set(baseline.map(\.bundleID)) }
        ticks = 0
        reposition()
        timer?.invalidate()
        // Placement is cheap and runs 4x a second so the stand-in reacts quickly
        // to full screen; the Accessibility scan inside runs once a second.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.reposition() }
    }

    func update(hiddenApps: Set<String>) {
        self.hiddenApps = hiddenApps
        fullScansOwed = 4
        if timer != nil { reposition() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        contentWidth = nil
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

    /// How far the visible icons reach left from the right edge of the menu
    /// bar, not counting the notch. The bar is right-aligned and shows the same
    /// icons on every display, so this one width places the stand-in everywhere.
    private var contentWidth: CGFloat?
    /// Apps seen with an icon; the frequent checks only ask these (plus
    /// macOS's own items), which keeps them cheap.
    private(set) var appsWithIcons: Set<String> = []
    private var baseline: [String: CGRect] = [:]
    /// The clock's frame when hiding. Accessibility only reports icon positions
    /// for the active menu bar, in that display's coordinates (sometimes ones
    /// that match no screen at all). The clock is always the rightmost icon and
    /// doesn't move on a given display, so a clock elsewhere means another
    /// display's menu bar is active and its positions can't be compared.
    private var baselineClock: CGRect?
    /// Icons whose frame has changed since `baseline`: those are certainly live.
    private var moved: Set<String> = []
    private var ticks = 0
    private var isScanning = false
    /// Full scans still owed after something changed (an app launched), since a
    /// new app's icon can take a moment to show up.
    private var fullScansOwed = 0

    func reposition() {
        placePanels()
        ticks += 1
        guard ticks % 4 == 1, StatusItemScanner.isTrusted, !isScanning else { return }
        let full = appsWithIcons.isEmpty || ticks % 40 == 1 || fullScansOwed > 0
        if fullScansOwed > 0 { fullScansOwed -= 1 }
        let visibleApps = appsWithIcons.subtracting(hiddenApps).union(StatusItemScanner.systemOwners)
        isScanning = true
        StatusItemScanner.scan(only: full ? nil : visibleApps) { [weak self] icons in
            guard let self else { return }
            self.isScanning = false
            // Stopped while this scan ran: don't bring the panels back.
            guard self.timer != nil else { return }
            if full { self.appsWithIcons = Set(icons.map(\.bundleID)) }
            self.measure(icons)
            self.placePanels()
        }
    }

    /// The display an Accessibility frame (top-left origin on the primary
    /// display) sits on.
    static func screen(containing frame: CGRect) -> NSScreen? {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = NSPoint(x: frame.midX, y: primaryTop - frame.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Identifies each icon as "bundle#n", its order within its app.
    static func keyed(_ icons: [StatusItemScanner.Icon]) -> [(String, CGRect)] {
        var counts: [String: Int] = [:]
        return icons.map { icon in
            let n = counts[icon.bundleID, default: 0]
            counts[icon.bundleID] = n + 1
            return ("\(icon.bundleID)#\(n)", icon.frame)
        }
    }

    /// Finds where the visible icons end. While hiding, Accessibility still
    /// reports hidden icons at their old frames, so starting from the clock
    /// this walks left and accepts an icon only if it's plausible as visible:
    /// macOS's own items, icons that moved or are new since hiding, and unmoved
    /// icons only until the first moved one (everything left of a moved icon
    /// that didn't move is stale). Overlaps are stale too, and the first real
    /// gap ends the run.
    private func measure(_ icons: [StatusItemScanner.Icon]) {
        let me = Bundle.main.bundleIdentifier ?? ""
        let hiddenApps = self.hiddenApps
        var items: [(key: String, frame: CGRect, system: Bool)] = []
        for (key, frame) in Self.keyed(icons) {
            let bundle = String(key[..<key.lastIndex(of: "#")!])
            guard bundle != me, !hiddenApps.contains(bundle), frame.width > 0 else { continue }
            if let before = baseline[key] {
                if abs(before.minX - frame.minX) > 0.5 || abs(before.width - frame.width) > 0.5 { moved.insert(key) }
            } else {
                moved.insert(key)   // appeared after hiding (AirPods connecting…)
            }
            items.append((key, frame, StatusItemScanner.isSystemOwned(bundle)))
        }

        // Anchor on the rightmost icon: the clock.
        guard let clock = items.max(by: { $0.frame.maxX < $1.frame.maxX }) else { return }
        // Another display's menu bar is active: its positions aren't comparable
        // with the baseline, so keep the last good placement until it returns.
        if let baselineClock,
           abs(clock.frame.minY - baselineClock.minY) > 2 || abs(clock.frame.maxX - baselineClock.maxX) > 40 {
            return
        }
        let notch = Self.screen(containing: clock.frame)?.notchRange
        let row = items
            .filter { abs($0.frame.midY - clock.frame.midY) < 8 }
            .sorted { $0.frame.maxX > $1.frame.maxX }

        var accepted: [CGRect] = [clock.frame]
        var edge = clock.frame.minX
        var passedMovedIcon = false
        for item in row.dropFirst() {
            let isMoved = moved.contains(item.key)
            if !item.system && !isMoved && passedMovedIcon { continue }
            if accepted.contains(where: { $0.insetBy(dx: 1, dy: 0).intersects(item.frame) }) { continue }
            var gap = edge - item.frame.maxX
            if let notch, item.frame.maxX <= notch.upperBound + 1, edge >= notch.lowerBound - 1 {
                gap -= notch.upperBound - notch.lowerBound
            }
            if gap > 24 { break }
            if !item.system && isMoved { passedMovedIcon = true }
            accepted.append(item.frame)
            edge = min(edge, item.frame.minX)
        }

        contentWidth = Self.contentWidth(from: edge, clock: clock.frame)
    }

    /// Distance from the menu bar's right edge to `x`, leaving out the notch
    /// when `x` lies left of it. The bar's right edge sits a fixed margin right
    /// of the clock; use the real margin when the clock's display is known.
    static func contentWidth(from x: CGFloat, clock: CGRect) -> CGFloat {
        let screen = screen(containing: clock)
        let barRight = clock.maxX + (screen.map { $0.frame.maxX - clock.maxX } ?? 20)
        var width = barRight - x
        if let notch = screen?.notchRange, x < notch.lowerBound {
            width -= notch.upperBound - notch.lowerBound
        }
        return width
    }

    private func placePanels() {
        guard let contentWidth else { return }
        var seen = Set<CGDirectDisplayID>()
        for bar in MenuBarWindows.bars() {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: bar.midX, y: bar.midY)) }),
                  let id = screen.displayID else { continue }
            // Full screen (a video, a full-screen app): the menu bar is hidden, so
            // the stand-in hides too, unless the pointer has revealed the bar.
            if Spaces.isFullScreen(screen) && !Self.isPointerInMenuBar(of: screen, height: bar.height) { continue }
            // A little breathing room, like the spacing between other icons.
            var right = bar.maxX - contentWidth - 4
            var x = right - width
            if let notch = screen.notchRange {
                // Icons that reach the notch continue on its left side.
                if right < notch.upperBound {
                    right -= notch.upperBound - notch.lowerBound
                    x = right - width
                }
                if x + width > notch.lowerBound, x < notch.upperBound { x = notch.lowerBound - width }
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

    private static func isPointerInMenuBar(of screen: NSScreen, height: CGFloat) -> Bool {
        let point = NSEvent.mouseLocation
        return screen.frame.contains(point) && point.y >= screen.frame.maxY - height - 4
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Set explicitly: by default clicks on the transparent pixels around
        // the glyph fall through to the menu bar, so only the ink was clickable.
        panel.ignoresMouseEvents = false
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
