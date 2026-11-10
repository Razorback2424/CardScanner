# Card Scanner launch contract

**Status:** current release finish line — adopted 2026-11-09 at owner request.
**Pricing amendment:** 2026-11-09 — owner requires an appropriate commercial
pricing API for launch. **Provider selected 2026-11-10:** paid JustTCG; exact
tier, active subscription and operator-managed integration remain unverified.
**Source:** owner-supplied *Card Scanner Launch Contract — Scanstash 1.0 system
definitions and release acceptance* (prepared 2026-11-09, repository baseline
`df6d4c0`). This Markdown is the repository authority; the .docx is not
committed. **Release decision:** not ready — no gate has passed.

This contract defines the finish line and the work needed to demonstrate it. It
does not certify the current app. It replaces the archived
[go/no-go framework](../legacy/card-scanner-1.0-go-no-go-framework.md). Approved
product decisions stay in force, including the paid Collector Tools offer and
on-device storage. Validation against the repository is recorded in
[§9](#9-repository-validation--2026-11-09).

> Card Scanner is ready to launch when every supported customer journey works
> correctly in the distribution build, no known user-visible defect remains in
> that scope, and the required correctness, usability, recovery and device checks
> have evidence of passing. Unexpected inputs and unavailable dependencies must
> produce an understandable, safe outcome. They must never silently change what
> the user owns or imply a result that did not happen.

## 1. What bug free means

A bug is a departure from a defined customer promise: wrong information, lost or
duplicate work, a failing control, an unfinished workflow, misleading feedback,
unacceptable responsiveness, or layout/accessibility problems that prevent
ordinary use. A crash is only one kind.

Testing cannot establish freedom from every undiscovered bug. The enforceable
standard is **zero known defects in a frozen supported scope after deliberate
verification**, with safe behavior for unsupported or unavailable cases.

| Example | Required outcome |
| --- | --- |
| A card cannot be read reliably | Offer a correction or review path; never save a guessed identity. Ordinary supported cards still meet completion and friction targets. |
| A provider has no exact price | Keep the card owned, mark its value unavailable and explain the gap. A supported lookup broken by app code is still a defect. |
| An owned card appears at two prices | For the same exact holding and selected evidence, all owned-value surfaces agree. A different source, date, grade or market context is labeled. |
| Centering Done ignores the last edit | Release-blocking even without a crash and even if the math tests pass. |
| A button is clipped at large text | Release-blocking when it impedes the promised task; a spacing preference without a functional defect is a design improvement. |
| An unfinished research mode fails | Outside acceptance only if unreachable in the shipped binary, unadvertised and not affecting shared production code. |

Severity sets repair order; it never silently waives a known defect. Order: data
corruption, wrong identities, wrong ownership, false prices, payment errors and
privacy breaches; then broken tasks and recurring friction; then polish, which
still must close. Credible user reports and failed applicable acceptance tests
are investigation items even without a formal issue. An older-build report closes
only by verification on the candidate. Any deliberate exception is recorded as
**approved by Sean**, never relabeled as bug free.

## 2. Launch boundary

Five games: Pokémon, Magic, Yu-Gi-Oh!, One Piece and Lorcana. Do not silently drop
a promised game or paid tool to turn the status green. Support is declared per
capability and card family.

| Area | Boundary for this release |
| --- | --- |
| Free | Scanning, collection access and corrections, basic inventory import/export, single-card listing-photo output — all usable without Collector Tools. |
| Paid | Approved $9.99 US base-price non-consumable Collector Tools: batch listing photos and guided centering. Show the localized StoreKit price. No subscription or scan credits. |
| Pricing service | Launch uses app-funded paid JustTCG, selected by the owner on 2026-11-10. Supported price-history charts, graded prices and sealed prices work without customers obtaining or entering a provider API key. Active tier, coverage and production acceptance remain open. |
| Storage | On-device continuity required. Live iCloud sync deferred. Do not promise collection restoration after app deletion because a purchase can be restored. |
| Platforms | iOS/iPadOS 18.0+, iPhone and iPad. Phone portrait and all four iPad orientations tested as applicable; the archive must confirm the declarations. |
| Card support | Freeze game, language, era/set/product families, raw/graded/sealed capabilities, physical variants and acquisition routes. Record price and artwork coverage separately from identity/ownership coverage. |
| Offline | Saved holdings, cached identities, existing evidence and local editing stay usable. An unseen card or remote quote may need connectivity; the app says so and keeps recoverable work. |
| Excluded | New games, binder-page recognition, social features, automatic marketplace listing, professional grading, a new sync system or a major redesign. |

### Pricing service for launch (mandatory product and licensing prerequisite)

Card Scanner will utilize paid JustTCG at launch, selected by the owner on
2026-11-10. Selection does not certify an active subscription, coverage or
integration. The app operator funds and manages provider access. Customers must
not need a separate provider account, subscription or pasted API key to use the
pricing capabilities promised in the support manifest. This does not change the
approved Collector Tools entitlement or price.

**Current implementation gap:** JustTCG access is bring-your-own-key (BYOK).
`PriceVendorCredentials` stores the customer's key in Keychain,
`JustTCGTransport` rejects unauthenticated requests, and Settings says the key is
required for market history, graded listings and provider-backed sealed prices.
Saved prices and cached history remain available. This implementation does not
meet the launch access requirement. It is an open product, licensing and
integration prerequisite, not a newly observed runtime bug or an accepted launch
limitation.

Before G07 can pass:

- Record the selected provider and active app-owned paid plan, recurring cost
  owner and expected launch traffic/quota budget. Confirm actual endpoint and
  exact game, printing/finish, raw/graded/sealed and history coverage in the
  support manifest; naming a provider does not establish coverage.
- Retain dated commercial-use terms and any required written authorization for
  end-user display, caching, history retention and permitted exports. JustTCG's
  [terms](https://justtcg.com/terms) and
  [commercial-use guidance](https://justtcg.com/docs/commercial-use), checked
  2026-11-10 (terms updated 2026-11-04), permit end-user display and server-side
  caching on an active paid subscription; standalone data redistribution is
  prohibited, and stored-data use rights end with the subscription. Review
  exports against those limits. A free-tier or customer-key workaround cannot
  close this gate.
- Integrate operator-managed access without exposing shared provider secrets in
  the shipped app. Validate a fresh distribution install with no customer key:
  supported charts, graded prices, sealed prices and refreshes work, while
  missing coverage, quota exhaustion, outages and expired credentials produce
  honest, recoverable outcomes. Settings, support and privacy copy match.

The [shared-pricing-cache plan](../plans/shared_pricing_cache_plan.md) is a gated
implementation proposal. Its Firebase architecture remains undecided; the
commercial API and no-customer-key requirements above are mandatory for launch.

### Support manifest (mandatory release artifact)

One row per game and capability, matching the installed app and App Store claims.
An empty or ambiguous mandatory cell is an unresolved scope gate. Current cells
cite the latest authority only; none is verified on a candidate.

| Capability | Pokémon | Magic | Yu-Gi-Oh! | One Piece | Lorcana |
| --- | --- | --- | --- | --- | --- |
| Card families and languages | Open — [coverage audit](../audits/catalog-coverage-audit-2026-11-01.md) | Open — [recognition plan](../plans/magic_historical_recognition_plan.md) | Open — [plan](../plans/yugioh_code_implementation.md) | **Production disabled** — `ONE_PIECE_CATALOG_ROLLOUT_MODE = disabled` | Open — 1,616 ordinary printings; held/premium/promo read-only ([rollout](../research/lorcana-normal-pricing-rollout.md)) |
| Scan / Browse / manual entry | Open | Open | Open | Open | Open |
| Save permitted | Open | Open | Open | **No** — `ONE_PIECE_COLLECTION_WRITES = NO` | Open |
| Raw / graded / sealed | Open | Open | Open | Open | Open |
| Price and history coverage | Open | Open | Open | Open | Open |
| Artwork source | Open | Open | Open | Open | Open |
| Offline behavior | Open | Open | Open | Open | Open |
| Visible limitations | Open | Open | Open | Open | Open |

The five-game finish line includes activating and validating the approved One
Piece production route. The production price-feed URL **is** configured
(`TCGCSV_PRICE_BASE_URL` in `Config/PokemonCatalogProduction.xcconfig`); live
publication and provider responses remain separate evidence.

## 3. Systems and acceptance requirements

Responsibility boundaries within the existing code — no new architecture or file
moves. Each requirement has a stable ID so a defect, fix and verification point
to the same promise. All requirements start **NOT VERIFIED** for the next
candidate; the Status column records only failures already known.

| Repository area | Role |
| --- | --- |
| `TradingCardScanner/App` | Startup, dependencies, lifecycle integration, storage setup. |
| `TradingCardScanner/Views` | Navigation, screens, interaction state, presentation of authoritative domain results. |
| `TradingCardScanner/Models` | Holdings, physical identity, prices, activity, history, centering data. |
| `TradingCardScanner/Services` | Recognition, resolution, writes, pricing, replay, export, purchases, catalog delivery. |
| `TradingCardScanner/Games` | Shared adapter contracts and five game implementations. |
| Catalog seeds and snapshots | Versioned runtime data and reviewed mappings; stale data can break the product with unchanged Swift. |
| CatalogCore packages and publishers | `PokemonCatalogCore`, `MagicCatalogCore`, `OnePieceCatalogCore`, publisher tooling and scripts. |
| `Config` and Xcode project | Feature activation, endpoints, signing, entitlements, permissions, platforms, release variants. |
| Tests and `TestFixtures` | Automated checks and samples; selection, expected failures and excluded research must be explicit. |
| `docs`, `references`, `review` | Requirements and dated evidence; current code and verified runtime behavior resolve stale narrative. |

### S01 App startup and navigation

Get a new or returning user into usable screens with the correct services and
collection. Owns navigation and permission handoffs, not domain truth.
*Code:* `App/TradingCardScannerApp.swift`, `Views/ContentView.swift`,
`AppOpeningView.swift`, `CollectionStorageBootstrapView.swift`,
`ScannerSettingsView.swift`.

| ID | Requirement | Status |
| --- | --- | --- |
| S01.01 | Fresh install, empty collection and populated relaunch reach a usable app without an indefinite opening screen. | Not verified |
| S01.02 | Camera permission allowed, denied, restricted and later changed in Settings each give a clear next action. | Not verified |
| S01.03 | Tabs, Back, Done, keyboard and sheet dismissal preserve or discard work as visibly expected. | Not verified |
| S01.04 | Interruption and resume do not duplicate navigation, leave a dead overlay or publish a previous screen's result. | Not verified |

*Verification:* `AppOpeningTests`, `LaunchModelActorTests`; native install, navigation and interruption journeys.

### S02 Camera and OCR

Turn the live image into current printed evidence; keep guide, capture
coordinates and recognition region aligned.
*Code:* `Services/CardScanner.swift`, `ScanParser.swift`, `CameraCapabilities.swift`,
`CameraRotationTracker.swift`, `Views/CameraPreview.swift`, game recognition adapters.

| ID | Requirement | Status |
| --- | --- | --- |
| S02.01 | Preview becomes usable; focus/framing feedback is understandable; supported orientations stay correct. | Not verified |
| S02.02 | Glare, sleeves, blur, partial cards, multiple identifiers and OCR misses never authorize an unsupported identity. | Not verified |
| S02.03 | Leaving Scan, backgrounding, interrupted capture and media-service reset stop/restart appropriately without a restart loop. | Not verified |
| S02.04 | A sustained physical session meets the frozen responsiveness budget without progressive hangs, memory failure or unusable thermals. | Not verified — device hang investigation open ([plan](../plans/hang-inspection-plan.md)) |

*Verification:* `ScanParserTests`, `CameraRotationTests`, `CardLatchTests`; physical camera and sustained-use recordings.

### S03 Exact card and variant identity

Resolve the physical object the evidence supports: game, printing, finish,
treatment, language, edition and graded details.
*Code:* `Services/CardCatalog.swift`, `VariantResolver.swift`, `GradedLabelParser.swift`,
`ScannedGradedResolver.swift`, `Models/CardVariant.swift`, `ProductIdentity.swift`,
`Games/Core` and adapters.

| ID | Requirement | Status |
| --- | --- | --- |
| S03.01 | Only validated evidence or an explicit user choice establishes identity; appearance or an incomplete singleton catalog cannot manufacture certainty. | Not verified |
| S03.02 | Conflicting games, printings or editions stay unresolved; a rejected modern identifier cannot become an unrelated historical match. | Not verified |
| S03.03 | Finish Lock applies only to physically possible variants and is visible while active; an incompatible lock asks for the missing decision. | Not verified |
| S03.04 | Chosen printing, finish, treatment, language and slab details survive select-to-save without substitution. | Not verified |
| S03.05 | How identity and variant were resolved is preserved, distinguishing catalog decisions from user confirmation. | Not verified |

*Verification:* `VariantResolverTests`, `GradedLabelParserTests`, `ScannedGradedResolverTests`; game integration and physical-choice tests.

### S04 Game catalogs and content delivery

Supply compatible reviewed data and capabilities to all surfaces; activate new
catalog generations safely.
*Code:* `Games/Core/CardGameRuntime.swift`, game registries/coordinators,
`SignedCatalogReleaseStore.swift`, `SignedCatalogUpdateClient.swift`, catalog
packages, seeds, publishers, `Config`.

| ID | Requirement | Status |
| --- | --- | --- |
| S04.01 | The distribution build enables the exact games and acquisition capabilities in the support manifest. | **Fail** — One Piece production rollout and writes disabled |
| S04.02 | Missing, corrupt, incompatible, stale or badly signed updates keep the last approved catalog or show an honest unavailable state. | Not verified |
| S04.03 | Activation makes recognition, Browse, printing choices and ownership admission agree; stale responses cannot authorize writes under an obsolete generation. | Not verified |
| S04.04 | Catalog changes never silently rewrite owned identities; any needed review is explicit. | Not verified |
| S04.05 | Coverage is checked independently of price availability; held/unreviewed objects cannot pose as ordinary supported printings. | Not verified |

*Verification:* game activation/integration tests, `SignedCatalogReleaseStoreTests`, catalog package tests; installed Release configuration and live-update/offline checks.

### S05 Scan session and recovery

Turn continuous recognition into intentional acquisitions with minimal
confirmation and persistent resolution of interrupted work.
*Code:* `Views/ScannerViewModel.swift`, `ScannerView.swift`, `ScanReviewSheet.swift`,
`ScanSessionOverlays.swift`, `Services/CardLatch.swift`, `ScanFeedback.swift`,
`UnresolvedScanStore.swift`.

| ID | Requirement | Status |
| --- | --- | --- |
| S05.01 | One continuously visible card adds once; two physical copies can be added deliberately; a glare gap is not a new copy. | Not verified |
| S05.02 | An unambiguous supported card takes the zero-tap path; a genuinely missing fact asks for the smallest useful choice. | Not verified |
| S05.03 | Added means the ownership write committed; a later pricing failure cannot become a retry that adds twice. | Not verified |
| S05.04 | Cancel, replacement card, new session, backgrounding and late responses cannot overwrite a newer choice or receipt. | Not verified |
| S05.05 | Needs Attention keeps intended work through interruptions and relaunch; successful retry retires the right item exactly once. | Not verified |

*Verification:* `ScannerViewModelTests`, `CardLatchTests`, `UnresolvedScanStoreTests`; mixed-stack and forced-interruption journeys.

### S06 Browse, artwork and discovery

Find, inspect and add the intended card while identity, images and prices load
independently.
*Code:* `Services/BrowseCatalog.swift`, `ArtworkFallbacks.swift`,
`CatalogSetCompletion.swift`, `Models/BrowseCatalogModels.swift`,
`Views/BrowseView.swift`, `CatalogCardDetailView.swift`, `SealedBrowseViews.swift`.

| ID | Requirement | Status |
| --- | --- | --- |
| S06.01 | Search, filters, sort, pagination, counts and selected set/game compose consistently and never show another request's result. | Not verified |
| S06.02 | The selected printing and variant reach the add operation unchanged. | Not verified |
| S06.03 | Cached identity and permitted actions stay usable during slow/failed pricing; a price spinner cannot hold the card hostage. | Not verified |
| S06.04 | Artwork matches the card and recovers after temporary failure; persistently missing expected artwork stays open. | Not verified |
| S06.05 | Set completion uses an honest denominator and distinguishes unknown/partial coverage from complete. | Not verified |

*Verification:* `BrowseFeatureTests`, `BrowsePresentationTests`, `PokemonClassicCollectionArtworkTests`; cached/live/offline visual checks.

### S07 Collection ownership and activity

Additions, quantities, corrections, removals and Undo, with the activity and
inventory ledger explaining them.
*Code:* `Models/CollectedCard.swift`, `CollectionActivity.swift`, `InventoryEvent.swift`,
`Services/CollectionStore.swift`, `CollectionWriteSerializer.swift`,
`InventoryLedger.swift`, collection views.

| ID | Requirement | Status |
| --- | --- | --- |
| S07.01 | One intended operation changes exactly the intended holding and quantity; repeated taps and retries cannot create phantom copies. | Not verified |
| S07.02 | Distinct variants stay separate; a correction preserves total ownership and sibling holdings. | Not verified |
| S07.03 | Ownership, activity and ledger commit together or stay unchanged on failure. | Not verified |
| S07.04 | Undo reverses its specific operation; consecutive adds then Undo keep earlier copies; repeated Undo is harmless. | Not verified |
| S07.05 | A read, delayed refresh or completed request for a deleted item cannot mutate ownership or resurrect a holding. | Not verified |

*Verification:* `OwnershipLedgerCompletenessTests`, `OwnershipConcurrencyStressTests`, `CollectionActivityHistoryTests`, `RefreshStructuralWriteTests`; reopen reconciliation.

### S08 Storage continuity and migration

Find, open and preserve the right on-device collection through launch, upgrade,
migration and recovery.
*Code:* `Services/CollectionStorageBootstrap.swift`, `CollectionStoragePolicy.swift`,
`CollectionStoreManifestStore.swift`, `CollectionStoreDigest.swift`,
`BackgroundModelActor.swift`, migration services.

| ID | Requirement | Status |
| --- | --- | --- |
| S08.01 | Successful writes survive termination and relaunch; upgrades keep identities, quantities, activity and supported valuation evidence. | Not verified |
| S08.02 | A failed read or migration shows recovery, never a successful-looking empty replacement. | Not verified |
| S08.03 | Old background work cannot write to a new storage session or publish stale state after a generation change. | Not verified |
| S08.04 | No network or iCloud account is needed for the local collection; Settings accurately describes local storage and deletion. | Not verified |
| S08.05 | Failures are tested on a copied fixture store, never the owner's only collection; CSV is not called a full backup without proof. | Not verified |

*Verification:* `CollectionStoreContinuityTests`, `CollectionStorageBootstrapTests`, `CollectionStoragePolicyTests`, migration tests; physical upgrade and reopen checks.

### S09 Exact pricing and refresh

Choose eligible evidence for the exact physical object, preserve chronology and
currency, and report refresh results honestly.
*Code:* `Services/PriceQuoteService.swift`, `PriceStore.swift`, `OwnedCatalogPrice.swift`,
`PriceRefreshController.swift`, `PriceRefreshTargets.swift`, `QuoteCache.swift`,
`PriceProvider.swift`, vendor services and game price adapters.

| ID | Requirement | Status |
| --- | --- | --- |
| S09.01 | A quote cannot cross finish, edition, treatment, grade, item-kind or currency boundaries without a labeled non-authoritative context. | Not verified |
| S09.02 | Owned-value surfaces use the same selected holding evidence; legitimate market comparisons state context and date. | Not verified — physical Mega Gengar report not reproduced on a candidate |
| S09.03 | Fetching now does not make old source data current; unknown age stays unknown; failed checks do not renew the market date. | Not verified |
| S09.04 | Late, invalidated or cancelled responses cannot replace newer evidence or restore a deleted holding. | Not verified |
| S09.05 | No quote, mapping gap, stale quote, transport failure and identity review have distinct outcomes; unknown price is not zero. | Not verified |
| S09.06 | Manual refresh, cancellation, edits during refresh and independent provider failures end in accurate progress and recoverable state. | Not verified |
| S09.07 | An active, app-funded commercial pricing service supplies the promised history, graded and sealed capabilities without a customer provider account or API key; coverage, rights, quotas and safe failures meet §2. | Not verified — paid JustTCG selected 2026-11-10; current access is BYOK, active-tier and production integration evidence open |

*Verification:* `PricingTests`, `PriceRefreshLifecycleTests`, `QuoteCacheTests`, `RefreshStructuralWriteTests`, per-game pricing tests; commercial entitlement evidence, exact live-provider readback and a fresh distribution install without a customer key.

### S10 Portfolio and history

Explain the value of actual holdings, excluded coverage and change over time
from the ownership and price ledgers.
*Code:* `Services/PortfolioEngine.swift`, `PortfolioReplay.swift`,
`PortfolioHistoryEngine.swift`, `PortfolioClose.swift`, `PortfolioCalendar.swift`,
`Models/Money.swift`, portfolio and history views.

| ID | Requirement | Status |
| --- | --- | --- |
| S10.01 | Current value reconciles to eligible unit prices × actual quantities, with clear priced and unpriced coverage. | Not verified |
| S10.02 | Acquisitions and removals are not gains or losses; market changes reconcile to the displayed range. | Not verified |
| S10.03 | Foreign-currency evidence is supported or explicitly excluded; no implicit dollar conversion. | Not verified |
| S10.04 | Missing or inconsistent history suppresses unsupported results instead of a plausible zero or fabricated change. | Not verified |
| S10.05 | Reopen, day rollover, timezone changes and rapid range changes cannot alter economic facts or show a prior selection's result. | Not verified |

*Verification:* `PortfolioLedgerTests`, `PortfolioReconciliationTests`, `PortfolioReplayEngineTests`, `PortfolioHistoryEngineTests`; hand-calculated fixture reconciliation.

### S11 Import, export and portability

Move supported data between files and the app without identity loss, duplicate
replay or false completion.
*Code:* `Services/CollectionCSV.swift`, game import adapters, file-picker/export
actions and diagnostics export.

| ID | Requirement | Status |
| --- | --- | --- |
| S11.01 | Mixed-game export and reimport preserve every field claimed round-trippable, including raw/graded/sealed identity and quantities. | Not verified |
| S11.02 | Interrupted import resumes only uncommitted rows; importing again as extra copies is an explicit different action. | Not verified |
| S11.03 | Malformed rows, contradictory keys, unsupported currency text and identity conflicts have specific outcomes and correct totals. | Not verified |
| S11.04 | Cancellation stops at a durable boundary and reports completed vs remaining work; no false all-or-nothing promise. | Not verified |
| S11.05 | The destination receives a real readable file; picker cancellation or failure does not alter collection data. | Not verified — native picker save/cancel open ([hang plan](../plans/hang-inspection-plan.md)) |

*Verification:* `CSVImportResumeTests`, `ImportedItemKindTests`, `CollectionKeyTests`; native Files export/import and supported-field comparisons.

### S12 Guided centering

An understandable geometric estimate from reviewed boundaries, reliable editing,
deliberate confirmation and matching annotated output.
*Code:* `Models/CardCenteringMeasurement.swift`, `CardCenteringBoundaryEvidence.swift`,
`CardCenteringSpatialMeasurement.swift`, `Services/CardCenteringAnalyzer.swift`,
`CardCenteringExport.swift`, `CardCenteringView`/`Canvas`/`ReviewSheet`.

| ID | Requirement | Status |
| --- | --- | --- |
| S12.01 | A new photo, rotation or replacement invalidates obsolete analysis and confirmation; late analysis cannot overwrite current work. | Not verified |
| S12.02 | Physical edges and printed boundaries stay distinct; initial guides are useful; uncertainty visible; invalid geometry cannot look credible. | Not verified — four historical initial-guide misses reproduce |
| S12.03 | Drag, numeric edit, zoom, pan and Undo affect the intended geometry; Done commits the latest complete localized input exactly once. | Not verified |
| S12.04 | Guides, ratios and export refer to the same current photo and geometry; confirmation explicit; automatic reporting stays disabled. | Not verified |
| S12.05 | Meet the frozen production accuracy and interaction requirements; DEBUG reference research stays separate with a reasoned applicability decision; tolerances never loosened. | **Fail (automated)** — six acceptance methods fail; each needs a shipped-behavior disposition ([ledger](../audits/centering-guided-repair.md#six-remaining-failures-focused-investigation--2026-11-09)) |
| S12.06 | Real users complete capture/import, correction, confirmation and actual share/save; result described as an estimate, not grading. | Not verified |

*Verification:* `CenteringReviewTests`, `CenteringExportTests`, `CenteringSpatialMeasurementTests`, applicable corpus/invariant tests; physical workflow evidence.

### S13 Listing photo preparation

Correct full-resolution listing images and usable exports from front/back photos,
including paid batches.
*Code:* `Views/EbayListingPhotosView.swift`, `ListingPhotoInspectorView.swift`,
`Services/EbayQuadrantCropper.swift`, `EbayListingPhotoExport.swift`,
`ListingPhotoLibrarySaver.swift`.

| ID | Requirement | Status |
| --- | --- | --- |
| S13.01 | Pairing, orientation, corners, crop order and names match the selection and inspected preview. | Not verified |
| S13.02 | One front/back pair produces ten images; two cards produce twenty decodable images in the correct folders. | Not verified |
| S13.03 | Large photos, source replacement, reordering, cancellation and retry cannot mix cards or publish obsolete output. | Not verified |
| S13.04 | Purchase dismissal, pending approval and recoverable failure keep in-session work. Draft restoration after process death is **not** promised. | Not verified |
| S13.05 | Files/ZIP/Photos delivery is tested by opening the result; permission denial leaves an alternative; prior exports stay valid. | Not verified |

*Verification:* `EbayQuadrantCropperTests`, `CollectorToolsTests` archive extraction; full-resolution pixel/file inspection and native destination checks.

### S14 Purchases and paid access

Sell and restore the approved non-consumable while keeping free capabilities and
customer work available.
*Code:* `Services/CollectorToolsStore.swift`, `Views/CollectorToolsOfferView.swift`,
`ProView.swift`, guarded centering and photo workflows, `CollectorTools.storekit`.

| ID | Requirement | Status |
| --- | --- | --- |
| S14.01 | Localized price visible before purchase; lookup failure is recoverable and never revokes an existing entitlement. | Not verified |
| S14.02 | Verified purchase unlocks both tools; cancelled, pending, failed, unrelated, unverified or revoked transactions do not. | Not verified — isolated state-logic tests only |
| S14.03 | Restore and transaction updates work across relaunch/account conditions; duplicate or late deliveries trigger no preparation or sharing. | Not verified |
| S14.04 | Refund/revocation removes future paid access without deleting collections, source photos or prior exports. | Not verified |
| S14.05 | Single-card output stays free, including one-card Batch; paid flows validated in sandbox/TestFlight with `LOCAL_COLLECTOR_TOOLS` absent. | Not verified — `SKTestSession` test not run; no sandbox/TestFlight run |

*Verification:* `CollectorToolsTests`, local StoreKit tests; real configured-product sandbox and TestFlight purchase/restore/interruption checks.

### S15 Presentation, accessibility and polish

Every reachable screen and control is understandable, consistent and usable at
supported sizes and accessibility settings.
*Code:* views throughout, `AppGlass.swift`, `ContentWidth.swift`, feedback/Undo
overlays, artwork and finish presentation, `PrivacyAndSupportSettingsView.swift`.

| ID | Requirement | Status |
| --- | --- | --- |
| S15.01 | Each screen has correct content, loading, empty, partial, error/offline and recovery behavior where applicable. | Not verified |
| S15.02 | No clipped primary controls, unreadable prices, wrong thumbnails, overlapping feedback, unexplained disabled actions or placeholder copy. | Not verified |
| S15.03 | Largest accessibility text, light/dark, iPad layouts and orientation changes preserve task completion. | Not verified |
| S15.04 | VoiceOver identifies cards, prices, uncertainty, controls, selected values and destructive actions in useful order; state not conveyed only by color. | Not verified |
| S15.05 | Feedback is prompt and reports success only after it happens. Version/build and support are discoverable in normal settings. | **Fail** — version/build appear only inside the Developer & Diagnostics sync-diagnostics export; support link shows "not available in this build" |

*Verification:* presentation/accessibility tests where available; screen-state screenshots; spoken VoiceOver checks; uncoached real-user completion.

### S16 Asynchronous work and dependency failure

Cross-cutting: stale requests, retries, cancellations and external failures must
not corrupt the current task.
*Code:* session/generation tokens, `CollectionWriteSerializer.swift`,
`StoreRevisionMonitor.swift`, bounded caches and circuit breakers, background
actors, network transports, view cancellation paths.

| ID | Requirement | Status |
| --- | --- | --- |
| S16.01 | Each long operation records owner, cancellation rule and success/failure state; every result is validated against current intent before applying. | Not verified |
| S16.02 | Slow network, timeout, offline, reconnect, rate limiting and malformed responses stay bounded and recoverable. | Not verified |
| S16.03 | Retry and repeated taps are safe; writes and side effects never repeat because a caller missed a completion. | Not verified |
| S16.04 | Backgrounding, foregrounding, changing card or leaving a screen cannot strand controls, lose committed work or replace newer state. | Not verified |
| S16.05 | Safe errors are insufficient if ordinary tasks routinely fail; measure completion separately from safe rejection. | Not verified |

*Verification:* concurrency, refresh, lifecycle and cancellation suites; fault injection; native interruption cases across critical journeys.

### S17 Distribution, support and release operations

The installed app is the verified app, with working content, purchases, support
and accurate claims.
*Code:* `TradingCardScanner.xcodeproj`, `Config`, `Info.plist`, entitlements,
`PrivacyInfo.xcprivacy`, catalog/feed publication, diagnostics/support surfaces,
release documentation.

| ID | Requirement | Status |
| --- | --- | --- |
| S17.01 | Record commit, local patch/hash, version/build, archive identity, configuration, catalog/feed revisions and test selection for the candidate. | Not verified — no candidate frozen |
| S17.02 | Install the actual TestFlight/distribution candidate, confirm features and endpoints, and verify no owner bypass or debug route certifies a production promise. | Not verified |
| S17.03 | Privacy/support URLs published, configured in the built app and opened from the installed UI; metadata and privacy declarations match behavior. | **Fail** — `CARD_SCANNER_PRIVACY_URL` and `CARD_SCANNER_SUPPORT_URL` empty (deliberately deferred launch prerequisite, not a code defect) |
| S17.04 | Non-consumable, agreements and submission details ready; production availability validated at release without treating sandbox as production. | Not verified |
| S17.05 | Every provider/content dependency has appropriate usage rights, observed working behavior and an outage path; diagnostics identify version and failure stage without unnecessary private material. | Not verified |

*Verification:* archive/TestFlight install evidence; built-config inspection; live link/provider checks; purchase configuration; App Review completeness.

## 4. Critical customer journeys

Each passes from the first action through its durable or delivered result, in
the real distribution configuration. A component test does not close a journey.
Record exact results, counts and output. All start **NOT VERIFIED**.

| ID | Journey and required result | Status |
| --- | --- | --- |
| J01 | Fresh install → permissions → usable app; repeat with denial and return from Settings; free capabilities still reachable. | Not verified |
| J02 | Mixed stack → correct identities/choices → exact copy counts → Collection → terminate → reopen; compare to an independently prepared inventory. | Not verified |
| J03 | Ambiguous/unavailable scan → Needs Attention → interruption/relaunch → retry/choice → one correct addition. | Not verified |
| J04 | Browse/search → exact printing/finish → add two copies → Undo latest → reopen; one earlier copy remains. | Not verified |
| J05 | Correct identity/finish/quantity → all surfaces and activity update → portfolio reconciles → relaunch keeps it. | Not verified |
| J06 | Fresh install with no customer provider key → supported price-history charts, graded and sealed prices → owned card across Browse/detail/Collection/Portfolio → refresh with newer, older and failed evidence; amounts, dates, exclusions and total reconcile. | Not verified |
| J07 | Export mixed inventory → open the file → import into an isolated fixture → compare fields; interrupt/resume and replay without duplicates. | Not verified |
| J08 | Centering photo → correct guides → localized numeric edit → Done → confirm → actual output; final edit and delivered geometry agree. | Not verified |
| J09 | One free pair → ten images; two paid pairs → twenty files in a readable ZIP; check order, orientation, names and pixels. | Not verified |
| J10 | Paid offer → cancel/pending/failure → retry/success → relaunch/restore → refund/revocation; free access and in-session work stay correct. | Not verified |
| J11 | Network loss, slow responses and background/resume; each task finishes or recovers without forced restart or data cleanup. | Not verified |
| J12 | Upgrade a copy of an existing collection → verify holdings/history → sustained use → next-day reopen; support links, version/build and diagnostics available. | Not verified |

## 5. Environments and measurable outcomes

Risk-based coverage: every critical journey, each game adapter and each important
failure transition, using deliberate combinations rather than every permutation.

| Dimension | Required coverage |
| --- | --- |
| Devices and OS | Slow/older supported iPhone, current/common iPhone and iPad; minimum declared OS plus current shipping OS. Record gaps. |
| Data size | Empty, small and representative collections, including the ~1,500-card workload ([follow-ups](../plans/release_followups.md)); add the largest intended collection, CSV and photo batch to the manifest before execution. |
| Card differences | Every game; ordinary cards; difficult printings, promos, parallel finishes, language/edition ambiguity, slab labels, enabled sealed routes. |
| Network and content | Fresh/cached, offline, slow, timeout, rate limit, malformed data, missing image, unavailable exact price, catalog generation change. |
| Lifecycle and concurrency | Cold/repeat launch, upgrade, background/resume, force quit around writes, rapid repeats, cancellation, switching card/screen mid-work. |
| Accessibility and input | Normal and maximum text, VoiceOver, Reduce Motion, light/dark, iPad orientations, English and decimal-comma entry. |
| Purchases | None, owned, unavailable product, cancel, pending, interrupted, verified/unverified, restore, revoked, duplicate and late updates. |
| Commercial pricing access | Fresh install without a customer provider key; active operator plan, missing/expired operator credentials, exhausted quota and outage; supported history, graded and sealed coverage. |

### Recognition acceptance

Proposed verification workloads — **not measurements already achieved**.

- Freeze a labeled 500-card normal-use corpus before measuring the candidate, with
  at least 75 distinct physical identities per included game; repeated frames do
  not inflate it. Independently label expected printing, acceptable choices and
  physical finish; keep genuine ambiguities. Add a separate 100-case
  difficult/regression set including previously reported failures.
- Zero observed silent wrong identities, wrong variants, phantom additions or
  false save confirmations in either corpus.
- ≥ 95% correct autonomous completion, overall **and per game**, on the subset
  determinable without human input. Eligibility is frozen independently of
  algorithm success. Success means the correct identity is durably saved within
  the frozen time budget; a clear but unresolved eligible card counts against
  the rate.
- ≥ 99% correct end-to-end completion on the ordinary supported corpus with the
  intended minimal confirmation. Report first-pass completion, retries,
  no-results and review rates separately.
- Every non-completion has an understood, safe outcome; no known deterministic
  failure hides inside the allowance. A newly found supported family is added to
  coverage; hard cases are never removed after failure.

### Responsiveness and experience

Existing frozen tolerances (especially centering) stay unless an evidence-based
scope decision changes them. Proposed targets elsewhere, measured at the 95th
percentile on the slow supported device with the setup frozen first: tap
response ≤ 100 ms; cached search/navigation ≤ 500 ms at the representative
workload; repeat launch to usable content and warm camera entry ≤ 2 s. Network
work is measured separately: immediate progress, independent controls stay
usable, a recovery action by 10 s for an unresolved ordinary lookup. Large
imports and batches need accurate progress and cancel.

At least two 30-minute physical sessions covering scanning, browsing, edits and
paid tools (memory, thermals, latency). Five collectors complete the relevant
journeys without coaching, with a second session including reopen or next-day
return, on users and devices outside the developer's setup. This defines an
exercise; it does not authorize contacting testers automatically.

## 6. Evidence and defect rules

| Status | Meaning |
| --- | --- |
| PASS | The specified check ran with retained evidence for the candidate (or a documented, valid unchanged component). Critical journeys still run on the final candidate. |
| FAIL | Observed behavior violates a requirement. Record expected/actual, reproduction, impact and source/build identity. |
| NOT VERIFIED | Not run, blocked, missing receipt, stale build, ambiguous attribution or incomplete device/provider evidence. Mandatory items here prevent launch. |
| OUTSIDE SCOPE | Deliberately unshipped and unpromised, with isolation and shared-code impact documented. Not a substitute for fixing an included capability. |

**Defect record:** requirement and journey IDs; affected game/card/device/build;
reproduction and expected result; user impact; screenshot/log/data comparison;
smallest safe repair; focused regression check; customer-path verification;
final disposition. Severity sets sequence; confidence says whether a finding is
confirmed. A source hypothesis or absent test is not a confirmed runtime bug.

**A fix is complete** only when the original failure no longer occurs, its data
effects are reconciled, the workflow passes and adjacent behavior stays correct.
A merged commit, isolated unit pass, screenshot of a screen opening or dismissed
error is not enough. Source fixes for import/identity defects do not repair
historical bad records; affected user data needs its own disposition.

**Evidence record:** build and source hash, command/selection, pass/fail/skip
counts, exclusions with reasons, environment, timestamps, catalog/feed revision
and location. Keep automated, inspected-UI, physical-device and
live-provider/purchase results distinct.

## 7. Starting point (2026-11-09)

Reconciled from source and retained records — not a fresh test run or a complete
bug census.

| Area | Position |
| --- | --- |
| Broad regression | 3,174 passed, 2 failed, 21 skipped across 3,197 cases; two long research classes not rerun wholesale; six centering gates unmet. Complete target uncertified ([progress](../../progress.md)). |
| Centering | Some failures concern default guide usefulness/accuracy, some DEBUG research. Disposition each against shipped behavior; neither six proven customer bugs nor all research. |
| Production vs local | One Piece production rollout/writes disabled. The `ReleaseLocal` configuration defines `LOCAL_COLLECTOR_TOOLS` (with `LOCAL_ONLY_SIGNING`), which marks the user owned; `Release` does not. Both need real release-configuration acceptance. |
| Owned prices | Code and simulator evidence address owned-price selection and stale evidence but do not certify the physical Mega Gengar case or live coverage. Reproduce on the candidate. |
| Commercial pricing | JustTCG history, graded listings and provider-backed sealed prices currently require a customer's Settings key. Paid JustTCG was selected 2026-11-10; active plan, rights/exports review, quota/cost budget and no-key production integration remain open launch prerequisites (S09.07/G07). |
| Runtime and providers | Physical camera, omitted-artwork intake/enrichment, delayed-price Browse, sealed-add Undo, device performance and native export/purchase checks remain evidence work. |
| Privacy and support | URLs empty by deliberate deferral to final launch preparation; must be real, configured and usable before submission. |
| Documentation | The old framework's free/no-StoreKit body is archived; this contract is the single authority. |

## 8. Final release decision

Freeze the supported product, requirements, workloads, tolerances, corpus and
claims before final execution. All gates must pass — no readiness percentage and
no averaging a broken paid tool against unrelated passes.

| Gate | Pass condition | Status |
| --- | --- | --- |
| G01 Scope matches reality | Manifest, code, installed Release build and marketing agree; no undeclared production/local difference. | **Fail** — One Piece; manifest unfilled |
| G02 No known customer defects | All confirmed user-visible violations closed; any owner exception is visible and changes the claim. | **Fail** — S12.05, S15.05, S17.03 |
| G03 Integrity checks pass | Ownership, identity, durability, import replay, currency, chronology, arithmetic and output invariants pass with no unexplained failures. | Not verified |
| G04 Every critical journey passes | J01–J12 complete and reconcile on the actual candidate, including recovery and delivered output. | Not verified |
| G05 Recognition is useful and safe | Frozen corpora meet error, completion and friction criteria; no deterministic failure hidden in aggregates. | Not verified — corpus not assembled |
| G06 The experience is polished | Screen states, accessibility, layouts, responsiveness and sustained use pass; external users finish uncoached. | Not verified |
| G07 Paid and external services work | Configured product, restoration, licensed app-funded pricing API, catalog/feed activation and public links have environment-appropriate evidence. Pricing passes §2 and S09.07 without a customer provider account or API key. | Not verified — commercial pricing selection, entitlement and no-key integration acceptance open |
| G08 The candidate is traceable | Automated checks, exclusions and device receipts reconcile to the tested source and distributed build; skips never pass as passes. | Not verified |
| G09 The submission is complete | Archive/signing, privacy metadata, screenshots, descriptions, links, review notes and in-app purchase submission complete and truthful. | Not verified |

**Work order:** reconcile scope and evidence; fix ownership/identity/valuation
trust defects; finish broken workflows; close interaction and polish defects;
then final device, purchase, provider and distribution acceptance. Smallest safe
fixes; add a regression test only where it guards a real failure mechanism.

For a failing test, decide whether it reflects production behavior, a wrong
expectation, the environment or isolated research, and repair or justify it with
evidence. Never delete, skip or weaken an applicable requirement to manufacture a
clean result. During repairs rerun affected invariants and journeys plus a
bounded whole-app smoke pass; on the final candidate run the complete mandatory
selection and all critical journeys.

After the freeze, a new finding blocks release when it violates an existing
requirement, exposes material data/payment/privacy harm or invalidates the
declared scope. New features and stylistic preferences go to the next release.
Once G01–G09 pass, submit.

## 9. Repository validation — 2026-11-09

Every concrete reference in the contract was checked against the working tree.

| Check | Result |
| --- | --- |
| Requirement count | 86 requirements across S01–S17 (4+4+5×6+7+5+5+6+5×5), including the owner-directed commercial pricing amendment S09.07. |
| Adoption source files (76) | All exist; additional commercial-pricing references are checked below. |
| Named test suites (36) | All exist in `TradingCardScannerTests`. |
| Platforms | `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `TARGETED_DEVICE_FAMILY = 1,2`; phone portrait only; four iPad orientations in `Info.plist`. |
| Broad rerun 3,174 / 2 / 21 and six centering gates | Match `progress.md` and the centering ledger. |
| One Piece disabled | `Config/OnePieceCatalogProduction.xcconfig`: rollout `disabled`, writes `NO`. |
| Local purchase bypass | `LOCAL_COLLECTOR_TOOLS` is defined only in `ReleaseLocal`, alongside `LOCAL_ONLY_SIGNING`; `Release` does not define it. |
| Privacy/support URLs empty | Confirmed in `Config/PokemonCatalogProduction.xcconfig`. |
| Price-feed URL configured | Confirmed (`TCGCSV_PRICE_BASE_URL`). Three documents still describe it as empty and are stale on that point: [feature-completeness review](../audits/feature-completeness-review-2026-10-29.md), [catalog pricing cases](../audits/catalog-pricing-cases-2026-11-01.md) and a dated [documentation audit](../plans/documentation_audit.md) entry. |
| Current JustTCG access | `PriceVendorCredentials.swift`, `JustTCGTransport.swift` and `ScannerSettingsView.swift` confirm customer-key storage, missing-credential rejection and the history/graded/sealed requirement. This source check does not close S09.07 or G07. |
| Photo drafts not restored after process death | Matches [monetization plan](../plans/CARDSCANNER_LAUNCH_MONETIZATION.md). |
| ~1,500-card workload | Matches [release follow-ups](../plans/release_followups.md). |
| Old framework contradicts paid tools | Confirmed (body said "No StoreKit implementation exists"); archived. |
| S15.05 version/build discoverability | **Fail found during validation:** `CFBundleShortVersionString`/`CFBundleVersion` are read only for the sync-diagnostics export under Developer & Diagnostics; Privacy & Support shows neither. |

### Source references

| Ref | Repository location |
| --- | --- |
| S1 Product principles and scanner contract | [`README.md`](../../README.md) |
| S2 Runtime registration and capabilities | `TradingCardScanner/Games/Core/CardGameRuntime.swift` |
| S3 One Piece production configuration | `Config/OnePieceCatalogProduction.xcconfig` |
| S4 Production endpoints and public links | `Config/PokemonCatalogProduction.xcconfig`, `TradingCardScanner/Info.plist` |
| S5 Release follow-ups and Nov 9 regression | [`release_followups.md`](../plans/release_followups.md), [`progress.md`](../../progress.md) |
| S6 / S15 Centering evidence and acceptance | [`centering-guided-repair.md`](../audits/centering-guided-repair.md) |
| S7 Purchase and entitlement | `TradingCardScanner/Services/CollectorToolsStore.swift` |
| S8 Owned-price correctness | [`pricing_correctness_and_coverage.md`](../plans/pricing_correctness_and_coverage.md) |
| S9 Earlier release framework | [archived framework](../legacy/card-scanner-1.0-go-no-go-framework.md) |
| S10 Commercial offer and scope | [`CARDSCANNER_LAUNCH_MONETIZATION.md`](../plans/CARDSCANNER_LAUNCH_MONETIZATION.md) |
| S11 Local storage boundary | `TradingCardScanner/Services/CollectionStorageBootstrap.swift` |
| S12 Ownership transactions | `TradingCardScanner/Services/CollectionStore.swift`, `CollectionWriteSerializer.swift` |
| S13 CSV import/export | `TradingCardScanner/Services/CollectionCSV.swift` |
| S14 Portfolio replay and accounting | `TradingCardScanner/Services/PortfolioReplay.swift`, `PortfolioEngine.swift` |
| S16 Platform, build and compilation | `TradingCardScanner.xcodeproj/project.pbxproj` |
| S17 Orientation, permissions, runtime keys | `TradingCardScanner/Info.plist` |
| S18 Commercial pricing access and proposal | `TradingCardScanner/Services/PriceVendorCredentials.swift`, `JustTCGTransport.swift`, `TradingCardScanner/Views/ScannerSettingsView.swift`; [shared-pricing-cache plan](../plans/shared_pricing_cache_plan.md) |
| A1–A3 | Apple App Review Guidelines; StoreKit testing environments; configuring in-app purchases for review. |
