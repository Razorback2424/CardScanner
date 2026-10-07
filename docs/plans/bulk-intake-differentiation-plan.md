# Bulk intake differentiation plan

**Status:** Stage 0 implemented and simulator-verified — 2026-10-07.
**Authority:** owner-approved scope and decisions dated 2026-10-06. Source and
current test evidence outrank the audit's historical line numbers.

## Purpose and boundaries

Prepare a moderated study with 10–15 collectors comparing CardScanner, Rare Candy
and DeckTradr on bulk scan speed, silent errors, correction effort and preference.
The scanner already supports automatic collection adds, a presentation latch,
speculative lookup, provenance and persistent Needs attention. Fix only the
verified friction in the tasks being measured.

Never automatically save a guessed base finish. That would introduce the study's
headline failure mode: a silently inaccurate collection. This work is separate
from the [Collection Integrity strategy](../vision/CardScanner%20Collection%20Integrity%20Strategy%20%E2%80%94%20Start-to-Finish%20Implementation%20Plan.md)
and its retention experiment. Bulk intake evidence informs differentiation;
the [release go/no-go framework §6](../release/card-scanner-1.0-go-no-go-framework.md#6-competitor-benchmarking-is-intelligence-not-a-launch-gate)
explicitly excludes competitor benchmarking from launch arithmetic. This study
does not demonstrate repeat Verify retention, willingness to pay or release
readiness. Follow the existing
[privacy rule](../experiments/collection-integrity-v1-retention-contract.md#privacy-rule).

## Approved decisions

- Dismissed finish and print-run questions save identified cards to Needs attention.
- After repeated identical finish answers, offer an explicit Finish Lock choice.
- Returning-copy automatic adds require spatial-exit proof and a default-off
  experimental setting. Enable only after the owner measures phantom duplicates.
- True first launch with an empty collection opens Scan. Other launches open
  Portfolio, which receives a real empty state and a Scan action.
- No commits or pushes without the owner asking.

## Stage ledger

| Order | Stage | Size | Store / ledger change | Status |
| --- | --- | --- | --- | --- |
| 0 | Study metrics log | S | No | Implemented; 118/118 focused simulator tests pass |
| — | Owner baseline self-pilot on device | — | — | Pending; required before Stage 1 |
| 1 | Skipped question → Needs attention | S–M | New unresolved reason only | Pending baseline |
| 2 | Needs attention: choices first | S | No | Pending |
| 3 | First launch, empty Portfolio, recent/session surfaces | S | No | Pending |
| 4a | Surface raw Fix finish | S | No | Pending |
| 4b | In-session Wrong card? | M | Undo + add through writer, one save | Pending |
| 4c | Collection Change printing | M–L | New correction ledger path | Pending |
| 5 | Suggest Finish Lock for the pile | S | No | Pending |
| 6 | Returning-copy automatic add | M | No | Pending; setting stays off |
| 7 | Documentation and frozen study protocol | S | No | Plan tracking begun; protocol pending |

Each stage is independently buildable and testable. Stop after Stage 0 until
the owner records the pre-change device baseline. Do not infer that a passing
simulator suite satisfies this checkpoint.

## Stage 0 — measurement before behavior changes

`ScanSessionMetricsLog` is an actor at Application Support/Scanner/
`scan-session-metrics.json`. Directory and file are excluded from backup. It is
local only; sharing requires Settings → Scanning → Export session log.
Record session metrics defaults off and applies at the next new Scan session.

The versioned JSON contains session `startedAt` / optional `endedAt`, encounters
with `confirmedAt`, a fixed `outcome`, monotonic `durationMs`, and an array of
`variant`, `printRun`, `printing`, `duplicate` or `heldDuplicate` interruptions.
Counters are undo, finish correction, printing correction, Needs-attention filed
and resolved, lock suggestions shown and accepted, auto-added duplicates and
their undos. Future-stage counters remain zero until those features exist.
Runtime UUIDs route callbacks only and are never serialized. No identifiers,
names, prices, images, collector IDs or free-text diagnostics enter the API.

Hooks are the confirmed-candidate start, `endOneCardScan`, the four question
creation sites, duplicate prompts, held-copy offer publication, successful undo
and finish correction, new unresolved-row filing, successful recovery-row
clearing and session finalization after the bounded writer drain. Actor calls are
explicitly ordered; export waits for queued events. Unreadable or newer-version
evidence is preserved, and export reports failure rather than replacing it.

Terminal outcomes follow the existing per-card signpost choke point. An
interruption counts each displayed question/offer. Filing counts newly created
rows, not repeated updates to an existing row. Resolving counts cleared rows
after successful recovery. Dismissing a recovery row is not a resolution. A held
offer can be recorded against an already completed encounter. `endedAt: nil`
denotes a session without a recorded finalization, including process termination;
do not treat it as a completed session in the study. Encounter time runs from
confirmation to the first terminal outcome, including question time. It excludes
time before confirmation and later review; the moderator must separately measure
time to an accurate collection and audit silent errors.

Tests cover round trip, default-off/no writes, preservation of existing evidence,
backup exclusion, strict payload fields, no names or runtime IDs, stale-session
fencing, held-copy offers, unreadable evidence and dismissed-choice recording
(`choice-dismissed` plus `variant`) without changing baseline dismissal behavior.

**Verification — 2026-10-07, `3fe972a` plus existing local changes:** Debug
simulator build and the Stage 0 selection pass on iPhone 17 Pro / iOS 26.5:
4 metrics-log tests, 97 scanner view-model tests and 17 unresolved-store tests
(118 passed; no failures or skips). Results reside on the external SSD under
`TradingCardScannerDerivedData/bulk-intake-stage-0/Logs/Test/`.
Documentation links and `git diff --check` pass. This verifies deterministic
instrumentation and existing scanner behavior, not device performance or actual
system share-sheet interaction. The owner baseline remains pending.

### Owner baseline checkpoint

1. Install the Stage 0 build on the physical device, enable Record session metrics,
   leave Scan and return to start a logged session.
2. Use a known supported pile with repeated copies, ambiguous finishes and
   print runs. Record deck composition and ground truth privately, outside the
   metrics payload. Include deliberate skips, a successful undo/correction and
   a Needs attention recovery.
3. Leave Scan to finalize, then export the JSON from Settings → Scanning.
   Check that terminal outcomes, interruptions and counters match observation.
4. Record wall-clock time to an accurate collection, silent errors, question
   interruptions and correction effort. Retain the pre-change build and export
   privately; confirm the baseline is captured before implementing Stage 1.

The formal participant study cannot begin until Stage 7 freezes supported deck
composition, counterbalanced app order, thresholds and the measurement protocol.

## Stage 1 — skipped questions retain the card

- Add `UnresolvedReason.choiceSkipped`, preserving unknown-reason decoding.
  Detail copy: “Finish not chosen — choose it to add this card”.
- `dismissChoice()` files the pending card and candidates using the interrupted
  recovery pattern, with its resolved provider ID, only outside duplicate context.
  Duplicate dismissal remains an explicit decision not to add another copy.
- `dismissPrintRunChoice()` also files it. Price Check files nothing. Preserve
  historical Pokémon `dismissIdentityChoice()` behavior.
- Reuse `.retryLookup` to identify again and ask for finish. The finish question's
  X becomes “Later”, accessible as “Save to Needs attention”, outside duplicates.
- Cover reason round trip, collection versus Price Check, print-run dismissal,
  duplicate dismissal, and recovery through finish commit and row clearing.

## Stage 2 — recovery choices first

Order detail content: Choose printing / Choose card / Actions, then Dismiss, then
a collapsed “What was read” disclosure containing diagnostics. For a skipped
choice, the primary “Choose finish” action uses retry lookup. List rows lead with
the known card name from printing/Pokémon candidates or hints, above identifiers.
Use “Needs attention” for the navigation title. Add surface smoke coverage.

## Stage 3 — landing and recent acquisition surfaces

- Before constructing `ContentView`, fetch the collection count in
  `CollectionSessionContent`. Empty and unset `didCompleteFirstLaunchRouting`
  passes `.scan`; always record the first decision. Default stays `.portfolio`;
  preserve DEBUG route parsing. This intentionally prompts camera permission on
  first launch. A new device awaiting iCloud mirroring can read empty once.
- Inject `onOpenScanner` into Portfolio. Show “Your collection starts here” /
  “Scan cards to track value and changes.” / “Start Scanning” instead of hero and
  charts only when `projectionStore.isLoaded && snapshot.rows.isEmpty`. Do not
  infer emptiness from deferred `portfolio.holdings`; retain Value unavailable
  for unreadable storage.
- Add Recently Added sorting by `row.dateAdded` descending with existing name
  tie break; update Collection sort labels/symbols. This means “last added to”.
- Capture `ScanSessionSummary.collectionKeys` before clearing session state.
  Tapping the summary opens Collection with a `sessionFocus` set. Add optional
  key filters to `CollectionFilters`, matching and query cache keys; display a
  clearable “Just scanned · N” chip. Rekeyed cards drop out of the old focus.
- Add Collection History to Collection's toolbar menu. Use `recentScanLimit`
  instead of hard-coded five for Review session.
- Cover recent sort, ties, key filtering, captured summary keys and surface
  construction. Capture first launch, PortfolioEmpty and ScanSessionSummary routes.

## Stage 4 — correct an acquired copy

Existing constraints: variant correction moves a whole open activity claim
(`remainingQuantity == quantity`); raw correction uses two ledger legs under one
operation ID; undo reverses single-copy lineages. There is no printing-change API.
Use the existing `.userCorrected` identity resolution for printing changes.

### 4a — visible raw Fix finish

Add the raw acquisition descriptor matching the graded predicate, without a fetch
limit. One open claim opens `CollectionActivityEditor`; several open claims push
`CollectionCardHistoryView`. After whole-row rekeying, `onRekeyed(newKey)` selects
the replacement in Collection. No store changes. Construct raw single/multi-claim
surfaces and retain Browse/activity-history correction coverage.

### 4b — in-session Wrong card?

Raw scan review gets a secondary Wrong card? action. Present Browse constrained
to the scan's game, prefilled with its name through optional initial search text.
Use catalog-card selection and the `.catalog` recovery branch's finish/print-run
evidence; ask explicitly if multiple options remain.

`ScannerCollectionWriter.replaceScannedPrinting` mirrors raw-to-graded conversion:
undo without saving, add with `.userCorrected` without saving, stage price and
save once; roll back on error. The view model uses generation/session guards,
keeps the RecentScan ID and replaces committed projections. Review rereads by ID.
History's Undone + Added representation is accepted for this path.

Cover the same scan ID, removal of old key, destination quantity one, corrected
identity provenance, session undo and injected failure without collection/ledger
changes. Run ownership completeness and update its source entry-point inventory.

### 4c — collection Change printing

Add `recordPrintingCorrection(for:to:resolved:pokemonPrintRun:)` mirroring the raw
variant-correction path. Validate the destination via catalog adapter first.
Move a whole claim, write two correction legs, merge with `checkedAdd`, retarget
all activity identity fields, set `.userCorrected` / `.userConfirmed`, append one
corrected activity, preserve existing destination artwork and stage new price.
Route one/multiple claims as in 4a and use the same Browse selection flow.

Cover two-leg lineage, existing-destination merge, undo across correction,
untouched sibling claims, rollback, empty integrity defects and repeated-tap
idempotence. Add evidence rows to the ownership-ledger completeness audit.

## Stage 5 — explicit pile Finish Lock suggestion

Track a per-game finish streak only after successful explicit nonduplicate choices
without an active lock. At three identical answers, suggest only a supported lock
option: “Scanning a pile of <finish>? Lock it” with Lock and dismiss. Accept uses
`setFinishLock`; dismiss suppresses that game/finish for the session. Reset streak
on different finish, dismissed choice, lock changes, cleared session or pending
scan invalidation. Keep the existing visible lock indicator. Record shown/accepted
metrics. Test mixed answers, duplicates, active locks, dismissal suppression and
next-card `.finishLock` provenance after accepting.

## Stage 6 — gated returning copies

Settings adds “Add returning copies automatically (experimental)”, default off.
Only `.spatialExit` evidence may bypass the prompt: consume it, revalidate using
the existing Add another checks, then commit with `.addAnother` authorization.
Failed revalidation falls back to the prompt. `.committedReplacement` and
`.needsAttention` always prompt. Successful automatic adds do not pause recognition.
The receipt carries “Another copy · now ×N” beside Undo. Track auto-duplicate
outcomes, commits and their session undos as a phantom-duplicate proxy.
Cover setting off, valid spatial exit without pause, replacement prompting and
undo restoring quantity. Device phantom-duplicate measurement governs enablement.

## Stage 7 and verification

Keep this plan, the documentation map, audit and dated progress entries current.
Before participant sessions, create `docs/experiments/bulk-intake-study-v1.md`
with supported-scope deck composition, counterbalanced app order,
time-to-accurate-collection definitions and frozen directional thresholds.

Use the external SSD if mounted (`ls /Volumes` first). Configure its mount path
locally; Stage 0 derived data lives under
`TradingCardScannerDerivedData/bulk-intake-stage-0/`. Run narrow `xcodebuild test`
selectors for each change. After Stages 1, 3 and 6, also run ownership completeness,
activity history, collection query and uncovered-surface tests. Run the full suite
once all stages finish, plus `git diff --check` and documentation link checks.

Use `scripts/ui_build_and_shoot.sh` for planned visual states; it uninstalls the
app, so first-launch screenshots represent a fresh installation. Add DEBUG routes
PortfolioEmpty and ScanSessionSummary. Device pause counts, lock interaction and
phantom duplicates remain owner evidence, never simulator acceptance claims.
