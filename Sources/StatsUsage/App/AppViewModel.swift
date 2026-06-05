import Foundation
import Observation
import StatsUsageDomain
import StatsUsageApplication

/// The `@MainActor @Observable` hub the UI binds to. Kept as a façade: it owns the
/// stores, the factory, and the scheduler, and exposes the freshest snapshots.
@MainActor
@Observable
final class AppViewModel {
    // Persisted + session state.
    private(set) var config: AppConfig
    private(set) var snapshots: [String: UsageSnapshot] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var lastLoadWasLossy: Bool

    /// Rolling per-provider remaining-percent history that feeds the sparkline widget.
    private(set) var usageHistory: [String: [Double]] = [:]
    private let maxHistory = 30

    // Collaborators.
    private let configStore: ConfigStore
    private let keychain: KeychainService
    private let relayRegistry: RelayAdapterRegistry
    private let factory: ProviderFactoryRegistry
    private let scheduler: ProviderRefreshScheduler
    private let notificationService: NotificationService

    private var providers: [String: any UsageProvider] = [:]
    private var consecutiveFailures: [String: Int] = [:]

    init(
        configStore: ConfigStore = ConfigStore(),
        keychain: KeychainService = KeychainService(),
        relayRegistry: RelayAdapterRegistry? = nil,
        notificationService: NotificationService = NotificationService()
    ) {
        self.configStore = configStore
        self.keychain = keychain
        self.relayRegistry = relayRegistry ?? RelayAdapterRegistry.loadFromBundle()
        self.factory = ProviderFactoryRegistry()
        self.scheduler = ProviderRefreshScheduler()
        self.notificationService = notificationService
        self.config = (try? configStore.load()) ?? .default
        self.lastLoadWasLossy = configStore.lastLoadWasLossy
        rebuildProviders()
    }

    /// Build the provider instances for the current config.
    private func rebuildProviders() {
        let deps = ProviderFactoryRegistry.Dependencies(keychain: keychain, relayRegistry: relayRegistry)
        var built: [String: any UsageProvider] = [:]
        for descriptor in config.providers where descriptor.enabled {
            built[descriptor.id] = factory.makeProvider(for: descriptor, dependencies: deps)
        }
        providers = built
    }

    /// Start the poll loop.
    func start() {
        scheduler.restart(providers: scheduleDescriptors())
    }

    func stop() { scheduler.stop() }

    /// Force-refresh everything now (e.g. on user request).
    func refreshNow() { scheduler.refreshNow() }

    private func scheduleDescriptors() -> [ProviderRefreshScheduleDescriptor] {
        config.providers.compactMap { descriptor in
            guard descriptor.enabled, providers[descriptor.id] != nil else { return nil }
            let id = descriptor.id
            return ProviderRefreshScheduleDescriptor(
                id: id,
                pollIntervalSec: descriptor.pollIntervalSec,
                enabled: true,
                refresh: { [weak self] force in
                    await self?.performRefresh(id: id, force: force)
                },
                failureCount: { [weak self] in
                    MainActor.assumeIsolated { self?.consecutiveFailures[id] ?? 0 }
                }
            )
        }
    }

    private func performRefresh(id: String, force: Bool) async {
        guard let provider = providers[id],
              let descriptor = config.providers.first(where: { $0.id == id }) else { return }
        do {
            let snapshot = try await provider.fetch(forceRefresh: force)
            snapshots[id] = snapshot
            errors[id] = nil
            consecutiveFailures[id] = 0
            recordHistory(id: id, snapshot: snapshot)
            evaluateAlerts(snapshot: snapshot, descriptor: descriptor)
        } catch {
            consecutiveFailures[id, default: 0] += 1
            errors[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Mark the prior snapshot (if any) as a cached fallback.
            if var prior = snapshots[id] {
                prior.valueFreshness = .cachedFallback
                prior.fetchHealth = (error as? ProviderError)?.fetchHealth ?? .unreachable
                prior.note = errors[id] ?? prior.note
                snapshots[id] = prior
            }
            evaluateFailureAlerts(id: id, error: error, descriptor: descriptor)
        }
    }

    /// Append the snapshot's remaining-percent to the rolling history (capped).
    private func recordHistory(id: String, snapshot: UsageSnapshot) {
        guard let pct = snapshot.remainingPercent ?? snapshot.quotaWindows.first?.remainingPercent else { return }
        var series = usageHistory[id] ?? []
        series.append(pct)
        if series.count > maxHistory { series.removeFirst(series.count - maxHistory) }
        usageHistory[id] = series
    }

    private func evaluateAlerts(snapshot: UsageSnapshot, descriptor: ProviderDescriptor) {
        let decision = AlertEngine.evaluate(
            snapshot: snapshot,
            consecutiveFailures: consecutiveFailures[descriptor.id] ?? 0,
            rule: descriptor.threshold
        )
        notificationService.post(decision: decision, providerName: descriptor.name)
    }

    private func evaluateFailureAlerts(id: String, error: Error, descriptor: ProviderDescriptor) {
        let synthetic = UsageSnapshot(
            source: id,
            fetchHealth: (error as? ProviderError)?.fetchHealth ?? .unreachable
        )
        let decision = AlertEngine.evaluate(
            snapshot: synthetic,
            consecutiveFailures: consecutiveFailures[id] ?? 0,
            rule: descriptor.threshold
        )
        notificationService.post(decision: decision, providerName: descriptor.name)
    }

    // MARK: Config mutation

    func updateConfig(_ transform: (inout AppConfig) -> Void) {
        var copy = config
        transform(&copy)
        config = copy
        try? configStore.save(copy)
        rebuildProviders()
        scheduler.restart(providers: scheduleDescriptors())
    }
}
