import AppKit

/// macOS 14–26: make the divider enormous. The menu bar lays items out right to
/// left, so everything left of a very wide divider ends up past the screen edge.
final class StretchStrategy: HidingStrategy {
    private let arrow: NSStatusItem
    private let divider: NSStatusItem
    private let normalWidth: CGFloat = 12

    private(set) var problem: String?

    init(arrow: NSStatusItem, divider: NSStatusItem) {
        self.arrow = arrow
        self.divider = divider
        divider.length = normalWidth
    }

    var isHiding: Bool { divider.length > normalWidth }

    /// Wide enough for the widest display (the bar repeats on each one), capped
    /// at 10,000pt, the most macOS accepts for a status item.
    private var stretchedWidth: CGFloat {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 2000
        return min(max(widest * 2, 600), 10_000)
    }

    func hide(_ done: @escaping (Bool) -> Void) {
        guard let dividerX = MenuBarSide.midX(of: divider),
              let arrowX = MenuBarSide.midX(of: arrow),
              MenuBarSide.isHidden(dividerX, comparedTo: arrowX) else {
            problem = "Hold ⌘ and drag the thin divider next to the hidnr icon, on the side you want hidden."
            return done(false)
        }
        problem = nil
        divider.length = stretchedWidth
        done(true)
    }

    func show() {
        divider.length = normalWidth
    }

    func screensChanged() {
        if isHiding { divider.length = stretchedWidth }
    }
}
