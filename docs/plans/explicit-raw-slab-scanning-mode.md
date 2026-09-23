# Plan: Explicit Raw / Slab scanning mode

## Context

Graded slab scanning has never produced a successful scan. The review found the cause is structural. Auto-detection races the raw-card pipeline:
- A single label probe runs on the first footer-text frame. If it misses, the raw card is confirmed within ~0.25–0.5 s and later label evidence is discarded by design (`isLateSlabUpgradeOfLatchedRaw`).
- After the first grader hint, the label and footer search areas collapse to bands calibrated for one exact slab position.
- The auto path also taxes every raw scan:
  - label OCR runs on the critical path of each new card;
  - periodic 1.5 s label passes run while a card is in view;
  - raw TAG TEAM cards can trigger an indefinite hold;
  - about 400 lines of hint/hold/recovery state sit on the raw path.

Outcome: slab recognition becomes an explicit mode, selected in the existing **Auto / finish-lock menu**. No new top-bar control. The mode is independent of the Collection / Price Check purpose.

User decisions:
- Mode is **session-only**, default Raw.
- In Slab mode, a card with no readable label gets a **"Switch to Raw"** offer.
- Collection + Slab **saves immediately and prices afterward**.
- Raw mode runs **no label OCR before commit**. It gets a **non-blocking post-save "Looks graded — convert?" banner**.

## Design overview

| | Raw mode | Slab mode |
|---|---|---|
| Guide | raw card outline | slab outline + card window from the start (solid) |
| Footer ROI | `CardFramingRegion.visionRect` only | padded slab footer band |
| Label OCR before commit | never | every OCR pass until evidence confirms |
| Commit requires | footer identity (2/4) | footer identity **and** confirmed label evidence |
| After commit | ≤4 low-rate label reads while the same card stays latched → optional "convert to graded" banner | label keeps reading only for certificate refinement (existing flow) |
| Price | unchanged | Collection: save now, bind graded price in background. Price Check: present now, existing auto-refresh fetches graded quote |

## Phase 1 — Mode plumbing and menu (no recognition change yet)

1. **New type.** Add `enum ScanSubjectMode: String, CaseIterable, Sendable { case raw, slab }` with `title` and `symbolName`. It goes in `TradingCardScanner/Models/` next to `ScanPurpose`.
2. **View model** (`Views/ScannerViewModel.swift`):
   - Add `@Published private(set) var subjectMode: ScanSubjectMode = .raw`. It is session-only, like `finishLocks` (~line 1040).
   - Add `func setSubjectMode(_:)`, mirroring `setPurpose` (~1764): `invalidatePendingScan()`, set the mode, `visibilityEpoch = UUID()`, `updateScannerConfirmationContext()`, `scanner.setSubjectMode(mode)`, `resumeRecognitionIfPossible()`, haptic, and an accessibility announcement.
   - Add `subjectMode` to `ScannerConfirmationToken` (~55) and `currentConfirmationToken` (~1399), so stale confirmations from the other mode drop through the existing `staleConfirmationDropped` guard.
3. **Scanner** (`Services/CardScanner.swift`):
   - Add `func setSubjectMode(_:)`. It hops to `visionQueue`, the same pattern as `usePokemonProfile` (~1482).
   - When the mode changes it runs `resetObservationState()` and `clearActiveSlab(cause: .lifecycle)`, installs the mode's ROIs, and publishes `uiState.subjectMode`.
4. **Menu** (`Views/ScannerView.swift`, `FinishLockControl` ~502):
   - Add a top section, "Scanning", with an inline `Picker` offering "Raw cards" / "Graded slabs". Below it sit the existing Auto item and the per-game lock submenus.
   - In Slab mode the lock submenus are disabled, with the caption "Finish locks apply to raw cards". Lock state is kept for when the user returns to Raw.
   - Pill label: Raw shows the existing summary ("Auto" or the locks). Slab shows a slab symbol, the text "Slabs", and a distinct tint. Add `subjectMode` to the `Equatable` of both `FinishLockControl` and `ScannerTopBar`, and to the accessibility label.
   - Thread `subjectMode` / `setSubjectMode` through `ScannerChrome` → `ScannerTopBar` (~150, ~368).

## Phase 2 — Strip auto-detection from Raw mode

In `CardScanner.swift`, delete or bypass the following on the Raw path:
- the bootstrap probe (`firstProbeForPresentation` and `mustProbeSlabBeforeNextCommit`, ~2434)
- `slabLabelCadenceKind` and the unbound cadence
- `updateSlabGuideHint`, `clearSlabGuideHint`, `slabGuideHintForGate`, `slabGuideHintIdentifier`, `slabLabelHold*`
- `updateSlabLabelPromptIfDue`
- `rawSlabOverride*` and `chooseRawForPendingSlabLabel`
- `shouldHoldForSlabLabel`
- `isLateSlabUpgradeOfLatchedRaw` (~2035, ~2081, ~2149)
- `slabRecoveryDeadline`, `unboundSlabAbsenceDeadline`, `unboundFooterEmptyFrames`, and the unbound-slab branch of `markTrackerContinuityLost`
- the unbound-footer bookkeeping in the `captureOutput` catch path (~3331)

Raw ROIs:
- footer: `CardFramingRegion.visionRect` only (drop the union with the slab footer)
- title: `CardFramingRegion.titleVisionRect`

The raw path of `handleFooterOutcome` then becomes: `parsed = subject`, latch, confirmation, engage. It is unchanged from the pre-slab design.

Also remove:
- `ScanCadenceKind.unboundLabel` and `unboundLabelInterval` (~288–350)
- the provisional-hint branch in `CameraPreview.layoutSubviews` (~160)
- `slabGuideHint` and `slabLabelReadPrompt` publishing in `CardScannerUIState` (~681–740). The prompt slot is reused in Phase 3.

## Phase 3 — Slab mode pipeline (scanner)

1. **ROIs.** Add to `Services/SlabFramingRegion.swift`:
   - `slabModeFooterVisionRect`: generic footer band, padded about ±0.02 x and ±0.015 y.
   - `slabModeLabelVisionRect`: generic label band, padded vertically, e.g. slab-relative y 0.72…1.06, clamped to the frame.

   These tolerate framing drift, which the current bands do not. Keep `geometry(for:)` as the single calibration surface. Keep the per-company rects as they are, but don't narrow to them in the first version.
2. **Guide.** `CameraPreview` shows `slabVisionRect` plus `cardWindowVisionRect` solid from the moment Slab mode is selected. `slabFraming` still carries the confirmed grade and cert for display.
3. **Label cadence.** In `captureOutput` (~3258), when `subjectMode == .slab`:
   - Run `labelRequest` on every OCR frame until `slabEvidenceWindow` confirms.
   - Afterward, run it at `labelInterval` (0.5 s) only while `certificationNumber == nil`, to feed the existing `onGradedSlabCertificationRefined` path.
   - Factor the decision into one pure function, `SlabLabelSchedule.shouldReadLabel(mode:hasEvidence:certKnown:lastLabelAt:now:)`. The test seams call the same function (this fixes the review's test gap).
4. **Commit gate** in `handleFooterOutcome`, Slab mode only:
   - If a footer identity is found but there is no `activeSlab`, do not feed `confirmationWindow`. Call `announceLatchHoldIfNeeded()` and start `slabAwaitingLabelSince`.
   - If a footer identity is found and `activeSlab` exists, set `parsed = ScanSubject(identifier:, slab:)` and run the normal confirm/engage.
   - A slab subject can never commit as raw.
5. **Presence.** Replace `updateActiveSlabPresence` with a simple rule. Evidence binds to the first footer key seen with it. It clears on any of:
   - 4 empty footer frames
   - a different footer key
   - spatial exit
   - latch release
   - mode change or lifecycle

   Drop the recovery windows and continuity stamps: losing evidence only costs one more label read. Keep `activateSlab`'s certificate enrichment (~2206) and its cert-refinement callback.
6. **No-label offer.** If a footer identity has been readable for ≥3 s with no confirmed evidence, publish a prompt through the existing `SlabLabelReadPrompt` / `SlabLabelReadingOfferView` slot (`ScanSessionOverlays.swift:20`, `ScannerView.swift:335`). New copy: "No slab label found — Switch to Raw". The action calls `model.setSubjectMode(.raw)`. Nothing is saved.

## Phase 4 — View model: save now, price after; instant Price Check

1. In `resolvePrintRun` (~2669), drop the blocking `await gradedResolver.resolve` for Collection. Leave `gradedOutcome` nil. `ScannerCollectionWriter.add` then uses `addScannedGraded` (`CollectionStore.swift:295`).
2. After a successful slab commit (`commitAuthorizedCollectionCandidate`, ~3268), call a new `queueGradedBinding(scanID:)`. It runs off the identification queue:
   - Call `gradedResolver.resolve(...)`.
   - On `.bound`, re-read the **current** `RecentScan.mutation.collectionKey` by scan ID, because cert refinement can change the key.
   - Call a new `ScannerCollectionWriter.bindScannedGraded(collectionKey:variant:)`.
   - Update the price in `sessionScans`, `recent` and the visible receipt.
   - Move the "no graded price published / no vendor match / price pending" notes here from commit time.
   - Guard with `isStorageGenerationCurrent` and a session ID, dedupe per scan ID, and skip if the scan was undone. This follows the `queueFallbackPrice` pattern (~3327).
3. **Reuse the binding logic.** Extract the `bind(...)` + `store.store(...)` + record-stamping block in `PriceRefreshController.refreshGraded` (~1300–1470) into a shared helper, e.g. `GradedVariantBinding.apply(variant:to row:priceStore:context:)`. Both the refresh pass and `bindScannedGraded` use it, so there is one lineage-promotion path (`PriceIdentityLineageMigration.promoteUnboundPriceIdentity`).
4. **Price Check.** Skip the resolver during resolution and present immediately. `PriceCheckCoordinator.present` (~180) already maps a nil outcome to an auto-refresh. For slab + nil outcome, set the initial `quoteState` to `.checking` rather than `.providerUnavailable`, so the sheet doesn't flash "unavailable".
5. In `resolveVariant` (~2746), pass `finishLock: nil` for slab requests. The label is the authority, and slab rows have no raw finish.

## Phase 5 — Parser and resolver accuracy fixes (from the review)

In `Services/GradedLabelParser.swift`:
- **TAG.**
  - Ignore a `TAG` token followed by `TEAM`, `BOLT`, `ALL`, or `GX`.
  - Require a certificate for TAG evidence.

  Apply both in `company(in:)` and in `parse`.
- **Grade word vs card-name "EX".** Prefer grade words that have an admissible grade number adjacent in the spec's `numberPosition`. Accept a lone `EX`, `NM`, or `VG` only when a grade number is adjacent.
- **Confirmation window** (`SlabEvidenceConfirmationWindow.matches`, ~798). Treat reads as matching when company, label and qualifier agree and the value agrees or is missing from one read. Return the most complete read.

In `Services/ScannedGradedResolver.swift` (`matchingVariant`, ~106):
- Accept a single candidate only if its label is nil or matches the scanned label after synonym normalization (`GEM MT` ≡ `GEM MINT`, `NM-MT` ≡ `NM MT`, …).
- Never bind Black Label from a non-Black-Label read.

## Phase 6 — Raw mode post-save "Looks graded — convert?" banner

1. **Scanner.** In Raw mode + Collection purpose, arm a `PostCommitLabelWatch(encounterID:startedAt:)` at `latch.engage`.
   - Only on OCR frames while that encounter is still latched. At most 4 label reads, starting 0.5 s after engage and spaced ≥0.75 s apart, using the wide `bootstrapLabelVisionRect`.
   - Use its own `SlabEvidenceConfirmationWindow`.
   - It ends on latch release, spatial exit, a new encounter, or a mode or purpose change.
   - On confirmation it emits `onPostCommitSlabEvidence(encounterID, evidence)` once.

   Label OCR never runs before a raw commit decision.
2. **View model.**
   - If the commit hasn't landed yet, stash the evidence by encounter ID, the same pattern as `pendingGradedCertificationRefinements` (~1017).
   - Once the commit lands, publish `pendingSlabConversionOffer` (scan ID + evidence). Show it as a banner modeled on `GradedVariantCorrectionOfferView` in `ScannerChrome` (~176): "Looks like PSA 10 — Save as graded" [Convert] [×].
   - The banner auto-dismisses on the next commit or after ~8 s.
3. **Convert.**
   - New `ScannerCollectionWriter.convertRawScanToGraded(previous: CollectionMutation, card:, evidence:, pokemonPrintRun:, resolved:)` runs `CollectionStore.undo` + `addScannedGraded` in **one save**. If either store method saves on its own, add a non-saving variant, following the `store.add(..., savesChanges: false)` pattern.
   - Replace the `RecentScan` in place with the same ID (as `correct(scanID:)` does, ~2336), with a slab subject and the new mutation.
   - Update the matching `committedSessionHistory` identity.
   - Then call `queueGradedBinding`.

## Phase 7 — Tests and docs

**Retire or rewrite** the auto-detection tests:
- `CardLatchTests` slab cases (~475–840)
- `OpusImplementationPlanTests` REQ007/008 and RM003/008 (~1377–1650)

Replace them with mode-based tests:
- Raw: no label pass before commit (counting seam); a TAG TEAM raw card confirms in 2 frames.
- Slab: footer-only frames never confirm; footer + evidence confirms; the no-label offer appears after 3 s; a mode switch drops in-flight confirmations.
- Post-commit watch: arms only after engage, reads at most 4 times, emits once.

**View model tests** (`ScannerViewModelTests` ~297–650). Keep the slab-subject tests and adapt them to save-now/price-after. Add tests for:
- binding after commit, including after a cert refinement changes the key
- the undo-during-binding race
- Price Check with a nil outcome

**Parser tests:**
- TAG TEAM labels and raw TAG TEAM text
- `CHARIZARD EX … MINT 9`
- a read missing the number matches a complete read

Resolver tests: a single conflicting-label candidate returns nil.

`SlabFramingRegionTests`: the padded slab-mode ROIs stay inside the frame and contain the generic bands.

**Docs:**
- Update `docs/audits/scanner_module_review.md`, or the current scanner plan named in `docs/plans/documentation_audit.md`, to record the move from auto-detection to an explicit mode.
- Add a dated `progress.md` entry.

## Critical files

- `TradingCardScanner/Services/CardScanner.swift` — mode, raw strip, slab pipeline, post-commit watch
- `TradingCardScanner/Services/SlabFramingRegion.swift` — padded slab-mode ROIs
- `TradingCardScanner/Services/GradedLabelParser.swift` — TAG/EX fixes, confirmation matching
- `TradingCardScanner/Services/ScannedGradedResolver.swift` — label-conflict fix
- `TradingCardScanner/Views/ScannerViewModel.swift` — mode state/token, price-after, conversion offer
- `TradingCardScanner/Views/ScannerView.swift`, `CameraPreview.swift`, `ScanSessionOverlays.swift` — menu, guide, banners
- `TradingCardScanner/Services/CollectionStore.swift` (`ScannerCollectionWriter`) — `bindScannedGraded`, `convertRawScanToGraded`
- `TradingCardScanner/Services/PriceRefreshController.swift` — extract the shared graded binding helper
- `TradingCardScanner/Services/PriceCheckCoordinator.swift` — `.checking` initial state for slab + nil outcome

Reused as-is:
- `GradedSlabEvidence`, `SlabEvidenceConfirmationWindow`
- `CardLatch` / `CandidateConfirmationWindow`
- cert refinement (`receiveGradedSlabCertificationRefinement`)
- `addScannedGraded` / `addGraded`
- `GradedVariantCorrectionOfferView`
- Price Check graded refresh

## Verification

1. Build and test narrowly. Use an external-SSD `-derivedDataPath` if one is mounted, per `AGENTS.md`:
   `xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TradingCardScannerTests/{CardLatchTests,GradedLabelParserTests,SlabEvidenceConfirmationWindowTests,ScannedGradedResolverTests,SlabFramingRegionTests,ScannerViewModelTests}`

   Then run the full suite, and report failures against the recorded baseline (40 known failures at `a4375df`).
2. Simulator UI: confirm the menu shows the "Scanning" section, the pill reads "Slabs" in Slab mode, lock pickers are disabled in Slab mode, and the top bar gains no new control.
3. Device (required; simulator evidence can't prove recognition):
   - **Raw speed.** Compare the Instruments `oneCardScan` / `footerOCR` / `labelOCR` signposts before and after on a stack of raw cards. Expect no `labelOCR` intervals before commit.
   - **Slab recognition.** In Slab mode, run the DEBUG `[GradedLabelCapture]` route on PSA, BGS and CGC slabs, in both Collection and Price Check. Record time-to-commit, the grade/cert read, and the price binding arriving after the save.
   - **Edge cases:**
     - a raw TAG TEAM card in Raw mode (no stall)
     - a raw card in Slab mode (the "Switch to Raw" offer)
     - a slab scanned in Raw mode (convert banner → graded row with price)
4. Do not record device, provider or release readiness from source or simulator results alone.
