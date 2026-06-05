import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: builds it, hosts the SwiftUI hub, pins it to the notch,
/// and shows/hides it in response to config + screen changes.
@MainActor
final class NotchHubController {
    private let viewModel: AppViewModel
    private let onOpenSettings: () -> Void
    private var panel: NotchPanel?
    private var screenObserver: NSObjectProtocol?

    /// Generous fixed footprint; the island animates within it, top-anchored.
    private let panelHeight: CGFloat = 320

    init(viewModel: AppViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }

        observeEnabled()
    }

    /// Track the notch-enabled flag and reflect it into panel visibility.
    private func observeEnabled() {
        withObservationTracking {
            _ = viewModel.config.notchEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyEnabledState()
                self?.observeEnabled()
            }
        }
        applyEnabledState()
    }

    private func applyEnabledState() {
        if viewModel.config.notchEnabled {
            if panel == nil { rebuild() }
        } else {
            teardown()
        }
    }

    private func rebuild() {
        guard viewModel.config.notchEnabled else { return }
        teardown()

        let screen = preferredScreen()
        let geometry = NotchGeometry.resolve(for: screen)
        let panelWidth = max(geometry.notchWidth + 84 * 2, 400)

        let frame = panelFrame(on: screen, width: panelWidth)
        let panel = NotchPanel(contentRect: frame)
        panel.contentView = NSHostingView(
            rootView: NotchHubView(
                viewModel: viewModel,
                geometry: geometry,
                onOpenSettings: onOpenSettings
            )
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func teardown() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func preferredScreen() -> NSScreen? {
        // Prefer the screen that actually has a notch; else the main screen.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func panelFrame(on screen: NSScreen?, width: CGFloat) -> NSRect {
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - panelHeight   // top edge flush with screen top
        return NSRect(x: x, y: y, width: width, height: panelHeight)
    }
}
