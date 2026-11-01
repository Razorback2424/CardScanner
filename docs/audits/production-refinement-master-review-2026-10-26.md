# Production refinement master review

**2026-10-31 second pass:** a later review's findings R1–R10 and slices S2–S7a are
recorded in the [second-pass section](#2026-10-31-production-review-second-pass)
on `refinement/production-review-2026-10-31`. Device measurements gating R5, R8
and R9 are pending.

**2026-10-31 closeout:** the [refinement follow-up](#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes)
is complete on `refinement/review-followup-2026-10-31` at `5344635`, verified
on `origin`. Steps 1–4 are closed for the scoped simulator verification,
accuracy fixes and documentation. Earlier S6-reverted/S7-pending notes are
historical; the follow-up records the remaining index, cross-device coverage
and owner-device limits. This closes the follow-up, not broader release acceptance.

**2026-10-29 follow-up:** the [high-confidence refinement fixes](#2026-10-29-high-confidence-refinement-fixes)
below record the later review's implementation, focused Simulator verification,
and retained release/measurement boundaries. Earlier checkpoint counts below
remain historical evidence for their respective patches.

**2026-10-28 follow-up:** the later comprehensive-review implementation is recorded
in the [current progress entry](../../progress.md#2026-10-28--refinement-review-implementation).
It includes catalog-backed slab finish discovery and first-baseline reconciliation,
superseding the corresponding open implementation labels in the earlier checkpoint
below. Scoped final simulator verification and its StoreKit failure/rerun are
recorded there; the owner kept privacy/support publication deferred. The following consolidation and
its test counts remain the earlier checkpoint, not evidence for the new patch.

**Status:** current consolidated findings; M01–M03 locally repaired on 2026-10-26. M04's reviewed UI ownership write paths, M05's opening hold and M06's owned-game filter choices are locally repaired through 2026-10-27; scoped verification and remaining runtime acceptance are recorded below. M07's action-availability first slice is implemented and locally regression-verified on 2026-10-27; catalog-backed alternative discovery and rendered acceptance remain open. Broader synchronous service boundaries are explicitly retained, not certified as nonblocking. M08 and later findings are unchanged backlog items.

**Reviewed:** 2026-10-26, commit `028b1356863687e1b4b4ce86f6a5f42794afb1c9`, initially clean working tree.

**Objective:** a faster, more accurate, more enjoyable production app with the minimum necessary intervention.

M01 now prevents new scanned acquisitions from merging incompatible finishes while preserving existing ownership keys and history. M02 prevents new automatic graded bindings and prices without physical finish evidence. M03 constrains CSV price interpretation so unsupported currency, malformed numbers and competing columns cannot seed USD valuation. M04's reviewed UI ownership transactions and exclusive-lock entry now run off-main, including sealed acquisition, Browse backfill and Portfolio repair. M05 begins the opening reveal at readiness without the former presentation hold. M06 makes every owned game filterable independently of browse capability. The remaining performance proposals require measurements before implementation.

This report reconciles the earlier chat review (A, findings F1–F10 and its measurement backlog) with the supplied nine-finding review (B, beginning “Ran check git status”). Each issue has one master entry below. The reconciliation tables retain the disposition of every original finding; they are provenance, not a second backlog. This document supersedes those two reviews as a working findings list. Existing game, pricing, centering, and release authorities retain their implementation and acceptance roles.

## Evidence and scope

The original review inventoried 226 Swift files under the app and 42 source files across MagicCatalogCore, PokemonCatalogCore, and OnePieceCatalogCore: 268 files and 125,841 lines including debug-only code. It also examined the centering C kernels and relevant configuration. Release conclusions exclude debug-only behavior.

Subsystem coverage included launch/storage/lifecycle; camera/OCR/recognition and duplicate handling; all five game integrations and catalog update/activation paths; raw/graded/sealed ownership; ledger/activity/undo/correction; CSV import/export; pricing/refresh/fallback/cache; portfolio valuation/history; collection/browse/detail/filter/chart UI; artwork and finish rendering; centering/listing-photo tools; purchases; accessibility; privacy/support; and deferred CloudKit paths. Investigation depth was risk weighted, not a line-by-line proof of every function or catalog record.

Reconciliation re-read the disputed paths and their callers, including notification filtering, bulk-write deferral, refresh-owned deltas, motion delivery gates, catalog authority revalidation, OCR eligibility/cadence, cache capacities, and safe-area ancestry. The initial reviews/reconciliation were source-only, with existing test source inspected where useful. The later M01–M06 implementations add the explicitly scoped native evidence below. No full-suite, archive, Instruments, live-provider, or physical-device acceptance is claimed. Historical test counts are not new evidence.

**Evidence labels:** “Source validated” establishes behavior or a missing invariant in code, not its frequency on devices. “Conditional” requires a focused reproduction before changing code. “Measure first” identifies actual work whose material cost is unestablished. “Not adopted” rejects an unsupported conclusion or remedy, while retaining any useful investigation.

## Prioritized findings

| ID | Priority | Finding | Evidence and next action |
| --- | --- | --- | --- |
| M01 | P1 | Certificate-less scanned slabs can merge different finishes | Locally repaired; new regressions pass, broader run has one confirmed pre-existing failure |
| M02 | P1 | Unknown-finish slabs can bind to the only published market finish | Locally repaired; six focused regressions and all 318 expanded tests pass |
| M03 | P2 | CSV prices lose currency/format semantics and column selection is unspecified | Locally repaired; four focused regressions pass; expanded 469 passed, zero failed, one opt-in benchmark skipped |
| M04 | P2 | UI ownership actions synchronously wait and write on the main thread | Reviewed UI ownership scope locally repaired; final expanded run: 615 passed, zero failed, one opt-in benchmark skipped; device/rendered acceptance remains |
| M05 | P2 opportunity | Ready app remains blocked by the opening hold | Locally repaired; hosted regression reproduces old delay and verifies immediate handoff; accessibility/device acceptance remains |
| M06 | P2 | Collection Game filter uses incomplete static capabilities | Locally repaired; choices follow full owned snapshot, including retained games; three focused and all 124 expanded tests pass |
| M07 | P2 | Graded “Fix finish” often cannot offer a correction | Action-availability first slice verified: 124 passed; broader catalog-backed alternatives and rendered acceptance remain open |
| M08 | P2, narrow trigger | First revision baseline checks row count rather than ownership contents | Source gap validated; reproduce the same-count launch sequence first |
| M09 | Verify first | Listing-photo output lifetime is tied to view disappearance | Cleanup validated; presentation/navigation consequences conditional |
| M10 | Release configuration | Privacy/support URLs are empty in checked-in Release settings | Source validated; known owner-deferred release item |

### M01 Certificate-less scanned slabs can merge different finishes

**Status:** repaired in the local working tree on 2026-10-26; no commit or release acceptance implied. The M01 repair did not implement other findings; M02's subsequent repair is recorded below.

**Where:** [scannedGradedCollectionKey](../../TradingCardScanner/Models/CollectedCard.swift#L439), [addScannedGraded](../../TradingCardScanner/Services/CollectionStore.swift#L3820), and the new [certlessScannedGradedCard lookup](../../TradingCardScanner/Services/CollectionStore.swift#L5092).

Before the fix, the scanned graded key included printing, grader, grade, optional certificate, Pokémon print run, and Magic treatments, but omitted physical finish. Certificate-less acquisition looked up that key and incremented quantity, changing the finish only when it was missing. Different finishes could therefore become one holding retaining the first finish. The focused regression demonstrated Normal + Reverse + Normal becoming one quantity-3 Normal holding instead of separate quantities 2 and 1.

**Impact and confidence:** incorrect inventory identity and potentially incorrect valuation; high confidence in the collision. The problem concerns the scanned certificate-less path, not every catalog-selected graded acquisition.

**Implemented remedy and benefit:** aggregate scanned certificate-less rows only when their stored finish (including nil), grade, company, print run, and treatment identity match. Match current stored facts because explicit finish corrections retain ownership keys. When an incompatible holding occupies the old key, allocate a separate opaque `:holding:<UUID>` suffix before any treatment suffix. Repeated compatible scans find that row through the same physical-identity lookup. Existing keys, certificates, events, history, and already-merged quantities are not bulk-rewritten or guessed apart. Certificate-based refinement and vendor-selected graded acquisition retain their existing paths.

**Risk and complexity:** persisted ownership/price lineage warranted broader regression coverage. The implementation changes one production file, adds one bounded lookup, and removes implicit unknown-to-known finish refinement during a new certificate-less acquisition. It requires no schema migration or general identity redesign. Previously merged holdings are not repaired automatically; their original composition is unavailable.

**Native verification:** Debug build/test on the booted iPhone 17, iOS 27.0 Simulator. Build data and the expanded result/log evidence are on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`.

| Run | Result |
| --- | --- |
| Focused regression before production changes | Failed: same key, one row, Normal quantity 3, missing Reverse holding and incorrect per-key ledger quantities |
| Original regression after the fix | 1 passed, zero failed |
| Final standalone M01 regression selection | All six passed, zero failed/skipped; finalized result summary and individual cases inspected |
| Expanded ownership/scanner/persistence selection | 124 executed: 123 passed, one failed, zero skipped; all six new M01 regressions passed |
| Failing sealed-product assertion against cached pre-fix test products | Same failure reproduced before M01: `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`, line 247, expected nil `catalogProviderID`, observed `direct-product` |

The [six new regressions](../../TradingCardScannerTests/CollectionItemKindTests.swift#L227) cover finish separation and same-finish aggregation; legacy and unknown finishes; repeated corrections without rekeying; Magic nonfoil/foil; binding and independent quotes; certificate refinement; undo/restore; an on-disk store reopen; and native CSV roundtrip followed by another scan. The expanded selection includes all 36 CollectionItemKind, 38 CollectionActivityHistory, nine CSVImportResume, 11 CollectionKey, and 15 ScannedGradedResolver tests, plus ten scanner, three identity-permit, and two legacy-CSV cases. The unrelated sealed assertion is retained as a verification limitation, not fixed or hidden by changing the selection.

Artifacts: `M01-final-six.xcresult` / `.log`, `M01-expanded.xcresult` / `.log`, and `M01-baseline-sealed.xcresult` / `.log`. Expanded tests completed before Xcode stalled collecting automatic simulator diagnostics; stopping only that run's diagnostic child allowed its result bundle to finalize. The finalized bundle confirms the 123/1 result. The baseline comparison disabled automatic diagnostics. The final standalone run encountered a simulator Instruments-server preparation delay but subsequently executed all six tests; its finalized result is Passed. No physical-device or full-suite acceptance is claimed.

### M02 Unknown finishes can receive authoritative graded prices

**Status:** repaired locally on 2026-10-26, `028b135` plus working-tree changes; no release acceptance implied.

**Where:** [initial resolver guard](../../TradingCardScanner/Services/ScannedGradedResolver.swift#L79), [matchingVariant](../../TradingCardScanner/Services/ScannedGradedResolver.swift#L154), [refresh selection](../../TradingCardScanner/Services/PriceRefreshController.swift#L1835), and [binding](../../TradingCardScanner/Services/PriceRefreshController.swift#L19).

**Demonstrated defect:** the initial resolver refused ambiguous catalog finishes but admitted zero evidence and did not constrain matching to a catalog singleton. Collection refresh bypassed the catalog ambiguity guard. The shared matcher accepted an unknown finish when the vendor published one printing; durable binding also admitted unknown finishes and missing vendor printing. Focused native regressions reproduced a saved unknown slab acquiring a vendor binding and $123 quote, an unknown Price Check publishing a graded quote, and a catalog-Holo singleton accepting a Normal listing.

**Impact and confidence:** plausible but incorrect authoritative collection values; high confidence from native reproduction and passing fixed-path tests.

**Implemented remedy and benefit:** the resolver requires a confirmed finish or exactly one catalog physical finish and forwards it to lookup and matching. The matcher requires physical evidence for a new binding; refresh skips unknown unbound rows before vendor work. The durable binding guard rejects unknown finishes and missing/conflicting vendor printing before any identity promotion or quote write. Existing exact vendor handles remain refreshable without inferring a replacement listing, preserving the explicit listing-picker workflow. No schema, ownership-key, price-lineage, or UI redesign was added.

**Risk and complexity:** low to medium regression risk: apparent coverage intentionally falls for unresolved finishes. The production change is bounded to two files, preserves overall complexity, removes unique-market-lane inference, and adds an exact-handle constraint for existing bindings. It does not bulk clear historical bindings or prices: persisted data cannot distinguish an explicit listing selection from an old inferred binding. Previously misbound holdings need identity review/correction; no historical cleanup is claimed.

**Verification:** six focused simulator tests pass: missing catalog evidence, singleton finish constraints, real Price Check publication/reference caching, repeated collection refresh followed by confirmation, durable binding rejection, and exact selected-listing refresh. Tests exercise fresh SwiftData contexts and missing/conflicting vendor printing; existing print-run/label fixtures now supply the known identity required by their success scenarios. Expanded evidence follows below. No live-provider, physical-device, full-suite, or release readiness is claimed.

| Native run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Focused before production repair | Six executed: five defect tests failed, exact-selected-listing control passed. An earlier run exposed an incomplete JSON fixture, corrected before this run; the Price Check fixture subsequently gained the full reference-cache schema for its positive cache assertion. |
| Focused after repair | Six passed, zero failed/skipped |
| Initial expanded run | 318 executed; eight scanner tests failed on 13 assertions because fixtures omitted printing or expected a price before finish confirmation. The other 310 tests passed. |
| Final expanded run after fixture/expectation reconciliation | 318 passed, zero failed/skipped; finalized result summary inspected |

The final selection comprises 37 CollectionItemKind, 23 PriceRefreshLifecycle, 78 Pricing, 36 QuoteCache, 18 ScannedGradedResolver, and 126 ScannerViewModel tests. It includes all six M01 regressions. Scanner correction tests now prove that unknown finishes receive no initial quote, confirmation can enable pricing, an unavailable recheck leaves the row unpriced, and changing a known Holo finish to Normal replaces the incompatible quote. Successful delayed binding fixtures supply explicit vendor printing rather than bypassing the new guard. The M01-era unrelated sealed metadata failure remains recorded above; it was not part of this M02 selection or repaired here.

Build data and native evidence remain on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M02-red-six.xcresult` / `.log`, `M02-green-focused.xcresult` / `.log`, `M02-expanded.xcresult` / `.log`, and `M02-final-expanded.xcresult` / `.log`. The M02 repair did not implement later findings; M03's subsequent repair is recorded below.

### M03 CSV price interpretation can corrupt imported valuation

**Status:** repaired locally on 2026-10-26, `028b135` plus working-tree changes; no release acceptance implied.

**Where:** [header interpretation](../../TradingCardScanner/Services/CollectionCSV.swift#L596), [portfolioMarketPrice and currencyAmount](../../TradingCardScanner/Services/CollectionCSV.swift#L1720), [import application](../../TradingCardScanner/Services/CollectionCSV.swift#L1041), and [storeImported](../../TradingCardScanner/Services/PriceStore.swift#L1079).

**Demonstrated defect:** the importer selected an arbitrary `market_price`-prefixed dictionary field, stripped symbols/text and commas, and stored the resulting number as USD. Native regression tests reproduced `€12.50` becoming USD 12.50 and `12,50` becoming USD 1,250, including persisted price observations and acquisition-ledger valuation evidence. Competing/duplicate columns supplied a value instead of being treated as ambiguous. Malformed `1e3` became 13; explicit foreign currency metadata was ignored.

**Impact and confidence:** incorrect current prices, observations and portfolio attribution; high confidence from native reproduction and passing focused regressions. This is an input-boundary defect, not a claim that every provider export contains foreign currency.

**Implemented remedy and supported contract:** one production file changed. Accept a single `Market Price` column or `Market Price (As of YYYY-MM-DD)` with a valid date, using the existing normalized-header convention. Require a nonnegative US-style number: optional `$`, an integer with optional correctly grouped thousands commas, and an optional dot-decimal fraction. Preserve zero and sub-cent USD values. If `Currency` or `Currency Code` is supplied, it must be blank or USD. Reject unsupported price headers/cells and every competing Market Price column, including duplicate normalized headers, without dropping valid inventory. There is no dictionary-order preference, locale guessing or currency conversion. Only validated formatting is removed before numeric conversion.

**Benefit, risk and complexity:** prevent newly imported misleading USD values while preserving quantity and valid imported prices. Regression risk is low to medium at the compatibility boundary: previously tolerated unsupported formats now import inventory without a price. Complexity increases modestly for explicit header/amount validation; no persistence, schema, observation, ledger, UI or import-resume redesign was added. Existing `PriceStore` and ledger admission paths remain unchanged.

**Historical-data limit:** previously imported prices, observations and ledger evidence are not retroactively rewritten or cleared; their original currency/text is not persisted. Re-importing the same inventory is idempotent and does not repair those values. Historical cleanup requires a separate evidence-backed correction plan.

**Verification:** four focused tests pass in the iPhone 17 / iOS 27.0 Simulator: valid USD and dated-header controls; foreign/malformed values with inventory retained; competing/duplicate/unsupported columns in both orders; and durable import checks of collection prices, observation counts and ledger values. The durable cases include foreign cells/metadata, decimal commas and competing/duplicate columns. The `$1,234.56` control retains quantity two, one observation and the correct per-copy ledger value. Expanded evidence follows below. No live-provider, physical-device, full-suite or release readiness is claimed.

| Native run | Result |
| --- | --- |
| Focused before production repair | Four selected: three defect tests failed; the supported-USD/date control passed. No unexpected failures. |
| Focused after repair | Four passed, zero failed/skipped |
| Expanded import/valuation and M01/M02 selection | 470 selected: 469 passed, zero failed, one skipped; finalized result summary inspected |

The expanded selection includes all 20 ImportedItemKind, nine CSVImportResume, 85 PortfolioReconciliation, 38 CollectionActivityHistory, 37 CollectionItemKind, 18 ScannedGradedResolver, 78 Pricing, 36 QuoteCache, 126 ScannerViewModel and 23 PriceRefreshLifecycle cases. `PortfolioReconciliationTests.testAgedStoreBaseline` is the existing opt-in `PERF_BASELINE=1` benchmark and was skipped; no performance improvement is claimed. All M01/M02 regression selections pass. The unrelated M01-era sealed metadata failure remains recorded above and was not part of this selection or repaired here.

The [four new regressions](../../TradingCardScannerTests/ImportedItemKindTests.swift#L11) use synthetic CSV fixtures and fresh SwiftData reads. Build data and evidence remain on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M03-red.xcresult` / `.log`, `M03-green-focused.xcresult` / `.log`, and `M03-expanded.xcresult` / `.log`. The M03 repair did not implement later findings; M04's subsequent bounded repair is recorded below.

### M04 UI ownership actions can block the main thread

**Status:** reviewed UI ownership scope locally repaired, `028b135` plus working-tree changes, 2026-10-26–27. Detail, history, undo-banner, raw/graded/sealed acquisition, Browse backfill, Portfolio repair and CSV/delete exclusive entry are implemented and verified below. No additional named M04 UI action implementation slice remains. See the [final caller sweep](#m04-completion-and-caller-sweep--2026-10-27) for retained service boundaries and runtime acceptance limits.

**Where:** [CollectionWriteSerializer.perform](../../TradingCardScanner/Services/CollectionWriteSerializer.swift#L50), the new [CollectionDetailWriter](../../TradingCardScanner/Services/CollectionStore.swift#L1579), [quantity action](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1410), [removal action](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1455), and the existing [background executor](../../TradingCardScanner/Services/BackgroundModelActor.swift#L12).

**Demonstrated mechanism:** the old detail write sequence used `.mainThread`, which synchronously waits up to 1.5 seconds, then creates a context, fetches/mutates and saves on that same thread. A native characterization test held the ownership lock off-main and queued a main-thread heartbeat to release it. The synchronous main-actor write prevented that heartbeat from running; the holder had to reach its forced 500 ms timeout. The write reported `mainThread=true`, `heartbeatDuringLock=false`, and about **515 ms** elapsed before the repair. The same legacy-path characterization remains reproducible after this slice because the serializer itself and other synchronous callers remain unchanged.

**Impact and confidence:** high confidence in the blocking mechanism and this slice's executor change; ordinary contention frequency, Release-device latency and population impact remain unmeasured. Attachment B5 is the whole-position removal instance of this finding. No deadlock was established.

**Implemented remedy and benefit:** quantity/removal actions await a model actor created with the existing dedicated background serial executor. Fresh-context reads, ownership locking, validation and save stay together off-main. Immutable keys/treatments/expected quantities and a Sendable removal receipt cross the boundary; no fetched model crosses executors. Both actions use the existing identity-exclusivity retry in the same task, preserving task-bound authorization. Quantity retains its compare-and-set validation; queued removal now also validates the confirmed quantity so later-added copies are not silently removed. Cancellation/storage-generation checks run after lock acquisition, and retired work does not publish success. A shared pending flag prevents overlapping detail actions, disables conflicting controls, and shows a labeled system progress indicator. The existing success/error contract remains: removal callback/dismissal follows commit, and failures use the existing alert. Back navigation and printing-detail navigation remain available.

**Risk and complexity:** medium risk from async ordering, stale input and lifecycle/identity gates; these receive focused tests. Complexity increases modestly for one small actor and pending/storage fences, partly offset by removing duplicated synchronous/asynchronous quantity retry branches. The actor reuses the established executor/serializer. The global lock, timeout policy, lock ordering and other UI write paths are not redesigned. No optimistic removal or speculative queue/coalescing layer was added.

**Focused native verification:** all five selected tests pass. The fixed quantity/removal paths let the queued main-thread heartbeat release the contended lock before timeout; an executor probe confirms the transaction runs off-main. Fresh-context assertions cover one mutation after acquisition, ledger totals, removal receipt/undo, stale quantity/removal refusal, repeated removal refusal, canceled/retired-storage refusal, and task-bound identity authorization through the background actor hop and existing retry gate. The original characterization documents the legacy blocking path rather than claiming the global serializer is fixed. This is forced-contention Debug simulator evidence, not a physical-device speedup or a rendered navigation/VoiceOver acceptance test.

| Native run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Before repair: old detail serializer/store sequence | One characterization passed, demonstrating a blocked heartbeat and about 515 ms forced main-thread stall |
| Focused characterization and fixed-path regressions | Five passed, zero failed/skipped |
| Expanded ownership/UI/executor and M01–M03 selection | 490 selected: 489 passed, zero failed, one existing opt-in benchmark skipped; finalized summary inspected |

The expanded run includes all M03 selections (with CollectionActivityHistory now 43 cases), both LaunchModelActor tests with the new writer, seven DetailDeletionRender cases, five RefreshStructuralWrite cases, and the OwnershipConcurrencyStress test's 200 racing write pairs. The skipped case is the existing `PortfolioReconciliationTests.testAgedStoreBaseline`, which requires `PERF_BASELINE=1`; no new performance threshold was skipped. Existing hosted detail/deletion rendering passes, but the newly pending spinner state was not independently captured or manually navigated. The unrelated M01-era sealed metadata failure remains recorded above and was not selected or repaired here.

The [detail characterization/tests](../../TradingCardScannerTests/CollectionActivityHistoryTests.swift#L1252) and [executor coverage](../../TradingCardScannerTests/LaunchModelActorTests.swift#L47) retain the contention and ownership invariants. Build data/evidence remain on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-blocking-baseline.xcresult` / `.log`, `M04-focused.xcresult` / `.log`, and `M04-expanded.xcresult` / `.log`.

**UI/HIG source gate:** verdict **PASS** for the bounded change: native progress feedback, labeled activity, existing navigation/error presentation, no added prompt, and disabled conflicting actions while a write is pending. Top issues: none identified in source. Minimal fix list: the pending state and control/indicator wiring in the detail screen. Rendered pending-state accessibility and device interaction checks remain open. The implementation follows [Apple's guidance to keep non-UI work off the main thread and show preparation feedback](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).

#### Activity/history follow-up — 2026-10-27

**Where:** [CollectionActivityWriter](../../TradingCardScanner/Services/CollectionStore.swift#L1694), [history backfill/reload](../../TradingCardScanner/Views/CollectionActivityLogView.swift#L218), [history actions](../../TradingCardScanner/Views/CollectionActivityLogView.swift#L555), [editor save](../../TradingCardScanner/Views/CollectionActivityLogView.swift#L727), and [fallback value snapshot](../../TradingCardScanner/Services/PriceFallbackQuoteResolver.swift#L53).

**Reproduction and confidence:** a pre-repair native characterization exercised all four old synchronous serializer/store sequences under a forced 500 ms lock hold. Backfill, removal, restoration and correction all reported `mainThread=true`, blocked the queued main-thread heartbeat, and took approximately **517–526 ms**. This establishes the mechanism with high confidence; ordinary frequency and Release-device latency remain unmeasured.

**Implemented remedy and benefit:** one history-specific model actor reuses the established dedicated background executor, fresh serialized contexts and store methods. The history view no longer calls the synchronous serializer. Backfill is awaited before publishing a complete read snapshot; revision/retry task IDs coalesce reloads and reject superseded completions. Backfill failures retain the prior complete snapshot with actions paused and retry available, replacing the old swallowed error. Removal captures the observed claim quantity and the store rechecks it alongside lineage in the transaction. Restore and correction retain their fresh-context preflight; correction returns only a Sendable fallback input/key/game receipt. The fallback snapshot initializer now runs on the model's owning executor rather than requiring the main actor; its lookup logic is unchanged. Existing fallback pricing is queued after durable correction. Pending controls/indicators prevent overlapping actions and preserve native back navigation. Cancellation/storage checks occur after lock acquisition and before mutation; retired work does not publish success. The same-task identity gate/retry remains intact.

**Expected benefit, risk and complexity:** input processing remains available during ownership-lock waits and persistence; transaction latency still depends on the serializer and store. Risk is medium around async reload/action ordering and stale claims. Complexity increases modestly for the small actor, pending states and reload-generation checks; four synchronous UI transaction bodies are replaced by value-only actor calls and a shared two-action pending/error wrapper. No generic write framework, lock-policy change, schema change or read-projection redesign was added.

**Verification:** the initial five-test focused selection passed, including the legacy characterization and background responsiveness/ledger, stale/repeated action, cancellation/storage, and identity-permit/load-failure-state cases. A further test covers storage retiring while a removal is queued behind the lock. The initial expanded selection exposed only an overly narrow new repeated-restore error assertion: the store correctly refused the duplicate as already resolved rather than with the other valid restore-conflict refusal. The test now accepts either existing refusal and explicitly checks the unchanged ledger; production behavior was not changed to fit the assertion. Final expanded evidence is recorded below.

| Native history run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Pre-repair characterization | One case passed, demonstrating blocked main-thread heartbeats in all four old write sequences |
| Initial focused selection | Five passed, zero failed/skipped |
| Initial expanded selection | 547 selected: 545 passed, one failed on the overly specific new restore-error assertion, one existing opt-in benchmark skipped |
| Final-build startup attempt | Runner channel disconnected before test-case execution; no code acceptance from that attempt |
| Final prepared-build retry after test reconciliation | 547 selected: **546 passed, zero failed, one existing opt-in benchmark skipped**; finalized result summary inspected |

The final run includes all 49 CollectionActivityHistory cases (all six new history cases), both background-executor tests with the new writer, 51 ProductFallback cases, and all earlier M01–M04 selections. It preserves the seven hosted detail/deletion cases, structural refresh races and ownership stress coverage. The only skip remains `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). The unrelated M01-era sealed metadata assertion remains recorded above and was not selected or repaired. No synchronous serializer calls remain in `CollectionActivityLogView.swift`.

Evidence is on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-history-baseline.xcresult` / `.log`, `M04-history-focused.xcresult` / `.log`, `M04-history-expanded.xcresult` / `.log`, `M04-history-final-expanded.xcresult` / `.log` (runner startup failure), and `M04-history-final-retry.xcresult` / `.log` (passed). A read-only sample of the retry's own xcodebuild process identified a CoreSimulator application-launch wait; launch recovered without resetting shared simulator services or changing code. The prepared-build retry then completed normally. No full-suite, physical-device, live-provider or release acceptance is claimed.

**UI/HIG source gate:** verdict **PASS** for native pending indicators, disabled conflicting actions, retained back navigation and existing failure/retry presentation. Top issues: none identified in source. Minimal fix list: the history/editor pending and reload wiring. Pending-state rendering, VoiceOver and manual navigation under contention have not been independently accepted. History fetches/projection and editor eligibility reads remain on the main actor; their cost remains the separate measure-first P06 concern.

#### Undo-banner follow-up — 2026-10-27

**Where:** [Collection undo](../../TradingCardScanner/Views/CollectionView.swift#L730), [Portfolio undo](../../TradingCardScanner/Views/PortfolioView.swift#L773), [shared banner](../../TradingCardScanner/Views/RemovalUndoBanner.swift#L14), and the snapshot overload on [CollectionActivityWriter](../../TradingCardScanner/Services/CollectionStore.swift#L1723).

**Reproduction and confidence:** both banners used the same synchronous serializer/`restore(snapshot)` sequence. A native characterization of that exact sequence held the lock off-main for a forced 500 ms while a main-thread heartbeat waited to release it. It reported `mainThread=true`, `heartbeatDuringLock=false` and **518 ms** elapsed. High confidence in the blocking mechanism; this does not establish ordinary contention frequency or device latency.

**Smallest remedy and expected benefit:** both callers await one snapshot-restore overload on the existing activity writer, reusing its dedicated executor, fresh serialized transaction and post-lock cancellation/storage checks. The store's snapshot lookup, authoritative durable removal, restore window, reacquisition/duplicate refusal and ledger inverse are unchanged. The existing identity retry remains in the same task. No new worker, transaction framework, schema or lock policy was introduced. The UI stays available during locking and persistence; total transaction time is not promised to decrease.

**Banner behavior, risk and complexity:** each view captures the snapshot/container/generation, marks the removal pending before suspension and shows a labeled system spinner. Undo/Dismiss pause until completion; navigation remains available. Success clears only the matching banner after commit. A newer removal message is preserved, and an old failure cannot surface against that newer message or a retired store. Failures otherwise retain the banner and existing alert for retry. Async ordering is the main regression risk (medium); complexity increases modestly for pending identity and lifecycle fences, while persistence/validation logic is reused unchanged. The existing duplicated view entry points were kept to avoid a broader presentation refactor.

**Verification:** five focused cases passed: the old blocking sequence, background heartbeat/ledger integrity and durable snapshot authority, duplicate/reacquired/expired refusal, queued cancellation/storage retirement, and the existing same-task authorization gate. The first focused build caught an error in the new fixture (attempting to change immutable snapshot quantity); the fixture now changes its mutable finish and verifies the durable stored finish wins. No production behavior was changed to accommodate the fixture. Four new cases bring CollectionActivityHistory to 53 tests.

| Native undo run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Pre-repair synchronous sequence | One characterization passed, demonstrating a blocked heartbeat and about 518 ms forced stall |
| Initial focused build | New fixture compile error; no tests executed |
| Corrected focused run | Five passed, zero failed/skipped; finalized summary inspected |
| Expanded regression selection | 551 selected: **550 passed, zero failed, one existing opt-in benchmark skipped**; finalized summary inspected, no runtime warnings |

The expanded run includes all previous history-expanded selections, the four new undo cases, both private-executor tests, seven hosted detail/deletion tests, refresh structural races and the ownership stress test. The sole skip remains `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). The earlier unrelated sealed-metadata assertion is still recorded under M01; it was not selected or repaired. This is scoped Debug simulator acceptance, not full-suite, physical-device, provider or release acceptance.

Evidence is on the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-undo-baseline.xcresult` / `.log`, `M04-undo-focused.xcresult` / `.log` (fixture compile error), `M04-undo-focused-retry.xcresult` / `.log` (five passed), and `M04-undo-expanded.xcresult` / `.log` (550 passed, one skipped). Source HIG gate **PASS** for native pending feedback, paused conflicting actions, accessible labels and retained navigation; rendered pending-state/VoiceOver acceptance and Release-device measurements remain unverified.

#### Detail artwork/metadata follow-up — 2026-10-27

**Where:** the existing [CollectionDetailWriter](../../TradingCardScanner/Services/CollectionStore.swift#L1579), [photo replacement](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1289), [catalog-artwork restoration](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1338), [graded finish correction](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L844), and [marketplace-link persistence](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1503).

**Reproduction and confidence:** a native characterization exercised the four synchronous transaction shapes under a forced 500 ms lock hold. Photo mapping, catalog-artwork restoration, finish correction and marketplace persistence each blocked the queued main-thread heartbeat, reported `mainThread=true`, and took **507–538 ms**. The finish transaction shape was characterized with a raw correction fixture; fixed-path tests use an actual scanned graded holding. Photo downsampling/PNG encoding and file creation also ran synchronously on the main actor before the old transaction. High confidence in the executor/blocking mechanism; no ordinary contention frequency, photo-preparation duration or Release-device improvement is claimed.

**Implemented remedy and expected benefit:** four methods extend the existing detail writer and reuse its dedicated executor. Image normalization/file creation, fresh serialized model reads, save and reference-aware cleanup all run off-main. Only photo data, immutable keys/identity/claims and a filename receipt cross the boundary. Failed pre-commit photo writes remove their newly minted file; after commit the worker owns its lifetime, so a canceled UI continuation cannot delete referenced artwork. Cleanup reads the current override in the transaction rather than a filename captured before waiting. Shared-file protection, retained-game local override/suppressed legacy fallback, synced metadata write eligibility, and store validation stay intact.

Finish correction retains the fresh claim/lineage checks and existing task-bound identity retry. It removes the main-actor optimistic preflight and duplicate gate branches; the in-write permit check remains authoritative. Marketplace persistence keeps the optional/best-effort presentation and checks the fresh row's game, provider, treatment identity and still-empty URL before writing. It has post-lock cancellation/storage fencing but adds no pending UI for an automatic lookup. User actions reuse the detail pending flag, disable conflicting controls, and show a labeled native toolbar spinner while preserving back navigation. Photo request/generation checks reject obsolete UI completions; the existing load/preparation/save failure messages remain.

**Concrete reliability discovery:** the first focused run reproduced the serializer's Debug assertion when the same graded finish correction was submitted twice. The exported crash stack identifies the repeated call in the new regression: read-through identity repair dirties the fresh context, then the already-current finish returns a nil mutation without saving. The detail worker now explicitly rolls back that no-op context. This prevents the assertion without committing incidental repair work or weakening the serializer invariant. The global store API and other correction callers were not redesigned. The same run also exposed an incorrect new test expectation: a graded correction preserves the existing quantity event and appends correction history; it does not create a raw-card quantity transfer. The test expectation was corrected, not the ledger behavior.

**Risk and complexity:** medium risk around photo/file lifetime, async action ordering, fresh eligibility and price-identity authorization. The smallest remedy reuses the existing actor and pending state, with one local transaction helper shared by its methods. Added worker methods replace repeated view transaction bodies; the finish preflight branch and UI file cleanup are removed. Overall complexity is roughly preserved while executor and file ownership become clearer. No schema, serializer/lock policy, image format/cache redesign, new queueing framework, provider networking change or M07 finish-option change was introduced.

**Verification:** all six focused cases pass after the no-op fix and test reconciliation. They cover responsive contended writes, shared files and retained-game suppression, invalid/missing-target artwork without leaked files, stale/changed marketplace input, real graded identity authorization and stale/repeated correction, plus queued cancellation/storage retirement for all four methods. The six new cases bring CollectionActivityHistory to 59 cases.

| Native detail metadata run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Pre-repair synchronous transaction shapes | One characterization passed, demonstrating blocked heartbeats in all four shapes |
| First focused run | Four passed, two failed: the new graded quantity-event expectation and the repeated-finish Debug assertion |
| Focused retry after reconciliation/fix | Six passed, zero failed/skipped; finalized summary inspected, no runtime warnings |
| Expanded regression selection | 557 selected: **556 passed, zero failed, one existing opt-in benchmark skipped**; finalized summary inspected, no runtime warnings |
| Additional existing artwork regressions | Three passed, zero failed/skipped in the separate prepared-build run; finalized summary inspected, no runtime warnings |

The expanded run includes all previous undo-expanded selections plus the six new cases, both private-executor tests, seven hosted detail/deletion cases, ownership stress and refresh structural races. Its sole skip remains `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). Three extra artwork selectors initially used the file name rather than their actual `PortfolioDebugFixtureSurfaceTests` class and therefore were not executed in that run; their separate result is recorded above. No full-suite, physical-device, PhotosUI, live-provider or release acceptance is claimed. The earlier unrelated sealed-metadata assertion remains recorded under M01 and was not selected or repaired.

Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-detail-metadata-baseline.xcresult` / `.log`, `M04-detail-metadata-focused.xcresult` / `.log` (including the exported `M04-detail-metadata-focused-grade-crash.ips`), `M04-detail-metadata-focused-retry.xcresult` / `.log`, `M04-detail-metadata-expanded.xcresult` / `.log`, and `M04-detail-metadata-artwork.xcresult` / `.log` (additional existing regressions). Source HIG gate: **PASS** for platform controls, clarity, unchanged type/layout, labeled pending feedback, preserved navigation and no added prompts; top issues: none in source; minimal fix list: the bounded pending/control wiring above. Rendered pending-state/VoiceOver, PhotosUI/device memory and Release-device latency remain unverified.

#### Catalog/raw acquisition follow-up — 2026-10-27

**Where:** [catalog add](../../TradingCardScanner/Views/CatalogCardDetailView.swift#L440), [add Undo](../../TradingCardScanner/Views/CatalogCardDetailView.swift#L583), [fallback quote checkpoints](../../TradingCardScanner/Views/CatalogCardDetailView.swift#L484), and the existing scanner writer's [catalog add](../../TradingCardScanner/Services/CollectionStore.swift#L561), [catalog Undo](../../TradingCardScanner/Services/CollectionStore.swift#L594) and [catalog price persistence](../../TradingCardScanner/Services/CollectionStore.swift#L602).

**Reproduction and confidence:** a native characterization held the ownership lock off-main for a forced 500 ms while a queued main-thread heartbeat waited to release it. The old raw-add, acquisition Undo and catalog-price checkpoint shapes all blocked the heartbeat, taking approximately **647 ms**, **529 ms** and **524 ms**, respectively. Price persistence was also a blocking serializer path: moving only the add would leave a synchronous checkpoint on the tap's completion path. High confidence in the mechanism; these are forced-contention Debug simulator timings, not ordinary device latency or p95 measurements.

**Smallest remedy and expected benefit:** three methods extend the existing `ScannerCollectionWriter` on its established private executor. The view passes immutable catalog details, resolved finish, print run and storage-generation continuation. A fresh serialized transaction stages the acquisition, resolves the resulting row's actual price identity (including imported aliases), validates and saves once before returning its mutation receipt. Catalog provenance, source, release order, finish/edition and ledger/activity lineage retain the existing store behavior. Add and Undo use the existing identity retry in the same task; no detached mutation or new worker is introduced. Post-lock cancellation/storage checks reject queued obsolete work before mutation.

The initial catalog-price calculation/checkpoint and both fallback callback quote checkpoints also run on that writer. Ownership and pricing stay separate: after acquisition commits, any later price-stage failure returns the durable receipt with a warning rather than throwing into an acquisition retry. Invalid quote staging rolls back its own fresh context; no-observation results remain saved/unpriced without creating a false observation. Delayed catalog quote provenance retains `retrievedAt`; freshness comparisons retain the checkpoint's actual write-time policy. The shared fallback resolver's existing main-actor identity-cache resolution/save behavior is unchanged; this slice does not claim all provider/cache work is off-main or fast. Measure that shared work before a broader resolver change.

**UI behavior:** the view sets pending state before launching async work, pauses raw-add/graded-entry/Undo controls, and shows labeled native progress. Back navigation remains available. Only durable acquisition results publish success and start the existing six-second Undo window. Undo cancels expiry while saving, retains the existing failure alert/banner for retry, and clears only its matching mutation. Retired-store completions do not publish. Per-instrument fallback task coalescing and optional price behavior remain; subsequent intentional adds can still acquire further copies.

**Risk and complexity:** medium risk around async receipt ordering, acquisition-versus-price failure, imported aliases and quote freshness. Reusing the existing actor and one price persistence method removes main-actor transaction bodies and duplicate callback persistence contexts. Pending/storage fences and the value receipt add modest coordination; overall complexity is approximately preserved. No catalog architecture, variant-choice policy, ownership schema, serializer/lock ordering, fallback networking policy or new queueing abstraction was added.

**Verification:** all eight final focused cases pass. They cover contended add/price/Undo responsiveness, final-save rollback, intentional copies and exact/repeated Undo, imported alias/price identity, edition and invalid quote behavior, post-commit price-stage failure without reacquisition, delayed-quote freshness/provenance, and queued cancellation/storage retirement for all three write methods. The eight new cases bring CollectionActivityHistory to 67 cases.

| Native catalog/raw run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Initial characterization build attempts | Two new fixture compile errors (required source-variant string); no tests executed |
| Corrected pre-repair characterization | One passed; blocked heartbeats in add, Undo and price checkpoint |
| Initial six-case focused run | Five passed, one failed on the new test's incorrect assumption that non-USD quotes are rejected |
| Delayed-quote test against the first worker version | One failed, demonstrating the lost checkpoint write-time policy before acceptance |
| Final focused run after fixture/policy reconciliation | Eight passed, zero failed/skipped; finalized summary inspected, no runtime warnings |
| Expanded regression selection | 604 selected: **603 passed, zero failed, one existing opt-in benchmark skipped**; finalized summary inspected, no runtime warnings |

The invalid-quote fixture now uses a negative USD amount; valid non-USD display behavior was preserved. The delayed-quote regression demonstrated an implementation risk introduced while moving the checkpoint: using historical retrieval time as the write clock let the older 10-unit quote replace a newer saved 20-unit quote. The writer now mirrors `PriceStore` checkpoint replay's actual-write-time comparison, retaining original quote provenance. This was repaired before acceptance and is not a claim of a separate defect in the original checkpoint implementation. The post-commit phase-failure case confirms one acquisition attempt, one saved copy/event/activity, no price observation and a usable Undo receipt.

The expanded run includes all 67 CollectionActivityHistory cases, 36 BrowseCollection cases, both executor tests, seven hosted detail/deletion cases, three existing artwork regressions, ownership stress and all earlier M01–M04 expanded selections. The only skip is still `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). The unrelated sealed metadata assertion recorded under M01 was not selected or repaired. No full-suite, physical-device, provider or release acceptance is claimed. `CatalogCardDetailView.swift` no longer calls the synchronous serializer or saves a price context directly.

Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-catalog-raw-baseline.xcresult` / `.log` and `M04-catalog-raw-baseline-retry.xcresult` / `.log` (fixture compile errors), `M04-catalog-raw-baseline-final.xcresult` / `.log`, `M04-catalog-raw-focused.xcresult` / `.log`, `M04-catalog-raw-freshness-red.xcresult` / `.log`, `M04-catalog-raw-focused-final.xcresult` / `.log`, and `M04-catalog-raw-expanded.xcresult` / `.log`. Source HIG gate: **PASS** for native controls/feedback, unchanged type/layout conventions, retained navigation and no new prompts; top issues: none in source; minimal fix list: the pending/control and mutation-matching wiring above. Rendered pending-state/VoiceOver, live provider outcomes, physical-device latency and release acceptance remain unverified.

#### Graded-picker acquisition follow-up — 2026-10-27

**Where:** [confirmation save](../../TradingCardScanner/Views/GradedVariantPickerView.swift#L279), [view-owned pending task](../../TradingCardScanner/Views/GradedVariantPickerView.swift#L260), and [ScannerCollectionWriter.addGradedSelection](../../TradingCardScanner/Services/CollectionStore.swift#L628).

**Reproduction and confidence:** a pre-repair native characterization held the ownership lock off-main for a forced 500 ms while a queued UI heartbeat waited to release it. The picker transaction reported `mainThread=true`, `heartbeatDuringLock=false` and **669 ms** elapsed; the heartbeat could not run until the holder timed out. High confidence in the blocking mechanism. This does not measure ordinary contention frequency, Release-device latency or a guaranteed total transaction speedup.

**Smallest remedy and expected benefit:** one method extends the existing scanner writer/private executor and delegates to the unchanged `CollectionStore.addGraded` inside a fresh serialized transaction. Selected listing, underlying card, optional certificate, release order and print run cross as values; only the mutation receipt returns. Lock wait, lookups, promotion, price/ledger/activity work and commit all stay off-main. Cancellation/storage checks run after lock acquisition and before mutation. The view retains its immediate repeat-tap guard and existing failure alert, disables certificate editing while saving, and adds labeled native progress. Back/Cancel remain available. The save is now owned by the confirmation view's `.task`; leaving cancels queued work. Once a transaction starts, it completes atomically. Canceled/retired completions do not call the success/dismiss callback.

The main-actor optimistic promotion preflight and its duplicate gate branches were removed. The existing in-write permit check and same-task identity retry remain authoritative. A real certified scanned-to-listed promotion is tested with enforcement enabled: the first attempt requests exclusivity, the second commits under the existing permit, preserving one physical copy and its original acquisition lineage. This uncommon case can perform an extra attempt compared with an optimistic preflight; no ordinary latency claim is made. Explicit listing selection remains distinct from M02's stricter automatic finish binding: a picker-selected exact listing can retain its price while physical finish remains unrecorded. No binding, certificate, aggregation, finish-option or provider lookup policy was changed.

**Risk and complexity:** medium risk around sheet/task lifetime, cancellation and promotion authorization. Reusing the existing writer and pending flag keeps production code size approximately unchanged and simplifies UI coordination by removing synchronous persistence/preflight branches. No new actor, schema, queue, fallback or generic write framework was added. The existing store continues to own atomic pricing/ownership and certificate-conflict rollback.

**Verification:** all five focused cases pass. They cover the legacy blocking sequence; responsive background acquisition with and without a price, raw/slab separation, selected listing/card handles, grade, certificate, release order and edition; repeated certified selection versus intentional certless copies; conflicting certificate/listing refusal without price/ledger mutation; real task-bound promotion and migrated lineage; and cancellation/storage retirement while queued. Five new cases bring CollectionItemKind to 42 tests.

| Native graded-picker run on iPhone 17 / iOS 27.0 Simulator | Result |
| --- | --- |
| Pre-repair synchronous acquisition | One characterization passed, demonstrating blocked heartbeat and about 669 ms forced stall |
| Focused characterization/regressions | Five passed, zero failed/skipped; finalized summary inspected, no runtime warnings |
| Expanded regression selection | 609 selected: **608 passed, zero failed, one existing opt-in benchmark skipped**; finalized summary inspected, no runtime warnings |

The expanded run includes all 42 CollectionItemKind and 67 history cases, 36 BrowseCollection cases, both private-executor tests, seven hosted detail/deletion cases, three artwork cases, ownership stress and all earlier M01–M04 expanded selections. The only skip remains `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). The unrelated sealed-metadata assertion recorded under M01 was not selected or repaired. `GradedVariantPickerView.swift` no longer invokes the synchronous serializer or the main-actor optimistic promotion preflight. No full-suite, physical-device, live-provider or release acceptance is claimed.

Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-graded-picker-baseline.xcresult` / `.log`, `M04-graded-picker-focused.xcresult` / `.log`, and `M04-graded-picker-expanded.xcresult` / `.log`.

Source HIG gate: **PASS** for native controls/feedback, retained navigation, unchanged type/layout conventions and no added prompt; top issues: none identified in source; minimal fix list: view-owned save task, certificate pause and labeled progress. Rendered pending-state/VoiceOver, back/Cancel interaction acceptance under contention, live vendor behavior and physical-device latency remain unverified. The native cancellation cases exercise the worker/task boundary; they do not certify rendered SwiftUI navigation.

#### M04 completion and caller sweep — 2026-10-27

**Reviewed UI-ownership scope:** the final remaining slices are implemented locally. [Sealed add/Undo](../../TradingCardScanner/Views/SealedBrowseViews.swift#L1005), [Browse release-order backfill](../../TradingCardScanner/Views/BrowseView.swift#L499), and [Portfolio quantity repair](../../TradingCardScanner/Views/PortfolioView.swift#L629) now await the existing scanner writer. The sweep additionally found CSV-import and collection-delete exclusive entry still waiting on the UI thread; both now await [background exclusive-lock acquisition](../../TradingCardScanner/Services/CollectionWriteSerializer.swift#L135). This closes the reviewed M04 UI-ownership action scope; it is not a claim that every synchronous persistence call in the app has been eliminated.

**Demonstration:** a native pre-repair characterization blocked the queued main-thread heartbeat in all five transaction/entry shapes under a forced 500 ms ownership-lock hold. Sealed add took about **632 ms**, sealed Undo **603 ms**, Browse backfill **519 ms**, quantity repair **515 ms**, and exclusive entry **510 ms**. High confidence in the mechanism. These synthetic Debug simulator waits do not establish normal contention frequency or a physical-device speedup.

**Implemented remedy and expected benefit:** sealed acquisition calls one small method on the established background writer; Undo reuses its existing catalog-mutation Undo method. Existing store acquisition, price identity promotion, certificate-independent sealed aggregation, durable price/ledger/activity writes and strict inverse checks are unchanged. Sealed add/Undo tasks are view-owned, conflicting actions pause with labeled native progress, success/expiry is mutation-matched, and canceled/retired results do not publish. The six-second Undo window and retryable failure presentation remain.

Browse's existing longest-prefix set lookup, release-order update and obsolete print-run cleanup moved as one fresh-context transaction. The existing price-identity gate remains held by the same task. The completion watermark is set only after a successful, still-current result; failed or canceled work remains retryable. Portfolio captures the defect list before suspension, pauses repeat submissions, and reuses the existing fresh projection/ledger repair preflight. It appends corrections without changing owned quantities, refuses stale/mixed defects, and recomputes only after durable success on the current store.

The exclusive-entry helper moves only lock acquisition to a dispatch worker. The caller retains the same identity-authorized task, migration/refresh gate order and UUID-based exclusive barrier through import/deletion, with the existing release policy. Cancellation or storage retirement detected after the wait releases the acquired token before throwing, preventing a leaked exclusive session. No SwiftData model or actual write is detached from its owning executor or task authorization.

**Risk and complexity:** medium risk from async task lifetime, migration lineage, stale repair inputs and exclusive-session cleanup. The changes reuse existing actors, serializer, gates and store methods. They remove UI transaction bodies and redundant sealed preflight branches, adding pending/lifecycle wiring and one focused asynchronous lock-entry helper. Overall complexity is approximately preserved; no schema, generic write queue, new fallback, authority redesign or unrelated finding implementation was added.

**Native verification:** all seven focused cases pass: the five-shape legacy characterization; responsive fixed-path writes; backfill edition/price/ledger migration under authorization; mixed/repeated repair refusal; real sealed promotion through the two-attempt task-bound gate and exact/repeated Undo; exclusive barrier/task-permit preservation; and queued cancellation/storage retirement for all entry points with token reacquisition proving no leaked session. Seven new cases bring CollectionActivityHistory to 74 tests.

| Run | Result |
| --- | --- |
| Initial baseline build | New sealed fixture omitted required `imageURL: nil`; build failed before tests. Fixture corrected, production behavior unchanged |
| Corrected baseline | One characterization passed, reproducing all five blocking shapes above |
| Focused completion regressions | Seven passed, zero failed/skipped; finalized result inspected with no runtime warnings |
| Expanded completion regressions | 616 selected: **615 passed, zero failed, one skipped**; finalized result inspected with no runtime warnings |

Expanded verification on iPhone 17 / iOS 27.0 Simulator includes all 74 history, 42 item-kind and 36 BrowseCollection cases, both background-executor tests, seven hosted detail/deletion cases, three artwork cases, CSV resume, ownership stress, pricing/fallback/cache/scanner and refresh regressions from the earlier selections. The only skip remains `PortfolioReconciliationTests.testAgedStoreBaseline` (`PERF_BASELINE=1`). The unrelated sealed-metadata assertion recorded under M01 was not selected or repaired. Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M04-completion-baseline.xcresult` / `.log` (fixture build error), `M04-completion-baseline-final.xcresult` / `.log`, `M04-completion-focused.xcresult` / `.log`, and `M04-completion-expanded.xcresult` / `.log`. No full-suite or release acceptance is claimed.

**Caller sweep and retained boundaries:** production view code no longer directly calls `.mainThread` ownership serialization or acquires an exclusive session synchronously. The two remaining literal view matches are `PortfolioDebugFixtures` and `ContentView.seedSealedArtworkQA`, both behind debug/performance-harness compilation gates. `CollectionStorageBootstrap` artwork cleanup uses its bounded timeout inside `Task.detached`, so those literal matches are already off-main. Other synchronous service transactions remain in automatic catalog activation/normalization, Magic migration, portfolio epoch setup/retry, and shared pricing/cache APIs. Those broader authority, maintenance and launch paths are outside this reviewed UI-ownership repair and retain their existing P01/P04/M08 measurement/authority work; this report does not certify them as nonblocking or fast. Preserve their publication/freshness/lifecycle contracts before changing them. No broad serializer rewrite or catalog authority redesign was attempted to claim a blanket main-thread-persistence-free app.

**Remaining acceptance, not additional M04 implementation slices:** measure ordinary `collectionWriteLockWait` and action latency on a Release device build, and independently accept rendered pending-state/back/Cancel/VoiceOver behavior. Source HIG gate: **PASS** for native controls/feedback, retained navigation, paused conflicting actions and no additional prompts; top issues: none identified in source; minimal fix list: the sealed/repair pending wiring above. Physical-device, provider, CloudKit, full-suite and release gates remain open.

### M05 Opening handoff adds waiting after readiness

**Status:** locally repaired on 2026-10-27, `028b135` plus working-tree changes. No later finding implemented by this change.

**Where:** [OpeningMotion](../../TradingCardScanner/Views/AppOpeningView.swift#L17), [hit-testing gate](../../TradingCardScanner/Views/AppOpeningView.swift#L151), [ready task](../../TradingCardScanner/Views/AppOpeningView.swift#L172), and [hosted regression tests](../../TradingCardScannerTests/AppOpeningTests.swift#L10).

**Demonstrated behavior before repair:** after readiness, normal motion paths waited 420 ms or 720 ms before beginning the reveal; Reduce Motion waited 120 ms. Content hit testing and accessibility remained gated during that hold. The native hosted regression failed on both normal-motion paths: readiness-to-handoff was about **444 ms fast** and **757 ms slow**. Eight other opening cases passed. This was programmed presentation waiting, not a computation bottleneck; the slower path imposed more waiting after the longer startup.

**Smallest remedy implemented:** removed the pre-reveal sleep and its two unused hold constants. The ready task checks cancellation and immediately begins handoff. Existing fade/scale behavior, fast-path visual selection, Reduce Motion reveal, post-reveal settling, loading/restoration gates and recovery/session-reset behavior remain. The fast-path classifier still controls scale animation, so removing it would change the visual treatment unnecessarily.

**Confidence and expected benefit:** high confidence in removing the explicit 420/720/120 ms hold for all motion branches. In the fixed hosted normal-motion cases, handoff began in about **32 ms fast** and **under 1 ms slow**. Those are controlled Debug simulator readiness-to-handoff measurements, not total cold/warm startup timings, touch-delivery measurements, or a physical-device speedup claim. Hit testing and accessibility gating already follow handoff; the reveal may continue while content is available.

**Risk and complexity:** low risk to visual continuity and spoken focus timing. Production complexity decreases: no new API, state, abstraction or fallback; four timing lines removed. Preserve the settling delay because it only removes the already noninteractive overlay after its animation, and does not delay content availability.

**Verification — 2026-10-27:** all nine focused opening tests pass, including actual `UIHostingController` mounting of `AppOpeningContainer`, fast/slow readiness under a 100 ms regression budget, reveal completion, phase-reset cancellation of the old settling task, and blocked-startup recovery exposure. Existing caption/count, unknown-count readiness, session replacement and storage phase tests pass. Expanded verification selected **69 cases: 68 passed, zero failed, one skipped**, covering all opening, storage-bootstrap, storage-policy and launch-executor tests in this configuration. The only skip is `CollectionStorageBootstrapTests.testStorageManifestAndIdentityMetadataAreReadableAfterFirstUnlock`, which explicitly requires a physical device for data-protection attributes. Expanded hosted timings were about 1.5 ms fast and 0.7 ms slow. The first baseline fixture build attempted to override SwiftUI's read-only Reduce Motion environment value and failed before tests; the fixture was corrected to use the native simulator setting before the accepted red/green evidence. Finalized focused and expanded summaries report zero runtime warnings.

Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M05-red.xcresult` / `.log` (fixture compile error), `M05-red-retry.xcresult` / `.log` (eight passed, one expected regression failure with two timing assertions), `M05-focused.xcresult` / `.log` (nine passed, zero failed/skipped), and `M05-expanded.xcresult` / `.log` (68 passed, zero failed, one physical-device test skipped).

**HIG source gate:** verdict **PASS**; top issues: none identified in source; minimal fix list: only the hold removal above. Platform patterns and navigation are unchanged; clarity improves by revealing ready content; typography/layout are unchanged; accessibility retains its Reduce Motion scale suppression and content/overlay visibility gates; interaction adds no taps/prompts; no new App Review design risk identified. This is a source gate, not rendered accessibility acceptance.

**Remaining acceptance:** compare real cold/warm readiness-to-first-interaction on a Release device build, inspect the visual crossfade, and check VoiceOver focus/announcements and native Reduce Motion behavior. Reduce Motion's 120 ms removal is source-verified, not a distinct native-settings runtime measurement. No screenshot, frame-budget, physical-device, provider, CloudKit, full-suite or release acceptance is claimed.

### M06 Collection Game filter omits owned games

**Status:** locally repaired on 2026-10-27, `028b135` plus working-tree changes. No later finding implemented by this change.

**Where:** [CollectionFilterSheet.gameOptions](../../TradingCardScanner/Views/CollectionFilters.swift#L28), [full-snapshot input](../../TradingCardScanner/Views/CollectionView.swift#L395), the existing [selection binding](../../TradingCardScanner/Views/CollectionFilters.swift#L191), and [focused regressions](../../TradingCardScannerTests/CollectionQueryTests.swift#L7).

**Demonstrated behavior before repair:** the picker enumerated browse-capable games from the static registry, producing only Pokémon and Magic even when the collection contained Lorcana, Yu-Gi-Oh!, One Piece and a retained unknown game. Three native regression cases failed on the actual picker-options property. Their query assertions showed those identities could already be filtered correctly; the missing choices were the navigation failure. High confidence. No claim of One Piece production activation is made.

**Smallest remedy implemented and benefit:** the parent passes unique game identities from `snapshot.all` while the filter UI is presented. The picker uses these owned games, ordered by existing identity descriptors, with raw-ID ordering/labels for unknown retained identities. Search, item-kind filters and the currently selected game do not narrow the Game choices; game-scoped set/finish/treatment options keep their existing narrowing. The selected game remains a valid choice if its last holding disappears, until the user changes or clears it. Empty collections offer only All Games. This makes all held games reachable without enabling any browse, provider or collection-write capability.

**Risk and complexity:** low risk to option availability/order. Overall complexity is approximately preserved: one explicit owned-game input and a small ordering property replace the incorrect cross-feature capability dependency. No new model, fetch, task, cache, registry policy or persistence write. The set of game identities is built only while filters are presented. The existing native Picker, All Games entry and selection setter remain; only setter visibility is widened internally for the direct binding regression.

**Verification — 2026-10-27:** all three focused cases pass. They cover all five named games plus a retained unknown identity, stable labels/order, exact game query results and copy counts, empty/subset collections, selected-game retention after removal, and clearing. Directly invoking the actual picker binding confirms a repeated same-game choice leaves filters untouched; a game change clears only set/finish/treatment, preserving price, quantity, item kind, company and grade; other owned games remain selectable. Static browse/write capabilities remain disabled for retained games. Expanded verification on iPhone 17 / iOS 27.0 Simulator: **124 passed, zero failed/skipped**, including all 46 CollectionQuery, 42 CollectionItemKind and 36 BrowseCollection cases. Both finalized summaries have zero runtime warnings.

Evidence is on the external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`: `M06-red.xcresult` / `.log` (three expected picker regression failures), `M06-focused.xcresult` / `.log` (three passed, zero failed/skipped), and `M06-expanded.xcresult` / `.log` (124 passed, zero failed/skipped). The red build first threaded the owned-game input and exposed the existing options as a property, preserving the original browse-based choices before applying the fix. The unrelated sealed-metadata assertion recorded under M01 was not selected or repaired.

**HIG source gate:** verdict **PASS**; top issues: none identified in source; minimal fix list: owned-game choices above. Platform patterns: existing native Picker/sheet/inspector and navigation retained. Clarity: every owned identity is reachable with stable labels. Typography/legibility: existing system styles retained. Accessibility: native tags/selection and All Games entry retained, with no gesture or target changes. Interaction cost: no new tap or prompt. App Review design risk: no new confusing flow identified. Each category passes in source; no additional fix indicated.

**Remaining acceptance:** inspect the expanded picker and dependent detail counts on phone/tablet, including a retained game, search, dynamic updates and accessible text/VoiceOver. Native cases validate the production options/binding/query logic, not taps or rendered layout in a sheet/inspector. Physical-device, provider, CloudKit, full-suite and release gates remain open.

### M07 Graded finish correction often offers no correction

**Status:** first slice implemented in `e92db193be32024304de5cf24cdc8017b69ed3f6` and verified locally on 2026-10-27. This closes misleading action availability only; broader catalog-backed correction is deferred.

**Where:** [Fix finish menu](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L751) and [gradedVariantCorrectionOptions](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L839).

**Original behavior:** the menu appeared when an eligible acquisition existed, while its catalog evidence often contained only the currently persisted finish. Without supplemental variant knowledge, options were the current finish alone or empty. Selecting the current finish immediately returned. The interface promised a repair that could not be performed, including some “Not determined” cases.

**Impact and confidence:** misleading recovery UI; high confidence. This is distinct from M02's incorrect automatic pricing, but it also limits recovery from uncertain identity.

**First slice implemented:** filter the existing resolver options by persisted finish ID, omit the menu when no different option remains, and retain the Printed finish label/value, including Not determined. The action-specific explanatory copy appears only with a usable action. Eligible-acquisition and pending-write guards, native Menu, accessibility label and correction writer are retained. Reviewed Pokémon patterns, stamped releases and exact-printing alternatives remain available. No global finish list, catalog request, persistence change, new state or view-model refactor was added.

**Risk and complexity:** low-risk presentation/option filtering; one small helper through the existing detail facade replaces the no-op current-finish menu branch. Broader catalog-backed correction remains medium risk and is not part of this slice.

**Native verification:** Debug iPhone 17 / iOS 27.0 Simulator: **124 passed, zero failed, zero skipped** (43 CollectionItemKind, 76 CollectionActivityHistory, five selected OpusImplementationPlan cases). The three new M07 regressions exercise ordinary Pokémon/Magic known and unknown finishes; reviewed singleton/multiple choices; Poké Ball/Master Ball and stamped supplements; and preservation of the print-run axis. The other two selected cases preserve existing underlying-printing routing and stamped-release coverage. Existing suites cover correction history, stale claims, identity-gate authorization, binding invalidation, quantities and Undo. Tests validate the exact option helper used by the view; hiding the menu while retaining finish text is source-checked, not rendered interaction acceptance.

The first build failed before test execution because the new helper lacked the outer detail facade's forwarding method; that seam was completed. The next build ran tests but was interrupted and left no finalized result bundle. After resumption, the same source/test patch was present in `e92db19`; the final `test-without-building` selection reused those SSD build products and exited 0. Evidence is under `CodexBuildArtifacts/TradingCardScannerM01/M07-first-slice/`: `resumed-focused.xcresult` / `.log`, `resumed-summary.json`, and `final-tested.patch` (SHA-256 `0ad5ae96318eb9cf79bb6c63ab2445a6459973ea82ebfcc0cdc40cae7358a9c0`). Earlier build/interrupted artifacts remain separate.

**HIG source gate:** verdict **PASS**; top issues: none identified in source; minimal fix list: the action guard above. Platform patterns retain the native Menu; clarity removes a no-op repair while retaining finish information; typography uses unchanged system styles; accessibility retains the existing label and controls when applicable; interaction adds no prompt or tap; no new App Review design risk identified. All six categories pass in source. Phone/tablet, Dynamic Type and VoiceOver rendering remain unverified.

**Remaining M07 scope:** obtain additional valid alternatives through the existing catalog adapter when a real correction workflow is required, without inventing finishes; separately verify rendered action availability and correction interaction. No physical-device, live-provider, CloudKit, full-suite, archive or release gate is closed. M08 and later findings are unchanged.

### M08 First revision baseline can accept an older same-count projection

**Where:** [StoreRevisionMonitor.apply](../../TradingCardScanner/Services/StoreRevisionMonitor.swift#L459). [The existing first-observation test](../../TradingCardScannerTests/StoreRevisionMonitorTests.swift#L9) covers insertion after an empty projection.

The first observation stores its fingerprint, then reconciles the launch projection only if physical row count differs. A quantity edit or replacement preserving row count can occur after the projection but before that baseline, particularly when bulk work defers observation. The latest fingerprint can then become the baseline while displayed ownership is older. The source guard does not detect this case; practical reachability/frequency through normal launch UI remains unmeasured.

**Impact and confidence:** potentially stale quantities/totals until another relevant mutation or reload. High confidence in the missing comparison; medium confidence in real-user frequency. Treat as a focused deterministic reproduction, not a common launch failure claim.

**Smallest remedy and benefit:** once reproduced, reconcile when establishing the baseline or compare the snapshot's relevant ownership contents. Reuse existing fingerprint/snapshot machinery. Avoid adding a separate revision abstraction.

**Risk and complexity:** low correctness risk; unconditional reconciliation costs another launch read/recompute. Neutral or reduced complexity.

**Verification:** force projection quantity 1 → durable quantity 2 → first accepted observation, with unchanged physical count and fresh prices. Repeat with same-count replacement and bulk deferral. Require correct grid and portfolio without an unrelated save, then measure added launch work.

### M09 Listing-photo output lifetime needs presentation verification

**Where:** [onDisappear](../../TradingCardScanner/Views/EbayListingPhotosView.swift#L215), [single-output cleanup](../../TradingCardScanner/Views/EbayListingPhotosView.swift#L613), and [batch cleanup](../../TradingCardScanner/Views/EbayListingPhotosView.swift#L848).

Every disappearance invalidates generations, cancels batch work, deletes prepared output/archive directories, and clears the single inspector selection. The same view presents full-screen camera and inspector flows. File lifetime follows visibility rather than an explicit workflow/share lifetime.

**Impact and confidence:** high confidence in cleanup behavior; medium confidence in consequences for supported presentation/navigation paths. Returning after temporary navigation may require regeneration; inspector dismissal or sharing failures have not been reproduced. This remains conditional, not a confirmed broken-preview claim.

**Smallest remedy and benefit:** reproduce first. If temporary presentation or sharing loses required output, retain that run while its consumer needs it; clean on replacement, Start Over, or true workflow completion. Follow existing export-lifetime patterns rather than adding a general file manager abstraction.

**Risk and complexity:** medium risk of retained temporary files; small justified ownership bookkeeping increase if the failure is confirmed.

**Verification:** prepare → inspect → dismiss, camera cancel, switch tabs and return, delayed Files/AirDrop sharing, and batch processing interruption on iPhone/iPad. Check both usability and eventual file cleanup. Make no production change if these workflows already retain the required files correctly.

### M10 Release privacy and support links require configuration

**Where:** [Release settings](../../TradingCardScanner.xcodeproj/project.pbxproj#L1846), [configured URL validation](../../TradingCardScanner/Services/CardScannerExternalLinks.swift#L4), and [settings](../../TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift#L7).

Checked-in Release settings contain empty privacy/support URLs. Without packaging overrides, settings display “not available in this build.” This is a known owner-deferred publication item, not a newly discovered requirement to build a website during remediation; see [release follow-ups](../plans/release_followups.md) and [legal publication guidance](../legal/README.md).

**Impact and confidence:** unavailable in-app support/privacy access; high confidence in defaults, external packaging overrides unverified.

**Smallest remedy and benefit:** when publication is authorized, supply the established published HTTPS endpoints through Release inputs and verify the built app. No runtime redesign is needed.

**Risk and complexity:** low risk, neutral complexity.

**Verification:** inspect the actual release candidate's Info.plist and open both links from settings. Source defaults alone do not certify the distributed configuration.

## Measurement and focused verification backlog

These entries retain useful observations from both reviews without presenting them as established performance defects. No percentage speedup, CPU target, frame-rate restoration, thermal reduction, or hitch elimination is predicted from source alone.

### P01 Repeated persistence reads and context setup

**Sources:** B1 and B6. [Fingerprinting](../../TradingCardScanner/Services/StoreRevisionMonitor.swift#L942), [projection](../../TradingCardScanner/Services/CollectionProjectionActor.swift#L122), [price snapshot](../../TradingCardScanner/Services/PriceSnapshotStore.swift#L147), [portfolio snapshot](../../TradingCardScanner/Services/PortfolioReplaySnapshot.swift#L176), [background executor](../../TradingCardScanner/Services/BackgroundModelActor.swift#L12), and [scanner writer](../../TradingCardScanner/Services/CollectionStore.swift#L551).

Whole-table reads overlap in purpose across these workers, and each `makeBackground` creates a queue/context/executor. A completed ownership update can trigger several reads. However, notifications are filtered; bulk writes defer work; changed fingerprints choose which consumers rebuild; refresh deltas suppress redundant whole-price rebuilding; and rebuild requests are coalesced. The attachment's “every save” description, object-allocation counts, 60–75% saving, and eliminated hitches are not validated.

The scanner writer also creates a fresh transaction context inside the serializer. That synchronous body remains on the background executor; this is not demonstrated actor-isolation bypass. Fresh reads under the process-wide lock support current-state validation across sibling writers. Reusing a long-lived actor context is not an equivalent cleanup.

**Decision:** measure 10-card and long-session intake, scanner departure, ordinary ownership edits, and refresh checkpoints with 500/1,500/larger holdings and mature ledgers. Separate fingerprint, fetch/projection, portfolio replay, context setup, allocation, and UI-hitch costs using existing signposts. If material, first eliminate a proven duplicate read or share compatible immutable inputs with explicit freshness. Do not replace content detection with entity names/counts alone; same-count changes matter, as M08 illustrates.

**Benefit/risk/complexity:** benefit unknown until profiled; cross-consumer unification has medium/high correctness risk and can increase coupling. Keeping the existing boundaries has no remediation risk. Context reuse is not recommended without evidence and a freshness proof.

### P02 Collection finish rendering and lazy layout

**Sources:** B2 and B3. [Motion channels](../../TradingCardScanner/Views/CardFinishOverlay.swift#L202), [delivery gates](../../TradingCardScanner/Views/CardFinishOverlay.swift#L438), [overlay](../../TradingCardScanner/Views/CardFinishOverlay.swift#L652), [production policy](../../TradingCardScanner/Views/ContentView.swift#L438), and [nested layout](../../TradingCardScanner/Views/CollectionView.swift#L601).

Eligible live collection overlays observe a shared channel capped at 30 Hz. Delivery also requires sufficient tilt change and active registrations; detail has a separate 60 Hz channel. Reduce Motion and lifetime controls already exist. Gradient/blend rendering is real work, but body invalidations are not a count of GPU passes, GPU work is not all main-thread work, and the claimed CPU percentages or guaranteed 120 fps are unsupported. `.staticCollection` is a useful existing experiment, not an automatic production recommendation.

`LazyVGrid` is nested in `LazyVStack`. That structure alone does not demonstrate eager creation of the entire grid on the supported OS versions. Apple describes viewport-based lazy layout and prefetching, and supports composing lazy containers; it does not establish this exact composition as universally broken. [Apple lazy-layout explanation](https://developer.apple.com/videos/play/wwdc2026/321/)

**Decision:** use the existing finish-policy harness to compare live/staticCollection/nonfoil controls with the same collection, device, motion, scrolling, and thermal state. Separately measure tile body/allocation/appearance and image-work counts at first display and during scroll in a 500-card grid. Distinguish cheap view-value initialization from expensive realized/rendered work. If layout is implicated, test a minimal container change and check header/footer spacing, scroll position, rotation, and tablet width.

**Benefit/risk/complexity:** unknown performance benefit; a static policy is low code risk but changes a deliberate product effect. Layout changes are low/medium interaction risk. Use existing controls and preserve architecture; do not add a new renderer or collection abstraction.

### P03 OCR workload and tracking opportunities

**Sources:** A measurement backlog and B7. [Frame processing](../../TradingCardScanner/Services/CardScanner.swift#L3775), [cadence](../../TradingCardScanner/Services/CardScanner.swift#L280), [slab schedule](../../TradingCardScanner/Services/CardScanner.swift#L368), [Yu-Gi-Oh! supplemental gate](../../TradingCardScanner/Games/YuGiOh/YuGiOhRecognitionAdapter.swift#L18), and [Lorcana full-text gate](../../TradingCardScanner/Games/Lorcana/LorcanaDiscoveryCatalog.swift#L471).

Eligible frames can perform multiple Vision passes on the serial queue. If an OCR cycle exceeds the 240 ms interval, OCR-first selection can reduce tracking opportunities. Actual pass durations, tracking gaps, thermal effect, and recognition consequences require device evidence.

The pipeline is not an unconditional blank-frame cascade: Yu-Gi-Oh! supplemental OCR needs footer markers, Lorcana full text needs its specific footer evidence, historical paths have plausibility/window gates, slab labels require stable footer identity and have 0.5/2-second scheduling, and post-commit label reads are bounded. These gates contradict the attachment's broad “unbounded” account. Its 250–500 ms timings and 25–35% thermal/load benefit were not measured.

**Decision:** profile raw/slab and difficult-lighting sessions, empty backgrounds, historical cards, supplemental regions, duplicate transitions, and sustained stacks. Use footer/supplemental/label/tracking signposts and thermal state. Only then adjust a demonstrated redundant pass or scheduling decision. Preserve encounter/identity ownership if label work moves. Do not introduce a global empty-footer shortcut or independent label timer on the present evidence.

**Benefit/risk/complexity:** benefit unknown; recognition scheduling changes have medium/high accuracy and concurrency risk. Existing gates should remain; a measured removal of redundant work could reduce complexity.

### P04 Card-detail history task startup and derived chart work

**Sources:** B4 and A chart measurement. [Tasks](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L317), [loadMarketHistory](../../TradingCardScanner/Views/CollectionCardDetailView.swift#L1031), [mapping](../../TradingCardScanner/Services/CardMarketHistoryService.swift#L70), and [mapping-change test](../../TradingCardScannerTests/LorcanaPricingTests.swift#L258).

The activation observer increments the retry token after subscribing, which can cancel/restart an initial load. This only applies to catalog-mapped raw One Piece/Lorcana requests, not every detail presentation. The startup ordering can create extra work; actual duplicate network requests or visible flicker were not established. The service coalesces pending history requests.

Repeated mapping resolutions after awaits are current-authority checks: a mapping can change, withdraw, or select a different product/finish while cache/network work is suspended. Replacing these checks with the first local result is unsafe. The subscribe-before-reload handshake also closes a missed-event window. Existing test source explicitly covers remapping/withdrawal; those tests were not rerun here.

Chart models are also reconstructed from points when the parent updates, including selection changes. Material scrubbing cost is unmeasured.

**Decision:** trace load starts, cancellations, cache reads, actual transport starts, mapping revision, and scrubbing cost. If startup churn is material, coordinate subscription and initial loading through one narrowly scoped owner while retaining after-await authority checks. Verify activation during subscription, cached load, network completion, withdrawal, and dismissal. Memoize chart derivation only if it contributes meaningful cost.

**Benefit/risk/complexity:** unknown latency benefit; simply deleting safeguards has high identity risk. A measured task-ownership simplification could reduce complexity; preserve mapping validation.

### P05 CSV accelerator copy cost

**Source:** A measurement backlog. [Per-row snapshots](../../TradingCardScanner/Services/CollectionCSV.swift#L834).

The importer retains dictionary/set snapshots for row rollback, then mutates growing accelerators. Copy-on-write can copy their storage repeatedly. Measure CPU/allocations with representative 1,000/5,000-row imports, distinguishing database save cost. If dominant, delay accelerator publication until row commit or rebuild only after failure. Preserve durable row progress, idempotency, and interrupted-import behavior. Benefit unknown; medium rollback risk; bookkeeping may become simpler. This performance concern is distinct from M03's price correctness.

### P06 Activity history main-actor projection

**Source:** A measurement backlog. [reloadSnapshot](../../TradingCardScanner/Views/CollectionActivityLogView.swift#L248).

The activity fetch is paged, but cards and inventory events are fetched without that limit and lineage is derived on the main actor. Measure history entry, filter changes, and “Show more” with a mature ledger. If slow, move the existing value projection to the established background boundary; do not weaken lineage validation. Benefit unknown; medium action-consistency risk; approximately neutral complexity. The backfill/write component is tracked and now migrated off-main under M04; the read/projection cost remains unmeasured and is not a duplicate write finding.

### P07 Long scan-session repeated work

**Source:** A measurement backlog. [Session value](../../TradingCardScanner/Views/ScannerViewModel.swift#L2312), [duplicate-offer rebuilding](../../TradingCardScanner/Views/ScannerViewModel.swift#L2896), and [fallback scans](../../TradingCardScanner/Views/ScannerViewModel.swift#L5746).

Session history grows and several operations scan it. Measure 200/1,000-acquisition sessions with `offerHeldDuplicateRebuild` and `queueFallbackPriceScan`. Add one value index only if a measured operation warrants it. Do not cap away reviewable session history for theoretical speed. Benefit unknown; medium stale-index risk; a new index increases complexity.

### P08 Centering latency, image memory, and obsolete analysis

**Sources:** both reviews' measurement backlogs. [Decode/working dimensions](../../TradingCardScanner/Services/CardCenteringAnalyzer.swift#L628) and [analysis dispatch](../../TradingCardScanner/Views/CardCenteringView.swift#L375).

Large source photos, decoding before bounded preparation, and dispatched analysis that outlives its useful result are plausible costs. Generation guards prevent stale publication but do not necessarily stop obsolete computation. UIKit image construction alone does not establish when the full decode occurs or prove a memory spike.

Measure peak resident memory, decode time, detection/analysis stages, replacement/dismissal behavior, and concurrent work with large photos. Preserve working dimensions and detection thresholds unless existing held-out/metamorphic evidence shows equivalent accuracy. Benchmarking speed does not establish sub-millimeter accuracy. Prefer a measured downsampling/cancellation adjustment over algorithm changes. Benefit unknown; medium/high accuracy risk for dimension changes; cancellation adds complexity and needs demonstrated overlap.

### P09 Launch catalog preparation and snapshot cost

**Source:** A measurement backlog. [Runtime preparation](../../TradingCardScanner/Games/Core/CardGameRuntime.swift#L290), [launch tasks](../../TradingCardScanner/Views/ContentView.swift#L245), and [background executor](../../TradingCardScanner/Services/BackgroundModelActor.swift#L12).

Validate full-catalog startup, especially the large Yu-Gi-Oh! catalog, with realistic holdings on slower devices. Separate catalog validation, projection, portfolio readiness and the visual reveal; M05's former readiness hold has been removed. Background executors are already explicit. Do not add a persisted projection cache or remove catalog validation without showing the dominant cost and preserving activation trust. Benefit unknown; medium/high trust/cache-invalidation risk; another persistent cache increases complexity.

### P10 Provider pacing and background refresh coverage

**Sources:** A background-refresh measurement and B's pacing caution. [Transport/pacer](../../TradingCardScanner/Services/JustTCGTransport.swift), [background refresh](../../TradingCardScanner/Services/BackgroundPriceRefresh.swift), and [refresh batching](../../TradingCardScanner/Services/PriceRefreshController.swift#L4282).

Keep current pacing until authenticated latency, quota/429 behavior, and cancellation are measured. Background work is intentionally bounded; measure completion/coverage under actual system budgets before increasing limits. Existing Magic catalog request batching is already implemented. Do not treat older batching plans as current defects. Benefit of further tuning unknown; medium provider/quota risk; changing constants is simple but validating behavior is not.

### V01 Scan-summary safe-area placement

**Source:** B8. [Root overlay](../../TradingCardScanner/Views/ContentView.swift#L160) and [banner padding](../../TradingCardScanner/Views/ScanSessionOverlays.swift#L1360).

Eight points of top padding does not itself prove notch/Dynamic Island overlap. The banner is overlaid on the root TabView; the inspected production ancestry does not establish that its top safe area is ignored. SwiftUI normally respects safe areas. [Apple safe-area documentation](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:))

**Decision:** visual verification, not a confirmed defect. Finish a scan session on cutout/non-cutout phones and iPad, in rotation and large text; check banner/dismiss target bounds and tab navigation chrome. Change safe-area ownership only if clipping is reproduced. Benefit conditional; low/medium layout risk because an added inset can move existing content; complexity neutral if a repair is needed.

## Findings not adopted as fixes

### N01 Replace the bounded cache data structure

**Source:** B9. [BoundedCache](../../TradingCardScanner/Games/Core/BoundedCache.swift#L20), [checklist capacities](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift#L783), and [historical capacities](../../TradingCardScanner/Games/Pokemon/PokemonHistoricalCatalog.swift#L64).

Touches and evictions are linear in bounded key count. Production checklist bounds are 10; historical defaults are 64 sets and 256 cards. The array stores keys, not entire checklist contents. Linear work is real, but no material bottleneck is shown. A touch does not necessarily allocate a whole array copy when its storage is uniquely owned. `OrderedDictionary` also does not automatically guarantee constant-time arbitrary removal; its ordered storage can require moving subsequent members. [OrderedCollections removal implementation](https://github.com/apple/swift-collections/blob/main/Sources/OrderedCollections/OrderedDictionary/OrderedDictionary%2BPartial%20RangeReplaceableCollection.swift)

Keep the current simple implementation. Do not reduce the 256-card bound merely to enforce an arbitrary 64-entry rule; lost hits may cost network work. Revisit only if profiling identifies cache touch/eviction as material. Expected current user benefit is unestablished, while a new LRU structure/dependency adds complexity and eviction-regression risk. Existing [bounded-cache tests](../../TradingCardScannerTests/BoundedCacheTests.swift) cover semantics, not performance.

### Other rejected conclusions and remedies

- **Guaranteed performance numbers:** B's object-allocation totals, CPU percentages, 120 fps restoration, 60–75% read savings, 250–500 ms OCR timings, and 25–35% load/thermal savings lack retained measurements. They are not acceptance targets or expected benefits.
- **Fingerprint removal based only on entity names/counts:** not equivalent to detecting quantity, identity, price, or artwork changes. P01 may justify narrower work, not loss of content-change detection.
- **Actor-isolation violation from fresh transaction contexts:** not established. Retain serializer freshness/rollback boundaries unless measurements and concurrency tests justify a change (P01).
- **Unconditional lazy-grid failure:** not established by nesting alone (P02).
- **Blank frames always execute every OCR pass, or label OCR lacks cadence:** contradicted by the inspected eligibility/scheduling gates (P03).
- **Collapsing mapping rechecks or deleting the initial retry without preserving subscription ordering:** can reopen stale-authority/missed-event races (P04).
- **Deadlock or dropped ownership from the timed main-thread wait:** no deadlock or silent loss demonstrated. Blocking and surfaced failure are the validated M04 issue.
- **Confirmed cutout collision:** not established by padding alone (V01).

## Reconciliation of every original finding

### Earlier chat review A

| Original | Master disposition |
| --- | --- |
| F1 Certificate-less finish collision | M01, locally repaired with scoped native evidence |
| F2 Unknown-finish graded binding | M02, locally repaired with scoped native verification |
| F3 CSV currency/column interpretation | M03, locally repaired with scoped native verification |
| F4 Synchronous UI ownership writes | M04, merged with B5; reviewed UI ownership scope locally repaired, including final sealed/backfill/repair and CSV/delete lock-entry sweep; runtime acceptance remains |
| F5 Ready opening delay | M05, locally repaired; existing reveal retained and hosted readiness regression passes |
| F6 Missing collection game filters | M06, locally repaired; all owned/retained identities offered without enabling unrelated capabilities |
| F7 Ineffective finish correction | M07, retained |
| F8 First-baseline same-count gap | M08, reproduction first; frequency unestablished |
| F9 Listing-photo disappearance cleanup | M09, conditional presentation consequences |
| F10 Empty Release URLs | M10, known owner-deferred release item |
| Measurement backlog and synthesis | P03–P10 and preservation recommendations; no duplicate implementation findings |

### Supplied review B

| Original | Validated observation | Master disposition |
| --- | --- | --- |
| 1 “Cascade invalidation storm” | Several workers read overlapping tables; fresh worker setup exists | P01; profile first. “Every save,” guaranteed savings/hitches, and low-risk universal unification not adopted |
| 2 Foil updates | Shared live motion can invalidate eligible overlays up to its delivery cap | P02; compare existing policies. No automatic static default or unsupported CPU/fps claim |
| 3 Nested lazy grid | The cited nesting exists | P02; eager realization not established; measure before layout change |
| 4 Detail task/mapping duplication | Catalog observer can trigger startup retry; repeated mapping checks exist | P04; scope narrowed to mapped raw games. Preserve current-authority checks and subscription handshake |
| 5 Main-thread removal lock | Synchronous timed wait and transaction exist | M04; merged, with risk raised and deadlock claim removed |
| 6 Ephemeral context | Serializer creates a fresh context within background writer execution | P01; cost unmeasured, isolation violation not established, reuse not recommended |
| 7 Multi-pass OCR | Eligible paths execute additional passes on a serial queue | P03; guarded/cadenced behavior retained; no blanket shortcut or invented thermal/timing numbers |
| 8 Dynamic Island collision | Root banner has eight-point top padding | V01; clipping unverified, existing safe-area behavior must be rendered |
| 9 Cache complexity | Touch/eviction use bounded linear arrays | N01; retain current implementation absent measured cost |
| Synthesis: centering dimensions and provider spacing | Accuracy/quota changes need evidence | P08 and P10; retained |

All nine B findings and ten A findings have a disposition. Rejected conclusions are preserved here so they are not accidentally reintroduced as approved work.

## Overall assessment and decisions

### Overall assessment

The foundation is appropriate for refinement. Conservative recognition, durable ownership events, price provenance, integer money handling, immutable UI projections, explicit background executors, and signed catalog boundaries serve concrete product needs. The most valuable defects are inconsistencies between workflows enforcing the same physical identity. Additional architecture is not the default remedy.

### Highest value before release

M01–M06 are locally repaired within the scope, verification and historical-data limits above. M04 still needs ordinary device latency and rendered interaction acceptance; M05 needs device/accessibility transition acceptance; M06 needs rendered picker/inspector acceptance. M07's action-availability first slice is verified; broader catalog-backed alternatives and rendered acceptance remain. Reproduce M08/M09 and V01 before implementing their conditional remedies. Keep M10 in its existing owner-controlled publication process.

### Responsiveness and polish

M04's demonstrated UI ownership blocking, M05's programmed opening hold and M06's missing game choices have been repaired locally; ordinary device latency still needs measurement. M07 now hides unusable correction actions; broader correction availability remains deferred. P01/P02/P03/P04/P06 are worthwhile measurements, not guaranteed bottlenecks. Listing-photo and banner consequences need rendering. Avoid optimizing theoretical operation counts while missing actual slow interactions.

### Complexity that can be removed

Opening timing is simplified under M05; M06 removes the collection filter's dependence on an unrelated capability decision. M07 removes the unusable correction action when no different valid finish exists. If measured, simplify one duplicate persistence read, task-start sequence, or CSV rollback accelerator at a time. Do not remove freshness, identity, ledger, or mapping validation merely because it repeats across concurrency boundaries.

### Correctness and reliability

M01–M03 are the strongest correctness findings. M08 identifies a narrower reconciliation gap. M06's verified filtering inconsistency and M07's misleading action availability are locally repaired; broader M07 alternative discovery remains. M09 remains conditional. Neither review established a reproducible crash, leak, deadlock, or live-provider failure. No source-only result certifies release readiness.

### Preserve unless new evidence warrants change

- Recognition confirmation, `CardLatch`, duplicate barriers, encounter ownership, and conservative ambiguity handling.
- Ownership serializer lock ordering, fresh transaction validation, expected quantities, activity/ledger history, import durability/idempotency, and price-identity authorization.
- Value-snapshot/background-actor boundaries, collection projection caching, and existing refresh coalescing/deltas.
- Portfolio replay structure, integer money/overflow safeguards, price currency/provenance separation, and honest stale-price handling.
- Current-authority mapping checks across suspension points and signed catalog monotonicity/activation boundaries.
- Existing image caching/downsampling and bounded caches; no new generic cache layer.
- Game-specific adapters where provider/identity contracts differ; no unification for its own sake.
- Finish effects until device evidence justifies changing the collection policy.
- Deferred CloudKit, verified purchase handling, and existing release gates; no source-only activation or readiness claim.

## Conservative remediation roadmap

Each row is independently reviewable and testable. Slices 1–4, slice 6 and slice 9's reviewed UI ownership scope have been locally implemented at the owner's request, with scoped evidence above. Slice 5's action-availability first slice is now implemented; its broader catalog-backed alternatives remain deferred. Runtime acceptance and broader service limitations remain explicit. Other slices remain proposals, not implementation or acceptance claims.

| Slice | Scope | Acceptance boundary |
| --- | --- | --- |
| 1 | M01 certificate-less finish admission/identity — locally implemented | Six new regressions pass, including reopen/CSV/binding/correction; expanded 123/124, with the sole failure reproduced in the pre-fix build |
| 2 | M02 finish certainty at every automatic graded binding path — locally implemented | Six focused regressions and all 318 expanded tests pass; unknown stays saved/unpriced, confirmed/proven singleton binds correctly, exact existing listings refresh |
| 3 | M03 deterministic supported CSV price inputs — locally implemented | Four focused regressions pass; expanded 469 passed, zero failed, one opt-in benchmark skipped; valid USD retained, ambiguous/foreign prices excluded from new observations and ledger valuation |
| 4 | M06 owned-game filter choices — locally implemented | Three focused and all 124 expanded tests pass for mixed/retained games, selection/clearing, query counts, detail-filter resets and existing collection behavior; rendered phone/tablet acceptance remains |
| 5 | M07 action-availability first slice — implemented; broader catalog alternatives deferred | Three new option regressions and all 124 selected cases pass; menu requires a different valid finish, finish information remains; rendered acceptance remains |
| 6 | M05 readiness handoff — locally implemented | Nine focused opening tests pass; expanded 68 passed, zero failed, one physical-device test skipped. Hosted fast/slow handoff begins within 100 ms; reveal completion, phase reset and recovery retained. Release-device interaction and rendered accessibility acceptance remain |
| 7 | M08 deterministic reproduction, then bounded reconciliation | Same-count pre-baseline edits visible; added launch work measured |
| 8 | M09/V01 separate presentation reproductions | Change only reproduced photo-lifetime or banner-layout failures; verify phone/tablet and cleanup |
| 9 | M04 reviewed UI ownership write paths — locally implemented, including final sealed acquisition, Browse backfill, Portfolio repair and CSV/delete exclusive entry | Final expanded verification: 615 passed, zero failed, one opt-in benchmark skipped. Fixed paths permit main-thread heartbeats during contention; durable results, authorization, lineage, file ownership and Undo preserved. Device/rendered acceptance and the explicitly retained broader service boundaries remain |
| 10 | P01–P10 targeted baseline captures | Optimize only demonstrated material cost; each optimization paired with accuracy/state regressions |
| 11 | M10 existing publication/release configuration | Owner-authorized published endpoints work in the built release candidate |

Do not combine a persistence-read rewrite, transaction-context reuse, rendering-policy change, and OCR tuning into one performance slice. Their invariants and acceptance evidence differ.

## Remaining confidence limits

Comprehensive production subsystem coverage was achieved, with deeper cross-file tracing of high-risk paths. Confidence remains limited for runtime frame budgets, large-store memory, camera/lighting accuracy, centering precision, SwiftUI presentation/layout lifetimes, actual provider quota/availability, purchases in distribution, CloudKit restoration, historical on-disk migration permutations, and the final packaged release configuration. None of those gates is closed by this report.

## 2026-10-29 high-confidence refinement fixes

**Candidate:** `9aeeff4`; existing artwork/history and other user changes were
preserved. These small repairs follow the later
comprehensive source review; they do not replace the earlier findings ledger.

| Demonstrated problem | Small repair and complexity effect | Verification |
| --- | --- | --- |
| Fallback search chose the first matching numbered product when several marketplace products matched. | Require one matching product before returning a price or retaining provider handles. Preserves complexity; conservative misses replace arbitrary identity choices. | Ambiguous responses in both orders and duplicate rows remain unresolved; a unique numbered result and the existing direct Magic handle still price correctly. |
| Cancelled directory/daily-price consumers waited for a shared download to finish. | Release each cancelled waiter independently; let the shared operation own cache publication, failure state and pending cleanup. Adds one small helper shared by the two actors. | A held download does not delay cancellation; the remaining consumer receives the single request's result, and the daily cache survives reopening. Directory failure remains retryable. |
| A catalog activation event could be lost while a collection import held the writer. | Retry only serializer contention without blocking the UI thread; coalesce to the newest durable snapshot and stop for a retired storage session. Adds bounded per-subscriber retry state. | Both existing subscribers receive revision 3 after contention, without duplicate revisions; a stale session never publishes. Existing save-failure and withdrawal tests pass. |
| Lorcana discovery cards could look collectible until the detail screen refused acquisition. | Carry optional catalog-owned availability copy into set tiles, card tiles and search results, including accessibility labels. Adds two optional display fields; ownership authority is unchanged. | Bundled set 14 is browse-only; set 1 is partially supported; card notices agree with acquisition authority. Search, artwork copies, Codable round trips and older payloads are covered. |
| Unsupported games displayed an unexplained disabled graded-copy action. | Omit that action when the runtime lacks graded acquisition capability. Slightly reduces UI complexity. | Rendered unsupported Lorcana detail omits it; supported Pokémon detail retains both raw and graded acquisition. |
| Centering retained original encoded photo bytes solely for a DEBUG loaded-state check. | Keep a Boolean loaded-state marker instead. Reduces retained state without changing detection, guides or rotation. | All 52 selected centering analyzer/export tests pass. The deterministic fixture and controls render using the existing local-tools compiler flag; normal Debug retains the purchase gate. No measured memory-size or precision claim. |
| Key removal reported success and cleared UI state after a Keychain deletion failure. | Return an error before changing the key/toggle state when deletion fails. Preserves complexity. | Normal dummy-key save/remove was verified in the Simulator. The failure branch was source-reviewed; no physical Keychain failure was injected. |
| At maximum text size, Browse search filters and badges collapsed into narrow columns. | Stack them at accessibility sizes using native layout; retain the standard-size row. Adds two local layout choices. | Latest-build screenshots show readable controls and a scroll-accessible availability notice in maximum Dynamic Type/dark mode; standard-size rendering remains intact. |

### Current verification and limits

- Normal locally signed Debug build and expanded native selection: **431 passed,
  6 skipped, 0 failures** out of 437 cases on iPhone 17 Pro / iOS 27.0 Simulator.
  Coverage includes fallback/directory matching, One Piece integration, Lorcana
  discovery/pricing, Yu-Gi-Oh! pricing, refresh lifecycle, Browse/loading/collection,
  and centering analyzer/export. Six prepared Lorcana expansion acceptance cases
  require a separate hash-bound input workspace; they were not silently accepted.
- The initial unsigned run had 197 passes and 9 Keychain entitlement failures
  (`errSecMissingEntitlement`); the normally signed fallback rerun passed all 53
  cases, and the expanded final run above used normal signing.
- A final rendered rail check found that its lazy horizontal stack clipped a
  later availability caption after measuring an earlier tile. Reserving that
  caption space in rail tiles fixes the introduced layout issue; the subsequent
  normal Debug build and 81 Browse/loading/set-artwork tests pass without skips
  or failures. The 431-pass expanded run preceded this final layout-only repair.
- Scoped HIG gate: PASS for truthful capability/availability copy, preserved
  supported actions, semantic availability text and accessible-size stacking.
  Native hierarchy inspection includes the new availability labels. Physical
  VoiceOver, touch/camera behavior and distribution purchases remain unverified.
- HIG categories: platform patterns PASS (native controls/navigation); clarity
  PASS (availability precedes acquisition); typography PASS (semantic text and
  accessibility-size stacking); accessibility baseline PASS within inspected
  labels/layouts; friction PASS (no new prompts); design consistency PASS
  (supported actions retained). Verdict: PASS for this patch. Top issues: none
  remaining within this scope. Minimal fix list: none beyond the implemented
  availability, graded-action and accessible-layout changes above.
- Evidence is external under
  `/Volumes/Keller Family Photos/CodexBuilds/CardScannerRefinement-20261029/`:
  `Regression.xcresult`, `regression.log`, and `UI/`. No full-suite, live-provider,
  physical-device, CloudKit, archive or release acceptance is claimed.
- Intentionally unchanged: published mirror/readback configuration, One Piece
  production enablement, later Lorcana physical-catalog expansion, and the
  owner-deferred privacy/support publication. These require their existing
  data/product/release decisions, not automatic code fallbacks. Image decode,
  large Activity/import costs and launch/frame budgets remain measurement work.

## 2026-10-30 refinement implementation and S6 stop gate

**Candidate:** `refinement/review-2026-10-30`, based on `f22d28f`; accepted
implementation through `f05a734`, dated 2026-10-30. Each accepted slice was
committed and pushed separately. No PR was opened. The eight pre-existing
working-tree changes were preserved and excluded from these commits;
verification ran with those changes present.

| Slice | Commit | Implemented scope and verification |
| --- | --- | --- |
| S1 | `f0149b0` | Exclude `OnePieceOwnerCatalog` in app-target Release and DebugProduction. Release and Debug simulator builds pass. Release omits the directory; Debug retains its 21,356 KiB (20.9 MiB). Both One Piece suites pass all 102 cases. No fallback script was needed. |
| S2 | `bc6e369` | Scanner and activity correction fallback prices use the existing background writer and storage-generation continuation. The exact Lorcana scan-to-price regression passes; expanded coverage has 498 passes, six prepared-data skips and no failures. Neither changed file constructs a fresh-checkpoint `PriceStore`. |
| S3 | `ecd1eab` | Read coverage near the newest published close with a seven-day margin; retain the 400-day pruning/chart horizon. Reconciliation has 86 passes and one opt-in benchmark skip; four expanded portfolio suites pass all 129 cases. The two existing coverage-contract tests remain unchanged and pass. Both deliberate benchmark runs below pass. |
| S4 | `204d6d7` | Reuse incomplete local/network Magic migration reports until invalidation. Completeness diagnostics remain unchanged. The new regression and all 109 expanded treatment, migration, snapshot, revision-monitor and refresh-lifecycle cases pass. |
| S5 | `f05a734` | Extract shared launch sequencing and default runtime binding. Source comparison confirms equivalent fixture, launch and binding statement order. Debug, Release and ReleaseLocal simulator builds pass; opening/launch/bootstrap coverage has 48 passes, one physical-device-only skip and no failures. |

`YuGiOhIntegrationTests` names a file rather than an XCTest class. S2 therefore
ran all ten classes in that file separately (94 passes, included in the 498
total). S4 includes the separate `MagicTreatmentMigrationTests` coordinator
class. Tests used normal local signing on iPhone 17 Pro / iOS 27.0 Simulator
with Xcode 27.1. An initial package-resolution failure from a missing compiler
cache was resolved by directing that cache to the external SSD.

### S3 measurements

The opt-in fixture has 300 instruments, 365 days, 109,500 check-day rows and
5,700 observations. These are simulator fixture timings, not device claims.

| Measurement | Before S3 | After S3 |
| --- | --- | --- |
| Full-window `coverageIndex`, no published close | 1.057006 s | 0.961710 s |
| `coverageIndex`, yesterday's close present | Not measured | 0.025211 s |
| `PriceRefreshDataIndex.init` | 0.129414 s | 0.101061 s |

The newest-close read is approximately 2.6% of the same run's full-window read.
Xcode did not forward the shell's `PERF_BASELINE` variable, so the first
invocation skipped. Measured runs used `EnvironmentVariables` in external
`.xctestrun` specifications; the repository scheme was not edited.

### S6 measured, rejected and reverted

> **Historical checkpoint, superseded on 2026-10-31:** S6 subsequently landed in
> `3e497f6`. The [verified follow-up](#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes)
> below records its fresh crash-gate results and the later S7 work.

A temporary test helper generated an on-disk fixture with 300 owned instruments,
365 days of checks, 5,700 observations and published closes through yesterday.
The helper was removed without being committed. The optimized ReleaseLocal app
reopened the fixture and displayed its expected $1,275 portfolio.

The valid Logging trace explicitly enabled the `TradingCardScanner` subsystem
to capture its custom `Performance` category. `Launch.storageStart` began at
7.870789375 s and the first `priceRefresh.run` began at 14.755697666 s into the
recording. Their **6.884908291 s** difference is a lower bound on launch-to-refresh
entry, exceeding the approximately one-second gate. Two preceding coverage reads
took approximately 96.1 ms and 32.3 ms. This warmed fixture's recorded refresh
attempt had no eligible targets: the timing is refresh entry, not a provider
response or an exact process-start measurement. Earlier recorder setup attempts
did not capture the custom category and are not timing evidence.

The authorized one-line change passed the focused M08 same-count first-baseline
regression. Its expanded selection then crashed with **SIGTRAP / EXC_BREAKPOINT
in SwiftData**, with the faulting stack through `PortfolioEngine.startRecompute`,
`finishAppliedComputation` and `apply`.
`PriceRefreshLifecycleTests.testProgressRelayPublishesTrailingCountWhileProviderIsIdle`
was active when the process exited; that does not establish the relay as the
cause. Xcode restarted the remaining tests, then stalled finalizing results.
The runner was interrupted and terminated (exit 143), so that invocation is not
a successful run or a finalized result bundle.

With **only the S6 line reverted**, the identical selection passed: **119 passed,
one opt-in benchmark skipped, zero failures** out of 120 cases. The failure was
not reproduced on the pre-S6 baseline and must not be classified as pre-existing.
A queued context/container lifetime issue is a source-level suspicion, not an
established root cause: the pending request stores a `ModelContext`, and
`startRecompute` reads `context.container`.

At this historical checkpoint, S6 remained reverted and had no commit. Per the
owner's stop-on-failed-acceptance rule, no additional engine fix was improvised.
Resolving this failed gate, or an owner decision to defer S6, was required
before continuing the ordered plan.

### Remaining work and evidence limits

**Historical status:** the S6/S7 and final-verification status below is superseded
by the [2026-10-31 follow-up](#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes).
The original stop record is retained.

- S7a was not started because S6 failed acceptance. No scan-write measurements
  exist at either requested shape. S7b's 50 ms gate has not been evaluated; no
  index benefit, deployment-target change or simulator upgrade acceptance is
  claimed.
- The final cross-slice expanded run remains pending. The accepted per-slice
  runs above do not complete the plan's end-to-end gate.
- Release's app bundle was rechecked after S5 and still omits the owner catalog.
  Existing user changes remain uncommitted; no generated artifacts were staged.
- Evidence is external under
  `/Volumes/Keller Family Photos/CodexBuilds/refinement-review-2026-10-30/`.
  The accepted timing source is `s6-before-logging.trace` and its exported
  signposts. Raw logs, screenshots, stores and results are not repo artifacts.
- Owner device checks remain open: a 30-card Lorcana Instruments session without
  main-thread ownership-lock waits, mature-collection launch-to-refresh timing,
  and prompt Portfolio updates after a quantity edit. No physical-device,
  provider, CloudKit, archive or release readiness is claimed.

## 2026-10-31 refinement follow-up verification and accuracy fixes

**Status:** complete; remote branch verified at `5344635` on 2026-10-31.
At that verification point, `origin/main` was at `ade96f1` and the branch had
not yet been merged. This closeout uses the existing Mac build/test artifacts;
no new test run accompanies it. The later integration is recorded in Git history.

| Follow-up step | Closed with |
| --- | --- |
| 1 — Verify what shipped | Configuration/resource checks, two passing S6 repetitions, S7 measurements and in-place simulator upgrade checks recorded below |
| 2 — Defect A | `3241304`; reproduced failure, fixed owned-history cutoff and passing regression/expanded selection |
| 3 — Defect B | `408e439`; reproduced failure, widened backdated-event coverage and passing regression/expanded selection |
| 4 — Reconcile docs | `5344635`; audit, progress and release evidence reconciled, with this explicit closeout |

The final combined selection has **808 passed, eight skipped, zero failed**;
the final Release build passes. Physical index creation after upgrade and
cross-device backdated coverage remain unresolved. Owner-device, provider,
CloudKit, archive and release acceptance remain open as detailed below.

**Candidate:** `refinement/review-followup-2026-10-31`, from `origin/main`
at `ade96f1`. The starting tree was clean: the former eight local edits are
already in the merged history. Follow-up commits are pushed separately; no PR
or merge to `main` was made. Tests use normal local signing, Xcode 27.1 and
iPhone 17 Pro / iOS 27.0 Simulator. These are selected-suite simulator results.

### Verify the shipped changes

Debug, Release and ReleaseLocal simulator builds pass at the reviewed baseline.
Release omits `OnePieceOwnerCatalog`; Debug retains it. All ten app/test
deployment settings are iOS 18.0. A final Release rebuild at `408e439` also
passes and omits the owner catalog. The first test invocation could not find the
requested iPhone 17 Pro destination (exit 70, no tests); creating that simulator
resolved the setup issue without changing existing simulators.

S6 was re-landed in `3e497f6`, retaining the model container through queued
recompute completion or cancellation. The initial fresh crash-gate repetitions
reported 120 passed / one skipped / zero failed, then 119 passed / one skipped /
one failed. Neither crashed. The second run failed
`testRefreshArrivingDuringSuspensionQueuesWithoutWaitingForResume` at line 549:
it used a real catalog request and expected completion within about one second.
Xcode exited 65; its separate simulator diagnostic collection timed out after
600 seconds. The owner authorized a focused unblock.

`9453ea5` makes that test deterministic using the existing fixture-fetch override
and queued-refresh completion API, with no production change. Its focused test
passes. Both complete crash-gate repetitions then pass, including
`testQueuedRecomputeRetainsItsContainerUntilCompletionOrCancellation`:

| Step 1 selection | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: |
| S6: revision monitor, refresh lifecycle, reconciliation — repetition 1 | 120 | 1 | 0 |
| Same selection — repetition 2 | 120 | 1 | 0 |
| `d115390`: Pokémon CSV pricing and portfolio history | 87 | 0 | 0 |
| Store continuity, storage bootstrap, replay engine and closes | 100 | 1 | 0 |
| S2: Lorcana, scanner, One Piece, Yu-Gi-Oh!, product fallback and activity history | 499 | 6 | 0 |

The S2 selection includes both One Piece classes and all ten classes in
`YuGiOhIntegrationTests.swift`. Skips are the opt-in performance baseline,
physical-device file protection and six prepared-data/live-provider opt-ins.

### S7 measurements and in-place upgrade

Fresh external `.xctestrun` environment settings ran the unchanged benchmark at
1,500 instruments × 365 days: 547,500 check days and 28,500 observations.
The exact pre-index `e292646` source was exported and built separately; the
indexed product uses `ade96f1` production code with the test-only unblock above.

| Measurement | Pre-index `e292646` | Indexed main product |
| --- | ---: | ---: |
| Scan price write | 51.261084 ms | 29.578375 ms |
| Full-window `coverageIndex` | 5.010375041 s | 5.780256333 s |
| `coverageIndex`, newest close present | 0.123734959 s | 0.126457250 s |

Both benchmark cases pass. The pre-index scan write exceeds the approved 50 ms
gate. These are single-run in-memory fixture timings; the full-window coverage
read did not improve in this comparison.

The mandatory simulator upgrade installed the iOS-17-targeting `e292646` app,
seeded four fixture holdings, saved two quantity additions and invoked Refresh
prices, then installed the iOS-18-targeting main product over it without deleting
the app. Every semantic row in the collection, price, inventory/activity,
observation, check-day and daily-close tables matches before/after; the store
identity is unchanged. The UI retains the $1,802 total, quantities 1/1/2/3,
stored unit prices $108/$126/$271/$342 and 30 Portfolio history points.
Startup logs contain no migration or store-open errors.

The first card-detail chart check used an injected debug series. A second
isolated `e292646` → main upgrade seeds the actual disk cache with three
synthetic prices ($10/$13/$20) and launches without chart injection. Both
builds display +$10 / +100%; the cache bytes match exactly after upgrade.
This verifies persisted chart-cache retention. The synthetic provider IDs
report some prices unavailable on manual refresh; stored prices remain intact.
These fixture checks do not establish live-provider history or refresh success.
The SQLite index lists for `PriceCheckDay` and `PriceObservation` remain empty
after upgrade. Data retention passed, but creation of physical indexes and an
on-disk upgrade performance benefit are not established by this evidence.

### Accuracy fixes

- **Defect A — `3241304`:** shared catalog observations stop at the earlier of
  first owned observation and the owned record's quote/withdrawal time. A later
  unchanged owned refresh cannot move that cutoff forward. The new whole-day
  regression fails against main production logic with three $9 closes instead
  of $10; the $8 acquisition remains correct. After the fix the focused case
  passes, and the three acceptance suites report 159 passed, one benchmark
  skipped and zero failed.
- **Defect B — `408e439`:** coverage widens from the recent margin to the earliest
  backdated event recorded after the newest close's `computedAt`, using the
  events already read and one newest-close fetch. The epoch/400-day bounds and
  public coverage wrapper behavior remain. Against main production sources the
  regression starts coverage on October 23, omitting the October 1 acquisition's
  check day; both assertions fail. After the fix it passes; expanded portfolio
  and activity coverage reports 274 passed, one benchmark skipped, zero failed.

The post-fix 300 × 365 S3 benchmark passes: full-window coverage is 1.021585834 s
and newest-close coverage is 0.021548084 s (about 2.1%); scan write is
0.014899416 s. Both new regressions were verified against `origin/main`
production logic before their fixes. The existing coverage-contract and
newest-close tests pass unchanged.

**Known coverage residual:** a CloudKit event arriving from another device with
`recordedAt` before this device's newest close still retains the older coverage
outside the margin. This remains a documented tradeoff, like edits beyond the
400-day evidence horizon; no additional synchronization mechanism was added.

**Final expanded verification:** at code tip `408e439`, the combined 25-class
selection executes 816 cases: **808 passed, eight skipped, zero failed**.
It includes both new regressions, the S6 lifetime/crash selection and all
portfolio, pricing, scanner and storage classes listed above. No SIGTRAP occurs.

Evidence remains external under
`/Volumes/Keller Family Photos/CodexBuilds/refinement-review-followup-2026-10-31/`.
Raw logs, stores, screenshots and result bundles are excluded from commits.
Owner checks remain open: a 30-card Lorcana session without main-thread lock
waits, mature-collection launch-to-refresh timing, consistent coverage after a
backdated sale, and an iOS 18 device upgrade from the App Store build. No
physical-device, provider, CloudKit, archive or release readiness is claimed.

## 2026-10-31 production review (second pass)

**Status:** S2–S7a implemented on `refinement/production-review-2026-10-31`
from `main` at `b592c91`, dated 2026-10-31. Each slice was committed and pushed
separately; no PR or merge. The owner's device measurement batch is pending.

A read-only review of launch, the scan → identify → save path, persistence,
Collection, card detail, Portfolio, sharing, Price Check, images, refresh,
StoreKit and listing photos found no new crash or data-loss defect. Its ten
findings are numbered R1–R10 here so they do not collide with the M/P/V ids
above. Line numbers in the review referred to `b592c91`.

| ID | Finding | Disposition |
| --- | --- | --- |
| R1 | Scan rail, session stack, review sheet and Price Check images used plain `AsyncImage`: no app cache, no fallback URLs, full-size decodes | S1, implemented separately on `refinement/scan-artwork-2026-10-31` |
| R2 | Four private `@Published` scanner bookkeeping values redrew every scanner observer; they only feed `canReloadCatalogs` | S2 |
| R3 | The price-check share sheet re-rendered its 1080 × 1350 bitmap on the main thread for every asking-price keystroke | S3 |
| R4 | Share was a dead end without artwork | Already fixed by `50ea0fe` before this pass |
| R5 | The card-detail chart model is rebuilt in `body` on every drag point, and `rangeEnd: now` makes two models never equal | Measure (M4), then conditional S8 |
| R6 | Collection tiles' 128 px accent copies shared the 60-entry decoded-image caches with full-size tiles | S4 |
| R7 | The listing-photo picker loaded every collected card on the main thread to find the few with photos | S5 |
| R8 | Price Check saves quotes on the main thread, and its coordinator is recreated on each Scan appearance | Measure (M9), then S10 stop-and-report |
| R9 | Quantity +/− waits for a full background write on every tap | Measure (M8), then conditional S9 |
| R10 | Graded finish choices and set links built a throwaway `BrowseCatalog` | S6 |

Two suspects were checked and cleared: correcting a whole slab's finish keeps its
collection key, and the StoreKit flow handles Ask to Buy, revocation and retry.

### Implemented slices

Tests ran with Xcode 27.1 on a dedicated iPhone 17 Pro / iOS 27.0 simulator, from
a separate worktree, because the S1 work was active in the main checkout.

| Slice | Commit | Scope and verification |
| --- | --- | --- |
| S2 | `3808d8d` | The four bookkeeping values became plain properties updating one published flag that changes only when reload availability flips. Scanner, One Piece, scan-metrics and suppression suites: 241 passed, 0 failed, 0 skipped, including two new `objectWillChange`-count tests. |
| S3 | `228d52f` | When only the asking price changed, the share bitmap is cleared and rendered after a 200 ms pause; the preview still follows every keystroke. Adds the `CardShare.render` signpost. Share suites: 25 passed, 0 failed, 0 skipped. The debug review route opens with Share enabled at once; typing was not exercised because simulator input access was not granted. |
| S4 | `b60c250` | Both decoded-image memory caches are bounded only by their 48 MiB byte limit; the collection store's zero fallback cost now uses a pixel estimate. Browse, orphan-sweep and detail-render suites: 84 passed, 0 failed, 0 skipped. |
| S5 | `3ba8801` | The picker reads only cards with a photo key or a legacy filename; eligibility rules are unchanged and live in `ListingPhotoCardSource`. Collector Tools plus the new predicate test: 11 passed, 0 failed, 1 self-skipped. A first run on the freshly created simulator failed three local StoreKit tests at product loading; they passed on rerun with and without the change. |
| S6 | `6f37dce` | `ContentView` publishes its session catalog as `sharedBrowseCatalog`; graded finish loading and set links use it first, with the previous fallbacks retained. Browse, Browse-presentation and activity-history suites: 167 passed, 0 failed, 0 skipped. |
| S7a | `8b8ee92` | Adds `CardDetail.chartModel`, `CardDetail.quantityWrite` and `PriceCheck.quoteSave` signposts and the device runbook. Activity-history and quote-cache suites: 125 passed, 0 failed, 0 skipped. The Release simulator build succeeds and still omits `OnePieceOwnerCatalog`. |

Combined verification at `8b8ee92` ran the fourteen test classes the slices
touched in one simulator session: 496 tests, 494 passed and 1 self-skipped
(`testLocalStoreKitInterruptedPurchaseReconcilesAfterIssueResolution`). The test
runner exited once, during `BrowseFeatureTests.testRecoverySearchDoesNotRequestSealedProducts`,
while the freshly rebooted simulator's own system daemons were being killed on
timeout. No app crash report was written, and Xcode restarted the runner and
finished the remaining tests. Rerun alone, `BrowseFeatureTests` passed 69 of 69,
including that test. An earlier attempt never started its tests because the
simulator's launch service died (Mach error -308), so the simulator was restarted
before the counted run.

### Measurement batch and decisions

The device runbook (M1–M9) and its decision rules are in the
[hang inspection plan](../plans/hang-inspection-plan.md#2026-10-31-review-measurement-batch).
No device numbers exist yet, so S8–S10 have not started. The S2, S3 and S4
benefits are unmeasured on hardware. Evidence is external under
`/Volumes/T7/CodexBuild/production-review-2026-10-31/`; logs and result bundles
are not repository artifacts. No physical-device, provider, CloudKit, archive or
release readiness is claimed.
