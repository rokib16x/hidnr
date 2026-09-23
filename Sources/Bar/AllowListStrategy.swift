import AppKit

/// macOS 27+: a wide divider no longer pushes icons away, so hidnr asks macOS
/// directly to show only an allow-list of apps.
///
/// Which apps are hidden comes from `IconLayout` (the Icons page in Settings).
/// The very first time, before the user has chosen, hidnr seeds that list from
/// where icons sit: apps left of the hidnr glyph are hidden.
/// Known limits, all imposed by macOS 27:
/// - it works per app, so an app with several icons shows or hides them together;
/// - macOS's own items (clock, Wi-Fi, Control Center…) always stay visible.
final class AllowListStrategy: HidingStrategy {
    /// System item identifiers to keep. Ids a Mac doesn't have are ignored, so a
    /// generous range covers every built-in item.
    private static let systemItems = (0..<64).map { NSNumber(value: $0) }

    private enum Failure {
        case noAPI, noTrust, notReady
        case refused(String)
    }

    private let glyph: NSStatusItem
    private var token: Any?
    /// Every restriction started and not yet released, including ones still in
    /// flight. `show()` ends all of them, so none can outlive a show.
    private var liveTokens: [AnyObject] = []
    private var isWorking = false
    /// A change arrived while an update was in flight; apply again after it.
    private var needsReapply = false
    /// The apps the current restriction allows, to skip no-op re-applies.
    private var allowedApps: Set<String> = []
    /// Bumped by `show()` so a hide that finishes afterwards is thrown away.
    private var attempt = 0
    private var askedForTrust = false
    private var failure: Failure?

    init(arrow: NSStatusItem, divider: NSStatusItem) {
        glyph = arrow
        // The glyph itself is the boundary here; the divider has no job.
        divider.isVisible = false
    }

    var isHiding: Bool { token != nil }

    var needsAccessibility: Bool { !StatusItemScanner.isTrusted }

    /// Recomputed on every read, so a permission granted a moment ago clears the
    /// warning without needing another click.
    var problem: String? {
        switch failure {
        case nil:
            return nil
        case .noAPI:
            return "This version of macOS doesn't offer the hiding switch hidnr uses."
        case .noTrust:
            return StatusItemScanner.isTrusted ? nil : "hidnr needs the Accessibility permission to find and hide icons."
        case .notReady:
            return "The menu bar isn't ready yet. Try again in a moment."
        case .refused(let reason):
            return "macOS refused to hide icons: \(reason)"
        }
    }

    var hiddenCount: Int? {
        isHiding ? IconLayout.hiddenApps.count : nil
    }

    func hide(_ done: @escaping (Bool) -> Void) {
        guard !isHiding, !isWorking else { return done(isHiding) }
        guard HNMenuBarAllowList.isAvailable() else { return fail(.noAPI, done) }
        guard StatusItemScanner.isTrusted else {
            if !askedForTrust {
                askedForTrust = true
                StatusItemScanner.askForTrust()
            }
            return fail(.noTrust, done)
        }
        guard let windowX = MenuBarSide.midX(of: glyph) else { return fail(.notReady, done) }

        if IconLayout.isConfigured {
            apply(done)
            return
        }
        // First run: turn today's arrangement into the saved layout.
        isWorking = true
        StatusItemScanner.scan { [weak self] icons in
            guard let self else { return }
            let me = Bundle.main.bundleIdentifier
            // Measure our own icon the same way as everyone else's: with several
            // displays AppKit frames and Accessibility positions can disagree.
            let boundary = icons.first { $0.bundleID == me }?.midX ?? windowX
            IconLayout.hiddenApps = Set(icons
                .filter { $0.bundleID != me && !StatusItemScanner.isSystemOwned($0.bundleID) }
                .filter { MenuBarSide.isHidden($0.midX, comparedTo: boundary) }
                .map(\.bundleID))
            self.isWorking = false
            self.apply(done)
        }
    }

    /// Re-applies the allow-list while hiding, e.g. after the layout changed or
    /// an app launched. The new restriction starts before the old one ends, so
    /// the bar never flashes fully visible.
    func layoutChanged() {
        guard isHiding else { return }
        guard !isWorking else { needsReapply = true; return }
        apply { _ in }
    }

    /// True when `bundleID` is a new app this restriction would hide by mistake.
    func wouldHideByMistake(_ bundleID: String) -> Bool {
        isHiding && !allowedApps.contains(bundleID) && !IconLayout.isHidden(bundleID)
    }

    func show() {
        attempt += 1
        isWorking = false
        needsReapply = false
        token = nil
        allowedApps = []
        let all = liveTokens
        liveTokens.removeAll()
        all.forEach { HNMenuBarAllowList.releaseToken($0) }
    }

    func screensChanged() {
        // macOS reflows the allow-listed bar itself; nothing to recompute.
    }

    /// Allows every running app except the hidden ones. Listing apps without
    /// icons is harmless, and it keeps apps visible that add an icon later.
    private func apply(_ done: @escaping (Bool) -> Void) {
        let me = Bundle.main.bundleIdentifier ?? ""
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let others = running.subtracting(IconLayout.hiddenApps).subtracting([me]).sorted()
        let allowed = [me] + others
        if isHiding && Set(allowed) == allowedApps { return done(true) }

        isWorking = true
        attempt += 1
        let thisAttempt = attempt
        HNMenuBarAllowList.allowSystemItems(Self.systemItems, apps: allowed) { [weak self] newToken, error in
            guard let self else {
                if let newToken { HNMenuBarAllowList.releaseToken(newToken) }
                return
            }
            guard thisAttempt == self.attempt else {
                // The user clicked show (or a newer update started) meanwhile.
                if let newToken { HNMenuBarAllowList.releaseToken(newToken) }
                return
            }
            self.isWorking = false
            guard let newToken = newToken as AnyObject? else {
                return self.fail(.refused(error?.localizedDescription ?? "unknown error"), done)
            }
            // Keep only the new restriction: end every older one.
            let older = self.liveTokens
            self.liveTokens = [newToken]
            self.token = newToken
            self.allowedApps = Set(allowed)
            older.forEach { HNMenuBarAllowList.releaseToken($0) }
            self.failure = nil
            done(true)
            if self.needsReapply {
                self.needsReapply = false
                self.layoutChanged()
            }
        }
    }

    private func fail(_ failure: Failure, _ done: (Bool) -> Void) {
        self.failure = failure
        NSLog("hidnr: can't hide: \(problem ?? "unknown")")
        done(false)
    }
}
