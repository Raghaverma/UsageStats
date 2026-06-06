# Release checklist

1. **Green build** — `swift build && swift test` passes locally (use
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if needed).
2. **Bump the version** — set `VERSION` (or pass `APP_VERSION`). Use semantic
   `X.Y.Z`.
3. **Smoke-test the bundle** — `./scripts/package_dmg.sh`, then open
   `dist/QuotaBar.app` and confirm the menu-bar item appears and refreshes.
4. **Tag & push** — `git tag vX.Y.Z && git push origin vX.Y.Z`. The `release.yml`
   workflow then:
   - builds the universal DMG + ZIP,
   - generates and validates `latest.json` (URLs match the tag, sha256 64 hex,
     sizes positive, ISO-8601 UTC date),
   - creates the GitHub release with all three assets,
   - re-fetches the published `latest.json` and asserts the version matches.
5. **Verify the update loop** — a prior install should detect the new version via
   `AppUpdateService.fetchLatestRelease(current:)`.

## Signing & notarization

- Ad-hoc signing is the default (open-source distribution; users right-click → Open).
- For Developer ID: set `DEVELOPER_ID_APPLICATION` (or `CODESIGN_IDENTITY`).
- For notarization: `NOTARIZE_DMG=1` plus `NOTARYTOOL_PROFILE` (a stored
  `notarytool` keychain profile).
