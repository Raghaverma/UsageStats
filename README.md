# StatsUsage

A menu-bar–only macOS app that unifies AI subscription usage that is otherwise
scattered: official subscription quota, rolling usage windows with reset
countdowns, third-party "relay" balances, and local desktop-client account status —
each value annotated with *freshness*, *health*, and *reset confidence* so you can
trust what you see.

Built as a layered Swift Package with **no third-party dependencies**.

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6.2+ toolchain (Xcode 16.x)

## Quick start

```bash
swift build          # compile
swift run            # launch from source (a menu-bar icon appears)
swift test           # run the XCTest suite
./scripts/package_dmg.sh   # build a distributable DMG + ZIP into dist/
```

> Running `swift test` requires the full Xcode toolchain (for XCTest). If your
> active developer dir is the Command Line Tools, prefix with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Architecture

The package is layered by responsibility; dependency arrows point inward toward the
dependency-free `Domain` contract:

| Target | Responsibility |
| --- | --- |
| `StatsUsageDomain` | Pure `Sendable` models & enums (`UsageSnapshot`, `ProviderType`, …) |
| `StatsUsageApplication` | Refresh scheduler, backoff policy, alert engine |
| `StatsUsagePresentation` | View-state models & pure presenters |
| `StatsUsageProviders` | Slim fetching contract |
| `StatsUsageFeatures` | Feature assembly |
| `StatsUsageBootstrap` | Composition root |
| `StatsUsageInfrastructure` | Credential-store seam |
| `StatsUsage` (executable) | AppKit status item, SwiftUI UI, concrete providers, relay engine, stores |

A boundary test (`ArchitectureBoundaryTests`) enforces that `Domain` and
`Application` never import AppKit/SwiftUI.

## Mental model

StatsUsage keeps a dictionary of `[providerID: UsageSnapshot]` fresh and renders it.
A **scheduler** drives a **factory-built set of providers** (official APIs, local
CLIs, or JSON-described relay sites) on one coalesced, jittered, backoff-aware poll
loop. Each provider returns a richly annotated snapshot which **pure presenters**
turn into menu-bar text and popover cards. Config is non-secret JSON with paranoid
recovery; secrets live in the Keychain. The app signs/packages itself into a DMG and
updates itself from a GitHub-hosted `latest.json`.

See [`docs/`](docs/) for extending the app and the release checklist.

## License

MIT — see [LICENSE](LICENSE).
