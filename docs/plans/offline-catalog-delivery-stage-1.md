# Offline catalog delivery · Stage 1 evidence

**Status** · 2026-11-26, working tree based on `cf59824f`; all changes are local and uncommitted. Stage 1 is complete except for two items that need the owner: the production revision inventory and HTTPS rollback rehearsal (blocked while Firebase returns HTTP 509), and approval of the storage and performance budgets below.

| Stage 1 item | State |
| --- | --- |
| Freshness tiers, identity checks, failures never overwrite a price | Done. Review fixes on 2026-11-26: a Browse quote kept after a failed refresh says "Refresh failed"; a capture from late yesterday reads "Updated yesterday"; Price Check hides the freshness line while refreshing. |
| Backup-excluded, bounded price storage | Done. Unusable legacy imports are now removed instead of left behind. |
| Collection refresh keeps dated prices through outages | Done. A stored-printing refresh waits for an in-flight newer build and falls back to the dated quote only after the check fails (`TCGCSVPriceMirror.awaitsRevalidation`). |
| One shared Pokémon mirror cache | Done. Set and product readers share the group download. A complete provider response always outranks a legacy positive-only import, and a set projection never serves a cache file without a feed build. |
| Persisted pointer ETags (Pokémon, Magic) | Done. |
| Price Check identity | Done. A collection-authority mismatch on a fresh quote reports a pricing failure, not "not matched". |
| CI restore cache | Done. |
| Lightweight price scope | Done. The price job reads the revision-bound `market-price-scope.json` sidecars. The approved Yu-Gi-Oh parent is now revalidated with its ETag and cached between runs instead of downloaded on every run. |
| Full-catalog parity | Done for Yu-Gi-Oh, One Piece, Lorcana and Pokémon on bundled data. Magic's reader is fixture-tested only; it gets real input when Stage 4 captures Scryfall bulk data. |
| Collection fixture | Done. `CollectionPrintingBaselineTests` pins every holdable printing (Yu-Gi-Oh 47,917, One Piece 4,153, Lorcana 3,576) and fails if any stops resolving. Pokémon and Magic collections store provider IDs resolved live, so the parity tool covers them. |
| Budgets measured | Done on the simulator; awaiting owner approval. |
| Failure drills | Done; see the drill table. |
| Production inventory and rollback rehearsal | **Blocked** by HTTP 509 until the monthly quota reset or a plan upgrade. |

## Historical release inventory

Keep the complete production history until a verified origin inventory and an HTTPS rollback rehearsal establish what can be retired. The restore checks each revision through the signed pointer and rejects a missing active immutable release. Read-only HEAD checks on November 26 returned HTTP 509 for the Firebase Pokémon pointer and the custom-domain price marker, so the table uses retained repository evidence. [Restore script](../../scripts/restore_catalog_hosting_site.sh) · [Hosting audit](../audits/release-stability-ledger.md)

| Game | Evidence in the repository | Keep for existing clients and recovery |
| --- | --- | --- |
| Pokémon | The app ships signed revision 26 and a matching checklist snapshot. The publisher also retains a revision 25 candidate. | `v1/current.json` and every immutable revision, including checklist snapshots, payloads and review reports. Clients can fetch the signed snapshot after reading the pointer. [Bundled release](../../TradingCardScanner/PokemonCatalogRelease) · [Publisher evidence](../../publisher/pokemon/production/revision-25) |
| One Piece | The repository records hosted revision 7 and the signed revision 4 seed. | `one-piece/v1/current.json` and all signed immutable envelopes. Keep known-good content available for a newly signed roll-forward revision and retain the reviewed publisher evidence. [Release evidence](one_piece_release_acceptance.md) · [Seed](../../TradingCardScanner/OnePieceCatalogSeed/README.md) |
| Yu-Gi-Oh! | The bundled catalog is the installation anchor. The approved-host path is conditional on the production approval configuration. | Keep `yugioh/v1/current.json` and every immutable approved revision. The app follows signed parent locators up to 32 envelopes with a 128 MiB aggregate catalog limit. Clients can also use a signed checkpoint that includes their anchor. Keep the signed envelopes and matching `catalog.json` files. [Client](../../TradingCardScanner/Games/YuGiOh/YuGiOhCatalogCoordinator.swift) · [Wire contract](../../TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift) |
| Magic | Production uses the live Scryfall catalog path. The signed validation and rollout path still exists. | Keep every published `magic/v1` object and its report if present. Move Magic to the shared channel with the offline Magic catalog in Stage 4. [Client](../../TradingCardScanner/Services/MagicCatalogUpdateClient.swift) · [Production configuration](../../Config/MagicCatalogProduction.xcconfig) |
| Lorcana | The app bundles discovery and reviewed physical catalogs. The signed rollout path is available in source. | Keep the bundled resources and review evidence. Record any hosted Lorcana revisions in the pre-cutover origin inventory. [Bundled catalogs](../../TradingCardScanner/LorcanaCatalogSeed) · [Activation](../../TradingCardScanner/Games/Lorcana/LorcanaCatalogCoordinator.swift) |

Before migration, record each origin pointer with its ETag, verified revision and SHA-256. Inventory every immutable object and hash, then associate them with the supported client versions, signed parent chains and rollback releases. Rehearse infrastructure rollback with a real HTTPS request against Firebase's custom domain and verify the returned bytes and certificate before changing nameservers.

## Simulator size checkpoint

Xcode 27.2, `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal`, iOS 27.0 review simulator. Values are logical file bytes from the built app directory, excluding the test plug-in. The tracked catalog resources and publisher inputs matched `cf59824f` byte for byte.

| Bundled catalog resources | Bytes |
| --- | ---: |
| Pokémon release and checklist | 19,814,671 |
| One Piece owner catalog | 33,136,647 |
| Lorcana seed | 15,860,387 |
| Yu-Gi-Oh! seed | 34,368,555 |
| Magic set seed, treatment catalog and historical pilot | 4,545,391 |
| Total catalog directories | 107,725,651 |
| Whole simulator app bundle | 245,250,178 |

### Measured on 2026-11-26 (simulator, ReleaseLocal, fresh install)

| Measure | Value | Notes |
| --- | ---: | --- |
| App bundle (simulator) | 252.8 MB | Not an App Store thinned size; device archives need an owner-run App Store Connect size report. |
| Data container after first launches | 6.6 MB | No hosted catalog updates arrived because production returns HTTP 509. |
| Launch to first content view | 3.7–4.4 s | Wall clock from `simctl launch`, three cold runs. |
| Peak memory, first launch | 377 MB | `phys_footprint_peak` after 45 s. |
| Peak memory, later launch | 251 MB | Same measure. |

**Computed storage bounds (not measured).** Each signed catalog store keeps a current and a previous slot and writes a new release atomically, so peak disk during an update is about three times the release: about 100 MB for One Piece (33.3 MB envelope) and about 14 MB for Pokémon. Price group files are capped at 128 MiB, plus 8 MiB for the legacy Pokémon set cache. Worst case, about 250 MB beyond the app bundle.

**Proposed budgets for owner approval:** bundle growth within 5% per stage; data container under 300 MB; launch to first view no slower than this baseline; peak memory under 400 MB on first launch.

## Parity and release gates

Run `python3 scripts/catalog_parity.py <game> --before A --after B` with the appropriate inputs below. A reviewed exception must include the exact before and after digests and a reason. For mirror price coverage, supply both complete, captured `market-prices/v1` directories with `--before-prices` and `--after-prices`. The comparator verifies feed hashes and build identifiers and tracks the presence of each priced product and finish. [Comparator](../../scripts/catalog_parity.py)

| Game | Input | Retained comparison |
| --- | --- | --- |
| Yu-Gi-Oh! | v1 `catalog.json`, including reference printings and seed price coverage | 687 sets and 47,956 printings |
| One Piece | Signed envelope or release payload | 134 products and 4,383 printing records in the signed production seed |
| Lorcana | Seed directory containing `discovery.json` and `market.json` | 19 declared sets and 3,576 physical printing records, plus discovery and sealed records |
| Pokémon | Repository root with signed checklists, bundled checklists, review evidence and retained market mappings | 157 bundled checklist entries and 32,428 slots, plus the signed release inputs |
| Magic | Retained Scryfall `sets.json` and `default-cards.jsonl[.gz]` | 1,067 directory sets and 108,232 English paper printings in the retained T7 capture |

These runs establish structural parity of the retained inputs. Production mirror receipts are required to prove live priced-product coverage, and the persistent collection fixture must resolve every old printing ID. The release gate also needs the fresh install and upgrade drills, corruption and interruption recovery, low disk space, and provider failures. A fresh offline install can display eligible bundled seed quotes and prices previously acquired on a device can survive an outage.

The catalog coverage workflow compares the four repository-backed catalogs against the pull request base, including both One Piece envelopes. A pull request with reviewed changes can supply `scripts/catalog_parity_allowlists/<game>.json` and use `one-piece-owner.json` for the owner envelope. The workflow applies allowlists changed by that pull request. Magic and production mirror coverage need their retained captures. [Catalog coverage workflow](../../.github/workflows/catalog-coverage-tests.yml)

The price publication job now revalidates the Firebase pointers inside the existing shared production lock. An intact cache retains verified immutable files and a missing or damaged cache triggers the original full restore. The job checks pointers and rejects older price builds immediately before deploy. Fixture tests cover 304 reuse, a changed pointer, partial caches and a missing previously verified revision. The hosted workflow still needs an origin that can serve successful pointer and artifact requests. [Workflow](../../.github/workflows/yugioh-catalog.yml) · [Restore cache](../../scripts/catalog_hosting_cache.py)

One Piece and Yu-Gi-Oh! each publish a compact `market-price-scope.json` next to the catalog pointer. Each file binds product and finish rows to its catalog revision and pointer digest. Firebase stages both scopes from the verified catalog tree under the shared production lock. The price job downloads the two scope files and checks both byte for byte against the restored catalogs before deployment. The first deployment can derive a missing scope from the existing verified legacy input. The separate Yu-Gi-Oh! candidate build still resolves its approved parent. The local One Piece publisher regenerates its scope after staging the new pointer. [Scope implementation](../../scripts/market_price_feeds.py) · [Price workflow](../../.github/workflows/yugioh-catalog.yml)

The remaining Stage 1 publication work is production readback of the scope files and the verified archive inventory, both blocked by HTTP 509. Group downloads now recheck the build marker only when the files carry a different build stamp, not on an ordinary HTTP failure. Preserve the build marker and product/price consistency checks when publication moves to R2.

## Executed verification

- ProfileLocal on the iOS 27.0 review simulator covered 808 distinct cases across pricing, game integrations, activation, recovery, variant resolution, portfolio eligibility and Collection. The final result for each case was 797 passes and 11 skips. The Yu-Gi-Oh! integration run caught an unnormalized cancellation in the collection refresh. The targeted rerun passed after the repair and verified that a historical mirror quote keeps its original date. The One Piece withdrawal rerun verified that a late response cannot restore a withdrawn lane. The `ScanStash-Stage1-*.xcresult` bundles are on the T7 SSD.
- The catalog and market-feed Python selections passed all 82 cases. The publication tests used local fixtures. Production workflow execution and device verification remain open.
- The scope changes passed 60 focused Python cases across market feeds, Hosting restoration and both One Piece publishing paths. A local replay of the price workflow requested only the two compact scopes. The bundled projections were 47,643 bytes for One Piece and 1,298,421 bytes for Yu-Gi-Oh! before compression. An intervening catalog approval blocked stale prepared prices in the fixture.
