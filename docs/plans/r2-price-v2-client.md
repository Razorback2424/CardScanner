# Stage 2 — Production v2 price client & release preparation

**Status, November 27, 2026.** The v2 price client (PR #71), canonical catalog hostname / release-gate preparation (PR #78), and pre-switch client hardening (PR #80) are complete in source. Production builds remain on **v1** (`https://catalog.scan-stash.com/market-prices/v1`) until all live Stage 2 acceptance gates below pass. Production DNS, CloudKit settings, JustTCG proxy/App Check settings, and catalog authority modes are unchanged.

## Client contract

The shared TCGCSV product-price actor ([`TCGCSVProductPriceSource.swift`](../../TradingCardScanner/Services/TCGCSVProductPriceSource.swift)) consumes either `/market-prices/v1` or `/market-prices/v2` through the existing `TCGCSV_PRICE_BASE_URL` Info.plist build setting:

- **Schema v2 integrity & forward compatibility:** Validates `schemaVersion == 2`, content-addressed `build` SHA-256 identity (cross-checked against the Python-generated fixture [`TCGCSVPriceV2ManifestParity.json`](../../TradingCardScannerTests/Fixtures/TCGCSVPriceV2ManifestParity.json)), bounded relative paths (accepting any positive integer TCGPlayer category ID and future `scopes/<game>.json` entries up to 20,000 files / 4 MiB manifest / 512 MiB build), paired `products`/`prices` entries, and exact byte count and SHA-256 on every group file before decoding.
- **File-backed marker persistence:** Persists `TCGCSVMirrorBuildMarker` checks and v2 manifests in `Application Support/TCGCSVMirrorBuildMarker-v1/` (`isExcludedFromBackup = true`) rather than `UserDefaults`, migrating and cleaning up any legacy `UserDefaults` blob automatically on launch.
- **Same-day corrections:** Distinct `build` hashes invalidate cached groups even when `sourceBuild` is unchanged.
- **Existing cache compatibility:** Existing v1 group snapshots decode with optional `verifiedBuildID: String?`; upgrading to v2 keeps cached prices available offline without restamping original capture dates and persists `verifiedBuildID` on the first successful v2 refresh.
- **Bootstrap and no-downgrade boundary:** A v2-configured client may fall back to sibling `/market-prices/v1` **only** on a confirmed HTTP 404 for `/market-prices/v2/latest.json` before ever accepting v2. Invalid manifests, hash/size mismatches, transport errors, HTTP 5xx outages, and any missing pointer after v2 has been accepted (persisted across relaunch) never downgrade to v1. There is no automatic cross-host fallback to Firebase; infrastructure rollback uses a DNS change to the verified Firebase backup.

## Canonical catalog hostnames & dependency audit (PR #78)

All production catalog origins now use the provider-independent hostname `https://catalog.scan-stash.com`:

| Game | Production base URL | Rollout mode | Key pins |
| --- | --- | --- | --- |
| Pokémon | `https://catalog.scan-stash.com` (`POKEMON_CATALOG_ALLOWED_ORIGIN_HOST = catalog.scan-stash.com`) | `remote-authority` | `pokemon-catalog-production-2026-09-18-01` (unchanged) |
| One Piece | `https://catalog.scan-stash.com` | `remote-authority` (`ONE_PIECE_COLLECTION_WRITES = YES`) | `one-piece-production-2026-10-23-01` (unchanged) |
| Magic | `https://catalog.scan-stash.com` (corrected from `scanstash-catalog-prod.web.app` in [`MagicCatalogProduction.xcconfig`](../../Config/MagicCatalogProduction.xcconfig) and [`MagicCatalogUpdateClient.swift`](../../TradingCardScanner/Services/MagicCatalogUpdateClient.swift)) | `legacy-live` (unchanged) | `pokemon-catalog-production-2026-09-18-01` (unchanged) |
| Yu-Gi-Oh! / Lorcana | Bundled seeds in production; Yu-Gi-Oh! origin validator permits `catalog.scan-stash.com` and `scanstash-catalog-prod.web.app` | Unchanged | Unchanged |

Retained Firebase (`scanstash-catalog-prod.web.app`) and R2 staging (`catalog-staging.scan-stash.com`) references are intentionally scoped to:

- Publishing workflows and R2-first staging origin reads (`.github/workflows/{pokemon,one-piece,magic,yugioh}-catalog.yml`).
- Firebase backup deploy, readback verification, rollback readiness checks, and recovery rehearsals (`scripts/rollback_readiness.py`, `scripts/catalog_hosting_cache.py`, `scripts/market_price_rollback.py`, `scripts/restore_catalog_hosting_site.sh`, `scripts/publish_one_piece_local.py`).
- Explicit build-setting override allowlists in `TCGCSVPriceMirror.baseURL`, `OnePieceCatalogBootstrapConfiguration`, and `YuGiOhCatalogBootstrap.productionEndpoint` for staging and Firebase rollback client validation.
- Staging-only configuration (`Config/PokemonCatalogStaging.xcconfig`, not included in production) and historical documentation.

## Supported pricing verification configurations

Use the existing `TCGCSV_PRICE_BASE_URL` Xcode build setting across all four configurations without modifying tracked `.xcconfig` files during validation:

| Configuration | `TCGCSV_PRICE_BASE_URL` | Intended use |
| --- | --- | --- |
| **Current production (checked-in default)** | `https://catalog.scan-stash.com/market-prices/v1` | Default `Release` / `Debug` builds until live activation gates pass |
| **R2 staging validation** | `https://catalog-staging.scan-stash.com/market-prices/v2` | Direct v2 client validation against R2 staging (`xcodebuild ... TCGCSV_PRICE_BASE_URL=https://catalog-staging.scan-stash.com/market-prices/v2`) |
| **Firebase rollback validation** | `https://scanstash-catalog-prod.web.app/market-prices/v2` | Direct v2 client rehearsal against verified Firebase backup (`xcodebuild ... TCGCSV_PRICE_BASE_URL=https://scanstash-catalog-prod.web.app/market-prices/v2`) |
| **Future production v2** | `https://catalog.scan-stash.com/market-prices/v2` | Authorized production v2 release candidate (`xcodebuild ... TCGCSV_PRICE_BASE_URL=https://catalog.scan-stash.com/market-prices/v2`, then one-line xcconfig activation) |

### Exact one-line production v2 activation change (when authorized)

In [`Config/PokemonCatalogProduction.xcconfig`](../../Config/PokemonCatalogProduction.xcconfig), change only:

```xcconfig
-TCGCSV_PRICE_BASE_URL = https:/$()/catalog.scan-stash.com/market-prices/v1
+TCGCSV_PRICE_BASE_URL = https:/$()/catalog.scan-stash.com/market-prices/v2
```

And update the checked-in default assertion in `OnePieceIntegrationTests.testBuiltAppConfiguresOnePieceMarketPriceFeed` (`TradingCardScannerTests/OnePieceIntegrationTests.swift`) and `.github/workflows/ios-release-gate.yml` in that tightly bounded activation PR.

## Effective application configuration verification

[`.github/workflows/ios-release-gate.yml`](../../.github/workflows/ios-release-gate.yml) verifies compiled `Release` `TradingCardScanner.app/Info.plist` and `xcodebuild -showBuildSettings` on every PR and manual dispatch:

- Confirms `https:/$()/` expands cleanly with no unresolved `$(` or `/$()/` tokens.
- Confirms canonical hostnames (`https://catalog.scan-stash.com`) for Pokémon, One Piece, and Magic; Magic `legacy-live`; byte-identical pinned keys; `NO_CLOUDKIT`; and unchanged empty proxy/App Check/privacy/support URLs.
- Rejects any staging (`catalog-staging.scan-stash.com`) or Firebase (`scanstash-catalog-prod.web.app`) hostname in production-designated Release builds.
- Confirms an explicit `TCGCSV_PRICE_BASE_URL=https://catalog.scan-stash.com/market-prices/v2` override reaches the compiled `TradingCardScanner.app/Info.plist`.
- Supports manual `workflow_dispatch` with `price_endpoint` (`production-v1`, `production-v2`, `staging-v2`, `firebase-rollback-v2`) plus the full-app test job (`full-app-tests`).

## Production v2 activation checklist & open live gates

Do **not** switch production from `v1` to `v2` until every prerequisite below has recorded evidence:

1. [ ] PRs #73–78 reviewed and passing all applicable CI checks.
2. [ ] Live R2-first pricing publication (`yugioh-catalog.yml`) verified end to end.
3. [ ] Live R2-first catalog publication verified end to end (immutable readback before pointer flip, scope parity).
4. [ ] Live Firebase v2 backup verified with preserved historical catalog revisions and earlier v2 price builds.
5. [ ] Live Firebase outage and catch-up rehearsal verified (R2 stays active; Firebase recovers all missed revisions and price builds).
6. [ ] Live Cloudflare staging cache rules verified via `r2-cache-verification.yml` (including negative-cache prevention on 404s).
7. [ ] Live targeted Cloudflare invalidation and canonical client-visible readback verified.
8. [ ] Strict Firebase rollback readiness reporting (`r2-rollback-readiness.yml`, `quota_mode=strict`) reporting `READY`.
9. [ ] Firebase custom-domain HTTPS certificate (`catalog.scan-stash.com` via SNI on Firebase) valid with >=14 days headroom and >=20% storage/bandwidth headroom.
10. [ ] **Firebase rollback client rehearsal (direct host):** Run a v2-configured build directly against `https://scanstash-catalog-prod.web.app/market-prices/v2` (fresh install and existing v2 cache) and confirm identical manifest identity, prices, finishes, capture timestamps, and cache headers compared against `https://catalog-staging.scan-stash.com/market-prices/v2`. *(Note: this verifies backup content and client compatibility only; it does not replace the custom-domain TLS and DNS rollback verification required by PR #77.)*
11. [ ] Full manually dispatched `ios-release-gate.yml` suite and device/upgrade verification passing on the final release candidate.
12. [ ] Seven-day dual-host parallel publication period completed with zero unexplained parity or cache failures before production DNS cutover.

## Release distribution, DNS cutover, and abort sequence

1. **Pre-cutover order:** Because `catalog.scan-stash.com` still points to Firebase before cutover, Firebase **must** already be serving verified v2 builds before shipping the production v2 app release.
2. **Ship v2 app release:** Open the one-line activation PR (`TCGCSV_PRICE_BASE_URL = https:/$()/catalog.scan-stash.com/market-prices/v2`), run the full `ios-release-gate.yml` test suite, archive, and distribute. Legacy `v1` paths remain published indefinitely for older installed app builds.
3. **DNS cutover:** After the v2 app is distributed and the 7-day parallel-hosting period holds with strict parity and rollback readiness `READY`, activate the production ruleset in [`Config/Cloudflare/catalog-cache-rules.json`](../../Config/Cloudflare/catalog-cache-rules.json) and move `catalog.scan-stash.com` DNS to Cloudflare R2.
4. **30-day rollback window:** Keep Firebase backups and continuous rollback readiness checks active for 30 days after cutover.
5. **Aborting activation:** If rollback readiness turns `NOT READY`, parity diverges, or cache/certificate checks fail before release submission, halt the one-line activation PR (production stays on v1). If an infrastructure incident occurs after DNS cutover, revert `catalog.scan-stash.com` DNS back to Firebase Hosting (which serves matching v2 + v1 prices and catalogs).
