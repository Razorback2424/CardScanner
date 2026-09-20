I'll start by mapping the scanner module.

# Scanner module review

Scope covered: `Services/CardScanner.swift`, `Services/CardLatch.swift`, `Services/ScanParser.swift`, `Services/SlabFramingRegion.swift`, `Services/CameraRotationTracker.swift`, `Services/CameraCapabilities.swift`, `Views/CameraPreview.swift`, plus the `ScannerViewModel` code paths the scanner callbacks drive.

The core trust machinery holds up: the `metadataRect` quarter-turn transforms are each correct against the stated derivation, `CardLatch` never releases on a single stray frame, and a false spatial-exit proof costs a user prompt rather than a silent duplicate (`CollectionCandidateRoutingPolicy.decision` → `.duplicate` → `pendingDuplicateConfirmation`, [ScannerViewModel.swift:2896](TradingCardScanner/Views/ScannerViewModel.swift:2896)). The findings below are the things that don't.

---

## Confirmed findings

### 1. `historicalAttemptLimit` / `historicalAttemptTTL` are both ineffective — historical title OCR is unbounded
**Where:** [CardScanner.swift:2504-2530](TradingCardScanner/Services/CardScanner.swift:2504), constants at [:854](TradingCardScanner/Services/CardScanner.swift:854) and [:866](TradingCardScanner/Services/CardScanner.swift:866).

**Issue:** When `attempt.retryCount` reaches the limit the code does `historicalAttempt = nil; return nil` — but the next frame hits `if historicalAttempt == nil` and immediately builds a *fresh* attempt with `startedAt: now, retryCount: 0`. The cap therefore suppresses the title pass for exactly one frame out of every seven, and because `startedAt` is reset on every restart the 1.5 s TTL branch at :2509 can never fire either.

**Why it matters:** `PokemonHistoricalIdentityResolver.canAttempt` returns `true` unconditionally for `.officialSet` ([TCGdexService.swift:782-788](TradingCardScanner/Services/TCGdexService.swift:782)). So *any* pre-Scarlet & Violet card showing a legible `NN/NNN` footer that doesn't produce a modern identification adds a third `.accurate` `VNRecognizeTextRequest` to essentially every OCR frame, on the same serial vision queue, for as long as the card sits in the band. That is the exact population this path exists for, and it is the population where it never terminates.

**Smallest correction:** don't clear `historicalAttempt` on limit exhaustion — keep the exhausted attempt (retaining `number` and `startedAt`) and return `nil`, so the TTL branch at :2509 becomes the only thing that can start a new one. A one-line change from `historicalAttempt = nil; return nil` to `return nil` inside that `guard`'s else.

---

### 2. The debug Vision overlay maps observation boxes against the wrong ROI
**Where:** [CameraPreview.swift:318-323](TradingCardScanner/Views/CameraPreview.swift:318), against [CardScanner.swift:1345](TradingCardScanner/Services/CardScanner.swift:1345) and [:2097](TradingCardScanner/Services/CardScanner.swift:2097).

**Issue:** `layoutDebugVisionBoxes` denormalizes with `ScanRegion.activeVisionROI`, which is `CardFramingRegion.visionRect`. The footer request's real ROI has been `visionRect.union(SlabFramingRegion.footerVisionRect(for: nil))` since the slab work landed, and becomes `SlabFramingRegion.footerVisionRect(for: company)` whenever a slab is active ([:2039](TradingCardScanner/Services/CardScanner.swift:2039)). Numerically, in the slab-active case the real ROI is `x≈0.234, y≈0.248, w≈0.533, h≈0.069` while the overlay assumes `x=0.158, y=0.225, w=0.684, h=0.085` — boxes land in visibly wrong places.

**Why it matters:** this overlay is the only on-device instrument for diagnosing the ROI/rotation transform, and the doc comment at [:52-63](TradingCardScanner/Services/CardScanner.swift:52) explicitly sells `calibrationUsesFullFrameROI` as the escape hatch for "the overlay draws nothing". That switch is now dead: `configureTextRequest` never consults `activeVisionROI`, so flipping it changes only the overlay's math while Vision keeps reading the band — the tool now actively lies in the case it was built for.

**Smallest correction:** have `CardScanner` publish the ROI it actually installed (it already publishes `slabFraming`/`slabGuideHint`) and pass that into `fullFrameVisionRect(fromObservationBoundingBox:in:)`; delete `activeVisionROI`/`calibrationUsesFullFrameROI` rather than leaving a switch that no longer reaches Vision.

---

### 3. The green scan band drawn over the preview does not match the region Vision reads
**Where:** [CameraPreview.swift:155-166](TradingCardScanner/Views/CameraPreview.swift:155).

**Issue:** Two of the three preview states disagree with the installed ROI. With no slab evidence, the preview draws `CardFramingRegion.visionRect` (h≈0.085) while the request uses the union with the generic slab footer band (y 0.225→0.317, h≈0.092). With only a `slabGuideHint`, the preview draws `SlabFramingRegion.footerVisionRect(for: nil)` (x 0.234→0.766) while the request is still the much wider union (x 0.158→0.842). Only the confirmed-slab branch is consistent.

**Why it matters:** the band is the product's sole instruction for where to put the card. In the hint state it tells the user to aim at a strip roughly 22% narrower than the one being read, which is a scan-quality regression in exactly the moment the scanner is least certain.

**Smallest correction:** derive the drawn rect from the same expression used at [CardScanner.swift:1345/2097](TradingCardScanner/Services/CardScanner.swift:1345) — publishing the installed ROI (finding 2) fixes both at once.

---

### 4. Frames with no image buffer bypass absence accounting; frames whose footer OCR throws bypass label-cadence accounting
**Where:** [CardScanner.swift:2815](TradingCardScanner/Services/CardScanner.swift:2815) and the `catch` at [:2940](TradingCardScanner/Services/CardScanner.swift:2940).

**Issue:** The module is deliberate about treating a bad frame as absence evidence — the `catch` block says so and routes `.nothing` through `handleFooterOutcome`. Two paths skip that contract. `guard let pixelBuffer = CMSampleBufferGetImageBuffer(...) else { return }` returns before any bookkeeping. And the `catch` path, while it does feed `handleFooterOutcome`, never calls `detectSlabLabelIfDue`, so `unboundFooterEmptyFrames` (which gates the `unboundFooterEmptyFramesBeforeReset = 9` slab-hint reset at [:2245](TradingCardScanner/Services/CardScanner.swift:2245)) does not advance on a failed frame.

**Why it matters:** low impact individually, but it means a sustained bad-buffer condition leaves a stale `slabGuideHint` alive, and `shouldHoldForSlabGrace` will keep deferring raw confirmations for up to `slabGraceDuration = 3.0` s longer than intended.

**Smallest correction:** route the missing-buffer guard into the same `throw CameraFrameError` the format-description guard already uses, and increment `unboundFooterEmptyFrames` in the catch path.

---

### 5. `CameraCapabilities.probeForMacroLens` never checks focus distance, and macro is the default
**Where:** [CameraCapabilities.swift:38-44](TradingCardScanner/Services/CameraCapabilities.swift:38), consumed at [CardScanner.swift:1003-1010](TradingCardScanner/Services/CardScanner.swift:1003).

**Issue:** The probe returns `device.isFocusModeSupported(.continuousAutoFocus)` alone. `CameraLens`'s own rationale at [:634-641](TradingCardScanner/Services/CardScanner.swift:634) is about *focus distance* ("~2 cm" vs "~12 cm"), and `minimumFocusDistance` is already read elsewhere in this file ([AssistanceDeviceState](TradingCardScanner/Services/CardScanner.swift:960)). Because macro is selected as the default whenever the probe says yes, a device with an autofocusing but long-throw ultra-wide opens every session on the wrong lens, and the cached `true` persists per hardware model.

**Why it matters:** the failure mode is a scanner that never resolves the identifier strip at all on affected hardware, with no in-app recovery other than the user finding the lens toggle.

**Smallest correction:** add `device.minimumFocusDistance` to the probe (accept only `>= 0 && <= ~70` mm, matching the `AssistanceDeviceState` convention that `-1` means unknown). Cache invalidation already keys on model identifier, so shipping a stricter probe needs a key bump.

---

## Concerns requiring measurement

### A. Tracker starvation by OCR on the shared vision queue
`videoOutput.setSampleBufferDelegate(self, queue: visionQueue)` puts frame delivery, footer OCR, title OCR, label OCR and `VNTrackObjectRequest` on one serial queue, with the preset chosen as high as `.hd4K3840x2160` ([:1462](TradingCardScanner/Services/CardScanner.swift:1462)). `nextVisionWork` ([:2819](TradingCardScanner/Services/CardScanner.swift:2819)) gives OCR unconditional priority: tracking runs only on frames where OCR is *not* due. If a single OCR pass — up to three `.accurate` recognitions, which finding 1 makes the common case on older Pokémon cards — exceeds the 0.24 s `ocrInterval`, then every delivered frame finds OCR due again and `trackCurrentFrame` never executes.

The consequence is not degraded tracking, it is the loss of the entire spatial-exit path: no `SpatialResetProof` is ever emitted, `CollectionCandidateRoutingPolicy` falls through to `.suppress` for every re-presented card, and genuine second copies can only be added via the held-card offer. That is a silent, device-dependent product regression.

This needs a device trace, not a code argument. The instrumentation is already in place: compare the `footerOCR` + `titleOCR` + `labelOCR` interval durations against the `tracking` event rate and `trackerSeeded`/`trackerLost` diagnostics on the slowest supported device at 4K, with an older Pokémon card in the band. If OCR wall time exceeds ~200 ms, either move tracking to its own `VNSequenceRequestHandler` on a second queue or cap the preset at 1080p for the tracking-critical path.

### B. Main-actor work proportional to session length
`offerHeldDuplicate` rebuilds a `Dictionary` over all of `sessionScans` on every latch-hold announcement ([ScannerViewModel.swift:1785](TradingCardScanner/Views/ScannerViewModel.swift:1785)), and the fallback-quote paths iterate `sessionScans` wholesale ([:3131](TradingCardScanner/Views/ScannerViewModel.swift:3131), [:3247](TradingCardScanner/Views/ScannerViewModel.swift:3247)). `sessionScans` is unbounded for the session, `committedSessionHistory` is capped at 6. The code already flags this with a signpost carrying `sessionScans.count`, which is the right instrument — the open question is whether a realistic bulk session (hundreds to thousands of cards) makes these visible against the scanner's frame budget. Measure with the existing `offerHeldDuplicateRebuild` interval before changing anything; if it grows, the fix is a `[RecentScan.ID: ScanSuppressionKey]` index maintained at `appendCommittedScan`, not a refactor.

### C. Tracker seed is a fixed rectangle, not the detected card
`seedTracker` seeds `VNTrackObjectRequest` with `spatialTrackingConfiguration.seedRect` — `cardVisionRect` inset 6% — rather than anything derived from the observed card ([:1556](TradingCardScanner/Services/CardScanner.swift:1556)), at `trackingLevel = .fast`. The exit rule needs only 2 consecutive qualifying observations (~250 ms at 8 Hz) to mark `hasLeft` on the latch. The design is correctly fail-safe — a false exit surfaces a user prompt, not a silent duplicate — but the false-positive *rate* determines how often the user is interrupted by a duplicate question for a card that never moved. `SpatialTrackingConfiguration` is explicitly labelled experimental; this is the calibration that needs field data (`spatialProof` vs `trackerLost` diagnostic counts against known-stationary cards), not a code change.

---

I did not find defects in the `metadataRect`/`imageOrientation`/`visionSourceSize` transforms (each checked against the inverse-rotation derivation), in `CardLatch`'s absence and clock-compensation logic, or in the `MagicScanProfile` collector-number canonicalization — those read as correct and I've left them out rather than padding the list.