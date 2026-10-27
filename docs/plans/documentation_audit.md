# Documentation and artifact audit

**Audit date:** 2026-10-02; implementation evidence updated 2026-10-27
**Purpose:** reconcile the chronological progress log, implementation plans,
QA checklists, and simulator evidence so that an old “pending” note is not
mistaken for a current defect—and a real validation gap is not lost in the
history.

## Current authority boundary — updated 2026-10-27

**M06 collection owned-game choices repaired locally — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's M06 evidence](../audits/production-refinement-master-review-2026-10-26.md#m06-collection-game-filter-omits-owned-games)
supersedes its earlier source-only finding status. Three native regressions
reproduced the picker offering only Pokémon/Magic despite held Lorcana,
Yu-Gi-Oh!, One Piece and a retained unknown game. Choices now use unique
identities from the full collection snapshot, independently of search/selected
game and browse/write capabilities; known descriptor ordering and raw unknown
labels are retained. An emptied current selection remains valid until changed
or cleared. Set/finish/treatment reset semantics and other filters are unchanged.
Three focused tests and all 124 expanded collection-query/item-kind/BrowseCollection
cases pass with zero failures/skips; finalized summaries contain no runtime
warnings. Source HIG gate passes. Phone/tablet sheet/inspector rendering and
VoiceOver acceptance remain unverified; no provider, CloudKit, full-suite or
release gate closed and no later finding implemented.

**M05 opening readiness handoff repaired locally — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's M05 evidence](../audits/production-refinement-master-review-2026-10-26.md#m05-opening-handoff-adds-waiting-after-readiness)
supersedes its earlier source-only opportunity status. The hosted production
container reproduced about 444 ms fast and 757 ms slow readiness-to-handoff
waiting. Removed only the pre-reveal sleep and two hold constants; retained
fade/scale, Reduce Motion reveal, settling, loading gates and recovery/reset.
All nine focused opening tests pass. Expanded verification selected 69 cases:
68 passed, zero failed, one physical-device data-protection case skipped. Both
finalized summaries contain no runtime warnings. Fixed hosted normal-motion
handoff measured about 32 ms fast / under 1 ms slow in the focused run and
1.5 ms / 0.7 ms in the expanded run. These are controlled Debug simulator
handoff measurements, not total launch or touch-delivery claims. The initial
fixture build's read-only environment override was corrected before accepted
red/green evidence. Source HIG gate passes; native Reduce Motion settings,
VoiceOver focus/announcements, rendered transition and Release-device cold/warm
interaction acceptance remain unverified. No later finding or release gate
implemented or closed.

**M04 reviewed UI ownership scope complete locally — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's completion and caller sweep](../audits/production-refinement-master-review-2026-10-26.md#m04-completion-and-caller-sweep--2026-10-27)
supersedes the earlier remaining-caller notes below. Sealed add/Undo, Browse
release-order backfill and Portfolio quantity repair now use the existing
background writer. CSV import and collection deletion also await background
exclusive-lock entry, preserving the same-task identity gate and token barrier.
A native characterization reproduced five blocking shapes at about 510–632 ms
under forced 500 ms contention. Seven focused tests pass, including responsive
heartbeats, price/ownership lineage, stale/mixed repair refusal, real promotion
authorization, cancellation/storage retirement and exclusive-token cleanup.
Expanded verification selected 616 cases: 615 passed, zero failed, one existing
opt-in benchmark skipped; finalized summary inspected with no runtime warnings.
Includes all 74 history cases and previous expanded selections. An initial new
fixture compile error was corrected before baseline evidence was accepted.
No additional named M04 UI action implementation slice remains. Automatic
catalog activation/normalization, Magic migration, portfolio epoch setup/retry
and shared pricing/cache service transactions retain their broader authority,
maintenance and launch boundaries; they are not certified as nonblocking.
Release-device latency and rendered pending/back/Cancel/VoiceOver acceptance
remain unverified, as do provider/CloudKit/full-suite/release gates. Later
findings were not implemented.

**M04 graded-picker acquisition follow-up — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's graded-picker evidence](../audits/production-refinement-master-review-2026-10-26.md#graded-picker-acquisition-follow-up--2026-10-27)
records a blocked main-thread heartbeat and about 669 ms under forced contention.
The confirmation now awaits one method on the existing scanner writer/private
executor; the store's atomic add/price/lineage and certificate rules are unchanged.
The main-actor optimistic promotion preflight/duplicate gate branches were removed;
real promotion retains the existing same-task permit retry. The save task is
view-owned, certificate editing pauses while pending, and canceled/retired
completions do not dismiss the picker. Five focused tests pass. Expanded native
verification selected 609 cases: 608 passed, zero failed, one existing opt-in
benchmark skipped; finalized summary inspected with no runtime warnings. Includes
all 42 item-kind, 67 history and 36 BrowseCollection cases and previous M01–M04
expanded selections. Exact selected-listing pricing remains valid independently
of M02's stricter automatic binding rules. The remaining sealed acquisition,
Browse backfill and Portfolio repair work was subsequently completed above. Rendered pending/
back/Cancel/VoiceOver, device/provider and release acceptance remain unverified;
no later finding implemented.

**M04 catalog/raw acquisition follow-up — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's catalog/raw evidence](../audits/production-refinement-master-review-2026-10-26.md#catalograw-acquisition-follow-up--2026-10-27)
records blocked UI heartbeats in add, acquisition Undo and the initial catalog
price checkpoint (about 524–647 ms under forced contention). These writes now
use the existing scanner writer's dedicated executor with fresh contexts,
post-lock lifecycle checks and same-task identity retry. Imported aliases,
finish/edition/provenance and exact Undo stay intact. Ownership commits before
the separate price attempt; price failure returns the durable receipt/warning,
never an acquisition retry. Callback quote checkpoints also use this worker;
the shared fallback resolver's existing main-actor identity-cache work is unchanged.
Pending feedback and mutation matching preserve the Undo window and failures.
All eight final focused cases pass after correcting a new non-USD fixture
assumption and restoring the checkpoint's write-time freshness policy, whose
omission was caught by the delayed-quote regression before acceptance. Expanded
verification selected 604 cases: 603 passed, zero failed, one existing opt-in
benchmark skipped; finalized summary inspected with no runtime warnings. Includes
all 67 history and 36 BrowseCollection cases, the three earlier artwork cases,
executor/ownership/UI coverage and previous M01–M04 selections. The catalog detail
view no longer calls the synchronous serializer or saves price contexts directly.
The subsequent graded-picker and final sealed/backfill/repair completion are
recorded above. Device/provider/rendered
pending-state/VoiceOver and release gates remain unverified; no later finding implemented.

**M04 detail artwork/metadata follow-up — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's detail metadata evidence](../audits/production-refinement-master-review-2026-10-26.md#detail-artworkmetadata-follow-up--2026-10-27)
records blocked main-thread heartbeats in all four synchronous transaction shapes
(about 507–538 ms under forced contention). Photo preparation/file ownership,
artwork mapping/removal, graded finish correction and marketplace persistence
now use the existing detail writer and dedicated executor. Fresh validation,
shared files, retained-game suppression and task-bound identity authorization
stay intact. Native regression also reproduced a repeated-finish no-op Debug
assertion; the detail worker now explicitly rolls back that fresh no-op context.
Six focused cases pass after reconciling a new test's incorrect graded-ledger
expectation and fixing that assertion. Expanded verification selected 557 cases:
556 passed, zero failed, one existing opt-in benchmark skipped; finalized summary
inspected with no runtime warnings. Three additional existing artwork regressions
passed in a separate prepared-build run after correcting their XCTest class
selection; finalized summary inspected with no runtime warnings. No
synchronous serializer calls remain in the detail view. M04 stays open for
catalog/raw, graded-picker, sealed acquisition and Portfolio quantity-repair
writes. No later findings, provider/device or release gates were implemented.

**M04 undo-banner follow-up — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's undo evidence](../audits/production-refinement-master-review-2026-10-26.md#undo-banner-follow-up--2026-10-27)
records the shared Collection/Portfolio restore sequence blocking a main-thread
heartbeat for about 518 ms under forced contention. Both banners now await the
existing activity writer's snapshot overload, preserving store validation and
same-task identity authorization. Pending feedback pauses Undo/Dismiss; completion
checks preserve a newer banner and suppress retired-store results. Five focused
tests pass, including stored-snapshot authority, ledger agreement, stale/repeated
refusal, queued cancellation/storage retirement and the existing identity gate.
Expanded verification selected 551 cases: 550 passed, zero failed, one existing
opt-in benchmark skipped; finalized summary inspected with no runtime warnings.
All 53 history cases, both executor tests and earlier M01–M04 selections pass.
The first focused build's new immutable-field fixture error was corrected without
changing production behavior. Evidence is in the external SSD's `M04-undo-*`
bundles/logs. The subsequent detail artwork/metadata slice is recorded above;
catalog/picker and Portfolio quantity-repair writes remain open. Rendered pending-state/VoiceOver, ordinary device latency and release
gates remain unverified; no later findings implemented.

**M04 activity/history follow-up — 2026-10-27, `028b135` plus working-tree changes:**
the [master report's history evidence](../audits/production-refinement-master-review-2026-10-26.md#activityhistory-follow-up--2026-10-27)
records all four old history write sequences blocking main-thread heartbeats
under forced contention. Backfill, per-entry removal, restoration and correction
now await a dedicated background model actor with fresh serialized contexts and
the existing identity gate. Pending/retry state preserves complete snapshots,
surfaces backfill failure and pauses actions; correction returns a value-only
fallback receipt built on its owning executor. Final expanded verification:
547 selected, 546 passed, zero failed, one existing opt-in benchmark skipped.
This includes all 49 history and 51 fallback cases and earlier M01–M04 selections.
An overly specific test assertion was reconciled; a separate runner-startup
disconnect and simulator-launch wait recovered without shared-service resets or
code changes. No synchronous serializer calls remain in the activity/history view.
History read/projection performance stays measure-first under P06. M04 remains
open for detail artwork/metadata, catalog and picker writes; the subsequent
undo-banner repair is recorded above. Later findings and device/release gates
remain open.

**M04 bounded local repair — 2026-10-26, `028b135` plus working-tree changes:**
the [master report's M04 evidence](../audits/production-refinement-master-review-2026-10-26.md#m04-ui-ownership-actions-can-block-the-main-thread)
records a forced-contention reproduction: the old detail write blocked a queued
main-thread heartbeat for about 515 ms. Detail quantity/removal now await a
dedicated background model actor using the existing serializer/executor and
identity retry gate. Pending controls, storage/cancellation fences, stale-removal
quantity validation and durable removal receipts preserve the interaction and
ownership contracts. Five focused tests pass; expanded verification selected 490:
489 passed, zero failed, one existing opt-in benchmark skipped. This repairs
only the detail quantity/removal slice at that checkpoint. The subsequent
activity/history and undo-banner repairs are recorded above. Artwork/metadata,
catalog and picker writes remain open; no later finding or device/release gate is closed.
Pending-state screenshot/VoiceOver acceptance and ordinary Release-device latency
remain unverified.

**M03 local repair — 2026-10-26, `028b135` plus working-tree changes:** the
[master report's M03 evidence](../audits/production-refinement-master-review-2026-10-26.md#m03-csv-price-interpretation-can-corrupt-imported-valuation)
records native reproduction of foreign/decimal-comma values entering USD prices,
observations and ledger evidence. The single-file CSV repair defines supported
headers and USD numeric formatting, rejects ambiguous/duplicate price columns,
and retains inventory when price interpretation is unsupported. Four focused
tests pass; expanded verification selected 470 cases: 469 passed, zero failed,
one existing opt-in aged-store performance benchmark skipped. M01/M02 selections
remain passing. Historical imports/history are not automatically repaired, and
re-importing the same inventory remains idempotent. M04's subsequent bounded
repair is recorded above; its remaining callers and runtime/release gates stay open.

**M02 local repair — 2026-10-26, `028b135` plus working-tree changes:** the
[master report's M02 evidence](../audits/production-refinement-master-review-2026-10-26.md#m02-unknown-finishes-can-receive-authoritative-graded-prices)
records native reproduction of unknown-finish bindings/quotes and conflicting
catalog-singleton matching. The resolver, matcher and durable guard now require
physical finish evidence before a new automatic binding; unknown unbound refresh
skips vendor work. Exact existing listing handles remain refreshable. Six focused
regressions and the final 318-test expanded selection pass, zero failed/skipped,
after reconciling scanner fixtures that assumed the old unsafe behavior. Historical
bindings/prices are not bulk cleared because their origin is not persisted. This
superseded report-only status for M02; M03's subsequent repair is recorded above.
Later findings and release gates remain open.

**M01 local repair — 2026-10-26, `028b135` plus working-tree changes:** the
[master report's M01 evidence](../audits/production-refinement-master-review-2026-10-26.md#m01-certificate-less-scanned-slabs-can-merge-different-finishes)
records a failing finish-collision regression followed by the bounded store
repair. Existing ownership keys/history remain stable; incompatible finishes
receive separate holdings and unknown finishes do not silently refine another
acquisition. All six new regressions pass, including binding, certificate
refinement, correction, undo/restore, on-disk reopen and CSV. Expanded verification
is 123 passed / 124 executed: the sole sealed-product metadata assertion also
fails in the cached pre-fix build. It is not repaired or counted as green.
This superseded the reconciliation's report-only state for M01; M02's subsequent
repair is recorded above. Other findings and runtime/release gates remain open.

**Production refinement review reconciliation — 2026-10-26, `028b135`:** the
[master findings report](../audits/production-refinement-master-review-2026-10-26.md)
is the working authority for the two supplied reviews, with all 19 original
findings accounted for. It merges synchronous removal into the broader UI-write
issue, retains graded identity/valuation defects first, and distinguishes
source-validated behavior from reproduction and measurement work. The supplied
review's performance percentages, blanket lazy-grid/cutout conclusions,
actor-isolation allegation, and proposed removal of mapping/OCR safeguards are
not adopted. Existing implementation/release plans retain their scope; this
documentation-only reconciliation closes no runtime, provider or release gate.

**Magic publication operational check — 2026-10-25, `9c73abe`:** the
[publication runbook](magic_catalog_key_handling_runbook.md#publication-failure-and-recovery--2026-10-25)
records a successful candidate preparation followed by missing signing/Firebase
credentials in run 40191118826. Its descriptions of protected and automatic
environments are setup requirements: fresh inspection found an empty,
unprotected Magic production environment and no Magic automatic environment.
The temporary Pokémon public pin also remains unreplaced. These operational
gaps supersede any inference that the documented environment setup is deployed;
no credentials, protection settings, rollout or hosting were changed.

**Lorcana actual-loader follow-up:** the
[current checkpoint](../research/lorcana-expansion-candidate-review-2026-10-23.md#local-loader-and-disney100-follow-up--2026-10-23)
supersedes the 8 MiB local packaging blocker recorded below. Shared 16 MiB local
manifest bounds, bounded resource reads and the same app resource-loader path
accept the exact 1,440 candidate. Six further Disney100 records pass isolated
acceptance, leaving 387 held. Final focused result: 138 passed, zero failures,
three live-opt-in skips / 141 cases; 23 Python tests pass. Signed transport bounds,
active catalog resources, keys, hosting and rollout remain unchanged/on hold.

**Lorcana isolated expansion review on `4cefbfa` plus local tooling/tests:** the
[candidate review](../research/lorcana-expansion-candidate-review-2026-10-23.md)
supersedes the unreviewed-970 preparation status with 1,440 native-validated
candidate additions and 393 explicitly held discrepancy rows. It does not
change the bundled production catalog, historical physical evidence or launch
coverage status. The 8 MiB delivery bound remains a packaging blocker. The owner
has explicitly placed keys and production changes on hold, superseding the
earlier pending key-provisioning request; paid Apple enrollment is still absent.

**Three-gate preparation on `4cefbfa`:** the
[execution record](../release/five-game-launch-readiness-2026-10-23.md#independent-preparation-executed--2026-10-23)
records exact Lorcana/One Piece replays, fresh preparation tests and an isolated
970-printing Lorcana dry run. None is adopted production authority. The owner
confirmed no paid Apple Developer Program membership, so enrollment precedes
App Store Connect product setup and sandbox/TestFlight acceptance. One Piece
signing/deployment environments are absent in fresh read-only inspection;
key creation, publication and activation remain separate approvals. This
supersedes any inference that the remaining account issue is merely sign-in.

**Five-game attachment review on `c4e1198`:** the
[launch follow-up](../release/five-game-launch-readiness-2026-10-23.md)
confirms the Release-only One Piece configuration gap and Lorcana discrepancy
counts. Hyperia City is released as of October 23, so earlier upcoming wording
does not exclude it from the current denominator. The bounded One Piece safeguard
requires review when a known ineligible sibling survives beside a verified
singleton; older automatic P-001 winner expectations are superseded by this
working-tree change. Full five-game, physical-device and distribution gates
remain open. Test evidence is recorded separately from implementation.
The documentation map's older monetization “pending owner approval” wording is
also superseded by the October 20 owner-approved offer in the monetization plan.

**Automatic scanning pass, local 2026-10-22 on `1ac6750`:** the
[automatic-family verification](../research/yugioh-catalog/automatic-family-verification.md)
supersedes older blanket manual-printing/zero-automatic statements only within
260 independently crosswalked families. The implementation is release-driven
and game-wide; source certification remains bounded. Unknown edition coverage,
uncertified releases, physical camera and production/release gates remain open.

**Focused pass on `7502144`:** the
[current local evidence](../research/yugioh-catalog/audited-verification.md#correctness-and-bounded-local-acceptance-on-7502144--2026-10-23)
supersedes the older open suspended-recovery-preflight and static bundled-wording
items: the former is native-verified, and active-source copy is fixed and rendered
with explicitly synthetic approved authority. Multi-quantity mixed-game CSV
persistence/resume/additional copies are native-verified. The system Files
variation and rendered totals remain unperformed because the Mac is locked;
older seven-copy Files evidence does not close this new variation. Shared quantity
intent/history fixes are separate from production trust, continuity, bounded
new-bundle policy and release gates. No new production activation is claimed.

**Latest review follow-up on `38fd8e6`:** the
[command-boundary evidence](../research/yugioh-catalog/audited-verification.md#latest-review-follow-up-on-38fd8e6--2026-10-22)
corrects the supplied review's Magic failure attribution: hosting restoration
succeeded, then publication failed with an empty signing-key binding. An early
required-variable preflight improves diagnostics; it does not provision secrets
or resolve production configuration. The same evidence retains explicit CSV,
mixed-game, suspended-preflight, active-source wording and bounded-rollout gates.

**Latest review corrections on `9a1d8b0`:** the
[new evidence](../research/yugioh-catalog/audited-verification.md#latest-review-corrections-on-9a1d8b0--2026-10-22)
supersedes the completion checkpoint's delivery-admission assumptions: signed
parent revision locators enable bounded ancestor catch-up, the publisher executes
the app's full catalog loader, and durable lineage sums reject arithmetic overflow.
Production delivery remains disabled; remaining UI and release gates are retained.

**Completion checkpoint on `eb12b5c`:** the
[latest evidence](../research/yugioh-catalog/audited-verification.md#completion-checkpoint-on-eb12b5c--2026-10-21)
supersedes the historical Files Save blocker and candidate-only delivery seam
below. Actual isolated CSV export/import succeeded. Cyclic correction Undo is
repaired, and approved delivery code is implemented locally but disabled without
owner-supplied production configuration. Earlier native totals are overlapping
snapshots, not a cumulative final-suite result. Physical, provider and release
gates remain open.

**Generic iPhone 17 follow-up:** the [interactive record](../research/yugioh-catalog/audited-verification.md#generic-iphone-17-interactive-acceptance--2026-10-21)
supersedes the older QA-device tap blocker for normal selection, recovery,
Browse Add, maintenance and reopen. Disabled recovery choices are now rendered
and verified. CSV export/import was pending at the system Files sheet at this
checkpoint; the successful isolated roundtrip in the completion evidence above
supersedes that limitation. Physical camera and live production delivery remain
separate open gates.
The 54-test and 37-test follow-ups are separate selections, not cumulative totals.

**Residual F3/F4 after reviewed `09c4a40`:** the earlier blanket closure wording
did not cover retired editions with durable duplicate rows, browse-only bulk
deletion, or compact recovery choices. The [residual evidence](../research/yugioh-catalog/audited-verification.md#residual-f3f4-corrective-pass-after-09c4a40)
now records focused fixes and real-store/recovery regressions for those paths;
historical test counts below do not establish their acceptance. Interactive and
physical-camera evidence remain separate gates.

**Yu-Gi-Oh corrective pass after `1a3242d`:** the
[canonical plan](yugioh_code_implementation.md) now separates persisted holding
maintenance from new admission and historical missing quotes from successful
current checks. The earlier claim below that correction/final save shared one
membership predicate did not cover retired editions or discovery-only runtime
maintenance; the [new evidence](../research/yugioh-catalog/audited-verification.md#corrective-pass-after-four-commit-review)
supersedes it. Local signed-candidate consumption is implemented and tested;
production signed delivery and interactive acceptance remain open. Earlier native
counts are retained as dated evidence and are not added to the new 425-test gate.

**Yu-Gi-Oh audited contract — 2026-10-21:** the
[current authority](yugioh_code_implementation.md) separates supported exact
membership from exhaustive coverage and quote availability. It supersedes the
2026-10-20 complete-family prerequisite, global unavailable runtime and proposed
starter-subset gate. The [pre-audit authority](../legacy/plans/yugioh_implementation_pre_audit.md)
preserves those historical claims. Earlier scanner conflict/retry repairs remain
in place; they were not reverted. The full raw-cache rebuild preserves all
46,504 original IDs and admits 46,303 explicit exact-product choices, with zero
automatic products and 239 in-app discovery records. Historical quotes are dated
bundled snapshots; provider observations do not certify physical exhaustiveness.
The [current verification](../research/yugioh-catalog/audited-verification.md)
separates tests from locked-Mac interactive UI, camera and production-delivery
gates. The boundary audit still reports its pre-existing 48 branches. Debug-only
isolated UI routing is distinct from production adapter behavior.

**Workflow source review — 2026-10-20:** the
[source review record](../release/workflow-source-review-2026-10-20.md) lists
major workflow traces and five additional repairs from `0c04c63` plus preserved
local changes. At source-review completion, no builds, tests or simulator runs
had been performed. The later requested ReleaseLocal build, signature check and
physical-device installation are recorded there; the app was not launched and
those source-review changes have no test-suite or post-install runtime evidence.
Earlier native evidence below does not validate those edits.

**Bounded card-detail cleanup — 2026-10-20:** the
[cleanup evidence](../release/card-detail-cleanup-2026-10-20.md) covers chart
domain reuse, stable artwork, observed overrides, manual primary refresh and
source/check attribution. It preserves current provider priority and source-age
freshness policy. The reported hang remains unconfirmed; this separate work
does not absorb the F1–F13 or Collector Tools scope.

**Bounded bug repair evidence — 2026-10-20:** the
[F1–F13 repair handoff](../release/verified-bug-repairs-2026-10-20.md) records
native regressions against `e2c37ad` plus local repairs. Earlier source-only
review notes do not describe this runtime verification. This does not certify
physical-device, provider, CloudKit, purchase or release readiness.
The continuation audit adds compatible graded-quote preservation and interrupted
held-repeat copy intent; its final affected native run passes 804 tests with
zero failures and one opt-in skip, and the app builds. Full interactive UI
acceptance remains incomplete in the handoff; the full goal is not certified.
The later review follow-up from `0c04c63` repairs certified-slab edition pricing
and same-session failed-copy prompt restoration. Its affected suites pass 167
tests with zero failures/skips; these overlap earlier counts and do not replace
the broader historical run or close interactive acceptance.

**Launch commercial reconciliation — 2026-10-20:**
[CARDSCANNER_LAUNCH_MONETIZATION.md](CARDSCANNER_LAUNCH_MONETIZATION.md) is the
single authority for retained founder rationale and the owner-authorized offer:
free core, free single-card photo output (including one pair in Batch), and the
$9.99 US one-time Collector Tools bundle for unlimited batch photos plus existing
guided centering/output. Its §10 supersedes the earlier batch-only proposal and
paid one-pair batch recommendation. Implementation starts from clean `be183f2`;
the `922dc9b` gap table is explicitly historical. Source presence is not runtime
acceptance. No live purchases or account actions occurred.

This supersedes the blanket free-only/no-StoreKit recommendations in the launch
plan, release framework, retention contract, strategy and shared-cache plan,
and the photo plan's post-1.0 commercial sequencing. Their top-level notices
preserve the prior decisions without making them competing offer authorities.
The C-15/C-18 entries below describe September reconciliation history, not a
veto on this approved bounded implementation. Any older scan-cap, collection-cap or paid-basic-
export recommendations are **superseded recommendations**, not launch tasks;
the bounded documentation search found no active numeric cap or paid-basic-
export proposal to amend individually. Free portability remains explicit.
The Lorcana acceptance ledger's no-StoreKit description is historical source
evidence, not commercial policy or rights clearance. No release gate is closed
by retaining this proposed offer.

**Unused-code cleanup — 2026-10-20:** on `main`, base `c695da8` plus
existing local pricing/history changes, removed 11 owner-approved declarations
after confirming no app or test callers. In
[`CollectionCardDetailView.swift`](../../TradingCardScanner/Views/CollectionCardDetailView.swift),
these were `AppCardBadge`, `AppCardSurface`, `CardDetailSourceLegend`,
`PortfolioMovementSummaryCard`, `conditionRow`, and
`CollectionArtworkStore.removeUnreferencedFiles(keeping:olderThan:)`.
The remaining removals were `CollectionCSV.canonicalImportText(_:)`,
`PriceObservationLog.backfillFromRecordsAndReturnObservations(...)`,
`PriceQuoteService.matchesResolvedIdentity(returned:resolved:)`,
`JustTCGV2GradedClient.gradedVariants(...)`, and
`TradingCardScannerApp.makeBackgroundContainer()`.
Active identity matching, observation reconciliation, graded lookup, headless
storage preflight, and reference-validated artwork cleanup retain their existing
implementations. Archived badge examples remain historical; they are not current
component guidance. Browse history and gated catalog/scanner work remain outside
this cleanup. Verification is recorded in the
[progress log](../../progress.md); this maintenance does not establish release
or physical-device readiness.

**Individual-card history decision — 2026-10-18:** the owner superseded the
September rejection of provider history. The [current chart authority](price_history_chart_plan.md)
now uses JustTCG's historical series independently of ownership dates and
local check days, with separate persistence and unchanged portfolio replay.
The former continuity/background-refresh proposal is preserved in the linked
archive; it does not constrain the market chart. Provider window and simulator
evidence limits remain explicit in the current authority and progress log.

**Pricing correctness follow-up — 2026-10-18:** the
[execution plan](pricing_correctness_and_coverage.md) separates correctness,
reviewed mapping recovery, shared retrieval and the complete coverage census.
Earlier native-EUR current-display behavior is superseded by the USD contract.
Missing mappings are catalog coverage rather than proof of an upstream null or
a failed provider request. Earlier mapped-lane live checks do not establish
coverage for discovery-only records. The new plan records its own bounded
simulator evidence and leaves provider/device/release acceptance open.

**Four-game specialty coverage — 2026-10-15:** the
[coverage authority](../audits/card-coverage-gaps-and-research.md) links a fresh
four-game review and reproducible discrepancy ledgers. Its exact Pokémon rules
and 132 Lorcana Enchanted additions supersede broad-ball and ordinary-only scope
claims for this adopted subset. Earlier 1,616/3,232 Lorcana totals remain dated
evidence; current mappings total 1,748/3,364. PLG20's provider code is not its
printed PRM code, correcting the earlier proposed length-only remedy. One Piece
review data now contains three more verified parallels, while the signed owner
seed remains revision 2 because new-key/pin activation requires explicit approval.
Review-corpus improvements cannot be presented as installed owner coverage.
The current One Piece source permits sole-verified resolution even when physical
coverage flags are false; older prose implying those flags enforce abstention is
not the current runtime contract. New known siblings require choices, and the
new acquisition check prevents an automatic save from bypassing that picker.

**Latest Lorcana edge-case sweep — 2026-10-14:** the
[production checkpoint](../release/lorcana-production-acceptance.md) records three
additional reproduced defects and five new tests: unreachable mapped batches,
explicit no-price completion, malformed/invalid daily caches, valid null/zero
reuse and independent healthy Pokémon batches. The final rebuilt shared/live
selection passes 162/162 with two internal QoS warnings; all 3,232 enabled lanes
return valid fresh-feed quotes. No mappings/models/CSV/UI changes, archive/export,
web update or physical acceptance occurred. The earlier 154-case recovery
selection remains historical intermediate evidence; current full-target/archive
certification is not inferred from the newer scoped run. Deferrals remain in force.

**Lorcana collection integrity/recovery — 2026-10-14:** current candidate starts
clean at `ec6d64c` plus local changes. The [production checkpoint](../release/lorcana-production-acceptance.md)
records seven new acceptance tests, the reproduced transport cooldown failure,
and fixes in the shared TCGCSV source and mapped refresh cancellation handling.
Final regression passes 154 cases, zero failures, three deliberate live skips
across 157 cases, with one internal QoS warning. It includes exact Normal/Foil
ownership/quantity/undo/relaunch/CSV and failure/interrupt/resume scenarios,
One Piece integration and shared CSV/refresh lifecycle checks. Separate price
records persist locally but are intentionally outside inventory CSV transfer.
No mappings, models or CSV format changed. Earlier full-target/live/archive
evidence remains snapshot-specific; no new archive/export or full-target run is
claimed for these recovery fixes. App Store exports and web page/URL work remain
explicitly deferred; physical/source-rights acceptance is not closed.

**Independent Lorcana continuation — 2026-10-14:** the
[production checkpoint](../release/lorcana-production-acceptance.md) now records
all 3,232 enabled lanes passing fresh-feed acceptance and 19/19 pricing cases
passing with live opt-in. The new full-matrix test uses the shared pricing
workflow and skips in ordinary/offline runs. Catalog and UUID ledger reproduce
byte-identically; 12 Python tests and the CloudKit source audit pass. The strict
game-boundary audit finds 48 pre-existing branches identical to `HEAD`, with no
Lorcana match; it remains an architecture debt check rather than passed evidence.
Local App Store export failed for a missing distribution profile, without portal
changes or upload. Earlier full-target counts remain a separate baseline because
this continuation changed tests only. Evidence and earlier finalized artifacts
are retained on the reconnected SSD. Physical and deferred page work were excluded.

**Owner scheduling update — 2026-10-14:** privacy/support page publication,
live verification and app/App Store Connect URL configuration are explicitly
deferred until resumed. The [implementation plan](lorcana_code_implementation.md),
[legal checklist](../legal/README.md) and [Bluehost guide](../legal/bluehost-publication.md)
retain the prepared work. Older pending/fix-first instructions for that step
are superseded as active work; the submission prerequisite remains uncompleted.

**Lorcana nonphysical close-out — 2026-10-14:** the
[production checkpoint](../release/lorcana-production-acceptance.md) supersedes
the older timing/full-suite failure status below for the current working tree
on `feat/lorcana-implementation`, base `8613a1d`. Native scalar and median work
passes exact kernel/geometry/profile checks without changing resolution,
confidence, selection, thresholds or latency limits. Final REQ-022 upper median
is 0.586 s and maximum 0.649 s. The finalized complete simulator target reports
2,188 passed, zero failed, 12 skipped and five runtime warnings. An initial
seven-case Browse rendering failure was caused by the outstanding simulator
camera permission dialog; all seven passed after foreground setup, followed by
the clean complete rerun. No pagination source/assertion change was needed.
Rebuilt actual iOS development archive/export and strict resource/signature
checks pass. The disconnected SSD required temporary internal build/cache
fallback; original cache links are restored. [Bluehost files/guide](../legal/bluehost-publication.md)
and [reviewer notes](../release/lorcana-app-review-notes.md) are prepared, not
published/submitted. Existing live privacy/support URLs still fail app-page
acceptance. Hardware, rights/provider details and distribution remain open.
Historical 2026-10-03/13 centering failures are retained as dated evidence;
they are not the current simulator timing outcome. Neither this update nor
the green simulator suite closes the centering contract's hardware/held-out gates.

**Historical Lorcana production checks — 2026-10-13:** the
[production checkpoint](../release/lorcana-production-acceptance.md) records real
iOS unsigned Release and development-signed ReleaseLocal archives, strict
signature verification and a development IPA export with the exact bundled
catalog. Focused storage/compatibility checks pass 140 cases with three expected
skips. The earlier Pokémon `unknownSet` failure was a stale set-membership fixture;
the corrected fixture passes all 25 Pokémon TCGCSV cases without weakening the
production check. Finalized full simulator results have 2,186 passed, two failed
and 12 skipped across 2,200 cases, with five runtime diagnostics. A second stale contract
assertion expected Lorcana sealed discovery to be unsupported; it now checks the
existing bundled path with no JustTCG transport and unknown-game rejection.
Finalized targeted results have 276 passed, one centering timing failure and zero
skips across 277 cases, including all 77 JustTCG contract cases passing. The targeted
bundle has two internal QoS warnings; both summaries are verified with `xcresulttool`.
The timing failure reproduces without competing builds;
it remains under the existing centering/refinement performance gates. This is
not a green full-app baseline, and no timing thresholds were weakened.
Physical cards are
unavailable and the paired iPhone was locked, so hardware acceptance remains open.
The live privacy URL is website/waitlist-only and support returns 404; app-page
publication/configuration, source/artwork scope and distribution acceptance remain
open. Current production wiring keeps collections on-device with sync unavailable.
Earlier Lorcana notes requiring mixed-client CloudKit before any local rollout
are superseded: live sync gates remain deferred until sync is enabled. Existing
CloudKit matrices are not marked passed. Remote signed delivery is likewise
optional to the bundled candidate. This checkpoint is not full-app certification.

**Lorcana normal pricing rollout — 2026-10-13:** the owner authorized expanding
online-reviewed mappings and enabling normal app workflows. The
[rollout checkpoint](../research/lorcana-normal-pricing-rollout.md) and
[implementation plan](lorcana_code_implementation.md) now own 1,616 mapped
ordinary printings / 3,232 lanes across eight expansions, plus preserved discovery
and sealed coverage. Normal app registration enables exact ownership/import and
pricing through existing shared components. A 260-case scoped regression and
100-case follow-up pass with zero failures/skips; a rendered unsupported-printing
fix has a further 66/66 Browse replay. These overlap and are not full-suite totals.
The final relaunch pass found and fixed empty automatic refresh queues failing
to publish completion while status stayed idle. The finalized post-fix bundle confirms
239 passed, zero failed and two expected live-opt-in skips, including a new
observer regression, with one internal QoS warning. Debug and arm64 ReleaseLocal
rebuilds pass. Xcode finalized the bundle about ten minutes after case completion.
Earlier default-unpriced/disabled-write/isolated-only statements below and in
dated discovery/physical/signing checkpoints are historical for this ordinary
scope. They remain accurate for held source rows, which cannot authorize ownership
or prices. Physical packets, device/camera, publication/asset rights and distribution
acceptance remain separate; see the later archive results above. Mixed-client
CloudKit is deferred for on-device 1.0. Future signed remote hosting
is optional to this bundled release, not a prerequisite to its runtime registration.

**Earlier Lorcana local live pricing — 2026-10-13:** the owner authorized online source
review. The [pricing checkpoint](../research/lorcana-pricing-review.md) and
[Slice 5](lorcana_code_implementation.md) record a bounded public-reference
Hades seed, exact Normal/Cold Foil joins and live existing-workflow acceptance.
Final focused result: 86 passed, zero failures/skips; two QoS warnings.
Earlier no-real-mapping/no-live-evidence claims are historical for this local
seed at that checkpoint. The 12 physical packets remain unapproved;
production provider/publication rights, activation, device/camera, sync and
release gates retain their separate requirements.

**Lorcana rendered UI — 2026-10-13:** the
[implementation plan](lorcana_code_implementation.md) and
[UI review checkpoint](../research/lorcana-ui-review.md) now record the bounded
synthetic iPhone/iPad simulator acceptance, default/large-text light/dark renders,
local save/undo/relaunch and incomplete recovery. Final scoped regression is
204 passed with zero failures/skips. Earlier claims that this synthetic rendering
is pending are historical; real corpus, spoken VoiceOver, physical device/camera,
remote activation, sync and release gates remained open
at that synthetic checkpoint. The later rollout evidence above owns live pricing.

**Lorcana pricing code — 2026-10-13:** [Slice 5](lorcana_code_implementation.md)
now implements exact reviewed physical-printing/finish pricing with shared
TCGCSV transport and the existing pricing/withdrawal workflows. Older statements
that Lorcana has no pricing implementation are historical for explicitly
injected physical catalogs. At that checkpoint default discovery had no pricing
capability or approved market mappings. The normal rollout supersedes that
registration limit; physical-device and production acceptance remain open.
Source aliases and discovery prices cannot
grant physical ownership or market authority.

**Lorcana catalog discovery — 2026-10-13:** the owner requested English cards
and sealed-product completeness for Browse and scanner lookup. The
[coverage checkpoint](../research/lorcana-catalog-coverage.md) records 3,556
source cards, 26 supplemental observations, 177 sealed products and 322 passing
continuation simulator tests. The initial 80 supplemental observations included
53 duplicate aliases and a card bundle; scoped joins and 58 inspected public
images now reconcile them. Default discovery/recognition is registered. Older
statements that all production registration is disabled are historical for
discovery at that checkpoint. Source IDs still cannot authorize physical acquisition
or collection writes; approved rows now use app UUIDs. Signed remote activation,
real-card and release acceptance remain open. Three Palace Heist components still lack automatic recognition evidence;
they now support explicit catalog recovery. That gap and the partial Q3/C3
source scopes prevent a whole-physical-catalog completeness claim.
The camera now conditionally reads same-frame card text for supported unnumbered
Quest footers. This closes an integration gap not covered by earlier literal
footer tests. Observed native hyphen/S7 OCR readings have bounded parser repairs;
body text cannot feed another game's recognizer or unrelated historical fallback.
The macOS CPU diagnostic is distinct from still-open device/camera acceptance.

**Portfolio refresh/ownership reconciliation — 2026-10-09:** the
[portfolio remediation](../audits/portfolio-review-remediation.md) qualifies the
October plan §H rule: price checkpoints remain gated, while ownership changes
request immediate coalesced replay during an active price pass. The controller's
terminal replay is retained. This trades additional replay work on user edits
for consistent Collection and Portfolio ownership presentation.

**Systematic One Piece market mapping repair — 2026-10-07:** the
[pricing gap audit](../audits/one-piece-op16-op17-pricing-gaps.md) now records the
shared repair and signed owner revision 2. The earlier 1,961 exact / 412 held
baseline and “investigation only” notes are historical: current coverage is
2,367 exact / six held finish disagreements. This expands local owner pricing
authority without changing physical identity or production rollout authority.

**Browse reliability and One Piece sealed — 2026-10-07:** the
[browse directory plan](browse_set_directory_remediation_plan.md) now records
shared bundled/registry authorization, detail identity checks and edition/order
isolation. The [One Piece ledger](one_piece_code_implementation.md) owns enabled
runtime sealed browse/repricing evidence. The integration plan's older sealed
follow-up scope is superseded by this implemented capability; legacy import
normalization restrictions remain distinct. Focused simulator verification does
not close live-provider, physical-device, CloudKit or production-rollout gates.

**Card-detail price history — 2026-10-07:** the
[pricing plan audit](browse_pricing_coverage_plan.md#final-architectural-decision)
reconciles the implemented Browse-only accumulation with the unimplemented
provider backfill path. Existing request flags, reserved summary fields and
comments about lazy detail fetching did not constitute historical series
integration. Owned charts still use device knowledge history; unchecked-date
market history remains an open implementation slice.

**Bulk intake measurement — 2026-10-07:** the
[staged differentiation plan](bulk-intake-differentiation-plan.md) records the
2026-10-06 owner decisions and Stage 0 implementation. Its privacy-safe, local,
default-off scanner log passes 118/118 focused simulator tests (4 metrics,
97 scanner and 17 unresolved-store tests; no skips/failures) before an owner
device baseline. Stage 1 and later behavior changes remain pending. This study
informs differentiation within the Collection Integrity strategy and is separate
from its frozen 42-day retention experiment. The
[release go/no-go framework §6](../release/card-scanner-1.0-go-no-go-framework.md#6-competitor-benchmarking-is-intelligence-not-a-launch-gate)
keeps competitor benchmarking outside launch arithmetic. No participant study starts until
the bulk intake protocol freezes supported decks, app order and thresholds.
Simulator instrumentation tests do not certify device speed or silent-error rates.

**Next-slice planning — 2026-10-06, `230a55f` plus existing local changes:** the
[camera acquisition/relaunch plan](one_piece_camera_acceptance_slice.md) details
the One Piece ledger's next acceptance slice using the ordinary owner app,
exact physical samples and bounded hardware evidence. All currently verified
printings have one supported finish; multi-finish controls retain fixture-test
evidence rather than a manufactured physical sample. The installed-app first-check
instructions now reflect the approved sole-candidate automatic-save policy.
This documentation pass runs no build, test, camera, provider or sync acceptance
and does not reopen owner-deferred supersession or production publication.

**One Piece existing-save priority — 2026-10-06, `230a55f` plus local changes:**
the owner selected reliability of existing saves and deferred speculative
supersession under KISS/YAGNI. The retained registry has no correction records
or superseding printings; older “supersession migration next” notes are historical
priority statements, not instructions to build that feature now. The
[implementation ledger](one_piece_code_implementation.md) records five passing
disk-backed fault-injection tests, including six correction combinations,
real-writer recovery/retry and withheld catalog authority on failed withdrawal.
Existing production behavior passed; only scoped Debug test hooks were needed.
The affected twelve-class simulator selection passes 380/380, with no skips or
failures, including 80 One Piece and 96 scanner cases; it includes the five new
tests and is separate from the initial focused run.
Debug and arm64/x86_64 `ReleaseLocal` simulator builds pass; the release arm64
binary omits the Debug fault-hook symbols. All 149 checked local links and
whitespace checks pass. Results remain on the external drive in
`CodexBuilds/OnePieceSaveReliability-20261006/`.
Injected pre-save faults do not certify mid-save crash recovery across two SQLite
configurations, physical-device, provider, CloudKit or release acceptance.

**Cross-game scanner edge cases — 2026-10-06:** the
[Pokémon, modern Magic and One Piece review](../audits/scanner-cross-game-edge-cases-2026-10-06.md)
records four fixes: explicit foreign Pokémon footers block English fallback;
unknown Pokémon identifier fields reject live and recovery requests; modern Magic
requires released, valid printing metadata and rejects provider-flagged oversized
objects; One Piece footer bounds must be fully contained. Four new focused tests,
619/619 affected simulator tests (no skips/failures), and Debug build-for-testing
pass. The older scanner remediation/full-suite counts remain dated snapshots.
One Piece's local owner catalog remains governed by its release acceptance ledger;
this follow-up does not open publication gates or certify physical-device accuracy.

**Historical Magic edge cases — 2026-10-06:** the
[follow-up review](../research/magic-historical-corpus/edge-cases.md) expands
ordinary historical layouts to leveler, fixes literal quoted/ligature names and
same-title oracle choices, rejects unrelated OCR titles, and fails incomplete
ordinary metadata without hiding printings. Nine new focused tests, 432/432
affected simulator tests (no skips/failures), 22/22 Python checks and Debug
build-for-testing pass. The original corpus remains 27/27 title/choice outcomes;
11 provider searches replay 29 exact printings. Provider metadata evidence does
not certify optical recognition of new photographs or physical-device accuracy.

**General historical Magic implementation — 2026-10-06:** the user's scope
correction supersedes the per-card pilot delivery restriction. The
[general scanner report](../research/magic-historical-corpus/general-scanning.md)
is current implementation evidence: normal raw/slab dispatch recognizes historical
titles across frame/layout generations, refreshes complete current printing
families, and requires explicit English and printing choice before acquisition.
All 27 references reach printing choices; final affected simulator regression
passes 388/388 with no skips/failures, Python checks pass 22/22, and the Debug
build-for-testing succeeds. The index pilot and its one-positive,
26-abstention results below remain dated evidence for optional automatic selection,
not the current general scanner behavior. Physical-device/release acceptance and
remote publication remain open.

**Historical Magic corpus-backed OCR/save — 2026-10-06, `412a09d` plus local changes:**
the [corpus evaluation](../research/magic-historical-corpus/README.md) and
[new projection report](../research/magic-historical-pilot/2026-10-06/corpus-reconciliation-report.json)
supersede the intake-only status below. The live pilot and evaluator share
card-relative Vision OCR. Survival of the Fittest `129/143` is reconciled to
its exact Exodus identity and current collision family, adding a fourth dated
key to the 150-record index. Actual OCR on 27 staged originals yields one
calibrated positive and 26 current-scope abstentions; explicit English choice
saves its exact row through the normal scanner writer. Focused 27/27, affected
regression 316/316, Python 20/20 and Debug build-for-testing pass. The initial
refresh failed closed on duplicate source provenance; replacement and rerun
tests correct that defect. Manually annotated framing and repeated still evidence
do not certify held-out positives, independent camera frames, live-provider
acquisition or device accuracy. Broader templates and production activation remain
open.

**Historical Magic photographic intake — 2026-10-06:** the
[corpus review](../research/magic-historical-corpus/README.md) supersedes the D
pilot's earlier “no known local photo folder” limitation. All 27 source images
decode; visual inspection classifies 20 photographic examples and seven clean
controls. The Unhinged Forest sample has a black border, correcting the attached
manifest's silver-border assumption. Exact printing IDs, held-out optical results
and device acceptance remain pending. No runtime activation or index change follows
from this intake.

**Historical Magic D pilot — 2026-10-06, `412a09d` plus local changes:**
the [recognition plan](magic_historical_recognition_plan.md) and
[reviewed pilot report](../research/magic-historical-pilot/README.md) supersede the
initial C artifact claims below: 150 exact IDs now reconcile, three provider fronts
have visible-number review and three dated complete-key receipts. The local pilot
implements bounded same-frame OCR, a separate evidence namespace, English
confirmation, exact hydration and pre-save/activation checks. Allay is a reviewed
singleton; outside-era/promotional matches remain blockers. Provider images and
mocked transport tests do not establish camera accuracy or device acceptance.
Production scanning remains off; A/C/D acceptance and broader E/F/B2 work remain
open. Final deterministic evidence is 314 passing selected simulator cases and
13 Python cases; the report holds the artifact hash and rendered evidence.

**Historical initial C evidence — 2026-10-06, `412a09d` plus local changes:**
the [recognition plan](magic_historical_recognition_plan.md) now records the next
inert C slice: dated complete AllPrintings capture/inventory, 143 exact-ID
reconciled Exodus printings, seven held cross-era matching identities and a
383 KB bundled projection. Profile/index compatibility, atomic paired activation
and explicit per-key receipt/expiry/source-context gates have deterministic tests.
All 145 focused simulator tests and eight importer tests pass. Physical-number
review, current-provider collision reconciliation, D integration and device gates
remain open; every bundled historical query remains incomplete. No acquisition,
signed schema or rollout authority change follows from this provider inventory.

**Historical B1 evidence — 2026-10-06, `412a09d` plus local changes:**
the [recognition plan](magic_historical_recognition_plan.md) now records an inert
app-local profile implementation and an initial dated set inventory. This
supersedes its proposal-only status. A's physical-printing/corpus gate and C–F
remain open; B1 supplies local generation/activation contracts without a
historical adapter or compatible index activation. Focused simulator evidence
is 136 passing tests plus 18 MagicCatalogCore tests. Historical acquisition,
signed schema and rollout authority are unchanged.

**One Piece variants/catalog audit — 2026-10-05, `f40e704` plus local changes:**
the [edge-case audit](../audits/one-piece-variants-catalog-edge-cases.md)
records admission, product-membership, exact finish/key, English price authority,
primary-release metadata and older recovery-choice fixes. The full retained
English corpus is exercised across recognition, Browse and CSV. This strengthens
admission and acquisition consistency without promoting held records, claiming
complete physical coverage, or completing supersession/ownership migration.
The implementation ledger retains the next-slice and operational gate authority.

**One Piece integrated acceptance — 2026-10-05, `f40e704` plus local changes:**
the [implementation ledger](one_piece_code_implementation.md) and
[release checklist](one_piece_release_acceptance.md) record the next local
acceptance slice, real-catalog simulator routing and a startup recovery race fix.
This supersedes the documentation map's stale “next: real reviewed local corpus
and usable printing choice” wording. The ordinary corpus and picker already
exist; remaining collection corrections, physical coverage, legacy adapter work
and device/provider/sync/release gates retain their stated scope. The isolated
acceptance route is optional developer infrastructure and does not change the
owner's ordinary daily-use collection.

**Scanner choice policy — 2026-10-05:** the owner's explicit request supersedes
the earlier One Piece English-confirmation/complete-universe requirement for
a sole verified printing. The [implementation ledger](one_piece_code_implementation.md)
now records automatic resolution within the available English catalog, shared
finish choice only for multiple finishes, and the compact picker update. Earlier
single-candidate-choice evidence remains historical; held records are still
unavailable, and this policy does not establish worldwide coverage or OCR language.

**Owner app correction — 2026-10-05:** the owner rejected the renamed, isolated
review app. The [installed app record](one_piece_device_review.md) supersedes
that flow: original TradingCardScanner name, existing identity and normal
collection storage, with verified local One Piece acquisition enabled. The
isolated tooling remains optional developer infrastructure. Production
publication and shared-collection acceptance remain separate pending gates.

The later ordinary-Xcode rebuild exposed that retained preferences were not a
reliable first-launch dependency. The normal local app now bundles the verified
catalog and public pin; custom installation settings are no longer required.

**One Piece release-plan reconciliation — 2026-10-05, `534127f` plus local
preparation:** [v1 acceptance](one_piece_release_acceptance.md) is the authority
for approved scope/source choices, private-install retirement and pending
hardware/rights/signing/sync gates. It supersedes automatic screen replacement
on recovery, the stale local-review “no price adapter” statement and assumptions
that all captured groups have selectable printings. The publisher retains
provisional/conflicted UUIDs as review history; verified-only means acquisition
eligibility, not deleting those records. Local review pricing is exact-mapping
only. Portfolio-format CSV still omits One Piece; app-format CSV preserves it.
Production remains disabled and writes default off.

**One Piece plan reconciliation — 2026-10-05, `6b64abe`:** the integrated code is
now committed on `merge/one-piece-integration`. The implementation ledger and
catalog design supersede older active wording that cached-price withdrawal,
exact finish correction, Pokémon/Magic catalog extraction or the ordinary
capture pipeline are missing. Current source retains 2,745 printings and 1,961
exact base mappings; all canonical physical-coverage flags remain false. Local
full-kit base-case acceptance is next. The read-only boundary audit still reports
eight Browse labels; legacy Browse/import/runtime work and production/device/
rights/sync gates remain open. This reconciliation reran no app/package tests;
the recorded 192-test checkpoint retains its original scope and provenance.

One Piece base pricing update — 2026-10-04, existing `one-piece-integration`
worktree at `69c714f`: exact TCGCSV pricing is now implemented for 1,961 reviewed
original base printings. This supersedes older “no pricing adapter / optional
pricing” notes for the local base-case milestone. TCGCSV exposes aggregate market
prices, not condition SKUs. Price Check, Browse detail/add and collection refresh
use permanent printing UUIDs and exact finish lanes; no name/number fallback is
allowed. The [implementation ledger](one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04)
records source scope, implemented cached-quote withdrawal and remaining physical mapping,
device and production gates. The full 2,745-printing debug kit verifies;
production scanning/sync remain disabled.

2026-10-05: container-bound catalog publication now persists exact managed-price
withdrawals before consumers see the new generation. The selected One Piece and
pricing checkpoint passed 103/103; same-container startup/quote-cache checks passed
18/18. A relaunch-found stale feed cache now refreshes per catalog generation;
its affected recheck passes, and final full-kit relaunch/Refresh Prices restored
the saved Shanks quote to $8.16. A subsequent three-test checkpoint proves actual
single/multi-claim rejection without ownership/history mutation after signed
catalog quarantine, conflict/stale revision handling and storage-session retirement.
The subsequent Magic catalog extraction owns Scryfall and signed child routing
under `Games/Magic`; 55 focused catalog/compatibility tests pass. Prepared-identity
coalescing retains fetch timestamps and does not cache a user's printing answer.
Signed Magic activation and the remaining legacy modules are still pending.
The subsequent Pokémon catalog extraction moves provider/offline/disk-cache and
historical behavior under `Games/Pokemon`, preserving keys and captured modern
definitions. One consolidated checkpoint passed 192 selected catalog, One Piece,
pricing and quote-cache tests. The boundary audit remains red on eight matching
labels, all in Browse; full-plan completion is not implied. Base-case acceptance
is the next milestone; further framework
or special-printing expansion waits for findings from that local test.

This is the repository-wide documentation index and reconciliation record.
Source code, tests, build settings, and evidence recorded against the current
checkout outrank dated plans. A document is current only when it is listed
below or linked from the current [documentation map](../README.md). Everything
under `docs/legacy/` or `review/legacy/` is retained for provenance and is not
release evidence.

The newest boundary-failure implementation and simulator evidence is in the
[October review ledger](../audits/october-review-remediation.md), against
`fix/october-review-boundaries` through `248a61d`. Slices 1–10 are committed;
focused checks pass, while its historical complete runs report centering failures.
Older “latest full run” statements below describe their dated snapshots and do
not supersede the October execution record. Physical-device and release gates
remain open.

The [October refinement plan](october-refinement-implementation-plan.md) validates
the supplied follow-up review against `55b2d40` and now records the authorized
implementation of slices A–I and C1, followed by the verified guided centering
repair recorded below.
Subsystem acceptance contracts remain binding. Slice C resolves the source/test
disagreement with the hybrid requirement: edits and warning refresh remain
pending until explicit approval of valid outer and inner frames. Manual-recovery
and invariant helpers invoke that action too; numerical tolerances and automatic
detector gates stay unchanged. Slice K fixes the reproduced preview rotation
mismatch and retains individual diagnostic/accuracy triage. The older passing
confirmation selectors are historical. The owner supplied intended future
`scan-stash.com/privacy` and `/support` pages, but confirmed they are placeholders;
Release URL configuration remains open until approved live pages exist. On
2026-10-03 the owner confirmed Scanstash as the app name and Info@scan-stash.com
as the live contact. The existing legal drafts were revised against current
source and Apple guidance; [publication checks](../legal/README.md) track the
remaining contact/operator, retention, provider, hosting, and Release URL gates.

The [guided centering repair ledger](../audits/centering-guided-repair.md) records
the approved October-2 working-tree implementation at `73898e8`. It supersedes
older centering failure counts as current guided-workflow evidence: 109 centering
cases have one failing latency case (two assertions), and the remaining 1,661
cases have zero failures with seven existing skips. The final regression reruns
1,692 cases (including 31 centering UI/export cases), with seven existing skips
and zero failures; ReleaseLocal and final phone/tablet visual checks also pass.
Guided transform tests now
use independently annotated reviewed frames; original automatic comparisons and
their unchanged tolerances remain explicit open research gates. Automatic
reporting stays disabled. The owner accepted deferring latency, without weakening
the speed assertions. The approved immutable revision export work also supersedes
the earlier measure-only thread-placement restriction for that specific change;
device performance and manual/release acceptance are still separate gates.
Native phone share-sheet and iPad popover presentation were observed in the
simulator; physical-device share/save completion and VoiceOver remain open.

The later October-2 uncommitted-change review in that ledger adds two geometry
regressions and five focused fixes. Its seven-class run has 111 cases with only
the existing latency case failing; the final UI/export/input rerun passes 33
correctness cases. Earlier counts above remain dated snapshots. A locked Mac
blocks the final numeric-field accessibility-tree and incomplete inner-capture
rechecks, so earlier visual evidence does not certify those latest view edits.

The [additional production refinement review plan](october-production-refinement-review-plan.md)
records the source review at `73898e8`: transient cooldown/monthly-period
accounting, manual catalog recovery, batch/scanner stale-result publication,
Magic live directories, ownership/price display, activity read errors, and
publisher validation. On 2026-10-03 the user authorized implementation: slice A
unifies rate-limit cooldowns in the uncommitted working tree against `dd2a1e3`,
with 121 focused simulator tests passed. B–J are implemented: final regression
executes 1,714 cases (1,707 passed, seven existing skips, zero failures), and the
publisher package passes 74 tests. The initial full run was not clean; the plan
records its corrected mock/pricing failures and unchanged centering latency
failure. K preserves that latency disposition and the automatic accuracy gates.
The owner requested wrapping up without further screenshots or device-specific
testing; L/M measurement, rendered/native/device acceptance remain deferred.
Live legal/support pages remain placeholders.
The plan records this evidence separately
from its source-review baseline and does not replace the earlier October plan.
At the original review's documentation time, pre-existing uncommitted centering
changes already move export preparation off
the main actor; the review's centering-export hypothesis must be revalidated
against that work. The existing centering contract/triage, URL dependency, and
release-follow-up measurements remain their single respective authorities.

## One Piece design and implementation reconciliation — 2026-10-04

Latest coverage checkpoint: the full ordinary batch covers 58 product groups and
2,731 selected release/artwork identities. The adopted corpus has 2,692 canonical
cards and 2,745 printings (2,490 verified, 224 provisional, 31 conflicted),
8,237 combined observations, 2,940 captures and 257 open discrepancies. All 817
earlier printing/artwork records and 794 canonical records remain unchanged;
all five outputs replay exactly. Unsigned revision 13 validates against revision
12 as protected review. All 42 selected Python tests pass. The core run reports
39 passes and one new assertion failure: the test incorrectly assigned base
EB04-061 to OP17 rather than OP15; the corrected affected test now passes.
No full-suite repeat was needed. App coverage is 41 initial passes plus two
corrected affected tests: Browse contains 52 verified-target groups rather than
all 60 retained products; wholly provisional ST30/ST31 products remain unowned.
The expanded scan/save cases pass. A full-corpus isolated local kit is signed and
independently verified; its 16,119,026-byte envelope remains below the 48 MiB
transport limit. Cold activation/memory and rendered/device acceptance remain open.
No signed/public production release or complete physical universe is claimed.
The efficiency-audit figures below are historical snapshots.

Latest efficiency audit: the current worktree has 534 canonical cards, 547 physical
printing records (446 verified, 93 provisional, eight conflicted) and 1,727
observations. Reviewed standard coverage reaches ST-10 and OP-03, including two
ST-10 reprints of OP-01 numbers. Earlier milestone logs confirm 40 core and 40
One Piece integration tests passed. The subsequent correction checkpoint reports
41 of 42 selected tests passing, then a passing focused rerun after fixing the
remaining test fixture; no clean full 42-case rerun is recorded. This documentation
audit reran no tests. Earlier
canonical-only, synthetic-only and small-demo-next claims below are historical.
The [implementation ledger](one_piece_code_implementation.md) now prioritizes
remaining correctness gaps, reproducible larger catalog batches, necessary
legacy routing and integrated acceptance. It limits repeated builds/signing and
retains full coverage, physical identity, rights and sync gates. No implementation
or production change is authorized by this documentation-only pass.

The subsequent code/file-level handoff names the exact correction authority,
product manifest/capture pipeline, legacy extraction destinations, signed seed
filename, three-namespace hosting preservation and focused regression targets.
Proposed API/file names are explicitly distinguished from existing source.
External rights/key/sync inputs remain owner decisions, not choices delegated to
the implementing developer. This follow-up changes plans only.

The latest handoff review separates already-implemented correction work from the
remaining publication-order/withdrawal checks. It prescribes a container-bound
activation source boundary, product/discrepancy fields, retained-byte migration
before capture expansion and explicit capture-orphan recovery. It also corrects
verification to the recorded `TradingCardScanner`/`Debug` checkpoint and existing
test files. This adds implementation instructions, not new passing evidence.

The owner subsequently authorized the full code-level implementation after its
source review. The [implementation ledger](one_piece_code_implementation.md)
records the revised correctness contracts and A–N delivery gates in the
`one-piece-integration` worktree, based on `69c714f`. The integration design now
explicitly distinguishes its original documentation change from that later
authorization. One Piece production support and external acceptance remain
disabled/unverified until the ledger records direct evidence.

The [One Piece integration plan](one_piece_catalog_integration_plan.md) records
the owner's older multi-source audit against `dd2a1e3` plus the existing working
tree. The Pokémon/Magic-only architecture claim belongs to that historical
baseline. The 2026-10-04 worktree audit includes new/untracked files as well as
tracked diffs: open game identity, runtime/recognition adapters, One Piece core,
local scanner/Browse/import/recovery fixtures and signed preparation/bootstrap
now exist. They do not establish production support. The plan retains Bandai
discovery, Limitless reconciliation, Scrydex enrichment, and permanent local
printing IDs, but replaces the draft's
confidence-based automatic physical selection with the current deterministic
resolution and user-choice contract. Signed delivery requires its own One Piece
schema and key/rollout boundary; existing game releases are patterns, not a
ready-made One Piece physical-printing catalog. Historical vendor counts,
coverage percentages, image/licensing statements, and ship-readiness language are
explicitly unverified. Pricing-provider selection and shared-cache publication
remain governed by their current plans. A weekly thread monitor is scheduled;
neither that schedule nor this documentation is ingestion or release evidence.

The code-level ledger's earlier “next: generic picker/recovery, then core/runtime”
sequence was stale after those implementations. Its current priority is a usable
local slice with a small real reviewed English corpus, collector-distinguishable
printing choices and complete unsupported-row/recovery guards. Keep shared seams
needed for the owner's planned Lorcana integration; defer optional abstraction
and provider work. Remaining legacy catalog/Browse dispatch still fails the final
architecture audit; the script alone does not cover every explicit game branch.

The audit also records a shared-host delivery gap: existing Pokémon/Magic
deployments restore only their two namespaces. One Piece publication there must
first make every deployment preserve all namespaces. Synthetic fixtures, signing
artifact uploads and disabled bootstrap configuration are not corpus, protected
hosting, CloudKit or launch-performance acceptance. This pass changed plans only
and ran no builds/tests; prior checkpoint counts remain dated, overlapping evidence.

The subsequent 2026-10-04 plan-only follow-up inspected the current picker source
and existing 52-case passing log. Bounded scrolling, optional artwork/footer
metadata and old-choice compatibility are now implemented, so the unbounded-grid
finding is historical. The owner rejected the verbose presentation and requires
the same compact option-button format as Pokémon/Magic. The
[visual checklist](one_piece_printing_choice_visual_checklist.md) remains
unaccepted; detailed provenance belongs on demand, while essential distinctions
must stay visible. Finish resolution already uses the shared `VariantChoiceBar`.
This changes the next UI task, not physical identity, catalog completeness or
production gates. No source changes, build/test reruns or new simulator evidence
were produced by this follow-up.

The resumed implementation then replaced the verbose picker with that compact
format. The visual checklist now records scoped final fixture captures and
native Details/skip/final-candidate checks; it retains real-corpus, loaded-artwork,
VoiceOver/device and owner acceptance gaps. The current ledger separates this
implementation evidence from the earlier plan-only audit and rejected rendering.

The later source-ingestion checkpoint retained six exact Bandai/Limitless HTML
captures externally and 30 normalized observations in the
[English stress-source review inputs](../../OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).
The earlier blanket description of all corpus inputs as synthetic is superseded:
real discovery metadata now exists, while physical-printing fixtures remain
synthetic and the real review registry has no physical UUIDs or automatic authority.
Eight bounded-parser/CLI tests and 31 core tests pass locally; no app build,
live workflow, physical corpus certification, asset redistribution or production
activation is claimed.

## Lorcana research import — 2026-10-03

**2026-10-12 UI review implementation:** the
[isolated review launch](../research/lorcana-ui-review.md) now uses the existing
scanner/choice/finish/Collection/Browse/CSV surfaces with a signed synthetic seed.
Earlier descriptions of the debug kit as only an injection API are superseded
for this route. Rendered phone/iPad/accessibility acceptance and all physical
evidence requirements remain open; fixture UUIDs are not real-card authority.

**2026-10-12 minimum acceptance preparation:** the supplied
[12-specimen batch](../research/lorcana-real-card-corpus/minimum-acceptance/README.md)
preserves all 26 files and three matching corpus snapshots. Local replay passes
23 offline assertions and 16 Python precheck tests; all packets remain unapproved
and all 25 iOS scenarios remain unexecuted. Published-photo and dimension claims
are research only. Package statements about unavailable Xcode/checkouts describe
its original preparation environment. The narrower target selection defers
Mulan and other cases; it does not close the broader corpus or footer universes.

**2026-10-12 representative reference import:** at base `1e368b3`, the supplied
[real-card package](../research/lorcana-real-card-corpus/README.md) is preserved
with matching original checksums. It has 29 inactive candidates, 35 cited sources
and 25 unexecuted scenarios; the original guide's 23-scenario summary is stale.
This closes source selection only. Earlier requirements for a permitted physical
corpus still apply: no photographs, UUIDs, finish approvals or signed real seed
are supplied. The Slice 2 corpus checkbox remains open, and the source package
does not alter the runtime or production registration.

**2026-10-12 local ownership follow-up:** at `9d7c780c` plus local changes on
`feat/lorcana-implementation`, Slice 4 supplies local reviewed-printing Browse,
exact UUID/finish CSV validation, coherent activated import metadata and checked
isolated debug writes. The final save guard rejects stale/incomplete catalog
authority; duplicate CSV keys retain conflicting evidence through failed exports.
The [implementation plan](lorcana_code_implementation.md) records 240 passing
regression cases outside ownership plus the final 13/13 ownership replay. One
initial assertion about imported set names was corrected; this is passing
evidence for 253 distinct selected cases across runs. Earlier scan-only and
missing-Browse/import statements describe previous checkpoints. Physical claims
remain synthetic; rendered UI, real seed/corpus/device/performance, pricing,
production writes/sync and rollout gates remain open.

**2026-10-12 signed-activation follow-up:** at `9d7c780c` plus local changes on
`feat/lorcana-implementation`, the [signed local contract](../research/lorcana-signed-activation.md)
now defines bounded canonical releases, independent trust/paths, protected
durable transitions/recovery, coherent container-bound snapshots and an explicit
ephemeral debug seed kit. The final app/test build and 129 focused simulator
cases pass, including 23 new activation cases and shared/One Piece regressions.
Earlier statements below that Lorcana lacks signed activation are historical.
This checkpoint uses synthetic physical claims and a supplied-manifest injection
API; real seed/corpus, rendered/device/camera/performance, production keys/hosting/
rights, ownership/Browse/import/pricing, sync and release gates remain open.

**2026-10-12 physical-contract follow-up:** at `9d7c780c` plus local changes, the
[schema-2 local contract](../research/lorcana-physical-contract.md) adds permanent
physical UUIDs, canonical relationships, reviewed candidate universes,
correction/transition validation, exact catalog/printing choice and per-printing
finish checks. Schema-1 still returns incomplete outcomes. All new physical
references are synthetic test claims; the source inventory contains no promoted
real physical seed. The app/test build and final 82-case simulator checkpoint
pass with no failures/skips; these contracts do not establish physical acceptance.
Production, real-corpus, ownership, pricing, signed activation
and release gates remain open. The execution plan separates completed code
contracts from physical acceptance; old “only incomplete” source descriptions
apply to schema-1 and the earlier checkpoint.

**2026-10-12 implementation checkpoint:** the current plan now records bounded
Lorcast card/set ingestion and retained source metadata, with 60 focused simulator
tests passing at base `b1959c6` plus changes on `feat/lorcana-implementation`.
The [source inventory](../research/lorcana-source-corpus.md) separates provider
observations from reviewed physical footer/finish/size/stamp evidence. The older
worktree and 44-test description below is historical; no production, ownership,
pricing, exact-printing or whole-corpus acceptance is inferred from either run.

**2026-10-04 recalibration:** the [Lorcana implementation plan](lorcana_code_implementation.md)
is now the execution authority for the existing uncommitted `one-piece-integration`
worktree at base `69c714f`. Shared runtime/recognition/catalog/recovery boundaries
replace the older proposal to start by importing the entire game. Slice 1 adds
local provisional print-family mappings, conservative complete-footer recognition
and generic incomplete lookup/recovery. Forty-four focused simulator tests pass,
including 13 new Lorcana cases. Provider codes are not assumed to be printed
markers; print-family keys are not physical ownership IDs. The imported research's
finish-classifier-first and variant/stamp hierarchy are superseded by the current
physical-printing-before-finish design. Real corpus, source rights, production
activation and collection sync remain open; the research release timeline is not
revalidated or adopted as completeness evidence.

The [Lorcana data, variant, and scanner-architecture audit](../audits/lorcana-data-variant-scanner-architecture-audit.md)
preserves an owner-supplied deep-research report as design input. Its proposed
footer-OCR and print/variant identity model is not implementation evidence:
current source and tests still determine supported games and behavior. The
report's inline citation identifiers belong to its originating research session
and cannot be resolved from this repository. Recheck time-sensitive release,
API, completeness, and licensing claims against their linked primary sources
before using them for implementation or release decisions.

## Latest two-set pricing evidence — 2026-09-30

The [pricing coverage plan](browse_pricing_coverage_plan.md) now records a
device-local TCGCSV exception for 30th Celebration and Classic Collection.
Statements below and in the older Phase 6 discussion that retain pokemontcg.io
as the bulk provider apply to the general Pokémon path; these two sets use
reviewed exact product/finish mappings. A general successor remains unresolved,
and published Stage 4B prices remain disabled. The focused simulator selection
passed 322/322 and the live production client validated all 188 mapped Holofoil
quotes. This evidence does not certify physical-device or release readiness.

## Latest catalog rollout evidence — 2026-09-20

The production catalog baseline is hosted revision 1, signed with the pinned
production public key. The committed app configuration is now
`remote-authority`. The validation-only online/relaunch rehearsal and the
focused/broader catalog suites passed after commit `54960fd` (8/8 focused,
64/64 broader); the one-off authority rehearsal activated hosted revision 1 on
the dedicated simulator, persisted `current = 1` with no previous slot, and
treated the identical relaunch fetch as `notModified` rather than a rejection.
The current checkout keeps release schema 1 and adds optional
`providerFingerprint` descriptors, a shared canonical provider-content
fingerprint, a separate local probe fingerprint, durable targeted device
reconciliation, and workflow classification that sends only post-baseline
content-only candidates to the automatic publication environment while routing
baseline, authority, new-set, and unknown changes through the protected
reviewer environment.

Workflow run [35443012617](https://github.com/Razorback2424/CardScanner/actions/runs/35443012617)
validated a no-op revision-2 candidate: all 28 descriptors, card counts,
provider fingerprints, and snapshot entries matched revision 1. The protected
publish job was canceled before signing or deployment, so hosted revision 1
remains current and the candidate is evidence only. Physical-device authority,
the genuine offline case, production cutover, synthetic behavior change, and
the first real catalog update remain open gates.

## Exact-candidate simulator evidence — 2026-09-20

The focused cross-area selection was run against `7dbaf40` on the iPhone 17 Pro
iOS 26.5 simulator with external-SSD DerivedData, module caches, package cache,
and result bundles. It executed 581 tests: 579 passed, 1 skipped, and 1 failed
in `ScannerViewModelTests/testCatalogMissVerificationStillFilesUnresolvedCard`.
The storage-safe full suite then executed 1,278 tests: 6 skipped and 4 failed
(1 unexpected), with failures in centering, ownership-ledger, and the same
scanner catalog-miss area. The external-SSD artifacts are under
`exact-7dbaf40/focused.xcresult` and `exact-7dbaf40/full-shell.xcresult`; the
prior `a4375df` suite remains historical.

## App Review remediation evidence — 2026-09-22 (snapshot at `main@9759050`)

At this snapshot, the workspace was clean at `main@9759050`. The scanner, price-refresh,
storage-bootstrap, manifest-protection, and bulk-operation remediation is
committed. The root [`app_review_fix_plan.md`](../../app_review_fix_plan.md) is
the implementation and acceptance authority; the
[`release_followups.md`](release_followups.md) document retains the residual
runtime, device, provider, and scale evidence. The affected 99-test simulator
selection with one Simulator-only protection-attribute skip, the separate
delete-actor integration test, and the broader normalization run were recorded
against the preceding `810954e` working-tree snapshot, not `9759050`. The full
suite and exact-HEAD device evidence remain open. The Release privacy/support
destinations are still owner input.

| Area | Current authority | Code/evidence boundary |
| --- | --- | --- |
| Product scope and roadmap | [`README.md`](../../README.md), [`CardScanner Collection Integrity Strategy`](../vision/CardScanner%20Collection%20Integrity%20Strategy%20%E2%80%94%20Start-to-Finish%20Implementation%20Plan.md), and the [active launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md) | The current Swift target and tests decide what is implemented; roadmap prose does not add product behavior. The launch plan's §0.1.1 binds open pass-2 findings to the tasks they block, and §0.1.2 lists current plans outside launch scope; both are required reading before a task is started. |
| Browse/Catalog | [`browse_screen_spec.md`](browse_screen_spec.md), [`browse_success_checklist.md`](../../references/browse_success_checklist.md), `TradingCardScanner/Views/BrowseView.swift`, and `TradingCardScannerTests/BrowseFeatureTests.swift` | Browse is a Collection push destination. The focused set-directory hardening selectors pass 133/133 with 0 failures, including invalid/valid cache bodies and symbol-prefix recovery. A8/B6 remain closed by the settled light/dark rerun2 evidence in [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md); provider/device checks remain open. |
| Automatic Pokémon set updates | [`automatic_pokemon_catalog_updates_plan.md`](automatic_pokemon_catalog_updates_plan.md) | Slices A–E are implemented. Slice F's production-host revision-1 rehearsal and same-revision relaunch handling are complete as of 2026-09-19. The committed production app configuration is `remote-authority`; schema-1 additive fingerprinting, canonical publisher/device parity, fail-closed classification, durable targeted reconciliation, parent-artwork metadata, and set-specific Browse updates are implemented and the latest focused verification is Core 38/38 plus app 37/37. Protected baseline publication, auto-environment setup, four-hour scheduling, physical-device/offline evidence, the first real catalog update, and release gates remain open. |
| Magic catalog signing and publication | [`magic_catalog_key_handling_runbook.md`](magic_catalog_key_handling_runbook.md) | Current authority for Magic-specific key custody, signed catalog releases, protected/automatic publication routing, Scryfall boundaries, and rollout safeguards. The Magic-specific key pin remains owner input; rollout remains `legacy-live`. |
| Artwork fallbacks | [`artwork-fallback-plan.md`](artwork-fallback-plan.md), `TradingCardScanner/Services/ArtworkFallbacks.swift`, and Browse tests | P0–P3 are implemented in the current tree; TCGdex-only stem/WebP candidates, symbol sibling-prefix recovery, decode-before-persist, legacy-cache eviction, and coalesced requests pass in the 133/133 focused run. Broader provider behavior and licensing are still operational gates. |
| Scanner workflow | `TradingCardScanner/Views/ScannerViewModel.swift`, the current [scanner module review](../audits/scanner_module_review.md), [explicit Raw / Slab scanning mode plan](explicit-raw-slab-scanning-mode.md), [scanner recognition remediation plan](scanner-recognition-remediation.md), [release follow-ups](release_followups.md), [`scan_cancellation_success_checklist.md`](../../references/scan_cancellation_success_checklist.md), and `progress.md` | The scanner module review remains authoritative for tracking/OCR findings and measurements. Explicit Raw / Slab mode is implemented in the 2026-09-23 working tree. The 2026-09-24 recognition/remediation implementation and 2026-09-25 review corrections are recorded in the linked plan and progress. The current focused correction selection passes 229/229; the earlier 1,561-test non-centering result was not rerun against this follow-up. Physical stack, live-provider, Instruments, and release acceptance remain open. The slab-specific automatic-detection and blocking-price recommendations in the archived scanning workflow review are superseded by the new plan. |
| Pricing and portfolio performance | [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md), [`release_followups.md`](release_followups.md), and the current services/tests | The 2026-09-22 fix plan tracks no-provider sentinels and bounded refresh eligibility. Large-store measurement, Magic batching, resumable sweeps, and physical-provider profiling remain open. |
| App Review and release | [`app_review_fix_plan.md`](../../app_review_fix_plan.md), [`app_review_preflight.md`](../../app_review_preflight.md), [`card-scanner-1.0-go-no-go-framework.md`](../release/card-scanner-1.0-go-no-go-framework.md), and the [current evidence ledger](../release/phase-1-integrity-evidence.md) | The last clean app-review baseline is `main@9759050`; its recent focused evidence is from the preceding `810954e` worktree snapshot. The current working tree is based on `main@30bd84e` and includes the Raw / Slab scanner work recorded above. CloudKit/device, archive/TestFlight, centering, actual privacy/support URLs, and other App Store gates remain open. |
| Card centering | [`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md) and [`review/centering-evidence/`](../../review/centering-evidence/) | Dated experiment artifacts remain inside the current evidence ledger; the active contract and its open accuracy/invariant/latency/device gates are authoritative. |
| Legal and future website | [`legal/privacy-policy.md`](../legal/privacy-policy.md), [`legal/support.md`](../legal/support.md), and [`CardScanner-Website-Implementation-Spec.md`](../CardScanner-Website-Implementation-Spec.md) | The website specification is a future website contract; no website source is present in this iOS repository. Its canonical support route is `/support`. |
| Known production defects | [`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) | The six-finding baseline was audited against `a4375df` (five confirmed, one suspected). F01–F03 source remediation is now landed and focused-verified; the audit has not been rerun at intended candidate `7dbaf40`, and entitled-device/runtime evidence remains open. Pass 1 in `docs/legacy/` is a 2026-09-09/10 snapshot and was not re-reproduced. |
| Browse set directory defects | [`browse_set_directory_remediation_plan.md`](browse_set_directory_remediation_plan.md) | Implementation landed 2026-09-15 for the set-tile artwork chain, extensionless/TCGdex-WebP recovery, checklist-backed denominators, empty-set exclusions, incremental/deduplicated price sort, shared-detail cancellation hardening, truthful price-load state, single completion-index ownership, deterministic candidate priority, retry-triggered rebuilds, duplicate-ID-safe checklist reuse, and memory-purge waiter safety. The 2026-09-16 focused selectors pass 133/133, including decode-before-persist, legacy-cache eviction, host gating, and symbol sibling-prefix regressions. A8/B6 remain closed by the final settled rerun2 capture; provider/device measurement C7/RF-9 remains open. |
| Pro tab and eBay listing photos | [`pro_tab_ebay_listing_photos_plan.md`](pro_tab_ebay_listing_photos_plan.md) | Slices A–C and the F1–F7 review remediation are implemented in `main` (merged 2026-09-20 from the isolated worktree based at `523f3e2`); the latest focused remediation selectors pass 14/14 and the Debug simulator build/run succeeds. It owns the Pro tab shell that replaces the centering tab and the new card-independent eBay listing-photo module. It changes where card centering is presented (one navigation level deeper, no inner `NavigationStack`) but not how it measures; the centering contract and its open gates stay in [`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md). Screenshot, manual, physical-device, provider, archive, and release gates remain open; SwiftData persistence against a card is out of scope. |
| Per-card price history chart | [`price_history_chart_plan.md`](price_history_chart_plan.md) | Proposed 2026-09-14, **not implemented**. Slice A is rendering only; the pass-2 F02 source dependency is remediated and focused-verified, while Slice B still requires the RF-8 device measurement. Provider history backfill is a recorded rejected option, not backlog. |

## Disposition — 2026-09-14

No documentation was deleted. Completed, superseded, or snapshot-specific
material was moved into explicit legacy locations, and current replacement
paths were kept where a caller or release workflow depends on them.

| Material | Legacy location | Current replacement or rule |
| --- | --- | --- |
| Duplicate app-review plans and old candidate evidence | `docs/legacy/app_review_fix_plan.md`, `docs/legacy/app_review_preflight.md`, `docs/legacy/phase-1-integrity-evidence.md`, `docs/legacy/ownership-ledger-completeness-audit.md` | Root app-review files and the current release/ownership ledgers are the only current authorities. |
| Old repository gap and first defect audit | `docs/legacy/collection-integrity-codebase-gap-analysis.md`, `docs/legacy/defect_review_pass_1.md` | Current source/tests, the launch plan, the release framework, and this audit. |
| Completed or superseded feature plans | `docs/legacy/collection_tile_*`, `design_slices_plan.md`, `graded_price_lookup_fix_plan.md`, `magic-finish-treatment-coverage-plan.md` | Current source, focused tests, `progress.md`, Browse/artwork plans, and release follow-ups. |
| Historical price/performance snapshots | `docs/legacy/performance_review_remediation_plan.md`, `docs/legacy/price_refresh_scale_plan.md` | Current [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md) plus [`release_followups.md`](release_followups.md). |
| Scanner workflow review snapshot | `docs/legacy/scanning-workflow-review.md` | Its pre-remediation F1–F5 lifecycle findings remain historical. Use the current [scanner module review](../audits/scanner_module_review.md) for module-level defects and concerns, plus the cancellation checklist, release follow-ups, and dated progress entries for their respective scopes. |
| Graded slab scanning recommendations in the scanner workflow review | `docs/legacy/scanning-workflow-review.md` | The slab auto-detection and blocking vendor-resolution recommendations are superseded by [`plans/explicit-raw-slab-scanning-mode.md`](explicit-raw-slab-scanning-mode.md), the current proposed design for explicit Raw / Slab modes. The archived review remains available for provenance. |
| Trust-hardening and whole-repository review snapshots | `docs/legacy/2026-09-10-*`, `review/legacy/` | Current centering contract/evidence and current release ledgers; archived review findings are historical inputs only. |

## Plan contradictions requiring reconciliation

**2026-10-06 historical Magic proposal:** the
[historical recognition plan](magic_historical_recognition_plan.md) corrects the
assumption that scanner support is only a publisher date/code Boolean, or that
the supplied inventory helper is an exact production-filter diff. Current source
also has ordinary-card/layout validation, modern-footer parsing, set-only signed
descriptors and a modern-only runtime projection. Browse already admits historical
sets. The plan adds a separate evidence/index/candidate path and preserves the
[Magic publication runbook](magic_catalog_key_handling_runbook.md). This is future
implementation scope, not a new supported-card or remote-authority claim.

The accepted planning follow-up makes Magic's adapter namespace-aware, requires
fresh complete candidate coverage before automatic uniqueness, separates printing
identity from finish, gates saving on independent/confirmed language evidence, and
uses a reviewed legacy layout allowlist. App-local profiles (B1) precede the bundled
pilot; signed schema-2 semantics (B2) follow successful pilot evidence when remote
publication is needed. Schema 1 and the publication runbook remain unchanged now.

The table distinguishes contradictions that are already resolved in the current
tree from release decisions that still require evidence. An archived document
may continue to contain the old side of a contradiction; its legacy banner is
the required warning, not a reason to rewrite history.

| ID | Contradictory claims | Current code/evidence check | Resolution |
| --- | --- | --- | --- |
| C-01 | Earlier Browse material treated Browse as a fourth/top-level tab; the current navigation model treated it as a Collection child. | `TradingCardScanner/Views/ContentView.swift` now defines Portfolio, Collection, Scan, and Pro tabs; `ProView` owns the Pro stack, while `TradingCardScanner/Views/CollectionView.swift` defines `Destination.browse`. | Resolved. The current Browse plan and checklist say `Collection → Catalog`; the old wording is historical. The isolated Pro implementation does not move Browse or alter the Collection navigation contract. |
| C-02 | The Browse plan read like future implementation work while Browse/Catalog behavior was already present in source and progress. | `CatalogGameBrowseView`, `CatalogSearchResult`, sealed content, release rail, grouping, and fallbacks are in the current source; focused selectors pass 133/133, and A8/B6 have a settled light/dark capture. | Resolved. The current plan is labeled an implemented acceptance contract; only live-provider/device measurement C7/RF-9 remains open. |
| C-03 | The Magic treatment plan described two modeled signals and an unimplemented 5,150-entry target. | `MagicTreatment.modelled` contains 31 cases; `MagicTreatmentTests` assert 31 and a 5,150-entry catalog with schema version 2. | Resolved by archiving the old coverage plan. Use source/tests and progress for current coverage. |
| C-04 | The 2a collection-footer specification and 4a footer plan describe competing layouts and open work. | `TradingCardScanner/Views/CollectionView.swift` renders the settled name, set/number, price, and combined status footer; current collection tests cover the behavior. | Resolved by archiving both snapshots. The current UI/source and tests control; a new footer change needs a new dated plan. |
| C-05 | The scanner workflow review listed F1–F5 as open defects after their lifecycle fixes landed. | `ScannerViewModel` clears/cancels `identificationTask`; the old `resolutionTask`, `undoLastAdd`, and `activeFinishLocks` symbols are absent from production; focused receipt/cancellation evidence is recorded. | Resolved as documentation status. Physical camera, thermal, provider, and full-suite evidence remain separate open gates. |
| C-06 | The old performance/price plans described main-actor refresh work and Slice 6 as proposed, while later code moved persistence behind a model actor. | `PriceRefreshModelActor`, `CollectionProjectionActor`, and value snapshots exist; `ContentView` no longer observes refresh as a whole-screen object. `PortfolioInputObserver`, Magic batching, and resumable sweeps are still open. | Resolved by archiving the detailed snapshots and keeping a short current scale plan that separates landed slices from open measurements/work. |
| C-07 | Duplicate app-review plans used different candidate branches, SHAs, suite counts, and authority locations. | The intended candidate is clean `feature/catalog-and-scanner-hardening` at `7dbaf40`; root app-review files identify the earlier `codex/scanning-workflow-review-remediation`/`0b4ac34` and `fix/app-review-preflight`/`a115e4e` data as historical. | Resolved by keeping root files as current summaries and moving the duplicate snapshot plans into `docs/legacy/`. |
| C-08 | Older release evidence and ownership documents appeared to certify earlier candidate identities, while the current checkout is different. | Current ledgers identify clean `feature/catalog-and-scanner-hardening`/`7dbaf40` and explicitly say NOT CERTIFIED; the latest complete full run at `a4375df` executed 1,277 with 6 skipped and 40 failures. The earlier 1,256-discovered/48-failure snapshot is historical at `0b4ac34`; the 2026-09-16 centering rerun was focused and partial (see C-11). | Resolved as an authority conflict. Production CloudKit, ownership, archive/TestFlight, and clean-candidate evidence are still open. |
| C-09 | The release framework and CloudKit audit describe storage/sync continuity as source-hardened with only **external enrollment** outstanding, which reads as “no known code defect in this area.” | The pass-2 audit's F01/F02 were deterministic source traces at `a4375df`; their source remediation is now present and focused-verified in `main`, while entitled-device/runtime evidence remains open. | **Partially resolved.** The source findings are addressed, but the enrollment/runtime gate remains open. Keep the audit snapshot as historical diagnosis until it is rerun against the current tree; gate rows remain open in the release framework. |
| C-10 | C-05 records the scanner workflow F1–F5 as resolved, which reads as “this area has no open findings.” | Pass 2 F03 was a **new suspected** finding at `ScannerViewModel.swift:2271` (`beginPendingResolution` could discard a choose-handler operation), not a restatement of F1–F5. The C-05 lifecycle fixes were separately re-verified; F03's recoverable-retention remediation is now focused-verified, but the pass-2 audit has not been rerun. | **Resolved for current source status, open for release evidence.** C-05 stays resolved for its own scope; F03 remains a dated audit finding and its runtime/release implications remain subject to the current App Review and release gates. |
| C-11 | `progress.md` and the entries above characterise the full-suite failures in aggregate as “unrelated fixture/source-environment or signal-kill failures.” | The pass-2 run at `a4375df` executed 1,277 with 6 skipped and 40 failures; its 36 corpus lookup failures came from duplicate PBX IDs, not absent repository files. The 2026-09-16 focused rerun after the project fix reached the corpus: 38 results, 28 passed, 9 test cases failed on centering assertions, and 1 profile test was canceled. Fixture reachability and manifest tests passed; the full target was not rerun. | **Updated.** Preserve the pass-2 counts as historical and keep failures classified per suite. Do not add skip guards for the committed corpus. The PBX resource collision is fixed; the centering assertions and complete-suite evidence remain open under F06/RF-6. |
| C-15 | The launch plan's plan-authoring gap list called StoreKit/purchase gating part of the release, while the current strategy and framework define a free 1.0 with no StoreKit. | The active strategy and release framework say free 1.0/no StoreKit; no StoreKit implementation is required for this scope. | Resolved as a product decision. StoreKit remains a future, separately approved monetization experiment, not a current launch defect. |
| C-16 | The launch plan said the website specification still froze `/contact`; the tracked specification already uses exactly `/, /privacy, /terms, /support`. | `docs/CardScanner-Website-Implementation-Spec.md` lists `/support` as the fourth route and defines its support page. | Resolved at the document level. The launch plan now records the route task as reconciled; website implementation/deployment remains future work. |
| C-17 | The old 2026-09-12 progress checkpoint and earlier 940/1,205-test snapshots could be read as current repository readiness; 1,095 remains a valid result only for the separate centering experiment. | The latest complete full run is the `a4375df` pass-2 run (1,277 executed, 6 skipped, 40 failures). The 1,256-discovered/48-failure count at `0b4ac34` is historical; the 1,095 result remains a scoped centering baseline. | Resolved by retaining old general-suite entries under historical headings, preserving the scoped centering result, and adding dated current checkpoints. New evidence must be appended chronologically. |
| C-18 | The shared-pricing-backend plan calls its commercial/licensing preflight “Phase 0,” while the product strategy and launch plan call retention-contract freeze “Phase 0.” | `docs/plans/shared_pricing_cache_plan.md` describes a future backend with device-local pricing still current; `docs/experiments/collection-integrity-v1-retention-contract.md` freezes the active app Phase 0. | Resolved by making the backend phase name explicitly scoped to that future project. It cannot alter free 1.0 or start Firebase work before its own gates A–C. |
| C-19 | [`browse_screen_spec.md`](browse_screen_spec.md) § 8 specified the set tile footer as `3 of 207` — a distinct-collector-number numerator over `set.cardCount` with the unit `cards` — while the set screen showed master-set **variation** slots owned over the built checklist length. | The current source now treats an all-zero provider variation breakdown as unpublished, carries standard/expanded checklist slot counts in the manifest, and uses `CatalogSetCompletionIndex` for both the tile and set screen. The spec subsection was reconciled on 2026-09-15. | **Resolved in source, contract, deterministic evidence, and authorized visual evidence.** Focused Browse selectors pass 133/133 with 0 failures, and the external-SSD snapshot check confirms denominator parity for all 157 entries. Pokémon uses the checklist-backed `variations` unit, with the bounded overflow explicitly labeled `cards`; Magic retains provider card totals. A8/B6 visual confirmation is recorded in [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md); C7/RF-9 remains open. |
| C-20 | The archived scanner workflow review and broad release notes could be read as the complete current scanner review, with only lifecycle fixes and generic camera/thermal/8 Hz measurement work remaining. | The current scanner module review covers `CardScanner`, `CardLatch`, OCR/ROI and slab framing, camera capability selection, `CameraPreview`, and scanner callback paths. It records five confirmed findings (historical OCR retry exhaustion, debug ROI mapping, scan-band ROI mismatch, bad-frame accounting, and macro-lens focus-distance probing) plus three concerns requiring measurement. | **Superseded.** [`audits/scanner_module_review.md`](../audits/scanner_module_review.md) is the current authority for this module scope and its findings. The archived F1–F5 lifecycle status remains valid only for that narrower historical scope; RF-2/RF-5 remain open measurement gates and must include the new review's OCR/tracking and session-length evidence where applicable. |

## Update plan

1. Before changing a status line, inspect the named source type, test, build
   setting, or evidence artifact and record the exact current checkout identity.
2. Keep one current authority per concern in the [documentation map](../README.md);
   move completed or superseded snapshots to `docs/legacy/` or `review/legacy/`
   with a banner and a current pointer. Do not delete them.
3. Keep current plans concise and status-first: distinguish implemented code,
   deterministic verification, manual/device/provider evidence, and owner- or
   vendor-controlled gates. Do not turn an old unchecked task into a current
   defect without reproducing it.
4. Add a dated entry to `progress.md` for each verified implementation or
   evidence change, then update the smallest relevant checklist or ledger.
5. Run a repository Markdown-link check after moves and review all remaining
   current-document references for old branches, SHAs, test counts, routes, and
   monetization claims. Historical references may remain only inside clearly
   marked archives.
6. Re-run the release gates in the current ledgers before calling the checkout
   certified. The current open gates are not closed by this documentation pass:
   production CloudKit/ownership proof, clean exact-candidate regression,
   physical scanner/provider validation, Browse manual sign-off, centering,
   archive/TestFlight inspection, and App Store submission evidence.

> **Amended 2026-09-12.** The checkpoint below is the repository-audit snapshot captured on 2026-09-09. It is historical and must not be used as the current card-centering test count or readiness claim. The active card-centering contract, experiment ledger, simulator evidence, and current branch results are maintained in the [current card-centering plan](../../review/opus-card-centering-implementation-plan.md) and [centering evidence](../../review/centering-evidence/).

## Historical checkpoint — 2026-09-09

- The review-time Debug build ran on the iPhone 17 Pro simulator.
- The review-time simulator suite discovered 940 tests: **939 passed, 1 skipped,
  0 failed**. The skipped case is the opt-in aged-store/performance fixture.
- This run emitted 11 non-failing build notices: nine normal signed XCTest
  simulator-binary strip notices and two benign AppIntents metadata notices.
  No Swift compiler warning appeared in this run; if the test-only concurrency
  warnings from an earlier build recur, treat them as cleanup rather than a
  claimed release blocker.
- The deterministic `MagicTreatmentSlice4` route initially crashed because
  its debug overlay was outside the `CollectionProjectionStore` environment.
  `ContentView` now injects that environment object and the route was rebuilt,
  launched, scrolled, and inspected successfully. This was a real loose end,
  not documentation-only cleanup.

## Current card-centering pointer

The current centering branch retains the newer quad/Vision/rectification implementation and has a default raw-HEIC E-A/E-B result of 8 confident and 2 declined fixtures. The screenshot batch remains a pre-E-B historical 3-confident/7-declined snapshot. Ground truth was rederived on 2026-09-12 with two analyzer-free profile passes plus physical-silhouette adjudication; its provenance/schema gate passes 10/10, while the first current production-entry-point suite passes 8/12 test cases and fails 4 accuracy cases. The refreshed post-REQ-027 E7 resolution curve keeps the missing-inner-reference fixture declined at all four tested maxima in both benchmark curves. The exact sideways/skewed REQ-028 regression methods also pass 2/2 in a focused current run. The current contract and open gates are recorded in the [card-centering plan](../../review/opus-card-centering-implementation-plan.md), not in this 2026-09-09 audit snapshot.

## Historical evidence-backed status — 2026-09-09

“Closed” below meant the implementation had source/test evidence and, where
applicable, a simulator capture at audit time. “Partial” meant a deterministic
surface is verified but the remaining real-device, network, or interaction
evidence was still named explicitly at the time of this audit. This table is
historical for the broader repository; the current centering status is in the
pointer above and the linked centering contract.

| Area | Status at audit time | Evidence |
| --- | --- | --- |
| Finish Lock | **Closed for the current design** | One top-level `Auto` clears all locks; Pokémon and Magic expose variant-only submenus; game-qualified summaries and accessibility labels are present. Supporting `finish_lock_checklist.md` and `finish-lock-global-auto-*` captures are ignored local artifacts, not durable repository files. |
| Card detail / identity / sealed artwork | **Closed for the audited UI slices** | Current dark/light/accessibility-large captures and focused/full-suite coverage are recorded in the three existing checklists. |
| Collection navigation | **Closed for compact-width behavior** | Collection → card detail → Back returns to the collection grid; the `collection-navigation-current.jpg` capture is an ignored local artifact. The intentional iPad split-view empty pane remains a separate behavior. |
| Card movement | **Closed for the deterministic fixture** | Card detail and Movement Details show the selected period, unit movement, quantity, and holding impact; the three-copy `-$0.05 × 3 = -$0.15` case is captured in the ignored local `card-movement-current.jpg` artifact. |
| Portfolio Today / Phase 3 / market movement | **Closed for the current additive model** | Current-value hero, reconciliation, movement chart, contributors, and most-valuable-card ranking are captured in the `portfolio-*` artifacts. The old Performance/Collection Value presentation is intentionally gone; [`release_followups.md`](release_followups.md) records that cleanup. |
| Magic treatment Slice 4 | **Closed for the deterministic route after the environment fix** | Receipt and catalog detail show the FIC #10 treatment path; the nonfoil contradiction remains source/test evidence rather than a separate visual route. The supporting `magic_treatment_slice4_checklist.md` is an ignored local artifact. |
| Browse | **Partial but no longer unverified** | Browse root and the bundled Pokémon directory launch without a catalog request; full search, exact-printing add/undo, remote artwork, and fallback-provider behavior remain interaction/provider checks. |
| Price Check | **Partial but no longer unverified** | The native purpose control and no-add routing are visible. The “Value only · Nothing is added” explanation is intentionally shown at choice time and in the VoiceOver announcement, not as permanent camera copy. A real scan/result/refresh-failure pass remains device/provider work. |
| Whole-card scanner / scanner chrome | **Partial** | The deterministic route and source-level hit-target/state behavior are available. Real camera guide, OCR-rate, thermal, tab-return, and camera-restart claims remain hardware gates. |
| Centering | **Tracked in the current card-centering contract** | This 2026-09-09 capture predates E-A/E-B and must not be used for current centering readiness. See the [current plan](../../review/opus-card-centering-implementation-plan.md) and [centering evidence](../../review/centering-evidence/). |

## Live gates that remain open

These are intentionally not “90% implemented” items to be silently marked done.

- [`release_followups.md`](release_followups.md) is the source of truth for
  collection cold-launch timing, 8 Hz scanner tracking, projection coalescing,
  additional graded-label samples, and live refresh/camera profiling.
- [`app_review_fix_plan.md`](../../app_review_fix_plan.md) still has evidence or
  product-owner gates for stale vendor-variant invalidation, migration
  serialization, store/account epoch scope, fan-out and large-session
  measurement, ProductIdentity misses, and the production bundle ID and
  entitlements. Its unchecked items are deliberate review gates, not forgotten
  implementation tasks.
- [`performance_review_remediation_plan.md`](../legacy/performance_review_remediation_plan.md)
  and [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md) distinguish
  landed simulator work from live-provider/Instruments measurements. Do not
  promote a “needs measurement” line to “done” because the simulator suite is
  green.
- [`shared_pricing_cache_plan.md`](shared_pricing_cache_plan.md) is a future
  backend project. Paid JustTCG licensing/key ownership (Gate A), the
  irreversible Firestore region choice (Gate B), and privacy/App Store review
  (Gate C) are all open before implementation should begin.
- Real-device scanner work remains open: camera pixel format versus OCR and
  thermal behavior, tab-bar flicker, camera restart latency, physical slab
  calibration, and the one physical Browse timing failure recorded by the
  performance plan.

## Documentation hygiene decisions

- `progress.md` remains a chronological engineering log. Old “pending” lines
  are preserved as history, but its current checkpoint now points here and to
  the live-gate documents. New status should be appended, not inferred from an
  old line.
- The portfolio history checklist was brought in line with the shipped
  additive market-movement design. It no longer asks for the removed
  Performance/Collection Value picker.
- The Price Check checklist now describes choice-time explanation and
  accessibility announcement rather than requiring stale persistent camera
  text.
- Deterministic route checklists now separate what the simulator proves from
  what requires a real camera, provider, or accessibility-size pass. Remaining
  unchecked boxes are therefore intentional.
- `artifacts/` is ignored local evidence. Root plans and this audit are the
  durable status record; captures are supporting proof and may need to be
  regenerated on another machine.

## October review reconciliation — 2026-10-02

The [October review ledger](../audits/october-review-remediation.md) owns the
new boundary-failure implementation and test evidence. The scanner recognition
plan's previous newest-50 backlog claim is superseded by unrestricted durable
retention. Interrupted collection recognition and pending duplicate prompts
are recovery work; explicit dismissals and Price Check still cancel.
[RF-13](release_followups.md#rf-13--october-review-performance-measurements)
keeps physical-device performance acceptance open. No executor hypothesis is
promoted to a measured defect or a release-readiness claim.

## Re-run rule

Review-fix reconciliation (2026-10-05; eleven finding fixes committed through
`55dc1e4`, remaining-audit cleanup local on that HEAD): the
[One Piece handoff](../audits/one-piece-integration-review-handoff.md) now
distinguishes the committed integration, committed fixes, local cleanup, and
historical transfer evidence. The old statements excluding `undefined/` from
review were incorrect after `55dc1e4` committed those copies; the cleanup removes
them and corrects both implementation-plan headers. Its old eight-label audit count describes the former regex;
the expanded boundary gate reports 37 existing game branches across Browse and
collection normalization. The broader detection does not complete the deferred
legacy extraction. Review-fix test evidence is recorded in
[the progress log](../../progress.md); production rollout, trust anchors,
mixed-client collection-write policy, and device/release acceptance remain open.

When a slice changes, update the smallest relevant checklist and add one line
to `progress.md`. When evidence is hardware- or provider-dependent, update
[`release_followups.md`](release_followups.md) instead of weakening a checklist
claim. A green simulator suite closes regressions; it does not close a physical
camera or live-network gate.
