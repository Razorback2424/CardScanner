# App Review Preflight

## Baseline

- Branch: `fix/app-review-preflight`
- Working tree contained pre-existing scanner, collection, UI, and test changes; unrelated files are intentionally preserved.
- Focused `CardLatchTests` baseline: 28 tests passed.
- Full test baseline: the scanner suite reached 504 tests; three existing `ProductIdentityTests` failed in the simulator Keychain environment and were outside this change.
- A subsequent source build reached Swift compilation but was blocked during asset catalog processing because CoreSimulator reported no available simulator runtimes.

## Findings in scope

The supplied review identifies three concrete, high-confidence production issues:

1. `CardScanner` does not feed each `VNDetectedObjectObservation` into `VNTrackObjectRequest.inputObservation`, so tracking does not continue from the latest observation.
2. `ScannerViewModel.correct` silently ignores a failed/missing-source correction while `ScanReviewSheet` has already changed its local picker state.
3. `DuplicateConfirmationBar` visually emphasizes the quantity-changing action instead of the safe no-mutation action.

These are implemented as minimal, local fixes with focused regression coverage. The supplied review also lists broader integration-test gaps; those remain follow-up coverage work unless directly exercised by the focused tests added here.
