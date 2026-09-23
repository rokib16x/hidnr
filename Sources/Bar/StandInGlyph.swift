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

    private var windows: [NSPanel] = []

    var isShown: Bool { !windows.isEmpty }

    /// Places the glyph on every display, `rightInset` points from the screen's
    /// right edge (measured to the glyph's right side).
    func show(image: NSImage, width: CGFloat, rightInset: CGFloat, appearance: NSAppearance?) {
        hide()
        for screen in NSScreen.screens {
            let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
            // No menu bar on this screen right now (e.g. it auto-hides).
            guard barHeight > 10 else { continue }
            let frame = NSRect(x: screen.frame.maxX - rightInset - width,
                               y: screen.frame.maxY - barHeight,
                               width: width, height: barHeight)
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
            view.onClick = { [weak self, weak view] secondary in
                guard let self, let view else { return }
                self.onClick(secondary, view)
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            windows.append(panel)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// The anchor for popovers: the stand-in on the screen under the pointer.
    var anchorUnderPointer: NSView? {
        let point = NSEvent.mouseLocation
        let panel = windows.first { $0.screen?.frame.contains(point) ?? false } ?? windows.first
        return panel?.contentView
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
