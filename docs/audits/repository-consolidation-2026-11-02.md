# Repository consolidation — 2026-11-02

**Status:** PRs #19, #18 and #20 squash-merged into main. The exact final integration tree passed hosted CI and local native verification.

The owner authorized committing/pushing the centering repair, squash-merging
all open PRs and consolidating branches/worktrees into a clean main workspace.
The three active PRs are [#19](https://github.com/Razorback2424/CardScanner/pull/19),
[#18](https://github.com/Razorback2424/CardScanner/pull/18) and
[#20](https://github.com/Razorback2424/CardScanner/pull/20).

The final integration tree is `0367a3166078441dc1026bb6a540eb9bc065bce5`.
It is byte-for-byte identical to published PR #20 head `f623cf0` and includes
the final #19 (`cb3220c`) and #18 (`477c7e3`) changes. The verified main code checkpoint is `a6ac13d719a162cb514fbfd3b542f5fef308dd71`.

- PR #19 squash commit: `4df876c788eddc72b1d024b6877be9ddeaa98b18`.
- PR #18 squash commit: `6de35eef79d9f5c47eaddcfe57644e87f4500856`.
- PR #20 squash commit: `a6ac13d719a162cb514fbfd3b542f5fef308dd71`.

## Verification and repaired integration findings

| Final local verification | Passed | Failed | Expected skips |
| --- | ---: | ---: | ---: |
| Complete centering native class | 47 | 0 | 1 |
| Combined selected native regressions | 1,734 | 0 | 3 |
| Offline Python tests | 159 | 0 | 5 |

The selected native methods reconcile individually between stdout and the
finalized result bundle: no missing/duplicate methods, status conflicts,
unexpected skips, restarts, publication warnings or bundle runtime warnings.
The three native skips are the development-performance, aged-store and live
Pokémon price opt-ins. The five Python skips require the built Swift publisher.
The pinned Pokémon finish ledger/resource audit also passes.

The combined run first reproduced an inherited stale assertion that a newly
added sealed row lacked `catalogProviderID`. Production `addSealed` explicitly
stores the product ID. The corrected test verifies that current contract and
separately clears the field to prove the legacy `justTCGCardID` fallback. The
accessor comment was corrected; production behavior was not changed to fit a test.

Hosted [run 41465555836](https://github.com/Razorback2424/CardScanner/actions/runs/41465555836)
then exposed a later-session fixture sequencing error: B's owned Done/removal
checks passed, but immediate refocus coalesced SwiftUI blur/focus observations.
A blur-only adjustment failed locally when B's initial focus was itself still
unobserved. The final fixture establishes B's observed focus and Done blur
before requiring the later fresh focus. A's real removal completion stays held
through B's boundary. The original rapid-refocus regression and two-second
deadlines are unchanged. Failed and canceled earlier attempts remain retained.

Further hosted traces showed capture in about 34 ms followed by roughly
3.76 seconds in native resignation. Capture timing and actual native window
detachment are now recorded separately, with every pre-B state assertion kept.
The production scheduler still defers publication after resignation; this
diagnostic does not change writes or scheduling. Another focused cleanup
failure recorded every callback inside two seconds but observed them later.
Cleanup now uses the latest completion across all controls in their current
native lifetimes, recognizes already-completed removals still detaching, and
waits for native detachment before closing the trace. Missing/late completions
remain failures. Original editing/commit deadlines and job timeouts are unchanged.

Hosted traces also showed native detachment before the end-editing notification.
Readiness now requires both, matching native identity/removal, and uses their
latest timestamp without imposing an order. Routine fixture focus is an awaited
next-main-queue action so it does not enter an observation transaction; explicit
rapid-refocus and stale-focus tests still call the native responder directly.

The shared centering test file retains the verified Reset coverage from #18.
Historical Pokémon entries were relocated without changing their text, and CI
fetches the exact pinned baseline rather than full history. Native selections
and timeouts are unchanged. A local squash-order simulation verifies all three
merges are clean and yield the final integration tree without losing source or
evidence records.

Final hosted runs are [#19](https://github.com/Razorback2424/CardScanner/actions/runs/41486987398),
[#18](https://github.com/Razorback2424/CardScanner/actions/runs/41486993853) and
[#20](https://github.com/Razorback2424/CardScanner/actions/runs/41486995888).
PR #20 passed the full 1,737-method final integration selection: 1,734 passed,
three expected skips and zero failures. Its Git tree is identical to the merged
main code checkpoint. At the owner's request to finish consolidation, the merges
used this completed hosted integration run and reconciled local native evidence.
The extra #19 bounded comparisons and #18 infrastructure rerun were still pending
at merge time; they are not claimed as green or waived failures. No branch
protection or required-check bypass was used.

The first #18 attempt at final head `477c7e3` remains failed: its finalized
bundle reports 1,536 passed, one SIGTERM termination and two skipped methods.
Retained diagnostics show Apple's `SimLaunchHost.arm64` crashing with SIGBUS /
`KERN_MEMORY_ERROR`, CoreSimulator losing that service connection, simulator
state 1 during the subsequent 120-second boot wait, and XCTest reporting
SIGTERM afterward. Other simulator services terminated at the same time.
This explains this attempt's interrupted execution; it is distinct from the
earlier allocator abort whose underlying trigger remains unidentified. One
failed-job rerun on a fresh hosted runner was requested without app changes,
weaker assertions or extended deadlines. Its full completion is required.

## Work preservation and cleanup

All worktrees were inspected before removal; none contained uncommitted source
changes. The older final combined worktree was identical to starting main
`4a9d70b`. Older feature-branch merge simulations added no application code;
their remaining differences were historical progress and workflow reconciliation.
The old stash's nine added test methods are already present. Its remaining
source alternatives are superseded by newer boundary/tracker behavior.

Recovery bundles, worktree inventories, exact source identities, native result
bundles, raw logs and per-method receipts are retained on the external SSD in
`CodexBuilds/CardScanner-Consolidation-20261102` and the companion
`CardScanner-PR19-Removal-20261102` evidence directory. Raw logs, private local
settings and generated artifacts are not added to the repository. The main
workspace's ignored settings/archive files are preserved.

This verifies the selected simulator/component and offline regression scope.
It does not certify physical-device, keyboard-toolbar tapping, VoiceOver,
provider, CloudKit, archive, distribution or release readiness. Existing release
gates remain open.
