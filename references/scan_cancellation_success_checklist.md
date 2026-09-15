Target screen:
- Route name: ScanChoiceCancellation
- Expected device: PA Quality iPhone 17 Pro

Status: deterministic simulator route verified — 2026-09-14. This checklist
records the cancellation contract; physical-camera performance remains a
separate release gate.

Visual checklist (must verify against `./artifacts/ui-latest.png`):
1. [x] Scanner chrome renders without a finish-choice card after cancellation
2. [x] The cancelled scan does not leave a “Saving to your collection…” card or spinner
3. [x] No collection receipt is shown for the cancelled scan
4. [x] Top controls and safe-area layout remain intact

Behavior checklist (verify via deterministic state or UI test):
1. [x] Cancelling the variant choice leaves the collection unchanged
2. [x] Recognition is resumed after the choice is cancelled

Evidence: the 2026-09-14 scanning-workflow verification recorded the clean
`ScanChoiceCancellation` state and the focused cancellation regressions. The
latest full simulator run remains non-clean only in unrelated suites; see
[`docs/plans/release_followups.md`](../docs/plans/release_followups.md).
