import Foundation
import StatsUsageDomain

/// Reads local Codex CLI login state (`~/.codex/auth.json`) and reports account
/// status. Quota windows are local estimates until an official endpoint is wired,
/// so the snapshot is honestly labeled as a CLI/local-estimate source.
final class CodexProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let keychain: KeychainService
    private let authFileURL: URL

    init(descriptor: ProviderDescriptor, keychain: KeychainService, authFileURL: URL? = nil) {
        self.descriptor = descriptor
        self.keychain = keychain
        self.authFileURL = authFileURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
    }

    func fetch() async throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw ProviderError.missingCredential("Codex CLI login (~/.codex/auth.json)")
        }
        let data = try Data(contentsOf: authFileURL)
        let account = parseAccountLabel(data: data)

        // Without an official quota endpoint, expose a local-estimate session window.
        let window = UsageQuotaWindow(
            id: "\(descriptor.id).session",
            title: "Session",
            remainingPercent: 100,
            usedPercent: 0,
            resetAt: nil,
            kind: .session,
            resetSource: .localEstimate
        )
        return UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            unit: "quota",
            note: "Local session (estimate)",
            quotaWindows: [window],
            sourceLabel: "CLI",
            accountLabel: account
        ).withDefaultResetMetadata()
    }

    private func parseAccountLabel(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Tolerate a few likely shapes for the account email.
        if let email = obj["email"] as? String { return email }
        if let tokens = obj["tokens"] as? [String: Any], let email = tokens["account_email"] as? String {
            return email
        }
        return nil
    }
}
