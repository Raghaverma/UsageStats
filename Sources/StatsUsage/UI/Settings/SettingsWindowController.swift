import AppKit
import SwiftUI

/// Hosts the SwiftUI settings tree in a standard `NSWindow`.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(viewModel: AppViewModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "StatsUsage Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsRootView(viewModel: viewModel))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
