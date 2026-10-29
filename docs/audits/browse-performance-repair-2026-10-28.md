# Browse entry and local search performance repair

**Status:** implemented; 42 focused native cases passed; optimized device build
installed and scoped entry/typing captured, 2026-10-28. Two recorded UI
microhangs keep full device hang acceptance open.

**Source identity:** `main`, `e92db193be32024304de5cf24cdc8017b69ed3f6`, plus
this working-tree patch. HEAD matches the supplied diagnosis. Existing changes
to the production-refinement master review, documentation audit and progress
log were preserved. No commit, push, merge or publication was performed.

## Findings and scope

The supplied source diagnosis is valid. `CatalogSetCardsView` synchronously
filtered, sorted and grouped on appearance and each relevant change. Number
comparisons reparsed both collector numbers; typing renormalized candidate
names/numbers and grouping rebuilt canonical-number identities. The small
bundled Destined Rivals fixture measured milliseconds, not a hang, so this
alone does not establish the cause of the reported device warnings.

The separate directory path had a scaling problem: the fallback for tiles,
Started and Most Complete walked all numbered collection rows for each set.
Completion preparation waited for every supported game's directory, while
those directories loaded serially. An unrelated delayed provider could keep
that fallback active. The synthetic differential measurement below isolates
this cost; it does not establish its frequency on the user's device.

## Repair

| Files | Change |
| --- | --- |
| `TradingCardScanner/Services/CatalogSetPresentation.swift` | Prepare immutable search text, number keys and grouping identities once per changed card snapshot. Cache number/price ordering, filter that ordering, cache identical presentations and ownership flags. Run projection on a per-route actor; cancel and reject obsolete publications. |
| `TradingCardScanner/Models/BrowseCatalogModels.swift` | Reuse prepared grouping identities. Prepare collector-number ownership buckets with each ownership snapshot, retaining game, print-run, provider-alias and canonical-number rules. Preserve exact physical-printing membership and unknown totals. |
| `TradingCardScanner/Services/CatalogSetCompletion.swift` | Cache complete directories per available game, merge only those supplied games, synchronously invalidate obsolete results, and guard access by ownership revision. |
| `TradingCardScanner/Views/BrowseView.swift` | Submit value-only requests, cancel on load/navigation changes, keep existing groups during replacement, prepare completion as directories arrive and use indexed fallback in rendering/filter/sort. |
| `TradingCardScannerTests/BrowsePresentationTests.swift`, `TradingCardScannerTests/BrowseFeatureTests.swift` | Fixed offline workload, cached/original projection equivalence, stale-result/cancellation gates, directory differential measurement, partial availability and completion freshness regressions. |
| `TradingCardScanner.xcodeproj/project.pbxproj` | Register the focused implementation/test files. |

Search text remains an immediate native binding with no added debounce.
Directory/provider concurrency and remote search pacing are unchanged. The
existing image decoder/download protections, price batching, background
writers and catalog authority remain. No schema or History/portfolio/scanner
implementation changes were made.

A route retains preparation while its view state survives temporary
disappearance. A newly pushed route prepares its immutable snapshot once;
there is no new global card cache. Per-game completion remains app-scoped.

The existing performance signposter now separates `Browse.directory`,
`Browse.completionReady`, `Browse.cardsPublished`, `Browse.prepare`,
`Browse.project`, `Browse.presentationPublished`, `Browse.typing` and
`Browse.firstUsable`. First-usable intervals distinguish display from canceled
entry. Search metadata records length, never the typed text. These are trace
boundaries; publication is not a measurement of delivered display frames.

## Measurements

Same bundled **415 standard slots**, empty ownership, number ascending, fixed
sequence: empty twice; `c`, `cy`, `cyn`, `cynt`, `cynth`, `cynthia`; clear;
`c`; clear twice. The test uses an isolated temporary checklist directory and
does not clear app data or user caches. Cold means the first projection in
this process, not a reboot or emptied OS cache. These are single-run samples.

Both runs use iPhone 17 / iOS 27.0 Simulator, the ProfileLocal scheme,
`ReleaseLocal` optimization (`-O`, whole-module), `ENABLE_TESTABILITY=YES`, and
the existing `DEBUG LOCAL_ONLY_SIGNING` fixture seams. Plain ReleaseLocal
cannot compile the existing test target because its tests reference
DEBUG-only helpers; that initial build failed before executing tests. The
optimized baseline subsequently passed. The MCP response timed out during
compilation, but its finalized xcresult was independently recovered.

| Stage | Before | After |
| --- | ---: | ---: |
| Bundled directory/manifest access | 41.22 ms | 14.57 ms |
| Bundled checklist access/publication input | 6.05 ms | 4.54 ms |
| Empty-owner directory completion readiness | 3.35 ms | 1.50 ms |
| First empty-query projection | 4.49 ms | 2.54 ms |
| Second identical empty-query projection | 1.78 ms | 0.012 ms |
| Typing projection median | 1.73 ms | 0.246 ms |

Directory/checklist timings include process and filesystem warmth differences;
the final workload follows other selected tests. Their differences are not
attributed to this patch. The isolated per-route projection actor starts empty
in both workloads. This is a projection comparison, not an end-to-end navigation
or rendered-frame speedup claim.

The baseline performs 12 sort passes and canonical grouping-metadata passes
for these 12 requests. The repaired ascending workload prepares number keys
and grouping identities once (415 number keys and 415 grouping identities,
plus 830 normalized candidate strings), with one ascending sort, zero price
sorts and ten projections for the twelve requests. Identical successive
inputs reuse the whole result. Variant grouping still reflects the
currently filtered slots, preserving ownership and finish behavior.

Directory differential fixture: 2,000 synthetic positive ownership rows and
60 sets, including repeated collector numbers/finishes and an unknown total.
The reference freezes the original fallback rules. It visits 120,000 rows;
the prepared lookup visits no collection rows after ownership preparation.
The original-rule reference took **5,709.13 ms** for one directory pass;
prepared lookup took **0.460 ms**, after **105.44 ms** to build the complete
ownership index. Preparation includes all existing ownership indexes as well
as the new buckets, and runs on the existing collection projection actor in
production. This synthetic input demonstrates the scaling cost; it is not a
timing of the user's real collection. Number-bucket memory is the tradeoff.

## Verification and remaining limits

The focused optimized run passed **37 tests, zero failures/skips**. The finalized
xcresult has no runtime warnings; this is not a device hang-detector capture.
Coverage includes:

- Empty entry, rapid typing/clearing and reuse of unchanged metadata/order;
  five-game equivalence with the original query/grouping behavior across
  ownership, tier and all number/price sorts, including unknown prices.
- Same-count catalog replacement and changed prices/ownership; gated obsolete
  results that deliberately ignore cancellation; disappearance and reopening.
- Pokémon normal/reverse/expanded grouping, collector-number suffixes,
  print runs, import aliases, cross-game isolation and unknown totals.
- Completion while an unrelated directory is delayed, then fails, then
  recovers; reuse of Pokémon checklist preparation on another game's arrival;
  stale ownership/catalog invalidation, manifest refresh and bounded overflow.
- Existing catalog selection/Undo, exact progress, Magic singleton/collision
  grouping, Started and Most Complete semantics.
- Four existing hosted set-view cases: navigation from the inactive collection
  tab, pagination, loading/search-field scroll origin and return to top, and
  cancel/resume of prices across disappearance. These confirm the rendered
  layout/interaction invariants, not screenshot or physical touch acceptance.

Five additional existing shared-ownership checks passed without another build
because the prepared ownership buckets affect stamped-release exclusion,
Magic suffixes and One Piece/Lorcana exact physical membership. Total final
verification: **42 passed, zero failures/skips** across the two selections.
Both finalized summaries contain no runtime warnings. Existing unrelated
compiler warnings remain; no new warning was reported in the changed files.

Evidence is stored outside the repository under
`/Volumes/T7/CodexBuild/TradingCardScanner-BrowseRepairEvidence/`:
`browse-before.xcresult`, `browse-after.xcresult`, `browse-after.log`,
`browse-shared-ownership.xcresult`, `browse-shared-ownership.log`, and
`tested-source-sha256.txt`.
DerivedData is in the sibling `TradingCardScanner-BrowseRepair` directory.

The phone required unlocking during the initial fixture pass. The physical
follow-up below supersedes that installation/capture limitation. Fixture
timings still do not establish live directory latency, delivered frames or
touch latency. No whole-app, provider, CloudKit, archive or release acceptance
is claimed.

## Physical-device follow-up — 2026-10-28

Built and installed the same source patch on an **iPhone 15 Pro Max / iOS
27.0.1 (24A446)**. This is the normal signed ProfileLocal / ReleaseLocal build
(`-O`, whole-module, `LOCAL_ONLY_SIGNING`), with no DEBUG fixture flags.
The source hashes match the repair tested above; the app executable and dSYM
UUIDs match. No application source changed during this follow-up.

The existing app was updated in place. No uninstall, erase, fixture seeding,
collection-edit action or cache-clear command was used. File metadata alone was
recorded to check preservation: immediately after installation, all **616**
existing cache entries and **174** Application Support entries remained.
After ordinary browsing, all 174 support entries remained; the cache had 647
entries, including 489 of the original entries and 158 new entries. Turnover
was confined to artwork and system HTTP cache files. The existing 60 MiB
artwork-cache trim policy is unchanged; artwork data measured 59.82 MiB before
and 59.74 MiB after verification. This is ordinary cache use/eviction, not
an artificially emptied cold-cache case. No collection contents were exported.

XcodeBuildMCP exposed only simulator controls, so this follow-up used Apple's
`xcodebuild`, `devicectl`, `xctrace` and Device Hub. Instruments could not resolve
attach targets by PID or name; recording by launching the installed bundle
succeeded. The first trace lasted **160.51 seconds**, using Time Profiler,
os_signpost and Hangs with the **250 ms** reporting threshold. Its exact flow
was Collection → Browse → Pokémon → Sets, directory scrolling/search to locate
Destined Rivals, first empty card query, incremental/rapid `cynthia`, clear,
another rapid `cynthia`, clear, Back and reopen. Device Hub forwarded keyboard
input and provided screen observations.

| Device measurement | Result |
| --- | ---: |
| First set-view appearance → `Browse.firstUsable`, displayed | 131.00 ms |
| Back/reopen → same marker | 120.63 ms |
| First nonempty-snapshot preparation | 1.93 ms, background |
| First nonempty-snapshot query/group projection | 2.66 ms, background |
| Ten recorded nonempty typing projections | 0.236–0.843 ms; median 0.334 ms |
| Two clear-query projections | 0.967 / 0.961 ms |

The first-usable marker ends when the view observes its first groups. It is
not tap-to-display latency or proof every image has decoded. All recorded
`Browse.project` intervals ran off the main thread. Rapid edits coalesced;
these are recorded projection durations, not a claim of one sample per key.
Two nonempty snapshot preparations correspond to the two separate pushed set
routes; each also prepared its initial empty state. Typing reused preparation.

**Residual stalls:** Hangs recorded **two microhangs**, neither overlapping
the set-entry intervals. At trace time 77.998 s, **260.16 ms** occurred before
Destined Rivals opened, during directory search/keyboard setup. At 129.454 s,
**334.45 ms** occurred about 1.25 seconds after the rapid typing publications.
The first window has 137 sampled main-thread stacks, 96 including UIKit's
keyboard-focus readiness helper. The second has 228 sampled stacks, 97 including
scene snapshot-context creation and 127 including SwiftUI rendering. These are
inclusive, overlapping stack counts, not additive CPU percentages. The trace
was symbolicated with the installed build's matching dSYM. No query/preparation
interval overlaps either stall. Snapshotting and rendering in this mirrored
workflow require further isolation; the evidence does not establish that
automation alone caused the stalls or that ordinary hand typing is hang-free.

A second **120-second** capture verified repeat entry at **132.15 ms** and
recorded no microhangs. It includes directory loading and keyboard focus, but
**zero card-typing events**: Device Hub kept the software keyboard suppressed,
so the intended on-screen typing follow-up could not be executed through that
interface. It is not counted as a clean typing run. Available-game directory
spans were 6.38–31.92 ms; the substantial completion build took 664.83 ms on
a background thread, starting before the unrelated directories finished.

Rendered observations confirmed empty entry, matching card names, unchanged
progress/finish rows, clearing and Back/reopen. A final normal launch outside
Instruments verified `cynthia` matches, adding the final `z` produces “No
matching cards”, and clearing restores the set. The app is left open on the
full set with Device Hub keyboard capture restored off.

**Outcome:** deployment and scoped interaction verification complete; fast
local projection confirmed on this device, but full hang-free acceptance
remains open because of the two recorded UI stalls and the unmirrored typing
limit. No pre-patch device capture was made, so no device speedup is claimed.

Device evidence is external under
`/Volumes/T7/CodexBuild/TradingCardScanner-BrowseDeviceEvidence/`: signed build
log/result, install/launch results, before/after container metadata,
`entry-typing-symbolicated.trace`, the original launch trace,
`onscreen-typing-launched.trace` (entry/focus only), XML table exports,
`device-verification-summary.json`, recording options and installed source/
executable hashes. Raw device metadata and traces remain outside the repository.

## Keyboard and snapshot remediation — 2026-10-28

Further main-thread review found redundant screen-state updates: both card
screens observed their complete global scroll rectangle even on iOS 18+, where
pagination already uses scroll visibility and never consumes that rectangle.
The version-scoped `CatalogPaginationViewport` now installs that observation
only for the iOS 17 fallback. Keyboard/snapshot geometry changes therefore no
longer write an unused rectangle into the whole card screen on newer systems.
The native search field also reserves its 44-point clear target while empty;
typing the first character no longer resizes the text input. The empty clear
control is disabled and hidden from accessibility.

The signed optimized layout patch was installed in place. The owner performed
on-screen typing with Device Hub mirroring/capture off and reported **“Done —
felt smooth.”** The 73.92-second trace captured **29** query projections,
**0.205–0.856 ms**, median **0.244 ms**, all off-main. No detected hang overlapped
the recorded focus/typing window. It also recorded **478.61 ms** in initial
app/Collection layout and **451.16 ms** in a subsequent background snapshot.
There were no exported set-entry intervals in this capture, so no new entry
latency is claimed. These results do not establish a whole-app improvement.

The background stall reproduced without mirroring. Its stacks include UIKit
scene snapshot trait/layout overrides and keyboard reloads; the last recorded
search focus remained active. This is not evidence of an actor-query stall or
an automation-only problem. A follow-up now ends native search focus on
`UIApplication.willResignActiveNotification`, before background snapshotting,
while retaining the query. Returning to the app leaves the keyboard dismissed;
the user can tap the search field to continue. Focus/scene signposts record
state only, never query text.

The first layout regression selection passed **14 tests** (nine hosted Browse
cases and five presentation cases). A new hosted regression verifies unchanged
input width after typing, focus dismissal on resign-active, and retained query.
The final optimized selection passed **15 tests**, zero failures/skips, with no
finalized runtime warnings. This includes the new focus/width/query test. The
device app compiled successfully through linking, but signing waited on a
macOS Keychain prompt. That build was later interrupted to include the
[Classic artwork repair](classic-collection-artwork-repair-2026-10-28.md); the
combined device build completed after the owner handled the protected signing
prompt and was installed in place. Both layout and focus-cleanup changes are
now on the phone. The direct-on-phone background-snapshot comparison remains
pending; full hang-free acceptance remains open.

HIG design gate **PASS** for platform patterns, clarity, typography,
accessibility, interaction cost and design consistency. Navigation is unchanged;
the search remains a native text field with a labeled 44-point clear target and
Dynamic Type. The explicit tradeoff is dismissed keyboard focus after app
deactivation, with query retention. No further UI fix was identified by this gate.

Evidence stays outside the repository in the same T7 directories:
`keyboard-layout-build.xcresult`, `keyboard-layout-hand-typing.trace`, its XML/
summary/source-hash files, `keyboard-layout-tests.xcresult`,
`search-focus-tests.xcresult` and their finalized summaries.
`search-focus-build.log` records the signing wait. The unchanged
collection/cache policies remain in force; no reset or cache clearing was used.

## Separate next work

- Measure the [History projection (P06)](production-refinement-master-review-2026-10-26.md#p06-activity-history-main-actor-projection).
- Reproduce the [first-baseline same-count correctness gap (M08)](production-refinement-master-review-2026-10-26.md#m08-first-revision-baseline-can-accept-an-older-same-count-projection).
- Complete the focus-cleanup snapshot comparison and isolate initial
  app/Collection layout separately from Browse query work.
