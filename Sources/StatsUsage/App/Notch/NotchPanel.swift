import AppKit

/// A borderless, non-activating panel that floats above everything (including the
/// menu bar) on all Spaces — the host for the notch hub. Uses public AppKit APIs
/// only (no private SkyLight/CGSSpace), so it stays App Store-safe.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // Let SwiftUI inside decide what is interactive; transparent areas pass through.
        ignoresMouseEvents = false
    }

    // A borderless panel must opt in to receiving mouse/key without stealing focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
