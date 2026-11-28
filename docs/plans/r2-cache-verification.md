# Stage 2 — Cloudflare Cache Rules, Targeted Invalidation & Live Verification Runbook

**Status, November 27, 2026.** Implementation and offline static/unit verification are complete in PR #76 (`stage2/r2-cache-verification`, stacked on PR #75). **Live staging acceptance remains open** until the Cloudflare staging rules are applied, inspected, and verified against `https://catalog-staging.scan-stash.com`.

Core principle: **cache immutable data aggressively; never edge-cache information that tells the app which data is current.**

## 1. Authoritative Cache Policy

The machine-readable ruleset specification lives in [`Config/Cloudflare/catalog-cache-rules.json`](../../Config/Cloudflare/catalog-cache-rules.json), and origin headers are defined in [`firebase.json`](../../firebase.json).

| Path class | Managed paths | Origin `Cache-Control` | Cloudflare edge behavior | Error responses (400–599) |
| --- | --- | --- | --- | --- |
| Immutable catalog releases | `/v1/releases/**`, `/magic/v1/releases/**`, `/one-piece/v1/releases/**`, `/yugioh/v1/releases/**` | `public,max-age=31536000,immutable` | Cache eligible, respect origin TTL & browser TTL, disable stale-while-updating | `status_code_ttl` `value: -1` (`no-store`) |
| Immutable v2 price builds & receipts | `/market-prices/v2/builds/**` (including extensionless `products`/`prices`, `index.json`, `scopes/*.json`, `last-updated.txt`), `/market-prices/v2/verified-builds/*.json` | `public,max-age=31536000,immutable` | Cache eligible (do not rely on default file-extension rules), respect origin TTL & browser TTL | `status_code_ttl` `value: -1` (`no-store`) |
| Legacy v1 price files | `/market-prices/v1/index.json`, `/market-prices/v1/tcgplayer/**` (extensionless) | `public,max-age=300` | Explicit edge bypass (`cache: false`) so legacy v1 clients never mix a new `last-updated.txt` with 300s edge-cached group files | Not cached |
| Mutable catalog pointers & scopes | `/v1/current.json`, `/magic/v1/current.json`, `/one-piece/v1/current.json`, `/yugioh/v1/current.json`, `/one-piece/v1/market-price-scope.json`, `/yugioh/v1/market-price-scope.json` | `no-cache` | Explicit edge bypass (`cache: false`), preserve conditional revalidation (`If-None-Match`) | Not cached |
| Mutable pricing metadata | `/market-prices/v2/latest.json`, `/market-prices/v2/history.json` (if exposed), `/market-prices/v1/last-updated.txt` | `no-cache` | Explicit edge bypass (`cache: false`) | Not cached |
| Publisher verification requests | Any managed catalog or pricing path with `?r2v=`, `?v2r=`, or `?publication_check=` | Origin header preserved | Explicit edge bypass (`cache: false`) overriding cacheable rules | Not cached |

**Legacy v1 note:** Legacy `/market-prices/v1/**` paths bypass Cloudflare edge caching (`cache: false`) while preserving origin `public,max-age=300` headers for browser/Firebase compatibility. Because R2 egress is free, bypassing edge caching for mutable v1 group files prevents mixed-build responses after a price publish without purging 1,300+ group URLs per run. Immutable v2 builds (`market-prices/v2/builds/<build>/**` + `latest.json`) provide atomic publication and full one-year edge caching.

## 2. Cloudflare Cache Rules & Precedence

Cloudflare Cache Rules (`http_request_cache_settings` phase) evaluate top-to-bottom as non-terminating `set_cache_settings` actions where **the last matching rule wins**.

Configure the four rules from [`Config/Cloudflare/catalog-cache-rules.json`](../../Config/Cloudflare/catalog-cache-rules.json) (`staging.rules`) in this exact order, scoped strictly to `http.host eq "catalog-staging.scan-stash.com"`:

1. **`immutable-catalog-and-price-builds`**: Eligible for cache, Edge TTL = Respect origin, Browser TTL = Respect origin, Status Code TTL `400–599` = Do not cache (`no-store`, API `value: -1`, **not** `0`), Serve stale = Disable stale-while-updating.
2. **`legacy-v1-market-prices`**: Bypass cache (`cache: false`) for `/market-prices/v1/index.json` and `/market-prices/v1/tcgplayer/**`.
3. **`mutable-pointers-scopes-and-markers`**: Bypass cache (`cache: false`).
4. **`publisher-verification-nonce-bypass`** *(must be last)*: Bypass cache (`cache: false`) for managed catalog/pricing paths whose query contains `r2v=`, `v2r=`, or `publication_check=`.

### Applying in the Cloudflare Dashboard

1. Open zone `scan-stash.com` → **Caching → Cache Rules**.
2. Inspect any existing zone rules for overlapping hostnames or catch-all expressions before adding rules.
3. Create the four rules above in exact order 1 → 4 using the expressions in `Config/Cloudflare/catalog-cache-rules.json` under `staging.rules`.
4. Confirm no rule matches `scan-stash.com`, `www.scan-stash.com`, legal pages, or mail hostnames.

### Equivalent Cloudflare Ruleset API Inspection (Read-Only)

Inspect the current zone entrypoint ruleset before making changes (never paste tokens into git or logs):

```bash
curl --fail --silent --show-error \
  -H "Authorization: Bearer ${CLOUDFLARE_RULES_READ_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" | jq .
```

To apply `staging.rules` via the Cloudflare API, merge the 4 rule objects into the zone's `http_request_cache_settings` ruleset while preserving any unrelated zone rules outside `catalog-staging.scan-stash.com`.

### Later Production Hostname Configuration (Not Activated Yet)

`Config/Cloudflare/catalog-cache-rules.json` also includes `production_cutover_template` (`hostname: "catalog.scan-stash.com"`, `activated: false`). Do not deploy those rules or change production DNS until Stage 2 staging verification, PR #77 rollback readiness checks, PR #78 client configuration, and the seven-day parallel validation period pass.

## 3. Credentials & Least-Privilege Permissions

Configure the following in GitHub Environment `r2-catalog-production`:

| Name | Kind | Purpose & required permission |
| --- | --- | --- |
| `CLOUDFLARE_ZONE_ID` | Environment variable | 32-hex zone ID for `scan-stash.com` |
| `CLOUDFLARE_CACHE_PURGE_TOKEN` | Environment secret | Least-privilege API token scoped **only** to `scan-stash.com` → **Zone → Cache Purge → Purge** |
| `CLOUDFLARE_CACHE_ENFORCE` | Environment variable | Optional staged-rollout switch: omit/`false` while configuring credentials (logs visible warning when skipped); set `true` to require purge + canonical verification on every publish |
| `CLOUDFLARE_RULES_READ_TOKEN` | Environment secret *(optional)* | Separate read-only token scoped to `scan-stash.com` → **Zone → Cache Rules → Read** for automated ruleset inspection |

Never reuse R2 S3 storage credentials for Cloudflare API calls, and never grant DNS edit, Cache Rules edit, or account-admin permissions to the recurring publisher token.

## 4. Origin Verification vs. Canonical Client-Visible Verification

Every primary R2 publish (`scripts/r2_catalog_publish.py` for Pokémon, One Piece, Magic, Yu-Gi-Oh!, primary pricing, and `scripts/publish_one_piece_local.py`) now executes two distinct verification stages:

1. **Origin verification (nonce-based):** Uploads immutable objects first, verifies every immutable object through `?r2v=<nonce>` (bypassing edge cache via Rule 4), then activates mutable scopes/pointers/markers and verifies them through `?r2v=<nonce>`. Any immutable failure aborts fail-closed before any pointer flips.
2. **Targeted purge & canonical client-visible verification (`scripts/cloudflare_cache.py`):**
   - Derives exact canonical URLs strictly from the verified publication plan (never arbitrary user URLs, never `purge_everything`, never immutable releases):
     - Catalog publish: `<namespace>/current.json` and (for One Piece / Yu-Gi-Oh!) `<namespace>/market-price-scope.json`.
     - Price publish: `market-prices/v2/latest.json`, `market-prices/v1/last-updated.txt`, `market-prices/v1/index.json`.
   - Calls `POST /client/v4/zones/{zone_id}/purge_cache` with `{"files": [...]}` using bounded retries (`Retry-After` clamped to 30s).
   - Fetches each canonical URL **without** a query nonce and **without** `Cache-Control: no-cache` request headers (matching an ordinary app request), checking HTTP 200, SHA-256, `Content-Type`, `Cache-Control`, and `CF-Cache-Status` (`BYPASS` or `DYNAMIC` required for all pointers, scopes, and markers; `HIT`/`STALE`/`EXPIRED`/`REVALIDATED`/`UPDATING` rejected).

## 5. Failure Handling & Idempotent Recovery

- **Pre-activation failure (exit code 1):** An immutable upload or origin readback failed. No pointer is flipped, no purge runs, and Firebase backup does not run.
- **Post-activation cache failure (exit code 2):** R2 origin activation and nonce-based verification **succeeded** (and legacy v1 completed for pricing), but Cloudflare purge or canonical client-visible verification failed.
  - R2 immutable objects and the active pointer remain untouched (never deleted or rolled back).
  - The workflow exports `origin_verified=true` and `cache_verified=false`, writes a JSON cache report with the exact publication and affected URLs, allows the independent Firebase backup job to proceed from the verified R2 origin, and fails the R2 job's final cache-verification step so the run **cannot** count toward Stage 2 cutover readiness.
  - **Safe idempotent recovery:** Rerun the failed workflow job (uploads are no-ops; origin readback, targeted purge, and canonical verification rerun safely), or run locally with the staged artifact:

```bash
python3 scripts/r2_catalog_publish.py \
  --primary-catalog <namespace> \
  --catalog-metadata <path/to/catalog-publish-metadata.json> \
  --site <path/to/site> \
  --public-base https://catalog-staging.scan-stash.com \
  --recover-cache-only \
  --require-cache-verification \
  --cache-report /tmp/cache-recovery.json
```

Dry runs (`--dry-run`) and `--write-catalog-metadata` never call Cloudflare or mutate edge state.

## 6. Verification Commands

### Static verification (offline CI, no network or credentials)

```bash
bash scripts/verify_pokemon_catalog_hosting_config.sh
```

### Live staging verification (authorized operator or `.github/workflows/r2-cache-verification.yml`)

```bash
# Read-only staging verification (discovers active immutable releases & builds dynamically)
python3 scripts/verify_hosting_cache.py live \
  --origin https://catalog-staging.scan-stash.com \
  --report /tmp/r2-cache-live-report.json

# Include authorized missing-object negative-cache probe (staging only, cleans up probe key)
python3 scripts/verify_hosting_cache.py live \
  --origin https://catalog-staging.scan-stash.com \
  --probe-missing-object \
  --report /tmp/r2-cache-live-report.json

# Include read-only Cloudflare Cache Rules inspection (separate CLOUDFLARE_RULES_READ_TOKEN)
python3 scripts/verify_hosting_cache.py live \
  --origin https://catalog-staging.scan-stash.com \
  --inspect-cloudflare-rules \
  --report /tmp/r2-cache-live-report.json
```

One successful CDN PoP (`CF-Ray` colo) proves behavior at that edge location, not globally; combine live probe results with deployed ruleset inspection (`--inspect-cloudflare-rules`).

## 7. Live Acceptance Evidence Ledger

Offline repository CI passing is **not** live acceptance. Record dated evidence below after applying the Cloudflare staging rules and running live staging checks (never include tokens or `Authorization` headers):

| Gate | Status | Evidence (URLs, path classes, expected/observed SHA-256, HTTP status, `Cache-Control`, `CF-Cache-Status`, `CF-Ray`) |
| --- | --- | --- |
| Staging Cloudflare Cache Rules applied & inspected | Open | Pending `--inspect-cloudflare-rules` output against `catalog-staging.scan-stash.com` |
| Immutable catalog & v2 price builds edge caching (including extensionless & verified-build receipts) | Open | Pending `verify_hosting_cache.py live` report |
| Mutable pointers, scopes & markers edge bypass + conditional revalidation | Open | Pending `verify_hosting_cache.py live` report |
| Legacy v1 300-second freshness policy | Open | Pending `verify_hosting_cache.py live` report |
| Missing-object negative-cache diagnostic probe (`v1/releases/_cache-probe/...`) | Open | Pending `--probe-missing-object` report |
| Qualifying live catalog & price publish targeted purge + canonical readback | Open | Pending live run with `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_CACHE_PURGE_TOKEN`, and `CLOUDFLARE_CACHE_ENFORCE=true` |
