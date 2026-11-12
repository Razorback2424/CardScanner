# ScanStash launch review implementation handoff

**Status:** proposed ordered work; no fixes implemented by this review.
**Baseline:** main at 2527c9b plus the preserved dirty working tree reviewed on 2026-11-10.
**Evidence:** [independent audit](../audits/launch-review-2026-11-10.md). **Product authority:** [launch contract](../release/launch-contract.md).

The ordinary scan flow, app-owned physical identities, serialized ownership/ledger/activity writes, current-price policy and separation between market charts and portfolio history are constraints to preserve. Re-read current source/diffs before each package: this is a handoff from a dirty candidate, not permission to overwrite the existing fixes.

## Order and dependencies

| Package | Result | Depends on |
| --- | --- | --- |
| W0 | Freeze scope and acceptance ledger | Start here; no app change required |
| W1 | App-funded JustTCG access without customer keys | W0 and active operator tier/budget |
| W2 | Approved production game/catalog activation | W0; coordinate mapping generation with W1/W4 |
| W3 | Accurate, honest shipped centering workflow | W0 and boundary/annotation agreement |
| W4 | Special-printing and product/price authority reconciled | W0; verify final mappings after W2 |
| W5 | Focused accessibility layout fixes | Can proceed after W0; preserve current behavior |
| W6 | Candidate journeys, performance and failure recovery accepted | W1–W5 completed or explicitly dispositioned |
| W7 | Distribution, legal and purchase acceptance | Final source/configuration frozen after W6 |

Small W5 fixes need not wait for backend work. Do not start speculative refactors while W1–W4 remain unbounded. Each implementation change should have its own cause, smallest patch, targeted validation and updated evidence; the reviewer will independently verify the final result.

## W0 — Freeze what this build promises

**Intended behavior:** the support manifest, UI, release configuration and marketing describe the same product. Keep the five-game, on-device, $9.99 US base-price non-consumable Collector Tools decisions. Local StoreKit supplies localized prices; there are no subscriptions or scan credits.

**Approach/files:** fill the manifest in [launch-contract.md](../release/launch-contract.md) by capability, language, family/era, raw/graded/sealed, acquisition route, price/history, artwork and offline behavior. Use CardGameRuntimeContainer and each runtime/adapter as source evidence. Keep unknowns explicit. Reconcile the historical S15.05 version/build finding with the current audit; ordinary Settings now exposes both.

**Acceptance:** every promised cell is concrete and linked to a candidate check; no Debug owner route is treated as Release support; every failed/skipped check has an applicability disposition. Record SHA plus working-tree/source/configuration identity. Source fingerprints and initial status are in the external review artifacts.

**Risks:** silently reducing scope, overwriting existing user work, or counting a test fixture as normal acquisition. No architecture/schema change is needed.

## W1 — Deliver operator-funded pricing access

**Addresses:** LR01. **Intended behavior:** a fresh customer with no provider account/key can use the promised history, graded and sealed features. Existing raw prices, stored evidence and offline editing remain useful; outages and missing mappings never become zero prices or false successful checks.

**Approach:** use the already selected paid JustTCG service with server-held credentials and a bounded app-feature interface. Freeze request/response contracts around exact supported product/finish/grade identity, provenance, source date, retrieval date, explicit absence, mapping failure and retry/quota state. Reuse the app's existing price-policy seams. Preserve functioning Scryfall/TCGdex/daily-feed paths; this package is not a mandate to migrate all raw pricing.

Relevant code: PriceVendorCredentials, JustTCGTransport, JustTCGV1Client, JustTCGV2GradedClient, ProductPriceService, CardMarketHistoryService, PriceFallbackQuoteResolver, PriceRefreshController, game price adapters and ScannerSettingsView. The [shared-cache plan](shared_pricing_cache_plan.md) is a proposal, not evidence that Firebase or any backend has already been selected/deployed.

Confirm active tier, operator cost/quota budget and published commercial-use terms. Avoid exposing the shared key or creating an arbitrary proxy/raw data product. Evaluate inventory and price-history exports against the actual licensing boundary; do not assume ordinary paid-tier consumer display needs additional written permission. Update privacy/support wording for the implemented backend without adding an unnecessary user account flow.

**Acceptance/validation:** fresh no-key install; raw exact history, supported grader/grade and sealed product; older versus newer quotes; provider-confirmed missing data versus mapping/transport failure; 401/403/429/5xx, cancellation, expiry, offline cache and relaunch. Check one exact holding across receipt, Browse, detail, Collection and Portfolio. No provider series backfills the local ledger. Add meaningful transport/contract regressions and rerun PricingTests, graded/history, refresh lifecycle/structural-write, scanner and purchase neighbors as affected. Include real funded-provider receipts and quota accounting.

**Regression risks:** broad cache-key collisions; currency leakage; using fetch time as market freshness; stale publication after correction/removal; depleting a shared quota; accidental purchase gating of free inventory features. Keep schemas compatible and keep provider credentials out of the binary.

## W2 — Activate the approved production content routes

**Addresses:** LR02/LR04. **Intended behavior:** the distribution app supports its approved One Piece scope and can receive signed Pokémon updates while surviving bad or unavailable releases safely.

**Approach/files:** Config/OnePieceCatalogProduction.xcconfig, PokemonCatalogProduction.xcconfig, MagicCatalogProduction.xcconfig; OnePieceCatalogBootstrap/Coordinator/Registry; PokemonCatalogCoordinator; SignedCatalogUpdateClient/ReleaseStore; catalog generators/publishers and the existing [One Piece setup](../release/one-piece-production-setup-2026-10-23.md) and [signing runbook](magic_catalog_key_handling_runbook.md). Re-read scripts/AGENTS.md before publication tooling changes. Use reviewed data, dedicated approved public pins and the established protected publication process. Do not copy local owner bootstrap resources or bypasses into Release.

Recheck the exact configured endpoint before editing code. Pokémon's /v1/current.json was 404 in this review, while the mapped 24722 shared price-feed paths worked. Fix the demonstrated delivery gap without declaring unrelated feeds broken. Regenerate/freeze seeds and manifest against the actual approved publication. Respect separately held, disabled or read-only records.

**Acceptance/validation:** installed Release readback matches the manifest; normal One Piece recognition/choice → save → reopen → price → removal/Undo → CSV; signed baseline and N+1 update; offline cold restart; malformed/signature/rollback/incompatible updates retain the last approved generation. Old choices cannot authorize writes after withdrawal, and recognition/Browse/import/pricing agree on generation. Run affected activation/integration/signed-store suites and catalog package/script tests. Retain live readback and rollback receipts separately from simulator passes.

**Regression risks:** mismatched game/key, omitted project resources, changing existing UUIDs or ownership keys, granting held variants, reviving withdrawn price authority and local/production flag leakage. Deployment requires a concrete reviewed candidate and the established owner publication authorization; prepare it fully before seeking any still-required approval.

## W3 — Close production centering accuracy and editing acceptance

**Addresses:** LR03. **Intended behavior:** useful initial guides, recoverable manual editing, exact typed Done semantics and an honest confirmed export on representative supported photos. Keep geometric estimates distinct from calibrated grading claims.

**Approach/files:** CardCenteringAnalyzer, measurement/spatial/boundary-evidence models, CardCenteringView/Canvas/ReviewSheet, CardCenteringExport and the [guided-repair authority](../audits/centering-guided-repair.md). Follow review/AGENTS.md and the existing centering acceptance contexts. Begin with the failing initial-guide test, native overlays and independent boundary identity. Resolve the competing definition in the ambiguous reference fixture before optimizing against it. Do not assume one coordinate-transform fix explains all four photos.

Keep the current confirmation/geometry/reference guards, native/working/view coordinate distinctions, localized drafts, synchronous precision commit, Undo and cancellation generations. The current hands-on test and 47 executed precision cases pass; preserve them. No source edit is justified merely to reproduce their existing behavior.

**Acceptance/validation:** unchanged 2 pp development criterion passes on the ordinary production analyzer; no new invented reference or encasement edge; representative independent/held-out photos meet the frozen contract. Capture native overlays and actual exports, standard and accessibility phone/tablet layouts, rotation, replace-photo/cancel, invalid and localized drafts, Done/blur/refocus/removal, Undo/Reset and stale share snapshots. Profile the shipped route on representative hardware with large source images.

The supplied-layout, Gengar, Prismatic and assisted-latency gates remain DEBUG research failures. They may stay outside launch acceptance only with their current compiled-out/unadvertised reachability evidence and preserved tests. Promoting that path reopens its accuracy/timing gates. Do not weaken any annotation, tolerance, budget or skip condition.

**Regression risks:** choosing a plausible interior stripe, fixture-specific tuning, losing image orientation/scale, stale analyses/exports, ratio approval surviving a new image or invalid geometry, and lowering fidelity to improve timing. A change in supported scope/claim or applicable acceptance requires an explicit owner decision, not a silent test edit.

## W4 — Reconcile physical coverage, prices and exact marketplace products

**Addresses:** LR06 and the unresolved support-manifest evidence. **Intended behavior:** high-certainty ordinary scans retain their speed; special printings do not receive an authoritative but unsupported finish, price or product link.

**Approach/files:** VariantResolver/VariantEvidence and bounded Pokémon minima; LegacyResolvedCard; Pokémon signed overlays/rules; MagicTreatmentCatalog and game catalog/recognition adapters; Lorcana physical/discovery catalogs; Yu-Gi-Oh! product/edition membership; TCGplayerLinkBuilder; price mappings and CSV adapters. Use current catalog/data authorities and public product/physical evidence before changing any generated resource.

First resolve the explicit policy conflict: incomplete Pokémon singleton membership currently auto-resolves and current tests require it, while the launch contract forbids treating incomplete coverage as certainty. Obtain an explicit scope/authority decision. Sample high-value/known-risk families independently and distinguish membership evidence from exhaustive coverage. Preserve exact printing identity in every comparison: the audit's earlier comparison of Pitch Black 001's editor with 30th-005's market lane is withdrawn. Current source already supplies Holo for the reviewed 30th mapping; no finish change is justified by that comparison.

Constrain changes to demonstrated affected families and reviewed evidence. Preserve user-selected and unknown historical values. Keep printing, finish, treatment, edition, slab/certificate and sealed identity distinct. Preserve current exact catalog correction and in-writer validation; do not reinstate a game-wide picker or a search fallback for marketplace links.

**Acceptance/validation:** declared physical scope agrees across scan choices, Browse, corrections, CSV, stored identity, current quote, history and marketplace product. Include missing/conflicting evidence, incompatible Finish Lock, unverified coverage, treatment-qualified products, first-edition/Shadowless, retained unsupported values and catalog withdrawal. Run affected resolver/parser, game, pricing, link, activity/import and key/ledger tests. Independently open a frozen representative set of product links and record exact product/printing agreement. Repeat live price checks only for approved mappings and retain source dates/coverage gaps.

**Regression risks:** adding friction globally; using price availability to define ownership; collapsing a treatment into generic foil; automatic rekeying of user corrections; trusting fixture assertions as physical truth. A validated risk may require a small authority/data fix, not an engine rewrite.

## W5 — Repair the two demonstrated accessibility layouts

**Addresses:** LR07/LR08. **Intended behavior:** Collection's placeholder/query remain legible and Portfolio's movement heading/actions remain readable and usable through the largest Dynamic Type size.

**Approach/files:** collectionSearchField in CollectionView.swift and the historical movers header in PortfolioView.swift. Let search content determine vertical size with padding and a minimum target; adapt the heading/info/See all arrangement to available width or accessibility size. Use existing view components and system text styles. Do not cap Dynamic Type, globally shrink fonts, redesign the tabs or alter queries/accounting.

**Acceptance/validation:** inspect real screenshots at standard and largest text on phone and iPad sidebar; focused typed query, keyboard/search clearing, long heading, every period label, populated/empty movement and See all/explanation navigation. Compare with the audit's phone-collection-accessibility.png, iPadCollection/detail-accessibility.png and phone-portfolio-accessibility-scrolled.png. Verify touch targets and spoken labels/order on a device. Run only relevant query/render/navigation checks if behavior changes; do not add tests that merely repeat the layout implementation.

**Regression risks:** search/header height swallowing the viewport, unexpected scroll jumps, keyboard/safe-area regressions and changed focus/selection. Keep debounce, stable navigation IDs and background service ownership intact.

## W6 — Complete the candidate journeys and measure real workloads

**Intended behavior:** each promised task reaches a durable, understandable result through normal UI, including interruption and failure. This is acceptance and diagnosis first, not permission for speculative performance rewrites.

Use the launch contract's J01–J12 with a disposable copied/synthetic store. The fresh review already verifies add/edit/remove/Undo/history; native CSV save/readback and import preflight/cancel; real-photo centering confirmation/Done/export; iPad selection/rotation; single-card JPEG/ZIP generation and inspector entry. Do not substitute those bounded checks for the remaining journeys.

Complete: a manual import into an empty disposable store, replay and interrupted resume; sale/trade and activity correction/restoration; custom artwork replace/remove and source recovery; price-only scanning with no ownership; failed recognition recovery after relaunch; real missing/offline artwork sharing; listing inspector return, batch cancel/partial failure, Files/Photos/AirDrop delivery; permission denial/settings change, camera contention, foreground/background and iPad multitasking recovery. Confirm counts, keys, ledger/activity and displayed prices after each durable action. Preserve the owner's only collection.

Follow the [existing hang plan](hang-inspection-plan.md) for current Release-device evidence: cold/populated launch, Browse/search/clear/back, collection scroll during refresh, aged history/chart ranges, 1,000/5,000-row imports, large/48 MP photos, batch tools and a sustained physical stack including repeated identical copies separated by removal. Correlate signposts and actor/lock/CPU/memory traces. Treat the older device-hang reports as unresolved until reproduced or disposed with evidence on the repaired candidate. Use Instruments/ETTrace/memgraph skills only for the measured issue; do not infer real-device speed from Debug simulator wall time.

**Acceptance:** representative iPhone/iPad on minimum and latest supported OS; largest text and spoken VoiceOver; no lost/duplicate ownership, false success, dead recovery, unexplained failure or unacceptable measured workload. Record exact configuration, data size, provider state, source version and evidence. Any demonstrated defect becomes its own small implementation package with a meaningful regression and independent rerun.

**Risks:** benchmarking while unrelated heavy jobs distort timing; accepting automatic test constructors as rendered UI; mutating personal data; fixing the scanner based on a simulated camera failure. Live CloudKit convergence stays outside on-device 1.0.

## W7 — Freeze and accept the distribution candidate

**Addresses:** LR05 and remaining G07–G09 evidence. **Intended behavior:** the shipped binary, purchases, services, legal pages and App Store claims match what passed.

Publish/configure the owner-approved privacy/support pages; inspect the built plist and open both from the installed app. Align privacy manifest, permission descriptions, actual backend data flows/retention, provider/artwork rights and App Store privacy answers. Recheck file-protection/continuity after first unlock and OS/app upgrades. Do not imply that restoring a purchase restores a deleted on-device collection or that CSV restores artwork/history.

Verify the approved non-consumable in real sandbox/TestFlight: localized price, purchase/cancel, pending approval, relaunch/offline ownership, restore with no purchase, revocation/refund and interrupted purchase/issue resolution. The local fourteen passing tests and one skipped interruption test do not close this gate. Free scans, collection, corrections, import/export and single-card listing photos must work without purchase.

Build/archive with the intended signing, entitlements, minimum OS and iPad orientations; confirm owner/debug/testing routes and resources are absent, production catalogs/endpoints are exact and no shared pricing key ships. Run all applicable mandatory automated checks on the frozen source, with the research exclusions and all skips explicitly reconciled. Complete final native J01–J12 and inspect submission metadata/screenshots/review notes against the manifest. Do not call a simulator Release compilation an accepted archive.

**Finish line:** no known in-scope defect, no unexplained applicable test failure, all nine contract gates backed by candidate evidence. Record any explicit owner exception as a changed claim/acceptance decision. New sync, new games, unadvertised DEBUG research, blanket Swift 6 migration and speculative cache/projection rewrites can follow later.
