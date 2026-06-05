import Foundation
import StatsUsageDomain

/// Turns a quota window into display strings. Pure and unit-tested; views stay dumb.
public enum MenuQuotaPresenter {
    public static func remainingText(_ window: UsageQuotaWindow) -> String {
        "\(Int(window.remainingPercent.rounded()))% left"
    }

    /// Human-friendly countdown to reset, e.g. "resets in 3h 12m".
    public static func resetCountdown(_ window: UsageQuotaWindow, now: Date = Date()) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "resetting…" }
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }

    /// A short trust label derived from confidence + freshness.
    public static func confidenceLabel(_ window: UsageQuotaWindow, freshness: ValueFreshness) -> String {
        if freshness == .cachedFallback { return "cached" }
        switch window.confidence {
        case .confirmed: return "confirmed"
        case .estimated: return "estimated"
        case .stale: return "stale"
        case .unknown: return "unknown"
        }
    }
}
