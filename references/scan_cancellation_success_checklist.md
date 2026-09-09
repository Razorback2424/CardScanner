Target screen:
- Route name: ScanChoiceCancellation
- Expected device: PA Quality iPhone 17 Pro

Visual checklist (must verify against `./artifacts/ui-latest.png`):
1. [ ] Scanner chrome renders without a finish-choice card after cancellation
2. [ ] The cancelled scan does not leave a “Saving to your collection…” card or spinner
3. [ ] No collection receipt is shown for the cancelled scan
4. [ ] Top controls and safe-area layout remain intact

Behavior checklist (verify via deterministic state or UI test):
1. [ ] Cancelling the variant choice leaves the collection unchanged
2. [ ] Recognition is resumed after the choice is cancelled
