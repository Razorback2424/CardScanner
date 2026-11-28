# Stage 2 — Continuous rollback readiness, content roll-forward, and recovery rehearsals

**Status, November 27, 2026.** Offline implementation and regression tests are complete in PR #77 (`stage2/r2-rollback-readiness`). Live Firebase Monitoring IAM verification, live staging/production readiness runs, and production DNS cutover remain open operational acceptance gates. Production DNS and v1 app client configuration are unchanged.

This document specifies how Firebase Hosting (`scanstash-catalog-prod.web.app`) is continuously verified as a ready 30-day fallback target during Stage 2, how operators recover from defective catalog releases without violating revision monotonicity, and how infrastructure failure/recovery rehearsals are executed.

## Rollback model

Two distinct failure classes require two distinct mechanisms:

1. **Content defects (bad catalog release)** — **Roll forward**. Client apps enforce strict revision monotonicity and reject older revisions. Recover by preparing a verified known-good historical revision `N` (`1 <= N < M`) under revision `M + 1` with [`scripts/catalog_roll_forward.py`](../../scripts/catalog_roll_forward.py) and signing/publishing it through the game's protected workflow.
2. **Infrastructure defects (Cloudflare / R2 outage during the 30-day rollback window)** — **DNS fallback to Firebase Hosting**. Every catalog and price publication backs up the verified R2 site tree to Firebase Hosting and immediately runs [`scripts/rollback_readiness.py`](../../scripts/rollback_readiness.py). Firebase backup or readiness failures are reported visibly and mark Firebase **NOT READY**, while **never blocking or rolling back** the verified R2 primary publication.

## Continuous rollback readiness checks

Every Firebase backup job in [`pokemon-catalog.yml`](../../.github/workflows/pokemon-catalog.yml), [`one-piece-catalog.yml`](../../.github/workflows/one-piece-catalog.yml), [`magic-catalog.yml`](../../.github/workflows/magic-catalog.yml), and [`yugioh-catalog.yml`](../../.github/workflows/yugioh-catalog.yml) runs `scripts/rollback_readiness.py` after backup readback verification and uploads `rollback-readiness.json` alongside an explicit `$GITHUB_STEP_SUMMARY` status (`READY` or `NOT READY`).

### 1. Continuous catalog and pricing parity

Compares R2 (`https://catalog-staging.scan-stash.com`, or the configured primary origin) against Firebase (`https://scanstash-catalog-prod.web.app`) using fresh `?rbv=<nonce>` cache-bypassing readbacks:

- **Catalog pointers & active immutables:** Required namespaces (`v1`, `one-piece/v1`) and any published optional namespaces (`magic/v1`, `yugioh/v1`) must exist on both origins with identical `current.json` SHA-256 digests and identical active immutable release files (`catalog-release.json`, plus `pokemon-catalog-snapshot.json` for Pokémon and `catalog.json` for Yu-Gi-Oh!). Half-published optional namespaces fail parity.
- **Catalog price scopes:** `one-piece/v1/market-price-scope.json` and `yugioh/v1/market-price-scope.json` must match byte for byte between R2 and Firebase.
- **Pricing builds & pointers:** `market-prices/v2/latest.json`, `market-prices/v2/builds/<build>/index.json`, `market-prices/v1/index.json`, and `market-prices/v1/last-updated.txt` must match byte for byte between R2 and Firebase, and Firebase's `market-prices/v2/history.json` must validate and contain the active `build` ID.
- **Firebase cache headers:** Pointers, scopes, `history.json`, and `last-updated.txt` must serve `no-cache`; immutable releases and v2 build files must serve `max-age=31536000` and `immutable`.

### 2. HTTPS certificate validity for the rollback hostname

Probes TLS 1.2+ certificates and full trust-chain validation on two endpoints:

1. Direct Firebase origin: connects to `scanstash-catalog-prod.web.app:443` with SNI `scanstash-catalog-prod.web.app`.
2. Custom rollback hostname directly on Firebase: connects to `scanstash-catalog-prod.web.app:443` (or `--custom-domain-connect-host`) with SNI `catalog.scan-stash.com`.

Connecting directly to Firebase with SNI `catalog.scan-stash.com` ensures readiness checks continue validating **Firebase's** custom-domain certificate even after public DNS moves `catalog.scan-stash.com` to Cloudflare. Each certificate must cover its hostname in SAN, be currently valid (`notBefore <= now < notAfter`), and retain at least **14 days** of expiry headroom (`--min-cert-days 14`).

### 3. Firebase storage, bandwidth headroom, and 7-day v2 retention

Enforces both local staged-site and live Google Cloud / Firebase Hosting usage budgets (default minimum headroom: **20% remaining**, i.e., warn/fail when usage exceeds 80%), configurable via repository variables without a PR:

| Budget | Default limit | Repository variable override | Source |
| --- | ---: | --- | --- |
| Staged Firebase site deploy | `2 GiB` | `FIREBASE_STAGED_SITE_LIMIT_BYTES` | Local `publisher/site` walk before/after deploy (always hard-fails) |
| Total Firebase Hosting storage (all retained versions) | `10 GiB` | `FIREBASE_STORAGE_LIMIT_BYTES` | Cloud Monitoring `firebasehosting.googleapis.com/storage/total_bytes` |
| Rolling 24-hour transfer | `10 GiB` | `FIREBASE_DAILY_BANDWIDTH_LIMIT_BYTES` | Cloud Monitoring `firebasehosting.googleapis.com/network/sent_bytes_count` |
| Rolling 30-day transfer | `100 GiB` (~$15/mo Blaze egress) | `FIREBASE_MONTHLY_BANDWIDTH_LIMIT_BYTES` | Cloud Monitoring `firebasehosting.googleapis.com/network/sent_bytes_count` |
| Minimum headroom ratio | `0.20` (20%) | `FIREBASE_MIN_HEADROOM_RATIO` | Applied to live storage and bandwidth ceilings |

- **Retention & zero-egress verification (`scripts/market_price_rollback.py`):** R2 retains every immutable v2 build indefinitely. Firebase Hosting retains the active build plus all builds from the last **7 days** (~14 builds / ~210 MB) and prunes older builds from Firebase's `history.json` and staging tree. During post-deploy backup verification, `verify` reads back only the active build and newly added builds over HTTP and verifies older retained builds via the Firebase Hosting API's live version file hashes (zero Firebase Hosting egress, failing closed if any file is missing/inactive and falling back to HTTP readback if a hash changes).
- **Restore cache ordering:** All four backup workflows seal and save the R2 restore cache immediately after backup readback succeeds and **before** running `rollback_readiness.py`, so a readiness failure never forces the next run to re-download the entire site.
- **Authentication, IAM, and pre-cutover vs. post-cutover quota mode:** `scripts/rollback_readiness.py` mints a short-lived Google OAuth2 bearer token from `FIREBASE_SERVICE_ACCOUNT` using `openssl dgst -sha256 -sign` (zero external Python dependencies) and queries Firebase Hosting REST API + Cloud Monitoring API. The service account requires **`roles/monitoring.viewer`** in addition to its existing Firebase Hosting permissions.
  - **Pre-cutover default (`FIREBASE_QUOTA_MODE=advisory`):** Because Firebase still serves all production Blaze traffic until DNS cutover, backup workflows default to `advisory`, treating live storage/bandwidth overages or missing Monitoring IAM as visible warnings (`NOT READY (QUOTA ADVISORY)` / `NOT READY (QUOTA UNVERIFIED)`, never false-green) while keeping content parity, TLS certificate, and staged-site limits as hard failures.
  - **Post-cutover enforcement (`FIREBASE_QUOTA_MODE=strict`):** Set repository variable `FIREBASE_QUOTA_MODE=strict` (and tune `FIREBASE_MONTHLY_BANDWIDTH_LIMIT_BYTES` / `FIREBASE_DAILY_BANDWIDTH_LIMIT_BYTES` if desired) once production DNS moves to Cloudflare so missing Monitoring data or budget overages fail the backup job visibly.

## Signed content roll-forward procedure

When a published catalog revision `M` has a content defect, never delete or overwrite immutable releases or attempt to re-publish revision `M` or an older revision `N`. Roll forward to revision `M + 1`:

```bash
python3 scripts/catalog_roll_forward.py prepare \
  --game pokemon \
  --target-revision 25 \
  --output-dir /tmp/roll-forward-pokemon-rev-27 \
  --reason "Roll forward from defective revision 26 to verified revision 25"
```

Supported `--game` values: `pokemon`, `one-piece`, `magic`, `yugioh`.

What `prepare` enforces before writing any artifact:

1. Downloads active `current.json` (revision `M`) and historical `releases/<N>/...` from R2 (or `--local-site` for offline rehearsals).
2. Enforces `1 <= N < M` and verifies both envelopes against app-pinned public keys via each game's existing Swift verifier (`pokemon-catalog-publisher`, `one-piece-catalog-publisher`, `magic-catalog-publisher`, `yugioh-catalog-publisher`).
3. Recomputes game-specific metadata for revision `M + 1`:
   - **Pokémon (`v1`):** Updates `revision` and `generatedAt` across `catalog-payload.json`, `pokemon-catalog-snapshot.json`, and `review-report.json`, recomputes `PokemonCatalogChangeClassifier` fields against active revision `M`, checks snapshot size via [`scripts/catalog_release_preflight.py`](../../scripts/catalog_release_preflight.py), and verifies content parity with revision `N`.
   - **One Piece (`one-piece/v1`):** Checks One Piece's permanent-identity and correction-history invariants (`OnePieceCatalogCandidateValidator`); if defective revision `M` introduced new permanent printing UUIDs or corrections absent from revision `N`, fails closed with a diagnostic requiring a reviewed supersession correction instead of silent dropping. Otherwise bumps `revision` to `M + 1`, verifies zero diffs against revision `N` via [`scripts/catalog_parity.py`](../../scripts/catalog_parity.py), checks payload size preflight, and outputs `reviewed_payload_sha256` for `one-piece-catalog.yml`.
   - **Magic (`magic/v1`):** Bumps `revision` to `M + 1`, recomputes `MagicCatalogChangeClassifier` surface diff and `changeClass` against active revision `M`, refuses `changeClass == none`, and stages `candidate/{catalog-payload.json,review-report.json}` for protected signing.
   - **Yu-Gi-Oh! (`yugioh/v1`):** Verifies `catalog.json` hash/size against the signed manifest, checks generation transition validity against active revision `M`, runs `catalog_parity.py` and `catalog_release_preflight.py`, and stages `catalog.json` + `parent-release.json` for `yugioh-catalog-publisher approve --revision <M+1>`.
4. Writes `roll-forward-manifest.json` with SHA-256 digests of every prepared artifact and the exact protected signing/publishing steps. Private signing keys and R2/Firebase credentials are never touched.

## Infrastructure failure and recovery rehearsals

### Automated offline rehearsal (CI & local)

Run the self-contained 6-phase offline rehearsal locally or via [`.github/workflows/r2-rollback-readiness.yml`](../../.github/workflows/r2-rollback-readiness.yml):

```bash
python3 scripts/catalog_roll_forward.py rehearse-recovery \
  --report /tmp/recovery-rehearsal.json
```

The rehearsal exercises:

1. **Baseline parity:** R2 and Firebase match → `rollback_readiness.py` reports `READY`.
2. **Firebase outage during R2 advance:** Firebase returns HTTP 503 while R2 advances catalogs, scopes, and v2 price build → R2 stays active, readiness reports `NOT READY`.
3. **Firebase recovery & catch-up:** Firebase recovers, parity detects drift before catch-up, `market_price_rollback.sync_r2` + catalog sync catch Firebase up while preserving historical revisions and earlier v2 builds → readiness returns to `READY`.
4. **Certificate & quota guardrails:** Expiring custom-domain certificate (`< 14` days) and exhausted storage/bandwidth headroom (`< 20%` remaining) each force `NOT READY`.
5. **Signed content roll-forward:** Prepares monotonic revision `M + 1` candidates from known-good revision `N` across all four hosted catalog games with verified parity and preflight checks.
6. **DNS fallback parity:** Confirms Firebase serves byte-identical active catalog pointers, releases, scopes, and v2 price builds matching R2.

### Live operator rehearsal checklist (open operational acceptance)

Before closing Stage 2 and switching production DNS:

1. Confirm `FIREBASE_SERVICE_ACCOUNT` in `pokemon-catalog-production` has `roles/monitoring.viewer` (or observe the explicit `HTTP 403` diagnostic from `r2-rollback-readiness.yml` and grant it).
2. Dispatch [`.github/workflows/r2-rollback-readiness.yml`](../../.github/workflows/r2-rollback-readiness.yml) with `run_live_readiness=true` and `quota_mode=strict` and confirm `Firebase Rollback Readiness: READY` (verifying live parity, Firebase `scanstash-catalog-prod.web.app` + SNI `catalog.scan-stash.com` certificate validity, and live storage/bandwidth headroom).
3. Complete one live catalog backup publish and one live price backup publish confirming `$GITHUB_STEP_SUMMARY` reports `READY` and uploads `rollback-readiness.json`.
4. Rehearse a non-destructive `catalog_roll_forward.py prepare` against a real hosted historical revision (for example, Pokémon revision 25 against active revision 26) using real pinned-key Swift signature verification (without signing or publishing).
5. Rehearse pointing a staging v2 client directly at `https://scanstash-catalog-prod.web.app` to confirm clean fallback operation before production DNS cutover.
