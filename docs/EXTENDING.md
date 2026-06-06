# Extending QuotaBar

## Add a relay (third-party) site — no code

Most NewAPI-style proxy sites need **only a JSON manifest**. Drop a file under
`Sources/QuotaBar/Resources/RelayAdapters/<your-site>.json` describing the
endpoints and `extract` rules, then add a provider whose `relayConfig.adapterID`
matches the manifest `id`.

The `extract` block uses a tiny expression language interpreted by
`RelayJSONExpressionEvaluator`:

- **Dotted paths** — `data.quota`, `data.0.name` (numeric segments index arrays).
- **`add(a,b,...)`** — numeric sum of its arguments.
- **`coalesce(a,b,...)`** — first non-null argument (string literals in `"quotes"`).

Example:

```json
"extract": {
  "success": "success",
  "remaining": "data.quota",
  "used": "data.used_quota",
  "limit": "add(data.quota,data.used_quota)",
  "unit": "quota",
  "accountLabel": "coalesce(data.group,\"Default Plan\")"
}
```

Add a parsing test that feeds a recorded JSON fixture into
`RelayResponseInterpreter.interpret(...)` and asserts the resulting snapshot.

## Add an official provider — code

1. Add a case to `ProviderType` in `QuotaBarDomain`.
2. Implement a `UsageProvider` in `Sources/QuotaBar/Providers/`. Keep request
   building / auth / parsing in the provider; reuse shared runtimes for caching and
   credential refresh.
3. Register it in `ProviderFactoryRegistry.makeDefaultMakers()`. The registry's
   `precondition` makes a missing registration a loud test failure.
4. Seed it (disabled by default if it needs setup) in `ProviderDefaultCatalog`.

## Add a setting

1. Add a field to `AppConfig` with a `decodeIfPresent` + default in its custom
   `init(from:)` — **persistence is additive only**, never make an old config
   undecodable.
2. Surface it in the relevant per-tab view under `UI/Settings/`.
3. Commit changes through `AppViewModel.updateConfig { … }`.

## Conventions

- Keep `RelayProvider`, `AppViewModel`, and the settings root as thin orchestration
  shells. New parsing/auth/branching goes in a dedicated seam.
- Secrets never live in config — only Keychain coordinates.
- Relay endpoints must use HTTPS, except explicit localhost development endpoints.
- External CLI credential files are read-only unless the user explicitly enables updates.
- The status item redraws only when its render signature changes; don't bypass it.
