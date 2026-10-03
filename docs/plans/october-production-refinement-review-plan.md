# Production refinement review and remediation plan

**Status:** A–J implemented and regression-verified; K triaged with the existing
latency gate open. L profiling and M screenshot/device/native acceptance deferred
at the owner's request; legal/support pages remain placeholders — 2026-10-03.

**Review baseline:** `fix/october-review-boundaries` at `73898e8`, clean during
the source review. The user requested documentation of the review for evaluation
and implementation as appropriate; this entry does not authorize or record code
implementation. Documentation was added on the same HEAD with pre-existing
uncommitted centering, test, project, and screenshot-script changes preserved.

## Purpose, authority, and evidence

Make the production app **fast, accurate, and a joy to use** with the minimum
necessary intervention. Prioritize real workflow improvements, correctness,
and unnecessary work over architecture changes or theoretical optimization.

This document owns the additional findings from the repository-wide review at
`73898e8`. It supplements the [October refinement implementation plan](october-refinement-implementation-plan.md)
and [October remediation ledger](../audits/october-review-remediation.md); it
does not reopen their implemented findings or replace subsystem contracts.
The [documentation audit](documentation_audit.md) reconciles authority boundaries.
The [release follow-ups](release_followups.md) remain the aggregation point for
device/runtime measurements. Centering acceptance remains governed by the
[centering contract](../../review/opus-card-centering-implementation-plan.md)
and [evidence ledger](../../review/centering-evidence/README.md).

The review was source-based, with inspection of tests and existing recorded
evidence. No fresh app build, XCTest suite, simulator session, physical-device
profile, native Photos/share rehearsal, or live provider request was performed.
Public JustTCG and Apple documentation was consulted for the quota-period and
submission requirements cited below. A source-proven execution path is not an
observed incident or a measured speed improvement.

**Revalidation before implementation:** source/tests/build settings outrank this
dated review. Locate the named functions rather than relying on baseline line
numbers. At documentation time, the existing working-tree changes already move
centering export rendering/encoding/writing into a detached snapshot task with
stale-result checks and a unique export directory. M1's original main-actor
description therefore applies to the reviewed commit, not that working tree.
Those changes have not been verified by this documentation task. Recheck M1,
G2, and any other overlapping work before creating another fix.

## Overall assessment and priorities

The application is in refinement territory. Preserve conservative matching,
separate ownership and price identities, fresh-context serialized writes,
explicit correction lineage, and price provenance. The highest-value remaining
opportunities concern recovery workflows, asynchronous publication boundaries,
and pricing availability policies. No architecture replacement is justified.

| ID | Opportunity | Priority / confidence | Disposition |
| --- | --- | --- | --- |
| F1 | Headerless 429 can block all vendor lanes until midnight | High / high source confidence | Slice A implemented; 121 focused simulator tests passed on 2026-10-03 |
| F2 | Provider billing-period usage merged into calendar-month counter | High / high for mismatch; prevalence unknown | Local budget separated from provider billing counts; regression verified |
| F3 | Search catalog does not complete saved-scan recovery | High / high | Selection handoff implemented; workflow regression verified; rendered acceptance deferred |
| F4 | Old batch ZIP failure overwrites a newer batch's state | High / high | Ownership checks implemented; delayed success/failure regression verified |
| F5 | Late certificate refinement alters a newer scanner session | High / high | Session publication checks implemented; delayed outcomes regression verified |
| F6 | Magic live directory freshness and update publication gaps | Medium / high | Existing cache/event correction implemented; regression verified |
| F7 | Owned labels omit grader/grade | Medium / high | Value/display correction implemented; quantity/completion regression verified |
| F8 | Vintage detail suppresses available exact prices | Medium / high | Edition-aware presentation and quote selection implemented; regression verified |
| F9 | Activity read failures masquerade as empty history | Medium / high; injected failure paths verified | Complete snapshot/error/retry behavior implemented; rendered acceptance deferred |
| F10 | Duplicate publisher snapshot keys trap before rejection | Low; tooling only / high | Validation order corrected; 74 package tests passed |
| M1 | Eager centering export repeats unused work | Measurement-gated; high for repeated work, unmeasured hitch | Revalidate against concurrent centering changes before profiling or changing |
| G1 | Live privacy/support destinations absent | Existing submission dependency / high | Owned by prior plan slice J; no duplicate implementation queue |
| G2 | Current centering acceptance baseline unresolved | Existing evidence dependency | Owned by centering contract and prior plan slice K |

## Findings and smallest sensible remedies

### F1 — Transient rate limiting can disable vendor access until midnight

**Where:** [ProductPriceService.swift](../../TradingCardScanner/Services/ProductPriceService.swift),
`get` HTTP 429 branch (baseline line 392), compared with
[JustTCGTransport.swift](../../TradingCardScanner/Services/JustTCGTransport.swift),
`send` HTTP 429 branch (baseline line 351).

**Behavior and impact:** a direct fallback response without `Retry-After`
records the next daily reset as its retry time. The shared transport instead
defaults to fifteen minutes. Both write the same persisted ledger, which blocks
all lanes. A fallback failure shortly after midnight can suppress vendor-backed
pricing and sealed-product access for nearly twenty-four hours, including after
relaunch. The provider distinguishes minute limits from daily/monthly exhaustion:
[rate limits](https://justtcg.com/docs/rate-limits) and
[error codes](https://justtcg.com/docs/errors), consulted 2026-10-02.

**Smallest remedy:** align transient headerless responses with the existing
bounded cooldown policy; honor supplied retry headers and keep explicit quota
exhaustion distinct. Do not add automatic retry loops. Treat a response carrying
an explicit daily/monthly exhaustion code according to that evidence rather
than treating all 429 responses as transient.

**Confidence:** high from source; no live incident reproduced. **Expected
benefit:** earlier recovery after transient throttling. **Regression risk:** low
if genuine exhaustion remains blocked. **Complexity:** preserves or slightly
reduces complexity by removing contradictory policies.

**Acceptance:** stub headerless minute-limit responses through both entry paths;
verify persisted retry times and cross-lane behavior. Cover numeric/date retry
headers, explicit exhaustion, relaunch, and unchanged interactive reserves.

### F2 — Monthly accounting combines different reset periods

**Where:** [JustTCGSyncLedger.swift](../../TradingCardScanner/Services/JustTCGSyncLedger.swift),
`syncFromServer`, `snapshot`, `rolloverIfNeeded`, and `nextMonthStart` (baseline
lines 105, 117, 144, and 165).

**Behavior and impact:** the app resets its monthly counter at the UTC calendar
month boundary, then takes the maximum of local usage and the provider's monthly
usage. JustTCG resets free accounts on their creation day and paid accounts by
billing cycle, rather than necessarily on the first of the month.
[Provider reset policy](https://justtcg.com/docs/rate-limits), consulted 2026-10-02.
A high imported usage count can survive provider renewal; a lower server count
cannot reduce it. At the local ceiling, requests stop before another response
can correct the state. Reset information and availability can be wrong even
while preserving the intentional conservative spending limit.

**Smallest remedy:** stop merging counts from different periods. Either align
the allowance with a trustworthy provider reset boundary or retain an explicit
local calendar spending budget separately from provider quota observations.
Establish the actual reset information available on each API path before
selecting the implementation; do not assume the existing usage metadata
supplies a calendar-period identity or a reliable reset timestamp. Do not
merely remove spending safeguards or clear counts whenever usage decreases.

**Confidence:** high for the mismatch; affected-account frequency is unknown.
**Expected benefit:** avoids extended local lockouts after provider renewal and
misleading reset dates. **Regression risk:** medium; this controls every vendor
request. **Complexity:** a small increase is justified to distinguish two facts
currently conflated, without building a billing subsystem.

**Acceptance:** injected-clock tests for a mid-month renewal, usage on both sides
of renewal/calendar rollover, restart, simultaneous reservations, and out-of-order
metadata. Retain daily/interactive ceilings and establish the trustworthy reset
input needed to recognize renewal without bypassing quota exhaustion.

### F3 — Search catalog does not resolve the saved scan

**Where:** [UnresolvedScanDetailView.swift](../../TradingCardScanner/Views/UnresolvedScanDetailView.swift),
Search catalog and its Browse sheet (baseline lines 99/121);
[CatalogCardDetailView.swift](../../TradingCardScanner/Views/CatalogCardDetailView.swift),
`commit` (baseline line 289); and
[ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift),
`resolveUnresolved` and the existing recovery/commit pipeline.

**Behavior and impact:** ordinary Browse opens without the unresolved row or a
selection callback. Its add action creates an independent acquisition, without
resolving the saved recovery record or carrying the original slab/additional-copy
intent. A user can identify and add a card yet retain the Needs attention row.
The prominent catalog action for a slab recovery is still Add Raw Copy. This is
an incomplete workflow, not proof that every search creates a duplicate.

**Smallest remedy:** introduce a narrowly scoped catalog selection handoff to
the existing recovery pipeline. Preserve original subject evidence, printing/run
selection, and duplicate confirmation; remove the saved row only after a
successful original resolution. Do not create a second ownership writer.

**Confidence:** high. **Expected benefit:** complete manual recovery, less
repetition, and fewer object-type mistakes. **Regression risk:** medium at the
ownership/identity boundary. **Complexity:** modest justified increase; reuse
existing resolution and commit gates.

**Acceptance:** raw Pokémon, Magic, slab, and additional-copy recovery saves the
intended object once with original evidence. Cancellation writes nothing;
failure retains a retryable row; explicit duplicate confirmation still applies.

### F4 — Old ZIP failure can overwrite a replacement batch

**Where:** [EbayListingPhotosView.swift](../../TradingCardScanner/Views/EbayListingPhotosView.swift),
`processBatch` early return and archive error handler (baseline lines 641/734).

**Behavior and impact:** archive success checks generation/cancellation, but
failure unconditionally clears loading, progress, and `batchDirectory` and
publishes its error. The archive worker is not cancellation-aware, so an old
operation can fail after cancel/reselect/restart and overwrite the new batch's
state. The initial generation-mismatch return also clears a shared loading flag
without establishing ownership.

**Smallest remedy:** clean the captured old directory independently, then fence
all shared-state publication by generation/cancellation. Clear tracked directory
references only if still owned by that operation. Reuse the single-card handler's
existing pattern; do not alter the archive implementation unnecessarily.

**Confidence:** high from source, no native reproduction. **Expected benefit:**
reliable cancel/restart and export ownership. **Regression risk:** low.
**Complexity:** preserved.

**Acceptance:** delay archiving, cancel/reselect/start another batch, then release
an old failure and old success. New loading/progress/directory/results survive;
old artifacts are cleaned; ordinary current-generation failure remains visible.
Include the stale task's initial-return path.

### F5 — Late certificate refinement can alter a new scanner session

**Where:** [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift),
`applyPendingGradedCertificationRefinement` nil/duplicate/error branches
(baseline line 4401 onward), and `beginSessionFinalization` (baseline line 1993).

**Behavior and impact:** refinement awaits persistence and potentially the price
identity gate. Ordinary success checks the session token, but nil, duplicate,
and failure publication occur before that check. Finalization drains for at most
two seconds and then starts a new session token. A late duplicate can decrement
the new session's success count; late errors can display old notes/haptics. The
review established a presentation/accounting defect, not corruption of the
authorized durable write.

**Smallest remedy:** use existing session/storage generation checks before every
post-await publication branch, including catch. Allow authorized persistence to
finish independently; do not extend the drain or cancel durable writes merely
to hide the UI race.

**Confidence:** high. **Expected benefit:** correct counts and feedback across
departure/reentry. **Regression risk:** low. **Complexity:** preserved.

**Acceptance:** hold refinement beyond finalization, start another session with
successful scans, then release duplicate, nil, and failure results. New counts,
receipts, notes, and feedback remain untouched; durable old results remain valid.

### F6 — Magic live set directories bypass freshness/publication

**Where:** [BrowseCatalog.swift](../../TradingCardScanner/Services/BrowseCatalog.swift),
`sets(for:)`, `loadSetDirectory`, `scheduleSetDirectoryRefresh` (baseline lines
253/390/401); [BrowseView.swift](../../TradingCardScanner/Views/BrowseView.swift),
`observeCatalogUpdates`; [Magic production configuration](../../Config/MagicCatalogProduction.xcconfig).

**Behavior and impact:** production uses `legacy-live`. Warm `setCache` entries
return without age checks. Stale disk entries initiate a background load, but
that load changes the caches without the update event Browse observes. Updated
sets can remain absent from the visible directory; memory caching bypasses the
disk directory's twenty-four-hour freshness policy.

**Smallest remedy:** publish the existing update event when refreshed directory
contents change and apply the existing age policy to the live memory directory.
Preserve signed authority and valid selected-set retention; avoid a new cache.

**Confidence:** high. **Expected benefit:** predictable new-set availability
without restarts or unrelated events. **Regression risk:** low–medium for event
feedback/selection reconciliation. **Complexity:** small localized increase.

**Acceptance:** old cached directory followed by changed network content updates
the open screen; fake-clock expiration initiates one coalesced refresh; retained
selections survive. Check remote-authority mode does not admit raw directories.

### F7 — Owned labels omit grader and grade

**Where:** [CatalogCardDetailView.swift](../../TradingCardScanner/Views/CatalogCardDetailView.swift),
`ownedSection` and `ownedLabel` (baseline lines 192/442);
[BrowseCatalogModels.swift](../../TradingCardScanner/Models/BrowseCatalogModels.swift),
`CatalogOwnershipCardSnapshot` (baseline line 1166).

**Behavior and impact:** ownership intentionally includes graded cards, but its
value snapshot lacks grader/grade and the label uses finish/treatment only. Raw
and PSA 10 copies can both display Normal; a manually added graded copy can
display Unknown finish. Correct quantities become hard to interpret.

**Smallest remedy:** carry the small grade description needed by this display
through the existing snapshot and format graded rows accordingly. Do not change
matching, quantity grouping, or set-completion semantics.

**Confidence:** high. **Expected benefit:** understandable, accurate ownership
presentation. **Regression risk:** low. **Complexity:** small justified increase.

**Acceptance:** raw plus graded copies, two grades, and multiple certificates;
verify labels, quantities, accessibility descriptions, and unchanged completion.

### F8 — Vintage detail hides usable exact prices before addition

**Where:** [CatalogCardDetailView.swift](../../TradingCardScanner/Views/CatalogCardDetailView.swift),
`priceSection` (baseline line 207) and its print-run-aware add pricing;
[PriceProvider.swift](../../TradingCardScanner/Services/PriceProvider.swift), `CardPricing`.

**Behavior and impact:** any Pokémon print run, including Unlimited, replaces
price presentation with a caution about pricing after adding. The existing add
path can already accept an exact quote for that object. The user loses useful
information while deciding what to add, despite its availability afterward.

**Smallest remedy:** present only quotes accepted by the existing print-run-aware
pricing path, with retrieval time and honest missing-price states. Do not expose
an aggregate list that borrows between editions.

**Confidence:** high. **Expected benefit:** more useful vintage browsing and
consistent pricing behavior. **Regression risk:** low–medium; edition separation
is essential. **Complexity:** preserves pricing architecture with a small display
adaptation.

**Acceptance:** Unlimited finishes, explicit First Edition quotes, and unsupported
Shadowless quotes; no cross-run borrowing and no fabricated value when absent.

### F9 — Activity read failure looks like empty history

**Where:** [CollectionActivityLogView.swift](../../TradingCardScanner/Views/CollectionActivityLogView.swift),
`reloadSnapshot` (baseline line 162).

**Behavior and impact:** three fetches independently use `try? ... ?? []`.
Failure can erase the visible history or remove correction/restore affordances
without explanation, precisely when someone may be investigating a problem.
Nothing happened and history could not be read are different states.

**Smallest remedy:** read a complete replacement snapshot before assigning it;
retain previous useful data on failure and expose an error/retry. Do not treat
stale mutation eligibility as newly verified; keep transactional write preflight.

**Confidence:** high for the path, storage failure not reproduced. **Expected
benefit:** truthful recovery UI with retained context. **Regression risk:** low.
**Complexity:** slight increase in explicit error handling.

**Acceptance:** inject each read failure on cold load and after success; verify
retained history, error visibility, safe actions, and successful retry.

### F10 — Publisher validation can trap before duplicate rejection

**Where:** [Pokémon candidate validator](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogCandidateValidator.swift),
snapshot dictionary construction (baseline line 120).

**Behavior and impact:** `Dictionary(uniqueKeysWithValues:)` precedes the
snapshot uniqueness guard. Duplicate normalized set IDs trigger a precondition
failure before the intended validation error. This affects publisher tooling;
it is not an established shipping-app crash.

**Smallest remedy:** validate normalized-key uniqueness before dictionary
construction and throw the existing candidate error.

**Confidence:** high. **Expected benefit:** predictable malformed-input rejection.
**Regression risk:** low. **Complexity:** preserved by moving existing validation.

**Acceptance:** duplicate candidate throws without process termination; valid
candidates and release validation remain unchanged. Keep this low-priority slice
separate from production UX work.

## Performance, polish, and complexity

### M1 — Eager centering export preparation

**Baseline location:** [CardCenteringView.swift](../../TradingCardScanner/Views/CardCenteringView.swift),
`ExportInput` task and `makeExportFile` (reviewed lines 511/229);
[CardCenteringExport.swift](../../TradingCardScanner/Services/CardCenteringExport.swift).

At the reviewed commit, every settled image/measurement/rotation change renders,
PNG-encodes, and writes an export synchronously through the main-actor model
after a 180 ms debounce, even when Share is unused. Ratio-based filenames create
multiple temporary exports without an explicit production cleanup lifecycle.
Repeated work is demonstrated; a visible hitch is not. The presentation image is
bounded, so this is not repeated full-resolution 48 MP rendering.

**Current overlap:** documentation-time uncommitted changes move work into a
detached snapshot task, add unique directories, and fence stale results. Do not
implement the reviewed remedy blindly or call those changes verified. Evaluate
remaining eager work and artifact lifetime against that implementation.

**Conditional smallest remedy:** if representative traces establish material
cost, prepare on demand with a clear preparing state and generation checks.
Own temporary files through actual native share consumption; do not delete files
while another consumer needs them. Retain native sharing behavior.

**Confidence:** high for baseline repeated work; latency benefit unmeasured.
**Expected benefit:** fewer renders/encodes/writes and potentially smoother edits.
**Regression risk:** medium for share timing/lifetime. **Complexity:** potentially
reduced by removing eager wiring; a small preparation state remains necessary.

**Acceptance:** identical guide-step/rotation workloads with/without Share on
supported hardware; main-thread stalls, operation counts, encoding/write time,
output equivalence, latest-measurement publication, share completion, and cleanup.

### Measurement-only targets

Use [release follow-ups](release_followups.md) and the existing October measurement
gate; this table does not create duplicate release gates. Use the external SSD
for build artifacts/caches/results when available. Record commit/worktree identity,
device/OS/build configuration, input sizes, repetitions, counts, elapsed time,
main-thread stalls, peak memory, and final data/output equivalence.

| Workload | Evidence needed before changing | Decision informed |
| --- | --- | --- |
| Collection first paint / portfolio replay | Approximately 1,500 holdings with realistic history; read/recompute counts and actual actor stacks | Whether projection/replay or executor placement causes material stalls |
| CSV import/export | Representative sizes, fetch/encode/save costs, memory, malformed sibling rows | Whether indexing or preparation needs adjustment; preserve per-row isolation |
| Camera/OCR | Oldest supported device, historical cards, glare/dim light, long sessions, OCR/tracking cadence and thermal behavior | Whether capture quality/scheduling actually limits throughput |
| Detail/custom artwork | Transfer/decode/normalization/cache misses and main-thread time | Whether remaining synchronous work causes visible stalls |
| Listing photos | Native-resolution batches; worker/inspection/share/Photos memory peaks | Whether quality-preserving memory or processing changes are necessary |
| Finish effects/transitions | Frame pacing during scrolling, representative devices, Reduce Motion | Whether effects impose a meaningful cost |

UX priorities are F3/F6–F9 and reliable cancellation/session behavior in F4/F5.
These complete existing flows rather than redesign navigation. Safe complexity
reduction consists of eliminating divergent rate-limit policy, reusing recovery
commits instead of a disconnected Browse-add workaround, and conditionally
removing eager centering export work. Broad file splitting, generalized caching,
new service layers, and speculative executor changes are not justified.

## Existing release dependencies and historical evidence

### G1 — Live Release privacy/support destinations

[Release build settings](../../TradingCardScanner.xcodeproj/project.pbxproj)
at reviewed lines 1414/1415 are empty; the
[Settings surface](../../TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift)
shows unavailable-link text. The prior refinement plan's **slice J** owns this
dependency. Owner-approved live destinations are required; proposed future
domains/pages are not acceptance evidence.

**Smallest remedy:** configure approved live URLs accepted by the existing
validator and confirm hosted content/contact routes. **Confidence:** high.
**Benefit:** working support/privacy access and removal of a submission dependency.
**Risk:** low configuration risk. **Complexity:** unchanged. **Acceptance:** built
Release `Info.plist`, in-app links, effective content/contact route, and matching
App Store Connect entries. Apple's
[privacy requirement](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
and [developer-information requirement](https://developer.apple.com/app-store/review/guidelines/#developer-information)
were consulted 2026-10-02; this is not a prediction of actual rejection.

### G2 — Current centering baseline and acceptance

The October ledger records an earlier 1,743-test simulator run with seven skipped
and 25 assertion failures across ten centering cases against binaries through
`248a61d`. Those counts are **historical**, not current failures at `73898e8`
or the documentation-time working tree. The prior plan's **slice K** and the
centering contract own fresh triage. Source guard correctness does not prove
detector reference accuracy or real-device responsiveness.

**Smallest next action:** reproduce affected selectors against one known build;
separate geometry/arithmetic, presentation/export, reference selection,
diagnostic-contract, and latency failures. Use injected known geometry to isolate
layers; repair only reproduced production defects. Do not weaken tolerances or
discard diagnostic assertions based on their names. **Confidence:** high that the
recorded evidence is historical; current failure status remains unverified.
**Benefit:** reliable release decisions. **Risk:** low for triage; subsequent
code risk depends on demonstrated root cause. **Complexity:** no increase from
triage. **Acceptance:** dated assertion-level dispositions and complete relevant
suites, with physical-device gates reported separately.

## Investigated areas to preserve

- Fresh-context serialized ownership writes, ledger completeness, correction
  lineage, and transactional rollback boundaries.
- Conservative identity matching and explicit duplicate/copy authorization.
- Exact print-run/finish/treatment identities and USD eligibility. Do not trade
  missing prices for a quote belonging to another physical object or currency.
- Separation of Price Check reference knowledge from ownership/portfolio truth.
- Stale-price retention with original retrieval/provenance timestamps and shared
  request coalescing/cancellation contracts.
- Interactive quota reserves and intentional spending ceilings; fix F1/F2's
  policy/accounting problems without removing these protections.
- Native-resolution listing quality absent measured memory evidence.
- Local-only release scope. Reviewed CloudKit support is not entitled-device
  evidence and does not justify enabling sync for this release.
- Centering detector thresholds and adopted hybrid confirmation boundary absent
  a reproduced defect under the current contract.

No shipping-app crash or widespread ledger corruption was established. F10 is
a concrete publisher-tool trap; F4/F5 are asynchronous publication defects;
F1/F2 affect vendor availability; F9 affects truthful read/recovery behavior.

## Conservative implementation roadmap

Each slice requires current-source review first and is independently reviewable.
Use existing clocks, provider fakes, delayed workers, and write gates where
possible. Add only a narrow seam required to reproduce the user-visible defect.
Do not add implementation-mirroring or layout source-text tests.

| Slice | Scope | Independent acceptance / dependencies |
| --- | --- | --- |
| A | F1 transient cooldown — implemented 2026-10-03 | Both request paths recover consistently; explicit quota exhaustion remains distinct; 121 focused tests passed |
| B | F2 monthly-period accounting | Establish reset authority, then test renewal/rollover/restart/concurrency; keep separate from A |
| C | F4 batch publication ownership | Delayed old success/failure cannot alter replacement batch; old cleanup still occurs |
| D | F5 certificate result publication | Late nil/duplicate/error cannot affect fresh session; authorized write remains durable |
| E | F3 manual recovery selection | Preserve original intent, save once, cancel safely, retain row on failure |
| F | F6 live Magic directory freshness/events | Updated sets visible, selection retained, one refresh, signed-authority behavior protected |
| G | F7 graded ownership labels | Correct display/accessibility with unchanged quantities/completion |
| H | F8 exact vintage prices | No cross-run borrowing; honest missing-price states |
| I | F9 activity read handling | Complete replacement snapshot, retained useful data, visible error, safe retry/actions |
| J | F10 publisher uniqueness guard | Malformed input throws; valid candidate behavior unchanged; low priority |
| K | G2 centering triage | Continue existing owner plan; revalidate concurrent work and classify current failures |
| L | M1 and other measured work | Profile current implementation; modify only a demonstrated bottleneck; compare equivalent outputs |
| M | G1 and native release acceptance | Continue existing URL/acceptance owners; live pages, Photos/share, accessibility evidence |

The user authorized B–M in roadmap order and requested builds/tests at the end,
unless a critical issue requires an earlier check. B–J are implemented with
passing regression cases. K's current centering failure is triaged below. The
owner then requested wrapping up without further screenshots or device-specific
testing; L profiling and M native/device acceptance remain deferred. F–I
are focused polish/reliability work; J can follow separately. K/M remain existing
release dependencies rather than optional performance cleanup. Do not delay
owner-controlled URL preparation behind unrelated code work.

For each code slice, run the narrowest relevant `xcodebuild` build/test and inspect
real rendered UI when presentation is involved. Expand to the integrated/full
suite when persistence, lifecycle, or portfolio risk warrants it. Record exact
candidate identity and outcomes, distinguishing current regressions from dated
known failures. Only measured output-equivalent improvements justify speed claims.

## Coverage and confidence limits

Repository-wide production source coverage at the review baseline comprised
**152 app Swift files (97,811 lines), 18 Pokémon package source files (5,792
lines), and nine Magic package source files (2,105 lines): 179 files / 105,708
lines**, including conditional debug/support code. Depth followed risk and
cross-file execution paths; this is not equal-depth certification of every line.

Coverage included scanning/parsing, saved recovery and duplicate handling,
ownership/persistence/migrations, pricing/refresh/quotas/caches, portfolio/history,
Browse/Collection/detail/settings, centering, listing export, lifecycle/bootstrap,
and catalog construction/validation/publication. Existing implemented fixes were
distinguished from new findings rather than repeated as open defects.

Insufficient execution confidence remains for physical-camera behavior, actual
SwiftUI/assistive-technology interaction, device latency/memory/thermal behavior,
native Photos/share consumption, live provider responses, numerical detector
accuracy across the corpus, entitled CloudKit, and live publishing infrastructure.
Those require targeted execution evidence; source inspection cannot retire them.

## Implementation record — 2026-10-03

The user authorized implementation after the review was documented. The checkout
was clean on `fix/october-review-boundaries` at `dd2a1e3`; changes below are an
uncommitted working-tree slice against that baseline. The review and its original
documentation-only scope above remain dated history.

### B–M implementation pass and final verification

- **B coded:** the documented response metadata has no billing-period ID or reset
  timestamp. Keep the explicit local UTC calendar-month spending budget;
  reconcile only matching UTC daily provider counts. Monthly provider usage no
  longer inflates local spending. Preserve existing persisted counts until the
  next calendar rollover because their local/provider portions cannot be
  reconstructed safely. Added renewal, restart, rollover, late-response, legacy,
  and concurrent-reservation cases. The provider continues to enforce its own
  billing quota; explicit quota 429 handling remains independent.
- **C coded:** stale task entry leaves replacement loading state alone. Archive
  completion cleans the captured run and publishes only to its current owner;
  delayed failure/success cases cover cancellation and generation replacement.
- **D coded:** session/storage fences precede nil/duplicate/error publication and
  protect in-flight refinement bookkeeping. Delayed cases exercise actual bounded
  finalization/reentry; the successful old write remains durable.
- **E coded:** card-only, original-game Browse selection replaces standalone add
  actions with a saved-scan handoff. Original subject/slab evidence, edition and
  finish selection, duplicate authorization, and the existing writer remain in
  control. Cases cover raw/slab Pokémon/Magic, failed save, finish cancellation,
  additional-copy confirmation, and absence of sealed vendor search requests.
- **M URL decision:** the owner confirmed on 2026-10-03 that privacy/support pages
  are still not live and requested keeping placeholders. Leave Release URL
  settings unconfigured and the existing unavailable-link UI intact. Live URL
  and App Store metadata acceptance remains explicitly deferred; do not enable
  the future domains or publish a website in this pass.

- **F coded:** legacy live Magic set directories use the existing 24-hour cache
  lifetime in memory and on disk. Stale data remains usable while one coalesced
  refresh publishes a changed directory; signed registry authority still wins.
- **G coded:** owned rows display grading company/grade for slabs; raw finish and
  treatment labels remain unchanged. Quantities and completion are not altered.
- **H coded:** published price rows use the selected vintage print run and retain
  honest gaps. First-edition quotes are not borrowed for Unlimited/Shadowless.
  The initial full run reproduced an additional underlying price boundary:
  `1st-edition` stamps were accepted as generic holo details. A read of the public
  [Base Set provider response](https://api.tcgdex.net/v2/en/cards/base1-4)
  confirmed the stamp/subtype representation on 2026-10-03. Edition lookup now
  recognizes that stamp, respects the selected finish, and restricts Unlimited
  detail lookup to unstamped Unlimited records before using its flat quote.
  Shadowless remains an honest gap under the existing price-authority contract.
- **I coded:** activity refresh publishes only a complete three-read snapshot.
  Failure retains prior data, shows retry, and pauses actions until a fresh read.
- **J coded:** snapshot ID uniqueness is checked before dictionary construction;
  malformed publisher input throws the existing validation error.

The requested end-of-pass verification began after B–J coding and K–M source
revalidation. The Pokémon publisher package passed 74 tests. The initial signed
app run completed 1,791 cases: 1,781 passed, seven skipped, three failed cases
(six assertions): one quote-cache mock counted directory requests as card
requests; the new vintage case exposed the edition boundary above; and the
unchanged centering latency gate failed at its upper-middle/median statistic
1.6244 / maximum 1.9206 seconds. The first two were corrected. A post-fix rerun
exposed a retry-save test issuing its answer before the identification task was
idle; its predicate now waits for that actual terminal state, with the save and
request-count assertions unchanged.

**Final result:** `Final-regression-v2` rebuilt the final source and executed
1,714 cases: **1,707 passed, seven existing skips, zero failures**. This includes
the entire remaining target and centering UI/export/input coverage. It excludes
the five expensive detector/corpus/diagnostic classes already completed in the
initial full run; those source files were not modified by B–J. The original full
run is not described as passing. REQ-022 retains both unchanged latency limits;
automatic reference accuracy, held-out acceptance, and hardware responsiveness
remain separate open gates. No detector, ground truth, or tolerance was changed.

Evidence is on the external SSD under
`CodexBuilds/TradingCardScannerRefinement-20261003/`: `Integrated-B-M.log` and
`.xcresult`, `Final-regression.log` and `.xcresult` (the failed intermediate
retry-save run), `Final-regression-v2.log` and `.xcresult`, and
`PokemonPackage.log`. Candidate: uncommitted working tree on
`fix/october-review-boundaries` against `dd2a1e3`.

**K:** existing guided correctness and presentation/export assertions passed;
REQ-022 is the single observed centering failing case. Its failure is the
existing latency disposition in the [guided repair ledger](../audits/centering-guided-repair.md),
not a B–J correctness regression. The original automatic comparisons remain
research evidence; passing guided checks does not establish automatic accuracy.

**L/M disposition:** the owner requested no more screenshots or device-specific
testing on 2026-10-03. No further profiling, rendered-workflow acceptance,
Photos/share completion, VoiceOver traversal, or device run was performed.
The existing detached centering export implementation was retained; no
unmeasured performance rewrite was introduced. Live privacy/support Release
configuration remains unconfigured by the owner's explicit placeholder decision.
These gates are deferred, not passed. No speed or release-readiness claim is implied.

### Uncommitted review follow-up — 2026-10-03

Review of the complete working-tree diff against `dd2a1e3` found additional
boundaries in the new edition pricing and catalog recovery paths. Edition quote
selection now excludes Jumbo/non-English objects and unrelated stamps. An
edition-only quote cannot price an unknown or specific physical finish. Catalog
recovery validates a selected finish against the existing resolver options,
retains the required vintage edition question for raw copies, and carries a
saved slab's validated printed edition unless the user selects another edition.
These are local checks using existing models/resolvers, with five new regression
cases; no new subsystem or future feature was added.

The support draft now distinguishes network updates from available offline
data. Slice A's earlier F2-open wording is explicitly historical rather than
contradicting the subsequent B implementation.

**Verification:** ten affected simulator suites covered 418 distinct test cases
across the review runs. The first run executed 417 cases with two failures in
the new pricing fixtures, which lacked a required set card count. After fixing
the fixtures, all 54 PricingTests passed. The later slab-edition fix and its new
case passed the complete 90-case ScannerViewModelTests suite. The other eight
suites passed all 274 cases. The Pokémon package passed 74/74. Relative Markdown
links and `git diff --check` passed. Artifacts use the same external SSD directory:
`Uncommitted-review`, `Uncommitted-review-pricing-v2`, and
`Uncommitted-review-recovery-v2` logs/result bundles, plus
`Uncommitted-review-package.log`.

The earlier broad regression above remains evidence for its dated source;
this follow-up is focused verification, not a new full-suite or physical-device
run. No centering gate or release acceptance changed.

### Slice A — F1 shared rate-limit policy

Both `ProductPriceService.get` and `JustTCGTransport.perform` now use the existing
transport's fifteen-minute cooldown for headerless transient or unrecognized
HTTP 429 responses. Valid numeric or HTTP-date `Retry-After` headers take
precedence. Explicit `DAILY_LIMIT_EXCEEDED` and `REQUEST_LIMIT_EXCEEDED` responses
retain a next-UTC-day recheck when no usable header exists. For monthly exhaustion
that is a bounded recheck, **not** the provider's billing reset date. The official
[error codes](https://justtcg.com/docs/errors) and
[rate-limit policy](https://justtcg.com/docs/rate-limits) were rechecked 2026-10-03.

The persisted shared block still covers every lane. No automatic retries were
added. Daily/monthly spending ceilings, background ceilings, and interactive
reserves are unchanged. The duplicate fallback retry parser and unused reset
helper were removed. F2's monthly-period accounting was still open at this
earlier checkpoint; its subsequent slice B implementation is recorded above.

Six new response-level regression cases exercise both request paths using a
mocked URL protocol: headerless minute limits, undecodable bodies, explicit quota
codes, numeric/date headers, and malformed headers. Each checks persisted retry
time, cross-lane blocking without another reservation, and expiry. Existing
ledger tests cover request ceilings and interactive reserves.

**Verification:** `TradingCardScanner-ProfileLocal`, `DebugRemoteLocal`, iPhone
17 Pro / iOS 26.5, normal simulator signing, parallel testing disabled. The
complete `JustTCGContractTests` (73) and `ProductFallbackTests` (48) classes passed:
**121 tests, zero failures, zero skips**. Existing simulator app data was preserved
by creating a disposable simulator for this selection. No live provider requests
were used. This is focused deterministic evidence, not a full-suite run or
device/provider/release acceptance.

Command (substitute a fresh disposable simulator ID):

```sh
xcodebuild -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner-ProfileLocal -configuration DebugRemoteLocal \
  -destination 'platform=iOS Simulator,id=<disposable-simulator-id>' \
  -derivedDataPath '<external-ssd>/CodexBuilds/TradingCardScannerCenteringRepair' \
  -clonedSourcePackagesDirPath '<external-ssd>/CodexBuilds/TradingCardScannerRefinement-20261003/Packages' \
  -resultBundlePath '<external-ssd>/CodexBuilds/TradingCardScannerRefinement-20261003/Pricing-A.xcresult' \
  -parallel-testing-enabled NO \
  -only-testing:TradingCardScannerTests/ProductFallbackTests \
  -only-testing:TradingCardScannerTests/JustTCGContractTests test
```

The build cache, command log (`Pricing-A.log`), and result bundle
(`Pricing-A.xcresult`) are on the external SSD in the paths above. Use a new
result-bundle path when rerunning; Xcode does not overwrite an existing bundle.
No elapsed-performance improvement is claimed: the verified benefit is a
shorter availability block under a reproduced response condition. This focused
run does not establish acceptance for the later B–J changes.

## Documentation handoff

Validate relative links and `git diff --check` before handoff. Record later
disposition, implementation, and evidence against their actual candidate; do not
silently turn a proposal into a completed finding.
