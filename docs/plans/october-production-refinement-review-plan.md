# Production refinement review and remediation plan

**Status:** proposed review backlog; implementation decisions and acceptance pending — 2026-10-02.

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
| F1 | Headerless 429 can block all vendor lanes until midnight | High / high source confidence | Proposed localized policy fix |
| F2 | Provider billing-period usage merged into calendar-month counter | High / high for mismatch; prevalence unknown | Proposed accounting correction; reset authority must be established |
| F3 | Search catalog does not complete saved-scan recovery | High / high | Proposed explicit selection handoff |
| F4 | Old batch ZIP failure overwrites a newer batch's state | High / high | Proposed generation/ownership checks |
| F5 | Late certificate refinement alters a newer scanner session | High / high | Proposed session publication checks |
| F6 | Magic live directory freshness and update publication gaps | Medium / high | Proposed existing-cache/event correction |
| F7 | Owned labels omit grader/grade | Medium / high | Proposed value-snapshot/display correction |
| F8 | Vintage detail suppresses available exact prices | Medium / high | Proposed print-run-aware presentation |
| F9 | Activity read failures masquerade as empty history | Medium / high for failure path; not reproduced | Proposed snapshot/error correction |
| F10 | Duplicate publisher snapshot keys trap before rejection | Low; tooling only / high | Proposed validation-order correction |
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
| A | F1 transient cooldown | Both request paths recover consistently; explicit quota exhaustion remains distinct |
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

Start A/C/D as small boundary fixes after revalidation. Review B's reset inputs
before implementation; undertake E without weakening recovery safeguards. F–I
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

## Documentation handoff

This plan records the supplied review without application-code changes. Validate
relative links and `git diff --check` before handoff. Record later disposition,
implementation, and evidence against their actual candidate; do not silently
turn a proposal or a concurrent unverified change into a completed finding.
