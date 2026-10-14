# Lorcana isolated UI review launch

**Status:** bounded rendered simulator acceptance passed — 2026-10-13.
Phone/iPad printing and finish flows, large-text scrolling and local ownership
were exercised with synthetic physical records. VoiceOver interaction,
real-device/camera and real-card corpus acceptance remain open.

## Launch

Build and run the `TradingCardScanner-DebugRemoteLocal` scheme. Add these launch
arguments in Xcode's Run configuration:

```text
-ui_debug_route LorcanaReview -ui_debug_state size
```

The route is compiled only with `DEBUG && LOCAL_ONLY_SIGNING`. A normal launch
continues to use the ordinary runtime/storage configuration. The local profile
scheme's Run action uses `ReleaseLocal`, so use the DebugRemoteLocal scheme to
run this harness; the profile scheme's Test action can build its tests.

The route prepares only Lorcana, checks the actual isolated local model
container, then binds its catalog/recognizer/finish/Browse/import authority before
constructing the scanner. It creates an ephemeral signed synthetic seed without
network updates or a committed private key. The banner identifies synthetic cards
and a separate collection on every tab. The camera stays off: synthetic footer
text reaches the existing scanner callback, then actual catalog lookup, choice,
finish and collection-write code.

The chosen sample is injected once when the scanner first appears. Use the
sample menu and **Scan synthetic footer** to scan another independent encounter.
Finish or dismiss a pending choice before injecting again. Existing printing
Details, finish selection, scan undo/recovery, Collection → Browse, and collection
CSV import/export remain the interaction surfaces. No new ownership picker or
alternate save path is introduced.

| `-ui_debug_state` | Expected catalog boundary |
| --- | --- |
| `size` (default) | Two candidates with the same footer, standard and oversized; explicit printing selection. |
| `standard` | One standard printing; normal/foil finish choice. |
| `oversized` | One oversized printing; explicit size selection, foil only. |
| `stamp` | Two visible stamp distinctions; explicit printing selection. |
| `artworkUnavailable` | Different artwork UUIDs without usable images or visible distinctions; incomplete lookup. |
| `held` | Provisional printing and incomplete universe; incomplete lookup. |
| `landscape` | Standard-size landscape fixture; exact lookup without any camera-orientation claim. |
| `unknown` | Recognized complete footer absent from the catalog; incomplete recovery. |

All names and evidence references identify UI fixtures. Their deterministic UUIDs
allow relaunch/CSV testing within this workspace; never copy them to real physical
records. The [12-specimen acceptance batch](lorcana-real-card-corpus/minimum-acceptance/README.md)
and its 25 iOS scenarios retain their separate evidence requirements.

## Storage and review boundaries

Collection and portfolio stores, bootstrap metadata, unresolved scanner recovery
and signed-release cache are under `Application Support/LorcanaLocalReview/`.
Keep the launch route enabled to reopen that workspace. Removing the arguments
returns to the ordinary collection; no store is erased, copied or migrated by
the route. Writable binding rejects an unrelated on-disk container or a CloudKit
configuration. Ordinary preferences, such as sort order, remain app preferences.

The launch has no approved market mappings or provider I/O and cannot establish market,
physical finish, camera, production registration or shared-sync acceptance.
Source inspection checks native controls, Dynamic Type fonts, vertical sample
controls and 44-point minimum action height. Actual rendering and accessibility
interaction evidence is recorded below; spoken VoiceOver interaction remains open.

## Rendered acceptance checkpoint — 2026-10-13

Verified on `feat/lorcana-implementation`, base `8613a1d` plus local pricing and
UI fixes, using DebugRemoteLocal. Dedicated iPhone 17 Pro and iPad Pro 11-inch
M4 simulators both ran iOS 26.5. An initial iPad M5/iOS 27 capture was supplemental;
the repeatable tablet acceptance used the dedicated M4 simulator. Portrait
screens were inspected; the `landscape` sample describes card layout, not device
rotation. Shared simulator contention prompted isolated devices without erasing
ordinary collection data.

| Check | Rendered result |
| --- | --- |
| Eight fixtures on both devices | Size/stamp distinctions and standard/landscape finish choices are readable. Oversized-only still requires size evidence. Unknown, held and indistinguishable artwork remain incomplete, with retry and no ownership write. |
| Printing Details | Readable metadata and explicit size actions in the native sheet; selected standard and oversized identities reach the existing save flow. |
| Default light / accessibility dark | Mode/finish labels wrap; accessibility choices stack. Phone scrolling reaches both sizes and both finishes; tablet size actions fit directly. Tested accessibility-extra-large (AX3), not every text size. |
| Ownership | Standard → Foil saves; immediate scan Undo removes it. First iPad save updates Collection and Browse without relaunch. Browse detail explains missing artwork/unmapped price and its native finish picker adds Normal; immediate Browse Undo on phone removes only that new Normal copy. Relaunch retains one Foil copy. |
| Repeated encounter / recovery | Repeated same-session card is suppressed as already added. Unresolved Scans lists retained incomplete encounters and states that nothing was added. Phone recovery detail exposes retry/search/dismiss; Retry lookup returns the same incomplete result without adding ownership. |

The pass found and fixed white camera controls on the stopped white preview,
low-contrast Details text, truncated card titles and top controls, ambiguous
oversized-only labeling, inaccurate missing-card copy, and a first-save race
between launch projection and the revision monitor baseline. Camera chrome now
uses a black backing/dark appearance; titles wrap, accessibility controls stack
and scroll, size labeling is explicit, incomplete lookup copy is neutral, and an
existing stale launch projection is reconciled on the monitor's first observation.

**HIG gate:** PASS for inspected portrait printing/finish choices, readable
light/dark surfaces, tested Dynamic Type layout, native sheets, clear no-write
outcomes and descriptive action labels. RISK remains for spoken VoiceOver focus,
real camera backgrounds/orientation and physical-device behavior; those require
their own interaction evidence. No release or App Review certification is implied.

Final scoped regression: **204 passed, 0 failed, 0 skipped** in
`accessibility-final-tests.xcresult`, verified with `xcresulttool`. It covers
scanner, ownership, pricing, catalog activation/physical identity, rotation
contracts and revision monitoring. A QoS priority-inversion runtime warning was
recorded; no full-suite success or performance acceptance is claimed.

Evidence remains outside the repository on the external SSD at
`CodexBuilds/LorcanaUIAcceptance-20261013/`: `iphone-qa/final-states/`,
`ipad26/final-states/` (artwork uses `artworkUnavailable-recapture/`),
`iphone-qa/accessibility-dark-size/`, `ipad26/accessibility-dark-size/`,
`ipad26/final-size/details.png`, interaction captures and the success checklist.
Launch-transition frames and earlier finding captures are retained as historical
diagnostics, not accepted final renders. No private screenshots or simulator IDs
were added to the repository; no commit or push was made.

## Historical launch-contract checkpoint — 2026-10-12

At base `1e368b3` plus local changes, the DebugRemoteLocal app/test build passes.
The final three review-launch tests pass with zero failures/skips and no runtime
warnings in `review-final.xcresult`. They cover exact route opt-in, deterministic
synthetic identity, all eight lookup boundaries, isolated disk ownership across
fresh ephemeral keys and rejection of ordinary storage. The earlier regression
log records 62 selected ownership/activation/physical cases passing, but Xcode
stalled after test completion while finalizing that result bundle. That process
was stopped and its log retained; this is not a finalized 62-test result bundle.
The subsequent three-test run completed successfully and its bundle was verified
with `xcresulttool`. This is contract verification, not rendered or physical
acceptance.

Build, dependency and result artifacts are on the external SSD under
`CodexBuilds/LorcanaReviewLaunch-20261012/`. The XcodeBuildMCP build wrapper could
not consume its configured session defaults, so direct `xcodebuild` performed
verification. The first compile caught a missing synthetic rarity string; it was
fixed before the passing build. No simulator was erased, no source corpus was
activated, and no commit or push was made.
