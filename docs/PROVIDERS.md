# Providers

QuotaBar supports two families of providers.

## Official (first-party)

Read a specific service's quota from local login state, OAuth tokens, or official
endpoints. Each can expose several source modes (`api`, `cli`, `web`, `auto`).

| Type | Status | Notes |
| --- | --- | --- |
| `codex` | Local account status | Reads `~/.codex/auth.json`; session window is a local estimate |
| `claude` | Local account status | Same local reader as Codex for now |
| `gemini` | Experimental local account status | Reads Gemini CLI OAuth state and Cloud Code Assist quota endpoints |
| `copilot`, `cursor`, `windsurf`, `jetbrains`, `kiro`, `trae`, `zai`, `amp`, `microsoftCopilot`, `ollamaCloud`, `opencodeGo`, `openrouterCredits`, `openrouterAPI`, `kimi` | Placeholder | Registered against `PlaceholderProvider`; report as not-yet-implemented |

The `PlaceholderProvider` keeps the factory's "every `ProviderType` is registered"
precondition satisfiable while honestly reporting the provider as unavailable.

QuotaBar labels Codex, Claude, and Gemini as experimental because they depend on
locally installed CLI authentication formats and provider endpoints that can change.
Credential files are read-only by default; users must explicitly opt in before
QuotaBar persists refreshed tokens back to those files.

## Relay (third-party, NewAPI-style)

Described entirely by a JSON manifest under `Resources/RelayAdapters/` and
interpreted by one generic `RelayProvider`. Provider types `relay`, `open`, and
`dragon` all use the relay engine. See [EXTENDING.md](EXTENDING.md) to onboard a
site without writing code.

Bundled manifests:

- `generic-newapi.json` — generic New API balance + token channels.

## Trust metadata

Every snapshot carries:

- **`valueFreshness`** — `live` / `cachedFallback` / `empty`.
- **`fetchHealth`** — `ok` / `authExpired` / `rateLimited` / `endpointMisconfigured` / `unreachable`.
- **Per-window `resetSource` + `confidence`** — inferred from the source label when
  not supplied (`api`→official/confirmed, `web`→webObserved/estimated, `cli`→localEstimate/estimated).
