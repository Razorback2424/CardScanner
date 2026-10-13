# Lorcana isolated UI review launch

**Status:** debug review launch implemented — 2026-10-12. Rendered phone/iPad,
large-text, VoiceOver and real-device acceptance remain open. This route uses
synthetic physical records and does not approve the real-card research corpus.

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

The launch intentionally has no pricing provider and cannot establish market,
physical finish, camera, production registration or shared-sync acceptance.
Source inspection checks native controls, Dynamic Type fonts, vertical sample
controls and 44-point minimum action height. Actual rendering and accessibility
interaction require the subsequent acceptance pass.

## Verification checkpoint

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
