import SwiftUI
import StatsUsageDomain
import StatsUsagePresentation

/// The popover body: a card per provider plus a footer with refresh / quit.
struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    var onQuit: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("StatsUsage").font(.headline)
                Spacer()
                Button {
                    viewModel.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }

            if viewModel.lastLoadWasLossy {
                Label("Some saved providers couldn't be read and were skipped.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            if orderedSnapshots.isEmpty {
                Text("No providers configured yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(orderedSnapshots, id: \.source) { snapshot in
                    ProviderCardView(snapshot: snapshot, name: name(for: snapshot.source))
                }
            }

            Divider()

            HStack {
                Button("Settings…", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var orderedSnapshots: [UsageSnapshot] {
        viewModel.config.providers
            .filter { $0.enabled }
            .compactMap { viewModel.snapshots[$0.id] }
    }

    private func name(for id: String) -> String {
        viewModel.config.providers.first(where: { $0.id == id })?.name ?? id
    }
}

/// One provider card: name, value, freshness, and any quota windows with countdowns.
struct ProviderCardView: View {
    let snapshot: UsageSnapshot
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(name).font(.subheadline.bold())
                Spacer()
                Text(primaryValue).font(.subheadline.monospacedDigit())
            }
            if let account = snapshot.accountLabel {
                Text(account).font(.caption2).foregroundStyle(.secondary)
            }
            if !snapshot.note.isEmpty {
                Text(snapshot.note).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(snapshot.quotaWindows) { window in
                HStack {
                    Text(window.title).font(.caption2)
                    Spacer()
                    Text(MenuQuotaPresenter.remainingText(window)).font(.caption2)
                    if let countdown = MenuQuotaPresenter.resetCountdown(window) {
                        Text("· \(countdown)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryValue: String {
        if let pct = snapshot.remainingPercent { return "\(Int(pct.rounded()))%" }
        if let remaining = snapshot.remaining { return "\(Int(remaining)) \(snapshot.unit)" }
        return "—"
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .ok: return snapshot.valueFreshness == .cachedFallback ? .yellow : .green
        case .warning: return .yellow
        case .error: return .red
        case .disabled: return .gray
        }
    }
}
