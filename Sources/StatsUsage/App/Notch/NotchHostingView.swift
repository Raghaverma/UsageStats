import AppKit
import SwiftUI

/// Shared, main-actor state that lets the SwiftUI hub report the live frame of the
/// visible island so the hosting view can pass mouse events through everywhere else.
///
/// Without this, the notch panel's `NSHostingView` claims hit-testing across its
/// entire (large) frame, creating a dead zone near the notch where the user cannot
/// click anything underneath. A `@MainActor` class is implicitly `Sendable`, so it is
/// safe to capture from SwiftUI's `@Sendable` preference-change closure.
@MainActor
final class NotchHitState {
    /// Interactive island frame, in the hub's top-left-origin coordinate space.
    /// `.zero` means "nothing interactive" (everything passes through).
    var islandFrame: CGRect = .zero
}

/// Hosting view for the notch hub that only intercepts mouse events within the
/// currently visible island; all other points fall through to the windows below.
final class NotchHostingView: NSHostingView<NotchHubView> {
    var hitState: NotchHitState?

    required init(rootView: NotchHubView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitState else { return super.hitTest(point) }

        // `point` is in the superview's coordinate system; bring it into ours.
        let local = convert(point, from: superview)
        // AppKit is bottom-left origin; SwiftUI frames are top-left origin.
        let topLeft = CGPoint(x: local.x, y: bounds.height - local.y)

        guard hitState.islandFrame.contains(topLeft) else { return nil }
        return super.hitTest(point)
    }
}
