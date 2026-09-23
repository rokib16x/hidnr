import AppKit
import SwiftUI

/// Owns hidnr's menu bar items and decides when icons are hidden or shown.
///
/// The main item is the "h" glyph: click it to hide/show, right-click for the
/// control panel. On macOS 14–26 a thin divider sits beside it and marks where
/// the hidden section starts; on macOS 27 the glyph itself is the boundary.
final class BarController: NSObject {
    private let glyph: NSStatusItem
    private let divider: NSStatusItem
    private lazy var strategy: HidingStrategy = HidingStrategies.make(arrow: glyph, divider: divider)

    private let panelModel = PanelModel()
    private lazy var panel: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ControlPanel(model: panelModel))
        return popover
    }()

    private var appsObservation: NSKeyValueObservation?
    private var launchDebounce: DispatchWorkItem?

    /// Stands in for the glyph while macOS hides it along with everything else.
    private let standIn = StandInGlyph()

    private var autoHideTimer: Timer?
    /// Ignores clicks that arrive while a previous toggle is still settling.
    private var isToggling = false

    override init() {
        Self.placeNearClockOnFirstRun()
        // Items created later appear further left, so the glyph comes first.
        glyph = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider = NSStatusBar.system.statusItem(withLength: 12)
        super.init()

        setUpItems()
        _ = strategy
        panelModel.toggle = { [weak self] in self?.toggle() }
        panelModel.openSettings = { [weak self] in
            self?.panel.performClose(nil)
            SettingsWindow.show(.general)
        }
        panelModel.organize = { [weak self] in
            self?.panel.performClose(nil)
            SettingsWindow.show(.icons)
        }
        panelModel.poll = { [weak self] in self?.refresh() }
        standIn.onClick = { [weak self] secondary, anchor in
            guard let self else { return }
            secondary ? self.togglePanel(from: anchor) : self.toggle()
        }
        panelModel.grantAccess = {
            StatusItemScanner.askForTrust()
            SettingsWindow.openAccessibilityPane()
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(layoutChanged), name: IconLayout.didChange, object: nil)
        // Background-only apps (most menu bar apps) never post the workspace
        // "did launch" notification, so watch the running-apps list itself.
        // Helper processes start all the time, so only real apps that the
        // current restriction doesn't already allow trigger a re-apply.
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            guard change.kind == .insertion else { return }
            let ids = (change.newValue ?? []).compactMap { app -> String? in
                guard app.bundleURL?.pathExtension == "app", app.activationPolicy != .prohibited else { return nil }
                return app.bundleIdentifier
            }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, ids.contains(where: self.strategy.wouldHideByMistake) else { return }
                self.appLaunched()
            }
        }

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            NSLog("hidnr: glyph at \(String(describing: self.glyph.button?.window?.frame)), strategy \(type(of: self.strategy))")
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("hidnr.debug.panel"), object: nil, queue: .main) { [weak self] _ in
            self?.togglePanelFromVisibleGlyph()
        }
        // Debug builds only: lets a script toggle hiding while testing.
        DistributedNotificationCenter.default().addObserver(forName: .init("hidnr.debug.toggle"), object: nil, queue: .main) { [weak self] _ in
            self?.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let self else { return }
                NSLog("hidnr: hiding=\(self.strategy.isHiding) hidden=\(String(describing: self.strategy.hiddenCount)) problem=\(self.strategy.problem ?? "none")")
            }
        }
        #endif

        if Settings.hideOnLaunch {
            // Give the menu bar a moment to place our items before measuring them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.hide() }
        }
    }

    // MARK: Items

    /// New status items land at the far left of the icon area, which on a
    /// notched MacBook is often behind the camera. macOS remembers each item's
    /// spot (points from the right edge) under this defaults key, so seed it
    /// once to start hidnr right next to the system icons.
    private static func placeNearClockOnFirstRun() {
        let key = "NSStatusItem Preferred Position hidnr.glyph"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(1, forKey: key)
        UserDefaults.standard.set(2, forKey: "NSStatusItem Preferred Position hidnr.divider")
    }

    private func setUpItems() {
        glyph.autosaveName = "hidnr.glyph"
        divider.autosaveName = "hidnr.divider"
        // ⌘-dragging an item out of the bar removes it for good; bring ours back.
        glyph.isVisible = true
        divider.isVisible = true

        if let button = glyph.button {
            button.target = self
            button.action = #selector(glyphClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        if let button = divider.button {
            button.image = Self.dividerImage
            button.target = self
            button.action = #selector(dividerClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Icons past this line are hidden by hidnr"
        }
        refresh()
    }

    private func refresh() {
        let hiding = strategy.isHiding
        if let button = glyph.button {
            button.image = hiding ? Self.hiddenGlyph : Self.shownGlyph
            button.toolTip = strategy.problem ?? (hiding ? "Show hidden icons (right-click for more)" : "Hide icons (right-click for more)")
            button.setAccessibilityLabel(hiding ? "hidnr, icons hidden" : "hidnr, icons shown")
        }
        panelModel.isHiding = hiding
        panelModel.hiddenCount = strategy.hiddenCount
        panelModel.problem = strategy.problem
        panelModel.needsAccessibility = strategy.needsAccessibility && strategy.problem != nil
    }

    // MARK: Glyph images

    private static let glyphSize = NSSize(width: 13, height: 17)

    /// The "h" from the logo.
    private static let shownGlyph: NSImage = {
        let base = NSImage(named: "BarGlyph") ?? NSImage()
        let image = NSImage(size: glyphSize, flipped: false) { rect in
            base.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// The "h" with a small dot beside it, meaning "more icons tucked away here".
    private static let hiddenGlyph: NSImage = {
        let base = NSImage(named: "BarGlyph") ?? NSImage()
        let dot: CGFloat = 4
        let size = NSSize(width: glyphSize.width + dot + 3, height: glyphSize.height)
        let image = NSImage(size: size, flipped: false) { rect in
            let rtl = MenuBarSide.isRightToLeft
            let dotX = rtl ? rect.maxX - dot : 0
            let glyphX = rtl ? 0 : dot + 3
            NSBezierPath(ovalIn: NSRect(x: dotX, y: rect.midY - dot / 2 + 1, width: dot, height: dot)).fill()
            base.draw(in: NSRect(x: glyphX, y: 0, width: glyphSize.width, height: glyphSize.height))
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static let dividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1, width: 1.5, height: rect.height - 2),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: Clicks

    @objc private func glyphClicked() {
        if isSecondaryClick, let button = glyph.button { return togglePanel(from: button) }
        toggle()
    }

    @objc private func dividerClicked() {
        if let button = glyph.button { togglePanel(from: button) }
    }

    private var isSecondaryClick: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePanel(from anchor: NSView) {
        if panel.isShown { return panel.performClose(nil) }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// Opens the panel from whichever h the user can see.
    private func togglePanelFromVisibleGlyph() {
        if standIn.isShown, let anchor = standIn.anchorUnderPointer {
            togglePanel(from: anchor)
        } else if let button = glyph.button {
            togglePanel(from: button)
        }
    }

    func toggle() {
        guard !isToggling else { return }
        isToggling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
        strategy.isHiding ? show() : hide()
    }

    // MARK: Hide / show

    func showEverything() {
        if strategy.isHiding { show() }
    }

    private func hide() {
        cancelAutoHide()
        guard !strategy.isHiding else { return }
        let before = glyphPlacement()
        strategy.hide { [weak self] hidden in
            guard let self else { return }
            self.refresh()
            if hidden { self.placeStandIn(startingAt: before) }
        }
    }

    private func show() {
        standIn.stop()
        glyph.length = NSStatusItem.variableLength
        strategy.show()
        refresh()
        scheduleAutoHide()
    }

    // MARK: Stand-in glyph

    private struct Placement {
        var width: CGFloat
        /// Distance from the screen's right edge to the glyph's right side.
        var rightInset: CGFloat
    }

    private func glyphPlacement() -> Placement? {
        guard let window = glyph.button?.window,
              let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })
        else { return nil }
        return Placement(width: window.frame.width, rightInset: screen.frame.maxX - window.frame.maxX)
    }

    /// After a hide on macOS 27, show the stand-in where the h can be clicked.
    /// macOS's allow-list hides our own item along with the rest (even for a
    /// Developer ID build), so the stand-in always takes over, and the real item
    /// shrinks to nothing so there can never be two h's.
    private func placeStandIn(startingAt before: Placement?) {
        guard HidingStrategies.usesAllowList else { return }
        let appearance = glyph.button?.effectiveAppearance
        glyph.length = 0
        // Let the bar reflow before measuring where the visible icons end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.strategy.isHiding else { return }
            self.standIn.start(image: Self.hiddenGlyph, width: before?.width ?? 30,
                               appearance: appearance, hiddenApps: IconLayout.hiddenApps)
        }
        // Fail open: if no stand-in could be placed, nothing would be left to
        // click, so bring every icon back instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.strategy.isHiding, !self.standIn.hasPanels else { return }
            NSLog("hidnr: couldn't place the stand-in h; showing icons again")
            self.show()
        }
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        guard Settings.autoHide, !strategy.isHiding else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: Settings.autoHideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Don't snap shut while the user is in the menu bar, the panel or settings.
            if Self.isPointerInMenuBar || self.panel.isShown || SettingsWindow.isVisible {
                self.scheduleAutoHide()
            } else {
                self.hide()
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    /// The menu bar is the strip between a screen's visible frame and its top edge.
    private static var isPointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX
                && point.y >= screen.visibleFrame.maxY && point.y <= screen.frame.maxY
        }
    }

    @objc private func screensChanged() {
        strategy.screensChanged()
        if standIn.isShown { standIn.reposition() }
    }

    /// Apps often launch in bursts; re-apply once they've settled.
    private func appLaunched() {
        launchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.layoutChanged() }
        launchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func layoutChanged() {
        strategy.layoutChanged()
        refresh()
        standIn.update(hiddenApps: IconLayout.hiddenApps)
    }

    @objc private func settingsChanged() {
        if !Settings.autoHide {
            cancelAutoHide()
        } else if !strategy.isHiding && autoHideTimer == nil {
            scheduleAutoHide()
        }
    }
}
