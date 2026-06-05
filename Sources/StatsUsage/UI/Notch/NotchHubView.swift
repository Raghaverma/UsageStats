import SwiftUI
import StatsUsageDomain
import StatsUsagePresentation

/// The Dynamic-Island-style hub. Collapsed it straddles the notch with a compact
/// readout on each ear; on hover it expands downward into a live usage panel.
struct NotchHubView: View {
    @Bindable var viewModel: AppViewModel
    let geometry: NotchGeometry
    var onOpenSettings: () -> Void

    @State private var isExpanded = false

    private var earWidth: CGFloat { 84 }
    private var collapsedWidth: CGFloat { geometry.notchWidth + earWidth * 2 }
    private var expandedWidth: CGFloat { max(collapsedWidth, 380) }
    private var collapsedHeight: CGFloat { geometry.notchHeight }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0).allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            collapsedBar
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .background(NotchShape(bottomRadius: 16).fill(.black))
        .overlay(
            NotchShape(bottomRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .contentShape(NotchShape(bottomRadius: 16))
        .onHover { hovering in
            guard viewModel.config.notchExpandOnHover else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                isExpanded = hovering
            }
        }
        .onTapGesture { onOpenSettings() }
    }

    // MARK: Collapsed

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            ear(alignment: .leading) {
                if let snap = primarySnapshot {
                    HStack(spacing: 5) {
                        Circle().fill(color(for: snap)).frame(width: 7, height: 7)
                        Text(percentText(snap))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            Spacer(minLength: geometry.notchWidth)   // reserve the camera gap
            ear(alignment: .trailing) {
                if let countdown = primaryCountdown {
                    Text(countdown)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                } else if let snap = primarySnapshot {
                    Text(snap.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(height: collapsedHeight)
        .padding(.horizontal, 10)
    }

    private func ear<Content: View>(alignment: Alignment, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: earWidth - 10, alignment: alignment)
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Color.white.opacity(0.12))
            ForEach(rows, id: \.id) { row in
                NotchProviderRow(snapshot: row, name: name(for: row.source))
            }
            if rows.isEmpty {
                Text("No live providers yet")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
            HStack {
                Button(action: { viewModel.refreshNow() }) {
                    Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                Spacer()
                Button("Settings", action: onOpenSettings)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    // MARK: Data helpers

    private var enabledProviders: [ProviderDescriptor] {
        viewModel.config.providers.filter { $0.enabled }
    }

    private var rows: [UsageSnapshot] {
        enabledProviders.compactMap { viewModel.snapshots[$0.id] }
    }

    private var primarySnapshot: UsageSnapshot? {
        if let id = viewModel.config.notchProviderID, let snap = viewModel.snapshots[id] { return snap }
        return rows.first
    }

    private var primaryCountdown: String? {
        guard let window = primarySnapshot?.quotaWindows.first else { return nil }
        return MenuQuotaPresenter.resetCountdown(window)
    }

    private func percentText(_ snap: UsageSnapshot) -> String {
        if let pct = snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent {
            return "\(Int(pct.rounded()))%"
        }
        return "—"
    }

    private func name(for id: String) -> String {
        viewModel.config.providers.first(where: { $0.id == id })?.name ?? id
    }

    private func color(for snap: UsageSnapshot) -> Color {
        let pct = snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent
        guard snap.status == .ok, let pct else { return .gray }
        switch pct {
        case ..<20: return .red
        case ..<50: return .yellow
        default: return .green
        }
    }
}

/// One provider row in the expanded hub: dot, name, ring, percent, countdown.
private struct NotchProviderRow: View {
    let snapshot: UsageSnapshot
    let name: String

    private var percent: Double? {
        snapshot.remainingPercent ?? snapshot.quotaWindows.first?.remainingPercent
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat((percent ?? 0) / 100))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if let countdown = snapshot.quotaWindows.first.flatMap({ MenuQuotaPresenter.resetCountdown($0) }) {
                    Text(countdown).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                } else if !snapshot.note.isEmpty {
                    Text(snapshot.note).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer()
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var ringColor: Color {
        guard snapshot.status == .ok, let pct = percent else { return .gray }
        switch pct {
        case ..<20: return .red
        case ..<50: return .yellow
        default: return .green
        }
    }
}
