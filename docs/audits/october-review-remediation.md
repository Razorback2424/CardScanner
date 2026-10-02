# October review remediation

**Status:** slices 1–10 committed and focused simulator checks passed; full suite retains centering failures; manual export acceptance and physical-device measurements pending — 2026-10-02.

Branch: `fix/october-review-boundaries`, based on `cdd60e1`. The approved review
contains eleven findings. The implementation preserves the inventory ledger,
fresh-context serialized writes, conservative identity matching, and explicit
ownership confirmation. Already-merged historical holdings are not split.

## Implementation slices

| Slice | Finding | Result |
| --- | --- | --- |
| 1 | F5, checked grade parsing | `4e593d3`: reject nonfinite and unrepresentable integral grades; malformed CSV rows remain visible among skipped rows. |
| 2 | F4, export ownership | `80a5e82`: the export service no longer deletes another owner's container; single and batch view cleanup remains authoritative. The Photos-save exemption cleans up after the save finishes. |
| 3 | F3, durable backlog | `67b888d`: remove all four 50-row truncations. Needs attention uses a lazy `List`; counts remain unrestricted. |
| 4 | F1, graded print-run identity | `6777a43`: namespace known Pokémon runs in graded keys and CSV fallback keys; legacy fallback requires a matching stored run. Preserve certificate-proven backfill and require run equality in price-identity preflight. Correction and restore already preserve graded keys. |
| 5 | F2, interrupted recognition | `cdc2de3`: file queued, active, and pending-choice work before invalidation; exclude authorized requests. Persist interrupted duplicate prompts as additional-copy requests and require a fresh explicit confirmation on retry, including after lookup on relaunch. Explicit dismissal and Price Check retain cancellation semantics. |
| 6 | F6, Browse selections | `6f9ae5b`: fetch replacement directories before swapping, retain valid selections, and preserve the old directory and selection for failed games. |
| 7 | F7, stable destinations | `109889d`: filtered entries fall back to the priced unfiltered snapshot with shared diagnostic logic. Missing-card copy now describes removal. |
| 8 | F8, catalog activation retry | `0eafc57`: retain HTTP validators after decode and clear them after rejected activation or verification, in both games. |
| 9 | F10, artwork errors/cache | `859b006`: fresh filenames preserve cached derivatives; failed transfer/preparation shows a generation-guarded error. Normalization remains synchronous pending measurements. |
| 10 | F11, text scaling | `248a61d`: scale tile name, identity, minimum height, and detail title; use semantic provenance text and allow essential tile text to wrap at accessibility sizes. |
| 11 | Physical-device measurement | Pending: no connected physical device was available. |
| 12 | F9 / normalization / actor placement | Deferred until slice 11 supplies evidence; no speculative executor changes. |

## Simulator evidence

Xcode 26.6, iOS 26.5, iPhone 17 Pro simulator. DerivedData and package caches
use the mounted external drive. The global SwiftPM cache symlink needed its
external mount name corrected before dependency resolution could succeed.

| Selection | Result |
| --- | --- |
| Slice 1: `ImportedItemKindTests` | 14 passed. |
| Slices 2–3: export, unresolved store, 55-row model reload | 17 passed. |
| Slice 4: `CollectionItemKindTests`, `ImportedItemKindTests` | 40 passed. |
| Slice 4 full suite | 1,732 tests; 7 skipped; 25 assertion failures across 10 centering cases. |
| Final working-tree build for testing | Passed, including slices 5–10. |
| Slices 5–10 focused selection | 124 passed, zero failures: scanner 82, unresolved store 10, Browse update 1, destination/deletion 2, Pokémon client/coordinator 14, Magic activation 4, artwork/render plan 11. |
| Full suite after slice 5, including slices 6–10 | 1,743 tests; 7 skipped; 25 failures across the same 10 centering cases. No other test cases failed. Completed 2026-10-01 against the binaries committed through `248a61d`. |

The full-run failures were in `CardCenteringInvariantTests` (rotation, mirror,
quarter-turn, scale, crop, latency, and automatic-inner confirmation),
`CenteringExportTests.testOnScreenGuidesRotateWithInjectedGeometry`, and two
`CenteringProfileDumpTests` cases. The run is not a release certification and
does not establish a new passing centering baseline. Concurrent compilation
during part of the run also limits interpretation of its latency assertion.
Raw logs and result bundles remain local; no screenshots or private simulator
data are committed.

Both complete runs failed; neither is presented as a passing baseline. The
second run took about 19 minutes and used no concurrent compilation. Its
simulator latency failure still cannot establish physical-device performance.

The focused follow-up and screenshots used a task-created simulator, preserving
the existing simulators' app data. Low internal disk space required recovery of
task-owned simulator data; build products and result bundles remained external.
After macOS file coordination blocked reopening the Xcode project, testing used
the successful build's `.xctestrun` with `test-without-building`. The screenshot
script accepts an explicit `UI_PREBUILT_APP_PATH` for this same tested app.

## Visual verification and remaining manual checks

Inspected synthetic `CollectionTilesLongContent` and `TrustCardDetail` routes at
default Large and Accessibility Extra Extra Extra Large. In dark appearance,
tile name/identity and detail title/provenance scale and wrap without overlap or
truncation. Default-size hierarchy remains intact. Navigation and the tab bar
remain available. Screenshots and the checklist are local ignored artifacts.

HIG verdict: **RISK** for the wider screens, with no observed regression in the
changed essential text. Existing issues remain: the black detail backdrop has
poor text contrast in light appearance; collection toolbar icons crowd the
header at the largest text size; the tile finish label truncates at that size.
The minimal follow-up is to align detail content colors with its backdrop and
adapt the collection toolbar and finish row at accessibility sizes. This slice
does not claim full-screen accessibility acceptance or VoiceOver/device testing.

| HIG category | Scoped review |
| --- | --- |
| Platform patterns | PASS: existing system navigation and actions remain; toolbar crowding is the broader follow-up above. |
| Clarity | PASS: title and provenance retain their hierarchy and wrap vertically. |
| Typography | RISK: changed essential text scales; wider finish-row truncation remains. |
| Accessibility | RISK: scoped dark captures pass; light contrast and VoiceOver/device acceptance remain open. |
| Interaction cost | PASS: text scaling adds no action or prompt. |
| App Review design | RISK: resolve the observed contrast/chrome issues before claiming full-screen design acceptance. |

Browse filter retention and open-detail price updates/removal have deterministic
test coverage. Interrupted intake, authorized writes, explicit dismissals,
purpose/mode switches, Price Check, and duplicate recovery have focused coverage.
Two exporter calls preserve the first files and ZIP. The complete interactive
single → batch → single preview/share/Photos-save exercise reached the system
photo picker with four synthetic fixtures, then stopped because native UI
control reported the Mac was locked and could not continue. This acceptance
check remains pending; unit evidence does not establish system share/save
behavior. The physical stack/throttled-lookup exercise also remains a device
check rather than a simulator-camera claim.

## Measurement gate

Use `TradingCardScanner-ProfileLocal` on the oldest supported physical device
with a synthetic collection of about 1,500 cards. Record device model, OS,
commit, trace template, workload, and repetitions. The device listing showed
only offline iPhone/iPad devices; no trace was captured and no duration or
thread-placement result is claimed.

| Workload | Evidence to capture |
| --- | --- |
| Collection first paint | Launch-to-first-real-row duration; `makeCachedProjection` interval; thread placement of `CollectionProjectionActor`. |
| Portfolio recompute | `portfolio.recompute` / computation intervals, main-thread versus actor work, persistence cost. |
| CSV import | Thread placement and elapsed decode/apply/write work with sibling malformed rows. |
| Centering export | Main-thread render, PNG encode, and file-write durations inside `makeExportFile`. |
| Artwork import | Transfer versus downsample/PNG normalization versus serialized database write. |
| Intake and price refresh | Revision-monitoring fetch stacks, `storeRevision.priceSnapshotRebuild`, `storeRevision.projectionRebuild`, frequency and cost. |

Only measured hitches justify detached immutable centering/artwork work or
creating a specific expensive actor away from main. Generation checks,
`CollectionWriteSerializer`, and ownership confirmation remain mandatory.
The current device agenda remains in [release follow-ups](../plans/release_followups.md).
