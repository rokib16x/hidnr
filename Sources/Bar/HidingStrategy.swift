import AppKit

/// How icons get hidden. `BarController` decides *when* to hide; a strategy
/// decides *how*, because macOS 27 changed what third-party apps can do.
protocol HidingStrategy: AnyObject {
    var isHiding: Bool { get }

    /// Hide the icons on the hidden side. `done(false)` means nothing was hidden
    /// and `problem` says why.
    func hide(_ done: @escaping (Bool) -> Void)
    func show()

    /// Displays were added, removed or resized.
    func screensChanged()

    /// Human-readable reason the last `hide` failed, if it did.
    var problem: String? { get }

    /// How many apps are hidden right now, when the strategy can tell.
    var hiddenCount: Int? { get }

    /// True when the problem is a missing Accessibility permission.
    var needsAccessibility: Bool { get }

    /// The Icons page changed or an app launched; re-apply if hiding.
    func layoutChanged()

    /// Whether a just-launched app would be hidden without the user asking.
    func wouldHideByMistake(_ bundleID: String) -> Bool

    /// Starts the current restriction afresh even if nothing changed.
    func forceReapply()
}

extension HidingStrategy {
    var hiddenCount: Int? { nil }
    var needsAccessibility: Bool { false }
    func layoutChanged() {}
    func wouldHideByMistake(_ bundleID: String) -> Bool { false }
    func forceReapply() {}
}

enum HidingStrategies {
    static var usesAllowList: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    static func make(arrow: NSStatusItem, divider: NSStatusItem) -> HidingStrategy {
        usesAllowList
            ? AllowListStrategy(arrow: arrow, divider: divider)
            : StretchStrategy(arrow: arrow, divider: divider)
    }
}

/// Where status items sit relative to each other. The "hidden side" is left of
/// the hidnr glyph in left-to-right layouts and right of it in right-to-left ones.
enum MenuBarSide {
    static var isRightToLeft: Bool {
        NSApp.userInterfaceLayoutDirection == .rightToLeft
    }

    /// True when `x` lies on the hidden side of `boundaryX`.
    static func isHidden(_ x: CGFloat, comparedTo boundaryX: CGFloat) -> Bool {
        isRightToLeft ? x > boundaryX : x < boundaryX
    }

    static func midX(of item: NSStatusItem) -> CGFloat? {
        item.button?.window?.frame.midX
    }
}
