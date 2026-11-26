# Offline-first, outage-resilient catalog and price delivery

**Status** · current plan, 2026-11-26. The owner approved the direction after review. Stage 1 code is merged: [#62](https://github.com/Razorback2424/CardScanner/pull/62) (hosting and CI bandwidth, `3a2fd71`), [#63](https://github.com/Razorback2424/CardScanner/pull/63) (app pricing reliability, `404e94c`) and [#64](https://github.com/Razorback2424/CardScanner/pull/64) (release preparation, `5c566e5`). Stage 1 is **not closed**: the price-publish readback, a populated memory measurement and budget approval remain (see Stage 1 status). Stages 2–5 have not started. Stage evidence lives in [`offline-catalog-delivery-stage-1.md`](offline-catalog-delivery-stage-1.md).

**Owner decisions recorded here:**
- Static hosting moves to Cloudflare R2. The pricing proxy's Functions, Firestore and App Check stay on Firebase.
- Magic becomes a full offline catalog, and Scryfall stays its price provider.
- Internal price delivery is unified, not providers.
- Legacy code is removed only after its replacement is proven.

## Context

**Principle.** ScanStash is an app that works locally and receives updates from the internet. It is not an internet app with offline fallbacks.

**Constraints:**
- It must work at a card show with no reception.
- It must not undo the certification work already done (printing identities, finishes, marketplace mappings, pricing coverage).
- It must not turn into a month of regressions.

**Why we're doing this.** The five games each solved delivery independently:

| | Bundled in the app | Hosted updates | Prices |
|---|---|---|---|
| Pokémon | Signed release + plain checklists | **On** (pointer + snapshot) | TCGdex live → mirror; two separate caches |
| One Piece | Signed 33 MB envelope | **On** (the envelope is served as `current.json`) | Mirror |
| Lorcana | Plain JSON | **Off** (code exists, not wired) | Mirror |
| Yu-Gi-Oh | Plain 34 MB JSON (with seed prices) | **Off** (no keys or URL) | Mirror → seed |
| Magic | Set list only | **Off** (`legacy-live`, borrowed key, pins `*.web.app`) | Scryfall live |

**Two problems we're fixing:**

1. **Firebase 509.** Each deploy replaces the whole site. So `scripts/restore_catalog_hosting_site.sh` first downloads **every past revision of every game** from production, about 0.4 GB per run. `yugioh-catalog.yml` publishes prices 4× a day, and every publish triggers that restore. The publish also reads the One Piece and Yu-Gi-Oh `current.json` (up to 130 MB) just to work out the price scope.
2. **Prices disappearing.** Several things combine:
   - `TCGCSVPriceMirror.canServe` (`Services/TCGCSVProductPriceSource.swift:7,14`) hides quotes older than 7 days.
   - Snapshots live in purgeable `Caches/`.
   - Collection refresh for One Piece, Lorcana and Yu-Gi-Oh turns off the stale fallback.
   - The price-cache key includes `catalogGeneration`, so a catalog update throws away valid prices.

**Five stages.** Each one leaves `main` stable and releasable, and launch does not depend on finishing all five. Each stage is a set of small PRs, and nothing old is deleted until its replacement is proven.

## Rules that apply to every stage

- **Unify delivery, not providers.** One internal price system holds a store, a freshness model and an identity check. TCGdex (Pokémon) and Scryfall (Magic) stay. No game moves to TCGCSV for consistency's sake. No new bundled TCGCSV price snapshots ship while the commercial-licensing decision is open (Yu-Gi-Oh's existing seed prices stay as they are). The provider becomes a plug-in, so swapping in a licensed vendor later needs no infrastructure work.
- **Preserve identity.** No printing ID, finish certification, marketplace mapping or collection reference changes unintentionally. This is enforced by the parity tool below, not by spot checks.
- **Remove historical releases only with evidence.** First take an inventory of which revisions existing clients, Yu-Gi-Oh parent chains (up to 32), rollback and audit evidence need. Until then, keep everything.
- **Reuse what exists.**
  - `Services/SignedCatalogReleaseStore.swift`
  - `Services/SignedCatalogUpdateClient.swift`
  - `GameCatalogActivationSource` / `GameCatalogSnapshot` (`Games/Core/GameCatalogAdapter.swift`)
  - `scripts/catalog_release_preflight.py`
  - `scripts/catalog_exceptions.py`

  Game-specific logic that works stays game-specific.

## Gate for every PR: full-catalog parity and budgets

- **New `scripts/catalog_parity.py <game> --before A --after B`.** It compares whole catalogs, never samples, and fails on any unexplained difference in:
  - sets and printings, with no losses;
  - printing IDs, with no changes;
  - finish coverage;
  - marketplace mappings;
  - priced-product coverage.

  An allowlist of reviewed, expected differences is checked into the PR.

  **What is implemented vs required (2026-11-26):**

  | Comparison | State |
  | --- | --- |
  | Pokémon, Lorcana, One Piece (including the owner catalog), Yu-Gi-Oh catalogs | Runs automatically on every PR against its base (`catalog-coverage-tests.yml`) |
  | Magic catalog | Reader exists and is fixture-tested; **required in CI before Magic's Stage 4 migration** |
  | Priced-product coverage from captured price feeds | Comparator exists; **required before any price-publication change in Stage 2** |
- **Collection safety, in two layers:**
  - **Implemented:** `CollectionPrintingBaselineTests` pins every printing a collection can hold today (Yu-Gi-Oh 47,917, One Piece 4,153, Lorcana 3,576) and fails if any stops resolving. Pokémon and Magic store provider IDs that resolve live, so this layer doesn't cover them.
  - **Required before each catalog-format migration (Stages 3 and 4):** an upgrade test that opens a saved collection store built with the previous app version, with rows for every game, migrates it, and checks that no row is lost or orphaned. A representative store is enough. It does not need tens of thousands of rows, because the baseline layer already covers every ID.
- **Budgets, measured first in Stage 1 and then held.** Each is recorded per game and in total, and any regression must be approved explicitly:
  - app download and install size;
  - on-device catalog and price storage;
  - peak storage during an update;
  - cold-launch time;
  - peak memory.

  Measurements are taken on the simulator and labelled as such. Device numbers come from you.

  **Budget scope.** The storage budget applies only to **replaceable** data: downloaded catalog releases and price caches. User-owned data (the collection, photos, price history) is measured and reported separately, and is never evicted to meet an infrastructure budget. Proposed limits, pending owner approval:
  - app bundle growth within 5% per stage (provisional);
  - replaceable catalog and price data under 300 MB;
  - no cold-launch regression from the Stage 1 baseline;
  - first-launch peak memory under 400 MB (provisional until measured on a device).

  The Stage 1 memory numbers were taken without hosted updates, so the memory budget must also be re-measured during a fully populated session (every game browsed and priced, plus a collection refresh) before it is accepted.
- **Failure drills (automated where possible):**
  - fresh offline install;
  - upgrade of an existing install;
  - corrupted download;
  - interrupted activation;
  - not enough disk space;
  - each price provider unavailable (HTTP 509 or timeout).

  Browse and scan must keep working, and the previous verified catalog stays active.

## Stage 1 status (2026-11-26)

Implemented in [#62](https://github.com/Razorback2424/CardScanner/pull/62) and [#63](https://github.com/Razorback2424/CardScanner/pull/63), both merged:
- **App:** freshness tiers, identity checks, failures never overwriting a price, backup-excluded bounded storage, the shared Pokémon cache, persisted ETags, collection refresh through outages, and review fixes.
- **CI:** the restore cache, revision-bound price scopes, and the ETag-cached Yu-Gi-Oh parent.
- **Gates:** full-catalog parity for all five games, the collection printing baseline, simulator budget measurements, and the failure-drill map.

**Verification (simulator only).** There are two app test runs, and their counts measure different things:
- **Targeted Stage 1 selection,** the final per-case result across pricing, game integrations, activation, recovery, variant resolution, portfolio eligibility and Collection: 808 cases, 797 passed, 11 skipped, 0 failed. An earlier interim count of 689 is superseded by this one.
- **Complete suite on the integrated candidate:** 3,691 tests (details below).

The Python selections passed too: 82 catalog and market-feed cases, and 60 scope cases.

**Review follow-ups (2026-11-26).** These came from the review of #62–#65, and each was confirmed against the code.
- **Done, in #62 (merged as `3a2fd71`):** the restore cache is saved only after the production readback passes, and recovered historical revisions can be reconciled on demand (`ff52b7bd`).
- **Done, in #63 (merged as `404e94c`):** a refresh that keeps a cached price after a failed download is reported as failed, with its amount and capture date unchanged (`963d434b`, `622683ec`).
- **Done, in #63:** decoded price groups held in memory are capped at 64, least recently used first. An evicted group reloads from disk without a network request, and in-memory hits keep the disk copy marked as recent (`3c5ab779`).

**Complete iOS suite on the integrated candidate (done).** The candidate was `main` at `3a2fd71` with #63 (`3c5ab779`) and #64 merged locally, without conflicts.
- On the iOS 27.0 simulator: 3,691 tests, 22 skipped, 9 failing tests (18 assertion failures).
- **None are regressions.** The 6 centering research tests fail the same way on plain `main` (they need local fixtures). The 3 local StoreKit tests in `CollectorToolsTests` pass when run alone on both the candidate and `main`, so their full-suite failures are interference between tests.
- The pre-existing centering and StoreKit-order failures are tracked separately, not as Stage 1 work.
- **CI on merged `main` (`5c566e5`):** the PR checks passed on each branch before merge. The scheduled catalog jobs on `main` fail at the production pointer read with HTTP 509, not on code. A green scheduled run is part of the production verification below.

**Still open before Stage 1 closes.** The project moved to Blaze on 2026-11-26 and hosting serves again; items 1 and 2 are done:
1. **Done: production revision inventory** (Stage 1 item 9). The origin holds only Pokémon revisions 1–26, One Piece revisions 1–7 and one price build; there are no hosted Yu-Gi-Oh, Magic or Lorcana catalogs, so no parent chains to retain. Everything is kept. Details in the evidence document.
2. **Done: HTTPS rollback rehearsal.** The custom-domain certificate validates; all 1,497 files match the inventory hashes; both signed pointers verify against the pinned keys and match what the app ships.
3. **Production readback of the price scope files** (`market-price-scope.json`): one scheduled price publish observed end to end, reading only the compact scopes and leaving the restore cache warm for the next run.
4. **Fully populated memory measurement:** every game browsed and priced plus a collection refresh, with hosted updates arriving. The current numbers were taken while production returned 509.
5. **Owner approval of the budgets,** as scoped in the gate section above. The memory budget stays provisional until item 4 is measured.

Stage 1 closes when items 3 and 4 are recorded in the evidence document and item 5 is approved.

## Stage 1: stabilize the current app (no format or host changes)

**App, price reliability.** Ships in the next build.

1. **Freshness model.** Replace `canServe`'s hide-after-7-days with three tiers, shown in the UI with the capture date:

   | Age | Label | Counted as current? |
   |---|---|---|
   | ≤24 h | "Updated today" | Yes |
   | ≤30 days | "Updated N days ago · stale" | No |
   | >30 days | "Historical estimate" | No |

   Call sites to change:
   - `PriceProvider.swift:58`
   - `Models/CatalogBrowseFilters.swift:231`
   - `BrowseCatalog.swift:1743,1769,2153`
   - `CatalogCardDetailView.swift:1070`
   - `PriceCheckCoordinator.swift:397,561,736`
   - `QuoteCache.swift:233`

   Totals that include stale or historical prices say so.
2. **Identity check on stored prices.** A stored price is shown only if its printing ID, finish, currency, provider product ID and provider all match the request. A dated price for the wrong variant is never shown.
3. **Never overwrite a good price with a failure.** A failed refresh keeps the existing amount and its original capture date (extending today's `PriceRecord.recordFailure` behavior to the reference and mirror stores). Add tests to prove it.
4. **Storage.** Move the mirror snapshots (`TCGCSVProductPrices-v1/`, `TCGCSV-v1/`) from `Caches/` to Application Support. Mark them `isExcludedFromBackup`, and bound them by size using an LRU scheme over the groups in use. The user's collection data (SwiftData) stays backed up as it is today.
5. **No redundant downloads.**
   - Drop `catalogGeneration` from the price-cache key (`TCGCSVProductPriceSource.swift:252`).
   - Merge `PokemonTCGCSVPriceService` into `TCGCSVProductPriceSource` (one cache; same providers).
   - Persist the Pokémon and Magic pointer ETags (pattern: `OnePieceCatalogUpdateClient.swift:68`).
6. **Collection refresh.** Allow the stale fallback in `refreshStoredPrinting` for One Piece, Lorcana and Yu-Gi-Oh, so an outage leaves dated prices rather than failures.

**CI, Firebase bandwidth.** This is the smallest safe change, since R2 replaces it soon.

7. **Skip unchanged restores.** Keep the restored site tree in the GitHub Actions cache, keyed by each game's pointer ETag. Each run makes conditional requests (`If-None-Match` → 304) and re-downloads only what changed. **No revisions are removed.**
8. **Price scope.** The price publish takes its scope from a small `scripts/market_price_scope.json` that catalog publishes update, instead of downloading the One Piece and Yu-Gi-Oh envelopes.
9. **Inventory of required revisions.** Write down which revisions existing clients, the Yu-Gi-Oh chains, rollback and audit need. This is evidence for Stage 2's retention policy only; nothing is deleted.

**Stopping point.** Prices persist and stay dated through outages. CI no longer downloads the site. Budgets and parity tooling are in place.

## Stage 2: move static hosting to R2 (same files, same URLs)

The host changes; the formats don't. Every path, file and header the app sees stays byte-identical, so a hosting problem can't be confused with a format problem.

- **DNS.** `scan-stash.com` is served by Bluehost's nameservers, and `catalog.scan-stash.com` is a CNAME to Firebase. An R2 custom domain needs the zone on Cloudflare, so this is a full nameserver move.
  1. Export every Bluehost record (website and legal pages, MX, SPF/DKIM, verification TXT).
  2. Recreate them in Cloudflare.
  3. Check each one with a script against Cloudflare's nameservers before switching.
  4. Lower TTLs 48 hours ahead.
- **Publication integrity.**
  - Upload new immutable objects first, then read each one back through the public domain and verify its hash. **Write mutable pointers last**: a single object PUT, so it's atomic.
  - A publish that fails before the flip changes nothing users see.
  - The app's signature and hash checks are a second barrier.
  - **Price builds must not overwrite live files.** Firebase swaps the whole site at once, but R2 writes one object at a time. Overwriting `market-prices/v1/...` in place would leave a mix of two builds if a publish fails partway. The app's build checks would reject the mix, so prices stay correct, but new installs and uncached groups would get no prices until the publish is repaired. The design:
    - Each price build is uploaded to its own immutable path, `market-prices/v2/builds/<build>/<category>/<group>.json`, then read back and hash-checked.
    - A small `market-prices/v2/latest.json` pointer, listing the build and each file's hash, is written **last** in a single PUT. Clients see either the old build or the new one, never a mix.
    - **Precondition:** an app release that reads `v2` must ship before the cutover. The app keeps last-known prices on device (Stage 1), so a client switching paths loses nothing.
    - **Compatibility for builds that only read `v1`:** keep publishing the mutable `v1` paths after `v2` is complete, with `last-updated.txt` written last. The partial-publish window is documented. Recovery is to re-run the publish, which rewrites every `v1` file from the same verified `v2` build. Those clients fall back to their dated on-device prices in the meantime. Retire `v1` once old builds age out.
- **Cloudflare caching (checked by a test, not assumed).**
  - Immutable releases: `max-age=31536000, immutable`.
  - Pointers and `last-updated.txt`: a cache rule **bypasses edge cache**, plus `no-cache` revalidation.
  - Price files: short edge TTL.
  - 404 responses: **not cached** (edge TTL by status code), so a newly published object is never masked by an earlier cached 404.
  - The publisher never requests an object's URL before uploading it.
  - The publisher purges pointer URLs after each flip.
- **Retention.** Every historical revision is copied once from Firebase to R2 with hash verification, then kept. Storage is cheap, and Stage 1's inventory decides any later cleanup.
- **Security.**
  - Signing keys, pinned keys, revision monotonicity, approval gates (`YUGIOH_APPROVED_PARENT_URL`, the Pokémon approval job) and preflight are all unchanged.
  - `verify_pokemon_catalog_hosting_config.sh` is rewritten to verify R2 metadata and cache rules.
  - The R2 write token lives only in GitHub environment secrets and the local fallback.
- **Out of scope.** `pricing-proxy/` (Functions), `firestore.rules` and App Check stay on Firebase. `firebase.json` keeps its `functions` and `firestore` blocks.
- **Rollback**, which has to work with revision monotonicity:
  - **Content problems** are fixed by **rolling forward**. A script republishes known-good content, signed, under the **next** revision number. The app would rightly reject an older revision.
  - **Infrastructure problems.** During a 30-day window the publisher keeps the Firebase site *current*. It rebuilds the tree **from R2**, which costs nothing to download from, and deploys it to Firebase on every catalog and price publish. Firebase then serves nothing until DNS points back at it, so falling back is a DNS change to a site that is up to date.
  - **Rollback readiness is checked on every publish during the window, not assumed from the first setup.** Each publish reads back from the Firebase origin (`scanstash-catalog-prod.web.app`) and checks that:
    - every pointer and price build matches R2 at the same revision;
    - the custom domain's HTTPS certificate on Firebase is still valid;
    - Firebase hosting usage has headroom left under its quota.

    If any check fails, the job fails visibly and the rollback target is marked not ready until a later publish passes again. A failed Firebase publish never blocks the R2 publish.
- **Cutover.**
  1. Publish to both for at least one week on a staging hostname, with hash parity on every publish.
  2. Move DNS.
  3. Watch for the window.
  4. Remove Firebase hosting.
- **App precondition (a small PR).** Point Magic at `catalog.scan-stash.com` instead of the pinned `*.web.app` host. Production Magic is `legacy-live` and never fetches it.

**Stopping point.** Same app behavior; hosting with no bandwidth cap.

## Stage 3: shared catalog channel, piloted with Yu-Gi-Oh

- **Format.**
  - A small signed **pointer** names the revision and the hash of a separate signed **manifest**, which has a size cap set by preflight. That removes any fixed limit on how many shards a game can have.
  - The manifest lists **content-addressed shards** per set.
  - The bundled seed uses the same format.
- **Deterministic shards.** These checks run in the builder:
  - Canonical serialization: sorted keys, no timestamps or build IDs inside shards. Unchanged data therefore produces identical hashes across builds (rebuilding the same input must give zero changed shards).
  - Global invariants are checked on the assembled catalog: every printing ID appears exactly once across shards; a card moved between sets is neither duplicated nor lost; finish certifications and mappings round-trip.
  - `catalog_parity.py` compares the sharded catalog with today's monolithic one and must find no differences.
- **Atomic activation and recovery.**
  1. Shards download into a staging directory.
  2. Each one is verified against the manifest.
  3. The release is activated through `SignedCatalogReleaseStore`'s two-slot swap only when complete.
  4. An interrupted or corrupted update leaves the previous verified release active, and is resumed or discarded on the next launch.
  5. Disk space is checked before staging.
- **Memory.** Shards load into the same in-memory model the game uses today. Lazy loading is added only if the Stage 1 budgets show it's needed.
- **Channel.** A thin `CatalogReleaseChannel` built on the existing store, client and activation source:
  - one mode enum;
  - a per-game key pin (every game gets its **own** key);
  - a persisted ETag;
  - checks on launch and on foreground, with a cooldown.

  It does not rewrite game-specific registries.
- **Pilot: Yu-Gi-Oh** (off → authority) first. Then, one PR each and only after the pilot holds in parity, drills and budgets: Lorcana, One Piece, Pokémon (including `finish-coverage.json`). Magic moves onto the channel only in Stage 4, together with its offline catalog, so it never goes through an intermediate migration.
- **Old paths.** Each game's old path stays in place, and published, until its replacement has passed the gate. If the app is already in users' hands, `v1` stays published until old builds age out.

## Stage 4: offline Magic catalog (Scryfall prices stay)

- New `scripts/build_magic_catalog.py` reads Scryfall's daily bulk `default-cards` file, reusing the streaming approach in `ScryfallBulkCardIndex`. It produces English paper printings as per-set shards and ships through the channel.
- Browse and scan read the local signed catalog. Scryfall stays the **price** provider (and the image source) through the shared price store and freshness model.
- **Gate.** Parity against Scryfall's live sets and printings for the same day, plus existing Magic recognition and pricing tests. The `legacy-live` path stays until Magic's coverage is equal or better.

## Stage 5: consolidate and remove the old code

- **One publish tool.** `scripts/publish_catalog.py <game>` (with `--local`) and one reusable workflow replace the per-game publish paths, once each game has passed through Stage 3. The price publish is its own small workflow.
- **Delete what's been replaced.** Remove the superseded coordinators, mode enums, duplicate envelope types and legacy `v1` paths, each one only after its replacement has passed the gate and, where it applies, old builds have aged out.
- **One reference.** `docs/catalog-delivery.md` becomes the single readable reference: format, paths, cache rules, publish steps, keys, freshness tiers, budgets, rollback, and a per-game table. Archive the older per-game hosting sections under `docs/legacy/`.

## Verification (applies per stage)

- **Scripts.**
  - `publish_catalog.py` / the R2 uploader against a local S3-compatible fake (MinIO), proving: the order (objects, readback, pointer); that a failed readback leaves the pointer untouched; and that rerunning is a no-op.
  - Shard determinism tests.
  - `catalog_parity.py` tests.
  - The existing `test_market_price_feeds.py`, `test_catalog_release_preflight.py` and `test_catalog_exceptions.py`.
- **App** (`-only-testing`, review simulator, DerivedData on the SSD):
  - prices: `PokemonTCGCSVPriceTests` (the outage case at `:1408` now *shows a dated price*), `QuoteCacheTests`, `PricingTests`, `PriceRefreshLifecycleTests`;
  - per game: the Yu-Gi-Oh, Lorcana, One Piece, `PokemonCatalogSlice*` and `VariantResolverTests` integration tests;
  - the new channel, activation and collection-resolution tests.
- **Gate.** Full-catalog parity, the failure drills, and the budget comparison, all as described above.
- **Hosting.** Automated checks of Cloudflare headers and cache status for pointers, immutable objects and 404s. A DNS record parity script. A rollback rehearsal on the staging hostname (roll-forward republish, then DNS back to Firebase).
- **Not claimed.** No device, App Store or provider readiness from simulator evidence.

## Owner actions

- Create the Cloudflare account, the R2 bucket, and a write-scoped token in GitHub environment secrets.
- Approve the nameserver move once the record check passes.
- Generate production signing keys for Yu-Gi-Oh, Lorcana and Magic (private halves kept off-repo).
- Approve the storage and performance budgets after Stage 1 measures them.
