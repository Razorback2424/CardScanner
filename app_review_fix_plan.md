# App Review Fix Plan

## Progress

- [x] Fix tracker observation feed-forward and terminal request lifecycle — High confidence / High severity — verified
- [x] Propagate correction success/failure to the review sheet — High confidence / Significant production issue — verified
- [x] Make `Same card` the visually prominent duplicate action — High confidence / Significant UX issue — verified

All three supplied findings are implemented and verified on `fix/app-review-preflight`.

## New attached review slice

- [x] Make the held-card “Already added” offer actionable for stacked duplicates — High confidence / explicit user-authorized quantity path — implemented

Evidence: the supplied specification identifies the existing eight-match latch-hold signal as reliable while Vision spatial exit can be ambiguous for aligned identical cards. Acceptance requires a one-shot, identity-bound authorization that cannot be created by OCR, weak absence, timeout, tracker loss, or a different card.

Rollback: revert the held-offer/authorization commit(s); the existing spatial-proof duplicate flow remains the fallback.

## Baseline verification

The focused baseline passed 28 `CardLatchTests`. The full suite had three unrelated simulator Keychain failures in `ProductIdentityTests`; a later build was blocked by unavailable CoreSimulator runtimes during asset processing.

## Acceptance criteria

- Every successful seed and tracking observation becomes the request's next `inputObservation`.
- Terminal tracker paths mark the request as the last frame before release; continuity loss remains non-authorizing.
- A failed correction leaves the review sheet's local selection unchanged and exposes a concise failure note.
- `Same card` is first and prominent; `Add another` remains at least 44 points and secondary.
- Focused tests cover the tracker feed-forward assignment and existing collection safety regression remains green.
- The held-card fallback is nonblocking, Collection-only, one-shot per held presentation, and dismissed by a different card, spatial proof, undo/delete, purpose/lifecycle invalidation, or session end.
- A held-repeat authorization is verified on the Vision queue, expires before encounter consumption, carries through resolution, and bypasses duplicate interception only after matching committed history and canonical identity validation.

## Verification notes

### Tracker slice — `6a53aa6`

- Status: Done
- Verification: `xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/CardLatchTests` — 29 tests passed.
- Coverage includes latest `inputObservation` assignment, terminal tracker behavior, and preservation of lost lineage across repeated invalidation.

### Correction slice — `c6d08b5`

- Status: Done
- Verification: `xcodebuild test -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/BrowseCollectionTests/testVariantCorrectionWithMissingSourceDoesNotCreateAnUnbalancedPosition` — passed.
- The target compiled `ScanReviewSheet`, `ScannerViewModel`, and `CollectionStore`; only pre-existing Swift 6 warnings were emitted.

### Duplicate-action hierarchy — `02ce8d1`

- Status: Done
- Verification: source inspection confirms `Same card` remains first, uses `.borderedProminent`, and retains a 48-point minimum height; `Add another` uses `.bordered` with the same minimum height and remains secondary in VoiceOver sort order. The focused `CardLatchTests` command also exited successfully after this UI-only change.

### Final verification

- `xcodebuild test -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device` — 506 passed, 0 failed, 0 skipped.
- `git diff --check` — clean for the working-tree changes; each fix commit also passed its staged diff check.

### Held-card fallback slice

- Status: Implemented
- `xcodebuild build -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/trading-card-scanner-held-repeat-no-explicit SWIFT_ENABLE_EXPLICIT_MODULES=NO` — passed; only pre-existing Swift 6 warnings were emitted.
- `xcodebuild build-for-testing -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/trading-card-scanner-held-repeat-tests SWIFT_ENABLE_EXPLICIT_MODULES=NO` — an initial attempt completed without source diagnostics; a later rerun was blocked before test execution by the local SwiftData macro server returning a malformed response.
- Added focused coverage for one-shot latch authorization, non-spatial semantics, identity mismatch, authorized reseeding after tracker loss, fake-clock expiry, and request carry-through.
- Runtime XCTest execution after this slice was not available because CoreSimulatorService was disconnected and no simulator device set could be discovered. The previously recorded 506-test baseline remains unchanged; on-device validation is still required for stacked-card camera behavior.
