# App Review Fix Plan

## Progress

- [x] Fix tracker observation feed-forward and terminal request lifecycle — High confidence / High severity — verified
- [x] Propagate correction success/failure to the review sheet — High confidence / Significant production issue — verified
- [ ] Make `Same card` the visually prominent duplicate action — High confidence / Significant UX issue — in progress

## Baseline verification

The focused baseline passed 28 `CardLatchTests`. The full suite had three unrelated simulator Keychain failures in `ProductIdentityTests`; a later build was blocked by unavailable CoreSimulator runtimes during asset processing.

## Acceptance criteria

- Every successful seed and tracking observation becomes the request's next `inputObservation`.
- Terminal tracker paths mark the request as the last frame before release; continuity loss remains non-authorizing.
- A failed correction leaves the review sheet's local selection unchanged and exposes a concise failure note.
- `Same card` is first and prominent; `Add another` remains at least 44 points and secondary.
- Focused tests cover the tracker feed-forward assignment and existing collection safety regression remains green.

## Verification notes

### Tracker slice

- Status: Done pending commit
- Verification: `xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/CardLatchTests` — 29 tests passed.
- Coverage includes latest `inputObservation` assignment, terminal tracker behavior, and preservation of lost lineage across repeated invalidation.

### Correction slice

- Status: Done pending commit
- Verification: `xcodebuild test -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/BrowseCollectionTests/testVariantCorrectionWithMissingSourceDoesNotCreateAnUnbalancedPosition` — passed.
- The target compiled `ScanReviewSheet`, `ScannerViewModel`, and `CollectionStore`; only pre-existing Swift 6 warnings were emitted.
