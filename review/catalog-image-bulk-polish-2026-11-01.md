# Bounded catalog-image and bulk-observation polish

**Date:** 2026-11-01 UTC. **Status:** verified local candidate; unpublished.
**Base:** current remote `main`, `0ab3b0e6c59bb8561f3ee4610bccd0f311bb716b`.
**Source candidate:** `3ca908d44c4a6b1689cf63c509d867d83f56764e`.
**Branch:** `polish/catalog-image-bulk-refresh-2026-11-01`.

Pricing PR #14 remains separate and open at
`ce17ea0acb8999bbdfb754a1c7b4f1145edf96ba`; its checkout was clean and left
untouched. The Mac had no competing native build or render process before this
pass. Build artifacts use the external T7 SSD.

## Reviewed plan and scope

1. Give successfully displayed artwork an identity independent of the cancellable
   pending request. Reappearance can reuse the exact completed derivative;
   interrupted loads restart, upgrades retain an older usable derivative, and
   source/reload changes still clear unrelated artwork. Keep cancellation and
   generation checks ahead of completion publication.
2. Bypass ordinary debounce only while a completed bulk generation remains
   unprocessed. Acknowledge it after a current, uncancelled apply has committed
   the same fingerprint. Preserve ordinary save/remote coalescing, active bulk
   checks, storage tokens, apply generations and pending fallback retry behavior.
3. Reproduce before fixing; run focused lifecycle/scheduling tests, then the
   relevant native aggregate. Prepare separate local commits and a local draft
   PR body. No public PR or body publication is part of this pass.

No cache-limit, provider, image-format, custom-photo, accessibility, history,
legal-URL or asset changes are included.

## Before and after

| Boundary | Before | Candidate |
| --- | --- | --- |
| Completed artwork disappears/reappears | Cancellation removed the source identity used by the view; reloading cleared the retained image and fetched again. | Displayed identity survives cancellation; the exact completed derivative remains usable without another fetch. |
| Cancelled image/size work | An interrupted size upgrade could clear the previous derivative on restart. | Pending work restarts while the completed derivative stays visible; cancelled/superseded completions cannot publish. |
| Outermost bulk completion | The settled generation still entered the ordinary 300 ms debounce. | Its pending observation skips debounce; later ordinary saves and remote changes still enter it. |

Image source/tests are isolated in commit `d58e618`. Monitor source/tests are
isolated in commit `3ca908d`.

## Verification

- Deterministic baseline: three selected tests failed with eight expected
  assertions, zero skips. They reproduced completed-artwork identity loss,
  redundant fetch, cancelled-upgrade image loss and completed bulk work blocked
  by the injected debounce gate. An earlier test-helper actor-isolation compile
  error was corrected before this baseline ran.
- Final focused native selection: **17 passed, zero failed, zero skipped**.
  Six image tests cover completed reappearance, real SwiftUI disappearance and
  remounting, interrupted restart, requested-size upgrades, source/reload-token
  switches, fallback behavior and stale completions. Eleven monitor tests cover
  nested intervals, a new bulk interval during suspended observation, cancelled
  observation, ordinary save/remote bursts, one settled projection/revision,
  foreground eligibility and ownership replay during active price refresh both
  with and without a new nested bulk interval.
- The first post-fix focused run passed all image tests; two monitor assertions
  incorrectly counted later ordinary-save observations as the bulk observation.
  The final tests instead prove bulk publication while ordinary debounce remains
  blocked. The production debounce stayed at 300 ms throughout.
- Relevant aggregate native selection: **350 executed, 349 passed, zero failed,
  one skipped**. The existing `PortfolioReconciliationTests.testAgedStoreBaseline`
  requires the opt-in `PERF_BASELINE=1`. Selection includes Browse features,
  loading, collection, pagination rendering and presentation; store revision,
  bounded caches, queries/digests, portfolio reconciliation, refresh lifecycle
  and structural writes, CSV resume, launch model actors and app opening.
- `git diff --check`: passed.

Toolchain: Xcode 27.1 (`27A9275`), Debug, iOS 27.0 iPhone 17 Pro simulator,
`CODE_SIGNING_ALLOWED=NO`, serial testing.

Local result bundles:

- `/Volumes/T7/ScanStash-Polish-before-retry.xcresult`
- `/Volumes/T7/ScanStash-Polish-focused-final.xcresult`
- `/Volumes/T7/ScanStash-Polish-aggregate.xcresult`

Native counts above come from the completed `xcodebuild` test logs. Structured
`xcresulttool` summary extraction encountered a local Library/Caches write error;
the result bundles and complete logs remain available. Logs are retained locally
at `/tmp/scanstash-polish-before-retry.log`,
`/tmp/scanstash-polish-focused-final.log` and
`/tmp/scanstash-polish-aggregate.log`; raw logs are not committed.

## Evidence limits

The image tests mount actual SwiftUI views in UIKit and assert lifecycle and
loader state with synthetic artwork. They are not a manual visual/device pass.
The monitor tests use disposable in-memory stores and controlled async gates.
They establish behavior and safeguard coverage, not a measured user-visible
300 ms improvement. No physical-device, camera, live-provider, CloudKit,
distribution or release certification follows from this simulator evidence.
