# Building **StatsUsage** From Scratch

A complete, opinionated guide to building a macOS menu-bar console for AI subscription quota, usage windows, third‑party relay balances, and local desktop‑client account status — modeled on the architecture of `oh-myusage`.

This document is the blueprint. It walks you from an empty folder to a signed, self‑updating, notarized `.app`, explaining **what** each layer does, **why** it exists, and **how** to build it. Code samples are faithful starting points (Swift 6.2), trimmed for clarity — treat them as scaffolding to grow, not drop‑in production code.

> Throughout, the product is called **StatsUsage** and the SwiftPM package/executable is `StatsUsage`. Substitute your own bundle id (`com.statsusage.app`) where shown.

---

## Table of contents

1. [What you are building](#1-what-you-are-building)
2. [Prerequisites & toolchain](#2-prerequisites--toolchain)
3. [Architecture at a glance](#3-architecture-at-a-glance)
4. [Step 1 — Scaffold the Swift package](#step-1--scaffold-the-swift-package)
5. [Step 2 — The domain layer (contracts)](#step-2--the-domain-layer-contracts)
6. [Step 3 — The provider abstraction](#step-3--the-provider-abstraction)
7. [Step 4 — Persistence & secrets](#step-4--persistence--secrets)
8. [Step 5 — Implement providers (official + relay)](#step-5--implement-providers-official--relay)
9. [Step 6 — The refresh engine](#step-6--the-refresh-engine)
10. [Step 7 — The app shell & menu bar UI](#step-7--the-app-shell--menu-bar-ui)
11. [Step 8 — The settings window](#step-8--the-settings-window)
12. [Step 9 — Alerts & notifications](#step-9--alerts--notifications)
13. [Step 10 — Self-update](#step-10--self-update)
14. [Step 11 — Packaging (DMG/ZIP, signing, notarization)](#step-11--packaging-dmgzip-signing-notarization)
15. [Step 12 — CI/CD with GitHub Actions](#step-12--cicd-with-github-actions)
16. [Step 13 — Testing strategy](#step-13--testing-strategy)
17. [Recommended build order (milestones)](#17-recommended-build-order-milestones)
18. [Conventions, concurrency & gotchas](#18-conventions-concurrency--gotchas)
19. [Final directory layout](#19-final-directory-layout)

---

## 1. What you are building

StatsUsage is a **menu-bar–only** macOS app (no Dock icon, no main window) that unifies AI usage information that is otherwise scattered:

- **Official subscription quota** — Codex, Claude, Gemini, Copilot, Cursor, Windsurf, etc. Read from local login state / OAuth tokens / official endpoints.
- **Model usage windows** — session, 5-hour, daily, weekly, monthly windows with **reset countdowns**.
- **Third-party "relay" balances** — NewAPI-style proxy sites, configured via JSON templates (Bearer/Cookie auth, balance + token channels).
- **Local desktop-client account status** — multi-account Codex/Claude slots, switch & import.
- **Diagnostics** — distinguish *official-confirmed* vs *local-estimate* vs *cached-fallback* vs *auth-expired* data so the user trusts what they see.

Key product qualities that drive the architecture:

| Quality | Architectural consequence |
| --- | --- |
| Always resident, low power | One coalesced poll loop; render only on change; cache snapshots |
| Trustworthy data | Every value carries *freshness* + *health* + *reset confidence* metadata |
| Extensible to many providers | A provider protocol + factory registry + JSON relay templates |
| Survives bad config / API drift | Lossy-tolerant config decoding, last-known-good, cached fallback |
| Distributed outside the App Store | DMG/ZIP packaging, ad-hoc or Developer ID signing, in-app updates |

---

## 2. Prerequisites & toolchain

- **macOS 14 (Sonoma) or newer** — the deployment target.
- **Swift 6.2 toolchain** (Xcode 16.x or a matching open-source toolchain). The package opts into the Swift 6 language mode, so concurrency checking is strict.
- **No third-party dependencies.** Everything uses the system frameworks: `AppKit`, `SwiftUI`, `Foundation`, `Observation`, `UserNotifications`, `Security` (Keychain), `CryptoKit` (checksums). This keeps packaging trivial and supply chain risk near zero.
- Command-line tools used for packaging: `swift`, `codesign`, `hdiutil`, `sips`, `iconutil`, `ditto`, `xcrun notarytool`/`stapler` (only if notarizing), `osascript` (DMG window styling).

Core commands you will use constantly:

```bash
swift build          # compile the executable target
swift run            # launch from source (macOS 14+)
swift test           # run the XCTest suite
./scripts/package_dmg.sh   # build a distributable DMG + ZIP into dist/
```

---

## 3. Architecture at a glance

The codebase is a **single Swift Package with multiple library targets**, layered by responsibility. The dependency arrows only point "inward" toward the domain — UI and providers depend on domain contracts, never the reverse.

```
                 ┌───────────────────────────────────────────┐
                 │            StatsUsage (executable)          │
                 │  App shell · SwiftUI UI · Services ·        │
                 │  concrete Providers · Resources             │
                 └───────────────┬─────────────────────────────┘
                                 │ depends on
   ┌───────────────┬─────────────┼───────────────┬───────────────┐
   ▼               ▼             ▼               ▼               ▼
Bootstrap      Features     Presentation     Application      Providers
(compose)   (assembly)   (view models)   (scheduling,      (fetch
                                          backoff,           contracts)
                                          analytics)
   └───────────────┴─────────────┬───────────────┴───────────────┘
                                 ▼
                          Infrastructure  ────►  Domain
                          (cred store)           (pure models & enums:
                                                  UsageSnapshot, ProviderType,
                                                  AuthConfig, ...)
```

Why split it like this?

- **`Domain`** holds pure, `Sendable`, dependency-free value types and enums. It is the stable contract every other layer agrees on. It imports nothing but `Foundation`.
- **`Application`** holds use-case logic that needs no UIKit/AppKit: the **refresh scheduler**, **backoff policy**, **usage analytics**, runtime diagnostics limits, a visible-clock controller. Pure and unit-testable.
- **`Presentation`** holds view-state models and presenter output that is independent of SwiftUI specifics.
- **`Providers`** declares the *fetching* contract (`UsageProviderFetching`) the app implements.
- **`Features`** assembles a provider id + title into a "usage feature descriptor" and builds refresh requests / summary view states.
- **`Bootstrap`** is the **composition root** — it wires Features/Application/Presentation together behind one small façade.
- **`Infrastructure`** holds cross-cutting plumbing (e.g. a credential store seam).
- The **executable** target (`StatsUsage`) is where the real macOS app lives: AppKit status item, SwiftUI views, the concrete provider implementations, the config store, keychain access, packaging resources.

> **Practical note:** in a real refactor you start with everything in the executable target and *extract* stable seams into libraries over time. The extra targets buy you (a) enforced dependency direction, (b) fast, app-free unit tests, and (c) compile-time isolation. If you are bootstrapping solo, it's fine to begin with just `Domain` + executable and grow.

A boundary test (described in [Step 13](#step-13--testing-strategy)) enforces that, e.g., `Domain` never imports AppKit.

---

## Step 1 — Scaffold the Swift package

Create the folder and `Package.swift`. The manifest defines every library target, the executable, its bundled resources, and the test target.

```bash
mkdir StatsUsage && cd StatsUsage
git init
mkdir -p Sources/StatsUsage/{App,UI,Services,Providers,Models,Utils,Resources}
mkdir -p Sources/StatsUsageDomain Sources/StatsUsageApplication \
         Sources/StatsUsagePresentation Sources/StatsUsageProviders \
         Sources/StatsUsageFeatures Sources/StatsUsageBootstrap \
         Sources/StatsUsageInfrastructure
mkdir -p Tests/StatsUsageTests/Fixtures
echo "0.1.0" > VERSION
```

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StatsUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StatsUsage", targets: ["StatsUsage"])
    ],
    targets: [
        .target(name: "StatsUsageDomain"),
        .target(name: "StatsUsageInfrastructure", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageProviders", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageApplication", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsagePresentation", dependencies: ["StatsUsageDomain"]),
        .target(name: "StatsUsageFeatures", dependencies: [
            "StatsUsageDomain", "StatsUsageApplication", "StatsUsagePresentation"
        ]),
        .target(name: "StatsUsageBootstrap", dependencies: [
            "StatsUsageDomain", "StatsUsageApplication",
            "StatsUsageFeatures", "StatsUsagePresentation"
        ]),
        .executableTarget(
            name: "StatsUsage",
            dependencies: [
                "StatsUsageDomain", "StatsUsageInfrastructure", "StatsUsageProviders",
                "StatsUsageApplication", "StatsUsagePresentation",
                "StatsUsageFeatures", "StatsUsageBootstrap"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StatsUsageTests",
            dependencies: [
                "StatsUsage", "StatsUsageDomain", "StatsUsageInfrastructure",
                "StatsUsageProviders", "StatsUsageApplication",
                "StatsUsagePresentation", "StatsUsageFeatures", "StatsUsageBootstrap"
            ],
            exclude: ["Fixtures"]
        )
    ]
)
```

`.process("Resources")` makes everything under `Sources/StatsUsage/Resources/` available via `Bundle.module`. The `Fixtures` folder is excluded from the test target so test JSON files aren't compiled.

A starter `.gitignore`:

```gitignore
.DS_Store
/.build
/dist
/Packages
xcuserdata/
DerivedData/
.swiftpm/configuration/registries.json
.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
```

---

## Step 2 — The domain layer (contracts)

Everything orbits one model: **`UsageSnapshot`** — the normalized result of fetching one provider once. Define it (and its enums) in `Sources/StatsUsageDomain/`. These types are `public`, `Codable`, `Equatable`, `Sendable`.

### 2.1 The credibility enums

The product promise is "tell me how much to trust this number." That promise is encoded as enums attached to every snapshot:

```swift
public enum SnapshotStatus: String, Codable, Sendable { case ok, warning, error, disabled }

// Why the fetch is in its current state — drives diagnostics copy.
public enum FetchHealth: String, Codable, Sendable {
    case ok, authExpired, rateLimited, endpointMisconfigured, unreachable
}

// Is this value live, a cached fallback after a failed refresh, or absent?
public enum ValueFreshness: String, Codable, Sendable { case live, cachedFallback, empty }

// What kind of quota window this is.
public enum UsageQuotaKind: String, Codable, Sendable {
    case session, weekly, reviews, credits, extraUsage, modelWeekly, custom
}

// Where the *reset time* came from, and how confident we are in it.
public enum UsageQuotaResetSource: String, Codable, Sendable {
    case official, webObserved, localEstimate, userCalibrated, unknown
}
public enum UsageQuotaResetConfidence: String, Codable, Sendable {
    case confirmed, estimated, stale, unknown
}
```

### 2.2 The quota window

A provider may expose several rolling windows (e.g. a 5-hour session window *and* a weekly window), each with its own reset clock:

```swift
public struct UsageQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var remainingPercent: Double
    public var usedPercent: Double
    public var resetAt: Date?
    public var kind: UsageQuotaKind
    public var resetSource: UsageQuotaResetSource
    public var observedAt: Date?
    public var serverClockSkew: TimeInterval?
    public var confidence: UsageQuotaResetConfidence
    public var windowIdentity: String?
    // memberwise init with sensible defaults (resetSource/.unknown, etc.) ...
}
```

A nice touch from the reference design: when a snapshot is constructed, it **back-fills missing reset metadata** by inference — if `resetSource == .unknown` it guesses from the source label ("api"→`.official`, "web"/"browser"→`.webObserved`, "cli"/"local"→`.localEstimate`), and if `confidence == .unknown` it derives confidence from freshness + source. Centralize that logic in a `withDefaultResetMetadata(...)` extension so providers can stay terse.

### 2.3 The snapshot

```swift
public struct UsageSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { source }
    public var source: String              // stable provider id
    public var status: SnapshotStatus
    public var fetchHealth: FetchHealth
    public var valueFreshness: ValueFreshness
    public var remaining: Double?
    public var used: Double?
    public var limit: Double?
    public var unit: String                // "quota", "USD", "credits", "%", ...
    public var updatedAt: Date
    public var note: String                // human-readable status / error line
    public var quotaWindows: [UsageQuotaWindow]
    public var sourceLabel: String         // "API" / "CLI" / "Web" — drives inference
    public var accountLabel: String?
    public var authSourceLabel: String?
    public var diagnosticCode: String?
    public var extras: [String: String]    // provider-specific display extras
    public var rawMeta: [String: String]   // raw fields kept for debugging
    // ...
}
```

**Implement `Codable` defensively.** Write a custom `init(from:)` that uses `decodeIfPresent` for every newer field and supplies defaults (`fetchHealth ?? .ok`, `extras ?? [:]`). This is what lets old cached snapshots keep decoding after you add fields — a recurring theme in this app.

### 2.4 Provider identity & configuration

```swift
public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case codex, claude, gemini, copilot, microsoftCopilot, zai, amp, cursor,
         jetbrains, kiro, windsurf, trae, openrouterCredits, openrouterAPI,
         ollamaCloud, opencodeGo, relay, open, dragon, kimi
}

public enum ProviderFamily: String, Codable, CaseIterable, Sendable {
    case official, thirdParty
}

public enum AuthKind: String, Codable, Sendable { case none, bearer, localCodex }

public struct AuthConfig: Codable, Equatable, Sendable {
    public var kind: AuthKind
    public var keychainService: String?    // where the secret lives, not the secret
    public var keychainAccount: String?
    public static let none = AuthConfig(kind: .none)
}

public struct AlertRule: Codable, Equatable, Sendable {
    public var lowRemaining: Double         // notify below this %
    public var maxConsecutiveFailures: Int  // notify after N failed refreshes
    public var notifyOnAuthError: Bool
}
```

> **Security rule, enforced by design:** the config never stores secrets. It stores *coordinates* (`keychainService` + `keychainAccount`) telling the app where to read the secret from the macOS Keychain at fetch time. See [Step 4](#step-4--persistence--secrets).

`ProviderConfiguration` / `ProviderSettings` are the domain-level, encodable description of a configured provider (id, name, family, type, poll interval, threshold, auth, optional official/relay sub-configs). The executable target has a richer `ProviderDescriptor` mirror; keep the persisted shape stable and additive.

---

## Step 3 — The provider abstraction

In the executable target, define the contract every concrete provider implements. This is the seam the factory and scheduler talk to.

```swift
import Foundation
import StatsUsageDomain

protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async throws -> UsageSnapshot
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot
}

extension UsageProvider {
    // Default: ignore forceRefresh unless the provider overrides it.
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot { try await fetch() }
}
```

A normalized error type gives the UI consistent, user-readable diagnostics:

```swift
enum ProviderError: Error, LocalizedError {
    case missingCredential(String)
    case unauthorized
    case unauthorizedDetail(String)
    case rateLimited
    case invalidResponse(String)
    case commandFailed(String)
    case timeout(String)
    case unavailable(String)
    var errorDescription: String? { /* map each to a sentence */ }
}
```

The `Application`/`Providers` layer wants a smaller contract (`UsageProviderFetching`) that returns a minimal `UsageQuotaSnapshot` (used/limit/capturedAt). Bridge with an adapter so the scheduler depends only on the slim contract:

```swift
struct UsageProviderFetchingAdapter: UsageProviderFetching {
    private let provider: any UsageProvider
    let providerID: UsageProviderIdentity
    func fetchUsageSnapshot(forceRefresh: Bool) async throws -> UsageQuotaSnapshot {
        let snap = try await provider.fetch(forceRefresh: forceRefresh)
        return UsageQuotaSnapshot(
            used: snap.used ?? max(0, (snap.limit ?? 0) - (snap.remaining ?? 0)),
            limit: snap.limit,
            capturedAtUnixSeconds: snap.updatedAt.timeIntervalSince1970
        )
    }
}
```

`ProviderDescriptor` (executable target) is the full configured-provider record:

```swift
struct ProviderDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var family: ProviderFamily
    var type: ProviderType
    var enabled: Bool
    var pollIntervalSec: Int
    var threshold: AlertRule
    var auth: AuthConfig
    var showInMenuBar: Bool?
    var baseURL: String?
    var officialConfig: OfficialProviderConfig?
    var relayConfig: RelayProviderConfig?
    var kimiConfig: KimiProviderConfig?
    // computed: showsInMenuBar (default true), isRelay (type in relay/open/dragon)
}
```

---

## Step 4 — Persistence & secrets

Two stores: **config** (plain JSON, non-secret) and **Keychain** (secrets). Both live in the executable target's `Services/`.

### 4.1 Config store

Config is one JSON document at `~/Library/Application Support/StatsUsage/`. The store is engineered to **never lose user state**, because provider config drift and partial corruption are real:

- **Lossy-tolerant decoding.** `AppConfig` decodes its `providers` array with a custom container that *skips* individual entries it can't decode (counting how many were dropped) instead of failing the whole file. New app versions can therefore read configs that contain provider types they don't recognize.
- **Multiple snapshot copies.** On save, write the primary file plus shadow/backup/last-known-good copies. On load, try them in order: primary → recovery → last-known-good → reconstruct from persisted official profiles → finally `AppConfig.default`.
- **Preserve-on-fallback.** If a file is invalid or lossy, the raw bytes are stashed as a "preserved fallback candidate" so nothing is silently discarded.
- **Legacy import.** Migrate older app/keychain names on first run (the reference app migrated `OhMyUsage` → `oh-myusage`).

Skeleton:

```swift
final class ConfigStore {
    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) { /* resolve ~/Library/Application Support */ }
    func load() throws -> AppConfig          // tries every snapshot, repairs, returns default if all fail
    func save(_ config: AppConfig) throws    // writes primary + shadow + last-known-good
    func reset() throws                      // remove all snapshots + import markers
    private(set) var lastLoadWasLossy = false
}
```

`AppConfig` itself:

```swift
struct AppConfig: Codable, Equatable {
    var language: AppLanguage                 // .zhHans / .en
    var resourceMode: ResourceMode            // background 3/5/10/15 min poll cadence
    var launchAtLoginEnabled: Bool
    var showOfficialAccountEmailInMenuBar: Bool
    var statusBarProviderID: String?          // which provider drives the menu-bar text
    var statusBarMultiUsageEnabled: Bool
    var statusBarMultiProviderIDs: [String]
    var statusBarAppearanceMode: StatusBarAppearanceMode  // followWallpaper / dark / light
    var statusBarDisplayStyle: StatusBarDisplayStyle      // iconPercent / barNamePercent
    var providers: [ProviderDescriptor]
    static let `default` = AppConfig(/* seed from ProviderDefaultCatalog */)
}
```

`ResourceMode` maps a friendly name to a poll interval in seconds and decodes legacy aliases ("responsive"→3m, "balanced"→5m, "lowPower"→15m) so old settings survive.

### 4.2 Keychain service

A thin wrapper over the `Security` framework storing per-provider secrets keyed by `(service, account)` — exactly the coordinates held in `AuthConfig`. Provide `read`, `write`, `delete`, and a "snapshot/reuse" cache so a single refresh round doesn't hammer the Keychain (a real perf win when you have many providers).

```swift
final class KeychainService {
    func setSecret(_ value: String, service: String, account: String) throws
    func secret(service: String, account: String) throws -> String?
    func deleteSecret(service: String, account: String) throws
    // Optional: beginSnapshot()/endSnapshot() to memoize reads within one refresh cycle.
}
```

Credential acquisition strategies (used by relay + some official providers):

- **`Manual Preferred`** — use the saved Keychain secret first.
- **`Browser Preferred`** — try a browser-extracted cookie/bearer, fall back to saved.
- **`Browser Only`** — only use browser-extracted credentials.

Browser extraction (reading Safari/Chrome cookie stores) is optional and gated behind macOS permissions; isolate it in `BrowserCookieService` / `BrowserCredentialService` so providers stay simple.

---

## Step 5 — Implement providers (official + relay)

There are two families with very different mechanics.

### 5.1 Official providers

These read a specific service's quota. They typically support several **source modes** (`api`, `cli`, `web`, `auto`) and reuse shared "official runtime" helpers:

- **`OfficialProviderFetchRuntime`** — wraps a `load` closure with a short TTL cache + a fetch "gate" that coalesces concurrent refreshes.
- **`OfficialProviderAuthRuntime`** — handles "request, and if the token is near expiry, refresh it and retry."
- **`OfficialSnapshotFallback`** — on failure, return the last good snapshot marked `valueFreshness == .cachedFallback`.

Sketch of a Gemini-style provider (Cloud Code Assist endpoints, OAuth credential refresh):

```swift
final class GeminiProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let cacheTTL: TimeInterval = 15
    private let refreshBuffer: TimeInterval = 5 * 60

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await OfficialProviderFetchRuntime.fetch(
            forceRefresh: forceRefresh, cacheLookupKey: descriptor.id,
            ttl: cacheTTL, cache: cache, gate: gate,
            load: { try await self.loadSnapshot() }
        )
    }

    private func loadSnapshot() async throws -> UsageSnapshot {
        let cfg = descriptor.officialConfig ?? .default(type: .gemini)
        switch cfg.sourceMode {
        case .api, .auto: return try await loadFromAPI()
        case .cli:  throw ProviderError.unavailable("CLI source not supported")
        case .web:  throw ProviderError.unavailable("Web source not supported")
        }
    }

    private func loadFromAPI() async throws -> UsageSnapshot {
        // 1. read OAuth creds (from disk/keychain)
        // 2. OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh {
        //      POST loadCodeAssist → resolve project id
        //      POST retrieveUserQuota → parse windows
        //    }
        // 3. map to UsageSnapshot(quotaWindows: [...], sourceLabel: "API", ...)
    }
}
```

The important pattern: **provider-local code only owns request building, endpoint/auth specifics, response parsing, and provider-only fallback rules.** Everything reusable lives in the shared runtimes.

### 5.2 Relay providers (the JSON-template engine)

This is the most reusable and elegant part. Instead of hand-coding each NewAPI-style proxy site, you describe it as a **JSON manifest** under `Resources/RelayAdapters/`, and one generic `RelayProvider` interprets it.

A manifest (`generic-newapi.json`):

```json
{
  "id": "generic-newapi",
  "displayName": "Generic New API",
  "match": { "hostPatterns": ["*"], "defaultBalanceChannelEnabled": true },
  "setup": { "requiredInputs": ["displayName", "baseURL", "balanceAuth", "userID"] },
  "authStrategies": [
    { "kind": "savedBearer" }, { "kind": "browserBearer" },
    { "kind": "savedCookieHeader" }, { "kind": "browserCookieHeader" }
  ],
  "balanceRequest": {
    "method": "GET", "path": "/api/user/self",
    "authHeader": "Authorization", "authScheme": "Bearer",
    "userIDHeader": "New-Api-User"
  },
  "tokenRequest": {
    "usagePath": "/api/usage/token/",
    "subscriptionPath": "/v1/dashboard/billing/subscription",
    "billingUsagePath": "/v1/dashboard/billing/usage"
  },
  "extract": {
    "success": "success",
    "remaining": "data.quota",
    "used": "data.used_quota",
    "limit": "add(data.quota,data.used_quota)",
    "unit": "quota",
    "accountLabel": "coalesce(data.group,\"Default Plan\")"
  },
  "postprocessID": "quotaDisplayStatus"
}
```

The relay subsystem is decomposed into small, single-purpose seams (keep `RelayProvider` itself a thin orchestration shell):

| Seam | Responsibility |
| --- | --- |
| `RelayAdapterRegistry` | Load & index manifests from the bundle |
| `RelayRequestResolver` | Build URLs/paths from the manifest |
| `RelayCredentialResolver` | Pick a credential per `authStrategies` + strategy preference |
| `RelayHTTPClient` | Transport (URLSession) |
| `RelayBalanceChannelExecutor` / `RelayTokenChannelExecutor` | Run the balance/token requests |
| `RelayResponseInterpreter` | Apply `extract` rules to JSON |
| `RelayJSONExpressionEvaluator` | Evaluate `data.quota`, `add(a,b)`, `coalesce(x,"y")` against a JSON tree |
| `RelayRecoveryPolicy` | Decide retry / browser-fallback on failure |

The `RelayJSONExpressionEvaluator` is the heart: it parses dotted key-paths and a tiny set of functions (`add`, `coalesce`, string literals) and resolves them against the decoded JSON. That single evaluator is what lets a *non-programmer* onboard a new site by editing JSON.

### 5.3 The provider factory

A registry maps each `ProviderType` to a closure that builds the concrete provider, injecting shared dependencies (Keychain, browser services). A `precondition` asserts **every** `ProviderType` case is registered — so adding an enum case without wiring it is a loud crash in tests, not a silent gap.

```swift
struct ProviderFactoryRegistry {
    struct Dependencies { let keychain: KeychainService; /* browser services... */ }
    typealias Maker = (ProviderDescriptor, Dependencies) -> UsageProvider
    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(Set(makers.keys) == Set(ProviderType.allCases),
                     "Every ProviderType must be registered")
    }

    func makeProvider(for d: ProviderDescriptor, dependencies: Dependencies) -> UsageProvider {
        makers[d.type]!(d, dependencies)
    }

    private static func makeDefaultMakers() -> [ProviderType: Maker] {
        [
            .gemini: { d, _ in GeminiProvider(descriptor: d) },
            .codex:  { d, deps in CodexProvider(descriptor: d, keychain: deps.keychain) },
            .relay:  Self.makeRelayProvider, .open: Self.makeRelayProvider, .dragon: Self.makeRelayProvider,
            // ... one entry per ProviderType ...
        ]
    }
}
```

---

## Step 6 — The refresh engine

Lives in `StatsUsageApplication`. The goal: keep N providers fresh **with one coalesced loop**, respect each provider's interval, back off on failure, add startup jitter, and refresh instantly when a local CLI session finishes — all without spawning a timer per provider.

### 6.1 Backoff

```swift
package enum BackoffPolicy {
    package static func delaySeconds(baseInterval: Int, consecutiveFailures: Int) -> Int {
        if consecutiveFailures <= 0 { return baseInterval }
        if consecutiveFailures == 1 { return 120 }   // 2 min after first failure
        return 300                                    // 5 min after repeated failures
    }
}
```

### 6.2 The scheduler

`ProviderRefreshScheduler` is `@MainActor` and holds a single `pollLoopTask`. Key ideas:

- It tracks `nextDueAt[providerID]`. Each loop iteration it sleeps until the **earliest** due time, then refreshes every provider that is due and not already in flight.
- It seeds each provider's first run with **random startup jitter** (0–20s) so a cold launch doesn't fire every request at once.
- After a refresh completes, it asks a `failureCountProvider` for that provider's consecutive failures and schedules the next run via `BackoffPolicy`.
- It tracks `inFlightRefreshTasks` so a slow provider is never double-scheduled.
- A separate **local-session monitor** loop watches for Codex/Claude CLI session-completion signals and triggers an immediate refresh of just those providers (with a minimum gap so it can't thrash).
- "Background" providers (not the one currently shown) can be polled on a longer interval than the active one.

```swift
@MainActor
package final class ProviderRefreshScheduler {
    package func restart(providers: [ProviderRefreshScheduleDescriptor]) { /* compute due times + jitter, start pollLoop */ }
    package func stop() { /* cancel loop + in-flight tasks */ }
    package func refreshNow(providers: [...]) { /* force-refresh all enabled */ }

    private func pollLoop(runID: UUID) async {
        while !Task.isCancelled, pollRunID == runID {
            // prune disabled providers; find earliest dueAt; sleep until then;
            // start refresh for each due provider; on finish, reschedule via BackoffPolicy
        }
    }
}
```

The `ResourceMode` from config feeds `backgroundProviderPollIntervalSeconds`, so "low power" mode literally widens the loop's cadence.

---

## Step 7 — The app shell & menu bar UI

### 7.1 Entry point — a menu-bar-only app

A SwiftUI `App` with an empty `Settings` scene, plus an `NSApplicationDelegate` adaptor that does the real work:

```swift
import AppKit
import SwiftUI

@main
struct StatsUsageApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
```

The delegate makes it an **accessory** app (no Dock icon), registers bundled fonts/icon, enforces a single instance, and constructs the view model + status bar controller:

```swift
@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppFonts.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)              // menu bar only
        guard SingleInstanceLock.shared.acquire() else {   // flock on /tmp/<id>.lock
            SingleInstanceActivationBridge.notifyExistingInstance()
            NSApp.terminate(nil); return
        }
        let vm = AppViewModel()
        statusBarController = StatusBarController(viewModel: vm)
        // present post-update release notes if version changed
    }
}
```

`SingleInstanceLock` takes an exclusive `flock` on a file in `/tmp`. If a second copy launches, it posts a `DistributedNotificationCenter` message that tells the running instance to surface its settings window, then quits.

> Set `LSUIElement = true` in `Info.plist` (done by the packaging script) so the app has no Dock presence even before `setActivationPolicy` runs.

### 7.2 The status item — render only on change

`StatusItemController` wraps an `NSStatusItem`. The critical optimization: it computes a **render signature** (the entries' names/values/percentages/icons + style) and only redraws the menu-bar button when the signature changes. A resident app that redraws every poll is a battery drain; this makes redraws content-driven.

```swift
@MainActor
final class StatusItemController {
    private var lastRenderSignature: RenderSignature?
    @discardableResult
    func render(entries: [StatusBarDisplayEntry], style: ..., foregroundStyle: ..., fallbackImage: NSImage?) -> Bool {
        let signature = Self.renderSignature(entries: entries, style: style, ...)
        guard signature != lastRenderSignature else { return false }   // no-op when unchanged
        // draw attributed string (icon + name + percent) or fallback image
        lastRenderSignature = signature
        return true
    }
}
```

### 7.3 The controller & popover

`StatusBarController` is the orchestrator: it owns the status item, a `MenuPanelController` (an `NSPopover`/panel hosting SwiftUI), and a `StatusBarAppearanceController` (resolves light/dark text by sampling the wallpaper when in *follow wallpaper* mode). It:

- builds the menu-bar entries from the view model's snapshots via `StatusBarDisplaySourceBuilder` + `StatusBarDisplayPresenter`,
- toggles the popover on click and hosts `MenuContentView`,
- runs a faster "visible refresh clock" while the panel is open (countdowns tick) and slows down when closed,
- chooses per-provider icons (with `_dark` variants) from the bundle, caching `NSImage`s.

### 7.4 The view model

`AppViewModel` is the `@MainActor @Observable` hub the UI binds to. In the reference app it is large, so it delegates to many small **coordinators** (refresh, official-profile lifecycle/state/sync, account import/switch, credential lookup, reset, status-bar prefs, configuration mutation, update). Treat `AppViewModel` as a façade and put real logic in coordinators — it keeps each piece testable and stops the view model becoming a 3,000-line monolith.

State it exposes: `config`, `snapshots: [String: UsageSnapshot]`, `errors`, `codexSlots`/`claudeSlots` (multi-account), permission flags, persistence status. A backing `AppSessionStore` separates persisted vs session state.

### 7.5 The menu UI (SwiftUI)

`MenuContentView` + card views + **presenters**. The presenter pattern is pervasive: pure, testable functions turn a `UsageSnapshot` into display strings/percentages (`MenuQuotaPresenter`, `MenuCardStatusPresenter`, `MenuSubtitlePresenter`, `MenuDashboardPresenter`). Views stay dumb; presenters carry the logic and get unit tests.

---

## Step 8 — The settings window

A standard `NSWindow` hosting a SwiftUI sidebar + detail layout (`SettingsRootView` → sidebar + pane container). Tabs:

- **General** — language, launch at login, resource mode.
- **Menu Bar** — which provider(s) drive the menu-bar text, display style, appearance mode.
- **Official** — enable/configure official providers; OAuth import; multi-account slots (Codex/Claude) with switch.
- **Relay** — add a third-party site from a template, fill in base URL / token / userID / GroupId, pick a credential strategy, preview the result.
- **Local Data / Usage** — local usage history & analytics, cache diagnostics.
- **About / Donate** — version, update check, links.

Keep **editing/draft** state (`SettingsDraftModels`) separate from persisted config; commit drafts through the configuration coordinator → `ConfigStore.save`. Put per-tab screens in `UI/Settings/` and shared primitives in shared helper files, not in the root composition. This is the "don't push logic back into the root view" rule that keeps the settings tree maintainable.

---

## Step 9 — Alerts & notifications

`AlertEngine` is a pure function over (previous state, new snapshot, `AlertRule`) that decides whether to fire: low remaining %, N consecutive failures, or auth error. `NotificationService` wraps `UNUserNotificationCenter` (request authorization, post). Keeping the decision logic pure means you unit-test thresholds without touching the notification system.

---

## Step 10 — Self-update

Because you distribute outside the App Store, build a small updater. The design uses a **`latest.json` manifest** published as a GitHub Release asset:

```json
{
  "version": "2.2.2",
  "pub_date": "2026-06-05T12:00:00Z",
  "release_url": "https://github.com/<owner>/StatsUsage/releases/tag/v2.2.2",
  "notes_url":  "https://github.com/<owner>/StatsUsage/releases/tag/v2.2.2",
  "assets": {
    "macos_zip": { "url": "...StatsUsage-macOS.zip", "sha256": "<64 hex>", "size": 12345 },
    "macos_dmg": { "url": "...StatsUsage.dmg",        "sha256": "<64 hex>", "size": 23456 }
  }
}
```

`AppUpdateService` (an `actor`) does:

1. **`fetchLatestRelease()`** — GET the manifest from `releases/latest/download/latest.json`; compare versions.
2. **`prepareUpdate(_:)`** — download the ZIP to a temp dir, verify `sha256` with `CryptoKit` (`AppUpdateError.checksumMismatch` on mismatch), unzip, locate the `.app`.
3. **`installPreparedUpdate(_:over:)`** — replace the running `.app` in place (only valid when running from an `.app` bundle, else `unsupportedInstallLocation`).

Show release notes after a successful update by persisting "I just updated to vX" and consuming it on next launch (`PostUpdateReleaseNotesStore`). Keep a legacy metadata URL fallback if you ever rename the repo.

---

## Step 11 — Packaging (DMG/ZIP, signing, notarization)

SwiftPM produces a bare executable, not an `.app`. A `scripts/package_dmg.sh` script assembles the bundle. The flow:

1. **Build universal release:** `swift build -c release --arch arm64 --arch x86_64`.
2. **Locate the binary** under `.build/.../release/StatsUsage`.
3. **Assemble `StatsUsage.app/Contents/`:** copy the binary to `MacOS/`, copy the SwiftPM resource bundle (`StatsUsage_StatsUsage.bundle`) and `PackageFrameworks/` into `Resources/`/`Frameworks/`.
4. **Generate the icon:** `sips` to resize `app_icon_source.png` into an `.iconset`, then `iconutil -c icns`.
5. **Write `Info.plist`** with `LSUIElement=true`, `LSMinimumSystemVersion=14.0`, `CFBundleIdentifier=com.statsusage.app`, version pulled from the `VERSION` file (or `APP_VERSION` env).
6. **Strip xattrs** (`xattr -cr`) so stray FinderInfo doesn't invalidate the bundle.
7. **Code sign:**
   - **Ad-hoc** by default (`codesign --force --deep --sign -`) — works for open-source distribution; users right-click→Open past Gatekeeper.
   - **Developer ID** if `DEVELOPER_ID_APPLICATION`/`CODESIGN_IDENTITY` is set (`--options runtime --timestamp`).
8. **Notarize** (optional, if creds present): zip the app, `xcrun notarytool submit --wait`, then `xcrun stapler staple`. Supports keychain profile, App Store Connect API key, or Apple ID + app-specific password.
9. **Build artifacts:** a ZIP (`ditto -c -k --keepParent`) and a DMG (`hdiutil create` → mount → style window via `osascript` → `hdiutil convert -format UDZO`). Output to `dist/`.

Usage:

```bash
./scripts/package_dmg.sh                      # ad-hoc, version from VERSION file
APP_VERSION=0.1.0 ./scripts/package_dmg.sh    # explicit version
NOTARIZE_DMG=1 DEVELOPER_ID_APPLICATION="Developer ID Application: You (TEAMID)" \
  NOTARYTOOL_PROFILE=my-profile ./scripts/package_dmg.sh   # signed + notarized
```

---

## Step 12 — CI/CD with GitHub Actions

Two workflows under `.github/workflows/`.

**`ci.yml`** — on every push/PR, on `macos-latest`, set up Swift 6.2 and run `swift build` then `swift test`.

```yaml
name: CI
on: { push: { branches: ["**"] }, pull_request: {} }
jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with: { swift-version: "6.2.0" }
      - run: swift build
      - run: swift test
```

**`release.yml`** — on a `v*` tag (or manual dispatch with a version):

1. Resolve & validate the version (`vX.Y.Z`), write it to `VERSION`.
2. Run `package_dmg.sh` to build the DMG + ZIP.
3. Generate `latest.json` (compute `sha256` + sizes of the artifacts).
4. **Validate the manifest** with a Python step (URLs match the tag, sha256 is 64 hex, sizes positive, ISO‑8601 UTC date).
5. `gh release create`/`upload` the DMG, ZIP, and `latest.json`.
6. **Post-publish check:** fetch the published `latest.json` and assert its version matches, with retries.

This closes the update loop: the workflow produces exactly the manifest `AppUpdateService` consumes, and verifies it before and after publishing.

---

## Step 13 — Testing strategy

Use **XCTest** (`final class ...Tests: XCTestCase`, `test...` methods). The reference suite has ~130 test files; the categories worth copying:

- **Provider parsing tests** — feed recorded JSON fixtures into each provider/relay manifest and assert the resulting `UsageSnapshot` (windows, percentages, reset times, freshness). Store fixtures under `Tests/.../Fixtures/` (excluded from compilation).
- **Config store tests** — golden config, lossy config (assert dropped-entry counting + recovery), legacy import. Keep `golden-*.json` / `lossy-*.json` fixtures.
- **Scheduler/backoff tests** — inject a fake `sleepAction` and clock so you can assert due-time math, jitter bounds, and backoff transitions deterministically (no real waiting).
- **Presenter tests** — pure presenter input→output (the bulk of UI correctness, no view rendering needed).
- **Architecture boundary tests** — assert layering rules hold. For example, scan source files and fail if `Domain` imports `AppKit`/`SwiftUI`, or if new logic creeps into a file that should stay a thin shell. This is how the project *enforces* its own structure over time.
- **Keychain tests** — use a test service name and clean up in `tearDown`.

Run `swift test` locally and in CI before every release.

---

## 17. Recommended build order (milestones)

Don't build all 8 targets on day one. Grow it:

1. **M0 — Walking skeleton.** `Domain` (`UsageSnapshot`, `ProviderType`) + executable. A menu-bar app (`LSUIElement`) showing a hardcoded percentage. Prove `setActivationPolicy(.accessory)` + `NSStatusItem` work.
2. **M1 — One real provider.** `UsageProvider` protocol + one concrete provider (pick the easiest API you have a token for) + `KeychainService`. Click the menu item, see a live number.
3. **M2 — Config + persistence.** `ConfigStore` + `AppConfig` + a minimal settings window to enable/disable the provider and set a poll interval. Add the lossy-decode + last-known-good behavior now, before you have lots of data to lose.
4. **M3 — Refresh engine.** Extract `ProviderRefreshScheduler` + `BackoffPolicy` into `Application`. Multiple providers refreshing on one loop.
5. **M4 — Relay templates.** `RelayProvider` + `RelayJSONExpressionEvaluator` + the registry + one manifest. This is where the app becomes broadly useful.
6. **M5 — Polish.** Quota windows + reset countdowns, appearance modes, alerts/notifications, multi-account slots, presenters + their tests.
7. **M6 — Ship.** `package_dmg.sh`, the two CI workflows, `AppUpdateService` + `latest.json`. Cut `v0.1.0`.

Each milestone is independently demoable, which keeps momentum and makes regressions obvious.

---

## 18. Conventions, concurrency & gotchas

- **Swift 6 strict concurrency.** Domain models are `Sendable` value types. UI/AppKit-touching types are `@MainActor`. The scheduler is `@MainActor` but its sleep/closures are `@Sendable`. Providers are `Sendable` (some use `@unchecked Sendable` with internal synchronization around a cache). Expect to annotate deliberately — the compiler will not let you share mutable state across actors by accident.
- **Style:** 4-space indent, `UpperCamelCase` types, `lowerCamelCase` members, one primary type per file named after the type. No linter is configured — match surrounding style.
- **Keep shells thin.** `RelayProvider`, `AppViewModel`, and the root settings view are *orchestration shells*. New parsing/auth/branching goes in a dedicated seam, not piled into the shell. Boundary tests guard this.
- **Additive persistence only.** Every new `Codable` field uses `decodeIfPresent` + default. Never make an old config undecodable.
- **Secrets never in config.** Only Keychain coordinates are persisted. Browser-credential reading is permission-gated and isolated.
- **Render on change only.** The menu-bar render signature and snapshot caches exist for battery life; don't bypass them with unconditional redraws.
- **Every `ProviderType` must be registered** in the factory — the `precondition` turns omissions into immediate test failures.
- **Localization.** The reference app defaults to Simplified Chinese with English fallback; route user-facing strings through a `Localization` helper from the start if you want bilingual UI.

---

## 19. Final directory layout

```text
StatsUsage/
├── Package.swift
├── VERSION
├── README.md
├── LICENSE                      # MIT
├── .gitignore
├── .github/workflows/
│   ├── ci.yml
│   └── release.yml
├── scripts/
│   └── package_dmg.sh
├── docs/
│   ├── PROVIDERS.md             # supported services
│   ├── EXTENDING.md             # how to add a provider / relay template / setting
│   └── RELEASE_CHECKLIST.md
├── Sources/
│   ├── StatsUsageDomain/        # pure models & enums (imports only Foundation)
│   ├── StatsUsageInfrastructure/# credential store seam
│   ├── StatsUsageProviders/     # fetching contract
│   ├── StatsUsageApplication/   # scheduler, backoff, analytics, diagnostics
│   ├── StatsUsagePresentation/  # view-state models
│   ├── StatsUsageFeatures/      # feature assembly
│   ├── StatsUsageBootstrap/     # composition root
│   └── StatsUsage/              # the executable app
│       ├── App/                 # lifecycle, status bar, view model, coordinators
│       ├── UI/                  # SwiftUI views, Presenters/, Settings/
│       ├── Services/            # ConfigStore, KeychainService, AppUpdateService, ...
│       ├── Providers/           # concrete providers + relay engine
│       ├── Models/              # ProviderDescriptor, AppConfig, catalogs
│       ├── Utils/               # Localization, helpers
│       └── Resources/           # icons, fonts, RelayAdapters/*.json
└── Tests/StatsUsageTests/
    ├── *Tests.swift
    └── Fixtures/                # JSON fixtures (excluded from compilation)
```

---

### Appendix — the one-paragraph mental model

StatsUsage is a **menu-bar accessory app** whose single job is to keep a dictionary of `[providerID: UsageSnapshot]` fresh and render it. A **scheduler** drives a **factory-built set of providers** (official APIs, local CLIs, or JSON-described relay sites) on one coalesced, jittered, backoff-aware poll loop. Each provider returns a richly annotated snapshot (value + freshness + health + reset confidence) which **pure presenters** turn into menu-bar text, popover cards, and settings rows. **Config** is non-secret JSON with paranoid recovery; **secrets** live in the Keychain. The app **signs/packages itself** into a DMG and **updates itself** from a GitHub-hosted `latest.json`. Layered SwiftPM targets + boundary tests keep all of that from collapsing into one giant file as it grows.

*Happy building.*
