# 2026-10-31 — Card sharing post-merge artwork recovery

Follow-up on `fix/card-share-artwork-recovery` from `main@3053218`.
[PR #6](https://github.com/Razorback2424/CardScanner/pull/6) merged at 15:41:17
UTC after its 15:37 draft state was reported. Its manual acceptance gates now
apply to main. Review correctly identified that the original `e503728` export
guard stranded items without artwork; the old guard-only test did not prove a
usable sharing flow.

Both sheets now render the facts without artwork during missing, slow or failed
loads. Share stays available, Retry is offered when there is a source, and late
results cannot replace a newer attempt. The renderer accepts only the actual
view; tests no longer supply unrelated artwork to bypass a guard. Ordinary
personal-photo proportions are preserved from 1:3 through 3:1; more extreme
photos use a centered crop and proportional corners. The asking field has equal
accessibility insets and intrinsic height. DEBUG review artwork is generated
locally rather than fetched from a provider.

The final Debug selection passes **33 tests, zero failures/skips**: 17 logic,
eight render/recovery and eight detail-render cases. It covers empty sources,
suspended loading, failure, retry, superseded results and extreme aspect ratios.
Twenty-three exported fixtures were inspected. SE captures show an enabled
Share without artwork and a readable accessibility3 failure/Retry row; a row
compression found during the loop was repaired and recaptured. The final Release
build passes on the arm64 iPhone 16 / iOS 27 simulator with Xcode 27.1 and
`ONLY_ACTIVE_ARCH=YES`. No fresh full suite is claimed; the initial
full-run counts below are historical.

Evidence stays on the external SSD. Native Share/Retry/Close with actual missing
images or networking off, extreme-photo acceptance, saved-file parity, keyboard
interactions, spoken VoiceOver and physical-phone destinations remain manual.
The current [handoff](docs/plans/card_sharing_handoff.md) distinguishes the
reviewed main regression, follow-up evidence and those owner checks.

# 2026-10-31 — Preserve saved feed prices during rollover outages

Follow-up to review of `21e6ec1`, based on clean `main@17658c9`. A still-valid
Pokémon feed snapshot remains available when a newer build cannot be downloaded,
including ordinary backoff and manual retry. Its quote and validation dates and
disk bytes stay unchanged; failed-request backoff remains active. Expired data
and cancellation still fail, and incomplete new files are never accepted.

Both new outage regressions failed before the fix. The post-fix feed suite passed
**50 tests, zero failures/skips**. Five new cases cover known-build outages,
marker outages, lagging publication files, expiry during a request and shared
cancelled/non-cancelled waiters. The expanded feed/pricing/quote-cache selection
passed **171 tests, zero failures/skips**. The Release simulator build and final
**50/50** feed-suite rerun passed, including the deterministic in-flight expiry
check. Diff whitespace and added local links pass validation. See the
[fix plan](app_review_fix_plan.md). The source/test fix is committed as
`2b31f0d`. This is recorded-response simulator evidence, not live-provider or
device acceptance.

# 2026-10-31 — Card sharing — initial Mac verification

Historical checkpoint: the original artwork guard below introduced a missing-art
dead end, and unlimited personal-photo proportions could become thin strips.
The post-merge follow-up above supersedes those behavior claims. The recorded
initial build/test counts are unchanged; manual gates were not closed by merge.

On `claude/card-share-sheet`, a Share button on collection card details and on
the Price Check result replaces screenshots with a rendered 1080 × 1350 image
plus the same facts as plain text. Collection shares (pulls and trades) have one
choice, Price on/off, remembered across shares; the user's own photo is used
when present, and a raw price is labelled with the provider's condition, never
the copy's. Price-check shares add an optional asking price and a 3-month trend
that is omitted below five observations or two weeks of history; graded checks
send no chart. Logic is in `CardShareContent.swift` with
`CardShareContentTests`; views are in `CardShareViews.swift`.

Mac verification merged committed `main@17658c9` through `f1ff681`, preserving
the original checkout's unrelated uncommitted work. Final Debug and Release
builds pass on the arm64 iPhone 16 / iOS 27 simulator with Xcode 27.1; Release
used `ONLY_ACTIVE_ARCH=YES`. No project-reference or original logic-test fixes
were required. `CardShareContentTests` passes **17/17**; four added export tests
and eight detail-render regressions bring the focused run to **29/29**, including
the final post-fix rerun.

The full sharing regression has **2,780 passed, 16 skipped and six failed**;
clean main has **2,758 passed, 16 skipped and seven failed**. Every branch
failure also occurs on main: **zero new failures**. The six shared failures
cover collection/graded identity assertions, three local-StoreKit cases and
SwiftData notification keys. Main's additional app-opening timeout passed on
the branch. This is not a green full suite.

Verification repaired placeholder-image export after failed artwork loading,
cropping of unusually wide/tall personal photos, and a reproduced accessibility
text truncation in the asking-price row. Fifteen 1080 × 1350 export fixtures
were inspected; iPhone SE and iPad captures cover both sheets, accessibility3
control rows, light surroundings and German currency formatting. The full
regression preceded the final control-row layout repair; final builds, the
29-test rerun and recaptured rows cover that repair. Artifacts remain on the
external SSD; no screenshots or raw logs are committed.

Native Save Image/preview parity, Price persistence, actual asking-price input
and keyboard dismissal, real collection/scan cases, spoken VoiceOver and
physical-phone share destinations remain manual. Catalog-detail and sealed-browse
entry points are not wired yet. The evidence and remaining checklist are in
[`docs/plans/card_sharing_handoff.md`](docs/plans/card_sharing_handoff.md).

# 2026-10-31 — High-confidence production review fixes

Remediation based on clean `main@36c2a64`, split into four focused commits:
`c1798ca` (graded finish correction claims), `8229bc6` (retry and unavailable
states), `21e6ec1` (feed publication rollover recovery), and `21c75ff`
(resolved-identity pricing diagnostics).
Graded finish correction now respects acquisition quantities, reuses the
existing split/ledger transaction, preserves another slab's shared vendor
quote and previously recorded history, and explains partial corrections in
detail. Added split/merge, bound-quote, print-run, rollback, undo and historical
acquisition coverage; CSV reopen/round-trip coverage includes a partial correction.

Missing artwork now ends in an unavailable state in Price Check and scan review.
Graded discovery retries transient/incomplete results in place, ignores
cancellation, and removes unused summary state. The resolved-identity pricing
explanation is reachable without treating an unsupported finish or raw identity
as sufficient graded pricing evidence. Daily-feed rollover recovery has one
bounded marker refresh and retains exact-file validation and original quote dates.

The focused baseline passed 168 tests; the original correction/rollover/diagnostic
regressions reproduced their failures before fixes. The combined signed iOS 27
simulator selection passed **764 tests, zero failures, one opt-in performance
benchmark skipped**. Hosted unavailable-artwork rendering passed at standard and
accessibility text sizes. An unsigned Keychain test-host failure was resolved by
signed-simulator verification. The final 45-test feed suite also passed, including
manual retry with a fresh cache and invalidation of cached sets after observing
a newer publication. The final Release simulator rebuild passed, with no new
compiler warning messages relative to the earlier Release build; see the
[fix plan](app_review_fix_plan.md). Diff whitespace and added local links pass.

DerivedData is on the external SSD. Activity/CSV optimizations remain
measurement-gated. Privacy/support publication remains owner-deferred; no URLs,
feed activation, One Piece production gate or CloudKit policy was changed.
These checks do not certify physical-device, live-provider, distribution or
release readiness.

# 2026-10-31 — Refinement follow-up closed

Steps 1–4 are complete on `refinement/review-followup-2026-10-31` at
`5344635`. A direct remote check confirms that branch is pushed; `origin/main`
was at `ade96f1` when the closeout was first published, before the requested
main integration. The branch was pushed directly without a PR.

The [closeout ledger](docs/audits/production-refinement-master-review-2026-10-26.md#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes)
records shipped-code verification, both accuracy fixes and their reproduced
regressions, and reconciled docs. Existing Mac artifacts confirm the final
selection: **808 passed, eight skipped, zero failed**, with a passing Release
build. This closeout adds no code or fresh test run. Physical index creation
after upgrade, cross-device backdated coverage and owner-device/release gates
remain open; earlier S6-reverted/S7-pending entries are historical.

# 2026-10-31 — Refinement follow-up verification

On `refinement/review-followup-2026-10-31` from `ade96f1`, Debug, Release and
ReleaseLocal simulator builds pass; Release omits the owner One Piece catalog.
The initial second S6 gate run failed a live-network-dependent lifecycle test.
Test-only `9453ea5` supplies its existing fixture override and awaits queue
completion. Both full S6 repetitions then pass: 120 passed, one skipped each.
The shipped catalog-alias suites pass 87/87; storage/replay has 100 passed and
one skipped; expanded S2 has 499 passed and six skipped, with no failures.

The exact pre-index 1,500 × 365 benchmark writes a scan price in 51.261084 ms,
over the 50 ms gate; the indexed main product measures 29.578375 ms. The
in-place simulator upgrade retains every semantic collection, price, ledger
and Portfolio row and its store identity. Physical index creation on that
upgraded store is not established: its two local tables still list no indexes.
A second in-place upgrade preserves a three-point chart disk cache and displays
the same +$10 / +100% without chart injection. Synthetic-ID price refresh
reports prices unavailable; these checks do not establish live-provider success.

`3241304` fixes catalog quotes leaking into owned history after a later refresh;
`408e439` widens coverage for newly recorded backdated inventory events. Both
new regressions fail against main production logic and pass after their fixes.
Their expanded selections pass 159 with one skipped and 274 with one skipped,
respectively, with no failures.
Post-fix newest-close coverage reads take 0.021548084 s versus 1.021585834 s for
the full 300 × 365 window. The final combined selection at `408e439` executes
816 cases: **808 passed, eight skipped, zero failed**.
The final Release rebuild also passes and still omits the owner catalog.

See the [dated verification and accuracy fixes](docs/audits/production-refinement-master-review-2026-10-26.md#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes)
for the original failure, counts, benchmark comparison, upgrade limits and the
known cross-device coverage residual. No PR or main merge was made. Device,
provider, CloudKit, archive and release gates remain open.

# 2026-10-30 — Indexed price history and resolved catalog pricing

The aged-store 1,500-instrument × 365-day scan-write benchmark exceeded the
owner-approved 50 ms gate. Added SwiftData indexes for daily price checks and
price observations, and raised the app and test deployment targets to iOS 18.
The [Lorcana production acceptance ledger](docs/release/lorcana-production-acceptance.md)
distinguishes this source update from the earlier archived build; no new archive
or distribution package is certified.

Normalized Pokémon CSV holdings keep their local ownership identity. Raw
Pokémon rows can now read through an exact catalog price only when finish and
print run match; an owned quote or withdrawal takes precedence. Collection
snapshots follow the selected price key, portfolio replay preserves earlier
shared quotes only until an owned quote or withdrawal, and an open additions
breakdown refreshes prices learned during the same selected period. Regression
coverage was added for these paths and same-period refresh. This entry's
unverified status is superseded by the dated 2026-10-31 verification above.

# 2026-10-30 — High-confidence review fixes

Follow-up based on `db318a8`, committed as `00942d9`, `6813f22` and `4d420ab`,
preserving the existing sale/trade work:
closed the certified-card restore/reacquisition loophole; aligned raw history
correction eligibility with the writer's remaining-quantity check and explained
the partial-claim restriction; moved metadata application to the existing
background model actor with fresh-context serialization and generation checks.

Undo uses the actual removal/history timestamp and expires in Collection and
Portfolio. The timestamp is optional snapshot JSON, retaining older decoding
and pre-ledger restoration. Removed the unused photo-workflow state and the
now-unused history card index. No new actor, dependency or SwiftData model field.

Baseline: 111 focused tests passed. Both new regressions reproduced the old
certificate duplication/main-actor blocking before the fixes. Final Debug
simulator verification: **208 passed, zero failures/skips** (202 ownership,
normalization, ledger, item-kind, schema and digest tests plus six cross-game
and construction/workflow checks). Existing compiler diagnostics remain.
Artifacts are on the external volume under
`CodexBuilds/TradingCardScannerReviewFixes-20261030/`; the initial full-T7 build
failure was superseded by the passing baseline on the other external volume.

See the [implementation ledger](docs/plans/october-refinement-implementation-plan.md).
Graded-refresh scheduling, measurement-only performance work and gated production
URL activation remain deferred. No physical-device, live-provider, CloudKit,
rendered UI, archive or release acceptance is claimed. No deployment was made.

# 2026-10-29 — Saved-card artwork and price-history identity repair

At `44b1831`, fixed Collection grid/detail artwork
requests that omitted the catalog identity required by the existing Classic
fallback. The wider sweep repaired the same omission in Portfolio thumbnails,
historical addition tiles with retained snapshots and Browse's owned-card fan.
Resolved IDs survive imported ownership keys. Extended the existing reviewed
artwork join to all 196 products across 30th Celebration, Classic Collection
and eight Mega Evolution Energy cards; no schema migration or re-import.

History now uses those reviewed product/finish identities and all 90 Trick or
Trade mappings ahead of stale original-release handles. Corrected cache keys
bypass unrelated earlier misses, and a modern Unlimited marker does not trigger
a redundant name search. Exact product, English/raw/USD, Near Mint and finish
checks remain required. No provider history is synthesized from a current quote
and no portfolio accounting history is rewritten.

The initial simulator selection passed 154/154. Final expanded selections
executed 326 cases: 320 passed, six Lorcana live/candidate opt-ins skipped,
zero failures. The six Yu-Gi-Oh! history controls were run by their actual test
class separately. Build data/results are on the external SSD under
`CodexBuilds/TradingCardScannerMVP_fixed_v4/collection-detail-redesign/DerivedData/Logs/Test/`;
final result names end in `18-05-27--0600.xcresult` and
`18-09-12--0600.xcresult`. Existing compiler/platform diagnostics remain;
this is not a warning-free or full-target claim.

All 196 reviewed full-size image endpoints returned HTTP 200/image MIME on
HEAD checks. Misty and Crobat G downloads also decoded and visually retained
the anniversary stamp. The bundled sweep found 844 rows without stored image
URLs; 653 have an existing allowed derived path and 191 need separate source
verification. Those counts include variant/print-run slots and are not a live
missing-card census. See the [artwork authority](docs/plans/artwork-fallback-plan.md)
and [history authority](docs/plans/price_history_chart_plan.md). No authenticated
history, physical-device installation, provider-wide, CloudKit or release
acceptance is claimed. The implementation and tests are committed through
`9aeeff4`.

# 2026-10-29 — Launch-speed branch native verification

Fetched and checked out `claude/launch-speed` at `c557499`, preserving the
existing listing-photo work. Corrected only the One Piece concurrency fixture's
server capture timestamps so an older delayed feed cannot masquerade as a newer
capture. The dedicated iPhone 17 / iOS 27.0 simulator selection passed all 186
launch/catalog/ownership/migration tests with zero failures/skips/runtime warnings.
Earlier shared-simulator attempts were superseded because concurrent photo UI
launches terminated the test host.

The full test target completed with 2,693 passed, six failed and 16 skipped.
Two StoreKit product-loading failures passed in isolation; interrupted-purchase
acceptance skipped because local StoreKit granted an entitlement early, leaving
sandbox follow-up open. Collection-key, graded-grouping and SwiftData
notification-key assertions still failed. Eight
full-run warnings concern SwiftUI State/Environment access in unhosted test views.
The full target remains failed. Release device code compiled with signing
disabled; normal signing failed on missing iCloud provisioning entitlements.
Device installation, collection changes and first/repeat launch measurements
were not performed. See [RF-1](docs/plans/release_followups.md) for the precise
failures, external evidence location and remaining device workload/signing gates.

# 2026-10-29 — Daily price delivery implementation (in progress)

Removed app requests to upstream TCGCSV across the shared product source and
Pokémon service. Default transports use the configured app-owned HTTPS feed,
block redirects/upstream URLs, and require a consistent daily build and original
server capture date. Missing, future, mixed and 24-hour-old metadata cannot
create current observations. Existing cached/saved values retain their dates.
Added the YGO daily source with dated bundle recovery for offline acquisition;
fresh null lanes and identity/cancellation errors cannot borrow another edition.

Prepared a scoped static publisher and full-site restoration contract using the
existing hosting path. The YGO candidate job reuses its exact raw capture, with
start/end build markers; other groups are fetched once per build. Sixteen Python
publisher/restoration cases passed, hosting cache validation passed, and YAML and
shell syntax checks passed. Initial native checks proved endpoint denial and
provenance preservation; the two-class run had 62 passes, six expected opt-in
skips and one outdated malformed-feed error expectation. That expectation is now
aligned with the new provider-rejection contract and its focused rerun passed.
Final native selections are still running. Logs/results now resolve to external
SSDs through the verified build-storage links.

The production feed endpoint remains empty. Uncached feed-backed prices in this
intermediate build require approved publication/readback and activation before
release. No deployment, workflow dispatch, credentials, signing or production
catalog activation occurred. See the [finding ledger](docs/audits/feature-completeness-review-2026-10-29.md)
for the exact scope and remaining gates. Graded support and other catalog/release
gaps remain open.

# 2026-10-29 — External build storage verification

Paused implementation at the owner's instruction and checked build/test/cache
locations before continuing. Verified 39,737 files / 12,983,327,216 bytes during
the content-hashed relocation of XcodeBuildMCP workspaces, Node tooling caches,
Python caches and Swift generated sources. Existing/concurrent moves of the
default Xcode DerivedData, archives, products, IDE cache and repository artifacts
were rechecked. All 16 inspected artifact/cache paths resolve onto T7 or Keller
Family Photos, both reported as external solid-state volumes. Compatibility
symlinks retain tool paths; DerivedData, compiler module caches and SourcePackages
remain external. The relocation report is outside the repository at
`/Volumes/Keller Family Photos/CodexBuilds/TradingCardScannerMVP_fixed_v4/InternalBuildStorage-20261029/relocation-report.json`.
Updated generated-path ignore rules so external links cannot be staged as source.
Source files and concurrent Browse changes were preserved. Apple-managed simulator
runtime installation is separate from these build/cache locations.

# 2026-10-29 — Feature completeness remediation (in progress)

Repaired normal-runtime Lorcana raw history by resolving the discovery wrapper's
reviewed physical registry. Three focused native tests passed, including catalog
and collection requests sharing the exact listing cache, unsupported finishes,
withdrawal, and existing remapping/in-flight checks. The research-runtime test
remains a separate control. Magic now retains expired validated modern metadata
for provider outages without renewing its price age; all 22 content-kind tests
pass, including reopened 90-day-old data, unseen-card refusal and identity
rejection. Initial offline failures were corrected and the whole focused class
rerun. README now states the first-use/token/historical offline boundaries.

Pricing Settings now explains the actual JustTCG features, the gap-filling
toggle and key recovery. Storage Settings explains CSV's recovery limits.
Standard and accessibility-size Settings captures were inspected, including
scrolling and final captures. The isolated Debug/local routes wait for view
appearance; initial fixed-delay captures had shown startup. Saved-key rendering
and save/remove interaction remain unverified because secure-field automation
did not change the input. No credential was saved. See
[the checklist](references/pricing_settings_success_checklist.md).

The final broader run passed 54 tests with six explicit opt-in/workspace skips;
the separate actual `YuGiOhMarketHistoryTests` class passed all six tests.
An earlier selection naming its source file instead of class discovered none
of those cases and is not counted. History now applies the same exact raw
English/USD/condition/printing uniqueness filter to Lorcana/One Piece/YGO;
the normal Lorcana fixture rejects earlier foreign and graded rows. Logs,
xcresults and screenshots are on the external SSD. Provider
access, graded expansion, data coverage and owner-controlled distribution gates
remain open; no deployment, purchase, credential change or release certification
is implied. See the [finding ledger](docs/audits/feature-completeness-review-2026-10-29.md).

# 2026-10-29 — Cross-game feature completeness review

Completed a source/data capability pass against clean base `b03a74f`; the
[dated matrix and findings](docs/audits/feature-completeness-review-2026-10-29.md)
separate a newly identified normal-app Lorcana raw-history mapping defect and
TCGCSV device-access, Magic offline, graded-action and
provider-setup issues from previously recorded Lorcana/One Piece/release gaps.
Recomputed the Lorcana payload: 3,582 discovery rows, 1,749 physical records in
sets 1–8, 1,460 discovery rows in sets 9–14 and 3,364 physical mapping lanes.
Seven read-only data/configuration assertions passed. A temporary native
characterization and existing control both passed, reproducing that normal
Lorcana registration loses a reviewed raw-history mapping while the research
runtime resolves it. The normal service throws `noListing` before HTTP; the
passes characterize the defect, not feature acceptance. Evidence and the
reproduction patch are retained on the external SSD. The temporary test was
removed afterward; no application/test source, credentials, collection data,
publication, device or release settings remain changed. No live pricing
coverage is claimed. Updated the document
map/audit so the capability gaps remain visible across later reviews.

# 2026-10-28 — Refinement review implementation

Validated and implemented the eight code findings from the comprehensive review:
edition pseudo-finishes cannot be newly saved by finish correction; unknown
finishes retain truthful labels; the first revision baseline reconciles same-count
ownership edits; shared market-history fetches cancel when their last consumer
leaves; saved Pokémon/Magic slabs reload exact catalog finish alternatives;
listing-photo tasks/files survive temporary inspection and reset correctly on
exit; Browse directories publish independently with stale-response guards; and
Portfolio period controls scale and reflow with 44-point minimum targets.

Regression source covers identity/ledger preservation, model/projection labels,
same-count launch edits, history consumers and quota, exact slab alternatives,
shared-file lifetime, independent directory publication, cancellation and retries.
A DEBUG-only `ListingPhotos` route generates its own pixels for private-media-free
inspection. Existing source changes and untracked files were preserved.

Implementation is complete. The final signed Debug selection ran 472 cases:
470 passed, one failed and one skipped. All nine new regressions passed. The
existing StoreKit purchase test failed with the simulator's "No transactions in
response" error, then passed in isolation using the same compiled test products.
The existing interrupted-purchase case skipped under its SDK/runtime guard; the
combined run is not represented as fully green. Debug compilation passed, and the
optimized ReleaseLocal simulator build's native log ended with `BUILD SUCCEEDED`
after the plugin's five-minute response timeout. Both build products and result
bundles use `/Volumes/T7/CodexBuild/TradingCardScanner-Refinement/` (plugin-managed
test product copies/logs also live in its standard workspace).

Inspected Portfolio period controls at normal and largest accessibility text
sizes: the latter uses two columns with readable labels. The synthetic listing
fixture opened its full-screen inspector and returned to ten prepared outputs
with Export still available. Automatic approval review blocked photo-picker
inspection because it could expose unrelated personal media; the generated-only
route supplied the safe alternative. A 326-file source/project hash snapshot
matched before and after final verification. Documentation links and diff
whitespace checks passed. This is scoped simulator evidence, not a full suite,
physical-device, live-provider, archive or release certification.

The owner explicitly kept privacy/support publication and URL configuration
deferred. Device latency, real camera/Photos/AirDrop behavior and release gates
remain separate acceptance work. Shared photo exports are retained for the process
and retired by the next process's existing temporary-directory sweep; initial
store reconciliation deliberately adds one launch read/replay to protect accuracy.

# 2026-10-28 — Classic artwork repair installed and verified on the iPhone

After the owner handled Keychain signing, the normal optimized device build
completed successfully and was installed in place on the unlocked iPhone.
Source hashes match the 12-test artwork patch. Normal-launch Device Hub
observations confirmed Classic artwork for Charizard, Lugia (via local search)
and neighboring cards, with progress/finish rows present. No uninstall, seed,
collection edit or cache reset was performed. Keyboard capture/mirroring were
released. Full-size detail/global-search rendering and all 30 cards on the
phone were not individually checked; the endpoint check covers all 60 URLs.

The installed binary also includes the 15-test focus cleanup. Its unmirrored
snapshot comparison remains pending; no full hang-free acceptance claim.
See the [updated artwork report](docs/audits/classic-collection-artwork-repair-2026-10-28.md).

# 2026-10-28 — Classic Collection artwork recovery

Investigated the owner's blank Classic Browse artwork. TCGdex returned
`image: null` for Charizard/Lugia; checked Scrydex image paths returned HTTP 403.
The shared card-artwork source now appends existing reviewed exact TCGplayer
product images for Pokémon / `30th-c`, preserving original URLs first. Browse
tiles, global card search and catalog detail supply exact card/set identities;
names or repeated printed numbers never select a product. Unknown IDs and
wrong-game/wrong-set contexts remain excluded. No identity, finish, price,
ownership, scanner, schema or cache-policy change; no data/cache reset.

All 60 thumbnail/full-size endpoints for the 30 reviewed cards returned
HTTP 200/image MIME. Charizard and Lugia were visually checked for the 30th
anniversary artwork. Optimized native verification passed **12 tests**, zero
failures/skips and no finalized runtime warnings. The normal device build
compiled through linking but is waiting on a protected macOS Keychain signing
prompt. The owner was asked to handle it; installation and phone rendering
remain pending. The older signing build was interrupted so this binary also
contains the already tested search-focus cleanup; its snapshot comparison
remains open. No commit, push or release acceptance.

See the [artwork recovery report](docs/audits/classic-collection-artwork-repair-2026-10-28.md).
Build/test results, public artwork samples and endpoint/source hashes remain
outside the repository on T7.

# 2026-10-28 — Browse keyboard/layout repair and direct typing evidence

Removed unused full-screen viewport observation on iOS 18+ while preserving
the iOS 17 pagination fallback. Reserved the native search clear target so
first/last-character edits do not resize the input. Installed that optimized
layout patch in place. The owner typed directly on the phone with mirroring
off and reported smooth behavior. The 73.92-second trace captured 29 off-main
projections at 0.205–0.856 ms (median 0.244 ms), with no detected typing hang.
It still captured 478.61 ms initial app/Collection layout and 451.16 ms
background snapshot stalls; no first-entry marker was exported in this run.

Added native focus cleanup on resign-active before background snapshotting,
preserving the query. Final optimized verification passed 15 tests, zero
failures/skips and no finalized runtime warnings, including a new hosted
input-width/focus/query-retention regression. The device rebuild compiled
through linking but is waiting on a macOS Keychain signing prompt. The protected
security window cannot be automated; the owner was asked to handle it and unlock
the iPhone. Focus-cleanup installation and snapshot comparison remain pending;
full hang-free acceptance remains open. No collection/cache reset was used.

See the [focused remediation evidence](docs/audits/browse-performance-repair-2026-10-28.md#keyboard-and-snapshot-remediation--2026-10-28).
Raw traces, hashes and build/test results remain on T7 outside the repository.
No commit, push or release acceptance.

# 2026-10-28 — Browse repair installed and profiled on the physical iPhone

Built normal signed ReleaseLocal (`-O`, whole-module, no DEBUG fixture flags)
and updated ScanStash in place on iPhone 15 Pro Max / iOS 27.0.1. Source hashes
match the previously tested repair; app/dSYM UUIDs match. Application source
remained unchanged. No collection reset, uninstall or cache-clear command was
performed. All 616 existing cache and 174 Application Support entries survived the
installation. Ordinary use then added/evicted artwork and HTTP cache entries
under unchanged policies; all Application Support entries remained present.

The 160.51-second physical trace covered Collection → Browse → Pokémon → Sets
→ Destined Rivals, initial empty query, incremental/rapid typing, clearing and
Back/reopen. First-usable markers were **131.00 / 120.63 ms**; ten nonempty
typing projections were **0.236–0.843 ms**, median **0.334 ms**, all off-main.
Rendered results/progress/finish rows and clearing/reopening were checked.
Normal launch additionally confirmed a final nonmatching character produces
the empty result, then clearing restores the full set. App remains open there.

Hangs detected **two microhangs**: **260.16 ms** in keyboard setup before the
set opened, and **334.45 ms** in snapshot/SwiftUI layout after rapid typing.
Neither overlaps entry or query-worker intervals. Matching-symbol CPU evidence
does not isolate automation from ordinary UIKit/render costs; full hang-free
acceptance remains open. A 120-second follow-up captured another **132.15 ms**
entry and no hangs but no card typing because Device Hub did not expose the
software keyboard. It is not accepted as a clean typing run. Instruments attach
lookup failed; launch-under-recording worked. No pre-patch device speedup claim.

Detailed scoped evidence and limits are in the
[Browse report](docs/audits/browse-performance-repair-2026-10-28.md#physical-device-follow-up--2026-10-28).
Raw trace/metadata/build artifacts remain on T7 under
`CodexBuild/TradingCardScanner-BrowseDeviceEvidence/`, outside the repository.
No commit, push, merge or release acceptance.

# 2026-10-28 — Focused Browse entry and local-search performance repair

Started on `main` at the supplied baseline `e92db19`; preserved existing
documentation edits. Set presentation now prepares normalized text, number keys
and grouping identities once per changed snapshot, filters retained ordering on
an actor and rejects obsolete/canceled publications. Search remains immediate.
Directory fallback uses prepared ownership buckets; completion prepares each
available game without waiting for unrelated catalogs and invalidates stale
ownership/tier/catalog results. Provider pacing/concurrency, image loading,
price batching, writers, persistence schema and catalog authority are retained.

Optimized iPhone 17 / iOS 27.0 hosted fixtures: Destined Rivals first empty-query
projection **4.49 → 2.54 ms**, typing median **1.73 → 0.246 ms**. Twelve requests
now use one preparation/ascending sort and ten projections. The frozen original
directory fallback took **5.71 seconds** for 2,000 synthetic rows / 60 sets
(120,000 row visits); prepared lookup took **0.46 ms**, after a **105 ms** complete
ownership-index build on the existing background projection boundary in production.
These are fixture costs, not physical-device/frame-delivery speedup claims.

Final native verification: **37 focused + 5 existing shared-ownership cases
passed**, zero failures/skips; both finalized summaries have no runtime warnings.
Includes hosted navigation/scroll/pagination/reappearance, stale results, same-count
catalog replacement, ownership/tier/price changes, finish grouping, exact cross-game
membership and a delayed/failed unrelated directory. Plain ReleaseLocal could not
compile the existing DEBUG-only test seams; accepted runs retain ReleaseLocal `-O`
optimization with those seams enabled. The baseline MCP response timed out, but
its completed passing result was recovered. Final verification used direct
xcodebuild logging on the T7 SSD. `git diff --check` and changed-document link
checks pass. Full evidence and remaining limits are in the
[Browse repair report](docs/audits/browse-performance-repair-2026-10-28.md).

The discoverable physical iPhone required unlocking, so no device install/trace
or hang acceptance is claimed. History projection, the M08 first-baseline
same-count gap and other profiling candidates remain separate. No commit,
push, merge, publication or whole-app/release acceptance.

# 2026-10-27 — M07 first slice: usable graded finish correction actions

Fix finish now appears only when the existing resolver supplies a different
valid finish ID. The Printed finish label and saved value (including Not
determined) remain visible for the same eligible acquisitions. The menu excludes
the current finish, and its explanatory copy appears only with the action.
Existing reviewed pattern/stamped/printing alternatives, pending-write guard,
accessibility label and correction writer remain. No global finish list,
catalog fetch, state/model refactor or persistence policy change was added.

Three new regressions cover ordinary Pokémon/Magic known/unknown finishes,
reviewed singleton/multiple alternatives, pattern/stamped supplements and the
separate print-run axis. The bounded Debug iPhone 17 / iOS 27.0 Simulator
selection passed **124 tests, zero failures/skips**: three new M07 tests, two
existing supplemental-options tests, all 43 CollectionItemKind and all 76
CollectionActivityHistory tests. Existing correction/binding/quantity/Undo and
authorization regressions are reused. The finalized summary has no runtime
warnings or test failures. Visibility and retained finish text are source-checked;
these native tests exercise the exact option helper used by the view.

Tested source/test revision: `e92db193be32024304de5cf24cdc8017b69ed3f6`.
Work began on clean `54af5ec`; after interruption the same implementation/tests
were already committed in `e92db19`, with a clean worktree. That commit was
preserved; this resumed pass made no commit or push. Its patch from `54af5ec`
matches `final-tested.patch` SHA-256
`0ad5ae96318eb9cf79bb6c63ab2445a6459973ea82ebfcc0cdc40cae7358a9c0`.
The first build failed before tests because the outer detail facade did not
yet forward the new helper; corrected before the next build. The next run
compiled and began tests, then was interrupted without a finalized bundle.
The final `xcodebuild test-without-building` reused that build and the same
bounded selection, with serial execution and a 120-second per-test limit;
exit 0. No incomplete run is counted as passing evidence.

External SSD evidence:
`/Volumes/Keller Family Photos/CodexBuildArtifacts/TradingCardScannerM01/M07-first-slice/`.
`resumed-focused.log` contains the exact invocation and per-case results;
`resumed-focused.xcresult`, `resumed-summary.json` and `final-tested.patch` retain
the accepted evidence. The same root's earlier `focused` and `final-focused`
artifacts preserve the build failure and interrupted run. Derived data remains
in the sibling `DerivedData` directory; temporary run data stays on the SSD.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md#m07-graded-finish-correction-often-offers-no-correction)
and documentation audit. Source HIG gate: PASS, no source issues identified;
native controls/system text remain, no prompt/tap added, and misleading no-op
actions removed. Broader catalog-backed alternative discovery is deferred.
Rendered phone/tablet, Dynamic Type/VoiceOver, physical-device, live-provider,
CloudKit, full-suite, archive and release acceptance remain unverified.
M08 and later findings are unchanged.

# 2026-10-27 — PR #5 focused verification of review follow-ups

Source review of `019ca6f`..`c091381` found three follow-ups. After M01, a
certless scanned slab never rewrites an existing holding's finish (exact match
or new holding), but the scanner/raw-conversion preflight still requested the
price-identity gate whenever a same-grade certless row had a different finish,
cancelling an active price refresh for an ordinary insert. The preflight now
flags only an unknown-finish refinement, and unbound certless scans skip it;
the in-write retry remains authoritative. History's loading flag no longer
sticks when storage is not ready, and the now-unused sealed promotion
preflight is removed. The original store-level regression is retained.

Verified branch `claude/review-followups-2026-10-27`, tested base
`7a72ff8f499aa29da27fbe68686f5f29a3e8ae6a`, plus the verification (then uncommitted)
patch SHA-256 `31bf929e4809a4e419526ae4fb1d28a1f547f15fbb8798004cc72377b49e9748`.
Started from clean `main` at `c0913819c5450f8da1a8a6adc1bfda8573df2633`;
GitHub PR head matched the requested reviewed head before checkout. No unrelated
work was changed; no commit, push or merge was performed during verification.

Two new refresh regressions directly call both changed ScannerCollectionWriter
preflight overloads for unbound certless scans and raw conversions, each with
an existing unknown or different finish. With ownership enforcement enabled,
preflight is false and the write succeeds in one attempt without an identity
permit. Both holdings retain distinct keys/finishes, one copy each, no vendor or
certificate binding, correct ledger quantities and valid activity lineage; raw
conversion leaves no raw copy. The shared refresh controller remains in flight
through each write and its paused stub fetch completes once without replay or
preemption. The refresh uses a separate in-memory fixture store; this is not an
end-to-end scanner UI or live-provider cancellation claim. Existing bound/
certified repair and stale-preflight retry coverage was reused.

Extracted only the History loading/token wrapper into its existing read-state
type, retaining the view's read/error handling. Two new regressions prove a
missing token clears loading before work runs, and an obsolete cancelled request
cannot clear a newer active request's loading flag; the newer request clears its
own flag. This tests the same wrapper used by the view, without a view-model
refactor or rendered UI acceptance.

Final Debug iPhone 17 / iOS 27.0 Simulator result: **251 passed, zero failed,
zero skipped** (43 CollectionItemKind, 76 CollectionActivityHistory, 126
ScannerViewModel, 6 selected PriceRefreshLifecycle). Finalized xcresult summary
has no runtime warnings or test failures. Unchanged test-target compiler
warnings and App Intents metadata notices remain. The first invocation was
interrupted (exit 75) after the new fixture seeded outside the required
serializer and asserted. After that fixture correction, the same selection
passed, but its synthetic refresh row logged a missing-ledger diagnostic.
Seeding that row through the production acquisition path removed the diagnostic;
the final complete selection passed again (exit 0). These were related fixture
corrections only; all three invocations reused the same SSD build and selection.

External SSD evidence root:
`/Volumes/Keller Family Photos/CodexBuildArtifacts/TradingCardScannerM01/PR5-20261027/`.
`accepted-focused.xcresult`, `accepted-focused.log`, `accepted-summary.json`,
`accepted-tested.patch`, its SHA-256 file and `verification-command.sh` preserve
the final evidence; earlier logs/results/patches are retained separately.
The exact test invocation in that script was:

```sh
pr5_root='/Volumes/Keller Family Photos/CodexBuildArtifacts/TradingCardScannerM01'
pr5_run="$pr5_root/PR5-20261027"
TMPDIR="$pr5_run/tmp" xcodebuild test \
  -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug \
  -destination 'platform=iOS Simulator,id=A23ECC25-0B75-4735-B26F-491044CDAF28' \
  -derivedDataPath "$pr5_root/DerivedData" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "$pr5_run/accepted-focused.xcresult" \
  -only-testing:TradingCardScannerTests/CollectionItemKindTests \
  -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests \
  -only-testing:TradingCardScannerTests/ScannerViewModelTests \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testStaleIdentityPreflightRetriesOnceInsideAuthorizedGate \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testAddGradedUsesPermitForUnboundSlabIdentityRewrite \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testAddScannedGradedUsesPermitForVariantIdentityRewrite \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testAddSealedUsesPermitForUnboundIdentityPromotion \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testUnboundCertlessScanPreflightPreservesActiveRefreshAndOwnership \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests/testCertlessRawConversionPreflightPreservesActiveRefreshAndOwnership \
  > "$pr5_run/accepted-focused.log" 2>&1
```

Also inspected the finalized bundle with `xcrun xcresulttool get test-results
summary --path <evidence-root>/accepted-focused.xcresult` and ran
`git diff --check`. Simulator/stub and focused-suite evidence only: no physical
device, provider, CloudKit, full-app audit, archive or release acceptance.

# 2026-10-27 — M06 collection owned-game filter choices

Three native regressions reproduced the Game picker offering only Pokémon and
Magic despite held Lorcana, Yu-Gi-Oh!, One Piece and a retained unknown identity.
The picker now receives unique owned games from the full collection snapshot,
only while presented, independent of search, item-kind and selected-game filters.
Existing identity descriptors determine stable order/labels; retained unknown IDs
remain selectable with their raw labels. If a last holding disappears, the current
game remains a valid selection until changed or cleared. No browse, pricing or
collection-write capability enabled; no fetch, task, model or cache added.

All three focused regressions pass. They cover mixed/retained identities,
empty/subset collections, stable order/labels, exact query results/copy counts,
selection retention/clearing and the real picker binding's game-scoped resets.
Set/finish/treatment clear on a game change; same-game selection and all other
filters retain their behavior. Expanded verification on iPhone 17 / iOS 27.0
Simulator: **124 passed, zero failed/skipped** (46 CollectionQuery, 42
CollectionItemKind, 36 BrowseCollection). Finalized summaries contain no runtime
warnings. Evidence is on the external SSD under
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M06-*`.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md#m06-collection-game-filter-omits-owned-games),
documentation map and audit. Source HIG gate passes; rendered phone/tablet
sheet/inspector and VoiceOver acceptance remain unverified. No device/provider/
CloudKit/full-suite/release acceptance claimed. M07 and later findings unchanged.

# 2026-10-27 — M05 opening readiness hold removed

Reproduced the actual hosted opening container waiting about 444 ms on fast
readiness and 757 ms after a slower load. Removed the pre-reveal sleep and two
unused hold constants. Handoff now starts at readiness, retaining the existing
fade/scale, Reduce Motion reveal, post-reveal settling, loading/restoration gates
and recovery/session-reset behavior. No new production API, state or abstraction.

Added two hosted regression cases: fast/slow handoff within 100 ms with reveal
completion, and cancellation of old settling on phase reset plus blocked-startup
recovery exposure. All nine focused opening tests pass. Fixed readiness-to-handoff
was about 32 ms fast / under 1 ms slow in that run. Expanded verification on
iPhone 17 / iOS 27.0 Simulator selected 69 opening/storage-bootstrap/storage-policy/
launch-executor cases: **68 passed, zero failed, one skipped**. The skipped
data-protection test requires a locked physical device. Expanded hosted timings
were about 1.5 ms fast / 0.7 ms slow. Finalized summaries contain no runtime warnings.
The first new fixture build tried to override a read-only SwiftUI environment
value; corrected before accepted baseline evidence. Evidence is on the external
SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/M05-*`.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md#m05-opening-handoff-adds-waiting-after-readiness),
documentation map and audit. Source HIG gate passes; visual/VoiceOver/native
Reduce Motion and Release-device cold/warm interaction acceptance remain
unverified. Simulator handoff measurements do not certify total launch latency,
touch delivery or release readiness. No later finding changed.

# 2026-10-27 — M04 reviewed UI ownership scope completed locally

Finished sealed add/Undo, Browse release-order backfill and Portfolio quantity
repair using the existing background writer and fresh serialized transactions.
The caller sweep additionally moved CSV-import and collection-delete exclusive
lock acquisition off the UI thread while retaining same-task authorization and
the existing token barrier. Pending feedback, repeat-action guards, cancellation
and storage-generation checks protect current UI state. Backfill preserves price
lineage; repair refuses mixed/stale defects without changing owned quantities.
Removed redundant sealed preflight branches; no schema or new actor added.

The native legacy characterization reproduced five blocking paths at about
510–632 ms under a forced 500 ms hold. Seven focused regressions pass, covering
responsive heartbeats, durable results, lineage, exact Undo, real promotion,
stale repair refusal and canceled/retired exclusive-session cleanup. Expanded
verification on iPhone 17 / iOS 27.0 Simulator selected 616 cases: **615 passed,
zero failed, one existing opt-in benchmark skipped**. Finalized result summaries
contain no runtime warnings. Includes all 74 history, 42 item-kind and 36
BrowseCollection cases, executor, hosted detail/deletion, artwork, CSV resume,
ownership stress and earlier pricing/scanner/refresh selections. The initial
sealed fixture build omitted required `imageURL: nil`; corrected before the
accepted baseline. Evidence remains on the external SSD under
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-completion-*`.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md#m04-completion-and-caller-sweep--2026-10-27),
documentation map and audit. No further named M04 UI action implementation slice
remains; earlier open-slice entries below are historical. Broader automatic
catalog/normalization, Magic migration, portfolio epoch and shared price/cache
service transactions remain outside this UI ownership repair and are not
certified as nonblocking. Source HIG gate passes; Release-device latency,
rendered pending/back/Cancel/VoiceOver, provider/CloudKit/full-suite/release
acceptance remain unverified. Later findings were not implemented.

# 2026-10-27 — M04 graded-picker acquisition writes

Reproduced the confirmation's synchronous write blocking a queued main-thread
heartbeat for about 669 ms under forced 500 ms contention. One method on the
existing scanner writer/private executor now runs the unchanged store add,
listing price, promotion, certificate and lineage work off-main. Value inputs
and a mutation receipt cross the boundary; post-lock cancellation/storage checks
reject queued obsolete work. The main-actor optimistic promotion preflight and
duplicate gate branches are removed; the existing in-write permit and same-task
retry remain authoritative. The real promotion test requires two attempts and
preserves one physical copy/acquisition with migrated lineage.

The confirmation's save task is view-owned so departure cancels queued work;
already-started transactions remain atomic. Pending progress/certificate pause
preserve navigation and the immediate repeat-tap guard. Canceled/retired results
do not call the success/dismiss callback. Selected-listing pricing, including an
explicit listing with unrecorded physical finish, stays distinct from M02's
automatic binding rules. No store/provider policy, new actor or schema added;
production code size is unchanged while UI coordination is simpler.

All five focused native tests pass. Expanded verification on iPhone 17 / iOS 27.0
Simulator selected 609 cases: 608 passed, zero failed, one existing opt-in
benchmark skipped; finalized summary inspected with no runtime warnings. Includes
all 42 item-kind, 67 history and 36 BrowseCollection cases, both executor tests,
hosted detail/deletion, artwork, ownership stress and earlier M01–M04 selections.
Evidence is on the external SSD under
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-graded-picker-*`.
Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md)
and documentation map/audit. HIG source gate passes; rendered pending/back/Cancel/
VoiceOver, ordinary device latency and provider/release gates remain unverified.
M04 stays open for sealed acquisition, Browse release-order backfill and Portfolio
quantity repair; no later finding implemented.

# 2026-10-27 — M04 catalog/raw acquisition writes

Reproduced blocked main-thread heartbeats in raw catalog add, acquisition Undo
and catalog-price checkpoint under a forced 500 ms lock hold (about 524–647 ms).
These transactions now extend the existing scanner writer and private executor.
Catalog details/resolution/print run cross as values; the fresh transaction stages
and saves the acquisition with its actual stored price identity before returning
a receipt. Imported aliases, source/provenance, finish/edition and lineage stay
intact. Post-lock cancellation/storage checks reject queued obsolete work.
Ownership and price remain separate: price failure returns the durable receipt
and warning rather than retrying acquisition. Initial and callback quote
checkpoints run on the worker; shared fallback resolver identity-cache work is
unchanged. Pending UI pauses overlapping add/Undo and starts the six-second Undo
window after the receipt, retaining navigation and mutation-matched completion.

All eight final focused native tests pass, including failed final save rollback,
exact/repeated Undo, intentional copies, imported alias price identity, editions,
invalid quote rollback, post-commit price failure, stale quote provenance and
queued lifecycle invalidation for all three methods. Initial fixture builds
needed the required source-variant string. The first focused run exposed a wrong
non-USD rejection assumption; the fixture now uses a negative USD amount. A
separate native red test caught a freshness regression in the first worker
version; the accepted version mirrors checkpoint replay's actual-write-time
comparison while retaining the quote's original retrieval time. Neither provider
currency support nor the original checkpoint freshness policy was changed.

Expanded native verification on iPhone 17 / iOS 27.0 Simulator selected 604 cases:
603 passed, zero failed, one existing opt-in benchmark skipped. Finalized summary
inspected with no runtime warnings. Includes all 67 history and 36 BrowseCollection
cases, three earlier artwork cases, both executor tests, seven hosted detail/
deletion cases, ownership stress and previous M01–M04 selections. The catalog
detail view no longer calls the synchronous serializer or saves price contexts
directly. Evidence is on the external SSD under
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-catalog-raw-*`.
Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md)
and documentation map/audit. Source HIG gate passes; rendered pending-state/VoiceOver,
ordinary device latency and provider/release gates remain unverified. M04 stays
open for graded/sealed additions, Browse release-order backfill and Portfolio
quantity repair; no later finding implemented.

# 2026-10-27 — M04 detail artwork/metadata writes

Reproduced all four synchronous transaction shapes blocking queued main-thread
heartbeats for about 507–538 ms under forced 500 ms contention. Moved photo
normalization/file creation and artwork mapping/removal, graded finish correction,
and marketplace persistence to the existing detail writer's dedicated executor.
Fresh metadata/claim/lineage checks, shared-file references, retained-game local
suppression and the task-bound identity gate remain. File cleanup belongs to the
worker: pre-commit failure removes the minted file; cancellation after commit
cannot delete referenced artwork. The current mapping is read inside the
transaction, rather than captured by the UI before waiting. User actions reuse
pending controls with a native toolbar spinner; navigation remains available.

The first focused run caught a new graded-ledger test assumption and reproduced
a repeated-finish no-op Debug assertion. The exported crash stack points at the
repeat call: read-through identity repair dirties the context, then the current
finish returns no mutation. The detail worker explicitly rolls back that no-op
context. The corrected test verifies the existing graded behavior: one quantity
event, one correction activity, unchanged quantity, no repeated mutation. Real
graded authorization traverses the existing retry gate in the same task.

All six focused cases pass. Expanded native verification on iPhone 17 / iOS 27.0
Simulator selected 557 cases: 556 passed, zero failed, one existing opt-in
benchmark skipped; finalized summary inspected with no runtime warnings. Includes
all 59 history cases, both executor tests, seven hosted detail/deletion cases,
ownership stress, refresh structural races and all earlier M01–M04 selections.
Three extra artwork selectors initially used the file name instead of their
actual XCTest class; the corrected separate prepared-build run passed all three
with zero failures/skips or runtime warnings in its finalized summary. Evidence is on the
external SSD under `CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-detail-metadata-*`.
Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md)
and documentation map/audit. No synchronous serializer calls remain in the detail
view. M04 remains open for catalog/raw, graded-picker, sealed acquisition and
Portfolio quantity-repair writes; no later finding implemented. Source HIG gate
passes; rendered pending-state/VoiceOver, PhotosUI/device memory, ordinary
Release-device latency and release gates remain unverified.

# 2026-10-27 — M04 undo-banner restoration

Reproduced the synchronous Collection/Portfolio undo sequence blocking a queued
main-thread heartbeat for about 518 ms under a forced 500 ms lock hold. Both
banners now await a snapshot-restore overload on the existing background activity
writer. Store validation, durable snapshot authority, ledger inversion and the
same-task identity gate stay intact. Pending spinner/controls prevent repeat
taps; matching removal IDs and storage-generation checks prevent an older result
from clearing a newer banner or surfacing against retired storage.

Five focused native tests pass. Expanded verification on iPhone 17 / iOS 27.0
Simulator selected 551 cases: 550 passed, zero failed, one existing opt-in
benchmark skipped. Finalized summary inspected with no runtime warnings. Includes
all 53 history cases, both executor tests, seven hosted detail/deletion tests and
earlier M01–M04 selections. Evidence is on the external SSD under
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-undo-*`.
The first focused build caught an immutable-field error in the new fixture;
the corrected fixture uses the snapshot's mutable finish and verifies the stored
finish wins. Production behavior was not changed to accommodate that error.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md)
and documentation map/audit. M04 remains open for detail artwork/metadata, catalog
and picker writes. HIG source gate passes; pending-state rendering, VoiceOver,
ordinary Release-device latency and release gates remain unverified. No later
finding implemented.

# 2026-10-27 — M04 activity/history writes

Reproduced backfill, removal, restoration and correction blocking queued
main-thread heartbeats under a forced 500 ms lock hold (about 517–526 ms per
old sequence). Moved these four transactions to a history model actor using the
existing dedicated executor, serializer and task-bound identity gate. Capture
claim quantities before suspension; retain fresh lineage checks and durable
outcomes. The editor receives a value-only correction/fallback receipt built on
the context owner. Pending/retry state pauses conflicting actions, rejects
superseded reload completions and surfaces backfill failures while retaining the
last complete snapshot. No synchronous serializer calls remain in the history
view. Read/projection work remains the separate measure-first P06 item.

The first five focused tests pass. Final expanded prepared-build verification on
iPhone 17 / iOS 27.0 Simulator selected 547 cases: 546 passed, zero failed, one
existing opt-in aged-store benchmark skipped. Includes all six new history cases,
49 history tests total, 51 fallback tests, queued storage-retirement coverage,
both executor tests and earlier M01–M04 selections. The first expanded run's sole
assertion failure required accepting either existing duplicate-restore refusal;
the unchanged ledger is explicitly checked. A subsequent runner startup channel
disconnect and simulator-launch wait recovered without shared resets or source
changes; the final retry passed. Evidence is on the external SSD in
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-history-*.xcresult` / `.log`.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md),
documentation map and audit. M04 remains open for undo-banner, detail artwork/
metadata, catalog and picker writes. Source HIG gate passes the bounded native
pending/error feedback; rendered history pending-state/VoiceOver and Release-device
latency remain unverified. No later findings implemented or release gates closed.

# 2026-10-26 — M04 detail ownership write slice

Demonstrated the old detail serializer/store sequence blocking a queued
main-thread heartbeat under a forced 500 ms ownership-lock hold; native baseline
reported mainThread=true, heartbeatDuringLock=false and about 515 ms elapsed.
Moved detail quantity/removal to the existing dedicated background-model-actor
pattern, preserving fresh-context transactions and task-bound identity retries.
The UI prevents overlapping actions and shows pending feedback; removal publishes
its receipt/dismissal after commit. Queued removal also validates the confirmed
quantity, and cancellation/retired-storage work is fenced after lock acquisition.
No global serializer or lock-policy change.

Five focused tests pass for heartbeat responsiveness, off-main execution, one
mutation, stale/repeated-action rejection, cancellation/storage fences,
task-bound authorization, and removal/undo. Expanded Debug iPhone 17 / iOS 27.0
Simulator verification selected 490 cases: 489 passed, zero failed, one existing
opt-in aged-store benchmark skipped. Includes all M01–M03 selections, both
executor tests, seven detail rendering/deletion cases, structural refresh races
and ownership stress. Finalized summaries inspected; evidence is on the external
SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/M04-*.xcresult` / `.log`.

Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md),
documentation map and audit. M04 remains **partially repaired**: activity/history,
undo-banner, artwork/metadata, catalog and picker synchronous writes still need
independent slices. Source HIG gate passes the bounded pending-feedback change;
pending-state screenshot/VoiceOver and ordinary Release-device measurements remain
open. No later findings implemented, no full-suite/device/release acceptance claimed.

# 2026-10-26 — M03 CSV price interpretation

Reproduced `€12.50` importing as USD 12.50 and `12,50` as USD 1,250,
including incorrect persisted observations and ledger valuation. The four-test
before-fix selection had three defect tests fail and the supported-format control
pass. Changed only CollectionCSV.swift: accept one supported Market Price header
and strict US-style USD amounts, preserve valid zero/fractional/date evidence,
reject foreign/malformed values and competing/duplicate price columns, and keep
valid inventory rows without those prices. No conversion, persistence migration,
or historical price/history cleanup. Re-importing the same inventory is still
idempotent and does not correct past values.

All four focused regressions pass. Expanded Debug iPhone 17 / iOS 27.0 Simulator
verification selected 470 cases: 469 passed, zero failed, one existing opt-in
aged-store benchmark skipped. This includes import/resume, portfolio
reconciliation and all M01/M02 selections. Finalized native summaries inspected;
evidence is on the external SSD in
`CodexBuildArtifacts/TradingCardScannerM01/Evidence/M03-*.xcresult` and `.log`.
Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md),
documentation map and audit. No later findings implemented; no full-suite,
live-provider, physical-device or release acceptance claimed.

# 2026-10-26 — M02 unknown-finish graded pricing

Reproduced unknown slabs acquiring vendor bindings and $123 quotes, unknown
Price Check publishing a quote, and a catalog Holo singleton accepting a Normal
listing. The bounded two-file production fix requires finish evidence for new
automatic bindings, carries catalog singleton evidence through matching, skips
unknown unbound vendor refresh, and rejects missing/conflicting printing before
durable binding. Existing exact listing handles remain refreshable. No schema
change or historical binding/price cleanup; stored data cannot distinguish an
explicit selection from an old inferred binding.

Six focused regressions pass. Final expanded Debug simulator verification on
iPhone 17 / iOS 27.0: 318 passed, zero failed/skipped, including all 126 scanner
tests and all six M01 regressions. Initial expanded failures exposed scanner
fixtures that omitted printing or expected unknown-finish pricing; their
reconciled cases now verify no quote until confirmation, correction/recheck,
delayed binding, and incompatible-price replacement. Evidence/results are on
the external SSD in `CodexBuildArtifacts/TradingCardScannerM01/Evidence/`.
Updated the [master report](docs/audits/production-refinement-master-review-2026-10-26.md),
documentation map and audit. No later findings implemented; no full-suite,
live-provider, device or release acceptance claimed.

# 2026-10-26 — M01 scanned graded finish collision

Demonstrated Normal + Reverse + Normal merging into one quantity-3 Normal slab
holding with a focused failing regression. Changed only CollectionStore's scanned
certificate-less path: match current physical identity including finish, retain
existing keys/history, and allocate a separate holding key when an incompatible
row occupies the old key. No schema migration or automatic repair of previously
merged quantities. Six new regressions pass for Pokémon/Magic, unknown/legacy
finishes, correction, binding, certificate refinement, undo/restore, on-disk
reopen and CSV; final standalone selection confirms six passed, zero failed or
skipped. Expanded simulator run: 123 passed / 124, zero skipped. The sole
sealed-product metadata assertion reproduces in cached pre-fix test products;
it remains unchanged. Updated the
[master report](docs/audits/production-refinement-master-review-2026-10-26.md)
with exact scope/evidence. Other findings were not implemented; no full-suite or
device/release acceptance claimed. Build data and expanded evidence use the
external SSD.

# 2026-10-26 — Production refinement review reconciliation

Reconciled the earlier ten-finding chat review and supplied nine-finding review
against clean `028b135`. The
[master report](docs/audits/production-refinement-master-review-2026-10-26.md)
accounts for every original finding once, prioritizes graded identity/valuation
and CSV correctness, merges the main-thread removal issue, and separates
measurement/reproduction work from validated source behavior. Unsupported
performance estimates and unsafe simplifications are explicitly not adopted.
Updated the documentation map and authority audit. Production code and tests
were not changed; no fresh native tests, profiling, provider or release
acceptance is claimed. Documentation links and diff validation are recorded in
the handoff.

# 2026-10-25 — Magic publication failure investigation

Inspected run 40191118826 on `main` at `9c73abe`. Core/fixture validation and
live candidate preparation passed; publication preflight found all five
required signing/Firebase variables empty and stopped before signing/deploying.
Read-only inspection confirmed no repository or Magic production secrets,
no Magic production protection rules, and no automatic Magic environment.
Firebase secret names exist only in the Pokémon production environment; their
values cannot be retrieved from GitHub. The hosted Magic pointer returned 404
and the config still uses the temporary Pokémon public pin. Updated the
[runbook](docs/plans/magic_catalog_key_handling_runbook.md#publication-failure-and-recovery--2026-10-25)
with exact provisioning, protection, pin replacement and fresh-run recovery
steps, and reconciled the documented setup with actual GitHub state. No keys,
workflow guards, environment settings, rollout or deployment were changed.
Resolution requires owner-held credentials and the dedicated Magic key/pin.

# 2026-10-24 — Finish-aware Magic raw product identity

Continued the systematic audit on `30a56af` plus preserved local changes.
Found the raw fallback, market history and marketplace-link paths still used
the ordinary Scryfall product for etched copies with a separate product ID.
Shared finish-aware selection now supplies all raw/graded paths and links saved
when adding or refreshing owned rows. Unknown finishes cannot choose between
distinct products; legacy Normal retains nonfoil semantics. All **40 H1R pairs**
pass raw/history/link projections and graded HTTP replays. Focused native
verification: **311 passed, zero failed**. All **15 Python tests**, both Magic
proofs, both Pokémon proofs and the whole installed mapping replay pass; census
and ledger hashes are unchanged. No saved holdings, signed catalogs, keys,
rollout flags or deployments were modified by this audit run. Live authenticated
graded coverage remains unverified. See the
[current audit](docs/research/set-pricing-audit.md#direct-magic-printing-identity).

# 2026-10-24 — Yellow A physical finish reconciliation

Continued on `30a56af` plus preserved local changes. Reviewed all six generated
Normal Yellow A records against the complete vendor group and price lanes.
Four EX cards are Holofoil; both trainers have separate Normal/Holofoil products.
Added all eight exact products to the reviewed raw/graded identity route,
corrected variant choices, exact marketplace links and printed totals, and
kept provider/local identifiers stable. Scoped padding preserves letter suffixes
and stated denominators. Bundled/old offline Browse checklists project the
correct eight physical slots and counts without rewriting source files or
fingerprints; the upgrade/cache tests pass in a **76-test** follow-up.
Conflicting detailed quotes and stale Normal EX Price
Check references cannot override reviewed physical identity; no cached data or
holdings are rewritten. Scans require a known finish when the catalog is
ambiguous, and Price Check forwards confirmed finish/edition evidence. Native
validation: **356 broad tests passed**, plus later **190 pipeline** and **39 cache
review** checks, zero failed. All 15 Python tests and both Pokémon/Magic source
projections pass. The reviewed Pokémon scope is now 39 cards/41 products.
Best of remains open: all nine detailed sources establish 15 standard products
and eight excluded jumbo objects, retained for stamp provenance work. No signed
catalog, key, rollout, deployment or collection changes. See the
[current audit](docs/research/set-pricing-audit.md#yellow-a-finish-reconciliation).

# 2026-10-24 — Reviewed Pokémon subset graded identities

Continued on `30a56af` plus preserved local changes. Independently captured every
detailed Unown Collection and Futsal card: all 33 have one standard English
unstamped Holofoil object and an explicit TCGplayer product ID. Added reviewed
per-card graded identities through the shared exact-product path. Parent vendor
groups stay separate catalog namespaces; the question-mark translation is
scoped to `exu-%3F` and preserves denominators/provider IDs. Wrong letters,
metadata, finishes, languages and edition claims fail closed. All 33 mappings
pass native requests with absent and Unlimited print runs; existing raw product
extraction agrees with the same source IDs. Targeted verification: **155 passed**;
broad five-game pricing/ownership/treatment/cache selection: **339 passed**, zero
failures. All 14 Python tests, complete subset/source projection verification,
Magic proof replay, cross-game mapping replay, links and diff checks pass.
Detailed Best of samples expose stamp/jumbo provenance work; two Yellow A
samples have generated Normal metadata without product IDs, while all eight
candidate vendor finish lanes have quotes. Those remaining fixes need physical
identity reconciliation. The 463-resolved/345-unaliased name census is unchanged;
it is not a count of application lookup failures. No collection, signed catalog,
key, rollout or deployment changes. See the
[current audit](docs/research/set-pricing-audit.md#reviewed-pokémon-subset-identity)
for retained receipts and live-provider limitations.

# 2026-10-24 — Exact Magic graded product identity

Continued on `30a56af` plus preserved local changes. Added a shared exact-product
route to the graded picker, scanned resolver and owned refresh. Re-resolved
Scryfall UUID/name/set/number and English paper/finish evidence authorizes the
snake-case v2 product request; returned external product/game/source IDs must
agree. Vendor group and collector-number conventions no longer block that
verified product. Source-declared face names handle Pathway-style vendor names.
Missing source product coverage retains the strict legacy route; source outages,
ambiguity, budget and pagination failures remain distinct from vendor absence.
All 40 H1R printings retain separate ordinary/etched product IDs, and legacy
Magic Normal imports retain nonfoil semantics. Native replays cover 103 cases
across 52 families plus every H1R etched pair: 141 distinct source printings,
181 product IDs. Samples cover 42 still-unaliased directory names; they do not
certify every printing or live graded availability. Broad verification:
**335 passed, zero failed**. Subsequent compatibility follow-up: **182 passed,
zero failed**. All 13 Python tests, pinned proof projections, cross-game replay,
documentation links and diff checks pass. The name census remains 463 resolved
and 345 unaliased; its scope is explicit. No collection, signed catalog, key,
deployment or rollout changes. See the
[current audit and sample ledger](docs/research/set-pricing-audit.md#direct-magic-printing-identity).

# 2026-10-24 — Card-level set pricing audit, second pass

Continued on `30a56af` plus preserved local changes. Completed independent
product/number review of all 58 queued Magic sets with known source groups:
8,448 English paper prints across 37 vendor groups. Ten aliases passed native
whole-group uniqueness checks for all 594 source cards. A proposed Secret Lair
alias was withheld after the native proof exposed ten double-faced name
rejections. Reviewed all five remaining Pokémon catalogs (53 cards), repaired
Creator Pack/Kids WB with a five-card proof, and retained specific identity
limitations for the other four. The census now resolves 463/808 names, with
345 explicitly queued and zero directory-resolved-but-rejected cases; the
cumulative systematic regression ledger contains 61 repairs. Final focused
native selection: **186 passed, zero failed**; expanded Magic-stage selection:
309 passed, six opt-in skips, zero failed. All 12 Python audit tests pass,
including pagination, rate limits and offline receipt validation. Projection
validation added 14 omitted sealed/numberless fixture records;
the affected 31 native identity tests passed again with those records included.
Source captures and full card diagnostics remain on the external SSD; per-set
metrics, dispositions and replay input are retained in the
[current audit](docs/research/set-pricing-audit.md). No signed catalog, key,
deployment, collection or rollout changes. JustTCG graded/device coverage and
the remaining identity repairs are still open.

# 2026-10-24 — Systematic set pricing identity audit

Continued on `30a56af` plus preserved local changes. Captured all 1,443 public
vendor groups and inventoried 1,804 installed directory entries. The native
Pokémon/Magic census checks 808 distinct Browse set names: 452 now resolve,
356 remain explicitly queued, and zero resolved sets fail graded identity.
Fixed 26 redundant display-name rejections and 24 reviewed aliases/ambiguity
cases. Ten edition-decorated audit rows were corrected as projections, not
counted as application fixes. All 5,731 installed One Piece/Lorcana lanes
across 56 groups match retained live identities and have quotes. Yu-Gi-Oh's
59,965 edition memberships retain dated snapshot authority; 1,701 have no quote.
Independent GN2 card-level IDs resolve a contradictory Scryfall set-level
group field. Final focused native verification: **184 passed, zero failed**;
six Python audit tests passed. No signed catalog, key, deployment, collection
or rollout changes. JustTCG graded/device/provider-wide coverage remains open.
See the [current audit and replay workflow](docs/research/set-pricing-audit.md)
for exact denominators, source hashes, all 50 regressions and next-review order.

# 2026-10-23 — Saved Files ZIP acceptance

Continued from clean `14c1c95` with the same accepted installed Debug binary
and retained synthetic batch. Completed **Save to Files** in the local
`CardScanner-Acceptanc` folder, then opened the destination ZIP in system
Files. Files extracted `Card-01` and `Card-02`, each with ten items. Independent
CRC, exact-path, full JPEG decode and byte comparisons passed for all twenty
destination/archive and Files-extracted images against generated originals.
The destination ZIP SHA-256 remains
`fe11d996ea102dff0e8822ff0742ba5e00a3c8f90c663f4c23a34b279e28c74e`.
This closes the prior local Files handoff/reopen gap; ownership restart was
already closed. Fresh purchase/interruption reconciliation, unowned single-card
UI export, generation cancellation, TestFlight and catalog-production work
remain separate. Only evidence documents changed; no build, test rerun,
commit, push or production action. See the
[destination evidence and receipt](docs/release/five-game-launch-readiness-2026-10-23.md#files-destination-save-and-reopen--2026-10-23).

# 2026-10-23 — Bounded process-restart and photo-export acceptance

Validated clean `bb72741` against the exact supplied reviewed-delta SHA-256.
Read the relevant historical 106/106 test log; no XCTest suite was rerun.
Using the existing Debug artifact and isolated Simulator storage, verified
owned entitlement reload and centering/batch access across terminated PID
52218 → new PID 52845, without purchase/restore or ownership overrides between
those checkpoints. Prepared a synthetic two-card ZIP, presented/canceled/
reopened system sharing and verified twenty exact decodable JPEGs in the
retained temporary archive. Background/resume retained the same PID and work.
Save to Files reached its local destination view, but completed save and
reopened destination contents remain unverified because system input/AX
tooling did not complete the handoff. Fresh local purchase provenance, other
purchase/generation interruptions and unowned single-card UI export also
remain open. No product defect was isolated; only evidence documents changed.
See the [bounded acceptance record](docs/release/five-game-launch-readiness-2026-10-23.md#app-process-and-files-acceptance-follow-up--2026-10-23)
for exact limits and manual entry points. Released Lorcana coverage and approved
One Piece production setup remain next; neither was started.

# 2026-10-23 — Yu-Gi-Oh automatic-resolution verification

Re-ran the current candidate based on `1ac6750`: 457 selected iOS 27.0 Simulator
tests passed with zero failures, including catalog admission, current-authority
save validation, scanner workflows and neighboring-game regressions. The Python
builder suite passed 33 tests and its self-test passed. Results are on the
external SSD at `CardBuilds/yugioh-integration-20261023/`; no device-install or
physical-camera claim is made. See the [automatic-family evidence](docs/research/yugioh-catalog/automatic-family-verification.md).

# 2026-10-22 — Game-wide Yu-Gi-Oh! automatic resolution

Validated the supplied scanning prompt against clean `1ac6750`. Replaced the
coupled printing/edition authority assumption with release-driven family
provenance and shared acquisition resolution at recognition and final save.
Verified 260 families across MP24, Duelist Nexus and Pharaoh's Servant; every
edition-coverage flag remains unknown. Positive supported edition text can skip
both pickers, while absent text requires the edition answer. Updated Yu-Gi-Oh!
copy and isolated debug OCR routes. All-printings source coverage remains open;
this is not full automatic-scanning completion. Builder (33), local publisher
(5) and final native (119) regressions pass. The earlier lifecycle failure also
passed on both unchanged HEAD and the final implementation in isolation.
Final Simulator and generic iOS builds passed. Inspected edition-only and
positive-First injected UI captures; the explicit edition tap and automatic
one-card receipt/Undo both work. First-launch camera permission was declined;
these remain fixture/UI evidence, not physical-camera acceptance. See the
[current evidence](docs/research/yugioh-catalog/automatic-family-verification.md).

# 2026-10-22 — Validated b11fd6f sealed-history review

Confirmed the attached review's P2 against clean `b11fd6f`; both new sealed-history
tests failed against the original source. Restricted One Piece/Lorcana catalog
mapping enforcement to raw cards, preserving exact sealed vendor identities and
the existing cache format. Added both-game exact-variant fetch, persisted-cache
reuse and listing-isolation coverage. Fixed the cross-game cache assertion to
restore and confirm the cached finish before changing game.

Focused Simulator verification passed eight tests with zero failures, including
raw remap/withdrawal, graded history and existing sealed add/undo/repricing.
[Review follow-up evidence](docs/research/yugioh-catalog/audited-verification.md#sealed-history-review-follow-up-on-b11fd6f--2026-10-22-local)
records the selection and logs. This is synthetic-provider service evidence;
mixed-game Files/UI acceptance, device installation and production/release gates
remain open. The review validation run made no commit or push; this follow-up is
being recorded in separate auditability commits.

# 2026-10-23 — Focused correctness and bounded local acceptance

Working from clean base `7502144`. Quantity edits retain the count visible before
the initial async read; stale intent refreshes without saving. History cache v2
pins exact product/provider finish, resolves current catalog authority before
reading and fences completion across activation. The focused Phase A run passed
43 native tests. Phase B's initial selection passed 28 tests, including suspended
collection recovery preflight cancellation/authority replacement and active-source
pricing wording. The combined follow-up passed 79 tests, including the four-position
14-copy mixed-game CSV reopen/resume/additional-copy regression and slab guards.
A final five-test pass verified return-time history authority and final source.
These overlapping selections are not full-suite or release certification.

Screenshot loop: the initial debug pricing review overlapped its fixture controls
and timed out waiting for an OCR-only readiness marker. The second iteration fixed
the debug layout/readiness and passed visual inspection in
`/tmp/cardscanner-ui-pricing/ui-latest.png`. Bundled and synthetic approved-source
text is legible, retains October 20 capture dates and discloses unavailable live
refresh. Final tested-build capture was inspected again with the same result.
Mixed-quantity Files interaction is blocked at the system picker because the Mac
is locked; native persistence evidence does not close UI totals or Files acceptance.
The [current evidence](docs/research/yugioh-catalog/audited-verification.md#correctness-and-bounded-local-acceptance-on-7502144--2026-10-23)
records exact selections, isolated routes, unperformed steps and the prepared
owner handoff for trust/hosting, approved-parent continuity and bounded bundles.
The acceptance pass performed no rollout or owner-data reset; its evidence was
recorded before the subsequent auditability commits and push.

# 2026-10-22 — Magic publication preflight and latest review follow-up

Reviewed the latest attachment against `main` at `38fd8e6`. The actual failed
Magic job completed hosting restoration, then failed at signing; the attachment
misattributes that failure to restoration. All five signing/hosting bindings
were empty in the job. Added an early presence check and isolated subprocess
tests, wired into Magic PR validation. The owner must still diagnose secret
availability/scope before a separately authorized publication retry.

The [current evidence](docs/research/yugioh-catalog/audited-verification.md#latest-review-follow-up-on-38fd8e6--2026-10-22)
records the corrected command boundary and explicit remaining acceptance and
bounded-rollout gates. No native/UI acceptance, secret provisioning, deployment
or production delivery enablement is claimed.

# 2026-10-22 — Latest review delivery and lineage corrections

Validated the supplied 22 October review against clean `9a1d8b0`. Added signed
parent revision locators and bounded immutable-ancestor retrieval for fresh and
skipped-release clients. The offline publisher now compiles and executes the
app's complete catalog loader; hosting/workflow compilation includes that source.
Durable lineage accumulation rejects arithmetic overflow with a recoverable
error. Local regressions cover malformed catalogs, missing/mismatched ancestry,
cancellation/reopen/retry, traversal limits and persisted lineage corruption.
Final verification passed 35 focused native tests and 40 Python tests, with
zero failures. Build artifacts and compiler caches stayed on the external SSD.

Verification and protocol limits are recorded in the
[review correction evidence](docs/research/yugioh-catalog/audited-verification.md#latest-review-corrections-on-9a1d8b0--2026-10-22).
Production delivery remains disabled. Existing CSV UI, recovery-preflight,
active-source copy, provider, device, CloudKit and release gates remain open;
no deployment or owner-data reset occurred.

# 2026-10-21 — Cyclic Undo repair and local delivery checkpoint

On reviewed base `eb12b5c`, reproduced and fixed retired-edition A → B → A Undo
using exact durable inverse lineage; retained acquisition restrictions and added
tamper, duplicate, rollback/retry and reopen coverage. Implemented shared signed
approved delivery, local publisher, parent-based ingestion, hosting preservation
and atomic runtime/price/capability adoption. Production delivery remains disabled
without owner configuration. Actual Files CSV export and seven-card import into
a separate isolated store succeeded, duplicate resume offered zero remaining
entries, and reopen preserved the collection. Fixed the twice-reproduced hidden
import confirmation by attaching presentation to the persistent NavigationStack.

Final source compiled and passed 121 focused native tests; 39 Python builder,
publisher and hosting tests passed. The earlier 482-test result predates final
changes and is not added to this count. The interrupted run is not a completed
result. [Exact evidence and remaining acceptance](docs/research/yugioh-catalog/audited-verification.md#completion-checkpoint-on-eb12b5c--2026-10-21)
includes unfinished CSV variations, recovery-preflight cancellation, active-source
pricing copy, production/provider/device/CloudKit/release gates. At evidence-
capture time, these changes were local and uncommitted; no deployment or owner-
data reset occurred.

# 2026-10-21 — Generic iPhone 17 interactive follow-up

Used the owner-selected generic iPhone 17 with isolated fixture OCR and stores.
Fixed acceptance preview geometry, added deterministic initial samples/readiness,
and replaced unsupported Yu-Gi-Oh history controls with truthful snapshot copy.
Preserved concurrent residual F3/F4 source and test changes. Verified real saved
outcomes for older, alternate-art, reissue, E-code and IOC-SE records; disabled
DCR discovery choices in both pickers; explicit editions; cancellation/recovery;
duplicate protection; Browse Add; quantity edits; delete/Undo; and seven holdings
after reopen. Unknown visibly identified/added nothing. Native follow-ups passed
54 affected and 37 neighbor tests with zero failures; these overlap older gates.
Final app build succeeded. External-SSD screenshots and exact scope are in the
[interactive evidence](docs/research/yugioh-catalog/audited-verification.md#generic-iphone-17-interactive-acceptance--2026-10-21).
CSV export reached system Files, but Save could not be activated by the available
input tools; interactive export/import remains pending. Pricing is historical
bundled data. Physical camera, production delivery and release remain open.
Deployment, owner-data reset and Journey interaction were outside this
acceptance run.

# 2026-10-21 — Residual F3/F4 corrective pass at `09c4a40`

Corrected the three remaining reviewed paths: durable duplicate-row maintenance
now uses exact contributing identities and bounded logical quantity/ledger deltas;
bulk deletion uses maintenance eligibility with final validation; Needs attention
disables/explains unavailable printings, guards direct actions and checks current
catalog authority before dismissal. Isolated real-store regressions cover
duplicate remove/reduce/correct/restore, rollback/retry, mixed-game bulk deletion,
safe-sibling acquisition rejection, and persisted/legacy/stale DCR recovery.

Executed native selections: 318 passed and 196 passed, both with zero
failures/skips; these overlap and must not be summed. The unchanged builder
guard passed all 29 tests. The final five-test run also passed after the
forged-restore refinement and rebuilt the final app/test targets. F4's residual
paths are native-verified; F3 is fixed/native-verified with interactive acceptance
pending: a reported successful Don't Allow tap left the Simulator camera alert
visible in both accessibility snapshot and screenshot. No app hang is inferred.
Exact evidence is in the [residual verification record](docs/research/yugioh-catalog/audited-verification.md#residual-f3f4-corrective-pass-after-09c4a40).
Build artifacts use the external SSD and native stores use the dedicated QA
simulator. Concurrent acceptance-route changes were preserved. The verification
did not use owner data, Journey or physical devices and did not deploy.

# 2026-10-21 — Yu-Gi-Oh review corrections and local delivery seam

Candidate based on reviewed `1a3242d`; fixed F1–F7: acceptance recovery scope,
missing historical quote freshness, disabled discovery siblings/stale-family
recovery, persisted/ledger-backed maintenance, complete-review precedence,
quarantine/automatic invariants, and observable Unknown recognition diagnostic.
New Phase A gate: 425 native tests passed; Python builder: 29 passed. Earlier
47-test focused run overlaps. Local signed delivery/loader: 11 passed, followed
by 17 full-bundle delivery/maintenance checks and 133 final stale-family/scanner
checks; these selections also overlap.
App/test builds use the existing external SSD. Fixed offline rebuild is identical
to the committed seed, retaining all catalog counts/identities.

Phase B adds a local Ed25519/hash/provenance-verified consumer using the existing
two-slot store and bundled fallback, plus consistent snapshot/live-unavailable
copy. No remote YGO activation, endpoint, production trust or deployment was
added. Daily approved-parent continuity and signed publishing/restoration need
the existing publisher owner. After owner unlock, native/browser automated input
still produced no UI changes, including after restarting only the dedicated
simulator without erasing data. A manual Collection-tab check is pending;
native fixture OCR is not camera acceptance. This verification did not modify
owner data, Journey work, credentials or personal-device state. See the
[corrective evidence](docs/research/yugioh-catalog/audited-verification.md#corrective-pass-after-four-commit-review)
and [canonical plan](docs/plans/yugioh_code_implementation.md).

# 2026-10-21 — Audited Yu-Gi-Oh! exact membership integration

Candidate implementation based on `402c7655be3ad94b08986d9d1b41d9b8774db2f0`.
Implemented independent product membership/coverage/quote facts and broad explicit
selection, retaining all 46,504 original printing/canonical UUIDs and distinctions.
Offline rebuild from 1,321 hash-verified original cached inputs retains 46,542
app products: 46,303 explicit-choice eligible, 239 discovery-only, zero automatic
and zero quarantined. Across all 47,910 raw products, 932 are excluded by bounded
source metadata and 436 missing-identity records remain in the diagnostic ledger.
There are 59,965 supported edition pairs, 58,264 exact market quotes and 1,701
listing-only pairs. Unknown physical-world coverage remains unknown for all rows.

Corrected scoped RA02 taxonomy, IOC-SE1–SE4 grammar, group creation-date semantics,
image/passcode separation and canonical-ID retention when YGO rarity labels are
invalid. Existing-holding correction and final save now agree on exact supported
membership independently of family completeness. No existing-row/import bypass
was added. Browse retains discovery records with limits. YuGiOh pricing reads
dated bundled snapshots, with no direct device TCGCSV requests. Daily server
candidate ingestion/staging uses the existing Firebase namespace; no deployment
or remote activation was performed.

Verification captured on the candidate: 646 package manifest entries validated;
four offline audit commands reproduced counters; seed replay is byte-identical.
The selected native suite passed **232/232**, followed by **14/14** strengthened
changed-catalog workflow, ledger correction/delete/restore and supplemental-registry
checks. Python policy tests passed **26/26**. App/test targets built on the external
SSD. A fresh generic iOS build-for-testing also succeeded; that build-only run did
not execute tests. The boundary audit still reports 48 pre-existing lexical findings.
Interactive UI acceptance is blocked by the locked Mac: the isolated app
launches/renders but taps cannot be validated. Physical camera, provider rights,
signed hosted activation, CloudKit and release gates remain open. No owner-data
reset, physical-device installation or deployment was part of this verification.
See the [canonical plan](docs/plans/yugioh_code_implementation.md) and
[audited verification](docs/research/yugioh-catalog/audited-verification.md).

- ScanStash opening-screen rebrand (2026-10-20; merged `origin/claude/scanstash-opening-rebrand` at `ece69bc`): adopted the ScanStash display name, adaptive app and launch artwork, and matching opening view while preserving main's full-bleed status-bar handling and handoff zoom. Generic iOS Debug app and test-bundle builds succeeded on the final merged worktree. Yu-Gi-Oh! builder self-test: 14 passed. CoreSimulator was unavailable, so tests were not executed and no visual acceptance is claimed.

- Yu-Gi-Oh! merged-review repairs (2026-10-20; base `4c3e53c`, local changes):
  production runtime is unavailable while the bundled catalog has no eligible
  printings. Direct acquisition resolution now enforces incomplete-code and
  family coverage gates. Edition conflicts finish the acknowledgement/scan
  interval while preserving recovery evidence. Scan, Browse Add and CSV import
  use epoch-day release order; verified local import metadata repairs the case
  where existing artwork/catalog identity prevented later normalization.
  Builder correspondence now requires source-row coverage and evidence-backed
  mappings for differing provider labels. Final focused simulator run: 170
  passed, zero failures/skips; Python: 14 passed. Boundary audit still fails
  with 48 existing branches. No production products were approved, no seed
  was regenerated, and no real-camera or release acceptance is claimed. See
  the [review follow-up](docs/research/yugioh-catalog/review-fixes.md).

- Repository consolidation and combined build (2026-10-20; merged app tree at
  `433ebd2`): Yu-Gi-Oh app integration, reproducible catalog data, and source
  evidence were committed separately. Merged the outstanding opening-screen
  redesign and Yu-Gi-Oh plan-review branches into `main`; retained the current
  implementation authority and its reviewed predecessor under `docs/legacy/`.
  Xcode Debug app build for generic iOS succeeded with signing disabled, using
  the external build volume. CoreSimulator was unavailable in this follow-up,
  so the merged opening-screen change has no new simulator or rendered UI
  acceptance. The focused Yu-Gi-Oh simulator results remain in the dated
  [verification record](docs/research/yugioh-catalog/verification.md).

- Yu-Gi-Oh! implementation plan (2026-10-20; HEAD `06459ea`): added
  [`docs/plans/yugioh_code_implementation.md`](docs/plans/yugioh_code_implementation.md).
  It validates the external research handoff against source, live TCGCSV
  category 2 / YGOPRODeck v7 responses and local Vision OCR of five TCGplayer
  card scans. Corrections: the set code sits at card-relative y ≈ 0.24–0.28,
  not the proposed 0.28–0.45 band; RA02-EN037's rarities include Prismatic
  Ultimate/Collector's and are 1st Edition only; the shared TCGCSV lane
  whitelist rejects YGO edition subtypes. Documentation only: no code, build,
  test, device or rights evidence.

- Workflow repairs and requested device install (2026-10-20): the four source
  repair groups and their review record were committed in auditable commits and
  pushed to `origin/main`; all local branches were merged into `main`. After the
  user's keychain authorization, Xcode automatic provisioning completed a
  successful `ReleaseLocal` device build, strict signature verification passed,
  and CoreDevice installed the app over the existing app on the paired iPhone.
  It was not launched. The source-review fixes have no test-suite or post-install
  runtime evidence; the earlier 167-test result applies only to the rescan and
  scanner-prompt repairs. Build artifacts and caches remain on the external
  build volume. [Review and installation record](docs/release/workflow-source-review-2026-10-20.md).

- Review follow-up (2026-10-20; starting HEAD `0c04c63`): repaired the two
  remaining P2 edges. Certified rescans validate final finish/edition together,
  invalidate incompatible pricing and resolve it without another acquisition;
  compatible quotes and ownership accounting remain intact. Failed authorized
  additional-copy writes retain recovery intent while abandoned prompts stay
  dismissed after Price Check, subject-mode and background transitions. Four
  focused regressions pass; the final affected-suite run includes those cases
  and passes 167 tests, zero failures/skips. App/test compilation, local links
  and `git diff --check` pass. No device, provider, interactive acceptance or
  Meditite incident-causation claim; no commit or push.
  [Evidence](docs/release/verified-bug-repairs-2026-10-20.md).

- Bounded card-detail cleanup (2026-10-20; starting HEAD `e2c37ad` plus retained
  local F1–F13 work): chart-domain reuse, stable same-source image derivatives,
  one live artwork-override query, explicit manual primary-refresh intent and
  distinct source/check/failure attribution. Combined affected native suites:
  508 tests, zero failures; final focused fallback/failure checks: 5 passed;
  final image guard checks: 3 passed; app build passed. Hosted dense-chart
  layout/snapshot median was 3180.59 ms with repeated domain evaluation and
  2560.97 ms with domain reuse on the same QA simulator; no physical-device or
  incident causation claim. Existing Cards Added sealed-fixture detail opened
  cold and warm. Full delayed raw-normal UI scenario remains unexecuted.
  [Evidence and exact checks](docs/release/card-detail-cleanup-2026-10-20.md)
  distinguish those limits. Existing repairs, Collector Tools, provider policy,
  owner data and commercial scope preserved; no commits or pushes.

- F1–F13 final audited native verification (2026-10-20): 804 tests, 0 failures,
  1 unchanged opt-in performance skip. In addition to the compatible-quote F2
  regression repaired below, the F4 choice regression now covers interruption
  of held-repeat finish/print-run choices: both initially lost additional-copy
  intent. Recovery now retains that marker only for a matching consumed permit;
  native checks verify no second copy is written before fresh confirmation.
  The final run includes the distinct $250 Holo → corrected $80 Normal case and
  stable certificate/ledger quantity checks; the final app build also passes.
  Requested full interactive UI
  acceptance remains blocked/unexecuted as recorded in the
  [handoff](docs/release/verified-bug-repairs-2026-10-20.md), so the full goal is
  not marked complete. Scope and unrelated work remain preserved.

- F1–F13 continuation audit (2026-10-20): a new native case exposed a regression
  in the initial F2 repair: a compatible graded quote disappeared unless a
  second lookup succeeded. The serialized correction now returns only a proven
  compatible durable quote; incompatible identities still use the graded
  resolver. Native affected suites pass again: 803 tests, 0 failures, 1 existing
  opt-in skip. Four focused F2 cases and two final price-preservation/replacement
  cases pass, including $250 Holo → corrected $80 Normal without changing
  certificate or ownership quantity. Full requested UI acceptance remains
  incomplete for the entitlement/automation reasons in the
  [handoff](docs/release/verified-bug-repairs-2026-10-20.md); the full goal is not
  claimed complete. No commercial boundary, rollout, collection-data reset,
  commit, push or normal-device deployment changes.

- Bounded F1–F13 bug-review repairs (2026-10-20; starting HEAD `e2c37ad`, clean
  worktree): repaired recovery isolation, graded price identity/races, scanner
  lifecycle/held choices, independent restores, edition/sealed normalization,
  portfolio trust/first-price attribution and export/history edge cases. Native
  affected suites pass: 802 tests, 0 failures, 1 existing opt-in performance
  skip; two strengthened F1/F2 tests pass separately; Debug simulator app build
  passes. UI smoke is partial: Needs attention fixture renders, centering is
  entitlement-gated, system Photos picker cannot be driven by available UI
  automation, and full interactive held/graded camera flows remain unexecuted.
  See the [repair handoff](docs/release/verified-bug-repairs-2026-10-20.md) for
  finding/file/regression mapping, exact command arguments and intermediate
  failures. Collector Tools work, rollout flags and the free/paid boundary are
  preserved; no commits, pushes, purchases, normal-device deployment, collection
  resets or commercial configuration changes.

- Collector Tools one-time unlock implementation (2026-10-20; clean starting
  checkout `be183f2`): added one StoreKit 2 non-consumable, shared verified
  entitlement, explicit restore, localized-price offer, multi-card action/share
  guards and the existing guided-centering gate/output disclaimer. One-card
  output remains free in both workflows; collection/scanning/crop logic is
  unchanged. Final Debug simulator app/test-host build passes for arm64/x86_64;
  seven isolated macOS entitlement/share-state tests pass. The local
  StoreKit integration test is added; iOS StoreKit/photo/centering runtime checks
  are blocked because Xcode 27.1 needs CoreSimulator 1174.9.2 but the service is
  1171.7.0. No runtime or release acceptance is claimed. See the
  [canonical decision](docs/plans/CARDSCANNER_LAUNCH_MONETIZATION.md) for exact
  behavior, remaining checks and owner setup. No live product/account changes,
  live purchases, provider clearance, commit or push occurred.

- Launch rationale retained and commercial gaps assessed (2026-10-20): clean
  `main` at `922dc9bb3d158a599e874d4a00e85297a138b6f8`; retained the supplied
  [canonical decision](docs/plans/CARDSCANNER_LAUNCH_MONETIZATION.md), linked the
  photo plan and active planning authorities, and marked older conflicting
  commercial guidance superseded. The proposed $9.99 one-time batch offer and
  entitlement boundary await owner approval. Single/batch output is present in
  source; StoreKit and paid messaging/gating are missing. Source review only;
  no build, simulator, purchase, provider or upload acceptance ran. Runtime and
  owner gates remain open; documentation links and diff checks are recorded at
  handoff. No application code or commercial actions changed.

- Collection quote fix personal-device installation (2026-10-18; `23fd978`):
  committed and pushed the quote-consistency, history-labeling and exact
  marketplace-link fix with its documentation. After fetching all remotes,
  every other local and remote branch was already an ancestor of main; no
  additional merge was needed. The optimized, development-signed `ReleaseLocal`
  iOS build succeeded on the external SSD, and strict signature verification
  passed. Bundled One Piece owner catalog and public pins match the committed
  source byte-for-byte. CoreDevice successfully installed the update over the
  existing personal iPhone app and launched it normally, without uninstalling
  or resetting app data. Build/install/launch evidence remains external under
  `CodexBuilds/CollectionQuoteFix-20261018/`. The preceding 27 focused simulator
  tests and rendered quote/ownership checks passed. Installation and process
  launch do not establish physical-screen or live-provider price acceptance.

- Personal-device installation (2026-10-18; `75601a1`): the One Piece
  availability fix, tests and simulator evidence were committed and pushed to
  `origin/main`. Every other fetched local/remote branch was already an ancestor
  of main. The development-signed `ReleaseLocal` iOS build succeeded using the
  external SSD; the bundled owner catalog and public pins matched the committed
  source byte-for-byte. CoreDevice successfully installed the app over the
  existing personal iPhone installation. The initial launch was denied while
  the phone was locked; after the owner unlocked it, CoreDevice successfully
  launched the installed app. Visible One Piece availability remains unverified.
  The Mac's standalone strict signature check
  reported `CSSMERR_TP_NOT_TRUSTED`; the device nevertheless accepted installation.
  No production rollout or release-readiness claim is made.

- One Piece availability across local build configurations (2026-10-18): fixed
  the bundled owner runtime being excluded from `ReleaseLocal` by a Debug-only
  compilation guard. ProfileLocal can now replace Debug under the same app
  identity while retaining One Piece. Signed catalog verification, collection
  storage and production rollout settings are unchanged. The standalone
  availability regression passed against the optimized ReleaseLocal simulator
  app (1 test, zero failures), checking repeated bootstrap with fresh settings
  and scan/Browse/pricing/sealed/collection-write capabilities. The first
  full-target ReleaseLocal test attempt could not compile existing tests that
  depend on Debug-only helpers; the passing isolated run excluded other test
  sources and enabled testability. The signed Debug simulator follow-up passed
  all 91 selected cases (90 One Piece integration tests plus the availability
  regression), with zero failures. Both final runs reported `TEST SUCCEEDED`;
  build data and result bundles used the external SSD. This is simulator
  evidence; no physical-device install or production rollout was performed.
  Added documentation links and `git diff --check` pass. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- Pricing correctness before coverage expansion (2026-10-18; `56d981f` plus
  local changes): completed the Priority 1 follow-up to the committed pricing
  baseline, preserving pre-existing navigation edits. Missing marketplace
  mappings now have a distinct outcome across Browse, details, Price Check,
  collection diagnostics and refresh summaries; they neither count as provider
  failures nor fabricate observations/successful provider checks. A priced
  finish still supplies an unqualified printing's sort price when a sibling
  finish lacks a mapping. Foreign/invalid Price Check responses cannot replace
  a valid USD reference quote. Newly available exact handles and matcher
  revisions reopen obsolete search misses; successful keyed responses restore
  ordinary cooldowns. New exact adapters also supersede old raw capability
  stamps without requiring paid fallback. Signed iPhone 17 / iOS 27 regression:
  522 passed, four deliberate opt-in skips, zero failures across 526 cases;
  `TEST SUCCEEDED`, exit zero. Coverage includes pricing/transport contracts,
  Browse, source-null/mapping distinction, reference-cache and refresh recovery,
  ownership preservation, portfolio reconciliation and Collection status copy.
  The first unsigned run exposed aggregation/expectation changes and Keychain
  entitlement failures; code/tests were corrected and simulator signing restored
  the credential tests without production credential changes. Evidence:
  the external SSD under `CardScannerBuild/PricingCorrectness-20261018-Verified.xcresult`.
  No new mapping data, UUIDs, ownership/schema migration, provider deployment,
  physical-device install, commit or push. Provider-path unification, reviewed
  coverage batches, prerelease/serialized reconciliation and the complete
  census remain deferred in
  [the current execution plan](docs/plans/pricing_correctness_and_coverage.md).
  HIG source review passes; no new rendered-device/VoiceOver or release claim.
  All 195 local links in affected documentation and `git diff --check` pass.

- Performance follow-up sweep (2026-10-18; local changes over `8e882eb`):
  extended the dedicated serial model executor to the six remaining database
  workers used by scanner writes, detail quantity reads, collection deletion,
  CSV import/export and catalog-normalization inputs. Scanner startup prepares
  its writer asynchronously; writes await that session's preparation inside
  the existing tracked-write lifetime so session shutdown still drains them.
  Moved value-history, unpriced-card, missing-artwork and sync-diagnostic
  exports off the UI thread; only text/value results return to settings, with
  single-flight and storage-generation guards. Diagnostic canonical sorting
  now encodes each sort key once instead of encoding both records on every
  comparison, preserving the version-1 byte ordering. All 13 database actors
  pass background-thread probes after real reads in memory and on disk.
  Final iOS 27 simulator regression passes 349 tests, one opt-in skip and zero
  failures across 350 cases, covering scanner lifecycle/undo/corrections,
  concurrent ownership, deletion, normalization, CSV recovery/exports and
  portfolio reconciliation. The initial run exposed a missing local-artwork
  table in the new test fixture; the fixture now uses the complete schema and
  the selected suite passes on rerun. Evidence stays on the external SSD under
  `CodexBuilds/PerformanceSweep-20261018/`. Concurrent pricing-model/controller
  edits appeared after the simulator run and are outside this sweep's changes
  and test claim. The owner requested no further builds/tests. Cancellation was
  sent to the running optimized build, which completed successfully before the
  cancellation took effect; no further validation was started. This follow-up uses synthetic local
  fixtures; no additional personal-device capture or install, collection
  export, measured latency claim, commit or push.

- Physical launch-hang follow-up (2026-10-18; local changes over `0748747`):
  built, signature-verified and installed optimized `ReleaseLocal` updates in
  place on the owner's iPhone 15 Pro Max / iOS 27.0.1 with explicit permission
  for bounded device diagnostics. The initial background-construction fix below
  was insufficient: the first device profile still attributed 1,652 ms of
  running main-thread samples to portfolio computation and 762 ms to the
  refresh worker, and the owner still observed hangs. Replaced the default
  executor for all six launch workers with an explicitly owned private serial
  model executor; context creation and every actor job use the same queue.
  Contexts/models remain with their actor, and existing task identity,
  cancellation/session guards and main-actor publication remain in place.
  Added disk-backed regression coverage alongside the in-memory probe.
  iOS 27 simulator verification passes 332 tests, four opt-in skips and zero
  failures across 336 cases. Final optimized device build and strict signature
  verification pass; the corrected build is installed and left open.
  The final phone profile shows zero running main-thread samples in all six
  sampled worker workloads, with the work present on background threads.
  Total running main-thread sample weight fell from 3,197 ms to 692 ms in the
  short recordings; these are CPU samples, not measured launch/hang durations
  or a controlled speedup benchmark. Instruments warned about mixed sampling
  periods; analysis consistently uses the 1 ms running-only table and excludes
  the conflicting 5 ms/context-switch table. The owner confirmed Portfolio now
  responds normally. Capture scope: two 15-second app-targeted profiles and two
  12-second app-console sessions, all retained locally on the external SSD at
  `CodexBuilds/LaunchHangs-20261018/`, including a privacy-safe comparison JSON.
  Console streaming is stopped. No collection export, sysdiagnose, raw device
  evidence in the repository, commit, push or general release certification.
  `git diff --check` passes. This supersedes the simulator-only executor evidence
  in the initial entry below.

- Launch hang remediation, initial simulator pass (2026-10-18; local changes over `0748747`): reproduced
  main-thread database execution in all six launch model actors: portfolio
  replay, collection projection, price snapshots, store revision fingerprinting,
  stale-price targets and the refresh worker. Added a shared background factory
  and switched every production construction site for these workers to it.
  Detached construction keeps SwiftData contexts on background executors while
  existing awaited operations, cancellation/session guards and main-actor UI
  publication remain in place. The synthetic executor regression first failed
  with six threading assertions and then passed after the fix. Focused iOS 26.5
  simulator verification passes 331 tests, with four opt-in skips and zero
  failures across 335 cases, including portfolio accounting/history, collection
  snapshots, refresh lifecycle, revision monitoring and cross-game pricing/
  integration. `git diff --check` passes. Results are retained on the external
  SSD under `CodexBuilds/LaunchHangs-20261018/`. No personal-device access or
  collection capture; physical-device launch timing and confirmation that every
  reported hang is resolved remain unmeasured. No commit or push.

- Four-game specialty catalog coverage (2026-10-15; `35473ed` plus existing
  local changes): compared fresh Scryfall/TCGdex directories, all 87 One Piece
  marketplace groups, LorcanaJSON and eight fresh Lorcana product/finish feeds.
  Adopted 132 original Enchanted printings with exact Holofoil joins; all previous
  1,617 Lorcana physical records are preserved. Current catalog has 1,749 physical
  records and 3,364 exact price lanes. Replaced the broad Pokémon reverse-holo
  ball fallback with 471 exact eligibility rows, shared with Browse generation;
  standard-English detailed lookup also excludes foreign/jumbo identity and
  quote/link evidence. Added six Magic mappings for actual PRM/Dragonfury footer
  labels rather than assuming provider set codes are printed. Added three verified
  original Romance Dawn parallel/manga records to the One Piece review registry,
  with 2,748 retained / 2,493 verified English records and all 2,745 previous
  printing records preserved. New acquisition validation prevents automatic saves
  from bypassing known sibling choices; existing sole-verified policy is retained.
  Unsigned revision 3 validates as protected review. Automatic approval review
  rejected generating/trusting a new signing key and replacing the local owner
  seed without explicit approval; installed owner revision 2/pins are unchanged.
  The [dated audit and discrepancy tables](docs/research/catalog-variant-coverage-2026-10-15/README.md)
  distinguish offline gaps, unreviewed source products and physical ownership.
  Publisher tests pass 46/46, Python tests 95/95, and the final Pokémon price/link/
  Browse/identity replay passes 211/211. The finalized cross-game selection passes
  467 tests, zero failures, three deliberate live-only skips across 470 cases.
  Intermediate failures exposed stale fixture loading, artwork opt-in leakage,
  automatic picker bypass, and a nondeterministic standard-art test; all corrected
  before the final green run. Public captures and unsigned candidate are retained
  under external `CodexBuilds/CatalogCoverage-20261015/PublicSources`; final result
  bundles use the SSD volume's `CodexBuilds/CatalogCoverage-20261015/`. No commit,
  push, production deployment, private signing material, optical/device or
  worldwide-completeness certification.

- Lorcana holistic edge-case sweep (2026-10-14; local changes over `ec6d64c`
  and the preceding uncommitted recovery work): reproduced three defects in
  selected failing regressions. Mapped offline batches retried the same
  unreachable feed for every owned finish without reporting unreachability;
  explicit no-price results missed completed-check accounting; invalid decoded
  data could poison the daily disk cache, including unrepresentable amounts.
  Fixed batch stopping/summary handling with independent mapped/legacy flags,
  named-provider absence accounting, and validation before cache publication and
  disk hydration. Duplicate products/lanes, cross-category/group data and invalid
  amounts reject; valid null/zero caches remain usable. Added five tests including
  corrected legacy-cache recovery and healthy Pokémon work continuing past its
  first concurrent batches. Finalized final shared/live replay passes 162/162,
  zero failures/skips and two internal QoS warnings; fresh matrix still returns
  all 3,232 quotes across eight sets. Earlier focused replay passes 50 with three
  live skips before the final mixed-provider test. Evidence, fresh reports and
  eight group snapshots remain on SSD at `CodexBuilds/LorcanaEdgeSweep-20261014/`;
  exact-seed live opt-in removed. Updated the implementation/production checkpoints
  and doc pointers. No mappings, schema, CSV or UI changes; no full-target rerun,
  App Store export, web update, physical test, portal change, commit or push.

- Lorcana collection-integrity/failure-recovery acceptance (2026-10-14;
  clean starting `feat/lorcana-implementation@ec6d64c`, local changes): reproduced
  the shared TCGCSV feed retaining transport failures for 15 minutes across
  offline, connection loss, timeout and URL cancellation. The source now permits
  recovered transport retries while keeping rejected-feed/HTTP cooldowns,
  pacing, exact product/finish and cache/watermark rules. Mapped refresh now
  treats URL cancellation and cancelled-task errors as abandoned work instead
  of provider failures. Added seven meaningful acceptance cases for recovery,
  last-good price/ownership retention, Normal/Foil quantities, Add/Undo, stale
  edits, disk reopen, CSV round-trip/idempotence and failed-row correction/retry.
  Stored owner-entered/imported reference values survive reopen; CSV remains
  inventory-only, with no new price/history backup claim. Finalized shared run
  passes 154, zero failures, three deliberate live opt-in skips across 157 cases,
  one internal QoS runtime warning; includes One Piece integration, CSV resume
  and refresh lifecycle. Earlier red bundle has one failed recovery case; first
  focused follow-up passes 44 with three skips before final scenario additions.
  Evidence stays on SSD at `CodexBuilds/LorcanaIntegrityRecovery-20261014/`.
  No mappings/schema/CSV format/UI changes, personal export, live opt-in,
  physical-card work, App Store export, web update, commit or push. Updated
  implementation/production checkpoints and documentation authority pointers;
  exports and web page/URL work remain explicitly deferred. Earlier full-target
  and development archive evidence predates these production recovery fixes.

- Lorcana independent rollout continuation (2026-10-14; local changes): added
  seed-bound opt-in acceptance for every enabled printing/finish using the
  existing runtime, quote service and TCGCSV adapter with fresh isolated group
  caches. All 3,232 lanes / 1,616 printings return valid exact quotes across
  eight sets, zero unavailable/mismatched; the full pricing class passes 19/19
  with zero skips and two internal QoS runtime warnings. Offline replay passes
  16 with three deliberate live skips and one QoS warning. Removed redundant
  nil fallbacks in test receipt serialization. Twelve Python tests pass; retained
  sources reproduce the market catalog/UUID ledger byte-identically with the
  same 15 held decisions. CloudKit source audit passes; strict game-boundary
  audit finds 48 existing matches identical to HEAD and zero Lorcana matches.
  Actual local App Store export fails because the distribution profile is
  unavailable; local identity inventory remains one development/zero distribution.
  No portal updates, signing asset creation, upload, production app/catalog edit,
  physical-card testing or deferred privacy/support work. Reconnected SSD holds
  current evidence and retained earlier full regression/development archive/IPA
  under `CodexBuilds/LorcanaRolloutCloseout-20261014/`. Temporary live opt-in and
  private export options removed; no full-target rerun claimed for test-only work.
  Updated the plan, pricing checkpoint and production checkpoint with results
  and remaining owner-controlled rights/distribution acceptance.

- Owner-requested deferral (2026-10-14): deferred privacy/support page
  publication, live verification and app/App Store Connect URL configuration
  until resumed. Updated the Lorcana plan, production checkpoint, legal checklist,
  Bluehost guide and documentation audit; retained drafts/upload files and left
  the submission prerequisite uncompleted. Documentation-only change; no hosting,
  app configuration or App Store Connect changes.

- Lorcana nonphysical rollout follow-up (2026-10-14; local changes on
  `feat/lorcana-implementation`, base `8613a1d`): profiled the reproduced
  centering latency failure and reused strict native pixel kernels for RGBA
  decoding, gradient averages, silhouette counts and Float/Double medians.
  Exact kernel and ten-fixture geometry/profile comparisons pass without
  weakening resolution, samples, thresholds, selection, confidence or timing
  limits. Focused REQ-022 median/max are 0.540/0.615 s; final complete simulator
  run reports 0.586/0.649 s against unchanged 0.8/1.5 s limits. Finalized full
  target: 2,188 passed, zero failed, 12 skipped, five runtime warnings. The first
  follow-up's seven Browse render failures were an outstanding simulator camera
  permission dialog; all seven replayed successfully after foreground setup,
  then the complete target passed. No Browse assertions or production behavior
  changed. Rebuilt actual iOS ReleaseLocal development archive and IPA export
  pass strict signature, byte-identical catalog, privacy manifest, iOS/minimum17
  and DEBUG-route exclusion checks. No hardware install, distribution upload,
  portal/key/sync change, commit or push. The disconnected SSD required internal
  `/private/tmp/LorcanaRollout-20261014/` fallback; temporary package-cache links
  are restored. Prepared app-and-website privacy/support HTML, mobile/desktop
  browser QA, a Bluehost upload guide and reviewer notes without cards. Live
  website privacy still covers only the website and support returns 404;
  publication/verified app URLs, rights/provider details, distribution and
  physical-device/card acceptance remain open. See
  [the production checkpoint](docs/release/lorcana-production-acceptance.md) and
  [Bluehost guide](docs/legal/bluehost-publication.md).

- Lorcana catalog accuracy continuation (2026-10-13; local changes): inspected
  58 public card images and retained references/digests. Corrected 53 redundant
  card listings and one card bundle, added 13 missing promo footers, verified
  six oversized/errata footers and four unnumbered Quest mappings. Exact source
  joins now handle accents/rarity qualifiers within the correct set; cross-set
  promo aliases need image evidence. Inventory is 3,582 English card records
  and 177 sealed products. All 3,574 numbered records pass recognition/lookup;
  all five unnumbered records pass exact title/Quest checks; all records support
  explicit scanner recovery. The three unreadable Palace Heist components stay
  held for automatic recognition. Upcoming labels advance on release and bind
  browse generations to the transition. Continuation passes 135 simulator and
  eight Python tests; all 58 image digests match. A further camera integration
  fix conditionally reads same-frame card text for known unnumbered Quest footers,
  isolates that text from other games and blocks unrelated historical fallback.
  Six public-image macOS CPU OCR probes succeeded after host acceleration failed;
  observed hyphens/S7 now receive bounded repairs, while real suffixes and
  competing repairs remain protected. Unnumbered source sequence numbers are
  hidden from printed-number presentation. Final expanded run passes 322 tests,
  zero failures/skips. SSD result:
  `CodexBuilds/LorcanaCoverage-20261013/Continuation-4.xcresult` (one internal QoS
  runtime warning). Final oversized/errata browse regrouping also passes all 16
  coverage tests at `Final-Browse-Grouping.xcresult` (two internal QoS warnings).
  Physical acquisition/collection writes, signed delivery,
  pricing, camera/device/CloudKit/release gates remain open. No commit or push.
- Lorcana English catalog completeness pass (2026-10-13; local changes):
  registered offline source discovery with all 3,556 English LorcanaJSON cards,
  80 additional market observations and 177 sealed products across all 21
  TCGCSV groups. Fixed actual bullet/D23 footer formats, artwork suffixes,
  Fabled collector zero and the unnumbered Q3 token. Preserved unknown finishes,
  partial/upcoming labels and separate physical authority. All 3,555 numbered
  source cards pass OCR-text recognition/lookup; all 3,636 card records and 177
  sealed products pass inventory traversal. Final focused simulator run passes
  134 tests, zero failures/skips; six builder tests pass. SSD result:
  `CodexBuilds/LorcanaCoverage-20261013/Focused-3.xcresult`. Thirty-three market
  rows still need footer review; source-only acquisition/saving, pricing,
  signed production delivery, device/camera/CloudKit/release acceptance remain
  gated. See `docs/research/lorcana-catalog-coverage.md`. No commit or push.
- Lorcana isolated UI review launch (2026-10-12; base `1e368b3` plus local
  changes): implemented the opt-in `LorcanaReview` DebugRemoteLocal route with
  isolated collection/portfolio/recovery/catalog-cache storage and an ephemeral
  signed synthetic seed. Eight samples exercise actual scanner callback lookup,
  size/stamp choices, finish selection and held/unknown/unavailable-artwork
  recovery through existing screens. Synthetic names/banner remain visible;
  no camera or price provider runs in this harness. App/test compilation passes;
  the final three new review-launch tests pass with zero failures/skips/runtime
  warnings. The earlier regression log records 62 selected contract passes;
  Xcode stalled in result finalization and that process was stopped, so only the
  later three-test bundle is confirmed finalized. SSD artifacts are under
  `CodexBuilds/LorcanaReviewLaunch-20261012/`. Rendered UI, phone/iPad/large-text,
  VoiceOver, real-card and device acceptance remain open. Production Lorcana
  stays disabled; no commit or push was made.
- Lorcana minimum physical acceptance preparation (2026-10-12): retained the
  supplied 26-file package under the real-card corpus, with all checksums matching
  and three source snapshots identical to the earlier import. Locally replayed
  23 offline assertions and 16 Python evidence-precheck tests, all passing.
  Twelve specimen packets remain unapproved; all 25 iOS scenarios remain unrun.
  Linked the acquisition workflow and documented the precheck's declaration-only
  boundary. No real photos, measurements, human approvals, UUIDs, finishes or
  signed seed were created. No Swift/runtime changes, simulator tests, commits
  or pushes; production Lorcana remains disabled.
- Lorcana representative reference corpus (2026-10-12; base `1e368b3`):
  imported the supplied eight-file research package byte-for-byte under
  `docs/research/lorcana-real-card-corpus/source-package/` and linked its review
  workflow from the current plan. Offline validation passes for 29 inactive
  reference candidates, 35 cited sources and 25 specified scenarios; all supplied
  SHA-256 checksums match. Documented the original guide's stale 23-scenario
  count and generator-only `/mnt/data` paths. Physical specimens, two independent
  reviews, exact UUID/finish approval and approved isolated-seed promotion remain
  open. No acceptance scenarios or simulator tests were executed, no runtime
  changed and production Lorcana support remains disabled.
- Lorcana Slice 4 local ownership/Browse/CSV (2026-10-12;
  `feat/lorcana-implementation` at `9d7c780c` plus local changes): completed the
  partly implemented local adapters and connected them to coherent runtime
  activation. Added checked isolated debug binding, exact UUID/finish import,
  duplicate-source conflict retention and final container catalog validation
  before collection/CSV saves. Scanner printing/finish acquisition and recovery,
  Browse add/undo, finish correction/withdrawal, pagination, normalization,
  disk-backed relaunch and CSV round-trip have deterministic coverage. App/test
  builds pass. The broad selected run passed 252/253; one new test expected an
  imported set name to be replaced, contrary to the metadata contract. The final
  corrected ownership replay passes 13/13 with no failures/skips; 240 other
  regression cases passed and were not repeated. These runs establish passing
  evidence for 253 distinct selected cases. Results retain an internal QoS
  warning. SSD build/cache/log/result artifacts remain under
  `CodexBuilds/LorcanaImplementation-20261012/`, including
  `ownership-regressions.xcresult` and `ownership-final.xcresult`. All physical
  records remain synthetic. Rendered UI, real seed/corpus/device/performance,
  pricing, production ownership/CloudKit and release gates remain open; production
  defaults omit Lorcana. No commit or push was made.
- Lorcana Slice 3 signed local activation (2026-10-12; `feat/lorcana-implementation`
  at `9d7c780c` plus local changes): added bounded canonical Ed25519 releases,
  independent trust/cache/transport wrappers, protected durable UUID/finish/
  evidence transitions and predecessor-validated recovery. Added immutable
  coordinator snapshots, container-authorized publication, scanner/recovery
  activation and a supplied-manifest debug kit with ephemeral keys. Production
  remains disabled and the runtime retains only `.scan`. The final app/test build
  and 129/129 selected simulator cases pass, including 23 new activation cases
  and shared/One Piece regressions, with no failures/skips. One internal QoS
  warning remains in a write-fault case. Build/cache/temp/package/log/result
  artifacts use the external SSD's `CodexBuilds/LorcanaImplementation-20261012/`.
  Selected packaging retains all app resources, tested fixtures and compiled
  code; unused test assets are preserved in the full package/source. Fixture
  compiler annotations and a signature-equality assumption were corrected;
  canonical payload/pin equality now permits independently verified re-signatures.
  Installer/storage attempts failed before cases ran. Prior QA app bundles/data
  were preserved on the SSD; its runtime directory was restored after macOS
  denied an external data path, and app data restored after placeholder repair.
  No simulator erase or main-simulator change occurred. See the
  [plan](docs/plans/lorcana_code_implementation.md) and
  [signed contract](docs/research/lorcana-signed-activation.md). Real corpus/seed,
  rendered/device/camera/performance, production keys/hosting/rights, ownership/
  Browse/import/pricing, sync and release acceptance remain open. No commit/push.

- Lorcana Slice 2 physical contract (2026-10-12; `feat/lorcana-implementation`
  at `9d7c780c` plus local changes): added schema-2 canonical/physical UUIDs,
  size/artwork/distribution/stamp identity, explicit per-printing finish evidence,
  complete candidate universes and retained correction/transition history.
  Extended local catalog lookup, exact printing choice, acquisition validation,
  finish menu and UUID-specific finish correction through existing game adapters.
  Known verified UUIDs retain finish authority when discovery is incomplete;
  acquisition cannot infer uniqueness by filtering unresolved alternatives.
  Real recognizer input, size/stamp/artwork distinctions, stable keys, stale/
  tampered choices and relaunch/read-only recovery are covered by 22 new
  synthetic physical-contract tests. App/test target build and final 82/82
  selected simulator cases pass, with no failures/skips. External SSD artifacts
  use `CodexBuilds/LorcanaImplementation-20261012/physical-final.*`.
  Internal disk exhaustion blocked the wrapper's initial package copy; only
  this conversation's generated packages were preserved by relocation to the
  SSD. Buffered progress led to interrupted runs; one prepared run had 52
  passes and a canceled test. A complete replay then had 81 passes and one
  ineffective JSON-tampering fixture; decoded-field edits fixed it before the
  final pass. One internal QoS warning remains. Project syntax, links and
  whitespace checks pass. See the [plan](docs/plans/lorcana_code_implementation.md)
  and [physical contract](docs/research/lorcana-physical-contract.md). Real physical
  corpus, signing, ownership/Browse/import/pricing, native/device/camera, rights,
  sync and release gates remain open; production stays disabled. No collection
  schema changes, simulator erase, commit or push was made.

- Lorcana Slice 2 provider ingestion (2026-10-12; `feat/lorcana-implementation`
  at base `b1959c6` plus local changes): created the requested implementation
  branch while preserving existing Browse/Collection edits. Rechecked Lorcast's
  API and added bounded offline card/set normalization, mandatory all-print
  requests, receipt/body provenance, continuation/envelope rejection and
  fail-closed malformed/duplicate/conflicting metadata checks. Retained four
  public JSON responses containing 31 card rows and 26 provider sets, with no
  image downloads or inferred physical UUID/footer/finish/market authority.
  App/test target build and 60/60 selected simulator cases pass (12 new ingestion,
  13 Lorcana integration, 31 forward compatibility, four suppression; no skips
  or failures). External SSD results use `CodexBuilds/LorcanaImplementation-20261012/`.
  XcodeBuildMCP's post-run parser hit internal disk exhaustion; direct result
  inspection confirmed the completed passing bundle, which also records one
  internal QoS warning. Capture syntax, receipt digests, project syntax, links
  and whitespace checks pass. See the [implementation plan](docs/plans/lorcana_code_implementation.md)
  and [source inventory](docs/research/lorcana-source-corpus.md). Physical records,
  finish evidence, rights, camera/device, activation, ownership, pricing, sync
  and release acceptance remain open; production stays disabled. No commit or
  push was made.

- Portfolio validation and remediation (2026-10-09; `3c28b30` plus local changes):
  validated the ten supplied findings and fixed ownership refresh staleness,
  synchronous history ranges, replay-consistent accounting, pre-epoch holdings,
  no-op delta publications, loading/exclusion/diagnostic copy and live details.
  Retained terminal pricing replay and the tested performance-factor pipeline.
  Focused simulator suite: 147 executed, one opt-in performance baseline skipped,
  zero failures (146 passed). The first runner failed to bootstrap; two new
  fixtures were corrected before the final pass. Inspected normal PortfolioToday
  and PortfolioHistory screenshots from the tested app on an isolated simulator;
  artifacts remain outside the repo. Build/results use external-drive
  `CodexBuilds/PortfolioReview/`. The
  [remediation ledger](docs/audits/portfolio-review-remediation.md) records scope,
  plan reconciliation, HIG review and evidence limits. Device timing, provider,
  CloudKit and release gates remain open. No commit or push was made by this task.

- Bulk intake Stage 0 (2026-10-07; `3fe972a` plus existing local changes):
  added the default-off, local, backup-excluded session metrics actor, ordered
  scanner event hooks and JSON ShareLink export in Settings → Scanning. The
  payload contains fixed outcomes, durations, interruptions and counters;
  runtime IDs, card names, prices and images are excluded. Unreadable evidence
  is preserved. Debug build and 118/118 selected simulator tests pass (4 new
  metrics-log, 97 scanner, 17 unresolved-store; no failures or skips), including
  dismissed-choice logging with baseline behavior unchanged. Build/test results
  use the external SSD at `TradingCardScannerDerivedData/bulk-intake-stage-0/`.
  Documentation links and whitespace checks pass. The
  [staged plan](docs/plans/bulk-intake-differentiation-plan.md) records the accepted
  later fixes; Stage 1 waits for the owner's pre-change device baseline. No
  physical-device, system share-sheet, provider, CloudKit or release acceptance
  is claimed. No commit or push was made.

- Cross-game scanner edge cases (2026-10-06; `412a09d` plus local changes):
  fixed explicit foreign Pokémon footer leakage into English recognition and
  secondary fallback, unknown Pokémon identity fields in live/recovery lookups,
  modern Magic future/missing/invalid printing metadata and provider-flagged
  oversized objects, and partially overlapping One Piece OCR bounds. Existing
  retro/multiface Magic, Pokémon subset/promo/collision rules, and One Piece
  alternate printing/finish/price/recovery behavior remain covered. Four focused
  tests, final Debug build-for-testing, and 619/619 affected simulator tests pass
  with no skips/failures, including all 27 historical Magic corpus references.
  A public French SVI footer was visually reviewed; this adds no physical-device
  or release acceptance claim. See the [dated edge-case report](docs/audits/scanner-cross-game-edge-cases-2026-10-06.md).

- Historical Magic edge-case review (2026-10-06; `412a09d` plus local changes):
  fixed excluded level-up cards (24 additional general titles), quoted names and
  old ligatures/typographic quotes. Same-title logical identities now remain
  separate exact choices, including B.F.M. halves. Unrelated recognized titles
  abstain; malformed ordinary provider rows fail incomplete rather than silently
  disappearing. Back-face/split aliases, suffixes/stars/leading zeroes, duplicate
  or truncated pages, changing totals and hydration drift have added regression
  coverage. The first provider replay caught Scryfall warnings from escaped
  embedded quotes; a warning-free query was verified for all three historical
  quoted names, with strict complete-name agreement retained. Final build,
  nine focused tests, 432/432 broader affected simulator tests (no skips/failures)
  and 22/22 Python checks pass. All 27 corpus titles/choices still pass; eleven
  captured provider searches resolve 29 exact printings through the shared catalog.
  New provider cases are metadata evidence, not new optical/device acceptance.
  See [edge cases and retained evidence](docs/research/magic-historical-corpus/edge-cases.md).

- General historical Magic scanning (2026-10-06; `412a09d` plus local changes):
  implemented the user's corrected scope, using the corpus as frame/layout
  references rather than adding individually activated cards. Normal raw/slab
  dispatch uses general OCR with 14,360 historical root/face titles, including
  title-only pre-Exodus, full-art, split/flip/transform, foil and planeswalker
  references. Complete current English paper printing searches drive explicit
  printing choice; collector OCR ranks without hiding alternatives. Encounter
  English confirmation, exact-ID hydration, refreshed choice membership and
  immediate pre-write checks preserve exact ownership/finish identity. Large
  printing families have native Details search. All 27 originals reach matching
  titles and printing choices without manual card framing or a per-card allowlist.
  An unlisted Counterspell fixture verifies the ordinary collection writer.
  Debug build-for-testing, 388/388 affected simulator tests (no skips/failures)
  and 22/22 Python checks pass. Three native search captures pass source/render
  HIG review, including accessibility3 wrapping. Static references do not certify live-camera or
  physical-device accuracy. Optional automatic index selection stays disabled.
  See [general implementation evidence](docs/research/magic-historical-corpus/general-scanning.md).

- Historical Magic corpus-backed OCR/save (2026-10-06; `412a09d` plus local
  changes): shared actual card-relative Vision requests between the local scanner
  pilot and private-corpus evaluator. Reconciled Survival of the Fittest `129/143`
  to its exact Exodus printing/current collision family, adding photographic
  visible-number evidence and a fourth dated complete key; retained 150 printing
  IDs and collision blockers. Hash-pinned staging keeps all original images on
  the external SSD and rejects changed/escaping/duplicate sources. Actual OCR on
  27 originals produces one calibrated positive and 26 scope abstentions. The
  normal scanner choice/writer saves its exact printing after English confirmation
  and writes nothing beforehand. Fixed the first run's duplicate source-receipt
  refresh defect with replacement/rerun coverage. Focused simulator 27/27,
  affected regression 316/316, Python 20/20 and Debug build-for-testing pass.
  Annotated framing/repeated stills do not certify held-out positive, independent
  camera-frame, live-provider acquisition or physical-device acceptance. Production
  remains disabled; broader frame templates are next. See the
  [corpus evidence and reproduction](docs/research/magic-historical-corpus/README.md).

- Historical Magic photographic corpus intake (2026-10-06; `412a09d` plus local
  changes): inspected the supplied sources-only archive without executing its
  embedded downloader; separately downloaded and decode-verified all 27 images
  on the external SSD. Visual review supports 20 photographic examples and seven
  clean-front controls. Recorded per-image hashes, preserved manifest labels and
  corrected the Unhinged Forest test-case assumption to black-border full-art.
  Survival of the Fittest has visible `129/143`, supplying an Exodus photographic
  review lead. Exact printing/face labels, held-out OCR evaluation and device
  acceptance remain open; no runtime/index changes or optical pass claims.
  See the [corpus review](docs/research/magic-historical-corpus/README.md).

- Historical Magic D integration (2026-10-06; `412a09d` plus local changes):
  reviewed three provider fronts for printed `number/143`; retained five complete
  all-era English/paper searches and seven exact-ID collision captures. Reconciled
  all 150 index identities, normalized Spanish/`es` and corrected PEXO's per-printing
  date before Exodus. Three dated key receipts expire 2026-10-07 UTC; outside-era
  and promo matches remain blockers. Added bounded same-frame OCR, historical
  namespace/profile pins, encounter-scoped English confirmation, exact hydration,
  printing choice, pre-save collision/activation checks and persisted recovery.
  Historical scanner/adapter production defaults remain off. Final selected
  regression passed 314/314 and Python importer/reconciliation passed 13/13.
  The real-store recovery recheck passed 10/10 after fixing identifier generation
  and correcting a fixture that bypassed held-card protection; exact row/finish
  keys remain unchanged. Evidence is retained on the external SSD under
  `CodexBuilds/MagicHistorical`. Final Debug build and standard/accessibility
  picker/Details captures pass the inspected UI checklist; English confirmation
  carries within an encounter and direct recovery applies the same gate. No known camera-photo folder is available;
  physical/device acceptance and broader plan gates remain open. See the
  [plan](docs/plans/magic_historical_recognition_plan.md) and
  [pilot report](docs/research/magic-historical-pilot/README.md).

- Historical Magic initial C index slice (2026-10-06; `412a09d` plus local
  changes): captured/hash-pinned dated MTGJSON AllPrintings/EXO and complete
  Scryfall EXO inputs on the external drive. Streamed 123,822 source rows into
  a full disposition ledger; source rows/faces are not a physical denominator.
  Bundled 143 exact-ID reconciled Exodus printings plus seven held cross-era
  collision records. Added dictionary lookup, explicit per-key all-era receipt
  membership/expiry/source-context checks and atomic compatible profile/index
  activation. Physical number visibility is unknown and actual completeness
  receipts are empty, so historical acquisition stays disabled. All 145 focused
  simulator tests and eight importer tests pass. Artifact size is 383,009 bytes;
  simulator load p95 68.3 ms and warm-query p95 0.036 ms. Memory/device/optical,
  current-source reconciliation and D adapter/save gates remain open. See
  `docs/research/magic-historical-pilot/README.md` and the current recognition plan.

- Historical Magic first implementation slice (2026-10-06; `412a09d` plus local
  changes): added versioned inert local recognition profiles, exact printing-ID
  overrides, deterministic catalog/profile/index generations and atomic
  compare-and-publish activation. Registry projection preserves schema-1 modern
  vocabulary and authority. Added six profile tests; 136 focused simulator tests
  and 18 MagicCatalogCore tests pass after a 130-test pre-change baseline.
  External drive holds DerivedData, package caches and result bundles. Retained
  a reproducible 910-set inventory (262 Phase-1 review leads), source/output
  hashes and explicit language/layout policy. Set counts do not establish a
  physical denominator. Historical acquisition remains disabled; physical corpus,
  reconciliation/index/freshness, historical adapter/OCR/picker/save and device
  gates remain pending in `docs/plans/magic_historical_recognition_plan.md`.

- Historical Magic plan review follow-up (2026-10-06): incorporated namespace-aware
  adapter preparation/lookup/choice/retry, candidate-universe completeness/freshness
  checks at lookup and save, printing-versus-finish/SKU identity rules, explicit
  encounter-scoped language evidence/confirmation and a reviewed legacy layout
  allowlist. Split B into app-local B1 and deferred signed schema-2 B2 after the
  bundled pilot; added failure/acceptance cases for each invariant. Documentation
  only; no app, catalog, schema, signing or rollout changes.

- Historical Magic implementation planning (2026-10-06; `412a09d` plus local
  documentation changes): source-checked the collector-number-era proposal and
  wrote `docs/plans/magic_historical_recognition_plan.md`. Corrected the scanner
  gate, set-versus-printing/profile assumptions, inventory-helper completeness,
  candidate uniqueness and exact scope claims. The plan covers inert profile
  contracts, a reconciled index, a bounded legacy OCR pilot, printing/finish
  choice, round-trips and device/rollout acceptance, with pre-Exodus deferred.
  No implementation, catalog adoption, build or rollout was performed.

- Card coverage data intake (2026-10-06; `412a09d` plus local changes):
  retained only 471 exact Pokémon parallel eligibility rows, two Magic PLG20
  filter regressions and 21 One Piece printing review leads. Retained hashes,
  sizes/counts, unique eligibility keys and negative cases pass. Compared
  existing NEO mappings and One Piece families; excluded duplicate data, stale
  aggregate counts, competing contracts and flawed helpers. Internal One Piece
  rows are available here despite the package's missing-input claim. No runtime
  adoption or release acceptance change. See the
  [intake note](docs/research/card-coverage-gap-data/README.md).

- Card coverage research report (2026-10-05; `f40e704` plus local changes):
  added `docs/audits/card-coverage-gaps-and-research.md` with known boundaries,
  unverified coverage, research priorities and closure criteria for Magic,
  Pokémon and One Piece. Direct Pokémon payload inspection corrected the
  earlier inference that low manifest cardCount values demonstrated missing
  cards; payload row counts meet the recorded standard slot counts for those
  eight entries. Magic token/art routes are distinguished from ordinary-path
  exclusions. Relative report links and diff whitespace checks pass. No source,
  catalog, device or release acceptance change is claimed.

- One Piece normal-app correction (2026-10-05): owner rejected the renamed app
  and isolated review collection. Built and installed the original
  TradingCardScanner identity/name with normal collection paths and a verified
  owner-local signed catalog enabling One Piece alongside Pokémon and Magic.
  Only the verified public pin is retained for subsequent ordinary local builds.
  The catalog copy and in-place installation succeeded without uninstall/export.
  Focused owner-catalog/storage selection executed 32 tests with zero failures
  and one expected simulator data-protection skip. Collection contents and camera
  behavior await phone confirmation. This supersedes the review-storage flow below.

- One Piece existing-app review update (2026-10-05; superseded): owner declined backup/app
  removal and explicitly requested reuse of the working scanner app. Added a
  signed debug-only opt-in for Home Screen review under the existing app identity,
  still using the separate OnePieceLocalReview storage root. The kit tool supports
  `--reuse-existing-app`; ordinary builds without the opt-in remain unchanged.
  Device build passed and two focused simulator tests passed. In-place install
  and signed catalog copy succeeded without uninstall/export. Remote launch was
  denied because the phone is locked; owner unlock/open and first physical scan
  remain pending. No production or shared-collection acceptance is claimed.

- One Piece physical-review preparation (2026-10-05; local changes): prepared a
  fresh full-corpus ephemeral signed kit and a separately identified “One Piece
  Review” DebugRemoteLocal app. Home Screen activation is restricted to the
  separate debug/local-only bundle and explicit public review pin; the kit tool
  now emits its review Info.plist. Device build passed with separate identity and
  no iCloud entitlements; two focused simulator tests passed. iPhone installation
  failed because its free developer-profile app slots are occupied. No existing
  app was replaced/deleted. Backup of the older scanner container was blocked by
  automatic approval review pending explicit export authorization; no backup
  ran. `docs/plans/one_piece_device_review.md` records the first-card checklist.

- One Piece v1 preparation (2026-10-05; uncommitted changes based on `534127f`,
  matching cached and live remote `main`): recorded owner approvals for private
  installs, English/verified/text-only scope and source roles in
  `docs/plans/one_piece_release_acceptance.md`. Moved seed preparation off the
  main actor, made recovery reload explicit and blocked during scanner work,
  retained authorities on no-change retries, and added the default-off production
  collection-write flag (remote-authority only). Added One Piece hosting cache
  rules and signed immutable namespace restoration, preserving existing publisher
  callers. Prepared deterministic printing/price/device samples and corrected
  local review pricing and CSV documentation. App build and 59 One Piece tests
  passed; final broader selection executed 159, zero failures and one expected
  simulator data-protection skip. Core suite 40 passed plus enhanced CLI case;
  seven focused Python tests and cache/link/diff checks passed.
  Rendered recovery QA preserved the Collection tab on no-op Retry and disabled
  Retry during Scan, restoring it after leaving Scan. This is simulator UI evidence.
  MCP's later export hit internal disk space; preserved this task's two bundles on the external SSD
  and reran directly there. No commits/push, production keys/publication, physical
  acceptance, CloudKit or archive evidence. Signing-key storage choice is pending.

- One Piece remaining-audit cleanup (2026-10-05; local changes on
  `merge/one-piece-integration@55dc1e4`, verified equal to freshly fetched
  `origin/main` before editing): removed three accidentally committed
  `undefined/` adapter copies, corrected model spacing and stale scope wording,
  accepted registered CSV display names while preserving unknown identities,
  moved fresh withdrawal-watermark reads off the main thread, and separated
  in-flight requests across withdrawals. Fetch-start timestamps and newer-cache
  retention prevent an older completion from replacing fresh data; the default
  cache moves to v2. Optional catalog failures now have a visible Retry action
  and retain update observers so later verified activation can restore the
  module without relaunch or weakening collection-write policy. The initial
  focused simulator selection passed 94/94; final pricing/cache, runtime,
  scanner/recovery, activity and CSV selection passed 257/257, zero failures or
  skips, with terminal `TEST SUCCEEDED`. Result:
  `<external-ssd>/CardScannerBuild/OnePieceAudit-2026-10-05/FinalRegression.xcresult`.
  The initial MCP test export uses its fixed app-support directory; derived
  data and the final run's result/logs use the external drive. A subsequent
  layout-only fix and final build passed; inspected the deterministic
  `CatalogUnavailable` screenshots on iPhone 17 Pro / iOS 26.5, checked Retry
  and Collection navigation, and verified headers/tabs remain visible. Local
  screenshots/checklist are ignored artifacts; prior `ui-latest` captures were
  preserved. The architecture audit still reports the same 37 existing legacy
  branches. No commit, push, device/provider/CloudKit or release certification.
  See the [current handoff](docs/audits/one-piece-integration-review-handoff.md).

- One Piece integration review fixes (historical checkpoint, 2026-10-05;
  uncommitted on `6b64abe` at verification time, subsequently committed through
  `55dc1e4`):
  isolate optional launch failures, reuse verified catalog snapshots/seeds,
  restore activity/CSV compatibility, preserve recovery copy state and purchase
  links, rehydrate current Pokémon definitions, batch history-write validation,
  make price-cache generation/freshness explicit, and verify signing against
  app-pinned keys. The activity finish picker now uses the bound registry and
  enables selection before Save. Final simulator regression: 300 passed, zero
  failures/skips across scanner, recovery, import, activity, pricing/cache,
  runtime, and signed-store suites. One Piece core/publisher: 40 passed; Python
  One Piece pipelines/trust anchors: 48 passed. Workflow YAML/shell syntax,
  165 local documentation links, and `git diff --check` pass. The expanded
  boundary audit reports 37 existing branches; legacy extraction and production
  rollout/collection-write/device/release gates remain open. Existing user
  edits are preserved; no commit, deployment, or release certification.
  See the [corrected handoff](docs/audits/one-piece-integration-review-handoff.md).

- One Piece plan/source reconciliation (2026-10-05; main checkout at `6b64abe`):
  updated the [implementation ledger](docs/plans/one_piece_code_implementation.md)
  and [catalog design](docs/plans/one_piece_catalog_integration_plan.md) for the
  committed integration, current corpus/base mappings, exact finish correction,
  container-bound withdrawal and catalog adapter extraction. Existing full-kit
  local base-case acceptance is next; legacy Browse/import and external gates
  remain open. Read-only boundary audit confirms eight Browse labels. Plan-only
  update; no implementation, build or app/package test rerun, and the recorded
  192-test selected checkpoint remains historical evidence.

- One Piece merge-branch review handoff (2026-10-05): transferred 183 integration
  files onto `merge/one-piece-integration` in the main checkout, preserving its
  existing whitespace edit and `undefined/` files. `main` and the source worktree
  remain unchanged; no commit was created. Added a factual
  [change report](docs/audits/one-piece-integration-review-handoff.md) identifying
  code boundaries, catalog/pricing scope, existing verification and remaining
  acceptance work. Documentation-only follow-up; no new build/test run.

- Base-case handoff / Pokémon catalog extraction (2026-10-05; One Piece worktree
  at `69c714f`): moved Pokémon provider/offline/disk-cache/historical behavior
  into game-owned catalog files, retaining persisted keys and captured modern
  definitions. Central catalog dispatch/coalescing is generic; eight remaining
  audited branches are all in Browse. All 192 selected tests passed in one
  checkpoint, including One Piece scan/save pricing, exact lanes and quote
  withdrawal, pricing/cache suites and legacy game compatibility. Result:
  `test_sim_2026-10-05T13-01-49-160Z_pid18958_cc372487.xcresult`.
  Installed and relaunched the simulator build with the unchanged full ordinary/
  base-pricing kit. Plan priority is local base-case acceptance before further
  framework or special-printing work; device/camera/production gates stay open.
  See [Package 3](docs/plans/one_piece_code_implementation.md#package-3-move-existing-behavior-behind-existing-adapters).

- Magic catalog adapter extraction (2026-10-05; One Piece worktree at `69c714f`):
  moved ordinary-card and signed/live token/art routing into `MagicCatalogAdapter`,
  registered by the runtime and legacy-compatible default factory. Central catalog
  now prepares/coalesces adapter identifiers, caches bounded lookup outcomes and
  preserves retrieval timestamps without storing the user's printing selection.
  All 55 focused Magic/forward-compatibility/historical-Pokémon/One-Piece cases pass
  in `test_sim_2026-10-05T12-37-17-792Z_pid18958_d68ce592.xcresult`. The strict
  boundary audit remains red at 11 matching labels. Signed Magic activation,
  Pokémon catalog, Browse/import extraction and release gates remain open.
  Updated app/full-kit relaunch retained the existing Shanks/portfolio $8.16
  display; no new provider request or camera acceptance was claimed.
  See [Package 3](docs/plans/one_piece_code_implementation.md#package-3-move-existing-behavior-behind-existing-adapters).

- One Piece withdrawal/retired-session acceptance (2026-10-05; existing worktree
  at `69c714f`): expanded the signed activation fixture to attempt actual
  single/multi-claim finish corrections after quarantine. Rows, acquisition
  claims, ledger operations, inventory events and price history remain unchanged.
  Added conflict/stale revision and retired/replacement storage-session coverage.
  All three focused tests pass in `test_sim_2026-10-05T12-24-13-145Z_pid18958_115e2d5a.xcresult`;
  no app behavior change or full regression run. The architecture audit still
  identifies 13 legacy Pokémon/Magic case labels. Full-plan/device/production
  gates stay open; local base-case testing remains the immediate handoff.
  See [Package 1 evidence](docs/plans/one_piece_code_implementation.md#package-1-implementation-checkpoint-2026-10-04).

- One Piece cached-price withdrawal (2026-10-05; existing worktree at `69c714f`):
  exact mapping fingerprints persist with owned/reference quotes. Catalog
  publication withdraws managed-provider values before exposing a changed
  generation; manual prices and permanent printing IDs stay intact. Older quote
  receipts cannot restore a withdrawn value. The app binds consumers to its
  authoritative storage container, using the coordinator's current snapshot.
  The consolidated One Piece/pricing selection passed 103/103; the focused
  same-container rebinding/quote-cache recheck passed 18/18. Relaunch found that
  older feed-cache receipts could delay restoration; feed caches are now bound
  to catalog generation. Its test caught default-protocol dispatch; explicitly
  async actor implementation fixed it and the affected test passed. Internal
  disk exhaustion during test packaging was resolved by retaining two generated
  bundles on the SSD. Final full-kit relaunch/Refresh Prices restored the saved
  Shanks copy and portfolio value to $8.16. Base-case local
  acceptance is next; production/device and special-printing gates remain open.
  See the [current handoff](docs/plans/one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04).

- One Piece exact base pricing (2026-10-04; existing worktree at `69c714f`):
  reviewed 1,961 original base mappings across 48 retained price groups; 412
  ambiguous/qualified-title or missing-lane decisions remain held. Permanent
  physical IDs/counts preserved. Exact TCGCSV product/Normal-Foil quotes are wired
  through runtime, Price Check, Browse details/add and collection refresh; no
  condition SKU, base-card fallback or zero-dollar placeholder is invented.
  Four Python review tests and two affected core tests pass. The app checkpoint
  passed 56/59 initially; corrected three synthetic completeness claims, then
  all three pricing tests plus affected Browse registration passed. Full debug
  kit verifies (20,873,783-byte envelope); unsigned revision 14 validates against
  revision 13. Live simulator: Shanks Romance Dawn Foil showed $8.16, adding one
  copy persisted/displayed $8.16 in collection; unmapped FILM RED Nami stayed
  unpriced. Camera save now also routes to the exact adapter; its focused
  save/choice/quote/persistence test passes without paid credentials. There are
  61 distinct passing app cases across the checkpoint and affected rechecks.
  No production sync/rights/device gate closed.
  See the [base pricing ledger](docs/plans/one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04).

- One Piece full ordinary app checkpoint/local kit (2026-10-04; existing worktree
  at `69c714f`): expanded scan/printing-choice/finish/save coverage through ST13,
  OP17, EB03/EB04 and PRB01/PRB02; held ST30/ST31 rows remain unowned. The 43-case
  app selection passed 41 initially, with two new assertions incorrectly assuming
  Browse exposed all retained products. Corrected to 52 verified-target groups;
  both affected rechecks pass. No full suite repeated. Generated and verified one
  full-corpus debug kit on the SSD; 2,745 printing records, 16,119,026-byte signed
  envelope, independent ephemeral key/revision-one local bootstrap. Unsigned
  publisher successor remains revision 13. Production, pricing, image rights,
  sync, rendered/device and activation/memory gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md#latest-full-ordinary-batch--2026-10-04).

- One Piece full ordinary corpus adoption (2026-10-04; existing worktree at
  `69c714f`): adopted all 58 ordinary product groups and 2,731 selected rows,
  including the retained legacy PRB01 release page. Current corpus: 2,692
  canonical cards, 2,745 printings (2,490 verified, 224 provisional, 31 conflicted),
  8,237 observations, 2,940 captures and 257 open discrepancies. All 817 earlier
  printing/artwork records, 794 canonical records and 19 product records remain
  unchanged. Exact replay matches all five artifacts; unsigned revision 13
  validates against revision 12 as protected review and is retained on the SSD.
  All 42 selected Python tests pass. Core: 39 passes and one assertion failure
  from the new test assigning base EB04-061 to OP17 instead of OP15; corrected
  and the affected recheck passes. App checkpoint/local kit remain pending; no
  production, rights, pricing or completeness gate closed. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md#latest-full-ordinary-batch--2026-10-04).

- One Piece full ordinary capture/source review (2026-10-04; existing worktree at
  `69c714f`): completed the 57-product capture with no availability/empty-page
  gaps and 2,935 retained source records. Extracted shared retained-source
  validation and added `--audit-only`: full-batch issue reporting without identity
  allocation or corpus adoption. Initial audit: 22 of 57 products source-ready;
  remaining issues include provider title annotations, special physical listings
  and missing starter finish evidence. Corrected exact printed-number title
  annotations while preserving treatment labels. New authored fixtures remain
  deferred to the consolidated checkpoint. No builds/suites, revised registry
  or successor candidate. Audit artifact:
  `/private/tmp/one-piece-bulk-source-audit-20261004/product-source-audit.json`.
  See the [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece full ordinary draft/capture (2026-10-04; existing worktree at
  `69c714f`): prepared a private unadopted 57-product, 2,730-row batch, preserving
  all 17 earlier product specifications. Combined-release base rows, selected
  starter reprints and held parallel artwork stay explicit; PRB-01 release-page
  evidence remains a scoped gap. Added whole-batch capture continuation for HTTP
  availability/empty retailer results while retaining fatal integrity checks.
  Corrected reuse of the already-retained OP17 series-index capture ID/filename
  without changing its bytes. Full-batch capture is running; no revised physical
  registry or catalog candidate yet. Authored fixtures are deferred to the final
  consolidated checkpoint; no builds or suites run. See the
  [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece bulk inventory implementation (2026-10-04; existing worktree at
  `69c714f`): added `scripts/discover_one_piece_products.py` using the retained,
  paced capture transport. Captured all 18 observed official product-index pages,
  58 ordinary series lists and 3,881 numbered artwork rows; 52 linked product
  pages include older PHP and directory-style release pages. Combined OP14/OP15
  and EB04 prefixes, shared deck pages, reprint aliases, future products and
  independent market-group candidates remain explicit discovery evidence.
  Private `bulk-product-discovery-v3.json` is retained on the external SSD.
  No physical UUIDs allocated, catalog coverage promoted, builds or suites run.
  Authored pagination/combined-release/reprint/offline fixtures and added the CI
  entry; execute them at the consolidated checkpoint. Next: review the complete
  product manifest and capture/reconcile ordinary printing evidence as one batch.
  See the [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece bulk execution change (2026-10-04; owner instruction): plan now
  batches all remaining ordinary OP/ST/EB/PRB products into one implementation
  deliverable with one consolidated replay/core/app checkpoint and one successor
  candidate/local kit. Bounded capture chunks remain resumable internal work;
  missing physical evidence stays held. The remaining physical distinctions form
  a second bulk pass. No implementation or tests in this planning update. See the
  [ordered execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece OP-04/OP-05/ST-11/ST-12 batch (2026-10-04; existing worktree at
  `69c714f`): retained 270 new standard identities, 246 verified and 24 provisional.
  Missing retailer finishes remain held; OP-05 PSA Magazine/SP rows are explicitly
  excluded from base-art evidence. Preserved all 547 earlier printing records.
  Current corpus: 794 canonical cards, 817 printings (692 verified, 117 provisional,
  eight conflicted), 2,515 observations, 856 captures and 127 open discrepancies.
  Allocation-free replay matches all five artifacts. Unsigned revision 12 validates
  against revision 11 as protected review; no signed kit/publication. All 40 core
  and 35 Python tests pass. All 43 selected One Piece integration tests pass,
  including the four new product choice/finish/save flows and held-finish ownership
  exclusions. The unsigned revision-12 candidate is retained on the external SSD;
  see the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece capture/discrepancy pipeline (2026-10-04; existing worktree at
  `69c714f`): added bounded retained-byte product capture with observed pagination,
  exact source/group checks, four globally paced image workers, explicit orphan
  recovery and offline mode. Replayed all 13 real products/533 selected artworks
  without network or source-manifest changes. Added 103 durable held-record/scope
  discrepancies with retained resolution history; all five reconciler artifacts
  match replay. All 32 selected Python tests pass. No iOS/core build or new live
  coverage. Next: ordinary-product expansion and the remaining activation checks;
  see the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece reviewed-product manifest migration (2026-10-04; existing worktree
  at `69c714f`): replaced reconciler product/reprint constants with the durable
  13-product, 533-identity manifest. Preserved all 547 printing records, artwork,
  aliases, finish evidence and existing observation keys. Two retained-byte runs
  reproduce identical outputs; registry/observations/inventories also match the
  prior corpus. Updated only review scope and the inaccurate retailer-only finish
  limitation. Added seven authored pipeline tests and workflow coverage; all
  24 selected Python tests pass. No iOS/core build. Capture automation, further
  coverage and activation ordering remain open in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece developer-handoff recalibration (2026-10-04; existing worktree at
  `69c714f`): reviewed uncommitted runtime, correction, capture/reconciliation and
  workflow source. Updated documentation only: distinguish implemented work from
  remaining activation ordering, specify the reviewed product/discrepancy schemas,
  split retained-byte manifest migration from capture expansion, and define replay
  and crash-recovery acceptance. Corrected the focused verification scheme and
  removed a nonexistent test-file requirement. No implementation, build or test
  run. See the [code/file-level handoff](docs/plans/one_piece_code_implementation.md#codefile-level-implementation-handoff).

- One Piece exact correction and evidence checkpoint (2026-10-04; worktree
  `one-piece-integration`, base `69c714f`): corrected the two ST-10 OP-01 review
  descriptions and reconciler output; replay retained all 533 standard identities
  and reproduced registry, observation, inventory and review JSON exactly. Added
  synchronous printing/finish validation to the One Piece adapter and all three
  collection correction mutations, with per-container adapters and monotonic
  activation revisions configured from the app root. The selected 42-case suite
  compiled with 41 passes and one test-fixture failure; after fixing its
  uppercase-UUID input and adding no-adapter/price-key assertions, the affected
  test passed in isolation. The full selected suite was not rerun after that
  test edit. A source audit also traced CSV, normalizer, detail-edit, quantity
  and removal writes to their capability/store gates. See the
  [Package 1 checkpoint](docs/plans/one_piece_code_implementation.md#package-1-implementation-checkpoint-2026-10-04).

- One Piece implementation handoff detail (2026-10-04; existing worktree at
  `69c714f`): expanded the current execution plan with prescribed files/APIs,
  collection authority and mutation ordering, product capture/manifest schema,
  Pokémon/Magic extraction targets, signed seed/hosting contract and focused
  verification inputs. External release decisions are explicit owner inputs.
  Documentation-only; no implementation, build or test rerun. See the
  [code/file-level handoff](docs/plans/one_piece_code_implementation.md#codefile-level-implementation-handoff).

- One Piece efficiency/plan audit (2026-10-04; existing worktree at `69c714f`):
  inspected current code, registry, publisher artifacts and existing test logs.
  Current state reaches ST-10/OP-03: 534 canonical cards, 547 printing records
  (446 verified, 93 provisional, eight conflicted) and 1,727 observations. Latest
  logs record 40 core and 40 One Piece integration passes. Updated only plans:
  retire small-demo-next priorities, batch catalog work, close exact correction
  and remaining routing gaps, and consolidate verification at milestones.
  Retained full physical coverage, rights, delivery, device and sync requirements.
  The two ST-10 reprint evidence descriptions still need manufacturer-only wording;
  no code/data fix, build or test was performed in this audit. See the current
  [execution plan](docs/plans/one_piece_code_implementation.md).

- One Piece next starter/booster coverage (2026-10-04; existing isolated worktree
  at `69c714f`): retained all 202 standard OP-02/ST-05–ST-09 rows, with 200 new
  verified printings and two provisional revision records. Current corpus: 394
  canonical cards, 405 printings (306 verified, 91 provisional, eight conflicted),
  1,284 observations. All earlier 203 printing records are unchanged; offline
  replay is exact and protected publisher revision 10 validates against revision 9.
  Prepared the expanded signed local kit externally. Fixed source timestamp
  validation to accept fractional ISO-8601 seconds; invalid values still fail.
  All 40 core and 40 One Piece integration tests pass, exercising one card per
  new product through recognition/choice/finish/save. Later products, revision
  reconciliation and production gates remain open in the
  [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece remaining launch starters (2026-10-04; existing isolated worktree
  at `69c714f`): added all 51 standard numbered ST-02/ST-03/ST-04 records, with
  24 more verified acquisition printings. The corpus now retains 192 canonical
  cards, 203 printing records (106 verified, 89 provisional, eight conflicted)
  and 678 observations. Retained every duplicate retailer finish assertion;
  unresolved original/revision and normal/foil disagreements remain review-only.
  Publisher revision 9 preserves revision 8 identities, offline replay is exact,
  and the expanded signed debug kit is prepared externally. All 39 core and 40
  One Piece integration cases pass, now exercising all four launch starters.
  Later products, original/revision reconciliation and production gates stay open
  in the [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece standard starter/booster expansion (2026-10-04; existing isolated
  worktree at `69c714f`): retained all 17 ST-01 and 121 OP-01 standard-art rows with
  permanent UUIDs and independent retailer finish evidence. Enabled 69 additional
  verified printings (ten starter, 59 booster); 68 errata records remain provisional
  and one conflicting starter leader remains excluded. The corpus now has 141
  canonical cards, 152 printing records and 518 observations. Offline replay
  reproduces all artifacts without UUID allocation; publisher revision 8 retains
  the earlier identities and an expanded signed debug kit is prepared externally.
  All 39 core and 40 One Piece integration tests pass, including ordinary Karoo,
  starter Luffy and booster Shanks choice/finish/collection paths. No app images,
  market joins, prices or production enablement were added. Remaining original/
  revision distinctions and further starter/booster products are still open in
  the [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece rendered Browse base case (2026-10-04; existing isolated worktree at
  `69c714f`): launched the expanded signed review kit, searched for FILM RED Nami,
  added one raw foil copy and verified release/finish/quantity after stopping and
  relaunching the app. Reinstallation also retained the review collection. Fixed
  internal product IDs in Browse projections and replaced unsupported-pricing
  retrieval/history claims with “Pricing unavailable”; the updated detail
  accessibility tree confirms that state. All 102 selected One Piece/Browse tests
  pass with no skips or failures. Camera OCR, rendered scanner choice, broader
  English corpus and production gates stay open. See the
  [local review instructions](TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md).

- One Piece retail base-catalog expansion (2026-10-04; existing isolated worktree
  at `69c714f`): reviewed twelve FILM RED retail alternate-art printings against
  the manufacturer's product/card list and explicit foil specification. The
  durable corpus now holds 13 verified printings and one provisional record,
  14 canonical cards and 103 observations. Retained sixteen raw source responses
  privately on the external review drive; app artwork URLs and market joins stay
  absent. All 38 core tests and 39 selected app cases pass, including real retail
  Nami scanning, explicit choice, foil and collection identity. Publisher revisions
  6/7 retain UUIDs across protected expansion and unchanged replay; prepared an
  expanded signed local kit. Original starter Nami finish, ordinary booster/starter
  coverage, rendered/device and production gates remain open. See the
  [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece real local base case (2026-10-04; existing isolated worktree at
  `69c714f`): debug/local-only launches can load a signed review catalog, scan and
  Browse One Piece and write an isolated persistent collection. Databases and
  recovery use a separate review directory; no remote One Piece updater or price
  adapter is created. Prepared a real small signed catalog on the external SSD
  with an ephemeral key. The real P-001 winner test covers recognition, explicit
  choice, sole foil resolution, disk save/reopen, CSV export and offline Browse.
  The checkpoint executes 68 cases: 67 passed, one existing storage skip, zero
  failures. The test runner shut down the simulator before separate installation,
  so rendered launch and physical-camera/process-relaunch acceptance stay open.
  See the [local review instructions](TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md)
  and [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece required import validator (2026-10-04; existing isolated worktree
  at `69c714f`): new-game CSV rows now require their installed printing adapter
  before any ownership operation. Writable capability alone cannot bypass exact
  identity validation; existing Pokémon/Magic legacy import behavior is retained.
  The simulator checkpoint passes all 72 selected One Piece integration, CSV
  resume and forward-compatibility cases, including refusal of numbered/UUID
  One Piece and future-game rows without an adapter. The plan records the remaining
  exact-printing finish-correction gap before write enablement. Links and diff
  whitespace pass; production remains gated in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece normalization live-policy guard (2026-10-04; existing isolated
  worktree at `69c714f`): request discovery, legacy sealed-artwork repair and
  metadata application now honor current container write permissions. Both save
  paths validate pending game writes; sealed rekeying shares the configured store.
  A suspended One Piece lookup discards its result after permission withdrawal,
  preserving identity, metadata, artwork, history and price observations.
  The focused simulator checkpoint passes 84 cases across One Piece integration,
  normalization and forward compatibility. Plan links and whitespace checks pass;
  wider direct-save, physical reconciliation and production sync gates remain
  open in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece Browse activation refresh (2026-10-04; existing isolated worktree at
  `69c714f`): updates now carry their own game and catalog revision, preserving
  older global provider events. Refresh only affected game directories; restart
  unchanged active searches through the existing debounce so old-generation rows
  and cursors are discarded. Open sets filter updates by game/set and rebase their
  descriptor on deliberate reset; pagination remains pinned. Withdrawn sets clear
  old selectable rows. The Browse checkpoint passes 104 selected tests, four
  focused rebase/scoping follow-ups pass, and the final withdrawal guard compiles
  in a build-only checkpoint. Whitespace and plan links pass. Rendered navigation,
  device, production and wider corpus gates remain open in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece required finish evidence (2026-10-04; existing isolated worktree at
  `69c714f`): rules version 2 requires an explicit catalog-supported finish review
  for every verified physical variant, agreeing with canonical number, language
  and release. Missing/contradictory claims, market observations and image-only
  roles are rejected. Migrated the real winner review to its manufacturer finish
  specification; participant stays provisional with no finish. Unsigned publisher
  revisions 4/5 preserve both UUIDs across protected migration and replay.
  All 38 core/publisher tests and 43 selected app tests pass, with successful
  terminal processes. Plans, JSON/candidate hashes and whitespace checks pass.
  Production, corpus coverage, rights and device/sync acceptance remain open in
  the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece first real award reconciliation (2026-10-04; existing isolated
  worktree at `69c714f`): allocated durable P-001 winner and participation UUIDs
  from reviewed official event evidence. The manufacturer specifies the winner's
  silver foil; a grading-company physical photograph independently corroborates
  the award identity and WINNER lettering. Participation remains provisional
  with unknown finish. Five retained responses match recorded hashes; six new
  observations bring the combined review candidate to 67. Publisher revisions
  2/3 retain both UUIDs and evidence, with no automatic candidates or market joins.
  The package checkpoint passed 32/34 initially; both affected corpus tests pass
  after timestamp/canonical-order corrections. Three selected app tests pass for
  the real OCR/choice/finish/Browse boundary and existing scanner regressions.
  Image URLs, production sync and pricing remain disabled; coverage, rights,
  further physical reconciliation and device acceptance remain open. See the
  [reviewed award evidence](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece unresolved-finish contract (2026-10-04; existing isolated worktree
  at `69c714f`): unverified publisher review printings can retain an empty finish
  list without inventing a normal/foil variant. Verified printings still require
  registered variants. Two new core tests cover stable regeneration, exclusion
  from automatic authority, invalid variant rejection and protected promotion.
  All 34 core/publisher tests pass; no app build was run for this package-only
  change. Real physical evidence and reviewed UUID allocation remain unfinished
  in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece collection-policy follow-up (2026-10-04; existing isolated worktree
  at `69c714f`): guarded commits now inspect blank-game history and inventory-only
  ownership, existing stores honor configured policy withdrawal, and backfill
  excludes unsupported rows/history. Local artwork overrides and removal survive
  relaunch without clearing unsupported synced legacy metadata. Simulator checks
  cover 66 distinct passing cases across one checkpoint and targeted follow-ups;
  initial failures were a retained-object rollback assertion and an import fixture
  that needed to enable its isolated container explicitly. Two artwork tests were
  rerun with their correct class selector. Plan links and diff whitespace pass.
  Remaining direct-save audit, physical reconciliation and mixed-client CloudKit
  enforcement stay open in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece broad market discovery (2026-10-04; existing isolated worktree at
  `69c714f`): inspected and adapted the owner's English catalog kit, retained 90
  paced TCGCSV responses from the Oct. 3 daily build, and generated 7,408 review
  rows across 87 groups. One empty presale inventory remains explicitly incomplete;
  DON!!, unnumbered and metadata-conflict candidates are retained outside exact
  numbered-card authority. Added 31 hashed stress market observations and a
  no-ownership candidate crosswalk (Shanks 7, Nami 10, P-001 Luffy 14 products).
  Private source thumbnails support seven illustration correspondences; Nami's
  market image is a placeholder. Recorded digital/footer discrepancies without
  asserting original physical footer, finish, exact UUIDs or market joins.
  Nine Python tests and 32 core/publisher tests pass; offline replay produces all
  four CSV/JSON outputs byte-identically, with a focused unchanged-mtime follow-up.
  No app rebuild or production enablement. See the [review evidence](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- Lorcana first slice (2026-10-04; existing `one-piece-integration` worktree at
  base `69c714f`, including uncommitted shared infrastructure): recalibrated the
  [implementation plan](docs/plans/lorcana_code_implementation.md) and implemented
  validated local print-family mappings, content-derived generations, conservative
  complete-footer recognition and generic incomplete lookup/recovery. Provider
  set codes remain independent from printed markers, premium numerators and promo
  tokens remain literal evidence, and unknown/cross-game ambiguity cannot borrow
  an exact physical identity. The focused simulator checkpoint passes 44 cases,
  including 13 new Lorcana tests. An initial project-ID collision was corrected
  before the successful checkpoint. Production registration, physical UUID/finish
  evidence, real corpus normalization, pricing and collection writes remain open.
  No full suite or physical-device/provider/CloudKit certification was performed.

- One Piece real source-review checkpoint (2026-10-04; existing isolated worktree
  at `69c714f`): retained exact response bytes for six official/Limitless pages
  externally, with SHA-256/timestamp manifests and 30 normalized observations in
  the [stress-source review inputs](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).
  Added bounded fail-closed normalization, preserving separate reprint appearances,
  provider aliases and incomplete discovery inventories. Eight parser/CLI tests
  and all 31 core tests pass. Publisher accepts the canonical-only unsigned review
  candidate with zero physical printings/automatic candidates; identical reruns
  preserve normalized outputs. No app build or wider scanner suite repeated.
  Real physical UUID allocation/reconciliation, permitted image evidence, rights,
  signing/delivery and collection sync acceptance remain open.

- One Piece compact picker (2026-10-04; existing isolated worktree at `69c714f`):
  replaced the verbose default with Pokémon/Magic-style header and short option
  buttons, bounded grid for long histories and Details on demand. Recovery uses
  the same concise labels; exact-printing/artwork safeguards remain. One batched
  checkpoint passed 37 cases; the affected label test passed a focused follow-up.
  Rendered header/contrast fixes received build-only verification. Final phone,
  tablet, large-text, footer and missing-artwork captures were inspected; native
  checks reached/selected fixture 61, skipped, and opened Details without choosing.
  These are component-fixture checks, not real catalog or ownership/sync readiness.
  See the [visual checklist](docs/plans/one_piece_printing_choice_visual_checklist.md)
  for evidence and open loaded-artwork/device/VoiceOver/owner acceptance.

- One Piece plan reconciliation and picker direction (2026-10-04; existing
  isolated worktree at `69c714f`, tracked and untracked changes reviewed): plans
  now reflect bounded picker mechanics and recovery validation already present.
  Existing picker checkpoint log records 52 passing selected tests; no tests or
  builds were run in this documentation-only pass. The owner rejected the verbose
  picker and requires the existing Pokémon/Magic header/short option-button
  format, with bounded scrolling for long printing histories. UX acceptance stays
  open. Retain Lorcana-relevant seams and prioritize compact picker plus a small
  real reviewed corpus and remaining write guards over optional extraction.
  Production data/rights, delivery, device/performance and CloudKit gates remain
  open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece recovery/identity follow-up (2026-10-04; existing isolated worktree
  at `69c714f`): retry-save after relaunch now revalidates evidence against the
  active catalog and asks for a printing again. One Piece live lookup, choice and
  retry share strict payload validation; incomplete local catalogs retain a
  retryable explanation. A single batched simulator checkpoint passed 138 of
  139 cases; a missing inventory entry in the new later-release fixture was
  corrected and its one-case follow-up passed. Passing evidence now covers all
  139 selected cases (29 One Piece, 94 scanner model, 16 recovery store), not a
  full-suite/device/provider/sync gate. Production support remains disabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece plan/code audit (2026-10-04; existing isolated worktree at detached
  `69c714f`, including tracked/untracked implementation): documentation-only
  review confirms the shared identity/runtime/local fixture architecture is on
  track, with production support disabled. Updated the
  [implementation ledger](docs/plans/one_piece_code_implementation.md) with a
  slice status matrix, prioritized picker/write/backfill/recovery/Browse gaps,
  missing real corpus and shared-host publication hazards, and a KISS sequence
  retaining the seams needed for later Lorcana. Reconciled stale no-implementation
  wording in the design/audit. No implementation changes or builds/tests in this
  pass; historical checkpoint counts remain dated evidence.

- One Piece uncataloged-number recognition checkpoint (2026-10-04; isolated
  worktree based on `69c714f`): registry-supported series recognize valid printed
  numbers independently of catalog membership. Missing numbers participate in
  frame ambiguity and remain incomplete/recoverable instead of creating owned
  printings. Unknown series remain excluded. One app build passed all 25 One
  Piece integration tests, including live unresolved retention without ownership.
  Clearer incomplete-catalog messaging, later-catalog recovery and picker/device/
  performance evidence remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece configured bootstrap checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): app registration can use a verified signed seed and
  dedicated configured keys/origin. Disabled mode omits the module;
  validation-only mode hides scan/Browse/write capabilities. Startup refreshes
  registered sources once per coordinator. One app build passed 61 selected
  tests; built plist/resource inspection confirms One Piece remains disabled
  with no endpoint, keys or production seed. Real reviewed data/signing/hosting,
  cold-start performance and independent sync policy remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece publication preparation checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): signing binds reviewed canonical payload hashes to pinned
  public keys and verified revision baselines, with explicit initial bootstrap.
  Publisher sign/verify produces identity/change manifests and protects inputs
  and existing artifacts. Optional workflow signing prepares artifacts without
  deploying; production configuration remains disabled and unprovisioned.
  The package checkpoint passed 29 cases; the initially failing CLI case passed
  after focused discovery/write/idempotency corrections, giving passing evidence
  for all 30 cases. Workflow YAML/shell, ledger links and whitespace checks pass.
  Real reviewed data/keys/rights, hosting publication, bootstrap and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece signed update transport checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): generic bounded HTTP envelope transport supports conditional
  fetch, cancellation, redirect refusal and transient retries. One Piece refresh
  coalesces callers, validates or durably activates signed candidates, retains
  last-known-good data on rejection and clears rejected conditional validators.
  Disabled rollout makes no request. One app build passed 43 selected tests.
  Production URL/keys/seed/publication, bootstrap scheduling, legacy transport
  extraction and provider/device/sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece shared-screen runtime checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): Collection and Settings now receive the app runtime and
  construct their normalizers from its adapters/capabilities/activation sources.
  Settings resolves current import adapters before acquiring the exclusive
  ownership lock and passes them into the isolated CSV actor. One app build
  passed 70 selected tests, including a signed revision activation followed by
  importing and enriching a newly introduced exact printing UUID. No rendered
  UI/device/provider evidence is claimed. Legacy adapter extraction, remaining
  mutation/import policies, production data/update publication and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece collection transaction guard checkpoint (2026-10-04; isolated
  worktree based on `69c714f`): container-scoped game write policy now reaches
  scanner writers and explicitly configured CSV transactions. Common commit
  guards cover saved/staged ownership and history changes; unsupported rows
  reject acquisition, quantity/removal/undo/restore/correction/bulk deletion.
  Quantity repair uses the guarded commit and history backfill skips unsupported
  rows. One build passed 63 selected tests, including four new guard cases;
  56 existing ownership/history and graded/sealed tests passed without rebuilding.
  Shared-screen runtime propagation, remaining metadata/ledger-only policies,
  production data and mixed-client sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece exact import/normalization milestone (2026-10-03; isolated worktree
  based on `69c714f`): registered game import adapters and runtime factories;
  CSV row validation/headless import preserve exact UUID/finish/ownership keys.
  One Piece accepts verified raw printing identities, with specific failures
  for unsupported finishes and conflicting evidence; no number/name inference
  allocates a printing. Normalization keys include game, item kind and exact
  attached ID; unsupported/gated rows receive no metadata/watermark writes.
  Unknown non-Pokémon first-edition CSV finishes retain their own identity.
  The batched app checkpoint passed 75 tests; the focused identity follow-up
  passed 21. Project parsing, ledger links and whitespace checks pass. Runtime
  propagation into shared screens, complete mutation guards, legacy adapter
  extraction, alias/ambiguous/manual and graded/sealed import policies remain
  open. App defaults still omit One Piece; production data/publication, rights,
  mixed-client sync, rendered/device/performance and release gates remain open.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece local Browse milestone (2026-10-03; isolated worktree based on
  `69c714f`): added game-owned Browse adapters/runtime dispatch, verified English
  product/card projections, local search/details and generation-bound pagination.
  Product appearances share one physical UUID; exact ownership and physical
  completion cannot borrow another printing's matching number/set label.
  Runtime catalog updates invalidate old details/summaries. Browse enumeration
  uses injected game capabilities; One Piece requests no sealed provider setup
  and its raw/graded additions remain gated. The batched app checkpoint passed
  75 tests; 38 affected legacy ownership/completion tests passed without rebuilding;
  one focused capability-state follow-up passed. Project parsing, ledger links
  and whitespace checks pass. Import/export/normalization, complete mutation
  guards, production data/publication, rendered UI/performance and sync/device
  gates remain open. App defaults still omit One Piece. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece signed storage/live activation milestone (2026-10-03; isolated
  worktree based on `69c714f`): extracted shared verified current/previous
  storage while retaining Pokémon/Magic contracts and revision policies; added
  bounded One Piece signed slots, durable transition validation and activation.
  Generic runtime activation now updates scanner/catalog/variant snapshots and
  recovery. Explicit retry revalidates printed evidence against the new generation;
  saved choices and old lookup completions cannot silently cross generations.
  Initial loads share one task and slow subscribers retain only the newest event.
  The batched app checkpoint passed 57 selected cases; the follow-up passed nine
  targeted concurrency, stale-choice and legacy recovery cases. Remote updates,
  production seed/data/publication, Browse/import, complete mutation guards and
  mixed-client sync/device gates remain open. One Piece remains disabled in app
  bootstrap with pricing and shared-collection writes off. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece local scanner milestone (2026-10-03; isolated worktree based on
  `69c714f`): added pinned-key signed-release verification, an immutable indexed
  One Piece registry, registry-derived numbered recognition, game-owned catalog
  and variant adapters, and runtime recognizer installation between frames.
  Number recognition leaves language unconfirmed; English physical choices are
  explicit, and incomplete/conflicted scope cannot manufacture automatic
  uniqueness. The scanner commit boundary now checks collection-write capability;
  One Piece remains scan-only with pricing and shared-collection writes off.
  Focused app build/tests passed all 222 cases. Synthetic signed fixtures
  exercised recognition, printing/finish ordering, separate physical copies in
  an in-memory collection, stale choices and write-gate refusal. Package tests
  passed all 27 cases including signature failure checks. Project parsing,
  ledger links and whitespace checks pass. Production seed/data, current/previous
  storage, activation/recovery, full mutation guards and sync/device gates remain
  open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece catalog-core milestone (2026-10-03; isolated worktree based on
  `69c714f`): added OnePieceCatalogCore contracts, durable-registry builder,
  reconciliation/index validator, protected change classification, market quote
  invalidations, normalized provider captures and a local unsigned publisher.
  Synthetic stress cases preserve every printing, identical-art reprints,
  product appearances, reviewed alias/supersession/split/merge history and exact
  SKU qualifiers; they do not claim vendor counts or production completeness.
  The final batched package checkpoint passed all 25 tests, including publisher
  baseline/input/symlink protection. Project parsing, ledger links and whitespace
  checks pass. No app build was run for this package-only checkpoint. Real
  ingestion/data review, signed activation, One Piece runtime/OCR and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece printing-picker/recovery milestone (2026-10-03; isolated worktree
  based on `69c714f`): generic catalog choices now open a game-neutral picker;
  selected printings proceed to finish resolution with the original catalog
  timestamp. Dismissed generic encounters retain separate recovery rows and
  generation-bound candidate lists. Reload keeps absent game modules read-only;
  supported recovery selections revalidate catalog membership and identity.
  Scanner/compatibility checkpoint passed 116 tests; the batched recovery
  checkpoint passed 19 tests. Full D/E migration, bounded live picker layout,
  production One Piece catalog/OCR, and sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece execution-priority clarification (2026-10-03): the owner plans
  Lorcana next, so retain shared identity, recognition, printing-choice/recovery
  and pricing-capability boundaries. Prioritize a complete One Piece local
  scan-to-collection/relaunch flow over finishing all legacy adapter migration
  or shared transport extraction first. Lorcana implementation is not added to
  this goal; the full One Piece checklist and production gates remain intact.
  This is a sequencing decision, not additional implementation or test evidence.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece generic resolved-card/catalog foundation (2026-10-03; isolated
  worktree based on `69c714f`): ResolvedCatalogCard replaces the closed downstream
  card enum, with a source alias and legacy provider projection preserving
  existing keys, metadata, treatment and pricing behavior. Generic printing
  keys remain stable across variant-count changes. Runtime catalog adapters
  expose resolved/printing-choice/incomplete outcomes, retain provenance and
  payload timestamps, validate generation and candidate membership, and keep
  different copies' printing selections independent. Expanded simulator
  regression passed 333 cases; final scanner/variant/pricing/fallback regression
  passed all 248 cases. Project parsing, ledger links and diff whitespace checks
  pass. Scanner choice/recovery UI and existing catalog providers still need
  migration; no One Piece production or sync/provider gate enabled. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece pricing adapter extraction (2026-10-03; isolated worktree based on
  `69c714f`): Pokémon/Magic module adapters now own exact-provider refresh and
  Pokémon bulk fallback. Runtime injection routes scanner Price Check through
  the generic pricing service; absent capability/adapter stops foreground
  fallback with a distinct unsupported-game state. Stored-card fallback and
  background/camera graded paths check capabilities before provider work.
  Expanded simulator regression passed 286 cases; the final slab capability
  change passed a focused 45-case rerun. Tests cover exact printing/variant
  forwarding, missing adapters, zero bulk/vendor requests and no synthetic
  price/product observations for unsupported games. Project parsing, ledger
  links and diff whitespace checks pass. The architecture gate still rejects
  catalog/Browse switches; background provider dispatch, generic resolved cards,
  and the remaining full-plan slices are unfinished. No One Piece production,
  provider, device or CloudKit gate enabled. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece runtime/variant foundation (2026-10-03; isolated worktree based on
  `69c714f`): app bootstrap and ContentView now use the registered runtime
  container, retaining existing coordinator behavior through an explicit legacy
  bridge. Game-owned policies supply variants and generic VariantLock options;
  scanner menus and lock validation use the injected registry. Final simulator
  runs passed 136 runtime/scanner/variant cases, all 166 Browse cases across four
  classes, and two screen-construction cases. Added the strict game-boundary
  audit: shell syntax passes, but existing catalog/Browse/pricing switches still
  fail its architecture gate pending adapter extraction. Full scope remains
  active; no One Piece production support, device/provider or sync gate enabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece recognition adapter foundation (2026-10-03; isolated worktree
  based on `69c714f`): primary recognition dispatches through registered adapters
  with explicit same-game/cross-game ambiguity and soft fallback rejection.
  Magic spatial rejection moved behind its adapter. Added semantic catalog
  generation to identifiers/snapshots; confirmation cannot merge generations,
  while suppression remains stable across activation. Focused simulator runs
  passed 99 recognition/historical cases and 107 parser/game/recovery cases.
  App bootstrap/runtime extraction and historical fallback context migration
  remain unfinished; One Piece catalog/support remains disabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece generic identifier/recovery foundation (2026-10-03; isolated
  worktree based on `69c714f`): replaced the closed scanner identity with generic
  canonical fields and separate suppression identity, retaining a typed
  Pokémon/Magic migration bridge. Added versioned recovery snapshots, legacy
  decoding, read-only future-game/version handling, original unknown-field
  retention, and malformed-neighbor isolation. App build passed; 120 unique
  focused simulator cases passed across final per-suite runs. One new test
  initially expected an empty plan instead of the existing `noCards` rejection;
  corrected it and reran all 25 game/recovery cases successfully. Full runtime,
  recognition, printing, catalog, provider, and rollout work remains incomplete.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece implementation foundation (2026-10-03; isolated worktree based on
  `69c714f`): started open game identities, capability enumeration, explicit-game
  CSV preservation/write refusal, and unsupported JustTCG mapping guards. Eight
  isolated Swift identity/capability checks passed. Registered app regressions
  have not run; simulator compilation still fails at unknown-game unresolved
  rehydration pending the generic identifier/recovery slice. Full implementation
  remains in progress. No CloudKit, provider, device, or release readiness claim.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- Uncommitted-change review follow-up (2026-10-03; working tree against
  `dd2a1e3`): tightened edition quote matching by size/language/stamp and physical
  finish; validated catalog recovery finishes, retained raw vintage edition
  choice, and preserved validated slab edition evidence. Added five regression
  cases using existing pricing/resolution paths. Corrected offline support copy
  and historical F2 status wording. All 418 affected simulator cases passed
  across the final per-suite runs, and the Pokémon package passed 74/74. Two
  initial new-fixture decoding failures were corrected before the pricing rerun.
  Relative links and `git diff --check` passed. Artifacts are on the external
  SSD; no new full-suite, device, provider, or release acceptance is claimed.
  See the [review evidence](docs/plans/october-production-refinement-review-plan.md).

- Privacy/support page review (2026-10-03; working tree at `dd2a1e3`): found
  existing Markdown drafts and in-app link surfaces. Updated the drafts to
  Scanstash and the owner-confirmed Info@scan-stash.com contact, corrected partial
  collection deletion, and added photo/permission, provider/authentication,
  support-data, export, and privacy-request disclosures. Added
  [publication checks](docs/legal/README.md) against Apple's current 5.1.1 and
  Support URL requirements. Documentation only; operator details, routine support
  retention, provider safeguards, live hosting, and empty Release URL settings
  remain open. No deployment or App Review approval is claimed.

- Production refinement slice A / F1 (2026-10-03; uncommitted working tree on
  `fix/october-review-boundaries` at `dd2a1e3`): both pricing paths now apply the
  same persisted fifteen-minute cooldown to headerless transient/unrecognized
  429s, honor numeric/date retry headers, and preserve next-day rechecks for
  explicit quota errors. Request ceilings and interactive reserves remain;
  duplicate parser/reset helpers were removed. Six new mocked-response cases
  cover both paths, persistence, cross-lane blocking, and expiry. The complete
  JustTCG contract and product fallback classes passed 121/121 on a disposable
  iPhone 17 Pro / iOS 26.5 simulator with normal signing; existing simulator data
  was preserved. Build artifacts, log, and result bundle use the external SSD.
  Monthly-period accounting and other slices remain open; no full-suite,
  physical-device, live-provider, or release acceptance is claimed. See the
  [production refinement review plan](docs/plans/october-production-refinement-review-plan.md).

- Production refinement review documented (2026-10-02;
  `fix/october-review-boundaries` at `73898e8`): recorded the repository-wide
  source review's ten additional findings, minimum remedies, confidence/risk/
  complexity, acceptance cases, and independent implementation slices in the
  [production refinement review plan](docs/plans/october-production-refinement-review-plan.md).
  Linked the plan from the documentation map and reconciled prior authority
  boundaries in the documentation audit. Existing uncommitted centering/code/
  test/script changes were preserved; overlapping export work needs revalidation.
  This is documentation only, not implementation or fresh app/runtime evidence.

- Browse supplemental quote retention (2026-10-02; uncommitted working tree on
  `fix/october-review-boundaries` at `55b2d40`): failed supplemental refresh now
  preserves cached Pokémon prices and their provenance. The regression covers
  fresh and expired details plus replacement by a successful missing quote.
  Focused simulator pricing/Browse tests pass 30 cases, and the existing shared
  detail waiter cancellation case passes separately. Build caches, results, and
  command logs are on the external SSD; full-suite and device/provider gates
  remain unchanged. See the [refinement implementation plan](docs/plans/october-refinement-implementation-plan.md).

- October refinement review and plan (2026-10-02; `fix/october-review-boundaries`
  at `55b2d40`): validated the ten supplied follow-up findings against current
  source, tests, and configuration; documented minimal slices, regression cases,
  centering test/confirmation-contract reconciliation, owner-controlled URL
  dependency, and measurement-only targets. No application code changed and no
  new build, test suite, simulator/device capture, provider, or Photos check ran.
  Prior centering failures remain historical evidence, not a current rerun.
  See the [refinement implementation plan](docs/plans/october-refinement-implementation-plan.md).

- October review boundary fixes (2026-10-01–02; `fix/october-review-boundaries`,
  `cdd60e1` → `248a61d`): committed slices 1–10 separately. Checked grade
  conversion, export-container ownership, unrestricted Needs attention
  retention, certless Pokémon graded print-run identity including CSV and
  price preflight, interrupted recognition and duplicate-prompt recovery,
  Browse filter retention, stable collection destinations, catalog activation
  retries, artwork failure/cache behavior, and essential Dynamic Type text.
  Inventory ledger, serialized fresh-context writes, conservative matching,
  and explicit ownership confirmation remain in place. Focused simulator
  selections passed 14, 17, 40, and 124 tests; the final build-for-testing passed.
  The full suite after slice 4 executed 1,732 tests with 7 skipped and 25
  assertion failures across 10 centering cases. The required full follow-up
  after slice 5 executed 1,743 tests with 7 skipped and 25 failures across the
  same 10 centering cases; no other test cases failed. Scoped default and
  largest-text screenshots were inspected; existing wider contrast/toolbar
  risks and remaining manual share/save acceptance are recorded. The export
  interaction check reached the photo picker with synthetic fixtures, then
  native UI control was blocked by the locked Mac. Build and
  result artifacts use the external drive; an isolated task simulator preserves
  existing simulator data. No physical device was connected, so slice 11 and
  its conditional slice 12 remain pending, without performance or release claims.
  No push or PR. See the
  [October review ledger](docs/audits/october-review-remediation.md).

- Two-set TCGCSV pricing fallback (2026-09-30; working tree based on `a707356`):
  added reviewed exact TCGplayer product mappings for all 158 `30th` and 30
  `30th-c` cards and one shared device-local daily feed client. Browse sorting
  and card details, scanner background quotes, Price Check, and collection
  refresh now use the exact Holofoil quote when existing USD evidence is absent,
  independently of JustTCG credentials/settings or legacy secondary-set matching.
  Product ID, group, name, printed number, and finish are validated; unrelated
  products and other finishes cannot supply a price. Daily downloads coalesce,
  persist atomically, preserve original retrieval time for unchanged exports,
  and back off after failures. Export timestamps are not market-price timestamps.
  Reviewed finish metadata corrects upstream generated Normal flags, including
  old Browse slots. Automatically assigned collection finishes can be corrected
  and priced in one refresh with existing ledger/ownership safeguards; explicit
  user choices remain protected. Recent legacy misses cannot suppress trying
  the new source after upgrade. Registered the new service/mapping/test files
  and recorded JSON fixture in their Xcode targets. The final normally signed
  iPhone 17 Pro / iOS 26.5 focused selection passed 322/322 (21 new TCGCSV tests);
  result bundle: `/private/tmp/cardscanner-tcgcsv-verified.xcresult`. The unchanged
  production feed client, exercised on macOS with minimal value-type adapters,
  validated all 188 quotes against live build `2026-09-30T20:05:12+0000`.
  No external SSD was available, so generated build data used `/private/tmp`.
  No full suite, physical-device run, catalog signing, deployment, commit, or
  push was performed. See the
  [current pricing contract](docs/plans/browse_pricing_coverage_plan.md).

- Classic Collection authority review corrections (2026-09-30; working tree
  based on `7db2e18`, reviewing `82d0611`): added the missing bundled main-set
  `30th` / `30C` / 128 scanner definition, tested all 30 bundled membership
  rows against production publisher input, used parent `30C` display metadata
  for offline and live membership results, and narrowed stale-cache eviction
  to one key with a same-set persistence regression. Historical identifiers
  already have no persistent key in this checkout, so the stale-cache branch
  is defensive. All 30 numbers agree with rendered TCGplayer listings and all
  provider IDs/canonical names agree with TCGdex; the evidence explains LEGEND
  and the provider's `Palkia` name versus marketplace `Palkia LV.X`. A publisher
  test confirms explicit revision 11 replacement corrects revision 10 while
  omitted membership preserves authority. The focused iPhone 17 Pro / iOS 26.5
  simulator run passed 50/50; focused publisher tests passed 3/3. With no
  external SSD mounted, generated build data used `/private/tmp`; result bundle:
  `/private/tmp/cardscanner-review-20260930/catalog-verified.xcresult`.
  First-launch Classic resolution remains unavailable offline until its
  checklist downloads; the new bundled-snapshot test verifies fail-closed
  behavior. No physical-card inspection, signing, deployment, archive, or full
  suite was performed. See the
  [membership evidence and correction boundary](publisher/classic-collection-evidence.md).

- Pokémon USD price gap validation (2026-09-26; `claude/pokemon-price-feed-gaps-kpxv5w`
  after `23566a0`): source-data audit only, no pricing code changed. TCGdex
  `cards-database@a9bf1ef` omits the set-level TCGplayer group for `30th` and
  `30th-c`, so its server never prices either set. Its list and GraphQL
  endpoints expose no bulk pricing (Phase 6.0 outcome B). Five bundled
  checklist slots are phantom: Perfect Order 019/024/028/050 Normal and Chaos
  Rising 122 Holo. Live price hosts were unreachable from the audit
  environment, so live counts remain open. Proposal:
  [`Pokémon USD price gap plan`](docs/plans/pokemon_usd_price_gap_plan.md).

- Scanner recognition remediation review corrections (2026-09-25; working tree
  based on `main@6747859f5e8c`): fixed the async candidate-list writeback by
  looking rows up again by ID, kept Needs attention rows until a successful
  commit or a verified existing collection entry, and carried slab identity
  through candidate choice. Exact chosen Pokémon printings now resolve from the
  offline checklist before broad historical matching. Cleanup is conservative
  for shared denominators and ignores candidate suggestions; historical rows
  are scoped across sessions, while a list-originated retry updates its source
  row by ID across that boundary. Persistence preserves records that an early
  registry cannot yet rehydrate, deduplicates row IDs, waits for ordered saves
  before catalog reloads, and retains Magic language. Retry-save checks the
  exact collection entry before routing, and Price Check/retry messages now
  reflect what actually happened. Same-number historical title evidence starts
  fresh after its TTL to prevent OCR from carrying over to a second card. The
  app-scoped Browse catalog is passed into Needs attention search, and Magic
  no-confirmed-match rows can retry lookup. The focused iPhone 17 Pro / iOS 26.5
  Simulator selection passed 229/229 tests with 0 skipped, including scanner,
  parser/latch, historical catalog, Pokémon catalog, retry-bound, and unresolved
  store coverage. Result bundle: `ReviewFixes-final-r3-2026-09-25.xcresult`
  under the external SSD's
  `CardScannerBuild/ScannerRecognitionReview-2026-09-25/Results/` folder. The
  full non-centering suite was not rerun for this follow-up; its 1,561 pass / 7
  skipped result is from the preceding source-review snapshot. Physical
  Ascended Heroes recognition, failure/relaunch actions, and the Instruments
  comparison remain open; simulator evidence does not establish device
  readiness. The plan records the review decisions in
  [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Scanner recognition remediation review follow-up (2026-09-25; working tree
  based on `main@a55f4df83e5cab`): completed a source-to-plan audit and fixed
  several correctness gaps. Denominator ownership now includes active registry
  official counts as well as checklist overrides. Same-key unresolved rows keep
  unioned evidence and candidates while updating to the latest failure reason;
  merging a direct set-code read keeps inferred-name validation disabled, and
  only rows first created in the current session count in its summary. The
  focused iPhone 17 Pro / iOS 26.5 simulator selection passed 227/227 tests;
  the full non-centering suite passed 1,561 tests with 7 skipped and 0 failures.
  Result bundles are `Focused-final-2026-09-25.xcresult` and
  `Full-noncentering-2026-09-25.xcresult` under the external SSD's
  `CardScannerBuild/ScannerRecognitionReview-2026-09-25/Results/` folder.
  Physical ASC-stack recognition, forced-failure/relaunch actions, and the
  Instruments comparison remain open; these simulator results do not establish
  device readiness. The current merge and inference behavior is described in
  [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Scanner recognition and Needs attention remediation (2026-09-24; working tree
  based on `main@a55f4df83e5c`): implemented denominator-owned modern Pokémon
  set inference with a unique fuzzy title agreement gate, Pokémon footer-code
  spacing support, historical OCR matching and evidence merging, scoped latch
  retries, and post-commit label OCR. Collection failures now file immediately
  to the capped local unresolved-scan store, survive Scan-tab departures and
  relaunch, expose candidate/retry/save/search/dismiss actions, and clear when a
  matching card is resolved or committed. The record also preserves graded
  label identity evidence so a relaunch cannot downgrade a slab retry into a
  raw-card add. Collection lock-wait signposts and 25-patch writer batches are
  included. Focused iPhone 17 Pro / iOS 26.5 simulator suites pass 225/225; the
  full non-centering suite passes 1,559 tests with 7 skipped and 0 failures.
  The injected unresolved-store suite passes 5/5, including corrupt-file,
  50-row-cap, unknown-set read-only, and slab-evidence round trips. Result
  bundles are `Test-TradingCardScanner-2026.09.24_22-27-41--0600.xcresult`
  (focused) and `Test-TradingCardScanner-2026.09.24_22-28-18--0600.xcresult`
  (full non-centering), under the external SSD result folder.
  The plan's “9 known pre-existing failures” referred to the superseded first
  2026-09-23 snapshot; the later same-day baseline at the top of this file had
  0 failures, and the current rerun also has 0. Result bundles are under the
  external SSD's `CardScannerBuild/ScannerRecognitionDerivedData/Logs/Test/`
  folder. The physical ASC stack, forced-failure/relaunch flows, and Instruments
  comparisons remain open; simulator evidence is not device readiness. Details
  are in [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Systems-review pass-2 follow-up (2026-09-23; working tree based on
  `main@c1837b2`): fixed the refresh/migration-gate deadlock, made refresh
  suspension clear to idle when no work remains, prevented a cancelled
  background caller from starting a refresh after shared migration completes,
  resumed CSV imports by deterministic ledger operation ID after rows are
  rekeyed, preserved all-again CSV salts across interruption, and kept graded
  price identity promotion canonical across repeated passes. Added tap guards
  for graded/sealed adds, limited identity pauses to actual promotions,
  required a saved quantity before detail edits, and moved launch history
  backfill waits off the main thread. Native-currency evidence remains visible
  while being excluded from USD valuation and sorting. Updated the stale slab,
  currency, chart-envelope, and storage-copy assertions. Final non-centering
  iPhone 17 Pro / iOS 26.5 simulator run: 1,510 tests executed, 7 skipped, 0
  failures. The separate Debug simulator build succeeded. Centering tests were
  excluded. Physical-device/background expiration, large-fixture signposts,
  and the manual flows in [`RF-12`](docs/plans/release_followups.md#rf-12--collection-write-refresh-and-lifecycle-acceptance)
  remain open.

- Historical first-pass checkpoint (2026-09-23; superseded by the follow-up
  evidence above): Systems-review pass-2 remediation (working tree based on
  `main@c1837b2`): implemented the storage retry marker, monotonic price
  freshness, Magic migration trigger, USD-only portfolio valuation, server
  clock cutoff, and unproven-readiness local preflight; added the fresh-context
  `CollectionWriteSerializer`, guarded refresh-row patches and resumable pass
  suspension, resumable/idempotent CSV import, foreground/background refresh
  ownership, relevant-save filtering, and per-context artwork cleanup with a
  launch orphan sweep. Added concurrency, lifecycle, structural-refresh, CSV,
  detail-deletion, and artwork sweep coverage, plus the one-shot Debug
  first-container-failure launch argument. The non-centering iPhone 17 Pro /
  iOS 26.5 simulator run executed 1,520 tests: 1,504 passed, 9 failed, and 7
  skipped. Those same nine failures occurred in the Phase 0 baseline (1,444
  passed, 9 failed, 7 skipped); no new failure remained after updating the
  Magic migration test to re-fetch through a fresh context. The unchanged
  failures are `ScannerViewModelTests.testCertificateReadAfterCertlessSlabCommitRefinesTheSameCollectionEntry`,
  `PrivacyAndSupportSurfaceTests.testCollectionStorageStatusDistinguishesTransientLocalFallback`,
  `CardLatchTests.testDifferentConfirmedCertificateOnSameFooterCanRelatchQuickCopySwap`,
  `PortfolioReconciliationTests.testFastAndAuthoritativeValuationAgreeAcrossCurrencyAndInvalidationTransitions`,
  `CardLatchTests.testHeldSlabIgnoresGradeFlickerAndEnrichesCertificateWithChangedCardText`,
  `PriceHistoryChartModelTests.testNearFlatExpensiveHistoryUsesMinimumVisualEnvelope`,
  `OpusImplementationPlanTests.testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically`,
  `OpusImplementationPlanTests.testREQ006NonUSDLocalPriceRecordIsCheckingButStillVisible`,
  and `OpusImplementationPlanTests.testRM006NonUSDTransitionAcrossDayBoundaryKeepsCurrentAndReplayAligned`.
  The targeted
  storage suites passed 56 tests with 1 skipped. The Debug simulator build
  succeeded, and the first-open injection reached Retry then opened the
  existing collection. No centering tests ran. OS background expiration,
  device timing, large-fixture signpost comparison, and the remaining manual
  flows remain open in [`RF-12`](docs/plans/release_followups.md#rf-12--collection-write-refresh-and-lifecycle-acceptance).

- Raw / Slab scanner review follow-up (2026-09-23; working tree based on
  `main@30bd84e`): fixed held-slab duplicate saves by accepting only same-grade
  certificate refinement or a distinct confirmed certificate for a copy swap,
  and rekeyed the latch when cert evidence arrives. Slab label OCR now requires
  a matching footer and runs at most every 0.5 s before confirmation and every
  2.0 s afterward; one footer miss ages the 2-of-4 commit window, and a single
  footer-key misread preserves label progress. Raw post-commit reads require
  the saved footer identity. Restored the missing-row graded-price fallback,
  FIFO evidence eviction, no-key guidance, and wider footer ROI. Simulator
  `build-for-testing` succeeded; 11 selected non-centering regression tests
  passed on iPhone 17 Pro / iOS 26.5. No centering tests ran, and the earlier
  full-suite failures were not rerun.

- Explicit Raw / Slab scanning mode implementation (2026-09-23; working tree
  based on `main@30bd84e`): added the session-only mode picker, separate raw
  and slab recognition paths, slab-gated commits, post-save raw-to-graded
  conversion, and asynchronous graded price binding. The focused iPhone 17 Pro
  / iOS 26.5 Simulator selection passed 166 tests with 0 failures. The broader
  selection excluded all seven centering-specific test classes at the user's
  request and executed 1,445 tests: 1,427 passed, 7 skipped, and 11 failed;
  the failure names are recorded in
  [`explicit-raw-slab-scanning-mode.md`](docs/plans/explicit-raw-slab-scanning-mode.md).
  Generic iOS build and simulator build/run succeeded. The menu and Slabs pill
  were visually confirmed; the simulator back camera is unavailable, so live
  framing and recognition remain device checks.

- Explicit Raw / Slab scanning mode plan (2026-09-23): added
  [`docs/plans/explicit-raw-slab-scanning-mode.md`](docs/plans/explicit-raw-slab-scanning-mode.md)
  word for word as provided. Updated the documentation map and audit to identify
  it as the current proposed scanner architecture, and marked the archived
  scanner workflow review's conflicting slab auto-detection and blocking-price
  recommendations as superseded. Documentation only; no implementation or
  verification claims were added.

App-review follow-up fixes (2026-09-22): Settings opened from Scan now releases
the scanner's session-wide bulk interval and reacquires it after dismissal;
the sheet cannot close through Done or a swipe while import/delete owns the
exclusive token. Fallback eligibility is independent from price-observation
storage: identity-confirmed cards with no catalog quote can reach JustTCG while
`.unavailable(nil)` is still never persisted as an observation. A pending
forced retry survives same-collection coalescing, re-fingerprints after the
active pass, and clears if fallback is disabled. Deletion copy now states that
removal activity, price records, and Value History stay on-device. The focused
iPhone 17 Pro / iOS 26.5 Simulator selection passed 4/4 tests; same-collection
live-toggle timing and device behavior remain unverified.

App-review remediation worktree (2026-09-22): implemented session proof
retention across automatic, Add Another, held-repeat, and undo flows; kept
unqueried prices out of persistence while making fallback eligibility explicit
for identified catalog cards; bounded unpriced, missing-artwork, and
no-supported-provider automatic retries; made exact-row
catalog enrichment fill-only while retaining canonical normalization for
synthetic CSV rows; skipped CloudKit account probes while restoration readiness
is unproven and reused the matching active local container; enabled locked
background access to small metadata files with a privacy-policy disclosure;
delivered store notifications on the main run loop; and moved collection
deletion to a model actor with mutually exclusive import/delete coordination.
The affected iPhone 17 Pro iOS 26.5 simulator selection passed 99 tests with 1
data-protection-attribute test skipped because Simulator exposes no such
metadata. The separate delete-actor integration test passed 1/1. A wider
intermediate normalization run exposed and led to a fix for CSV set-code
canonicalization; that broader run also reported a Cardmarket test expectation
that conflicts with the current `CardPricing` implementation. The full suite, locked-device behavior,
physical scanner stack, actual privacy/support URLs, archive/TestFlight,
provider behavior, and release status remain open. See
[`app_review_fix_plan.md`](app_review_fix_plan.md) and
[`docs/plans/documentation_audit.md`](docs/plans/documentation_audit.md).

Browse pricing coverage Stage 4A (2026-09-22): implemented the revised
`browse_pricing_coverage_plan.md` Stage 4A slice. Browse now has a separate
device-local, per-set `BrowsePriceHistoryStore` under Application Support with
atomic writes, corrupt-file isolation, excluded-backup storage, 90-day
provider-day retention, versioned finish descriptors, restricted USD market
sources, and UTC/provider timestamp normalization. Existing Pokémon bulk and
TCGdex normalized price paths feed history without changing current-price
behavior; Magic uses a 24-hour Scryfall bulk-dataset stamp and labels that day
as approximate. Added the Browse detail chart with independent gap segments,
history diagnostics, migration coverage, and 104 focused history/Browse/pricing
tests passing on the iPhone 17 Pro iOS 26.5 simulator. The full external-SSD
baseline after the stale test compile repair was 1,442 passed, 18 failed, and 6
skipped; remaining failures are pre-existing centering, fixture, Keychain
environment, and legacy pricing-expectation failures. Phase 6.0 remains
unresolved because the current TCGdex service has no supported set-level
pricing response; pokemontcg.io remains authoritative. Stage 4B remains
disabled, and no provider, device, CloudKit, or release-readiness claim is
made.

Browse Pokémon pricing join/fallback hardening (2026-09-22): implemented the
attached follow-up plan. Bulk set requests now resolve TCGdex ids through the
existing conservative secondary-set matcher, cache the mapping, and decline
ambiguous/unresolved joins. Bulk card keys are canonicalized as
`<tcgdexSetID>|<localNumber>` so unpadded pokemontcg.io payloads join padded
TCGdex summaries. Pokémon fallback work is one card per six-wide worker slot
with incremental progress; the browse banner now separates unresolved cards
with Retry from resolved cards with no USD quote. Bulk requests use the
existing transient retry budget and have injectable recorded-response seams.
The app target builds cleanly with `CODE_SIGNING_ALLOWED=NO`. The test target
remains blocked before execution by the pre-existing missing
`CardCenteringMeasurement.confirmManualPlacement()` references in
`CenteringExportTests.swift:941` and `OpusImplementationPlanTests.swift:2434,
2506`; no provider, device, CloudKit, or release-readiness claim is made.

Browse pricing coverage stages 1–3 (2026-09-22): completed the USD-only
catalog rule and Settings coverage-gap diagnostics, persisted Magic page price
maps, added cached per-set Pokémon USD bulk pricing with exact-finish mapping
and per-card fallback, removed the 400-key prefetch cap, and made Browse price
loads queueable/retryable with a terminal “no USD price” state. Added focused
regression coverage for cache persistence, finish isolation, and one bulk
request per set. The app target builds cleanly; the test target remains blocked
by the pre-existing `CenteringExportTests.swift:941` reference to the missing
`CardCenteringMeasurement.confirmManualPlacement()` API. Stage 4 remains behind
the written redistribution-licensing gate; Stage 5 history remains pending.

Automatic set artwork on new-set release (2026-09-21): implemented the
zero-official-count browse-only admission path, 448 KiB publisher payload guard,
status/MIME/body artwork probe, gated derived-parent artwork, optional
pokemontcg.io/Scrydex set and card-art enrichment with whole-directory
fail-closed matching, signed descriptor card-art fallbacks, and app preference
for published fallbacks while preserving the snapshot fallback. PokemonCatalogCore
passes 54/54 tests and the fixed-timestamp offline publisher validation is
repeatable. A clean iOS test build is currently blocked by an unrelated existing
centering test/source mismatch (`confirmManualPlacement` is referenced by a test
but absent from the current `CardCenteringMeasurement` source); the app source
build itself completed successfully. No physical-device, provider, or release
readiness claim is made.

Centering remediation checkpoint (2026-09-20, current working tree): followed the required
order without changing contract thresholds. Formalized the ten-image `HOLDOUT-INTERIM` split
with a machine-readable `holdoutFreeze` block, kept its final REQ-040 gate open, and redirected
centering diagnostic writers to simulator temporary storage (or the explicit
`CENTERING_DIAGNOSTIC_OUTPUT_ROOT`) instead of tracked review paths. Implemented the registered
Pokémon/Magic back-template branch using observed border registration, then the separate
front-bottom art-window candidate generator with role-tagged alternatives and deferred joint
selection. Verification passed 4/4 focused manifest/source/semantic/outer checks and 1/1 REQ-042
ledger diagnostic; the temporary ledger measured 34/40 outer and 34/36 gradeable inner edges,
with remaining misses at IMG_0352 left and IMG_0780 right. All five development backs selected
the registered branch and IMG_0782 remained `none`/declined. The public L1 accuracy test still
failed with 53 assertions, so accuracy, metamorphic invariants, latency, final holdout
generalisation, joint selection, and physical-device gates remain open. The redirected REQ-041
profile passed 1/1 over 20 analyses with 2.7409/3.2918 s median/max wall time; the 0.80/1.50 s
budget remains unmet. No tolerance was loosened.

Centering remediation follow-up (2026-09-21): gated the discarded front-bottom candidate
generator call to DEBUG, then ran a same-session ten-fixture A/B on the pinned iPhone 17 Pro /
iOS 26.5 simulator. Without/with generator inner-generation medians were 0.7869/1.0085 s and
wall medians were 2.5304/2.7284 s; Release no longer executes that observational work, but the
0.80/1.50 s contract remains open. Added diagnostic-only identity telemetry and scored the five
development fronts: the maximum winning family score was 0.5500 versus the unchanged 0.72 gate,
and no front passed the full registered-back gate. Inventoried the new branch constants in the
centering plan. The interim holdout remains sealed; at that checkpoint joint selection was the
next permitted perception change, and the public L1/recall/device gates remained open. The later
REQ-045 entry records the bounded attempt and its failed pre-registered bar. No tolerance was
loosened.

Centering REQ-045 safety decision (2026-09-21): development evidence is now treated as a
fail-safe release decision, not a holdout result. Inner candidate recall is 34/36 (94.4%) against
the 95% gate, 0/8 confident numeric fixtures meet both ratio tolerances, and front T/B error is
19–22 pp across tested resolutions. The decision stopped automatic release and authorized one
bounded, development-only joint-selection experiment measured against L1; the sealed capture-diverse
holdout must not be evaluated to confirm this development-visible failure. The pre-registered
bar is zero confidently-wrong outputs and at least 80% confident-and-correct coverage; if it were
met, it could only expand a reliable automatic subset after the remaining REQ-045 gates. The
REQ-045 hybrid path is the product path now, with automatic starting geometry, user-placed inner
guides, exact ratio/rendering math, and guided manual correction. The selector outcome is recorded
in the following entry; no tolerance was loosened.

Centering REQ-044 experiment and hybrid implementation (2026-09-21): ran the one authorized
DEBUG-only joint selector over all ten development fixtures without reading the sealed holdout.
Nine fixtures had gradeable inner ground truth; 0/9 candidate readings met both ≤2.0 pp ratio
tolerances and 9/9 remained wrong under the pre-hybrid automatic-confidence interpretation, so
the zero-wrong / ≥80% pre-registered bar failed and the selector was not promoted. The analyzer
and view now expose a manualConfirmationRequired state: automatic outer/best-inner geometry
remains an editable starting guide, while ratio reporting and export require explicit confirmation
or adjustment of both frames; unsupported cases remain declined. Focused hybrid L1, confirmation,
and selector-evidence tests passed. The holdout remains sealed and no tolerance was loosened.

Centering hybrid verification (2026-09-21): reran the complete centering test selection after
making outer-frame confirmation explicit. On the pinned iPhone 17 Pro / iOS 26.5 simulator with
`CODE_SIGNING_ALLOWED=NO`, the seven centering classes executed 92 tests: 72 passed and 20
failed in 1,077.241 s. `CardCenteringAnalyzerTests` passed 21/21, `CenteringExportTests` 19/19,
`CardCenteringGroundTruthTests` 12/12, `CardCenteringSurfaceTests` 2/2, and the corpus manifest
1/1; the remaining failures are the already-open INV-2/4/5/7/8, REQ-022 latency, and E0/E-E
profile diagnostics. The new confirmation contract and REQ-045 confirmation test passed. The
holdout was not read; no tolerance was loosened. Result bundle: `/tmp/TradingCardScannerCenteringFull-20260921-v2.xcresult`.

Centering hybrid seed-prior diagnostic (2026-09-21): measured the detector's seeded inner
depths against a leave-one-out median prior from the same game family over the nine gradeable
development fixtures (36 edges). Depths were normalized by the annotated outer width for
left/right and height for top/bottom. The result was mixed: the family prior was clearly better
for Pokémon bottom edges (`0.10` versus `0.75` pp median; 5/6 per-edge wins), while the
detector was better for Pokémon top (`0.07` versus `1.21` pp) and Magic top/bottom (`1.18/2.77`
versus `2.54/16.99` pp). Magic left/right favored the prior, and Pokémon left/right were mixed
(the Pokémon-left median was effectively tied, `0.25` versus `0.24` pp). No blanket T/B seed
replacement is justified by this small family/side split; no production seed, threshold, or
selector behavior changed. The sealed holdout remains untouched. The focused
`testHybridSeedAgainstLeaveOneOutFamilyPrior` passed 1/1 on the pinned simulator.

Magic semantic publication hardening (2026-09-20, current working tree): added
shared Magic surface-diff and fail-closed semantic classification, with only
displayName, releaseDate, cardCount, and iconSVGURL eligible for the automatic
content-only lane. Added origin validation for signed icon URLs, explicit
removal authorization, publish-time candidate/report recomputation, dynamic
protected-versus-automatic workflow routing, and Magic-specific environment
guards. Verification passed: MagicCatalogCore 18/18, PokemonCatalogCore 39/39,
Magic release build, recorded fixture validation, hosting configuration
validation, and a serialized Debug iPhone 17 Pro Simulator build whose app
bundle was produced under external-SSD DerivedData. The hosted Magic pointer
check returned HTTP 404. The old Pokémon public pin remains temporary pending
owner input for the Magic key ID and public key; rollout remains legacy-live.

Magic catalog signing and domain-separation safeguards (2026-09-20, current
working tree based at `080db79`): brought `MagicCatalogSigningKeyLoader` to
parity with Pokémon's four GitHub publication-context checks, added the
explicit `MAGIC_CATALOG_PUBLISH` workflow marker, and made the variable source
injectable for unit coverage. Added an additive optional Pokémon schema-1
`catalogKind` marker: publisher-generated releases emit `pokemon`, the
verifier rejects a present wrong domain, and legacy releases that omit it stay
readable. Updated the key runbook to document Magic's second protected
environment and separate-key custody boundaries. Verification passed:
MagicCatalogCore 10/10, PokemonCatalogCore 39/39, Debug iOS Simulator build,
and `git diff --check`.

Documentation freshness reconciliation (2026-09-20, current `main` at
`31eb97e`): updated the current App Review/release ledgers, launch plan, and
repository audit to distinguish the clean current checkout from historical
candidate evidence; recorded the committed F01–F03 source remediation while
keeping entitled-device/runtime and release gates open; and updated the Pro/
eBay plan and centering contract to reflect their merge into `main`. Dated
historical evidence and older progress entries were preserved. Documentation
only; no source, tests, or build settings changed.

Pokemon catalog artwork fingerprint parity fix (2026-09-20, current working
tree): preserved raw provider `logo`/`symbol` values while carrying resolved
artwork in transient fields used only by descriptor construction. `v1` now
hashes the decoded provider payload, including the distinct `nil`/empty-string
tokens, so directory fallback, CDN resolution, and resolver failure cannot
make publisher and device fingerprints diverge. Added a Core parity test that
drives the real fixture fetch through the directory, CDN, and empty-string
paths and verifies both fingerprint equality and descriptor artwork delivery.
Verification passed: PokemonCatalogCore 38/38, the focused parity test,
`xcodebuild` Debug simulator build, and `git diff --check`. Two non-blocking
follow-ups are recorded in
[`docs/plans/release_followups.md`](docs/plans/release_followups.md): document
the load-bearing directory-row artwork fallback and add an iOS test covering
the device-side `canonicalFingerprint` mapping.

Catalog schema-1 provider-content propagation (2026-09-20, current working
tree): kept `PokemonCatalogCoreContract.releaseSchemaVersion == 1` and added
`providerFingerprint` as an optional additive descriptor field. Legacy
schema-1 releases decode it as `nil`, while new releases can carry a signed
desired content value without requiring an app update. Added one canonical
Core fingerprint for publisher/device parity, a distinct local-only probe
fingerprint for the independent 24-hour sweep, and fail-closed change
classification for content-only, baseline, authority, new-set, and unknown
changes. The first nil-to-fingerprint population is therefore protected
baseline migration; only later explicit content-only changes select
`pokemon-catalog-production-auto`.

The device now persists `(providerSetID, desiredFingerprint)` reconciliation
targets, retries mismatches without clearing them, publishes a set overlay only
after the computed canonical fingerprint matches, preserves full-sweep state,
and emits a set-specific Browse update. Activation events also carry content
change IDs and invalidate the existing resolved-card cache path. Verification
passed: PokemonCatalogCore 36/36 and 37/37 focused catalog app tests on the
arm64 iPhone 17 Pro simulator, with DerivedData, module caches, temporary files,
and the xcresult on the external SSD. Protected baseline publication, auto
environment setup, four-hour scheduling, live-provider, and physical-device
acceptance remain open.

F04 automatic Pokémon catalog preparation (2026-09-19, isolated branch
`codex/automatic-catalog-discovery-f04` from committed `edd8dc6`): added TCGdex
series/official-abbreviation evidence decoding, provider-side image-MIME-gated
CDN artwork resolution, safe active-descriptor metadata merges, automatic
ordinary-expansion code/count/release-order derivation, discovery policy and
due-set CLI preparation, card-art fallback hints, explicit `30th-c` support,
and scheduled workflow preparation with protected approval still required.
The signed release remains the only scanner authority; production config was
not changed. Verification passed: PokemonCatalogCore 22/22, recorded CLI
validation, BrowseFeatureTests 49/49, PokemonChecklistBrowseTests 56/56,
Slice B 29/29, Slice C 6/6, Slice D 4/4, Slice F 8/8, focused legacy snapshot
compatibility 1/1, and DebugProduction build. Live TCGdex candidate generation,
production approval/deployment, and device acceptance remain open. The main
working tree was left untouched.

Catalog authority rehearsal completed (2026-09-19): commit `54960fd` was
pushed with the same-revision coordinator fix and its production-configured
catalog suites passed 8/8 focused and 64/64 broader. The validation-only
production binary fetched hosted revision 1 from `catalog.scan-stash.com`,
validated 28/28 descriptors, ran validate-and-discard, and kept remote-store
disk usage at zero. A one-off external-SSD build with
`POKEMON_CATALOG_ROLLOUT_MODE=remote-authority` then activated revision 1,
persisted `current` with no `previous`, survived relaunch, and treated the
identical HTTP 200 envelope as `notModified`. The committed production
xcconfig remains `bundled-validation-only`; physical-device and genuine
offline evidence remain open.

Revision-2 candidate intentionally not published (2026-09-19): workflow run
[35443012617](https://github.com/Razorback2424/CardScanner/actions/runs/35443012617)
passed core validation and production candidate preparation from `54960fd`.
Its revision-2 candidate matched hosted revision 1 across all 28 descriptors,
provider card counts, provider fingerprints, and snapshot entries, with zero
added/changed/excluded IDs. The protected publish job was canceled before
signing or deployment, so hosted revision 1 remains current and the candidate
and reports are retained as external-SSD evidence only. The first real catalog
change should become revision 2.

Centering diagnostics slices implemented (2026-09-18): added REQ-049 positional
consistency diagnostics that report left/right and top/bottom ratios at five
evenly spaced positions with min/max/spread, without feeding the result into
selection or confidence. Added REQ-050 numerical-parameter injection with
unchanged production defaults plus a standalone recorded-grid harness under
`review/centering-harness/`; the harness has not yet been run over the corpus
or holdout, so REQ-050 completion and signed evidence remain open. Focused
simulator verification passed 19 `CenteringExportTests` and the two new
REQ-049/REQ-050 invariant tests on iPhone 17 Pro, iOS 26.5. The full suite,
corpus sensitivity sweep, and REQ-051 resolution comparison were intentionally
deferred. See
[`review/opus-card-centering-implementation-plan.md`](review/opus-card-centering-implementation-plan.md).

Catalog infrastructure state verified (2026-09-18): recorded the actual
deployment prerequisites in the plan's "Resume here" table after checking them
directly rather than inferring them. All catalog work for Slices A-F is in the
working tree and is **uncommitted and unpushed** at `db50515`, so
`.github/workflows/pokemon-catalog.yml` has never run and its `validate` job has
never executed on a runner. `catalog.scan-stash.com` does not resolve;
`scan-stash.com` resolves to Bluehost, which serves the marketing site and is
deliberately not the catalog origin. The `pokemon-catalog-production` GitHub
environment does not exist (HTTP 404); `pokemon-catalog-staging` exists but
holds only `POKEMON_CATALOG_KEY_ID` and `POKEMON_CATALOG_SIGNING_KEY`, and no
environment holds `FIREBASE_SERVICE_ACCOUNT` or `FIREBASE_PROJECT_ID`, both of
which the publish job requires. Also recorded one open gap the plan had been
claiming as a control: `PokemonCatalogUpdateClient.defaultBaseURL` validates
HTTPS, host presence, and unexpanded build variables, but implements no host
allowlist, so the plan's "release origin is a separate allowlist entry" claim is
aspirational until either the allowlist is added or the claim is dropped. The
earlier duplicated environment-path mapping in the publisher CLI is confirmed
fixed: `PokemonCatalogPublicationEnvironment.path` is now `public` and
`main.swift` consumes it instead of its own ternary. Documentation only; no
code, tests, or build settings changed. See
[`docs/plans/automatic_pokemon_catalog_updates_plan.md`](docs/plans/automatic_pokemon_catalog_updates_plan.md).

Catalog publication first-channel readiness (2026-09-18): kept the publisher
on one Firebase Hosting target and one local site root (`publisher/site`) for
the first Slice F rehearsal. The publisher environment path is public and is
the single source used by the CLI and filesystem publisher; staging retains its
future `staging/v1` namespace but is not wired into the current workflow.
Added production-only restoration with the existing 404-versus-corruption
semantics, dot-file Hosting ignores, local `.complete` markers, and a checked-
in Firebase target example. The app remains `bundled-validation-only`, so the
production hostname is acting as the rehearsal origin without granting remote
authority. Core tests pass 8/8 and the DebugProduction simulator build passes;
the focused Slice F simulator test target built but the runner exited before
XCTest bootstrapped, so its assertions remain unverified. GitHub PR validation,
Firebase project/DNS provisioning, production credentials/key pin, and the
ordered live rollout remain owner-controlled gates. Staging is deferred until
remote authority is close. The first validation-only GitHub Actions dispatch
after the push passed all four validation steps in 40 seconds (run
35394732002); publication was skipped because `publish=false`.

Catalog publication review remediation (2026-09-18): production publication is
now workflow-dispatch-only while Slice F is incomplete; scheduled runs remain
validation-only. The production job reconstructs the previously served
versioned release objects before deploying the fresh Hosting tree, and retains
the public review report as a 90-day Actions artifact. The Slice E checklist
now labels its publisher/filesystem and configuration evidence separately from
the still-open device rehearsal; Slice F records that privacy/support updates
are complete while App Store metadata confirmation remains open. Pointer fetch
failures now stop publication; only an explicit 404 is accepted as an initial
deployment.

Measured catalog rollout guard (2026-09-18): implemented Slice F's bundled-authority rollout mode. Production/default builds now fetch the signed catalog pointer for validation but never load or persist a remote registry; remote authority remains disabled until the future staging boundary and no-op rehearsal are ready. Added fail-closed public-key build configuration, launch/network/validation/activation/disk/memory diagnostics, and focused simulator coverage for validation-and-discard, explicit activation, persisted-release isolation, and configuration parsing. The focused Slice F target built, but its simulator test runner exited before XCTest bootstrapped, so those assertions remain unverified; the app build passes. The live Firebase pointer, production key ceremony and signing secrets, real new-set clean-install/upgrade/offline/cancellation/rollback run, physical-device measurements, and App Store evidence remain open. See [`docs/plans/automatic_pokemon_catalog_updates_plan.md`](docs/plans/automatic_pokemon_catalog_updates_plan.md).

Slice E checkpoint (2026-09-18, before Slice F rollout guard): automatic Pokémon catalog updates Slices A–D are implemented, and Slice E publisher/staging implementation has begun. Slice D makes the shared signed `PokemonCatalogCoordinator` the production Browse activation authority: TCGdex remains transport for authorized provider IDs, provider-only discoveries stay out of Browse until activated, and the checklist refresh validates official counts before publishing. Browse reloads on registry/checklist updates, preserves the previous complete directory on provider failure, uses registry release ordering through rollback, and removes the obsolete UserDefaults ordering authority and Pocket request. Pending sets intentionally render as nothing until active; legacy/diagnostic representations use `Code pending`, never a provider ID. Added `PokemonCatalogSliceDTests.swift`; the focused Slice D run passed 4/4 on the iPhone 17 Pro simulator. Slice C installs the same registry into Scanner; the app build and existing Slice A/B/C catalog/coordinator suites pass. Slice E adds the UIKit-free `PokemonCatalogCore` package, deterministic publisher fixtures, human-input gate, guarded signer, immutable filesystem publication, Firebase cache policy, CI workflow, and staging configuration. Its focused core run passed 7/7, recorded CLI validation passed, and the compile-only iOS build passed. The live Firebase deployment, production signing secret, populated production input, app `pinnedKeys`, provider/device/archive/release gates remain open; no full simulator suite or centering tests were run. See `docs/plans/automatic_pokemon_catalog_updates_plan.md`.

Historical checkpoint (2026-09-17): automatic Pokémon catalog updates Slice A is complete. Created `PokemonCatalogRelease.swift`, `PokemonCatalogRegistry.swift`, `PokemonCatalogSignatureVerifier.swift` (contract, bundled registry, signature verifier); added `PokemonCatalogDiagnostics` diagnostic counters on both `set.id.uppercased()` fallback paths (`PokemonChecklistSnapshot.swift:192` and `CollectionCatalogNormalizer.swift:741`); migrated all nine disposition-table consumers from `SetCodeMap`/`PokemonPromoCodeMap` to the registry (`ScanParser`, `RecognitionProfile.customWords`, `CardCatalog` officialCount, `BrowseCatalog` sort, `PriceRefreshController`, `CollectionCatalogNormalizer`, `PokemonChecklistSnapshot` display code, `TCGdexCard` release order); the generator coverage list at `PokemonChecklistSnapshot.swift:1203` stays on the seed. `CollectionCatalogNormalizer.resolvePokemonSet` receives the registry as a parameter, pinned for the pass. `PokemonCatalogTests.swift` (40 tests, 0 failures) covers round-trip/malformed envelopes, signature success/wrong-key/changed-byte/unknown-key/replay/future-skew, registry collision (expansion, promo, provider ID, cross-namespace) and `scanEnabled`/`.notScannable`, promo pad-width parity for all six series, and the parity gate across all migrated consumers including end-to-end ScanParser parsing. The targeted existing-suite run (ScanParser, BrowseFeature, CatalogNormalization, CardLatch plus all new tests) passed 227 tests with 0 failures. Slices B–F remain unimplemented. See `docs/plans/automatic_pokemon_catalog_updates_plan.md`.

Previous checkpoint (2026-09-16): the current branch is `main`; the focused
Browse/cache and PBX resource correction verification ran on the tree based at
`c381c99`. Browse selectors pass 133/133, the A8/B6 light/dark visual checks
are closed, and C7/RF-9 live-provider measurement remains open. The PBX fix
restored all 57 committed centering corpus files to the test bundle.

The latest complete full simulator run remains the pass-2 run at `a4375df`:
1,277 executed, 6 skipped, and 40 failures (36 fixture-resource lookup, 1
load-sensitive, 3 substantive). A focused post-fix centering run produced 38
results: 28 passed, 9 test cases failed on known centering assertions, and 1 profile-dump
test canceled; it was not a full-suite baseline. Card-centering accuracy,
invariant, latency, and device-only gates remain open, as do App Review
storage/CloudKit, physical-device, provider, archive/TestFlight,
ownership-ledger, and release-candidate evidence. The current documentation
boundary and contradiction matrix are in
[`docs/plans/documentation_audit.md`](docs/plans/documentation_audit.md).

## Historical checkpoint — 2026-09-12

Current checkpoint (2026-09-12): the repository-wide documentation and artifact
audit remains tracked in `docs/plans/documentation_audit.md`. The active
card-centering contract and evidence are tracked in
`review/opus-card-centering-implementation-plan.md` and
`review/centering-evidence/`. The current signed post-E-REQ044 full suite on
the pinned iPhone 17 Pro / iOS 26.5 simulator reports 1,095 result entries:
1,085 passed, 1 skipped, and 9 failed. All nine failed entries are centering
gates; the known pre-existing Magic-treatment failure from an older baseline
did not recur in this run. No Keychain entitlement failures occurred. The
current production accuracy, invariant, semantic-role, and latency gates remain
failing.

The rederived ground truth is adjudicable. The current E-A/E7 branch is 9
confident and 1 declined, with IMG_0782 correctly declining, but 3/10
development records meet the descriptive ratio target at 1200/1600/2000/2400.
The corrected REQ-042 ledger finds 34/40 outer candidates (85.0%) and 28/36
gradeable inner candidates (77.8%) under the exact role-specific tolerances;
the eight inner misses are generator failures, not selector measurements.
All nine non-none outputs still report `art_window`, including the five backs.
The screenshot batch remains a pre-E-B historical 3/7 snapshot. The 34-image
supplementary intake is now covered by a SHA-256 manifest: 24 new files are
development data and 10 are sealed as `HOLDOUT-INTERIM` before new analyzer
work. This is an interim safeguard, not final generalization evidence: the
HEICs are from one iPhone model, the PNG capture role is unknown, and no new
ground truth has been assigned. The capture-condition-diverse REQ-040 gate
therefore remains open; see `review/opus-card-centering-implementation-plan.md`.
Historical “pending” entries below are retained as chronology, not as the
current status.

Original prompt: Implement Browse Sets and Cards across Pokémon/TCGdex and Magic/Scryfall.

- Portfolio history Phase 2: fixed closed-close half-open attribution, unified state replay with the deterministic timeline, added pure value snapshots/history engine, cached SwiftData flattener, history card, Audio Graph/VoiceOver descriptor, and focused accounting/TWR tests. Source compile reached the new files; simulator build/capture is pending CoreSimulator availability.

- Added deterministic Browse launch route and QA checklist. Build/screenshot execution intentionally not run per user instruction.
- Implemented provider-neutral catalog browsing, both providers, global filtering/search, exact-printing add/undo, ownership aliases, release ranks, and unit-test coverage. Static checks only.
- Added at-a-glance unique-card set completion (`owned/total`) and progress bars to game set lists. Builds/tests/screenshots remain intentionally unrun.
- Added per-set card sorting by price or collector number plus owned/not-owned product filters. Price sorting hydrates exact-printing prices on demand with bounded concurrency and caching; execution checks remain intentionally unrun.
- Made the optional price fallback free-tier safe: fresh non-USD values become fallback work only when enabled, actual HTTP requests are capped at 95 per UTC day with background work capped at 75, 429 backoff is persisted, and Collection now exposes pending work, allowance state, and shared fallback settings. Builds/tests remain intentionally unrun.
- Unified camera, finish lock, price fallback, and collection deletion in one shared SettingsView accessible from all four tabs; Collection refresh is now a compact icon beside the green collection value. Build/test verification stopped at the user's request.
- Sealed-artwork loop target: `SealedArtwork`. Done means priced and null-price responses persist artwork independently, existing rows receive one backfill, terminal provider misses stop artwork retries, and the real remote image plus diagnostic placeholder pass `artifacts/sealed_artwork_checklist.md` in a simulator screenshot.
- Sealed-artwork loop 1: focused tests passed; screenshot harness failed because the named iOS 18.2 simulator was combined with an implicit `OS=latest`. Updated the harness to target its stable simulator UUID.
- Sealed-artwork loop 2: app compiled for the correct device, but workspace-local DerivedData inherited iCloud resource metadata and failed code signing. Moved the disposable screenshot build cache to `/tmp`.
- Sealed-artwork loop 3: screenshot rendered the network image and terminal diagnostic correctly, but exposed that fixture ID `610553` is a Suicune single. Replaced it with TCGplayer product `98580`, verified as Legendary Treasures Booster Box and returning HTTP 200 JPEG.
- Sealed-artwork loop 4: verified product `98580` rendered the correct Legendary Treasures Booster Box. HIG review found the name squeezed beside the five-digit price, so the tile now gives the name and price separate full-width lines.
- Sealed-artwork loop 5: final screenshot passed every visual and behavior item. Missing legacy sealed artwork may backfill with a configured vendor key even when general fallback pricing is off; ordinary fallback pricing remains opt-in. Full test suite and Release build passed.
- Whole-card scanner loop 1: replaced modal historical title capture with an on-demand same-frame title request, added a whole-card guide/footer band, and added conservative assistance models. Debug build and focused whole-card tests pass; visual route added for screenshot verification.
- Whole-card scanner loop 2: first deterministic capture reached the correct Scan tab but the reinstall-triggered camera permission alert obscured the guide. Updated the harness to grant camera permission after install for this route.
- Whole-card scanner loop 3: simulator privacy grant still surfaced the authorization sheet. Made the DEBUG-only `WholeCardScanner` route render the production scanner surface without starting capture; normal app launches still request and use the camera.
- Whole-card scanner loop 4: view-level bypass was insufficient because authorization still occurred below SwiftUI lifecycle ordering. Added the same DEBUG-route guard at `CardScanner.start()`, the single authorization entry point.
- Whole-card scanner loop 5: scanner-focused tests pass and the Release simulator app builds. The full suite passes 356/359; the only failures are existing Keychain tests rejected by the simulator with entitlement error `-34018`. Visual verification remains unclaimed because the simulator retained a camera-permission sheet over the deterministic route.
- Whole-card scanner loop 6: corrected the whole-card guide's normalized geometry for the portrait 16:9 source-pixel aspect. The old constants produced the ~0.40 aspect seen on device; the guide now resolves to the physical 2.5:3.5 card ratio, with footer/title ROIs expressed card-relatively.
- Portfolio stabilization loop target: `PortfolioToday`. Done means the deterministic normal-day fixture renders whole-collection value, reconciliation rows, honest checked/not-refreshed coverage wording, and no clipping or hidden residual in `artifacts/ui-latest.png`.
- Portfolio stabilization loop 1: the explicit-device harness built and launched `PortfolioToday`; the screenshot passed the checklist with a $125 whole-collection hero, $125 Added/Total reconciliation, an Aug 24 close, “1 of 1 checked today,” and no clipping, overlap, or unexplained residual. The harness now installs, launches, and captures from its requested simulator UUID instead of an arbitrary booted device.
- Portfolio populated-store migration: built d23347b in a detached temporary worktree, seeded its `SealedArtwork` route (2 cards, 2 inventory events, 2 price records), installed the stabilized build in place, and launched successfully. All six synced rows survived; the new local-knowledge backfill created 2 observations and 2 check rows, while close count remained 0 on migration day as required.
- Portfolio stabilization loop 2: added the explicit Current row required by the accounting-card contract and recaptured the route. The final artifact shows prior close and current together, still fits above the secondary collection grid, and passes the complete checklist.
- Portfolio stabilization loop 3: after the final epoch durability, earliest-baseline, and CSV attribution fixes, `PortfolioToday` was rebuilt and recaptured. The $125 hero, Added/Total, Aug 24 close, Current, and “1 of 1 checked today” remain correct with no clipping, overlap, or visible residual.
- Portfolio final populated-store migration: rebuilt and seeded d23347b with 2 cards, 2 inventory events, and 2 price records, then updated in place to the final hardening build. The app remained running, all six synced rows survived, 2 local observations and 2 check rows backfilled, and migration-day closes remained 0.
- Portfolio history hardening: closes now plot at their next-midnight economic instant with separate display days, the portfolio engine publishes a monotonic history refresh revision, the chart has a visible snapped-point inspector, Audio Graph and VoiceOver strings use correct percentage interpolation, and the Phase 2 acceptance tests cover new assets, nonmarket observations, reversals, DST, live deduplication, empty states, and shuffled-input reproducibility. Full scheme compilation passed; runtime tests and screenshots remain blocked by CoreSimulator service/device availability.
- Portfolio F: one computation per input change (history consumes the engine's replay result instead of building its own snapshot and replaying 47k observations again), SwiftData materialization moved off MainActor onto a @ModelActor with stale-result versioning, and the PortfolioHistory route captured for the first time. Two bugs surfaced only in the real UI: inputRevision was published before the result existed so the history card never refreshed, and the QA fixture seeded fabricated zero-valued closes that the replay correctly overwrote. Verified on simulator: Performance 25% traces the seeded 100/104/101/112/118/125 with the $100 acquisition excluded, Collection Value shows +$25 with $0 net collection activity, mode switching is instant, and scrubbing snaps to published closes. Real-device timing remains unverified.
- Marketplace link: persisted TCGplayer product/SKU identity from the JustTCG batch path and sealed browse, added TCGplayerLinkBuilder (product id + printing, else provider-supplied URL, else no button — never a name/set search), and a "View on TCGplayer" action directly under the price on card detail. Verified on simulator. The observation log records explicit invalidations on marketplace-variant changes, while the grid and portfolio now share record-backed instrument selection and keep observation-aware valuation. Holding detail was moved onto the grid's rule deliberately; see performance_review_remediation_plan.md R2/C2.
- Device signing: Debug now uses TradingCardScanner-Local.entitlements (no iCloud, no Sign in with Apple) so a personal Apple Developer team can provision and install on a real device; Release keeps the full entitlements for a paid team. LOCAL_ONLY_SIGNING skips the CloudKit container attempt and replaces the sign-in button with an explanation. Verified: generic/platform=iOS Debug build signs, and the signed app carries no iCloud or applesignin entitlements.
- Phase 3 explainability loop target: `PortfolioToday`. Done means the existing portfolio hierarchy retains its Today and Phase 2 surfaces, then presents Impact-ranked Biggest movers and Largest holdings with no clipping. The current fixture now seeds four deterministic positions with positive and negative contributions for visual QA.
- Centering camera/measurement fix: centering now follows the scanner's macro-first lens and near-focus configuration; captured image orientation is normalized before edge detection so portrait cards are not stretched into false desk-edge measurements. Simulator verification remains blocked by CoreSimulator service availability.
- Price Check implementation: added purpose-captured scanner routing, a device-local quote cache isolated from portfolio evidence, a dedicated result view and forced exact-card refresh, plus the deterministic `PriceCheck` screenshot route/checklist. Build, tests, and screenshot validation intentionally deferred at the user's request.
- Pokémon checklist snapshot loop: bundled 159 checklist resources across 148 supported provider sets, added local-first Browse loading and atomic opportunistic refresh, and passed focused plus non-keychain full-suite tests. The simulator rendered-test path passed, but the standalone screenshot helper could not capture after CoreSimulatorService disconnected.
- Scanner chrome loop 1: removed unused presentation state from published assistance, added downward hysteresis and a focused regression test, scoped transient scanner animations to mutation sites, stabilized Menu/control identities and 44pt hit targets, and narrowed CameraPreview observation to rotation/debug-box state. Build and screenshot verification pending.
- Scanner chrome loop 2: generic simulator build passed with the scanner changes compiled; the focused runtime test and deterministic screenshot were blocked when CoreSimulatorService disconnected and the configured device UUID was unavailable. Unrelated temporary compile workarounds were restored exactly.
- Scanner chrome loop 3: removed the sealed-set `releaseDate` stored-property default and updated its undated fixture, capped presentation hysteresis, animated slow-identification state at the mutation sites, preserved 34pt pill visuals inside 44pt targets, and added long-run hysteresis coverage. Full `build-for-testing` and the full simulator test suite pass; real-device interaction and screenshots remain pending.
- Collection navigation fix: compact-width Collection now uses the grid as the NavigationStack root, so card detail Back returns directly to the grid instead of exposing the split-view placeholder. The simulator build passed; screenshot capture is pending CoreSimulator availability.
- Portfolio market-movement simplification: primary Portfolio now uses one canonical additive market series for the headline, chart, movers, and all five existing ranges; full value reconciliation remains behind Details and contributor residual labels are clarified. The later cleanup removed the unused presentation-mode plumbing while retaining performance factors as internal replay data. App build passed; the focused history test target was previously blocked by unrelated `PortfolioReconciliationTests.swift` compile errors, and the user requested no further screenshot captures.
- Centering controls loop 1: rotation is now a display-only transform that preserves existing red/cyan guide positions and measurements; outer/inner guide rows accept direct numeric entry alongside steppers; the card preview remains pinned above a scrollable controls pane. Final Debug build and focused centering export tests pass; expanded simulator capture inspected before CoreSimulatorService disconnected again.
- Magic treatment Slice 4 loop 1: composed Magic finish/treatment labels now feed scan receipts and catalog card detail, explicit finish/treatment contradictions are read-only diagnostics, and a deterministic DEBUG route is ready; screenshot capture remains pending CoreSimulator availability.
- Magic treatment Slice 4 loop 2: finish-aware labels now suppress a foil-only treatment on a selected nonfoil copy, while browse detail presents dual-finish treatments without silently choosing foil; FIC #10 is the deterministic QA fixture.
- Magic treatment Slice 5: persisted forward-compatible treatment ids through collection rows, activity history, removal snapshots, prices, reference quotes, and vendor identities; centralized independent collection/price key codecs across raw, graded, sealed, and CSV paths; treatment-qualified rows refuse generic price read-through. Generic iOS build passed; simulator suite passed 692 tests with only the three pre-existing Keychain-entitlement tests excluded.
- Magic treatment Slice 6: made catalog pricing treatment-aware through the shared finish-filtered derivation; quarantined pre-existing generic treatment-keyed prices from collection, quote, portfolio, and replay reads; blocked generic JustTCG matching and scoped vendor misses by treatment; kept ordinary finish pricing independent; and hid unproven treatment marketplace links across both detail paths. Focused and full simulator suites passed, with the full suite at 710 tests under normal signing and no exclusions; visual/device capture remains pending.
- Magic treatment Slice 7: carried exact treatment identity, publisher qualifiers, and printed content kind through Browse summaries, ownership/completion, collection badges and filtering, history, removal/rekey paths, and lossless CSV export/import. Collector-number ordering keeps bare numbers before `a`/`b` suffixes, treatment remains a qualifier rather than a new set slot, and pre-/post-Slice-5 CSVs use the collection read-through. Full scheme suite passed 723 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 6–7 review hardening: treatment capability gaps now return a distinct non-evidence outcome through product fallback and never create a 30-day vendor-miss identity; ProductPriceSubject requires an explicit treatment axis; and completion canonicalization maps zero-padded suffixed numbers such as `0523a` to `523a`. Full scheme suite passed 725 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 8: added a per-row exact-printing migration that understands raw, graded, certified, sealed, and imported collection identities; enriches only from embedded Scryfall ids; preserves opaque vendor price bases without moving generic evidence into treatment keys; repairs safe canonical/legacy collisions with deterministic, idempotent correction legs; retains activities, removal snapshots, content kind, and ledger lineage; skips certified slabs; clears stale treatment-qualified vendor negatives; and handles pre-ledger collections before portfolio baseline creation. Launch now performs local repairs before portfolio startup, then batches deferred exact-id Scryfall enrichment in groups of 75 with pacing and recomputes afterward; optional identity fields require agreement rather than treating missing metadata as a match. Full scheme suite passed 742 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 9: completed the cross-slice regression gate for all four audited NEO Neon Ink qualifiers, FIN collector-number suffix identity and completion, dual-finish FIC keying and treatment-aware pricing, deterministic two-device migration correction payloads, quantity/ledger conservation, and the existing parser, star, rescan, collision, CSV, and generic-price-substitution matrix. The first requested simulator build succeeded with no warnings, followed by 746/746 full-suite tests passing with zero failures or skips; visual/device capture remains pending.
- Magic treatment post-Slice-9 audit fixes: serialized local/network treatment migration with foreground, automatic, and background price-refresh planning; rebuilt foreground targets from the live model context after the gate; preserved queued portfolio recomputes across cancellation; centralized catalog retry-watermark writes in CollectionCatalogNormalizer; and invalidated completed migration results when observed Magic collection inputs change, including stale in-flight results. Added deterministic gate, cancellation, and migration-invalidation coverage. Simulator build and 750/750 full-suite tests pass with zero failures or skips; visual/device capture remains pending.
- UI Updates: centralized iOS 26 scanner glass with tinted locked/unresolved states, carried catalog unit price through scan receipt/review, and refactored collection card detail into grouped List sections with honest checked-day step/gap history and instrument-key predicates. Debug simulator build plus affected tests pass; screenshot capture deferred at the user's request after CoreSimulatorService became unavailable.
- UI Updates hardening: the scanner tab bar now hides only while a choice, duplicate confirmation, or receipt occupies the thumb zone and reappears when idle; legacy tinted-pill fallbacks preserve the red lock and 0.85 orange attention chip. Debug build and affected tests pass; screenshot remains deferred.
- Performance remediation slices 1-4, 6, 7, 11 (branch `perf/remediation-slices`, see performance_review_remediation_plan.md §0): holding detail projects from price records instead of the ledger, with a test pinning which of the three instrument-resolution rules it now follows; LedgerIntegrityLog and the unused epoch context parameter removed; Portfolio and Collection stopped observing PriceRefreshController from whole screens and share one activity row, and Collection's pull-to-refresh returns instead of awaiting the pass; the refresh write path (applyVendorBatchHit, ProductIdentityStore, ProductIdentityIndex and five transitive helpers) is context-owned rather than @MainActor, which is the prerequisite audit for moving refresh persistence to a @ModelActor; background task identifiers derive from the bundle id in both code and Info.plist; catalog fallback quotes dedupe by instrument instead of cancelling the previous card's; the Magic scan vocabulary is no longer recompiled on every Scan-tab appearance. Slice 4 bounds PriceCheckDay coverage to a 400-day window and prunes behind it, with pruned days' coverage read back from the published closes so ALL still renders — measured flat at 1.66s for an 800-day store where the unbounded read would have cost ~3.3s and kept climbing. Signposts and an opt-in aged-store fixture (PERF_BASELINE) produce the numbers. 851 tests, 1 skipped, 0 failures. Slice 5 is now implemented and simulator-verified; its live-provider event-count profile remains recommended. Slice 9's P1/U2/U3 items remain hardware gates, and Slice 10 is closed by the current iOS 17 deployment decision; Slice 8 is recorded below.
- Performance remediation correction: `PortfolioEngine.publish` now carries `carriedForwardValue` from pruned `PortfolioDailyClose` rows alongside the three coverage fields already carried. `testPrunedDaysKeepPublishedCoverage` uses a published `$2` versus pruned `$9` fixture and confirms both the no-revision and late-revision cases preserve the original value/coverage.
- Performance remediation Slice 8 (R4): refresh persistence now runs through a dedicated `@ModelActor`; the main-actor controller retains only the migration gate, queue, cancellation, status/progress, and fallback-budget UI. Targets, both whole-table indexes, `PriceStore`, identity/artwork writes, checkpoint saves, and background refresh target construction are actor-owned; only value requests/results and `PersistentIdentifier`s cross. Target-build failures remain retryable for the automatic stale check, and queued unlimited limits are preserved. Full simulator build/test passed: 850 tests, 1 skipped, 0 failures in 24.561 s. Runtime Instruments capture against a live provider remains recommended; device-gated slices are unchanged.
- Performance remediation Slice 5 (R3): the portfolio observer no longer hashes local price fetch/check timestamps, and the collection projection token preserves only freshness-presence bits plus exact `fetchedAt` for unstamped providers. Focused freshness tests and the full simulator suite pass: 851 tests, 1 skipped, 0 failures. No seeded-store number is substituted for the planned live-provider `makeCachedProjection`/`startRecompute` event count.
- Performance remediation Slice 8 (R4): refresh persistence now runs through a dedicated `@ModelActor`; the main-actor controller retains only the migration gate, queue, cancellation, status/progress, and fallback-budget UI. Targets, both whole-table indexes, `PriceStore`, identity/artwork writes, checkpoint saves, and background refresh target construction are actor-owned; only value requests/results and `PersistentIdentifier`s cross. Target-build failures remain retryable for the automatic stale check, and queued unlimited limits are preserved. Full simulator build/test passed: 850 tests, 1 skipped, 0 failures in 24.561 s. Runtime Instruments capture against a live provider remains recommended; device-gated slices are unchanged.
- Performance remediation closeout evidence: the app-only iPhone build and signed physical test bundle build succeed. The physical test run reached 851 tests with 1 skipped but failed only at `BrowseFeatureTests.testBrowseSearchDebouncesBeforeStartingBothSearchLanes` (a focused retry reproduced its provider-start count mismatch, `0` vs `2`); no P1/U2/U3 code was changed or claimed verified. R5 `#Index` is closed without code because both targets remain iOS 17.0 and `#Index` requires iOS 18; raising the target remains a separate product/migration decision.
- Performance remediation fourth-pass correction (2026-09-05): `ContentView` now keeps `PriceRefreshController.shared` as a plain reference; only the small refresh controls, attention badge and activity row observe progress, so 250 ms status publications no longer invalidate the whole tab tree. Graded v2 requests are also bounded by `JustTCGQuota.maximumPageSize` (20). Focused post-correction simulator tests pass 62/62, the generic test build succeeds, and the full suite passes 857 tests with 1 skipped and 0 failures in 24.814 s. Live SwiftUI/Instruments body and signpost counts remain unmeasured.
- Card-detail redesign S0 (2026-09-06): promoted the shared Liquid Glass surface into `AppGlass.swift`, renamed the scanner-prefixed modifiers to app-scoped names, and kept the iOS 17 fallback plus iOS 26 material branch unchanged. The simulator app build succeeds.
- Card-detail redesign S1–S6 (2026-09-06): rebuilt owned-card detail around a full-bleed hero, unified identity and accessible badges, a single price/movement surface, a bounded treatment-aware finish sheen, and one Market/History/Quantity action strip. Collection tiles and Portfolio holding/contribution rows now reuse the same badge vocabulary; the scoped instrument-key queries, chart step/gap rules, observation kinds, and collection actions remain unchanged. The simulator app build succeeds and the full suite passes 861 tests with 1 skipped and 0 failures. The deterministic CardDetail route launched, but CoreSimulatorService disconnected before screenshot capture, so the visual checklist remains pending a healthy simulator/device session.
- Card-detail visual follow-up (2026-09-06): nil remote artwork now terminates in the existing diagnostic placeholder, the pushed detail destination hides the collection tab bar so the resting identity block is not occluded, and quantity-one movement summaries no longer repeat the same dollar amount per card. The deterministic CardDetail fixtures now carry direct Charizard artwork, and the debug auto-open waits for the seeded snapshot instead of racing it. The inspected dark-mode capture shows the real hero and fully visible identity block. Full simulator suite passes 861 tests with 1 skipped and 0 failures. The clustered-data chart axis remains unchanged pending real multi-day data.
- Card-detail follow-up (2026-09-06): artwork actions now live in the navigation toolbar instead of covering printed hero content. The CardDetail fixture no longer duplicates the current price and successful check day already recorded by `addSealed`, so its chart has exactly two observations and one checked day; a DEBUG surface test pins the stored rows and `2 changed prices across 1 checked day.` summary. The settled dark-mode CardDetail capture was inspected after the cold-launch frame and shows the menu outside the artwork. Full simulator suite passes 862 tests with 1 skipped and 0 failures. Dominant-colour extraction, finish-qualified fixture data, and the clustered-data axis remain explicitly deferred.
- Card-detail deferred-item closure (2026-09-06): artwork accents are now extracted asynchronously from the existing local/remote artwork source, cached by source key, and applied to the hero backdrop without work in `body`; the DEBUG fixture now uses a catalog-resolved holo card with direct artwork so the treatment-aware finish path is exercised; and clustered price observations use their observed span plus bounded padding for the plot domain while preserving step/gap semantics. Focused chart, fixture, and accent tests pass; the settled dark-mode CardDetail capture shows the loaded hero, visible identity block, and menu outside the artwork. Full scheme suite passes 864 tests with 1 skipped and 0 failures.
- Card-detail chart accessibility follow-up (2026-09-06): x-axis tick dates now derive from the fitted plot span, short spans include date-plus-time context, and accessibility-large caps the axis at two labels; fitted charts identify that the selected range is wider than the available data. Dark, light, and accessibility-large route captures were inspected, focused chart tests pass, and the full suite remains green at 864 tests with 1 skipped and 0 failures. The simulator was restored to dark appearance and default text size.
- Card detail finish and holding controls: replaced the foil overlay, which drew a hard-edged rounded rectangle at 82% of the card's width and screen-blended it at 0.72 opacity — a translucent box sitting on the artwork, showing its own corners and lifting the art's blacks. It is now a directional band wider than the card's diagonal, masked to the card so no edge is ever in frame, soft-light blended so the sheen blooms on highlights and leaves shadows alone, with a single narrow additive specular core. Surge Foil renders three bands out of phase, Neon Ink two hue-shifted, reverse holo is masked to the border the printing actually foils. Motion was running the whole time but peaked at 3.6pt of travel on a 400pt card; it now derives from device attitude against a reference captured on appear, tracks rather than lags, and sweeps most of the card. Reduce Motion keeps the finish and rests the band at centre. Quantity moved from a menu at the bottom of the page into the identity block as a stepper, removal moved to the overflow menu, and holding total appears beside the unit price when quantity exceeds one. The artwork is inset with the card's own corner radius, edge and shadow rather than bleeding square-cornered to the screen edge, and the extracted accent is layered over the system background weighted to the top instead of a single 20% stop that was invisible on device. 864 tests, 1 skipped, 0 failures; verified in the simulator in both appearances.
- Card-detail identity block (2026-09-06): relocated printing provenance and rarity to one glance row, reduced copy condition to the most specific true description, kept quantity beside it, and disclosed all remaining metadata through a collapsed-by-default `LabeledContent` fact list. Unknown finish now becomes an actionable confidence note; treatment, graded, unclassified, and sealed branches preserve their evidence without badge clutter. Added tolerant rarity-token coverage, a local artwork accent, and Reduce Motion handling. Dark/light, expanded, and accessibility-large captures were inspected; the full simulator suite passes 864 tests with 1 skipped and 0 failures.
- Card-detail identity review follow-up (2026-09-06): rarity tokens now retain the provider's exact label while classifying only for tint, so named rarities such as `Illustration Rare` are not flattened. The glance palette now uses neutral/silver common families, gold rare, and orange-red mythic; the condition row is semibold primary text. Focused rarity coverage passes; the full simulator suite passes 872 tests with 1 skipped and 0 failures. Settled dark and light CardDetail captures were inspected and the simulator was restored to dark.
- Scan receipt layout fix (2026-09-06): the receipt's `Undo Scan` label had a large intrinsic width and no compression limit, so it beat both the name and the price for space — the price column collapsed and `$62.47` typeset one character per line as a vertical strip, which set the card's height, while the name and identifier both truncated. Undo is now an icon-only 44 pt bordered button keeping its full VoiceOver label and hint; the price is `lineLimit(1)` + `fixedSize` with priority above the title column; the 40 pt thumbnail is gone in favour of a leading green check, since at that size it could not identify a card and cost the name the width that confirms a fast scan; treatment diagnostics moved to their own full-width line. The `WholeCardScanner` DEBUG route now seeds a receipt fixture, because this surface could not previously be captured without a camera, which is how the defect shipped. Capture in `artifacts/scan-receipt-card.png`; full suite passes 873 tests with 1 skipped and 0 failures.
- Card-detail history/options follow-up (2026-09-06): the per-card history destination now captures its collection key in a stable local before building the SwiftData predicate, matching the safe query pattern used by the rest of the app; this removes the dynamic-query crash path when opening history. The artwork actions menu no longer adds a custom black circle behind its label, leaving the navigation toolbar's single Liquid Glass surface in charge. The patched CardDetail route built successfully, opened History, opened the artwork actions menu, and the full simulator suite passed 872 tests with 1 skipped and 0 failures. Direct screenshot-harness capture lost CoreSimulatorService during `simctl` output, so the loaded XcodeBuildMCP frame was inspected instead.
- Graded slab scanning review hardening (2026-09-06): vendor binding now matches company + numeric grade + qualifier, with the label used only to break stable-axis ties; slab suppression, consecutive identity, held-repeat publication, and catalog-miss verification all carry `ScanSubject`; confirmed slab framing remains sticky until the band exits; non-TAG bare numbers cannot become grades; legacy unbound graded price keys remain readable; graded Price Check refreshes cache exact vendor keys and retries unavailable states; and dismissal paths clear pending graded outcomes. The latch compatibility overloads were removed and the regression suite now exercises the subject-aware APIs directly. Focused tests, the generic iOS simulator test build, and the full simulator suite pass. Per-company slab geometry remains a shared calibration hook, and TAG/SGC calibration plus real-device slab capture remain pending hardware verification.
- Scanner pipeline and session UX implementation (2026-09-06): footer OCR now wins same-frame scheduling, tracking defaults to 8 Hz on non-OCR frames, first-plausible confirmation is pulled forward, slab-label OCR is gated, and signposts cover frame, tracking, OCR, confirmation, catalog, persistence, and success UI. Collection writes use an ordered `ScannerCollectionWriter` `@ModelActor` with value-only commit routing and honest Recognized/Added/Failed feedback. Scan keeps a five-card rail plus full session review with async undo/correction, and departure publishes known/unpriced/unresolved counts while clearing the session; backgrounding does not finalize it. Generic app/test builds pass; simulator tests and visual capture remain blocked by the locked Mac/CoreSimulatorService connection.
- Scanner pipeline review hardening (2026-09-06): JustTCG graded requests now send documented uppercase company tokens, omit unsupported TAG and malformed/named grade filters, normalize numeric grade lists, enforce the v2 `type` discriminator, and consume `grading.canonical` for Authentic display. Refresh matching normalizes stored numeric grades. Scanner finalization now has a bounded drain and per-session write fencing so late actor completions cannot contaminate a later visit. Generic build, focused contract/resolver tests, and the full booted-simulator suite pass; real-card timing and visual capture remain hardware validation work.
- Release follow-up backlog (2026-09-07): removed the dead `PortfolioHistoryMode` plumbing and centralized the remaining launch, scanner hardware, projection profiling, and graded-parser test debt in `release_followups.md`.
- Portfolio movers display redesign loop 1 (2026-09-07): contributor rows now label the right-side amount as total movement and show exact replay-derived per-card movement for consistent multi-copy holdings, with a total-only fallback when the affected quantity is unavailable or varied. Debug build and `PortfolioPhase3` screenshot capture passed; the full simulator suite passed 916 tests with 1 skipped and 0 failures.
- Collection tile plan loop 1 (2026-09-07): collection footer hierarchy, footer quantity badges, finish/treatment display suppression, target-sized remote image decoding, high-resolution collection artwork, bounded local artwork storage, and deterministic CollectionTiles QA route implemented. Debug build, focused treatment/downsampling tests, dark/light accessibility-large captures, and the full simulator suite passed 917 tests with 1 skipped and 0 failures.
- Centering keyboard dismissal (2026-09-07): guide numeric fields now track local focus and expose a keyboard-toolbar Done action that clears it, so the number pad can be dismissed while editing outer or inner guide values. Debug simulator build passed; live screenshot capture was blocked after CoreSimulatorService disconnected.
- Most valuable cards owned (2026-09-08): split per-card market price from total position value, rank the dashboard section by the former, and keep duplicate quantity obvious with the existing badge plus total and per-card values. Added focused ranking coverage and a deterministic duplicate-heavy screenshot route; the settled simulator capture shows the higher single-card price above the larger two-copy total.
- Finish lock menu (2026-09-08): replaced the flattened cross-game picker with native per-game submenus, added game-qualified collapsed summaries, and verified the `WholeCardScanner` route on the iPhone 17 Pro simulator. The initial render showed separate `Pokémon Auto` and `Magic Auto` submenu rows; each opened only its own variants, and an active two-game state announced `Pokémon Reverse · Magic Foil`.
- Finish lock global Auto follow-up (2026-09-09): made `Auto` one top-level reset action that clears every per-game lock, removed duplicate Auto rows from the Pokémon and Magic variant submenus, and labels unlocked game rows only by game. The iPhone 17 Pro simulator shows top-level `Auto`, `Pokémon`, and `Magic`; Pokémon exposes only its ten lockable variants, Magic exposes only its three, and selecting `Magic Foil` then global `Auto` restores the unlocked state.
- Documentation/artifact audit (2026-09-09): reconciled stale checklist language with the current additive market-movement and choice-time Price Check designs, recorded deterministic simulator evidence for collection navigation, movement, portfolio, Browse, centering, Price Check, and Magic treatment surfaces, and separated genuine hardware/provider/review gates into the live follow-up documents. The audit also found and fixed the missing `CollectionProjectionStore` environment injection on the `MagicTreatmentSlice4` debug route; the route now builds, launches, scrolls, and renders its receipt and catalog-detail evidence.
- Scanner cancellation recovery (2026-09-09): dismissing a variant, print-run, or identity choice now clears only that encounter's pending "Saving to your collection..." acknowledgement, so a cancelled no-write scan cannot leave the scanner latched indefinitely. Added regression coverage plus a deterministic `ScanChoiceCancellation` DEBUG route; the focused test and full 955-test simulator suite pass. The rendered capture reached the scanner but was covered by the simulator's notification-permission prompt.
- Scanner choice transition follow-up (2026-09-09): the visible "Saving to your collection..." acknowledgement now begins only at the authorized collection-write boundary, after identity/print-run/variant resolution. Recognition haptics and counting remain immediate, while choice-required scans go directly to their choice bar without a transient save banner. The gated timing regression, focused scanner tests, and full 955-test suite pass; the final `ScanChoiceCancellation` capture was inspected with clean scanner chrome and no save banner, choice, or receipt after cancellation.
- Portfolio tab redesign loop 1 (2026-09-09): implemented the mockup refresh on `portfolio-tab-redesign` with split hero currency, gated period-change badge, direction-tinted capsule range control, gradient area chart with start/today captions, horizontal best-card rail, and pill-based mover rows. The app build succeeds; simulator visual and focused Portfolio test verification are next.
- Portfolio tab redesign loop 2 (2026-09-09): settled iPhone 17 Pro captures were inspected for the full Portfolio, movers, and best-cards states; range switching and the accessibility chart surface were verified; focused Portfolio tests passed 146 with 1 skipped and 0 failures. The existing chart scrub overlay, haptics, and descriptor paths remain intact.
- Portfolio tab redesign remaining polish loop 1 (2026-09-09): restored composed VoiceOver labels for best-card tiles and the hero change badge, removed the obsolete axis-precision helper and its stale test, and added `1D` as the leftmost history range with explicit previous-day/live-endpoint coverage. The iPhone 17 Pro shows a sane two-point 1D chart and all six per-card history segments without truncation; the full Contributors sheet intentionally keeps the shared pill-only rows because its range header and movers explanation already provide the context formerly supplied by the redundant per-row caption.
- Portfolio tab redesign remaining polish loop 2 (2026-09-09): suppressed the published-history caveat for the live-only `1D` window and aligned best-card VoiceOver output with the visible movement line by omitting zero-valued per-card movement from the composed label.
- Portfolio tab redesign remaining polish loop 3 (2026-09-09): rebuilt and reran the focused Portfolio suites after the 1D caveat and zero-movement accessibility fixes; the post-fix 1D capture shows the two-point chart without the misleading “History is being recorded.” message.
- Portfolio tab remaining redesign (2026-09-09): completed the palette, value-series chart, full-bleed layout, labeled market-movement total, distributed six-range control, best-card rail, mover row geometry/dividers, direction badge, and arrow-only pill accessibility pass. Live iPhone 17 Pro captures were inspected at the PortfolioToday, PortfolioPhase3, and PortfolioMostValuable routes; the movers popover exposes Full accounting. Portfolio-focused verification passed 174 tests with 1 skipped and 0 failures.
- Portfolio tab mockup completion: implementing the remaining palette, value-chart, full-bleed layout, mover accounting, rail, and badge polish from AppScreen.dc.html; screenshot loop and focused verification pending.
- Portfolio chart fill boundary (2026-09-09): changed the AreaMark from Swift Charts' padded axis baseline to the accounting anchor value, so positive and negative fills terminate at the dashed period-start rule and cannot tint the sections below the chart. Build/run and live PortfolioToday/PortfolioPhase3 captures pass.
- Collection tile footer plan (2026-09-09): replaced variable badge wrapping with four fixed footer rows, added compact rounded/tabular prices, unpriced caveats and counts, appearance-aware finish dots, relative artwork glow, and shared 30/60 Hz finish motion. Added slab/sealed-first status resolution and focused treatment/specular coverage. Standard dark/light and accessibility-large captures were inspected; the full simulator suite passes 959 tests with 1 skipped and 0 failures.
- Collection tile follow-up (2026-09-09): motion now refuses to start and stops on Reduce Motion changes, the grid only requests motion when filtered content has a specular row, and accent extraction follows both remote artwork URLs plus stale-local fallback. DEBUG logs confirmed all four CollectionTiles fixture accents loaded; the settled capture shows the low colored halo below the artwork. Full simulator suite passes 959 tests with 1 skipped and 0 failures.
- Trust-hardening execution (2026-09-10): committed the design spec and created the adversarial benchmark template; the focused pre-change baseline passed 171 selected tests with 1 skipped and 0 failures. Implementation checkpoints follow.
- Trust-hardening UI loop (2026-09-10): beginning the deterministic `TrustCardDetail` capture with `catalogSilent`; checklist is in `docs/benchmarks/trust-provenance-ui-checklist.md`.
- Trust-hardening UI loop (2026-09-10): fixed the replay helper's missing explicit return exposed by the first UI build and rerunning `TrustCardDetail/catalogSilent`.
- Trust-hardening UI loop (2026-09-10): build passed; simulator screenshot output is being staged in `/tmp` because the sandbox rejects direct `simctl` writes to `artifacts`.
- Trust-hardening UI loop (2026-09-10): app-aware simulator capture reached the `catalogSilent` detail state; it visibly shows “Finish not published” without duplicating the finish row.
- Trust-hardening UI loop (2026-09-10): starting the `finishLock` detail capture after the simulator bridge recovered.
- Trust-hardening UI loop (2026-09-10): made the detail route target the exact seeded collection key and wait for projection readiness; the rebuilt `catalogSilent` capture now opens the intended detail and visibly shows “Finish not published.”
- Trust-hardening UI loop (2026-09-10): the rebuilt `finishLock` detail capture opens the exact fixture and shows the finish together with “Finish Lock” in the identity block.
- Trust-hardening UI loop (2026-09-10): the rebuilt `userConfirmed` detail capture shows “Holo · You confirmed” beneath the exact card identity, with no duplicate finish row.
- Trust-hardening UI loop (2026-09-10): the rebuilt `catalogSilent` scan receipt keeps the provenance line prominent in orange; the receipt also exposes the unknown finish as intended.
- Trust-hardening UI loop (2026-09-10): the rebuilt `finishLock` scan receipt shows “Reverse Holo · Finish Lock” as an attention state.
- Trust-hardening UI loop (2026-09-10): the rebuilt `userConfirmed` scan receipt shows “Holofoil · You confirmed” as the attention state.
- Trust-hardening UI loop (2026-09-10): the rebuilt routine `uniqueInCatalog` receipt stays visually quiet—no attention icon or orange emphasis—while still stating “Holofoil · Only variant printed.”
- Trust-hardening UI loop (2026-09-10): final visual pass is captured through the XcodeBuildMCP simulator workflow; the checklist covers deterministic routing, provenance/accessibility text, attention hierarchy, and safe-area layout.
- Trust-hardening verification (2026-09-10): focused trust suites pass 283 tests with 1 skipped and 0 failures; the full simulator suite passes 980 tests with 1 skipped and 0 failures on the final rerun; the compile-only simulator build also passes. The manual 150–300-card adversarial benchmark remains intentionally not executed and is recorded in `docs/benchmarks/trust-adversarial-benchmark.md`.
- Browse screen loop 1 (2026-09-13): implemented the codebase-corrected Catalog root and set-directory spec with Browse kept as a Collection push destination, an all-lane search model, set rail/game fan, adaptive year-grouped set grid, local sort/filter controls, ownership progress treatment, dark-safe asset tints, and Magic SVG fallbacks. App build and focused BrowseFeatureTests pass; deterministic screenshot capture is next.
- Browse screen loop 2 (2026-09-13): inspected the final deterministic Catalog capture, confirmed the title/search/rail/game hierarchy and sealed entry point, then fixed set-list formatting and deterministic completion-sort ties. Final simulator build and focused BrowseFeatureTests pass; alternate appearance capture was unavailable after CoreSimulatorService became unstable.
- Browse screen loop 3 (2026-09-14): reran the deterministic Browse capture, inspected settled Catalog root, Pokémon set directory, search ordering, sort menu, Started filter, and Magic fallback states, and refreshed the Browse checklist. XcodeBuildMCP build and focused BrowseFeatureTests pass (22/22); the repository-wide run reached 1,163 passed and 1 skipped but still reports 45 unrelated missing-fixture/source-environment failures.
- Browse catalog remediation loop 1 (2026-09-14): fixed non-chronological set sorting/grouping, tile progress and hairline layout, dark progress/badge contrast, lazy sealed search gating, hot-path artwork/set-ordering work, rail readiness, and related accessibility/polish details. The focused BrowseFeatureTests suite passes 28/28 and the app build succeeds; a fresh screenshot attempt was blocked by a recurring CoreSimulatorService connection failure.
- Browse catalog close-out (2026-09-14): removed the lazy sealed-search trigger and stale directory mirror, restored ordered card-then-sealed search, capped fan artwork defensively, simplified recent-row ordering, and added oldest-first/Started-filter coverage. BrowseFeatureTests passes 30/30 and the iOS Simulator build succeeds. Pre-release manual pass remains: confirm set tiles announce their set name and button trait without exposing artwork/progress internals, DisclosureGroup expands and collapses cleanly, and BrowseSetBadgeFill remains legible in dark mode with tiles fitting at AX5.
- Scanning workflow review (2026-09-14): completed roadmap Slices 1–5 and Slice 6 instrumentation: invalidated identification tasks are cleared immediately, scan counter resets no longer flash, dead scanner state was removed, catalog-miss observation hops are gated, informational receipts keep the tab bar stable, and fallback-price queue cost is signposted. ScannerViewModel, CameraPreview, and catalog-miss regressions pass; the WholeCardScanner receipt capture confirms tab-bar/safe-area behavior. The XcodeBuildMCP full simulator run discovered 1,256 tests and reported 48 unrelated fixture/source-environment or signal-kill failures, so the repository-wide suite is not recorded as clean.
- Browse implementation close-out (2026-09-14): implemented the unified card/sealed Catalog search, game-level Cards/Sealed navigation, cached-credential sealed states, dated release rail, game summaries, set sorting/progress copy, missing-art fallback, and grouped Pokémon finish tiles. The prescribed Browse route built and rendered a settled Catalog root with the Collection tab selected, release rail peek, and one row per game. `BrowseFeatureTests` plus `UncoveredSurfaceTests` pass; the full target remains non-clean only in unrelated centering/fixture and scanner-environment tests.
- Browse implementation visual recheck (2026-09-14): after the final grouped-tile cleanup, the simulator briefly returned a black frame while CoreSimulatorService disconnected; a delayed capture after service recovery again rendered the settled Catalog root correctly.
- Browse audit remediation (2026-09-14): stabilized unified pagination task identity and cancellation handling, made cached sealed directories load without credentials, gated inactive card search, cached ranking/grouping hot paths, pre-sorted game-row artwork, added tile re-appearance artwork retry and grid card-count fallback, hardened Magic display identities, and completed the Browse cleanup. Focused `BrowseFeatureTests` plus `UncoveredSurfaceTests` pass; the Debug Browse build and settled iPhone 17 Pro capture pass.
- Browse audit verification follow-up (2026-09-14): corrected the sealed credential test ordering so its provider-call and error-copy assertions are independent, added regression coverage for the inactive Sealed-segment card-search gate, and verified the real `BrowseFeatureTests`, `SealedBrowseSurfaceTests`, and `ViewConstructionSmokeTests` selectors (46 tests, 0 failures). The final Debug Browse build and settled iPhone 17 Pro capture pass; the full target remains non-clean only in the previously identified unrelated suites.
- Collection header redesign (2026-09-14): implemented the Collection-scoped leading navigation row, full-collection value hero, source-aware refresh status, inline search/filter/sort controls, mixed-scope footer semantics, and Settings-based activity entry point. Focused Collection/view tests pass 43/43; dark, light, accessibility-size, and CardDetail navigation captures were inspected.
- Production defect audit pass 2 (2026-09-14): reviewed the repository against `a4375df` for real and highly probable defects; no application code, tests, schemas, or build settings were changed. The findings are recorded in `docs/audits/defect_review_pass_2.md`: six findings, five confirmed and one suspected. F01 — the shipped `UnprovenCloudRestorationReadinessSource` default makes every `openCloud`/`adoptRemoteCollection` decision terminate in `.restoringFromCloud(.failed)` without installing a session, so a clean install on an iCloud-signed-in device reaches a state whose only affordance reproduces itself; the failed attempt has already written `attachmentState = .attached`. F02 — `CollectionStorageHeadlessPreflightDependencies.production` selects `backgroundMode` from the entitlement alone, so the background refresh builds a CloudKit-mirrored container for exactly the `.neverAttached`/`.suspended` stores it then reports as `.onDevice`. F03 (suspected) — `beginPendingResolution` returns without running its operation after the caller has already cleared the pending choice. F04 — `PortfolioEpoch.establishIfNeeded` writes `initialBalance` events with no matching `CollectionActivity`, which `CollectionActivity.integrityDefects` rejects; production is masked only by a `try?`-swallowed `backfillExistingCollectionIfNeeded` running first. F05 — `InventoryLedger.quantities(from:)` retains negative nets and has no production callers. F06 — 36 of the 40 suite failures are absent-fixture failures that `XCTUnwrap` rather than skip, so the exit status cannot carry gate evidence. Build passes; the full simulator run executed 1,277 with 6 skipped and 40 failures, triaged per suite rather than in aggregate, with the three substantive failures reproduced in isolation. The documentation map, repository audit (C-09/C-10/C-11), release framework §14, ownership-ledger audit, and release follow-ups (RF-6, RF-7) were updated to point at the new audit. No physical device, entitled CloudKit container, live provider, second device, or real camera was exercised.
- Per-card price history chart plan (2026-09-14): traced why the card detail chart renders as isolated dots and recorded the plan in `docs/plans/price_history_chart_plan.md`. No code changed; nothing in the plan is implemented. Cause is coverage, not a chart bug: `allDaysChecked` joins two samples only when every calendar day between them has a `PriceCheckDay` row, those rows exist only for days a refresh actually succeeded for that instrument, and `BackgroundPriceRefresh.appRefreshTargetLimit` prices three cards per `BGAppRefresh` launch. Slice A adds a derived carried-forward bridge between adjacent segments, rendered dashed and step-end, so the chart reads as a line while keeping measured spans visually distinct from last-known ones; it introduces no sample, date, or amount, and leaves `samples`/`segments`/`hasGaps` unchanged. Slice B replaces the background count cap with an elapsed-time budget and is blocked on pass-2 F02 plus the new RF-8 device measurement. Provider history backfill was investigated and rejected for this plan: `PriceObservation`/`PriceCheckDay` are the portfolio valuation ledger, so backfilled rows would rewrite published closes; JustTCG does publish a per-day `priceHistory` array and the `include_price_history` parameter is already plumbed with every caller passing `false`, while Scryfall publishes current prices only and TCGdex exposes rolling `avg7`/`avg30`/`trend` aggregates. The documentation map, repository audit, and release follow-ups were updated to point at the plan.
- Follow-up reference wiring (2026-09-15): bound the open pass-2 findings and the per-card chart plan into the active launch plan so they cannot be orphaned when Phase 0/1 execution resumes. The launch plan gains §0.1.1 (a finding→task table: F01/F02 bind Task 4 and Task 8, F04/F05 bind Task 12, F06 binds Task 1 and Task 11, F03 has no owning task and is triaged before RC) and §0.1.2 (current plans outside launch scope, recording that chart Slice B is blocked on F02). Its §0.1 locator was corrected from `0b4ac34` to `a4375df`, §1.5 no longer repeats the "48 unrelated failures" characterisation that documentation audit C-11 marked partially incorrect, and §7 execution discipline now requires re-reading both new sections before a task is started. Back-references were added from the pass-2 audit, the chart plan, and the documentation-audit roadmap row so either document leads to the other. Documentation only; no code, tests, or build settings changed.
- Pro tab and eBay listing photos plan (2026-09-15): recorded `docs/plans/pro_tab_ebay_listing_photos_plan.md` after reading the separate `/Users/seankeller/Documents/eBay Photos` Flask tool and the current Pro/centering source. No code changed; nothing in the plan is implemented. The plan replaces the Centering tab with a Pro tab hosting card centering plus a new card-independent eBay listing-photo module, and ports only the tool's live path: its worker always calls `process_scans(..., use_full_frame=True)`, so contour detection, perspective warp, OCR, and Pokémon-TCG auto-naming are dead code and are not ported; the ported geometry is `create_quadrant_crops`' four overlapping corner crops at `int(dimension * ratio)` truncation, ratio 0.60 front and 0.63 back. Five deliberate divergences are recorded: the ratio throws outside `0.5...0.9` instead of being silently clamped, JPEG quality matches OpenCV's default 95, EXIF orientation is applied during the single decode (the original ignores it and would crop a rotated photo at the wrong physical corners), exports are numbered `01-Front.jpg`…`10-Back-BL.jpg` because eBay uploads in arrival order, and multi-pair batching is scheduled as Slice C rather than dropped. Outputs are native-resolution slices with no resampling: one decoded side is held at a time, `CGImage.cropping(to:)` is relied on as a non-copying view, orientation is baked by decoding through ImageIO with `kCGImageSourceThumbnailMaxPixelSize` set to the image's own longest edge, and file-size pressure is answered by stepping JPEG quality rather than dimensions. Two source facts drive required changes: `CardCenteringView` owns its own `NavigationStack` and must give it up to be pushed, and `CenteringCameraView` sets no `maxPhotoDimensions` and prefers the ultra-wide macro lens, so the capture path would silently produce ~12 MP while the library path produces 48 MP. An earlier draft's claim that `CenteringCameraView` is too coupled to reuse is corrected in the plan; it already exposes `onCapture: (Data) -> Void`. The plan is sequenced after the release candidate is certified.
- Documentation reconciliation (2026-09-15): synchronized the current documentation set with the new Pro tab plan without changing any status claim. The documentation map and repository audit gained Pro tab rows; the active launch plan's §0.1.2 open-plans table now carries the plan with a "must not begin before Task 18" constraint drawn from its own §7 evidence-invalidation rule; `review/opus-card-centering-implementation-plan.md` gained a presentation-scope note stating that the plan may move where centering is presented and add a camera configuration parameter defaulting to today's macro/`.near` capture, but may not loosen, renumber, or waive any centering requirement; and `browse_screen_spec.md`'s "do not change Centering tab structure" constraint and the audit's C-01 evidence line now name the planned rename as proposed and not implemented. Markdown links in the touched files were validated and `git diff --check` is clean.
- Pro tab and eBay listing photos implementation (2026-09-15, isolated `pro-implementation` worktree based at `523f3e2`): implemented Slices A–C from `docs/plans/pro_tab_ebay_listing_photos_plan.md`. The fourth tab is now a Pro module list; centering is pushed without a nested navigation container; the shared camera keeps its centering default while listing-photo capture selects the main wide lens and active format's maximum still dimensions; the eBay workflow captures or picks front/back data, decodes one side at a time with ImageIO orientation, preserves eligible JPEG bytes, emits native-resolution numbered full/corner JPEGs with eBay's 12 MB byte ceiling and quality step-down, and builds sequentially packaged batch folders/archives without SwiftData persistence. Added cropper/export tests plus view-construction coverage and registered all new files in the Xcode project. Focused simulator verification passes 27/27 (17 centering export, 9 cropper, 1 listing-export), and the compile-only simulator build succeeds. Screenshots were intentionally skipped at the user's request; manual, physical-device, provider, archive, and release-readiness gates remain open, and the implementation is not merged back into `main`.
- eBay listing-photo review remediation (2026-09-15, isolated `pro-implementation` worktree): applied F1–F7 from `review/ebay-listing-photos-review-plan.md`. Batch moves and archive creation now run off the main actor; export quality steps continue through `0.45`; camera max dimensions are applied after session commit and read back from the photo output; in-flight batch controls are disabled and batch start is re-entrancy-safe; EXIF orientation transcode coverage was added; both feature temp roots are swept on entry; and the dead `CenteringCameraView` configuration property was removed. The focused remediation selectors pass 14/14 and the Debug simulator build/run succeeds. F3 hardware capture, manual, archive, provider, and release-readiness gates remain open; the implementation is not merged back into `main`.
- eBay listing-photo follow-up remediation (2026-09-15, isolated `pro-implementation` worktree): fixed N1's stale archive publication after cancellation by re-checking generation/cancellation after the detached archive worker returns; fixed N3 by clearing `isPreparingBatch` on an early `processBatch` exit; and fixed N2 test hygiene by injecting the byte budget and using a small high-frequency fixture. The focused remediation selectors pass 14/14 in 12.2 seconds, and the Debug simulator build/run succeeds. Hardware capture, manual, archive, provider, and release-readiness gates remain open; the implementation is not merged back into `main`.
- Browse set-directory remediation (2026-09-15): completed the artwork fallback, checklist-backed denominator, empty-set, incremental price-sort, shared-detail cancellation, truthful price-load, completion-index ownership, and deterministic candidate-priority slices. The focused Browse selectors pass 127/127 with 0 failures; the regenerated external-SSD snapshot contains 157 entries with standard/expanded denominator parity and no `rc`/`sp`/`wp` entries. All derived data, build products, module caches, temporary files, and result bundles for this verification were redirected to the external SSD. Screenshots A8/B6 and live-provider/device measurement C7/RF-9 remain intentionally open.
- Browse set-directory remediation hardening (2026-09-15): fixed case-folded duplicate set-ID checklist reuse, one-pass ownership ranking across provider aliases, retry-triggered completion rebuilds, single price-request identity, memory-warning detail-waiter safety, and artwork candidate deduplication/data-driven parent ordering. The focused Browse selectors pass 128/128 with 0 failures; the regenerated external-SSD snapshot contains 157 entries with standard/expanded denominator parity and no `rc`/`sp`/`wp` entries. All derived data, build products, module caches, temporary files, and result bundles for this verification were redirected to the external SSD. Screenshots A8/B6 and live-provider/device measurement C7/RF-9 remain intentionally open.
- Browse set-directory sort-price cache correction (2026-09-15): fixed two defects found reviewing the second hardening pass. `BrowseCatalog.produceSortPrices` wrote back only the slots the current request covered, so the C5 first-page prefetch truncated a fully priced set's stored ordering map to one page on every cold open and re-crawled the remainder — it now merges into the stored map and carries forward only a fresh envelope, so a stale map's age is never reset without re-pricing the slots the request skipped. Its early returns on cancellation and on a task-group throw also skipped `continuation.finish()`, which would leave the set screen suspended in `for await` with the price banner stuck; the finish moved to a `defer`. Added `testNarrowerSortPriceRequestDoesNotTruncateTheStoredMap`, confirmed failing against the pre-fix write path before the fix was restored. The focused Browse selectors pass 129/129 with 0 failures on the external SSD. Plan C4 and its C6 box were reconciled. A8/B6 visual verification and C7/RF-9 provider measurement remain open.
- Browse set-directory visual close-out (2026-09-15): completed the authorized settled light/dark simulator capture at the Pokémon set directory, confirmed the A8 logo-weight/wordmark/plaque checks, HIF's non-zero `69 cards` count, CRI's `203` completion-denominator parity, and the absence of `rc`/`sp`/`wp` tiles. The same scroll session visually confirmed all eight remaining bundled-logo identities; their exact MD5s are recorded in the remediation plan. Evidence is linked from [`artifacts/pokemon_browse_checklist.md`](artifacts/pokemon_browse_checklist.md). A8/B6 are closed; C7/RF-9 remains open.
- Browse set-directory artwork fallback correction and final revalidation (2026-09-15): the initial A8 frame exposed SVI's dead stored `.png` derivative, so the artwork chain now tries the stored `.png`, its extensionless stem, and the explicit TCGdex `.webp` image derivative in that order, including for older downloaded overlays and inherited parent artwork. The focused Browse selectors pass 130/130 with 0 failures. The final settled light/dark `rerun2` capture shows SVI rendered normally, confirms the logo-weight/wordmark/symbol-plaque checks, HIF's non-zero count, CRI's `0/203` detail denominator, and the absence of `rc`/`sp`/`wp`; A8/B6 are closed again. The eight bundled-logo MD5 results and visual identity checks are recorded in the remediation plan. All build products, caches, temporary files, and result bundles remained on the external SSD; C7/RF-9 remains open.
- Browse artwork/cache hardening (2026-09-16): added TCGdex-only host gating for extensionless candidates, `/univ/`↔`/en/` symbol-prefix fallback, decode-before-persist with eviction/retry for undecodable legacy cache entries, and regression coverage for both invalid and valid cache bodies plus concurrent fetch coalescing. The focused Browse selectors pass 133/133 with 0 failures. A storage-controlled `xcodebuild` rerun routed `TMPDIR`, Clang/Swift module caches, DerivedData, and the `.xcresult` to the external SSD; the result is `.codex-cardscanner-build/browse-set-remediation-20260915/results/browse-artwork-hardening-20260916-external.xcresult`. The XcodeBuildMCP test-products bundle and logs from the initial run were also moved onto the SSD. No screenshots were taken in this follow-up. A8/B6 remain closed and C7/RF-9 remains open. Xcode emitted one non-failing warning that `CardFinishRenderPlanTests.swift` is in the Copy Bundle Resources phase.
- Browse artwork batch / F06 project-resource correction (2026-09-16): verified the 57-file centering corpus is tracked and fixed the duplicate PBXBuildFile/PBXFileReference UUIDs plus the dangling fixture-group reference. The simulator build succeeded and fixture-reachability and corpus-manifest tests passed. The focused selection produced 38 results: 28 passed, 9 test cases failed on known centering accuracy/invariant/performance assertions, and 1 profile-dump test was canceled; this was not a full-suite rerun. Diagnostic-dump tests wrote seven tracked outputs in the repository; exact generated versions were copied to `.codex-cardscanner-build/browse-set-remediation-20260915/results/f06-generated-diagnostics-20260916/`, and tracked copies were restored. DerivedData (including Xcode's module and compilation caches), TMPDIR, result bundle (`f06-fixture-copy-20260916.xcresult`), and preserved generated diagnostics are on the external SSD; the package-source clone path was also directed there (no package fetch was needed). No screenshots were taken. F06's missing-bundle cause is corrected; centering assertions and a complete suite baseline remain open.
- Pass-2 storage/scanner remediation (2026-09-19): implemented F01's safe local fallback and delayed `.attached` manifest claim, F02's manifest-derived headless container mode plus active-mode publication, and F03's pending-answer retention when the identification pipeline is busy. Focused iPhone 17 Pro iOS 26.5 simulator verification passes 64 storage/policy/continuity tests in Debug, the same 64 in DebugProduction with one intentional entitlement-gated skip, 20 readiness tests, and the new pending-resolution regression. Entitled-device clean-install, background-refresh, CloudKit production, archive, and full-suite gates remain open; F03 chose recoverable retry rather than a formal reachability proof.
Exact-branch evidence pass (2026-09-20, candidate `7dbaf40`): focused iPhone
17 Pro iOS 26.5 simulator selection covering scanner, Browse/UI,
collection/projection, Pokémon catalog, and Magic catalog suites executed 581
tests: 579 passed, 1 skipped, and 1 failed in
`ScannerViewModelTests/testCatalogMissVerificationStillFilesUnresolvedCard`.
The storage-safe full simulator suite used external-SSD DerivedData, module
caches, package cache, and result bundle; it executed 1,278 tests with 6
skipped and 4 failures (1 unexpected), spanning current centering,
ownership-ledger, and the scanner catalog-miss test. Result bundles are under
the external-SSD `exact-7dbaf40` directory. The earlier `a4375df` run remains
historical.
- Ownership-ledger gate close (2026-09-20, candidate `7dbaf40`): reproduced and
  fixed F04 by writing baseline `CollectionActivity` alongside each
  `initialBalance` event, fixed F05 by excluding negative reconstructed nets,
  and made source-inventory verification independent of the test runner's
  working directory. The exhaustive mutation/restart/rollback matrix passed
  105 of 106 selected tests with one intentional opt-in skip and zero
  failures. Evidence is in the external-SSD
  `exact-7dbaf40/ownership-matrix.xcresult`; simulator ownership is closed,
  while entitled CloudKit production and two-device convergence remain open.
- Collection card detail redesign (2026-09-22): restructured the detail page into
  centered artwork/identity/valuation, truthful chart, marketplace, ownership,
  and printing-details sections; added the minimum-envelope chart-domain tests;
  the external-SSD Debug simulator build succeeded. The focused chart test
  selection remains blocked by the pre-existing `CardCenteringMeasurement`
  API mismatch in `CenteringExportTests`; screenshot iteration was stopped at
  the user's request after the detail route was visibly reached.
- MEP 095 unresolved-scan messaging (2026-09-22): distinguish explicit
  provider not-found results for exact identifiers from unconfirmed matches,
  preserve the cautious reason when rows merge, and show provider-unavailable
  retry copy. The focused HistoricalTitleCapture, ScannerViewModel, and
  ScanParser selections pass 115 tests; iPhone 17 Pro iOS 26.5 simulator
  screenshots confirmed mixed-row and catalog-only copy plus combined row
  accessibility labels. No physical-device or later TCGdex publication check
  was performed.
- Guided centering repair verification (2026-10-02; uncommitted working tree
  based on `73898e8`): implemented perspective-preserving guide edits, shared
  finite/nested geometry eligibility, request-scoped diagnostics, newest-input
  fencing, and immutable export snapshots. Seven centering classes executed
  109 cases with only the latency case failing (two unchanged assertions);
  the remaining target executed 1,661 cases with seven existing skips and zero
  failures. Original automatic transform research gates remain open; independent
  reviewed annotations validate the guided path. The owner accepted latency
  deferral. Initial phone/default and maximum accessibility captures were
  inspected; toolbar crowding and preview height prompted focused UI refinements.
  Final visual/build verification continues in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Guided centering final verification (2026-10-02; same repair working tree):
  final regression selection passes 1,692 cases with seven existing skips and
  zero failures; the preceding 109-case centering selection retains only its
  unchanged latency failure. ReleaseLocal builds for both simulator architectures.
  Final phone/tablet light/dark, rotation, zoom/pan, numeric-control, and maximum
  accessibility-text captures were inspected. Native simulator confirmation,
  live edge updates, phone share-sheet presentation, and anchored iPad export
  popover were verified. Temporary appearance/text-size settings were restored.
  Physical-device test launch was blocked by a locked-device/runner connection;
  no device pass is claimed. The owner accepted latency deferral; automatic
  accuracy, actual VoiceOver/share/save, and release gates remain open in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Uncommitted-change review (2026-10-02; `73898e8` plus the repair working tree):
  fixed crossed-guide coordinate relabeling, unrecoverable coincident guides,
  double-inversion eligibility, confirmed control-route expansion, and numeric
  fields embedded in Stepper labels. Three geometry regressions were reproduced
  before fixing them. Seven centering classes execute 111 cases with only the
  existing latency case failing; the final UI/export/input rerun passes all 33
  correctness cases, with the isolated latency recheck still failing at
  1.5814/1.8764 seconds median/maximum. Final ReleaseLocal simulator build passes
  for arm64 and x86_64; project parsing, shell syntax, 202 local Markdown links,
  and diff whitespace checks pass. Final outer controls were visually checked;
  the locked Mac blocks the final accessibility-tree and incomplete inner-capture
  rechecks. Current evidence and limits are in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Production refinement B–J implementation (2026-10-03; uncommitted tree on
  `fix/october-review-boundaries` against `dd2a1e3`): separate local monthly
  spending from provider billing counts; fence batch/certificate publication;
  route catalog recovery through the original scan; refresh live Magic
  directories; display slab grades and exact vintage quotes; preserve complete
  activity snapshots on read failure; reject duplicate publisher IDs safely.
  Final signed simulator regression: 1,714 cases, 1,707 passed, seven existing
  skips, zero failures; Pokémon package: 74/74 passed. The initial full run's
  mock and edition-price defects were corrected; its centering latency case
  remains open with unchanged limits. The retry-save harness now waits for the
  task to become idle before answering. The owner deferred further screenshots,
  profiling/device/native acceptance and confirmed legal/support placeholders.
  No commit, deployment, speed improvement, or release certification is claimed.
  See the [implementation and evidence record](docs/plans/october-production-refinement-review-plan.md).

- One Piece scanner choice/UI correction (2026-10-05; `534127f` plus local
  changes): one available verified printing now resolves automatically, matching
  Pokémon/Magic's choice rule; multiple printings and supported finishes still
  ask. The bundled Shiki OP17-047 saves without either picker. Persisted singleton
  choices remain valid only after exact adapter revalidation. The remaining
  picker uses a smaller headline, stacked set subtitle, compact rounded actions,
  and two columns from three choices. Two passing simulator runs cover 118
  distinct cases (97 plus 56 overlapping); phone captures verify long titles,
  accessibility3, 61 choices and unavailable artwork. Native fixture checks
  verify Details without selection, choice 2/61 and skip. The screenshot helper
  accepts an optional capture delay for catalog preparation. Logs/captures remain
  on the external drive; no physical-device or release acceptance is claimed.

- One Piece integrated local acceptance (2026-10-05; `f40e704` plus local
  changes on `merge/one-piece-integration`): implemented the plan's next major
  slice using the full signed owner catalog and actual scanner callbacks,
  printing/finish selection and collection writer. The optional Debug route
  isolates test collection/recovery storage and starts after initial projection;
  ordinary owner launches retain their storage. Initial captures exposed startup
  projection and recovery-load races. The route now waits for readiness; shared
  recovery serializes disk reloads, defers saves and retains removals while loading.
  Full-corpus regressions verify distinct same-number UUIDs, exact mapped/unmapped
  pricing and overdue refresh, Browse/details/add, disk reopen, CSV and skip/retry.
  Nine-class regression: 315/316 passed; its monitor fixture enabled observation
  before starting Portfolio. After correcting the fixture, all five monitor cases
  passed. All 70 One Piece and 96 scanner cases passed in the broader run. Final
  Debug simulator build and helper syntax check pass. Inspected settled picker,
  Normal starter and Foil booster receipts; native recovery/details/retry and
  relaunch checks are recorded in the
  [acceptance checklist](references/one_piece_acceptance_success_checklist.md).
  Evidence remains on the external SSD. The next code slice is explicit
  supersession migration and failed-save collection evidence; hardware/provider,
  CloudKit, rights and release gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).
  The ready-marker loop caught an unsupported unknown-sample series; replaced
  it with OP01-999. The affected real-catalog sample regression passes for every
  route state in `Acceptance-Samples.xcresult`.

- **2026-10-05 — One Piece variants/catalog edge-case audit:** reviewed the
  retained 2,692 canonical cards and 2,745 printings across admission, scan,
  printing/finish choice, Browse, CSV, recovery and exact pricing. Fixed external
  SKU qualifier/numeric alias collisions, duplicate mappings, unanchored product
  appearances, invalid product/finish metadata, missing CSV finish, foreign
  price authority, primary-release order, older persisted printing choices and
  exact One Piece finish-lock identity. Negative cases reproduce the defects;
  full core 44/44 and offline Python 49/49 pass. The broader selected app run
  passed 389/389, including all 2,490 eligible English printings across Browse,
  recognition/choices and CSV finishes. After the final finish-lock fix, the
  affected recheck passed 204/204 (74 One Piece, 96 scanner, 34 variant), including
  the full-corpus walk again. These are separate passing selections. Evidence
  is retained on the external SSD under
  `CardScannerBuild/OnePieceVariantAudit-2026-10-05/`. Catalog statuses, permanent
  UUIDs and ownership/payload formats are unchanged; no retained rows were
  migrated. See the [edge-case audit](docs/audits/one-piece-variants-catalog-edge-cases.md)
  and [implementation ledger](docs/plans/one_piece_code_implementation.md).

- **2026-10-06 — One Piece existing-save reliability** (`230a55f` plus local
  changes on `merge/one-piece-integration`): added disk-backed real-writer
  failure/retry coverage for scanner insert/increment, same-session and relaunch
  recovery, an unrelated subsequent save, six finish-correction combinations,
  and signed catalog price-withdrawal publication. Failed writes preserve
  ownership, claims, ledger lineage, price/history and artwork; retry commits
  once. Withdrawal failure retains installed authority and manual/imported
  values. Source artwork remains available for undo. Scoped Debug hooks throw
  immediately before the normal save; no production save defect was reproduced.
  The initial compile and fixture-expectation errors were corrected. Final
  focused tests pass 5/5; the affected twelve-class Debug simulator selection
  passes 380/380 with no skips/failures, including all 80 One Piece and 96 scanner
  cases. These are separate runs with overlapping tests, not 385 distinct cases.
  Debug and generic `ReleaseLocal` simulator builds pass; the release executable
  contains arm64/x86_64, and its arm64 symbols omit the Debug failure hooks.
  All 149 checked local links and diff whitespace checks pass; no screenshots
  were required for this unchanged interface.
  Results and synthetic fixtures are on the external drive under
  `CodexBuilds/OnePieceSaveReliability-20261006/`. The owner deferred speculative
  supersession under KISS/YAGNI; the retained registry has no correction records
  or superseding printings. Next recommended acceptance slice: existing One Piece
  physical-camera scan/choice/save/relaunch. Mid-save crash recovery across two
  SQLite configurations, full storage/account, device/provider/CloudKit and
  release gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md) and
  [priority reconciliation](docs/plans/documentation_audit.md).

- **2026-10-06 — One Piece camera acceptance preparation** (clean `3fe972a`,
  `merge/one-piece-integration`, before these evidence-document edits): built
  the ordinary signed Debug iOS app with all build data on the external SSD.
  Build and signature verification pass; original name/bundle identity and
  unchanged owner seed hash are verified. In-place installation succeeds on
  iPhone 15 Pro Max / iOS 26.6.1. Launch without review flags is denied because
  the phone is locked. Five compile warnings, no errors; no application code
  changed or tests rerun. Prepared six bounded sample records using the retained
  registry and the existing parent sample selector. All physical observations,
  existing-collection confirmation, camera/save/relaunch, offline/recovery,
  accessibility, provider and sync acceptance remain pending. No uninstall,
  data reset or collection export occurred. Evidence is external under
  `CodexBuilds/OnePieceCameraAcceptance-20261006-3fe972a/`; raw device logs and
  identifiers are not in the repository. Next: unlock/open the usual app and
  present an exactly matched owner card for the first checkpoint in the
  [camera plan](docs/plans/one_piece_camera_acceptance_slice.md); see the
  [device record](docs/plans/one_piece_device_review.md).

- **2026-10-07 — Catalog artwork, visual iteration 1:** initial simulator
  capture confirmed deliberate Magic code tiles, missing One Piece artwork
  projection and card-fan overflow. Reused real Magic card/illustration URLs,
  and constrained fan alignment. Existing regression coverage established that
  One Piece source images are review evidence by default. The owner explicitly
  requested real One Piece cards, so the owner bootstrap now opts into exact
  recorded manufacturer image URLs tied to each artwork's hash; general review
  and production defaults are preserved. One Piece does not use the nautical
  emblem. Missing-art visual QA uses a Debug-only fixture with no collection
  writes. Evidence is external under
  `CodexBuilds/CatalogArtwork-20261007/`.

- **2026-10-07 — Catalog artwork, final visual verification:** corrected the
  illustration bounds so NEW/game badges stay visible, and suppressed failed
  fan slots instead of showing gray card backs. Inspected the settled real
  catalog in light and dark, accessibility-extra-large text, the deterministic
  missing-artwork state and the repeated final dark capture. The owner catalog
  shows actual One Piece card renders; absent One Piece game artwork leaves a
  text-only row. Decorative fans hide at accessibility text sizes. The focused
  browse/One Piece/Pokémon suites passed 216 tests; a final selected rendering
  recheck passed 7 overlapping tests, and the final app build succeeded.
  `git diff --check` passed. The scoped visual/HIG checklist and screenshots
  remain on the external SSD under `CodexBuilds/CatalogArtwork-20261007/`.
  General review/production artwork defaults remain unchanged; this enables
  recorded artwork in the owner's local configuration. No physical-device
  installation or verification was performed.

- **2026-10-07 — Card detail price chart:** added currency Y-axis labels,
  subtle gridlines, smaller observation dots and horizontal scrubbing that
  updates the headline price/date. Unchecked spans show no price; release,
  cancellation and range changes restore the current display. VoiceOver
  stepping/reset actions are implemented; source timestamps can wrap. The
  focused owned/Browse chart tests pass 15/15, including recorded-step and
  unchecked-gap regressions. Inspected synthetic month, held-price scrub and
  gap captures in a separate QA Simulator; native post-release snapshots
  restore the current amount. Existing user edits and Simulator data were
  preserved. Testing concluded at the owner's request; larger-text, actual
  VoiceOver and physical-device acceptance remain unverified. Evidence is on
  the SSD under `CodexBuilds/CardPriceChart-20261007/`; scoped acceptance is in
  [the chart checklist](references/card_price_chart_success_checklist.md).
  The source audit confirms Browse-only local accumulation landed, while
  JustTCG historical series fetching/decoding never landed. Corrected
  aspirational comments and recorded the distinct provider-history slice in
  [the pricing plan](docs/plans/browse_pricing_coverage_plan.md#final-architectural-decision).
  No historical backfill, provider acceptance or release readiness is claimed.
  Final Debug simulator build passes after moving the VoiceOver reset action
  outside the chart modifier chain to resolve a compiler complexity error;
  whitespace checks pass. No additional test run was started after the owner
  requested testing conclude.

- **2026-10-07 — Startup, iteration 1:** replaced separate storage/catalog
  loading labels with one collection opening. The tab tree stays mounted but
  hidden until the first local portfolio result or an integrity defect arrives;
  subsequent replays retain the visible portfolio. The reveal uses a short
  opacity transition and respects Reduce Motion, with no minimum splash time.
  Simulator build succeeded. Visual and focused test verification are in
  progress; synthetic evidence is external under `CodexBuilds/Startup-20261007/`.

- **2026-10-07 — Startup, verified:** inspected the opening in light, dark,
  and accessibility-extra-large text, repeated the final opening capture, and
  verified the settled synthetic Portfolio route shows its value and tabs.
  The simulator build and 8 selected portfolio trust/cold-start/retained-value
  tests passed; `git diff --check` passed. Source review confirms integrity
  defects reveal the failure UI and Reduce Motion disables the reveal fade.
  HIG gate passed for this scoped change. No startup speed measurement or
  physical-device verification is claimed. Evidence and scoped checklist remain
  external under `CodexBuilds/Startup-20261007/`.

- **2026-10-07 — Opening v2, iteration 1:** implemented the supplied lock-on
  handoff plan with one app-level overlay, an honest count from the existing
  valuation pass, matching light/dark launch assets, readiness latching, fast
  handoff and Reduce Motion support. Replaced the first-pass opening views.
  Initial simulator build passed; focused tests and visual checks are underway.
  Evidence is external under `CodexBuilds/OpeningV2-20261007/`.

- **2026-10-07 — Opening v2, review stopping point (unfinished):** stopped
  at the owner's request. The v2 card/guides, captions, app-level coordinator,
  copy-count projection and matching launch assets are implemented and uncommitted.
  Simulator builds passed; the selected opening/portfolio suites executed 93
  tests with 1 skipped and 0 failures, and a later focused recheck passed 15 tests.
  Inspected light and dark/accessibility opening layouts and recorded launch
  frames. **The live Portfolio handoff remains unresolved:** a normal
  `PortfolioToday` launch stays on the opening even though storage is ready.
  Changes to container construction and scene dependency registration did not
  resolve the observed issue. Next: trace runtime/service mounting and the
  readiness reporter, then repeat the motion recordings. Reduce Motion motion,
  warm fast-path behavior, Scan bypass, tap timing and iCloud/error transitions
  remain unverified. Debuggers are detached; unrelated existing user changes
  are preserved. No physical-device readiness is claimed.

- **2026-10-07 — Opening v2, polish iteration:** preserved the owner's
  `Color.clear` bootstrap fix and overflow-safe valuation changes. Slowed the
  guide settle, staggered the ready caption, added a subtle ready outline, and
  expanded the handoff to a 720 ms ready beat plus a 480 ms reveal. Quick-ready
  launches use a shorter beat; Reduce Motion keeps a brief fade without inset,
  entry-offset or scale movement. The opening test suite passed; simulator
  motion captures are underway. This intentionally gives the ready presentation
  more time rather than claiming faster startup computation.

- **2026-10-07 — Browse reliability and One Piece sealed:** implemented on
  `merge/one-piece-integration`, base `1711b06` plus preserved local changes.
  Pokémon checklist/detail authorization now accepts active signed registry
  sets and verified bundled sets under one policy, without granting bundled
  scanner authority. Provider identity/membership and signed count checks remain;
  registry changes invalidate authority, shared provider fetches preserve virtual
  edition context, and mixed release ordering uses complete signed ordering or
  consistent bundled ranks. Cancellation/shared-waiter, stale-price fallback and
  supplemental-pricing regressions remain covered.
  Enabled One Piece runtimes now expose sealed browsing through the documented
  JustTCG mapping, injected capability gates and existing vendor directories,
  pagination, caches, artwork and request budgets. Add/Undo retains existing write
  gates; blocked saving is explicit. Exact vendor sealed variants reach batch
  repricing; raw-card pricing behavior remains covered. Typed recovery feedback
  offers Retry/Refresh Catalog appropriately and retains usable cached content.
  No persistence migration or production rollout/write-permission change occurred.
  Focused browse/checklist/One Piece/pricing tests passed **405/405**, and the final
  targeted recheck passed **95/95**, zero failures (overlapping selections).
  The final Debug simulator build passed; artifacts/results are external under
  `CodexBuilds/BrowseReliability-20261007*`. Earlier failing runs exposed obsolete
  empty-membership fixtures and a request-body-stream fixture crash; the fixtures
  were corrected before the clean runs.
  Cold-launch Browse → Pokémon → first card loaded Tropius / Pitch Black on iPad
  iOS 26.5. The exact reported installed-build card remains unconfirmed.
  Post-catalog-refresh detail loading passed deterministically; a manual live
  full-refresh route remains unverified. An opt-in Debug recorded-provider route
  with isolated collection storage verified One Piece directory → two product
  pages → detail → permitted Add/Undo (quantity returns to its prior value),
  blocked saving, and offline Retry recovery. Inspected accessibility XXXL
  directory/error layouts remain readable, with no empty vendor section on total
  failure; restored the simulator's original text size. Scoped HIG feedback review
  passes; no full VoiceOver audit is claimed. Exact sealed repricing is test
  evidence, not a live request. Live JustTCG acceptance remains open: the existing
  key was unavailable in the simulator and host keychain. Physical-device,
  CloudKit, archive and release readiness remain unverified. Current browse and
  One Piece plans and documentation reconciliation were updated; user changes
  remain uncommitted. All 363 checked local documentation links and
  `git diff --check` pass.

- **2026-10-07 — OP16/OP17 pricing gap investigation:** read-only audit of the
  owner signed payload, retained review decisions, pricing/sort UI and fresh
  public TCGCSV products/prices. The strict canonical-name match holds vendor
  number-suffixed titles: 27 missing mappings for OP17, matching the reported
  count, and 37 for OP16 versus the reported 36 (installed generation/cache not
  inspected). All have unique number-suffixed base candidates; 63 have the exact
  catalog finish and a live quote. OP16-030 is Normal in the catalog but Foil at
  the vendor and requires separate review. All 174 existing mappings validate
  against live data. Missing mappings become unresolved Retry UI; Retry cannot
  add catalog authority. Findings and focused repair direction are recorded in
  `docs/audits/one-piece-op16-op17-pricing-gaps.md`; public captures and per-card
  audit are external under `CodexBuilds/OnePiecePricingGaps-20261007/`. No code,
  signed catalog, collection or rollout changes; no simulator tests required for
  this investigation.

- **2026-10-07 — Systematic One Piece mapping repair:** audited all 2,373
  eligible ordinary-base decisions across 48 sets, then fixed the shared title
  policy for exact short/full parenthesized identifiers and hyphenated full
  identifiers. Independent printed-number, release-group, unique-product and
  finish checks remain strict. Wrong numbers, duplicate products, Alternate Art,
  Manga and other treatment qualifiers remain rejected. Added **406 mappings
  across 39 sets** (OP17 +27, OP16 +36), raising exact coverage to **2,367**.
  Fresh paced public TCGCSV captures validate all 2,367 identities and expected
  finish quotes with zero failures. Six true finish disagreements stay held:
  EB03-001, OP16-030, ST22-001, ST21-001, ST21-003 and ST21-008. No physical
  finish or ownership identity was changed to force a quote.
  Updated corpus/evidence and per-set held-reason reporting; the reusable
  `prepare_one_piece_owner_update.py` validates a mapping-only transition from
  the previous signed baseline and signs/verifies the next owner revision with
  an ephemeral review key. Bundled owner revision **2** retains the previous pin
  and adds its new public pin; local bootstrap supports that explicitly pinned
  rotation. Production rollout, collection permissions and persistence are
  unchanged. All **81 Python**, **46 core**, and **88 One Piece simulator app**
  tests pass. The initial core run exposed an obsolete 1,961-count expectation;
  it was updated for the expanded reviewed corpus before the clean recheck.
  The publication manifests agree and list exactly 406 mapping invalidations.
  The built app contains revision 2 and its pin. Verified against `0641b3a` plus
  local changes after owner commits advanced the checkout during this task.
  Accepted publication, captures, tests and logs remain external under
  `CodexBuilds/OnePieceMappingRepair-20261007/` (accepted signed artifacts are in
  `publication-r2/`). Device installation, CloudKit and release readiness are
  not established. Final Debug simulator build, 271 local documentation links
  and `git diff --check` pass. I did not commit or push.

- **2026-10-13 — Lorcana exact pricing implementation:** implemented Slice 5's
  `LorcanaPriceAdapter` for resolved and stored physical printings, with explicit
  reviewed product/finish mappings, USD aggregate scope, no name/number fallback,
  and independent pricing capability. Reused One Piece's transport/cache logic
  through `TCGCSVProductPriceSource`, with category/group isolation and preserved
  receipt times, coalescing, generation checks and withdrawal watermarks. Public
  category-71 products/prices confirm Lorcana's Normal, Cold Foil and Holofoil
  lanes; those observations do not approve physical UUID mappings. Signed
  snapshots now carry price authority so changed/withdrawn mappings invalidate
  collection/reference quotes before publication, reject in-flight receipts and
  preserve imported manual values. Older unmapped manifests retain canonical
  bytes; mappings do not change ownership keys.
  Debug build and **125 Lorcana/Lorcast tests**, including **13 new pricing
  tests**, plus **88 One Piece tests** pass. Price Check, scanner save, Browse
  detail/sort, collection refresh/relaunch and mapping withdrawal are exercised.
  Broader pricing regression: **321 passed, 1 failed, 0 skipped** out of 322;
  the unchanged Pokémon offline-Browse case fails with `unknownSet`, also when
  run alone. No full-suite success is claimed. Evidence and public-feed hash
  provenance remain on the external SSD at `CodexBuilds/LorcanaPricing-20261013/`.
  Verified at `8613a1d` on `feat/lorcana-implementation` plus local changes.
  Default source discovery remains unpriced until reviewed real physical market
  mappings are supplied; rendered/device/provider-rights, production activation,
  CloudKit and release gates remain open. Current authority is
  [the Lorcana implementation plan](docs/plans/lorcana_code_implementation.md).

- **2026-10-13 — Lorcana rendered UI loop 1:** the isolated iPhone review route
  exposed white controls on a stopped white preview and a first-save ownership
  projection that stayed empty until relaunch. Added a black preview backing,
  dark camera-chrome material, an initial loaded-projection reconciliation and
  a readiness marker for deterministic captures. Initial monitor regressions
  exposed an unnecessarily broad uninitialized-projection replay; restricting
  reconciliation to an existing loaded projection restores all six monitor tests.
  Captures and build/test results remain external under
  `CodexBuilds/LorcanaUIAcceptance-20261013/`.
- **2026-10-13 — Lorcana rendered UI loop 2:** the eight-state iPhone sweep found
  truncated finish titles, an oversized-only action labeled as artwork, and an
  inaccurate missing-card claim for incomplete physical resolution. Fixed full
  title/footer presentation, explicit singleton size labeling, printing-Details
  text contrast and neutral incomplete-lookup copy. Added first-save projection
  and compact size-label regressions. All 204 focused tests pass. A fresh iPad
  iOS 26.5 rendered first save now updates Collection and Browse ownership without
  relaunch. Accessibility-size capture exposed further mode/finish truncation;
  the subsequent final loop completes that Dynamic Type layout replay.
- **2026-10-13 — Lorcana rendered UI loop 3:** inspected all eight final fixture
  states on dedicated iPhone 17 Pro and iPad Pro 11-inch M4 iOS 26.5 simulators.
  Default light and accessibility-extra-large dark layouts pass the bounded
  printing/finish review; the phone scroll reaches both sizes and finishes.
  Exercised Standard/Foil save, immediate scan Undo, repeated-card suppression,
  iPad first-save Collection/Browse projection, Browse Normal add/Undo, persistent
  review ownership and unresolved recovery/retry. Final current-source regression
  passed 204/204 with zero failures/skips; a QoS warning is recorded. Updated
  [the implementation plan](docs/plans/lorcana_code_implementation.md) and
  [UI checkpoint](docs/research/lorcana-ui-review.md), retaining captures/results
  on the SSD at `CodexBuilds/LorcanaUIAcceptance-20261013/`. Real corpus,
  camera/device/VoiceOver interaction, live mapped pricing, production activation,
  sync and release acceptance remain open. No commit or push was made.
- **2026-10-13 — Lorcana live pricing loop 1:** owner authorized public online
  evidence for mapping review. Inspected the publisher's Hades footer/artwork,
  official standard/oversized gift-set package and the distinct oversized market
  image; retrieved category-71/group-22937 products/prices with receipt hashes.
  Added a bounded public-reference local seed with stable app UUIDs and explicit
  Normal/Cold Foil mappings for ordinary Hades; oversized stays unmapped in this
  slice. Added the isolated `LorcanaPricingReview` route, expiring seed-bound live
  test opt-in and existing-workflow acceptance replay. Build-for-testing passes;
  the first rendered choice screen correctly identifies public reference review
  and separate storage. Live/regression results remain in progress on the SSD at
  `CodexBuilds/LorcanaLivePricing-20261013/`; physical packets and production
  defaults are not promoted by this source review.
- **2026-10-13 — Lorcana live pricing loop 2:** actual URLSession/provider
  acceptance passed across the existing Price Check, scanner, Browse, collection
  refresh, relaunch/cache receipt and withdrawal paths. Observed ordinary Hades
  Normal/Cold Foil at $0.19/$0.35 USD aggregate; oversized stays unavailable.
  Initial finalized bundle passed all 86 selected cases; the evidence-anchor
  corrected final replay logs 86 passes; final bundle confirmation follows below. Removing
  the test opt-in produces one expected skip with zero failures. Rendered phone
  Collection/Browse prices, withdrawal without ownership loss, restored refresh
  and independent unpriced oversized all pass. Tablet choice render is inspected;
  automation taps did not advance it, so no tablet pricing interaction is claimed.
  The [public-reference checkpoint](docs/research/lorcana-pricing-review.md)
  records sources and scope; final captures/results remain external.
- **2026-10-13 — Lorcana live pricing loop 3:** final evidence-corrected seed
  build and `live-final.xcresult` pass, verified with `xcresulttool`: 86 passed,
  zero failures/skips, two internal QoS warnings. Xcode finalized the bundle
  roughly ten minutes after case completion. Rendered Normal Price Check shows
  $0.19 plus provider/receipt time and leaves the two Foil ownership rows intact;
  final Collection shows standard $0.35 and oversized unpriced/excluded from the
  total. Mappings and storage remain scoped to `LorcanaPricingReview`; the live
  opt-in is removed and Collection mode restored. Updated the implementation
  plan, source/provider review, documentation map/audit and external capture
  manifest. All 199 checked relative links, JSON/shell syntax and diff whitespace
  pass. Broader mappings, physical packets/device/camera/VoiceOver, production
  rights/keys/activation, sync and release remain open. No commit or push made.
- **2026-10-13 — Lorcana normal rollout loop 1:** owner requested ordinary-app
  pricing and fast production rollout using public sources. Added an offline
  exact-join builder and persistent app UUID ledger: 1,616 mapped ordinary
  printings / 3,232 Normal/Cold Foil lanes across expansions 1–8, retaining the
  existing unpriced oversized Hades record. Fifteen additional rows stay held.
  Normal app registration now composes reviewed physical/pricing/import/write
  authority with the existing discovery/Browse/sealed adapter; source aliases
  cannot authorize ownership and snapshot mismatches fail closed. Generation
  follows both reviewed metadata and discovery/release presentation. Twelve
  Python checks and final build-for-testing pass. Multi-set live/regression and
  normal Browse rendered acceptance are in progress on the SSD under
  `CodexBuilds/LorcanaNormalRollout-20261013/`. No commit, push or release made.
- **2026-10-13 — Lorcana normal rollout acceptance:** finalized bundles confirm
  260/260 scoped pricing/catalog/ownership/activation/One Piece cases, 100/100
  Lorcana/Browse cases, then 66/66 Browse cases after the final rendered fix;
  zero failures/skips, overlapping selections. The first two have three internal
  QoS warnings each. Twelve Python builder tests, resource/hash/UUID validation,
  final Debug build-for-testing, generic simulator ReleaseLocal build, shell
  syntax and diff whitespace pass. Actual normal-runtime live transport returns
  16 exact Normal/Cold Foil quotes across eight expansions; eight saved foil rows
  refresh through the common worker. Removed the expiring live opt-in. Normal
  iPhone Browse displays Ariel's separate $0.13/$0.75 observations, existing
  finish choice and ordinary Collection save/quote/refresh; relaunch retains
  ownership. Fixed held details offering Add and misleading price retries;
  unsupported Fru Fru now shows unavailable/review copy with Add disabled.
  Native Device Hub controls resolved the iPad semantic-tap automation issue;
  normal split-view search/detail shows both quotes and the existing popover
  saves one Normal copy, immediately visible in Collection at $0.13 and retained
  after relaunch. A redundant relaunch accidentally invoked the default `/tmp`
  Debug build and exited 75 with an internal Xcode IDE failure before installation;
  corrected to reuse the tested SSD binary. Current plan, documentation
  map and audit now supersede older default-unpriced/isolated-only claims for
  1,616 mapped ordinary printings while preserving unsupported inventory. The
  earlier Pokémon `unknownSet` failure and physical-device/camera/VoiceOver,
  mixed-client CloudKit, publication/asset-rights and archive/release gates remain
  separate. Receipts, reports, screenshots, logs and results are external under
  `CodexBuilds/LorcanaNormalRollout-20261013/`; no commit, push or release made.
- **2026-10-13 — Lorcana relaunch refresh follow-up:** normal iPad relaunch
  revealed a shared presentation defect: an empty automatic pass can stay idle
  throughout and finish without notifying the small refresh observers. Published
  queue ownership so completion clears the indicator, without changing provider,
  freshness or queue policy. Added a meaningful idle-to-idle observer regression.
  Final phone/tablet relaunch retains normal/foil ownership and prices with a
  clean indicator; explicit iPad refresh returns prices already current. Full
  retained-source generator replay reproduces the bundled market catalog and
  UUID ledger exactly, including 15 held joins. Debug build-for-testing and
  arm64 ReleaseLocal build pass. Post-fix case logs show 239 passed, zero failed,
  two expected live-opt-in skips across 241 selected cases. Bundle finalization
  was initially pending; `xcresulttool` now confirms Passed with those exact totals
  and one internal QoS warning, about ten minutes after case completion. The
  direct architecture CLI flag was rejected before building, then
  corrected to supported ARCHS/ONLY_ACTIVE_ARCH build settings. The existing
  broader Pokémon failure and physical/device/sync/release gates remain separate.
- **2026-10-13 — Lorcana production-check follow-up:** fixed the stale Pokémon
  supplemental-pricing fixture by including its exact card in the set; all 25
  Pokémon TCGCSV cases pass without weakening the production membership guard.
  Finalized storage/schema/forward-compatibility/Lorcana selectors pass 140 cases,
  zero failures, three expected hardware/live opt-in skips and zero warnings;
  shell schema audit passes. Actual generic-iOS unsigned Release and development-
  signed ReleaseLocal archives succeed. Strict signature verification succeeds
  outside the sandbox (the unchanged archive had a sandbox trust error).
  Development export succeeds with the existing automatic profile and no portal
  updates/uploads; initial manual export settings correctly rejected that managed
  profile. Archive/IPA catalog bytes match the checkout, with 1,617 physical
  records, 3,232 mapped lanes, matching discovery SHA and privacy manifest.
  Found an impossible `nil` enum pattern in the existing finish chooser; `.opaque`
  now displays full Lorcana footers. Separate final simulator build and inspected
  initial/final phone/tablet captures show `23/204 EN 1` with intact controls and
  layout. Final signed iOS archive, strict verification and development IPA export
  pass with unchanged catalog hashes and the footer correction; five unrelated
  source warnings plus App Intents metadata extraction remain. Finalized full results
  finish 2,200 cases: 2,186 passed, two failed and 12 skipped. Corrected a second
  stale test expecting Lorcana sealed Browse to throw: it now verifies all 177
  bundled products without JustTCG transport and retains unknown-game rejection.
  Finalized targeted replay shows 276 passed, one failed and zero skipped across
  277 cases; all 77 JustTCG contract cases pass. Centering timing reproduces with
  no competing builds (median 1.663s/max 1.955s vs 0.8s/1.5s limits), so its
  existing app-wide performance gate remains open; budgets/algorithm unchanged.
  The targeted bundle has two internal QoS warnings; the full bundle has five
  QoS/SwiftUI view-state diagnostics and finalized about nine minutes after case
  completion. Both summaries are verified with `xcresulttool`. Updated the implementation plan, legal draft, documentation
  map/audit and new production checkpoint. Current 1.0 sync is unavailable, so
  live CloudKit gates are deferred to enabling sync rather than required for
  on-device Lorcana. Physical cards are unavailable and the paired phone was
  locked; no device installation/camera acceptance is claimed. Website-only
  privacy text, missing support route, provider/asset confirmation and distribution
  remain open. Evidence stays external under
  `CodexBuilds/LorcanaProductionChecks-20261013/`; no commit, push or release.
- **2026-10-18 — Catalog set scrolling/navigation follow-up:** replaced the
  game, set-directory and set-card navigation search drawers with native text
  fields in each screen's top safe-area inset, removing the shared search
  presentation dependency. Set cards now use a stable outer VStack around the
  existing lazy card grid so loading-to-content layout does not depend on lazy
  header estimation. The original intermittent failure did not reproduce in
  the initial simulator sequence; the revised build shows the complete header
  at rest and after returning to the top. Verified Lorcana search, Back while
  focused, immediately responsive Catalog taps/reopening, and the filtered
  Pokémon directory-to-set route on iPhone 17 / iOS 27.0 Simulator. Debug build
  succeeds; all 8 BrowsePaginationRenderTests pass, including the new delayed
  loading/scroll-origin regression. Existing compiler warnings remain. Final
  reopened-set screenshot inspected; evidence is external under
  `CodexBuilds/CatalogScrollFix-20261018/`, with the local checklist in
  `artifacts/catalog_navigation_checklist.md`. No physical-device verification,
  commit, push or release is claimed. Existing and concurrent user changes
  were preserved.
- **2026-10-18 — Reproduced and fixed normal-launch Catalog safe-area loss:**
  user screenshots showed search behind the status bar and clipped card-detail
  artwork. Reproduced on iOS 27 Simulator only after starting on Portfolio and
  switching to Collection before Plus → Magic; the earlier direct-Collection
  checks missed this path. The closed Collection inspector installs a UIKit
  split wrapper around the phone stack and loses pushed content's safe-area
  layout/touch handling in this lifecycle. Compact/unspecified-width filters now
  use a sheet; regular-width filters retain the inspector. Collection chrome,
  navigation and catalog behavior otherwise remain unchanged. New inactive-tab
  navigation regression passes with the fix and fails when restoring the old
  inspector (search minY 19.67 vs required 106 points, on first push and reopen).
  Restored correct code; final suite passes 11/11 Browse/detail render tests.
  Direct touch events verify normal launch → Collection → Plus → Magic → card
  detail → Back → Catalog → Pokémon → Sets → set, scrolling back to its complete
  header, then returning to Collection and opening/closing filters. Inspected
  before/after captures and local checklist; external evidence remains under
  `CodexBuilds/CatalogScrollFix-20261018/`. Optimized signed ReleaseLocal iPhone
  build, strict signature verification, in-place installation and normal launch
  succeed; no uninstall or data reset. Owner confirmation of physical navigation
  remains distinct from install/launch success. No commit, push or release.
- **2026-10-18 — Card detail holo bounds:** removed the flexible artwork stack
  and outer fixed aspect ratio that let the sheen and border extend above and
  below the fitted card. The finish is now an overlay of the naturally sized
  artwork; absent artwork keeps a card-shaped placeholder. Debug simulator
  build and focused finish-plan/detail-render tests pass. Inspected initial
  and final settled holo-card captures on isolated iPhone 17 / iOS 27 Simulator;
  no bands, cropping, or toolbar/content overlap. Evidence is external under
  `CodexBuilds/CardArtworkBounds-20261018/`; local checklist is
  `artifacts/card_artwork_bounds_checklist.md`. Preserved concurrent edits.
  No physical-device verification, commit, push, or release.
- **2026-10-18 — Individual-card provider history** (local changes over
  `a0c707e`): collection and catalog details now request JustTCG's full supported
  trailing year of history for the exact printing/finish or graded listing.
  One Piece and Lorcana consume reviewed mappings from the active catalog.
  The continuous linear chart and range movement use provider prices rather
  than ownership dates or local check days. Separate persistent caching retains
  older points for ALL, preserves history when raw vendor handles resolve,
  and returns the complete merged series to concurrent viewers. Portfolio
  observations/check days, inventory events and closes are not backfilled.
  Final focused iPhone 17 / iOS 27 simulator run: 96 tests passed, zero failures;
  provider v1/v2 contracts, exact-listing isolation, pre-acquisition dates,
  cache merge/concurrency, range/scrubbing and module mapping tests are covered.
  Evidence: external SSD `CardScannerBuild/DerivedData/Logs/Test/` result
  `Test-TradingCardScanner-2026.10.18_08-03-06--0600.xcresult`. Main, empty and
  retry/error simulator states were rendered and inspected using synthetic
  provider-shaped history; checklist: `artifacts/card_market_history_checklist.md`.
  The September rejection of provider history is archived and superseded in
  the current chart authority and documentation audit. All 208 affected local
  documentation links and `git diff --check` pass. Existing user changes were
  preserved. No live-provider acceptance, physical-device install, commit,
  push, archive or release claim.
- **2026-10-18 — Collection detail quote consistency:** the default headline
  now uses the same `PriceDisplay` as ownership value and collection totals,
  instead of replacing it with the newest JustTCG history point. Quote source
  and timestamp are visible; historical movement and timestamps are grouped
  and labeled as history. Removed the Magic-only screen restriction on exact
  marketplace links, reusing the existing cross-game link builder. Debug
  simulator build and 27 focused tests pass (14 link, 13 chart-model). Inspected
  populated-history and empty/error captures on isolated iPhone 17 / iOS 27;
  the synthetic $342 quote remains separate from the historical series and
  equals the one-copy holding value. Evidence: external SSD
  `CodexBuilds/CollectionQuoteFix-20261018/`; checklist:
  `artifacts/collection_quote_fix_checklist.md`. Fresh simulator startup needed
  a settled recapture; an unrelated existing catalog-unavailable banner was
  left unchanged. Documentation links and diff whitespace checks pass. No
  hardcoded user price, physical-device installation, commit, push or release.
- **2026-10-18 — Scanner confirmation placement:** moved passive saving/add
  feedback below the top controls, leaving the footer reading area clear while
  the recent-card rail and session review remain at the bottom. Explicit choices
  retain their existing lower action surface. Camera/recognition geometry is
  unchanged. Added a DEBUG-only 38-card session fixture with no collection writes.
  Simulator build passed; inspected the standard-size 38-card layout on a
  dedicated iPhone 17 / iOS 27 simulator. Evidence: external SSD
  `CodexBuilds/ScannerFeedback-20261018/`; checklist:
  `artifacts/scanner_feedback_checklist.md`. Accessibility-large exposed existing
  title compression and session-control overlap, recorded as unresolved limits.
  Simulator camera guides are absent without live camera input; no physical
  camera alignment, device installation or release claim. Concurrent scanner
  routing/test changes were preserved. Whitespace validation passed.
- **2026-10-18 — Cards Added quantities:** added period-scoped acquisition
  counts from the same replay as added value, exposed each card's copy count
  visually and to VoiceOver, and clarified that displayed amounts are totals.
  Delayed first prices do not count as new copies. The 67 focused replay/history
  tests passed, including changing prices, disposals, undo, and range boundaries.
  Inspected standard light and accessibility-large dark simulator captures;
  quantity labels remain readable and scroll above the tab bar. Initial route
  captures needed additional startup time. Fixed the DEBUG fixture's sealed-key
  check after relaunch exposed repeated sample additions. Final fixture rebuild
  passed; inspected the clean dark-mode capture showing 3 copies at $126.75
  plus 1 copy at $39.39 reconciling to $166.14. HIG gate PASS; no new prompts
  or navigation changes. Evidence on external SSD:
  `CodexBuilds/PortfolioReview/CardsAdded-20261018/`. Concurrent scanner changes
  preserved; no physical-device or release verification claimed.
- **2026-10-18 — Cards Added search:** added native search scoped to the frozen
  period's cards, matching name, set, number, and variant. Search reports the
  matching count and a period-specific empty state. Simulator build and
  whitespace checks passed. Inspected the rendered native search field and
  period contents; source confines filtering to `result.additions`. Simulator
  automation reported successful taps/types without UI changes, then timed out
  after restarting the isolated simulator, so interactive typing/clearing and
  filtered-state screenshots remain unverified. No physical-device claim.
  Evidence: external SSD `CodexBuilds/PortfolioReview/CardsAddedSearch-20261018/`.
- **2026-10-18 — Scanner band and disclosures:** supersedes the earlier scanner
  confirmation placement above. Recent scans/session review and needs-attention
  now live in separate, initially collapsed disclosures at the top. Other scan
  controls and guidance also stay above the footer band; the name/price receipt
  sits below it, using the preview's rendered bounds and a 12-point gap. Camera
  ROI and production conversion are unchanged. Standard-size captures show a
  38-card session and five attention items without footer overlap; expansion
  reveals the rail and review actions. Simulator Debug build and whitespace
  validation pass. Large text wraps the receipt name within a bounded scroll
  surface, but automated swipes did not prove access to offscreen price/Undo;
  recent-scans collapse automation also hits child content. Needs-attention
  expansion and collapse are verified. The other checks remain
  explicit verification limits, not passing interaction claims. Evidence:
  external SSD `CodexBuilds/ScannerBandLayout-20261018/`; local checklist:
  `artifacts/scanner_band_layout_checklist.md`. Preserved concurrent changes.
  No physical-device installation, live-camera alignment or release claim.
- **2026-10-18 — MEE Basic Energy recognition and exact catalog identity:**
  explicitly onboarded denominator-free MEE through a rules-2 Energy descriptor
  and a separate scan namespace, preserving expansion denominators and old
  identities. TCGdex still has only 001–008; reviewed public product records
  supply 009–016 with explicit secondary IDs, exact artwork, Holofoil-only price
  joins, and generic anniversary stamp metadata. Psychic 013 maps to TCGplayer
  713252; Darkness 015 maps to 713254. Bounded checklist regeneration preserves
  every original primary row and produces 16 numbers / 24 slots. Catalog package
  75 passed; final focused Simulator batch 275 passed after correcting fixture
  access (first batch: 3 access failures). Exactly two app builds; no interactive
  Simulator review. Original photo inputs were unavailable, so photo OCR and
  live-camera acceptance remain open. Signed remote activation still requires
  a release including the explicit override; no publication, personal-device
  run, commit or normal-collection mutation. See
  [MEE evidence and commands](publisher/mee-energy-evidence.md).
  Final audit then added an Energy-only exclusion to historical fraction
  matching and regression assertions for false /8 identities. Both app-build
  slots were already used; final guard syntax parsing and diff checks pass,
  but its new assertions were not rerun. The 275-pass result precedes that
  final guard and does not certify the final source in Simulator.
- **2026-10-20 — Unused-code cleanup:** removed the 11 owner-approved
  declarations listed in the [documentation audit](docs/plans/documentation_audit.md)
  after reconfirming no app or test callers. The six source files lose 259 lines;
  active helpers and archived documentation remain intact. Base: `main` at
  `c695da8` plus existing local pricing/history work, preserved throughout.
  A reference scan across 309 app/test Swift files finds none of the removed
  names. Xcode Debug `build-for-testing` for the `TradingCardScanner` scheme on
  the iPhone 17 iOS Simulator destination succeeded, compiling both app and test
  targets with signing disabled. Tests were not executed. Concurrency warnings
  were reported in scanner/storage code outside this cleanup. Build artifacts:
  external SSD `CodexBuilds/DeadCodeCleanup-20261020/`, including
  `Compile.xcresult`; command output: `/tmp/trading-card-dead-code-build.log`.
  Updated-document links and `git diff --check` pass. No physical-device,
  provider, CloudKit, archive, or release-readiness claim.
- **2026-10-20 — Workflow source review, in progress:** reviewed CSV parsing,
  import confirmation, durable per-row writes, interruption/retry, collection
  export, and listing-photo selection, preview, processing, archive, Photos save,
  and cleanup paths. File preparation now restores a pending additional-copy
  import's operation salt before counting completed entries and fences its
  result against collection-storage replacement. Batch pair edits now invalidate
  thumbnail requests before an export directory exists, preventing an old
  request from overwriting swapped front/back previews. Scanner tracing covered
  identification routing, printing/run/finish choices, duplicate authorization,
  collection commit, interruption, undo/correction, and Price Check routing.
  Pending answer requests now remain recoverable until write authorization;
  cancellation before that boundary files them to Needs attention, while
  authorized writes remain excluded. Updated the CSV resume regression and
  authored scanner boundary regressions. Source/diff inspection only; no builds,
  tests, or simulator runs, as requested. This is a checkpoint, not completion
  of the whole-workflow review: finish scanner/catalog/recognition internals,
  collection editing/history/artwork and deletion, Browse/catalog activation,
  foreground/background pricing, portfolio/history/reconciliation, storage
  bootstrap/switching/sync recovery, and centering analysis/export before closing
  the goal. No runtime, device, provider, CloudKit, or release claim.
- **2026-10-20 — Workflow source review, collection and Browse continuation:**
  traced collection filters/projection, quantity editing, activity finish
  correction, removal/restore, local artwork writes and cleanup, and delete-all
  entry points. Consolidated market-history identity changes and Retry into one
  cancellable task in both detail surfaces; cancelled requests can no longer
  overwrite the next chart's cached data, results, error, or loading state.
  Continued through Browse search/pagination, set pages, raw/graded/sealed adds,
  undo, and signed-catalog transport/storage/publication. Sealed cache-miss
  continuations now recheck request ownership before publishing offline state
  or beginning a provider request. Pokémon and Magic startup callers share and
  await the complete persisted load. Pokémon publishes only increasing
  revisions after the persistence await and computes change events from its
  actual published predecessor; registry and revision startup reads use one
  stored-release snapshot. One Piece recovery now validates cached revisions
  and transitions against the bundled fallback, preventing an app update's
  newer bundled catalog from being replaced by an older saved release.
  Authored regression coverage for concurrent startup/activation and newer
  bundled fallback recovery; none was executed. All verification remains
  source/diff inspection, with `git diff --check` passing. No builds, tests, or
  simulator runs. The goal remains open for the scanner/recognition internals,
  catalog cache/provider details, pricing/background refresh, portfolio/history
  reconciliation, storage bootstrap/switching/sync recovery, and centering
  analysis/export passes; these changes do not certify runtime or release gates.
- **2026-10-20 — Workflow source review, pricing continuation:** traced refresh
  target construction/staleness, catalog fetch batching, mapped/free/paid price
  lanes, finish/condition matching, graded resolution/binding, fresh-context
  checkpoints, quote/identity caching, pacing/quota/cooldowns, queue suspension
  and foreground/background handoff. Label-only slab grades such as Authentic
  can now reach graded refresh instead of being stamped unsupported. A failed
  graded checkpoint now discards its staged progress counts with its writes,
  preventing a later save from counting rolled-back prices. Background work
  reports target-build failure to iOS after settling any durable portfolio
  work. JustTCG and Scryfall reject nonfinite Retry-After seconds rather than
  keeping an infinite cooldown. Direct Scryfall card lookup now rejects a
  response whose printing ID differs from the requested ID, protecting refresh
  and metadata callers at the service boundary. Authored regression cases for
  label-only graded refresh, malformed cooldown values, and direct Scryfall
  identity checking; none was executed. Source/diff inspection only;
  `git diff --check` passes. No builds, tests, simulator runs, commits, or
  runtime/release claims. Remaining review: scanner/recognition internals,
  catalog cache/provider details beyond the pricing path, portfolio/history
  reconciliation, storage bootstrap/switching/sync recovery, and centering
  analysis/export. The whole-workflow goal remains active.
- **2026-10-20 — Workflow source review, portfolio/history continuation:**
  traced bulk ledger/evidence snapshots, price-observation reconciliation,
  forward replay and attribution, daily-close publication/revisions, history
  range accounting, and chart/headline presentation. Currency hero values now
  split at the locale's decimal separator, preventing grouping periods from
  splitting German-style values. Same-day Undo collapsing respects the replay
  cutoff, preserving ownership before a later Undo. Synced native-currency
  price transitions now reach local observations, so a USD-to-EUR change is
  explained as loss of USD priceability rather than leaving replay on the old
  USD value. Authored regression cases for localized rendering, before/after
  Undo cutoffs, and synced currency transitions; none was executed. Verification
  is source/diff inspection only; `git diff --check` passes. No builds, tests,
  simulator runs, commits, or runtime/release claims. The audit remains active
  for the remaining portfolio ledger/bootstrap details, scanner/recognition
  internals, catalog cache/provider details beyond pricing, storage
  bootstrap/switching/sync recovery, and centering analysis/export.
- **2026-10-20 — Workflow source review, ownership and storage continuation:**
  completed the portfolio ownership pass through ledger append/deduplication,
  correction and inverse operations, collection Undo lineage, quantity repair,
  and epoch/initial-sync baseline establishment. Traced storage startup through
  store discovery and legacy adoption, manifest/sidecar validation, account and
  anchor policy, attachment confirmation, restoration probes/checkpoints,
  local fallback, headless reuse, session-generation publication, and recovery
  UI. Both fresh-store and existing-store anchor claims now recheck bootstrap
  generation immediately after awaiting the claim, preventing a superseded
  failure or conflict from replacing a newer session's state. Authored an
  unrun regression case that completes a newer retry during each claim path
  and verifies the older failure cannot replace its ready state. Source/diff
  inspection only; `git diff --check` passes. No builds, tests, simulator runs,
  commits, or cloud/runtime/release certification. The goal remains active for
  scanner/recognition internals, remaining catalog cache/provider details, and
  centering analysis/export.
- **2026-10-20 — Workflow source review, scanner recognition continuation:**
  traced camera start/stop and recovery, OCR cadence and frame processing,
  footer/title/label evidence, physical-card latch and explicit repeat permits,
  spatial exit tracking, modern/historical parser arbitration, and the shared
  catalog lookup/printing-choice boundary; continued into Pokémon provider and
  historical identity resolution. Failed Vision or malformed-buffer passes no
  longer feed synthetic empty-band observations into duplicate protection:
  failures clear partial confirmation/evidence windows while retaining the
  consumed-card latch and established slab identity. This prevents an OCR
  outage from counting as proof that a stationary card left. Authored an unrun
  regression case for clearing partial confirmation while retaining consumed
  identity through sustained failures and recovery. Source/diff inspection
  only; `git diff --check` passes. No builds, tests, simulator runs, or commits.
  Remaining audit: game-specific recognition/resolution and catalog caches,
  then centering analysis/export. The whole-workflow goal remains active.
- **2026-10-20 — Workflow source review, recognition/catalog continuation:**
  continued through One Piece and Lorcana footer recognition, verified-printing
  choices and acquisition checks, Magic modern/child-set/historical resolution
  and exact hydration, Pokémon historical/offline resolution, and resolved-card
  disk-cache loading, expiry, persistence, and invalidation. Pokémon offline
  loads now carry an invalidation generation and join the replacement load
  rather than allowing a canceled older load to republish stale entries.
  Set-based resolved-card invalidation now loads the disk cache before removing
  entries, so activation cannot miss saved entries in a cold cache instance.
  Authored an unrun regression case that writes a complete cache entry,
  invalidates it from a fresh instance, and checks another fresh instance still
  misses it. Source/diff inspection only; `git diff --check` passes. No builds,
  tests, simulator runs, or commits. Centering analysis/export and the final
  workflow-coverage audit remain; the goal stays active.
- **2026-10-20 — Workflow source review, centering and completion audit:**
  traced centering image/file/camera input, analysis-generation ownership,
  orientation/downscaling, outer/inner candidate selection and confidence,
  coordinate mapping/rectification, manual guide edits and confirmation,
  ratios/warnings, and snapshot-based image export. The shared still-camera
  controller now matches callbacks to their AVFoundation photo request IDs and
  checks the main-actor lifecycle before publishing either image data or a
  capture error. A late callback after stop/restart can no longer consume a
  newer capture or publish an old image into centering/listing photos.
  Compared the app's Portfolio, Collection, Scan, and Pro routes plus Settings
  actions against this review's workflow entries: scanner intake/questions/
  recovery/Price Check; collection editing/history/artwork/deletion; Browse
  raw/graded/sealed acquisition; CSV import/resume/export; listing-photo
  preparation/export; catalog recognition/resolution/activation/caches;
  foreground/background pricing; portfolio ledger/replay/history; storage
  startup/identity/account transitions/recovery; and centering/export are all
  covered at the source level. Re-read the accumulated implementation and
  regression diffs and checked changed async call sites. No further
  high-confidence concrete findings remain from this review. `git diff --check`
  passes. The requested source-only workflow audit is complete; all authored
  regression cases remain unrun. No builds, tests, simulator runs, commits,
  device/provider/CloudKit validation, or runtime/release certification.
- Workflow source review (2026-10-20; HEAD `0c04c63` plus preserved local work):
  traced major app workflows and catalog publication. Fixed photo retry in
  listing/centering, CSV preparation ordering and stale import errors, and
  Magic publisher pointer rollback. Source/diff and local-link checks only;
  no builds, tests or simulator runs, per request. No runtime acceptance claim,
  commit or push. [Coverage and repairs](docs/release/workflow-source-review-2026-10-20.md).
- **2026-10-20 — Yu-Gi-Oh source integration and corrected safety model:**
  started from clean `main` at `81a6f2c`, fetched and compared reviewed plan
  `fd917fd`, and implemented the bundled catalog builder, recognition module,
  generic supplemental OCR, printing/edition resolution, exact TCGCSV pricing,
  Browse/import/collection adapters and Xcode registration. Edition evidence
  retains contradictory positives independently of illegibility through
  confirmation, retry, record re-filing, recovery merges and tagged persistence;
  physical exit/new encounters clear the partial accumulator. Bare EDITION and
  ambiguous Limited fragments never become First. Product-specific physical
  edition support/completeness is separate from observed price lanes; unknown
  coverage cannot be bypassed by locks or singleton resolution. Valid reviewed
  mappings can discover later prices without a new seed; no edition or low/mid
  substitution. The broad catalog contains 46,504 printings / 37,846 codes from
  659 groups, but **all 46,504 remain quarantined** pending independent physical
  edition metadata (zero automatic/manual acquisition eligible products).
  Offline rebuild is byte-identical; 11 builder fixtures pass. Dedicated iOS
  Simulator verification: 319 focused/scanner cases passed; final affected
  Price Check/pricing/workflow batch 9 passed; final explicit catalog boundary
  batch 2 passed. Neighbor batch: 543 passed,
  1 failure, 3 opt-in skips (547 executed); its sealed-product collection-key
  failure reproduces identically in an isolated archive of unchanged HEAD.
  Counts overlap and are not summed. Both stubbed edition-by-tap and
  printed-edition scan → printing choice → save → exact refresh → CSV export →
  fresh-store import → persistence reload chains pass. Earlier test-build
  errors and corrections are recorded separately. Strict boundary audit stays
  red on the same 48 pre-existing branches; no YGO branch was added to its
  central files. Project integrity, local documentation links and whitespace
  checks pass. HIG source gate retains catalog/usability risks; rendered camera,
  accessibility, provider rights, physical-device, CloudKit, archive/App Store
  and release gates remain open. External SSD evidence:
  `CardScannerBuilds/yugioh/`; raw cache: `YuGiOhSourceCache/2026-10-21/`.
  Journey's devices, processes and saves were untouched. No commit, push,
  deployment or physical-device installation. See the
  [canonical plan](docs/plans/yugioh_code_implementation.md) and
  [commands, counts and remaining owner action](docs/research/yugioh-catalog/verification.md).
- **2026-10-23 — Supplied five-game launch-readiness review (`c4e1198` plus local changes):**
  validated the exact source pin, resolved Release settings and Lorcana payload/
  discrepancy counts. One Piece now requires explicit verified-printing choice
  when a known active held sibling exists; P-001 cannot automatically become the
  winner. Unambiguous singletons and explicit acquisition remain supported.
  Fixed missing local StoreKit scheme configuration and strengthened missing-
  product/JPEG acceptance. Final native selection: 91 One Piece + 8 Collector
  Tools tests, **99 passed, zero failed**, including real local StoreKit
  purchase/relaunch/restore/refund and ordered decodable twenty-JPEG/two-card ZIP
  output. Initial StoreKit setup failure and intermediate old-policy assertions
  are recorded separately. Reconciled Hyperia City's October 23 general release
  and stale monetization-approval wording. Production One Piece configuration,
  Lorcana later-set physical authority, physical-device/camera, rights, public
  pages, sandbox/TestFlight and distribution gates remain open; full five-game
  scope was not reduced. No commit, push, deployment or device installation.
  See the [validated findings and finish sequence](docs/release/five-game-launch-readiness-2026-10-23.md).
  Owner-directed continuation prepared an unsigned production revision-1
  bootstrap candidate on the external SSD, SHA-256
  `251165ad79ebe34e9b2d8a37919f711d8affb2d550386eac7a71bd27d8323c0b`.
  The current publisher validates 2,748 retained printings / 2,367 exact mappings;
  decoded comparison proves only revision/timestamp changed from the reviewed
  unsigned r3, and all 2,745 owner-r2 printing objects remain unchanged. The
  existing host's One Piece pointer returned 404. Signing-environment metadata
  and secret-name API requests also returned 404, leaving protection/access
  unverified. [Production setup and receipt](docs/release/one-piece-production-setup-2026-10-23.md)
  are ready for owner review. No production key generation/provisioning, signing,
  workflow dispatch, publication or activation occurred; production stays disabled.
  Final independent checks: all 46 One Piece core/publisher package tests pass;
  unsigned production replay is byte-identical. Normal Release simulator build
  succeeds for arm64/x86_64 with signing disabled. Built-app inspection confirms
  `ScanStash`, One Piece disabled/writes off, empty production pins/privacy/support
  URLs and absent production seed. These checks do not establish distribution,
  physical-camera, source-rights or production activation acceptance.

## 2026-10-23 — One Piece serialized acquisition and extracted ZIP acceptance

- Validated the supplied focused review at `872dbf2` and reproduced its retained
  automatic-finish defect with signed coordinator activation and disk-backed
  persistence. Closed the gap with synchronous current-authority validation
  inside the collection serializer, preserving eligible explicit selections
  and actionable recovery. Added six writer/scanner regressions, including
  post-preflight activation and retired identities with historical Undo.
- ZIP tests now extract the exact twenty archive entries and decode/compare the
  archived JPEG bytes. Renamed local StoreKit reconstruction coverage accurately;
  actual process restart and system-share/Files handoff remain unrun with an
  exact checklist in the [release follow-up](docs/release/five-game-launch-readiness-2026-10-23.md).
- Fresh Debug iPhone 17 / iOS 27.0 Simulator selection: 97 One Piece + nine
  Collector Tools tests = **106 passed, zero failures**, `xcodebuild` exit 0.
  External SSD evidence: `CardScannerBuilds/yugioh/acquisition-verified.xcresult`
  and `logs/acquisition-verified.log`. Source is `872dbf2` plus local changes;
  production remains disabled and no commit, signing-key, publication or account
  change was made. Local Debug signing is not distribution signing.

## 2026-10-23 — Isolated Collector Tools purchase and cancellation acceptance

- Started clean at `main` / `b6e4728`; preserved the accepted owned Files workflow
  and existing Simulator. Created a disposable iPhone 17 / iOS 27.0 Simulator.
  Actual unowned UI and zero transactions preceded free output and purchase.
- Free UI Save to Files yields exactly ten decodable, byte-matching JPEGs.
  Actual local purchase-sheet cancel retains six pairs, an edited name and swap.
  Successful Xcode purchase yields one configured non-consumable transaction;
  the same pairs generate sixty verified JPEGs without reselection. Actual
  termination/relaunch reloads owned access before Restore; Restore stays at one
  transaction. Same-process background recovery passes separately.
- Real large-image generation canceled at Card 1 of 6, returns to Prepare with
  pairs/name preserved and empty output roots. Retry produces sixty verified
  JPEGs. Existing delayed-completion regression passes. No app repair was needed.
- Added real pending-approval and transaction-count/verified-identity assertions.
  Final focused native selection: **12 passed, zero failures, one explicit skip**
  across 13 cases. Precommit rerun on this checkout confirms the same result;
  `collector-tools-commit-validation-20261023.xcresult` is under the machine-local
  external build root. Do not add this overlapping selection to historical totals.
  The skipped interruption fixture exposes a failed/issue transaction while
  StoreKit 2 already returns a verified unrevoked entitlement; two diagnostic
  runs failed the no-early-access expectation. This remains an acceptance gap,
  not a passed interruption check or proven production-app defect.
- Exact matrix, commands, UI/build identity, retained external synthetic evidence
  and sandbox/TestFlight handoff are in the [release ledger](docs/release/five-game-launch-readiness-2026-10-23.md#isolated-collector-tools-purchase-and-cancellation-acceptance--2026-10-23).
  Only tests and documentation changed; no commit/push or production actions.

### 2026-10-23 — Three-gate independent preparation at `4cefbfa`

- Preserved the existing plan diff. No app/catalog/workflow change, commit,
  push, production key/environment creation, signing, publication or activation.
- Owner confirmed no paid Apple Developer Program account. Enrollment is the
  concrete first blocker for App Store Connect, real-store sandbox and TestFlight.
  Source product ID/type and production scheme configuration match; no real
  product/account availability was inspected or claimed.
- Replayed the 1,749-printing Lorcana catalog byte-identically with unchanged
  UUID ledger; independently reproduced all 1,833 discovery-only discrepancy IDs.
  Captured twelve fresh later-set product/price feeds. Isolated dry run retains
  every existing physical object and deterministically prepares 970 additional
  exact joins / 1,940 mappings; 490 later-set and 373 earlier/special/Quest rows
  remain held. No additions were installed. Set 13's 207 denominator, newer foil
  policy, 19 exact-join holds and newer Hydra artwork/text drift require review.
- Revalidated the retained unsigned One Piece hash and metadata-only difference
  from the reviewed source; current publisher replay is byte-identical. Both
  public pointers return 404. Read-only GitHub environment inventory confirms
  proposed signing and deployment environments are absent. Exact candidate/key
  custody/reviewer approval is prepared; publication and activation stay separate.
- Fresh checks pass: One Piece Core 46; Lorcana Python 14; One Piece Python 47;
  normalization 8; hosting restoration 6. Existing Collector Tools XCTest runs
  were not repeated. External artifacts/receipts/worklist are retained under
  `CardScannerBuilds/ThreeGatePreparation-20261023/` on the external SSD.
  The [launch ledger](docs/release/five-game-launch-readiness-2026-10-23.md#independent-preparation-executed--2026-10-23)
  owns results, limits, owner blockers and approval details. All launch gates open.

### 2026-10-23 — Lorcana isolated candidate and held-row review

- Continued at `4cefbfa` plus prior preparation-document changes. Honored the
  owner's hold on production keys, publication, activation and bundle adoption.
  The active catalog, UUID ledger, configuration and workflows remain unchanged.
- Validated all original 970 additions through native footer resolution,
  supported finish/CSV identity, acquisition checks and representative disk-store
  add/Undo/reopen/CSV replay. That first two-test run passes with no skips.
- Added an explicit opt-in later-set review mode to the existing Python builder.
  Scoped set 13's 207 denominator, 25 explicit separate Normal/Foil product
  pairs, later Epic/Enchanted/Iconic physical numbers/patterns, set-9 zero and
  set-10 single-pattern Whisper Holofoil. Unexpected siblings, multiple foil
  patterns, wrong source groups and duplicate lanes remain held. Default
  generator replay remains byte-identical to the active catalog.
- The isolated candidate now adds 1,440 physical records / 2,652 exact mappings,
  preserving all 1,749 existing physical objects and original 970 identity/
  mapping identities. Second replay with the retained review UUID ledger matches.
  Every original discrepancy row has a disposition: 1,440 validated candidate,
  393 held (20 later-set, 373 earlier/special/Quest). Retained 15 further product
  captures; row-level evidence requirements and exact associations are external.
- Final native selection: **136 passed, zero failed, three existing live-opt-in
  skips / 139 cases**, exit 0. All three candidate checks execute, including
  every new lane through the real pricing adapter using retained feeds; this
  is not a fresh live census. Python discovery/builder tests: **20 passed**.
- Packaging remains blocked: 11,364,404-byte candidate exceeds the 8 MiB
  byte-loader bounds. Typed-manifest acceptance is separate from package loading;
  no bound was relaxed. No paid Apple account is needed for completed checks.
  No physical-camera, rights, accessibility, archive or launch coverage claim.
  Detailed evidence and reproduction are in the
  [candidate review](docs/research/lorcana-expansion-candidate-review-2026-10-23.md).

### 2026-10-23 — Actual Lorcana loader and Disney100 held-row continuation

- Resolved the local 8 MiB blocker with one shared 16 MiB manifest budget in
  registry byte decoding and bundled market loading. The app's actual resource
  loader reads at most each resource limit plus one before rejection; source
  binding, schema/identity/record limits and discovery/Browse bounds remain.
  Signed network payload/envelope limits remain 8/12 MiB.
- Replaced the candidate tests' typed-manifest bypass with byte loading and an
  isolated resource bundle through the same function used by `bundledMarket`.
  Exact original 1,440-addition candidate: five focused tests pass, zero failures/
  skips, including size boundary/oversize/source-binding checks and all mappings.
- Continued the held ledger with six exact Disney100 source/product joins.
  Manufacturer distribution/foil/printed-signature evidence, source footers and
  exact group 23305 products agree. New explicit review option preserves all
  previous objects; signatures are modeled as printed designs, not autographs.
  Isolated candidate: 1,446 additions, 3,195 total objects, 6,022 total mappings;
  remaining held rows: 387. Candidate/replay/UUID ledger and all-row dispositions
  are external under the existing review root's `LoaderAndDisney100/` directory.
- Final six-suite native selection: **138 passed, zero failed, three existing
  live-opt-in skips / 141 cases**, exit 0. All three candidate tests execute,
  including 2,658 exact captured price lanes and foil-only Normal rejection.
  Python builder/discovery selection: **23 passed**. SDK/Simulator diagnostics
  remain; no full-app or physical-device/performance certification.
- Active catalog/discovery/UUID resources, production keys, hosting and rollout
  settings remain untouched. No publication, activation, enrollment or upload.
  The [review checkpoint](docs/research/lorcana-expansion-candidate-review-2026-10-23.md#local-loader-and-disney100-follow-up--2026-10-23)
  owns detailed evidence and the remaining physical/distribution/model checks.

### 2026-10-24 — Portfolio period-switch chart flash

- Kept the completed history result rendered while a requested period computes;
  the selected chip, chart, totals and movers now present the same completed
  period and switch together. Animation follows the displayed range. Scrub
  selection resets on both the request and the completed range change.
- Added delayed-calculation coverage for retained chart rendering (actual
  SwiftUI hosting height), aligned period selection, rapid taps, obsolete-result
  rejection and clearing inputs. Final focused run: **51 passed, zero failures**,
  xcodebuild exit 0; `git diff --check` passes. The first test fixture lacked a
  published close and was corrected before the successful runs.
- Inspected the settled iPhone 17 runtime screenshot. Scoped HIG gate passes;
  existing Reduce Motion and selected-chip accessibility remain intact. Live
  tap-driven animation verification remains limited: simulator input reports
  successful taps without changing the visible selection; native input is
  unavailable while the Mac is locked. No physical-device verification.
- Results, final runtime screenshot and checklist are on the external SSD under
  `CodexBuilds/PortfolioPeriodSwitch-20261024/`. Existing Lorcana work is preserved.

### 2026-10-24 — Device build and focused native verification

- At `e9d26a0`, the focused iOS Simulator run discovered 98 cases: **95 passed,
  zero failed, three live-opt-in cases skipped**. All three prepared Lorcana
  expansion cases and the portfolio period-switch regression test executed.
  Lorcana Python tests: **23 passed**. The changed documentation's relative links
  and `git diff --check` also passed.
- A generic iOS build with signing disabled completed. Xcode found the connected
  personal iPhone, but the signed build remained blocked in Apple's key-signing
  service; the device-targeted retry timed out after three minutes. No app was
  installed. Physical-device acceptance remains open.
- Device-build DerivedData is under the external SSD's
  `CardScannerBuilds/CommitAndInstall-20261024/` directory.

### 2026-10-28 — Yu-Gi-Oh! market history implementation

- Added active-catalog product/edition mapping to the existing JustTCG history
  service; both detail screens now allow Yu-Gi-Oh! charts. Current valuation
  quotes retain their snapshot provenance and dates.
- Final focused simulator selection passed **149 tests, zero failures/skips**,
  including six new history regressions, existing vendor/game contracts and
  chart/render tests. Collection/catalog requests share the same edition cache;
  stale vendor handles and catalog withdrawal cannot redirect it.
- Inspected synthetic chart, missing-key recovery and unavailable-history
  presentation on Simulator; final chart capture uses the isolated QA device.
  See the [history checklist](references/yugioh_history_success_checklist.md).
  Results/screenshots are external under `CodexBuild/YuGiOhHistory-20261028/`.
- HIG source/individual-capture review passes; repeated full-shell visual
  acceptance remains a risk because some QA captures lose static header glyphs.
  Complete individual captures and the limitation are recorded in the checklist.
  Current plans/map/audit distinguish the new history
  provider from valuation freshness; added local links, shell syntax and
  `git diff --check` pass.
- Build/test products use the external SSD. No live-provider, physical-device,
  deployment or release acceptance is claimed.

### 2026-10-25 — Seamless card market-history loading

- Collection and catalog detail now distinguish initial loading, unavailable
  history, an empty selected period and a failed request. Loading uses one compact
  row; saved charts remain usable during refresh and after failures. Empty periods
  offer View all history. Provenance/timestamps live under Price details.
- Removed duplicate startup history reloads for games without catalog-owned
  mappings. Recover the same raw Pokémon/Magic printing's unbound disk cache when
  its product ID is learned, while preserving game/finish/product isolation and
  catalog-activation safeguards. A one-time binding claim prevents recovery into
  a subsequently different product.
- Final focused native selection: **8 passed, zero failures, zero skips**;
  simulator build, shell syntax and `git diff --check` pass. Coverage includes
  cross-launch cache reuse, retained history after refresh failure, listing and
  catalog-remapping isolation, accessible loading size and the recovery binding.
  The final MCP response timed out during rebuilding; its runner continued and
  the completed final xcresult independently confirms the eight passing cases.
- Inspected deterministic iPhone 17 screenshots for loading, refreshing, empty
  period, unavailable, first-load failure and saved-history failure. Added a
  DEBUG-only readiness marker to the existing screenshot harness. Scoped HIG gate
  passes. Simulator taps reported success without changing the period; the action
  is verified at the binding level, not claimed as an end-to-end tap check.
- Build products, final test bundle, screenshots and checklist are external under
  `CodexBuilds/MarketHistory-20261025/`. No physical-device install, live-provider
  verification or release-readiness claim. Existing documentation edits preserved.

### 2026-10-29 — Pokémon collector-tier definitions and external build storage

- Researched Master / Grand Master conventions and recorded the explicit English,
  set/run-scoped contract in
  [the collector criteria review](docs/research/pokemon-master-set-definitions-2026-10-29.md).
  Renamed the displayed tiers while preserving saved `standard` / `expanded` values.
- Master now includes confirmed booster ball/Energy/Team Rocket patterns and
  EX-era stamped reverses. Removed reviewed rarity/reverse descriptor duplicates,
  excluded 151's phantom plain-holo product aliases and Prismatic non-holo Lugia
  from Master, preserved existing ownership aliases and the distinct metal Mew.
  Directory/detail counts share the corrected read-time projection; original
  source resources, fingerprints and holdings are not rewritten.
- Representative Master checks: 151 **360**, Prismatic **447**, Celebrations **25**,
  Classic Collection **25**, Destined Rivals **415**, Brilliant Stars **310**.
  Both 30th builder fixtures retain one Holofoil scope and no duplicate tier option.
  Separately numbered promos, subsets, energies and vintage runs remain separately
  tracked; cataloged Grand Master totals are not exhaustive promo certification.
- Final simulator build/test selection: **122 passed, zero failures, zero skips**
  (84 checklist, 36 ownership/collection, two offline-upgrade cases), including
  all 157 bundled manifest/checklist denominators. Documentation links and
  `git diff --check` pass. HIG source review passes; no new screenshot/device or
  release-readiness claim.
- Moved **12.56 GiB** of generated internal XcodeBuildMCP output, DerivedData,
  archives/products, Xcode/Clang caches and repository artifacts to the T7 with
  verified inventories and compatibility symlinks. Research temporary inputs
  moved too. Final build commands explicitly route host temporary files,
  package/compiler caches, logs and results externally; compiler cache paths
  were verified from the build log. Evidence is under
  `/Volumes/T7/CodexBuild/InternalArtifactMigration-20261029/MasterSetReview/`.

### 2026-10-29 — Repeatable hang inspection plan

- Reviewed clean `main` at `fe7ac88`, existing signposts, optimized profiling
  scheme/dSYM settings and prior device traces. Confirmed installed Instruments
  templates through `xctrace`; the initial sandboxed inventory failed on an
  Instruments cache permission, then the approved read-only retry succeeded.
- Added the [inspection protocol](docs/plans/hang-inspection-plan.md): eight
  ordered scenarios, focused capture instructions, source/stack attribution,
  sanitized finding records and comparable before/after completion criteria.
  Start with the unresolved initial-layout and background-snapshot stalls.
- Linked the workflow from the documentation map, audit and release follow-ups;
  existing issue authorities and device/release gates remain in place.
- Documentation only: no application instrumentation, runtime capture or fix;
  no build/test or new responsiveness acceptance claimed. Local Markdown link
  targets across all five changed documents and `git diff --check` pass.

### 2026-10-29 — Centering rotates only the photo

- Moved manual rotation from the shared photo/guide layer onto the photo;
  exports also leave the guide geometry fixed. Zoom/pan continue moving both
  layers together. Updated the helper text to “Rotates photo only.”
- Corrected earlier render tests and checklist expectations that required
  shared rotation. The documentation audit explicitly supersedes that contract.
- Focused normal Debug Simulator run: **28 passed, zero failures/skips**.
  Tests cover fixed rendered guides, opposite photo rotations, export and
  zoom/pan geometry. The first run's two assertions expected reversed photo
  slope signs; corrected assertions pass. Its runner lingered after reporting
  results and was terminated after the successful rerun completed.
- Inspected the final seven-degree iPhone 17 Simulator screenshot: photo tilted,
  red/cyan guides fixed, controls/title/safe areas legible. Used the existing
  local Collector Tools build flag for the visual check after the normal
  Simulator correctly presented its unowned gate. Final local build, links and
  `git diff --check` pass. No physical-device or live-purchase verification.
- Evidence remains on the external SSD under
  `/Volumes/T7/CodexBuild/CenteringRotation-20261029/`;
  [current checklist](references/centering_guided_success_checklist.md).

### 2026-10-29 — Simpler listing photo controls and optional sides

- Replaced each side's three source buttons with one native Add / Replace menu;
  camera, Photos and Files remain available. Added visible per-side removal that
  invalidates pending loads and generated exports while keeping original photos.
- Single-card generation is now an explicit action. Either attached side creates
  five photos; with both attached, choose Both sides, Front only or Back only.
  Side-only exports preserve 01–05 / 06–10 numbering and all export actions use
  the actual photo count. Batch pairing remains unchanged.
- Focused Debug Simulator run: **38 passed, 1 skipped, 0 failures** across export,
  crop and Collector Tools tests. The existing interrupted-purchase case skipped
  because local StoreKit supplied entitlement early; sandbox acceptance is open.
  Added tests for each side's filenames, pixels, dimensions and ZIP contents,
  plus empty-source rejection. Final UI build and `git diff --check` pass.
- Verified source menu presentation, Photos cancel preserving the attachment,
  removal/empty-state disabling, front-only output/export options, back-only
  output with both inputs attached, and clearing front while back stays ready.
  Inspected light/dark and maximum Dynamic Type; fixed mid-word label wrapping
  using vertical accessibility rows and a scope menu. Final dark preview passes;
  restored Simulator light appearance / standard text size afterward.
- [Acceptance checklist](references/listing_photos_success_checklist.md) records
  the scoped HIG review and manual camera/save/share/VoiceOver limitations.
  Build/test/screenshot evidence remains on the external SSD under
  `/Volumes/T7/CodexBuild/ListingPhotos-20261029/`. No physical-device or release
  readiness claim; pre-existing user changes were preserved.

### 2026-10-29 — Listing Photos mock-up implementation

- Reviewed the supplied HTML's empty, ready and results states as design input.
  Implemented side-by-side source tiles, source thumbnails and corner previews,
  a pinned Generate action, and a separate photo review/export state.
- Added native Files export, source selection from device-local Collection
  artwork, and lossless reorder copies with numbered filenames. Collection
  currently retains one saved photo per card, so the UI says this explicitly.
- Final Simulator build and 31 photo export/crop tests pass without failures or
  skips, including three new preview/reorder cases. The wider run had 40 passed,
  1 skipped and 1 failed; the unchanged local StoreKit entitlement test then
  passed in isolation. No live-purchase or device claim.
- Inspected empty, ready and results states, light/dark appearance and maximum
  Dynamic Type. Fixed decorative badge overflow, primary button padding and
  dark secondary-action contrast found during the screenshot loop. Verified
  source removal, scope selection, Collection empty state, thumbnail selection,
  Make Cover Photo, Files/share cancellation and full-size inspection.
- [Current acceptance checklist](references/listing_photos_success_checklist.md)
  records HIG results and remaining manual checks. Evidence is under
  `/Volumes/T7/CodexBuild/ListingPhotosRedesign-20261029/`; Simulator settings
  were restored. No physical-device or release-readiness claim.

### 2026-10-29 — Photo Styles responsiveness and list usability

- Put side selection first, with 5/10-photo counts and full-row targets. Added
  actual style thumbnails, removed the duplicate picker heading, and defaulted
  the sheet to its expanded size. Large text stacks counts and uses compact
  decorative symbols; long corner labels remain readable while scrolling.
- Kept selection state inside the sheet and applied only a changed final choice
  on dismissal. Verified that Front → Both → Done preserves an existing ten-photo
  export and that Back → Done updates generation to five back photos.
- Replaced full-image preview-task identifiers with lightweight load-state
  identifiers. Added localized 150 ms fades for selection feedback and review
  image changes, with Reduce Motion support. No device frame-rate claim.
- Final Debug Simulator build and `git diff --check` pass. Light/dark, maximum
  text and native list scrolling were visually inspected; no export algorithm
  changes or new implementation-mirroring tests. See the
  [current checklist](references/listing_photos_success_checklist.md).
- Used Keller Family Photos for remaining captures after T7 reached about
  3.6 GiB free: `/Volumes/Keller Family Photos/CodexBuild/ListingPhotoStyles-20261029/`.

### 2026-10-29 — High-confidence production refinement fixes

- Reject ambiguous fallback products before retaining provider handles. Cancel
  shared directory/daily-price waiters promptly while the operation completes
  its own cache publication and cleanup. Retain catalog activation through
  writer contention, coalesce newer revisions and stop for retired sessions.
- Label Lorcana browse-only sets/cards/search results before acquisition,
  preserve supported raw/graded actions, and omit unsupported graded actions.
  A rendered maximum-text check also led to a small stacked Browse filter/badge
  layout. Removed redundant centering source bytes and made failed key removal
  preserve settings state with an error.
- Final normal Debug Simulator regression selection: **431 passed, 6 skipped,
  0 failures**. The skips require prepared Lorcana expansion inputs. An initial
  unsigned Keychain setup failure was corrected by normal local signing; its
  focused rerun passed 53/53. Existing user/concurrent changes were preserved.
- Verified Browse set/card/search notices and accessibility labels, unsupported
  and supported detail actions, maximum text/dark appearance, and dummy-key
  save/remove. Standard Simulator appearance/text size restored afterward.
  See the [implementation and confidence ledger](docs/audits/production-refinement-master-review-2026-10-26.md#2026-10-29-high-confidence-refinement-fixes).
  Evidence is on Keller Family Photos under
  `/Volumes/Keller Family Photos/CodexBuilds/CardScannerRefinement-20261029/`.
- Measurements, published endpoints, catalog expansion and owner-controlled
  release gates remain separate. No full-suite or device/release-readiness claim.
- Centering's deterministic image/controls also render with the existing
  `LOCAL_COLLECTOR_TOOLS` test flag; normal Debug still enforces its purchase gate.
- Final rail QA caught a clipped availability caption caused by the lazy
  horizontal stack's initial height. Reserved caption space in rail tiles;
  the subsequent normal Debug build and 81 Browse/loading/set-artwork tests
  pass with no skips or failures. The expanded 431-pass run preceded this
  final layout-only repair.

### 2026-10-29 — Zero quantity and optional personal sales/trades

- The collection detail minus action can remove the last copy through the
  existing removal/history/undo path. The store also accepts zero quantity
  with its existing stale-value protection; negative quantities are rejected.
- Added optional sale/trade entry with quantity, exact total sale price in USD
  before fees, and notes/received items. Blank prices remain unknown; an
  explicit zero remains zero. Metadata lives on removal activity, persists
  after the last owned copy leaves, and participates in the store digest.
  Personal transaction evidence does not replace provider market prices.
- Normal Debug iOS Simulator regression: **202 passed, 0 failures**, covering
  collection history, ledger completeness, portfolio ledger, store digest,
  schema compatibility, item kinds and forward-compatible games. An initial
  new schema test selected the relationship's entity accidentally; its entity
  lookup was corrected before the green rerun. New coverage includes partial
  sale/full trade, last-copy removal, restore, stale/invalid requests, failed
  save rollback, exact localized amount parsing and reopening a disk store.
- Isolated synthetic simulator interaction verified a $12.34 sale with a note,
  undo, retained Sold history and reviewable original details after restore.
  Final Debug build succeeded after a copy adjustment and deterministic
  ownership capture route. Rendered last-copy decrement removed the card and
  showed Undo; light sale, dark trade and maximum accessibility text/scrolling
  were inspected. Native controls, clarity, legibility, accessibility,
  one-tap decrement and navigation consistency pass the HIG design gate.
  Evidence and generated build data are under
  `/Volumes/Keller Family Photos/CodexBuilds/CardTransactions-20261029/`.
  Physical-device, live CloudKit migration/sync and release acceptance remain
  unverified; these are personal records, with no shared transaction backend.

### 2026-10-30 — Ordered refinement implementation; stopped at S6

**Historical checkpoint:** superseded by the
[2026-10-31 closeout](#2026-10-31--refinement-follow-up-closed).

- Created `refinement/review-2026-10-30` from `f22d28f`. Accepted and pushed one
  commit per slice: S1 `f0149b0` (production owner-catalog exclusion), S2
  `bc6e369` (background fallback writes), S3 `ecd1eab` (bounded coverage read),
  S4 `204d6d7` (reuse incomplete migration reports), S5 `f05a734` (shared launch
  and binding code). No PR was opened. The eight existing uncommitted changes
  were preserved and excluded from these commits.
- Accepted slices passed their required simulator builds/tests with normal
  signing. S1: 102 passes; S2: focused regression plus 498 expanded passes and
  six prepared-data skips; S3: 86 reconciliation passes, one opt-in skip,
  129 expanded passes and both deliberate benchmarks; S4: focused regression
  plus 109 expanded passes; S5: three build configurations, 48 passes and one
  device-only skip. Actual Yu-Gi-Oh! file classes and the Magic migration class
  were selected explicitly where the supplied suite name was insufficient.
- At 300 instruments × 365 days, S3's full coverage read measured 1.057006 s
  before and 0.961710 s after; with yesterday's close present it took
  0.025211 s, about 2.6% of the full read. Refresh-index construction measured
  0.129414 s before and 0.101061 s after. External test-run specifications
  supplied benchmark variables that Xcode did not forward from the shell.
- S6's optimized on-disk fixture trace measured a 6.884908291 s lower bound from
  launch storage start to the first refresh-attempt signpost. The one-line
  change passed M08's focused case but its expanded run crashed in SwiftData
  through queued portfolio recomputation. Xcode restarted, then stalled
  finalizing; the runner was terminated with exit 143. Reverting only S6 made
  the identical selection pass: 119 passes, one benchmark skip, no failures.
  S6 remains reverted and uncommitted; no broader engine fix was attempted.
- The stop rule leaves S7a, the conditional S7b gate/upgrade check and final
  expanded regression pending. No scan-write benchmark, index benefit,
  minimum-OS change or upgrade acceptance is claimed. Release still excludes
  the 20.9 MiB owner catalog, while Debug retains it.
- See the [dated implementation and stop-gate ledger](docs/audits/production-refinement-master-review-2026-10-26.md#2026-10-30-refinement-implementation-and-s6-stop-gate).
  Evidence is external under
  `/Volumes/Keller Family Photos/CodexBuilds/refinement-review-2026-10-30/`.
  The temporary seeder was removed; no logs, screenshots, stores or results were
  committed. Device lock-wait, mature launch and quantity-edit checks remain
  owner-run. No device/provider/CloudKit/archive/release readiness claim.
