# CardScanner App Review Fix Plan

## Centering follow-up — 2026-11-09

The [focused six-failure investigation](docs/audits/centering-guided-repair.md#six-remaining-failures-focused-investigation--2026-11-09)
adds native-source review, clarifies the two different Starting Town reference
targets and records named timing stages. One bounded DEBUG-only optimization
reuses a selected design's immutable registration across paired paths; the
before/after Spinerock geometry is exactly equal. No accuracy selector, annotation,
support threshold, confidence guard or timing budget was changed. Eliminating
repeated registration does not establish an end-to-end speedup or resolve the
six failed acceptance methods. These remain open; the earlier broad regression
counts below are historical evidence for that run, not a new full-target result.
Focused follow-up verification covers 23 distinct methods: **17 pass, six fail**,
with no new failed method. The affected native transfers and fallback controls
pass, including the 34-photo library's unrelated-result preservation checks.

## Full-checkout regression investigation — 2026-11-09

Baseline: `dd48a5f` plus the existing November 9 refinement changes. The signed,
unfiltered Debug simulator target executed **3,248 cases: 3,195 passed, 32 failed,
21 skipped**. The three catalog packages separately executed **153 cases:
152 passed, one skipped, zero failed**. Failed tests are not 32 independent app
bugs: the full run included a camera-permission overlay, the owner shutting down
the simulator, three CSV assertion crashes, outdated test assumptions and known
centering research/accuracy gates.

Three small, high-confidence source fixes followed:

| Finding and location | Demonstrated behavior, remedy and benefit | Risk, complexity and verification |
| --- | --- | --- |
| CSV replay leaves staged ownership repairs — [CollectionCSV.swift](TradingCardScanner/Services/CollectionCSV.swift) | Moving replay recognition after identity validation exposed read-through repairs that dirty the context. Returning without saving/rolling back tripped the Debug serializer assertion in two Lorcana imports and a mixed-game Yu-Gi-Oh! import. Roll back this no-op row and discard its pending artwork cleanup after validation; retain the conflicting-identity checks. | Low risk: prior rows already commit individually. No quantity, history or schema rule changes. Complexity is preserved with two existing cleanup calls. Verify a clean context and unchanged material digest on replay, plus repeated isolated imports, failed-row retry and mixed-game reopen/resume. |
| Signed finish corrections become durable provider evidence — [PokemonCatalogSupport.swift](TradingCardScanner/Games/Pokemon/PokemonCatalogSupport.swift) | The resolved-card cache flattened the signed variant overlay into its stored finish list, so revoked authorization could survive cache reads. Store the underlying evidence without `reviewedAdditionalVariants`; existing reads reapply the current registry. Cache generation 3 rejects previously flattened files. | High confidence, low behavioral risk; old resolved caches incur a one-time miss/rebuild. No ownership data or SwiftData schema changes. Complexity is preserved. Verify live-to-cache reads, registry withdrawal, a cold adapter, weaker coverage, minimum finishes and old-generation rejection. The withdrawal fixture now isolates its provider from the bundled checklist. |
| Foreground return ignores disabled capture — [ScannerViewModel.swift](TradingCardScanner/Views/ScannerViewModel.swift) | `startCamera: false` applied only to the initial start. Foreground callbacks subsequently opened capture, requesting permission or producing simulator camera errors that invalidated a later pending choice. Retain the session's capture policy and honor it on foreground return; recognition eligibility still resumes independently. | High confidence, low risk: ordinary capture-enabled sessions retain their start path. One Boolean preserves the existing input across lifecycle callbacks. Verify the session requests no camera start, its preserved choice remains actionable, and a second choice is canceled only by backgrounding. All 136 scanner view-model tests pass. |

Test corrections preserve the checks' purpose: canvas pixel probes use the
rendered photo frame after automatic card fitting; profile normalization adds a
front fixture because the two back fixtures now bypass that branch; SwiftData
notification assertions require the consumed identifier keys while permitting
additional framework metadata. Current-format weak-coverage cache fixtures use
generation 3. No centering accuracy tolerance, annotation, reporting guard,
experimental promotion gate or timing budget was relaxed.

Broad post-fix verification executed **3,197 cases: 3,174 passed, two failed,
21 skipped**. All launch, Browse render, CSV replay/ownership, cache, scanner and
corrected diagnostic tests pass. The two failures are the unchanged initial-guide
accuracy and supplied-layout accuracy gates. The 45 print-pilot and seven native
research cases were run in the unfiltered baseline rather than repeated wholesale
in this broad selection; all five of their failed/interrupted cases were rerun
separately. The interrupted Prismatic library case passes. Three accuracy cases
and the assisted latency case still fail, leaving six persistent centering test
failures across the final-source runs. Every original failure group has a
disposition; no workflow failure is being hidden by an expected-failure marker.
Result-tree reconciliation confirms all **32 originally failed method IDs**
were rerun on final source: **26 pass, six fail, none are missing**.
This is not a green full-target or release-readiness claim.

### Remaining centering acceptance

| Gate | Reproduced evidence | Conservative next step |
| --- | --- | --- |
| Untouched initial guides | Four existing photos exceed the unchanged 2 percentage-point ratio limit; worst top/bottom error is about 10.97 pp. Final-source broad rerun reproduces the same errors. | Improve proposals using independently reviewed photo boundaries. Keep manual confirmation and the current annotations. |
| Supplied-layout probe | `IMG_0780` does not recover all reviewed boundaries. This is a DEBUG interpretation experiment. | Keep automatic routing stopped; validate boundary identity before implementing/promoting a new candidate. |
| Foil Gengar transfer and library membership (two methods) | The transfer remains unverified; four designs match where the experiment expects five. Both methods reproduce in `PilotFailureIsolation.xcresult`. | Preserve ordinary fallback and investigate the unsupported physical/printed boundary. A recognized design alone does not establish measured geometry. |
| Prismatic printed-frame right edge | Reproduces about 11.95 native pixels of error against the unchanged four-pixel limit. | Resolve the already documented partial right-edge transfer against the source photo; do not relax the limit. |
| Assisted-reference latency | Fresh-host rerun fails both budgets: upper median **0.963 s** versus 0.8 s, maximum **2.393 s** versus 1.5 s. | Profile named stages and measure representative device behavior before optimizing. Source tracing confirms this injected-reference route is DEBUG-only; these timings characterize that experimental path. |

Confidence is high that these gates remain unmet. A small, accuracy-preserving
algorithm fix is not established by the evidence; none was guessed here.
The [centering accuracy investigation](docs/audits/centering-guided-repair.md)
retains the failed candidates, independent-photo limits and promotion criteria.
An intermediate focused run exposed current-format cache fixtures that still
used generation 2; those fixtures were corrected and pass in the broad final run.

Artifacts and build data are on the external T7 SSD under
`ScanStash_ReadOnly_20261109`. The full run is `FullRegression.xcresult`; the broad
final-source result is `PostFixBroad.xcresult`; remaining pilot cases are in
`PilotFailureIsolation.xcresult` (one passed, three failed), and fresh-host timing
is in `LatencyIsolation.xcresult` (one failed). No commit or publication was made.
Final **unsigned ARM64 Release simulator compilation passes** with no compiler
errors (`ReleaseVerification.xcresult`). Added local documentation links and
anchors validate, and `git diff --check` passes. No production source changed
after the final test runs. Compilation is separate from device/archive acceptance.
Physical-device, live-provider, CloudKit, archive and sandbox interruption gates
remain open. Privacy/support publication remains explicitly owner-deferred until
final launch preparation in [release follow-ups](docs/plans/release_followups.md#owner-deferred-launch-links--2026-11-08).

## Ownership and purchase refinement — 2026-11-08

Owner-authorized fixes for the third review's two High and two Medium findings.
Preserve all 60 pre-existing modified files and the prior refinement work.
Baseline: `304328e` plus the reviewed working tree; no commit, schema change,
publication or release acceptance is authorized by this task.

| Slice | Acceptance / verification | Status |
| --- | --- | --- |
| Non-raw CSV ownership | Refuse contradictory uncertified-grade and sealed identities before quantity, pricing, history or replay changes; retain legitimate legacy and bound/unbound round trips. Import/resume and ownership tests. | Implemented; focused and expanded checks pass |
| Authenticated redirects | Reject redirects before forwarding either pricing client's API-key header. Keep injected sessions and normal success, cancellation, pacing and quota behavior. Local redirect and transport regressions. | Implemented; real-loopback and expanded transport checks pass |
| Purchase feedback | Restore messages follow accepted reconciliation; confirmed ownership clears obsolete pending/error feedback. Preserve verified ownership and revocation rules. Controlled races plus existing StoreKit tests. | Implemented; controlled, pending-approval and purchase/restore/refund checks pass; interrupted-purchase sandbox gate remains |
| Localized sale digits | Normalize localized decimal digits before the existing checked cents arithmetic; preserve blank, precision, sign and overflow rules. Locale and disposition regressions. | Implemented; locale and expanded disposition checks pass |

The review reproduced both non-raw merge errors, Arabic sale rejection, two
purchase-message inconsistencies and cross-host synthetic-key forwarding.
Those scratch probes are baseline evidence, not regression verification for
these fixes. Rollback is limited to the focused source/test changes in each
slice and this tracking entry; preserve the earlier diffs.

Further investigation covers catalog activation memory, opt-in logging cost
and inspection gestures. They are measurement candidates rather than confirmed
Medium defects; no architectural, retention, durability or gesture change is
justified without additional evidence. Privacy/support links remain
owner-deferred until final launch preparation.

The CSV slice changes `CollectionCSV.swift`; the redirect guard is shared by
`JustTCGTransport.swift` and `ProductPriceService.swift`; purchase feedback stays
in `CollectorToolsStore.swift`; sale parsing stays in `CollectionActivity.swift`.
Tests cover unchanged material store digests on rejected merges/replays,
failed-row retry, bound/unbound export round trips, controlled reconciliation
ordering, approved pending purchases and Arabic/Persian/Bengali decimal digits.
No persistence schema, entitlement, purchase access rule or dependency changes.

Initial verification exposed two test-harness problems: URLProtocol's synthetic
redirect callback crashed the async URLSession test, and a first real-server
fixture retained cached permanent redirects. The fixture now uses a real
loopback-only Network server and disables URLSession caching. Three existing
local StoreKit tests could not load their product through the connector's
packaged test-products run. Direct scheme testing passes the complete
purchase/reconstruction/restore/refund/photo-ZIP method; the expanded run uses
that same scheme path. No StoreKit assertions or skip conditions were changed.

Final affected-scope Debug simulator selection: **572 passed, 0 failed,
2 skipped**, reconciled against distinct console method records (574 executed).
It covers import/resume, ownership kinds/keys/ledger, portfolio reconciliation,
Magic treatment aliases/migration, disposition/activity, pricing transport and
fallbacks, and Collector Tools. Both clients reject 301/302/303/307/308 for
same-host and cross-host redirects before any destination request. An
unprotected positive control first proves the loopback fixture follows redirects
and forwards the synthetic key. Pending approval and the full purchase/restore/
refund/photo-ZIP workflow pass. Existing skips are the opt-in aged-store
benchmark and local StoreKit interrupted-purchase case, which reported a
verified entitlement before issue resolution. That interruption scenario still
requires sandbox acceptance; it is not counted as passed. The final unsigned
ARM64 Release simulator build passes with zero errors and the same 11 existing
production warnings. Build data is on the external SSD. Local documentation
links and `git diff --check` pass. This is not a new full-suite,
physical-device, CloudKit, provider, archive or release-readiness claim.

A final controlled ordering test also reproduced pending/error feedback
overwriting already-confirmed ownership when the original purchase call returns
after an approval update. Purchase completion now clears that obsolete feedback
when ownership is confirmed, without bypassing verified-delivery handling or
transaction finishing. Its two pre-fix assertions failed as expected; the final
expanded selection and repeated Release compilation pass with that regression
and final completion change included. No source changed after those checks.

A host probe of the actual opt-in metrics actor measured mean counter-write
costs of 0.91/4.63/36.64 ms at 0/20/200 sessions of 50 encounters each, with
473/186,793/1,863,673-byte payloads. Loading took 3.61/7.98/70.45 ms. These are
synthetic host/external-SSD diagnostics, not device responsiveness budgets.
Logging is off the main actor and opt-in; this evidence does not justify a
retention, durability or batching change. Catalog peak-memory and rendered
inspection-gesture behavior still need representative device evidence; neither
is established as a Medium-or-higher defect. Do not change either speculatively.

## Additional workflow refinement — 2026-11-08

Owner-authorized implementation of the additional review's two High and five
Medium findings. Preserve all 40 pre-existing modified files, including the
earlier refinement and marketplace/feed work. No commits, publication, schema
changes or release acceptance are part of this work.

| Slice | Acceptance / verification | Status |
| --- | --- | --- |
| Listing photo metadata | Strip sensitive image metadata from full JPEG output without resampling/recompressing the JPEG fast path; preserve orientation, color and size limits. Tagged-image and existing export/ZIP tests. | Implemented; expanded checks pass |
| Raw CSV identity | Reject contradictory explicit Pokémon/Magic raw keys and incompatible merges; preserve known legacy/treatment aliases and non-raw round trips. Validate ownership before replay detection. | Implemented; expanded import/ledger checks pass |
| Centering precision input | Require a complete localized finite number; preserve signed values, native editing boundaries and untouched precision. Parser and native editor tests. | Implemented; expanded native editor checks pass |
| Asking-price input | Accept a single localized positive amount, including intended currency/grouping formatting and decimal digits; reject ranges and malformed text. Share parser/render tests. | Implemented; parser/render checks pass |
| History cache failure | Return verified provider points when derived cache persistence fails; retain authority/cancellation checks. Fixture transport and unwritable-cache regression. | Implemented; history/transport checks pass |
| Portfolio dates | Format economic-day labels in the pinned portfolio timezone; preserve calendar/locale preferences, event timestamps and accounting. Travel/DST and presentation tests. | Implemented; expanded portfolio checks pass |
| CSV preparation feedback | Expose reading state and prevent duplicate selections; clear state on current success/failure while preserving request/generation fencing. Build and applicable settings/surface checks. | Implemented; compiled and settings construction checks pass |
| Abandoned centering analysis | Cancel the already-owned analysis task when its model is released. Keep temporary presentation/sheet behavior unchanged. | Implemented; expanded centering checks pass |

Baseline: source/host probes established GPS passthrough, malformed numeric
acceptance and timezone drift; the CSV and cache-failure findings are traced
across callers and guards. Prior 702/162/95-test results and the Release build
belong to the preceding refinement, not this new diff. Current verification is
recorded here as it completes. Rollback is limited to this section's focused
source/test changes, preserving every earlier change.

Further investigation covers centering task cancellation/export overlap, cold
native-detail crop latency and representative CSV parsing/import cost. Do not
alter detector accuracy, photo resolution, durability boundaries or add caches
without measured evidence. Physical camera/thermal/quality and release gates
remain separate. Privacy/support URLs remain owner-deferred until launch.

The first new selection built after correcting a String/CardGame comparison,
then reported 248 passes and 10 failed assertions. It exposed replay validation
ordering, a decimal formatter accepting exponent notation, and five assertions
that expected source JPEG metadata bytes. Ownership now validates before replay
detection, decimal fields reject exponent notation, and JPEG assertions verify
identical decoded pixels/color rather than private metadata. All 41 focused
follow-up tests pass, including two temporary timing probes (removed afterward).

The expanded selection initially passed 612 tests, skipped two opt-in benchmarks,
and failed two accounting tests whose synthetic ownership keys contradicted
their provider IDs. Corrected those fixtures to use canonical keys and added
explicit import-success assertions; all accounting assertions remain. The final
selection reports **614 passed, 0 failures, 2 skipped** across sharing/rendering,
CSV/resume, metadata/crops/ZIP/cancellation, provider/history contracts,
portfolio accounting/reconciliation, raw/graded/sealed identity, Magic legacy
treatments, native centering editing/export, ownership durability and view
construction. Skips are the existing experimental native-refinement benchmark
and opt-in aged-store baseline. This is affected-scope verification, not a new
full-suite or release certification. The native ARM64 **Release simulator build
passes** with zero errors and the same 11 previously recorded production
warnings; build data is on the external SSD. `git diff --check` and local links
in the new documentation entries pass. Interactive device file-picker/loading
and travel/accessibility smoke checks remain appropriate alongside the existing
release gates. No archive, physical-device, provider or CloudKit acceptance is
claimed.

Synthetic Debug simulator probes on this host: CSV parsing took 9.8/67.7/331.9 ms
for 100/1,000/5,000 rows; in-memory imports took 362.9/3,759.7 ms for 100/1,000
rows. A 3,024 × 4,032 JPEG took 710.8 ms to analyze; ten cold 200 × 200 native
crops took 3.9–6.7 ms each, and 100 cache hits took 0.11 ms total. The ordinary
900 × 1,200 working-canvas PNG export took 122.6 ms, below its existing 180 ms
edit debounce. These are diagnostic samples, not device budgets or comparative
benchmarks. No parser rewrite, batching/durability change, extra image cache,
crop threading refactor or export scheduling rewrite is justified by this
evidence. Analysis teardown cancellation is a two-line lifetime fix; physical
device crop/export latency, large-photo memory pressure and thermal behavior
remain measurement items. No permanent benchmark or diagnostic hooks were added.

## Production refinement fixes — 2026-11-08

Owner-authorized implementation of the major/high/medium, high-confidence
findings from the production review, based on `304328e` plus the existing dirty
marketplace-link/feed changes. Those changes are preserved. No commit, push,
publication, persistence schema change, or release acceptance is implied.
This section supersedes earlier dates only for the findings below.

| Slice | Smallest remedy and acceptance boundary | Status |
| --- | --- | --- |
| Graded refresh/history integrity | Commit the owner binding, price identity, observations, check-day coverage and inventory references in one existing serialized checkpoint. Revalidate exact ownership after network I/O; removed/corrected owners retain their history. A rejected quote rolls back the binding. Remove the obsolete split patch, handle-only owner index and unused price-only enqueue wrapper. | Implemented; expanded suite and final recheck pass |
| Sealed cache freshness | Carry the original retrieval date into Add. Recover missing legacy dates from the saved page envelope; never turn reopening a cache into a new successful price check. | Implemented; expanded suite and final recheck pass |
| Repeated collection work | Return the already-written scanner row directly. Quantity reads sum the same exact/legacy/duplicate rows without staging history repairs. | Implemented; expanded suite passes |
| Magic confirmed price gaps | Persist an explicit provider-confirmed no-USD answer and reuse it for the existing six-hour negative-cache period. Legacy nil amounts remain unknown and retry remains available. A newer saved price supersedes an older saved gap. | Implemented; final 95-test Browse/cache selection passes |
| Catalog identity normalization | Use POSIX folding for catalog identity and membership matching, independent of the device's language/region. Display and numeric input remain localized. | Implemented; app normalization and host package checks pass |
| Scanner price trust | Label old raw quotes “Last known,” including accessibility; identify the actual source and provider/retrieval date. Keep graded quote lifecycle rules separate from raw daily staleness. | Implemented; scanner and surface checks pass |
| Price range input | Accept localized decimal separators/digits; refuse invalid or reversed ranges instead of silently dropping a bound. Preserve fractional precision when reopening the form. | Implemented; decimal regression passes |
| Graded scan provenance | New scanner acquisitions write scan activity/ledger provenance; explicit graded Browse additions retain graded-catalog provenance. No historical rewriting. | Implemented; scanner, history and provenance checks pass |
| Reduce Motion | Suppress scanner chrome animations, receipt bounce and rail pulse/scale when enabled; retain ordinary behavior otherwise. The standalone slab prompt uses an opacity transition. | Implemented; scanner and surface checks pass; visual/device QA remains |

The first affected selection passes 231 tests. The initial expanded selection
exposed three assertions in one new rollback test: its fixture had no lifecycle
evidence and therefore exercised accepted quote retention, not quote rejection.
The fixture now supplies a newer exact lifecycle receipt, preserving the
rollback assertions. All other checks in that selection pass, including all 136
scanner view-model methods. The corrected expanded selection passes **702
distinct methods, zero failures/skips**, confirmed against individual console
records. Final tracing also removed the handle-only owner lookup: rows sharing
a vendor handle can have different finish price keys, so exact price identity
must select the owner. The **162-test recheck passes without failures or
skips**, including that new regression, rollback/removal, pricing, refresh
snapshots/races, disk price-gap replay, sealed surfaces and scanner overlays.
Extending disk replay to a later successful retry reproduced another cache
ordering problem: the old gap hid the newer saved price. Comparing check dates
fixes that precedence without adding a cache layer. The unchanged regression
then passes with the full **95-test Browse/cache selection, zero failures/skips**.
The earlier universal Release build was deliberately interrupted for this fix;
it is not counted as verification. Final unsigned **ARM64 Release simulator
compilation passes** (`CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`),
with zero compiler errors. Existing Swift concurrency/closure warnings remain;
this is not Swift 6 migration certification. No source changed after the final
95-test recheck. All 349 local documentation-link targets and whitespace checks
pass.
The host `PokemonCatalogCore` run passes 88 tests, with one opt-in live CDN
check skipped. Its first attempt could not open the default compiler cache;
the successful run explicitly uses the external SSD cache. Build data uses
`/Volumes/T7/ScanStash_Refinement_20261108`.

Rollback is limited to each slice's local source/test changes; preserve the
pre-existing marketplace/feed changes. Highest regression risk is ownership
lineage and alias quantity behavior, covered by history, treatment, refresh,
ledger and scanner tests. Cache additions decode older payloads without schema
migration. The checkpoint consolidation reduces complexity; freshness/input/
accessibility fixes add small pieces of state or validation with concrete uses.

### Investigated boundaries and remaining measurements

- Ordinary `card(forAnyKey:)` repair also validates and repairs activity,
  removal snapshots and ledger aliases. It cannot safely be replaced wholesale
  with a plain fetch. The redundant second scanner repair and read-side
  mutation are removed; further history-path optimization needs aged-store
  signpost evidence, not an unproven migration bypass.
- The 1,500-card opening/projection path, long-session recent-scan indexing and
  main-thread session-summary history work need Release latency/allocation
  measurements before adding caches or moving work. Use the existing
  [hang inspection protocol](docs/plans/hang-inspection-plan.md).
- The resolved Magic cache is capped at 512 entries and writes ordered snapshots
  off the scan path. Measure sustained scan write backlog and I/O before adding
  coalescing. Image decode/coalescing, foil rendering and motion energy also need
  trace evidence. Core Motion already stops with no eligible consumers and
  under Reduce Motion; inactive-scene energy remains a device measurement.
- Camera resolution/cadence/thermal behavior and large centering/photo-export
  memory peaks require representative physical devices. No camera or centering
  tuning is justified by simulator compilation/tests alone.
- Conditional cross-container snapshot coalescing and CloudKit behavior are
  not reproduced release defects; CloudKit remains intentionally disabled for
  1.0. Do not change persistence policy to address a hypothetical future mode.
- Privacy/support pages and URL configuration are explicitly owner-deferred
  until final launch preparation. The
  [release follow-up](docs/plans/release_followups.md#owner-deferred-launch-links--2026-11-08)
  owns that decision; keep the values empty until approved pages exist.

No physical-device, live-provider, CloudKit, archive, full-suite or release
certification follows from these focused checks. Rendered layout, Dynamic Type,
VoiceOver wording and Reduce Motion should receive the ordinary device polish
pass; the current source/runtime assertions do not establish pixel-level QA.

## Repository review follow-up — 2026-11-06

Owner-authorized high-confidence fixes on `main@11ff208`, preserving the
existing uncommitted source/test changes. No simulator use, commits, pushes,
publication or release-readiness claim. Verification uses unsigned generic iOS
builds, compilation of the existing iOS test target and host catalog-package
tests; iOS regression methods are not counted as executed.

| Slice | Acceptance / rollback boundary | Status |
| --- | --- | --- |
| Certified CSV identity | Reuse a compatible physical certificate across bound/unbound keys; refuse conflicts without changing ownership/history. Local import/store/test diff. | In progress |
| Yu-Gi-Oh current refresh | Live failure remains failure; initial offline valuation retains dated bundle support. Adapter/test diff. | Pending |
| Scan artwork latency | Exact identity can finish without awaiting optional image probes; retain signed artwork and later enrichment. Catalog/test diff. | Pending |
| Graded expiry publication | Known deadlines invalidate published current prices and portfolio projections; preserve history and superseding quotes. Snapshot/monitor/test diff. | Pending |
| Scanner storage fence | Recheck the captured storage generation within the serialized add; preserve ordinary authorized-write draining. Writer/view-model/test diff. | Pending |

Baseline review evidence: the preceding full app run executed 3,169 tests with
11 failing methods and 18 skipped; three host catalog packages executed 153
tests with zero failures and one skipped. This implementation will not use a
simulator. Centering algorithm changes and unmeasured rendering changes remain
evidence-dependent. Feed and privacy/support configuration require verified
published destinations; placeholder URLs will not be enabled.

## Browse pagination render investigation — 2026-11-05

Owner-authorized follow-up from clean `0a11fc7`. Tracing the held-provider fixture,
`BrowseViewModel` pagination and the actual `BrowseView` footer establishes an app
concurrency bug: a shared page batch blocks a newly ready lane. The original
four-request and zero-cancellation assertions and their deadlines are unchanged;
no retry-to-green or test skip. Baseline: the unchanged render
test fails 8/10 repetitions with three requests instead of four
(`BrowseRender-20261105/Baseline.xcresult` on the external T7 SSD).

- [x] Reproduce the unchanged failure.
- [x] Establish whether the missing request is fixture synchronization or app
  pagination; add a controlled interleaving regression.
- [x] Apply the smallest verified fix, rerun the original render test repeatedly
  and verify related search/cancellation behavior.

The five diagnostic repetitions all fail with both first responses finished,
one next page held and zero cancellations. The controlled real-view regression
then fails in both game orders (four assertions): an early page batch pins the
single footer, so a late initial response cannot start its next page. This is an
app concurrency bug; increasing the wait cannot release the held batch.

The implementation gives each card/sealed lane its own task in the same footer
and removes the shared key/revision/coordinator. The original render
test is byte-for-byte unchanged. Its first post-fix run and both new native
interleaving/departure tests pass. One adapted model test initially observed the
existing coalesced sealed-results update before delivery; it now awaits that
same result count within its existing readiness helper, retaining its assertions.
The native scroll-out/re-entry check caught a gap in the first fix: a replacement
footer could return while the cancelled request still marked its lane busy, then
never restart after that request settled (two failed assertions). Each lane now
advances its own pagination revision on settled cancellation, waking only its
replacement task without consuming the retained cursor. Existing query, error,
filter and hidden-screen gates remain in the view-model entry points.

The isolated Debug build passed, but `VerifiedFix.xcresult` records an early
test-host exit before any methods ran (zero tests, one infrastructure error).
The same built binary passed all 18 focused checks on a dedicated simulator
(`DedicatedFix.xcresult`), including the re-entry regression and all sealed
surface tests. The exact final source then passes **80 repeated render
executions: 20/20 for each of four methods**, including the unchanged original.
The controlled method exercises both game orders on every run. The stored
`RepeatedFinal.xcresult` metrics report four distinct methods with zero
failures/skips; console records retain all 80 executions. The exact final broader
selection passes **254 distinct methods, zero failures/skips**, covering Browse
search/loading/filtering, collection/checklist integration, presentation, rendered
pagination, sealed surfaces and view construction. `BroaderFinal.xcresult`
metrics agree with all 254 individual console records. The exact final **arm64
Release simulator build passed** (`release-final.log`, exit 0), with the tested
source unchanged. Its slower cold compile is not a controlled timing comparison
with the earlier warm build; a brief sample confirmed active LLVM optimization.
No optimization settings were changed. Whitespace, project-file syntax and added
local documentation-link checks pass.

Concurrent card-detail/pricing edits are preserved. Final verification uses an
external snapshot of `0a11fc7` plus only `BrowseView.swift`,
`SealedBrowseViews.swift` and `BrowseFeatureTests.swift` from this fix; its source
hashes are retained beside the results. Other in-progress changes are not
included or certified by that evidence.
Artifacts are retained under `/Volumes/T7/CodexBuild/BrowseRender-20261105`.
The two production files have 41 fewer net lines; no persistence schema changes.

Rollback is limited to this investigation's source/test/documentation diff.
The fix is committed and pushed on `main`; no physical-device or release
acceptance is claimed.

## High-confidence refinement fixes — 2026-11-05

User-authorized implementation following the repository-wide source review at
clean `40403c1`. This scope includes the small, high-confidence usability and
removal findings. The implementation is committed and pushed on `main`; no
publication or release-policy change is authorized by this implementation record.

| Slice | Acceptance and verification | Status |
| --- | --- | --- |
| Graded expiry | Wire conversion, retained graded variants, Price Check and collection binding reject elapsed current quotes; preserve legacy responses, historical evidence and new-sale recovery. Focused contract/quote-cache/pricing tests. | Implemented; affected 179-test selection passes |
| Sealed pagination | Search and set browsing advance by the provider limit, including empty filtered pages and cached continuation. Legacy cached products remain visible offline while incompatible cursors require refresh; fresh terminal pages retain their original freshness. | Implemented; all 11 sealed surface tests pass |
| Sealed setup | Missing credentials are reported for the requested game even when offline Lorcana is available; cached results remain usable. Search-state tests; HIG gate. | Implemented; affected selection passes |
| Quota preflight | Known daily/monthly/cooldown refusals precede pacing without spending quota or a pacing slot; final reservation stays atomic. Transport/ledger/cancellation tests. | Final 185-test contract/fallback recheck passes |
| Unused Browse history | Remove the unconsumed local history renderer/recorder/stamp request and obsolete diagnostic wiring; preserve current market charts, prices, portfolio history and existing files. Browse/history/portfolio tests and Release build. | Implemented; history/chart/portfolio checks and final Release build pass |

Rollback is limited to each slice's source/test diff. Baseline and final build
artifacts use the external T7 SSD. Baseline: 46 tests passed. All five new
regression methods failed against unchanged production code (23 assertions).
After the fixes, 179 affected methods pass with no failures/skips. This includes
expiry boundaries, history retention, new-sale recovery, cache isolation, empty
filtered pages, quota cancellation, interactive reserve and post-pacing quota
revalidation. Prior non-green full-suite evidence is not superseded here.
The direct-fallback regression separately reproduced both blocked waits before
its fix; all 54 fallback tests now pass. Its failed run required interruption
after tests finished because Xcode remained in diagnostic collection; the
assertions are retained in its log, without claiming a completed result bundle.
The cleanup retires tests solely for the removed recorder/chart factory, retains
chart scaling/range/scrubbing checks against provider history, and keeps the
provider-date parser used by bulk current pricing. Existing history files and
ownership/portfolio evidence are not deleted or migrated.
The cleanup selection passed 125/126 methods. One unchanged card-only render
test observed three requests instead of four. It failed twice in three isolated
current-tree runs and once in three runs of an isolated, unmodified `40403c1`
export. Its assertions and pagination implementation remain unchanged; this
pre-existing timing-sensitive check stays open rather than being weakened.
The first combined affected run subsequently passed **966 tests, one opt-in aged-store
benchmark skipped, zero failures** (967 total). Stored result-bundle metrics
agree with the console counts; all 966 passes have distinct method IDs. The run
includes all rendered-pagination cases, 29 selected graded/Price Check scanner
methods, current charts, cache upgrades, collection writes and portfolio replay.
Final quota fixtures additionally intercept HTTP at a synthetic host so a future
regression cannot contact a live provider. Their 185-test recheck passes.
The final cache refinement avoids refreshing a fresh legacy page without a
continuation, preserving its original timestamp. All 11 sealed surface tests,
including both migration paths, pass in the exact final affected run.
That final run executes **968 distinct methods: 966 passed, one opt-in benchmark
skipped, and the same pre-existing rendered-pagination assertion failed**.
`FinalAffected.xcresult` metrics agree with the console method records. The
earlier green combined run predates the terminal-cache refinement and fixture
hardening; it does not replace this non-green final result. The assertion, its
test body and the card-pagination implementation remain unchanged.
The exact final **arm64 Release simulator rebuild passed**
(`release-final-v2.log`, exit 0). An earlier universal Release build was
interrupted to finish cache compatibility and is not counted as a passing build.
The production diff removes 1,281 net lines without a persistence-schema change.
Final whitespace, project-file syntax and local documentation-link checks pass.
Artifacts are retained under `/Volumes/T7/CodexBuild/RefinementFixes-20261105`.

- [x] Implement the five scoped fixes and preserve stored data/current charts.
- [x] Reconcile final simulator test records, retain the baseline render failure,
  and complete the arm64 Release simulator build.

Source HIG gate: PASS; existing native empty-state copy/navigation and controls
are retained, with no added prompt or interaction. Rendered/device accessibility
acceptance is not claimed.
Centering-reference adjudication, published feed/public URLs and device profiles
remain evidence-dependent follow-ups, not automatic code fixes.

## Feed-cache fallback follow-up — 2026-10-31

Based on clean `main@17658c9`, following review of `21e6ec1`:

- [x] Reproduce loss of a still-valid saved snapshot after learning a newer
  feed build, including manual retry and the failure cooldown.
- [x] Return the original snapshot on refresh failure or cooldown while its
  validation remains under 24 hours old. Preserve quote/validation dates, failed
  request backoff, strict new-file validation and waiter cancellation.
- [x] Verify expiry during a request, lagging publication files, recovery and
  shared cancelled/non-cancelled waiters with recorded-response simulator tests.

No release gate or provider configuration changes were made. The source/test
fix is committed as `2b31f0d`; rollback is limited to its service/test diff.
Both new outage regressions failed against the committed service before the fix.
The post-fix feed suite passed **50 tests, zero failures/skips**, including all
five new regressions. The expanded feed/pricing/quote-cache selection passed
**171 tests, zero failures/skips**. The **Release simulator build passed**. The final feed
suite rerun also passed **50/50**, including the deterministic in-flight expiry
check. Diff whitespace and added local documentation links pass validation.
Earlier counts below describe the earlier candidate. The cache is never
restamped or rewritten on failure, and freshness is rechecked after the network
await. No live-provider, physical-device or distribution readiness is claimed.

## High-confidence refinement fixes — 2026-10-31

Scope: the five source-proven findings from the current review, based on clean
`main@36c2a64`. The owner authorized all high-confidence fixes, including the
small UI findings. The fixes are split into focused commits. Publication,
release-gate changes and speculative performance refactors remain out of scope.

- [x] Respect acquisition quantity in aggregated graded finish correction;
  verify split/merge, shared vendor quotes, earlier removed acquisitions,
  pricing, lineage, undo and transaction rollback.
- [x] End nil-artwork loading in Price Check and scan review; preserve existing
  artwork sizing and loading/error behavior.
- [x] Retry transient graded discovery in place; verify failure-to-success,
  incomplete search, terminal absence and overlapping-load protection.
- [x] Recover a daily feed publication rollover with one bounded marker refresh;
  verify ordinary/manual retry, torn responses and cache/coalescing behavior.
- [x] Restore the resolved-identity pricing diagnostic without weakening more
  specific reasons; remove the confirmed unused graded-picker summary state.

Baseline: repository status and diff were clean; prior review package tests had
145 passes and one opt-in live-network skip. The focused iOS baseline passed
168/168 tests. The four new correction/rollover/diagnostic regressions then
failed against unchanged production logic, confirming the reviewed defects.
Verification uses external-SSD DerivedData and recorded provider responses.
The first post-fix selection passed 175 tests; its graded-picker test could not
write its synthetic key because the unsigned simulator host lacks Keychain
entitlements (`-34018`). The signed rerun passed all three checks, including a
credential round trip; this was a test-host configuration failure. The broader
selection then passed 757 tests with one opt-in benchmark skipped. A Release
simulator build passed. A further correction-boundary regression reproduced
shared vendor price/history migration affecting another slab; its scoped ledger
fix and historical-acquisition regression passed the 273-test correction,
scanner/history and refresh-race selection. The final combined signed-simulator
selection passed **764 tests, zero failures, one opt-in benchmark skipped**.
The final 45-test feed suite passed, including fresh-cache manual retry,
known-build invalidation of cached sets and unchanged-build quote-date retention.
The exact final **Release simulator rebuild passed**, with no new compiler
warning messages relative to the earlier Release build. `git diff --check`
and the added local documentation links pass validation. All five code findings
are implemented; the owner-controlled and measurement gates below remain open.

The correction reuses the existing split/ledger transaction and removes the
duplicated graded branches. Partial corrections preserve other quantities;
bound whole-row corrections preserve shared vendor instruments and historical
events, moving only the selected claims with correction legs. Compatible
quotes retain their original retrieval date; incompatible quotes are not
borrowed. The detail screen explains which copies change and confirms a split.

UI gate: **PASS** for these scoped changes: native Retry and unavailable states,
existing navigation, no added confirmation prompt, and unchanged artwork sizing.
Hosted Price Check/scan review renders exposed the unavailable text at standard
and accessibility text sizes. Physical-device VoiceOver and provider acceptance
are not claimed. No dependency, persistence-schema or release-policy change.
Each fix stays local to its existing path; rollback is its focused source/test
diff. Privacy/support destinations require published owner-controlled URLs;
Activity/CSV performance changes require measurements and remain outside scope.
Commit references are recorded in the 2026-10-31 entry in `progress.md`.

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task. The remediation changes are now committed in the repository history;
> this plan does not constitute release certification.

## Previous checkout snapshot — 2026-09-20

At the time of this snapshot, this root-level file was the App Review
remediation authority. Its branch/SHA and suite counts describe the earlier
`feature/catalog-and-scanner-hardening` candidate, not the current worktree.
The tree at that time was
clean `feature/catalog-and-scanner-hardening` at `7dbaf40`.

Source-level storage hardening and focused regression coverage have progressed,
but production CloudKit enrollment, physical-device continuity, ownership-ledger
certification, and a clean exact-candidate suite remain open. The intended
candidate is the clean `feature/catalog-and-scanner-hardening` branch at
`7dbaf40`. The exact-candidate focused run executed 581 tests with 579 passed,
1 skipped, and 1 failed in the scanner catalog-miss test. The exact-candidate
full simulator run executed 1,278 tests with 6 skipped and 4 failures (1
unexpected); centering, ownership, and scanner catalog-miss failures remain
open. See the current
[`docs/release/phase-1-integrity-evidence.md`](docs/release/phase-1-integrity-evidence.md)
for the candidate ledger.

## Remediation snapshot at `810954e` — 2026-09-22

This remediation was recorded in the working tree based on `main@810954e` and
was subsequently committed in the repository history through
`main@9759050`. N1–N3, N5–N7, and F1–F4 are implemented. N4's
Settings copy is truthful, but its Release URLs remain open until the owner
provides the actual deployed destinations. The affected simulator regression
selection passed 99 tests with 1 skip; a separate delete-actor integration test
passed 1/1. The skipped file-protection assertion is a Simulator limitation,
not a device result. An intermediate broader run exposed and led to correction
of the synthetic-CSV canonicalization regression; it also reported an unrelated
existing Cardmarket expectation in `CatalogNormalizationTests`. No full-suite,
physical-device, CloudKit, archive, TestFlight, provider, or release
verification is claimed for the current `9759050` checkout. The counts below
remain evidence for the earlier `810954e` working-tree snapshot only.

The targeted follow-up batch for scanner-to-Settings bulk-operation access,
identity-aware fallback eligibility, retry latching, and truthful deletion
copy passed 4/4 selected tests on iPhone 17 Pro / iOS 26.5 Simulator. This
confirms source behavior only; active-refresh timing and physical-device
behavior remain open.

| Finding | Code-level change and acceptance | Status / remaining evidence |
| --- | --- | --- |
| N1 — duplicate proof lifetime | `ScannerViewModel.pruneSpatialResetProofsToLiveHistory()` retains token-bound evidence only while its encounter and presentation token remain in `committedSessionHistory`. A proof with `presentationToken == nil` is provisional and survives only while `oneCardScanIntervals[encounterID]` shows that encounter is still pending. Prune immediately after the bounded history trim and after automatic routing, `addAnother`, held-repeat, and suppression. Keep the full clears at session reset and interruption. `undoScan` already removes the undone encounter's proof; retain that scoped behavior and cover it. Acceptance: A→B→A′ presents the duplicate dialog; choosing **Same card** never inserts A′. This explicitly accepts a prompt for the same physical A after B where the prior behavior silently suppressed it. | Regression coverage exercises A→B→A′, `addAnother`, held-repeat, scoped undo, and the no-add Same card choice. Device stack acceptance remains open. |
| N2.1 — skip an unused account probe | When `readinessSource.isProven == false`, pass `CloudAccountAvailability.notQueried` through `CollectionStoragePolicy`; do not substitute `.noAccount`. Policy opens a verified local replica but conservatively blocks when a manifest exists and the replica is absent. Bootstrap skips account and anchor probes and ignores account-change notifications in unproven mode. | Policy/bootstrap tests cover fresh local open, verified-replica open, missing-replica block, zero account-probe calls, and account-change no-op. Fresh-install airplane-mode launch timing remains a device check. |
| N2.2 — reuse a same-process local container (separate slice) | Before `start()` suspends the storage generation, cancels refresh, pauses Magic migration, or creates a container, reuse `storageGeneration.activeSession()` only when readiness remains unproven, the session is `.onDevice`, and policy selects the exact same `storeID` with `.restorationUnproven`. Preserve the generation token and current attachment state. | A bootstrap test asserts the container instance is reused, its generation token remains current, and neither the account probe nor a second container creation occurs. Device acceptance must exercise background-task launch followed by foreground start in the same process and verify no duplicate store open/write. |
| N3 — locked background refresh | Remove the `isProtectedDataAvailable` early return from `BackgroundPriceRefresh.run`. Set `completeUntilFirstUserAuthentication` at all four manifest/identity write sites in `CollectionStoreManifestStore`: the manifest metadata directory and temporary manifest before replacement; the identity metadata directory and temporary identity sidecar before replacement. On a readable foreground load, best-effort migrate existing manifest, sidecar, and metadata-directory attributes. | Simulator cannot report the protection attributes; its test skips explicitly. Keep locked-and-charging device verification open. The privacy policy states the tradeoff: after first unlock, the local manifest and identity metadata (store ID, attachment/migration state, opaque account fingerprint, checkpoint, and file identity) are readable while locked; collection rows and images are not in those metadata files. |
| F1 / N5 — no-provider price result | `PriceLookup.hasObservation` controls persistence: `.unavailable(nil)` is never stored as a provider observation. Fallback eligibility is separate: scanner, Browse, and automatic refresh callers pass `identifiedCatalogCard: true` when a catalog identity exists, so an identified Pokémon/Magic card with no catalog quote may still reach JustTCG when fallback is enabled. The eventual vendor result is persisted only when it carries an observation. Browse keeps its fallback call behind this shared identity-aware rule and avoids saving an empty context or reporting a false price-save failure. | Regression coverage distinguishes no-observation persistence from identity-aware fallback eligibility. Acceptance: skipped `.unavailable(nil)` catalog data leaves no price record and remains immediately eligible on the next automatic pass because `lastCheckedAt == nil`. Fallback remains user opt-in and consumes the shared JustTCG budget. |
| F2 / refresh eligibility | Automatic `.noSupportedProvider` stamps for raw and graded cards use the same 30-day retry interval while fallback is enabled; with fallback disabled they are not retried automatically. Manual `forceUnsupportedRetry` bypasses the interval. A never-checked row remains immediately eligible. Rows with no price **or** missing artwork retry immediately when `lastCheckedAt == nil`, otherwise after eight hours. Include `usesPriceFallback` in monitor observation and the target fingerprint; persist the observed preference and reset coalescing on change. If enabling fallback meets an active same-collection pass, retain the forced retry and start it after that pass using a fresh collection fingerprint; forced retry bypasses target deduplication. Accepted delay: there is no eight-hour wake timer; a row crossing the threshold mid-session becomes eligible at the next launch, store/save observation, or relevant preference change. | Boundary tests cover provider-negative 30-day behavior, missing artwork, immediate never-checked eligibility, and the retry latch. Same-collection live-toggle timing remains a device/runtime acceptance check. |
| N6 — normalizer retry loop | Scan/Browse catalog rows retain `catalogProviderID`. If that ID exists, require exact provider-ID agreement and fill only missing fields. If a row has no catalog ID but already has a real provider ID equal to the result, also fill only missing fields. A synthetic `csv:` row uses full canonical metadata after the importer resolver successfully matches it, so its imported set label is normalized. Missing rarity alone is not unresolved after exact catalog identity exists; missing image or catalog identity remains actionable. | Tests pass for exact Pokémon-row enrichment, known-field preservation, synthetic-CSV set canonicalization, and missing-rarity eligibility. |
| F4 — save notifications | Deliver both `ModelContext.didSave` and `NSPersistentStoreRemoteChange` through `RunLoop.main` before changing SwiftUI-observed generations. This is a prerequisite to moving deletion off-main because the save observer uses `object: nil` and will see model-actor saves. | Source compiles in the successful affected-suite build. There is no direct callback-thread assertion yet; keep any notification integration check separate from the actor delete test. |
| N7 — bulk import/delete | App-scoped `DerivedStateWriteCoordinator` owns CSV progress and result/export data after Settings is dismissed. It grants one exclusive import or delete token and refuses either operation while the other is active; keep the existing shared write-depth gate as an additional guard. When Settings opens from Scan, pause recognition and release the scanner session's long-lived bulk interval; reacquire it on dismissal. Disable the Done action and interactive dismissal while an exclusive operation is active. `CollectionDeletionModelActor` deletes off the UI context, checks the storage-generation continuation before each position and before its single commit, and rolls back on invalidation. | Focused scanner-to-Settings coverage passes for both exclusive operations; the existing delete-all ledger/history test runs through the model actor. Import throughput at 1,000/5,000 rows and dismiss/reopen behavior remain to measure manually. UTF-8-only CSV parsing is unchanged. |
| N4 — public links | Release build settings for privacy/support URLs remain empty until the owner provides the actual deployed destinations. Settings now says each link is unavailable in this build instead of claiming it is configured. | **Open release blocker / owner input.** Do not publish guessed or undeployed URLs. |
| N8/N9 — measurement and provider migration | Centering PNG export, first-use treatment-catalog decode, Activity Log main-thread reload, portfolio replay cost, and 1,000/5,000-row CSV import remain measurement-gated. The Pokémon TCG API's own [documentation](https://docs.pokemontcg.io/) says existing keys continue through 2027-03-01 and directs integrators to migrate to Scrydex. Keep migration, a separate Magic signing key, and non-UTF-8 CSV support on the release backlog. | No code change in this slice. Recheck the provider timeline and gather measurements before scheduling these changes. |

Implementation order: (1) supply live N4 privacy/support URLs; (2) N1 proof retention and duplicate interaction; (3) F1/N5 shared no-observation pricing rule; (4) N6 exact-identity, fill-only normalization; (5) N2.1 account-probe removal with conservative `.notQueried` policy; (6) N2.2 same-process container reuse as a separate slice after probe removal; (7) F2 refresh eligibility; (8) N3 locked-background metadata protection and privacy disclosure; (9) F4 main-run-loop notification delivery; (10) N7 mutually exclusive bulk import/delete; (11) measure before N8/N9 changes. N4 cannot close until the owner supplies deployed destinations. Keep the release candidate uncertified until device, provider, full-suite, archive, and URL evidence is recorded against the exact candidate.

## Pass-2 F01–F03 remediation — 2026-09-19

The three requested pass-2 findings are now addressed in the committed tree:

- [x] F01 — an unproven restoration source is now an explicit policy input.
  Fresh and unsafe-to-recreate iCloud paths stay on-device, failed restoration
  exposes **Keep on This Device**, and the manifest is not changed to
  `.attached` until affirmative readiness.
- [x] F02 — headless container construction now takes the manifest-derived
  `CollectionStorageMode`; `.neverAttached` and `.suspended` production paths
  request `.onDevice`, and headless installation updates the app's active mode.
- [x] F03 — pending scanner answers are retained until the resolution task is
  accepted. A busy pipeline reports a recoverable problem and leaves the answer
  available for retry; the regression test covers the interleaving directly.

Focused evidence on the iPhone 17 Pro iOS 26.5 simulator is 64 storage,
policy, and continuity tests passing in both Debug and DebugProduction (the
DebugProduction run has one intentional entitlement-gated skip), 20 readiness
tests passing, and the new F03 regression passing. This is source and simulator
evidence only; RF-7 still requires the entitled-device and clean-install/
background-refresh checks below.

## Historical baseline — `fix/app-review-preflight`

- Branch: `fix/app-review-preflight`
- Baseline commit: `a115e4e`
- Baseline source checks: Debug/Release source typechecks, simulator app-module
  and XCTest-source typechecks, CloudKit source audit, plist validation, and
  `git diff --check` passed before this remediation pass.
- Baseline runtime: the full Debug suite executed 1,205 tests with 45 known
  failures before this remediation; physical-device verification remains
  unavailable.

## Remediation buckets

- [ ] Storage architecture and local-only disclosure — Blocker — the production
  factory now keeps `.onDevice` proof-gated and uses explicit CloudKit versus
  local-only configurations; Task 4B/device proof still required
- [ ] Manifest/store-file identity and path validation — Blocker — source hardening
  now distinguishes a completely absent replica from orphaned journals and
  identity corruption, rejects unsafe replacement paths, rotates the physical
  store identity at physical store replacement before container construction;
  readiness authority remains checkpoint-only and failed path resolution stays
  fail-closed; runtime execution still required
- [ ] Confirmed anchor claim ordering — Blocker — source ordering and orchestration
  tests applied; claim readback now also rejects unsupported anchor format or
  missing generation before container construction; runtime execution still
  required
- [ ] Restoration observability and continuity suites — Blocker — cached empty
  checkpoints can no longer authorize startup, populated checkpoints are
  explicitly last-known/non-authoritative, and checkpoints require the current
  anchor generation; the production readiness mechanism remains deliberately
  unproven
- [ ] Fresh-process background storage preflight — High — headless preflight now
  validates the current anchor, exact generation, store identity tuple, and
  replica URL before construction and returns without constructing a
  non-authoritative container while the G4 readiness gate is unproven; an
  active process session is reused without rotating the generation, while
  suspended/transitioning sessions skip safely; runtime execution still required
- [ ] Magic treatment migration generation fencing — High — token propagation,
  cancellation, rollback, and gate invalidation applied; runtime execution still required
- [ ] Ownership-ledger production-entry matrix — High/specification gap — disk-backed
  production-entry/restart/rollback coverage added; full matrix execution still required
- [x] Screenshot tooling bundle identifier — High — default corrected to
  `com.seankeller.CardScanner`

## C1–C4 review follow-up

- [x] C1 — forced restoration now binds a replacement identity to the sidecar
  and manifest before CloudKit container construction; the readiness checkpoint
  remains the only readiness authority. A failed remote adoption is covered by
  a relaunch regression test and retries restoration instead of entering the
  identity-metadata support block.
- [x] C2 — headless preflight retains anchor/generation/identity/path checks but
  returns before constructing a non-authoritative production container. The
  populated-checkpoint continuity test asserts `makeCount == 0`.
- [x] C3 — the replica-state fixture now models an explicitly missing sidecar,
  and the test target's Debug configuration matches the app's
  `LOCAL_ONLY_SIGNING` condition. Release remains the no-flag production-path
  compile configuration. No-flag XCTest coverage remains a follow-up because
  Release does not enable `ENABLE_TESTABILITY`; add a `DebugProduction`
  configuration with testability enabled and without `LOCAL_ONLY_SIGNING`,
  without changing the shipping Release configuration.
- [x] C4 — dependency defaults for anchor reads are now `.unknown`, preserving
  fail-closed behavior when a caller omits the dependency.

Current focused verification is `PASS` for 64 storage/policy/continuity tests
in Debug, the same 64 tests in DebugProduction with one intentional skip, 20
`CloudRestorationReadinessTests`, and the new pending-resolution regression.
The older 59-test count is retained only in historical notes elsewhere; it is
not the current evidence count.

## Historical verification snapshot — pre-current-checkout

The following storage-remediation run belongs to the earlier candidate and is
retained for implementation evidence only; it is not the current full-suite
result:

`EXECUTED — 1,205 tests; 45 failures at baseline, 43 with these fixes.` The
remaining 43 were classified as pre-existing and unrelated:
centering-corpus/fixture failures, source-path tests that resolve relative to
`/` under `xcodebuild`, a `CollectionSyncDiagnostics` date-encoding mismatch,
and two tracked `OwnershipLedgerCompletenessTests` assertions. The storage
suites have zero failures. No commit hash is claimed until the owner requests
or approves a commit containing the complete working tree.

The latest complete full-suite result is recorded in the [current release
ledger](docs/release/phase-1-integrity-evidence.md): the historical `a4375df`
run executed 1,277 tests with 6 skipped and 40 failures. No full suite has been
rerun at current candidate `7dbaf40`.

## Verification and rollback

Each bucket will be source-checked before the next bucket is advanced. No
destructive commands or broad worktree reset are permitted. Rollback is by
targeted patch only; release evidence must name the exact candidate it covers.
