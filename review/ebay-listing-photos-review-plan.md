# Review remediation plan — eBay listing photos (Slices A–C)

**Reviewed:** uncommitted changes on `pro-implementation` at base `523f3e2`, 2026-09-15.
**Scope of this document:** only high-confidence, material defects. Cosmetic
preferences and already-open gates from
[`docs/plans/pro_tab_ebay_listing_photos_plan.md`](../docs/plans/pro_tab_ebay_listing_photos_plan.md)
(screenshots, device evidence, release certification) are **out of scope** and
are not repeated here.

**What was verified and is correct** — do not "fix" these:

- Crop geometry, truncation, listing order, and corner-to-name mapping.
  `CGImage.cropping(to:)` indexes from the top-left of the image buffer, so
  `.topLeft` really is the physical top-left. Covered by tests.
- The JPEG byte-passthrough path works; `CGImageSourceGetType(source) == (UTType.jpeg.identifier as CFString)`
  does compare by value (proved by `testExportPreservesAnUpOrientedJPEGFullImageAndCreatesListingOrder`,
  which asserts the written file equals the source bytes).
- `EbayListingPhotosView` is `@MainActor`-isolated: SwiftUICore declares
  `@preconcurrency @MainActor public protocol View`, so global-actor inference
  applies to the whole struct. There is no off-main `@State` mutation. This is
  also *why* F1 below is a real defect.
- The centering capture path is unchanged: `maximumPhotoDimensions` is left
  `nil` for `.centering`, so `AVCapturePhotoSettings.maxPhotoDimensions` is
  never set on that path.
- The batch loop cannot index out of bounds. Every mutation of `batchPairs`
  bumps `batchSelectionGeneration`, and the generation guard precedes the
  `batchPairs[index]` subscript in each iteration.

---

## F1 — `makeBatchArchive` zips and copies the whole batch on the main actor

**Severity:** high (UI freeze, watchdog-termination risk on large batches).

**Where:** [`TradingCardScanner/Views/EbayListingPhotosView.swift:583`](../TradingCardScanner/Views/EbayListingPhotosView.swift#L583)
calls [`EbayListingPhotoExport.makeBatchArchive`](../TradingCardScanner/Services/EbayListingPhotoExport.swift#L138),
and line 551 calls [`moveOutput`](../TradingCardScanner/Services/EbayListingPhotoExport.swift#L114).

**Why it is a defect:** `processBatch` is `@MainActor`-isolated (see above).
`makeBatchArchive` and `moveOutput` are *synchronous* statics, so they execute
on the main thread. `makeBatchArchive` runs `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)`,
which zips the entire batch directory, then `FileManager.copyItem` duplicates
the resulting archive. For a 12-card batch of 48 MP photos that is ~120 files
and several hundred megabytes of compression plus a full byte copy — seconds of
a completely frozen UI, during which the "Card N of M" progress view cannot even
repaint. Every other expensive operation in this feature is correctly pushed
into `Task.detached`; these two were missed.

### Implementation

**Step 1.** In `TradingCardScanner/Services/EbayListingPhotoExport.swift`,
rename the existing `moveOutput` and `makeBatchArchive` to private synchronous
workers and add async wrappers that mirror the `makeListingPhotos` pattern.

Replace the declaration line of `moveOutput` (line 114):

```swift
    static func moveOutput(_ output: Output, to cardDirectory: URL) throws {
```

with:

```swift
    private static func moveOutputSynchronously(_ output: Output, to cardDirectory: URL) throws {
```

Replace the declaration line of `makeBatchArchive` (line 138):

```swift
    static func makeBatchArchive(at batchDirectory: URL) throws -> URL {
```

with:

```swift
    private static func makeBatchArchiveSynchronously(at batchDirectory: URL) throws -> URL {
```

**Step 2.** Immediately after the closing brace of `makeBatchArchiveSynchronously`
(currently line 187, the `}` following `return archiveURL`), insert these two
wrappers:

```swift
    /// Moves one completed pair into its batch folder off the main actor.
    /// A rename is usually cheap, but a cross-volume fallback copy is not, and
    /// this runs once per card while the progress view must stay responsive.
    static func moveOutput(_ output: Output, to cardDirectory: URL) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            try moveOutputSynchronously(output, to: cardDirectory)
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Zips the batch off the main actor. Compressing and copying a multi-card
    /// batch of native-resolution JPEGs is a multi-second operation; running it
    /// on the main actor froze the progress view until it finished.
    static func makeBatchArchive(at batchDirectory: URL) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) {
            try makeBatchArchiveSynchronously(at: batchDirectory)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
```

**Step 3.** In `TradingCardScanner/Views/EbayListingPhotosView.swift`, add
`await` at both call sites.

Line 551, change:

```swift
                try EbayListingPhotoExport.moveOutput(output, to: cardDirectory)
```

to:

```swift
                try await EbayListingPhotoExport.moveOutput(output, to: cardDirectory)
```

Line 583, change:

```swift
            batchArchiveURL = try EbayListingPhotoExport.makeBatchArchive(at: directory)
```

to:

```swift
            batchArchiveURL = try await EbayListingPhotoExport.makeBatchArchive(at: directory)
```

**Step 4.** `Output` is `@unchecked Sendable`, so it already crosses into the
detached task without a diagnostic. Do not change its conformance.

**Acceptance:** build succeeds; a batch of at least 4 pairs keeps the
"Card N of M" progress view animating through the archive step, and the Cancel
button remains tappable.

---

## F2 — The JPEG quality ladder dead-ends at 0.75 and aborts all ten outputs

**Severity:** high (total, unrecoverable export failure on photos this app's own
camera produces).

**Where:** [`TradingCardScanner/Services/EbayListingPhotoExport.swift:391`](../TradingCardScanner/Services/EbayListingPhotoExport.swift#L391).

**Why it is a defect:** `encodedJPEG` tries `[0.95, 0.85, 0.75]` and then throws
`.byteBudgetExceeded`. That error propagates out of `processSide` →
`makeListingPhotosSynchronously` → `makeListingPhotos`, which deletes the run
directory and rethrows. In single-card mode the user gets an error string and
**zero of the ten photos** — one oversized image destroys the whole set.

This is reachable, not theoretical. Slice B's own camera change
([`CenteringCameraView.swift:186-199`](../TradingCardScanner/Views/CenteringCameraView.swift#L186))
deliberately configures the capture at the sensor's **maximum** supported photo
dimensions, i.e. 48 MP on an iPhone 14 Pro or newer. A 48.8 MP JPEG at quality
0.75 lands roughly in the 8–17 MB range for detailed, high-frequency subjects —
foil and textured card stock being exactly that. Above 12 MB the export throws.
A 48 MP HEIC chosen from the photo library is worse: it cannot take the byte
passthrough at all, so it always runs the ladder.

Extending the ladder fixes this without touching the plan's explicit
"reduce quality, never dimensions" policy (plan §Memory-and-encoding, item 3):
at quality 0.45 a 48.8 MP JPEG is comfortably inside 12 MB.

### Implementation

In `TradingCardScanner/Services/EbayListingPhotoExport.swift`, in `encodedJPEG`,
change line 391:

```swift
        let qualities: [CGFloat] = [0.95, 0.85, 0.75]
```

to:

```swift
        // The ladder must be able to bring the largest image this app can
        // produce under the budget. The camera path captures at the sensor's
        // maximum photo dimensions (48 MP on recent devices), and a 48 MP JPEG
        // of a foil card can still exceed 12 MB at 0.75. Stopping there made a
        // single oversized image discard the whole ten-photo set.
        let qualities: [CGFloat] = [0.95, 0.85, 0.75, 0.65, 0.55, 0.45]
```

Leave the rest of `encodedJPEG` unchanged: `return (data, index > 0)` still
flags anything below 0.95 as reduced, and the final `throw` is retained as a
genuine last resort.

### Required test (simulator, no device needed)

Append to `final class EbayListingPhotoExportTests` in
`TradingCardScannerTests/EbayQuadrantCropperTests.swift`:

```swift
    /// A source that cannot fit the budget at 0.75 must still export, because a
    /// single oversized image previously discarded all ten outputs.
    func testOversizedSourceStepsBelowQualityPointSevenFiveInsteadOfFailing() async throws {
        let noisy = try XCTUnwrap(noiseFixture(width: 4_000, height: 5_600).cgImage)
        let data = try jpegData(for: noisy)
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: data,
            backData: data
        )
        defer {
            EbayListingPhotoExport.removeRun(
                at: output.urls.first?.deletingLastPathComponent()
            )
        }

        XCTAssertEqual(output.urls.count, 10)
        for url in output.urls {
            let written = try Data(contentsOf: url)
            XCTAssertLessThanOrEqual(
                written.count,
                EbayListingPhotoExport.maximumJPEGByteCount,
                "\(url.lastPathComponent) exceeded the export byte budget"
            )
        }
    }

    /// High-frequency noise is the worst case for JPEG: it defeats the DCT and
    /// keeps the encoded size near its ceiling at every quality step.
    private func noiseFixture(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var generator = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: 0, to: width, by: 2) {
                    UIColor(
                        red: CGFloat(UInt8.random(in: 0...255, using: &generator)) / 255,
                        green: CGFloat(UInt8.random(in: 0...255, using: &generator)) / 255,
                        blue: CGFloat(UInt8.random(in: 0...255, using: &generator)) / 255,
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
    }
```

**Acceptance:** the new test passes, and all ten written files are at or below
`EbayListingPhotoExport.maximumJPEGByteCount`.

---

## F3 — `settings.maxPhotoDimensions` can exceed the output's maximum (ObjC exception)

**Severity:** high (hard crash, on the untested physical-device path).

**Where:** [`TradingCardScanner/Views/CenteringCameraView.swift:99-101`](../TradingCardScanner/Views/CenteringCameraView.swift#L99)
and [`:186-199`](../TradingCardScanner/Views/CenteringCameraView.swift#L186).

**Why it is a defect:** two problems compound.

1. `camera.activeFormat.supportedMaxPhotoDimensions` is read at line 187, which
   is **inside** `session.beginConfiguration()` / before the `defer`-ed
   `commitConfiguration()` at line 178. Configuration changes — including the
   `sessionPreset = .photo` set at line 179 and the input added at line 183 —
   are batched and applied at commit. The `activeFormat` read there is not
   guaranteed to be the format the session actually settles on.
2. `AVCapturePhotoSettings.maxPhotoDimensions` raises an `NSInvalidArgumentException`
   when it is set larger than the photo output's `maxPhotoDimensions`. An
   ObjC exception is not catchable in Swift — it terminates the app. If (1)
   leaves `photoOutput.maxPhotoDimensions` clamped below the cached
   `maximumPhotoDimensions`, every shutter press crashes.

The fix removes the cached value entirely and reads back from the output, which
is valid by construction, and moves the read to after the session commits.

### Implementation

**Step 1.** Delete the now-unneeded cache. In `CenteringCameraController`,
remove line 44:

```swift
    private var maximumPhotoDimensions: CMVideoDimensions?
```

and add in its place:

```swift
    /// Set once the session has committed, because `activeFormat` is not
    /// settled until then. Only the listing-photo configuration raises it; the
    /// centering path keeps AVFoundation's default photo dimensions.
    private var configuredCamera: AVCaptureDevice?
```

**Step 2.** In `capture()`, replace lines 99–101:

```swift
            if let maximumPhotoDimensions = self.maximumPhotoDimensions {
                settings.maxPhotoDimensions = maximumPhotoDimensions
            }
```

with:

```swift
            if self.configuration == .listingPhotos {
                // Read back from the output rather than from a cached format
                // value: `maxPhotoDimensions` is the only value guaranteed to
                // be accepted here, and exceeding it raises an uncatchable
                // ObjC exception.
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
```

**Step 3.** In `configureSession()`, replace the whole block at lines 186–199:

```swift
        if configuration == .listingPhotos {
            guard let dimensions = camera.activeFormat.supportedMaxPhotoDimensions.max(
                by: { lhs, rhs in
                    Int64(lhs.width) * Int64(lhs.height)
                        < Int64(rhs.width) * Int64(rhs.height)
                }
            ) else {
                throw CameraConfigurationError.unavailable
            }
            photoOutput.maxPhotoDimensions = dimensions
            maximumPhotoDimensions = dimensions
        } else {
            maximumPhotoDimensions = nil
        }
```

with:

```swift
        configuredCamera = camera
```

**Step 4.** Add a new method immediately after `configureSession()` (that is,
after its closing brace at line 231):

```swift
    /// Raises the still-image size to the sensor maximum for listing photos.
    /// This must run after `configureSession` returns, because the session's
    /// `commitConfiguration` is deferred to that point and `activeFormat` is
    /// not settled before it.
    private func applyMaximumPhotoDimensionsIfNeeded() {
        guard configuration == .listingPhotos, let camera = configuredCamera else { return }
        guard let dimensions = camera.activeFormat.supportedMaxPhotoDimensions.max(
            by: { lhs, rhs in
                Int64(lhs.width) * Int64(lhs.height)
                    < Int64(rhs.width) * Int64(rhs.height)
            }
        ) else { return }
        photoOutput.maxPhotoDimensions = dimensions
    }
```

Note the deliberate change from `throw` to a silent return: failing to raise the
resolution should degrade to a default-size capture, not make the camera
unavailable.

**Step 5.** In `configureAndStart(requestID:)`, change:

```swift
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
```

to:

```swift
                if !self.isConfigured {
                    try self.configureSession()
                    self.applyMaximumPhotoDimensionsIfNeeded()
                    self.isConfigured = true
                }
```

**Acceptance:** the centering path is byte-identical in behaviour (no
`maxPhotoDimensions` is ever set on it). On a 48 MP device, a listing capture
produces a 48 MP image; on any device, repeated shutter presses do not crash.
This must be checked on hardware — it is part of the already-open device gate.

---

## F4 — An in-flight batch is silently destroyed by controls that stay live

**Severity:** medium-high (silent loss of minutes of work, no user feedback).

**Where:** [`TradingCardScanner/Views/EbayListingPhotosView.swift:210-235`](../TradingCardScanner/Views/EbayListingPhotosView.swift#L210).

**Why it is a defect:** while `isPreparingBatch` is true, the `PhotosPicker`
(line 210), every row's Swap button, and every row's folder-name `TextField`
remain interactive. Touching any of them reaches `updateBatchPairs()` or
`invalidateBatchResults()`, both of which bump `batchSelectionGeneration` and
cancel `batchProcessingTask`. The task's cancellation branch then deletes the
whole batch directory, including every card already completed.

The user sees no explanation: `invalidateBatchResults()` clears
`batchErrorMessage`, `batchFailures`, and `batchProgress`, so the progress view
simply vanishes and the "Prepare N cards" button reappears. A 20-card batch can
be wiped by one stray tap on a text field.

The Cancel button is the intended way to stop a batch and must stay enabled.

### Implementation

In `TradingCardScanner/Views/EbayListingPhotosView.swift`:

**Step 1.** Disable the picker during processing. Change lines 210–218 from:

```swift
            PhotosPicker(
                selection: $batchPickerItems,
                maxSelectionCount: nil,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("Choose an even number of photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
```

to:

```swift
            PhotosPicker(
                selection: $batchPickerItems,
                maxSelectionCount: nil,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("Choose an even number of photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
            // Re-picking mid-run cancels the batch and deletes every card
            // already written. Cancel is the deliberate way out.
            .disabled(isPreparingBatch)
```

**Step 2.** Disable the per-row editing controls. Change lines 234–236 from:

```swift
                ForEach($batchPairs) { $pair in
                    BatchPairRow(pair: $pair, onChange: invalidateBatchResults)
                }
```

to:

```swift
                ForEach($batchPairs) { $pair in
                    BatchPairRow(
                        pair: $pair,
                        isEditable: !isPreparingBatch,
                        onChange: invalidateBatchResults
                    )
                }
```

**Step 3.** In `private struct BatchPairRow`, add the property. Change:

```swift
    @Binding var pair: EbayListingPhotosView.BatchPair
    let onChange: () -> Void
```

to:

```swift
    @Binding var pair: EbayListingPhotosView.BatchPair
    let isEditable: Bool
    let onChange: () -> Void
```

**Step 4.** In `BatchPairRow.body`, disable the two controls. Change the Swap
button's modifier chain from:

```swift
                .labelStyle(.iconOnly)
                .accessibilityLabel("Swap front and back for this pair")
```

to:

```swift
                .labelStyle(.iconOnly)
                .accessibilityLabel("Swap front and back for this pair")
                .disabled(!isEditable)
```

and the `TextField` from:

```swift
            TextField("Folder name", text: $pair.folderName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Folder name for this card")
```

to:

```swift
            TextField("Folder name", text: $pair.folderName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Folder name for this card")
                .disabled(!isEditable)
```

**Step 5.** Update the smoke test construction if `BatchPairRow` is referenced
anywhere outside this file. It is `private`, so no other call site exists —
confirm with `grep -rn "BatchPairRow" --include='*.swift' .` and change nothing
else if the only hits are in `EbayListingPhotosView.swift`.

**Step 6.** Close the re-entrancy hole in `startBatch()` while here. Change
lines 496–502 from:

```swift
    private func startBatch() {
        guard !isPreparingBatch, !batchPairs.isEmpty else { return }
        let generation = batchSelectionGeneration
        batchProcessingTask = Task {
            await processBatch(generation: generation)
        }
    }
```

to:

```swift
    private func startBatch() {
        guard !isPreparingBatch, !batchPairs.isEmpty else { return }
        // The flag must be raised here, not inside the task body: `Task` does
        // not run synchronously, so two taps landing before the first hop
        // would otherwise start two pipelines and leak the first directory.
        isPreparingBatch = true
        let generation = batchSelectionGeneration
        batchProcessingTask = Task {
            await processBatch(generation: generation)
        }
    }
```

`processBatch` already sets `isPreparingBatch = true` at line 506; leave that
line in place — it is harmless and keeps the function correct on its own.

**Acceptance:** during a batch run the photo picker, Swap buttons, and folder
name fields are visibly disabled; Cancel still works and still cleans up.

---

## F5 — The orientation transcode path has no test at all

**Severity:** medium (the single highest-risk behaviour in the feature is
covered only by an open manual gate).

**Where:** `TradingCardScannerTests/EbayQuadrantCropperTests.swift` —
`EbayListingPhotoExportTests` contains exactly one test, and it exercises the
byte-passthrough path only.

**Why it matters:** the plan's difference table (§Ported behavior, row 3) states
that applying EXIF orientation is the deliberate fix for a bug in the Python
original, and that getting it wrong "would put the 'top-left' crop on the
physical bottom-right." Nothing currently verifies this. The whole correctness
of `kCGImageSourceCreateThumbnailWithTransform` plus `max(pixelWidth, pixelHeight)`
rests on it, and it is testable in the simulator — it does not need the open
device gate.

### Implementation

Append to `final class EbayListingPhotoExportTests`:

```swift
    /// EXIF orientation 6 (rotate 90° CW on display) must be baked in during
    /// the single decode. If it were not, the exported crops would come from
    /// the wrong physical corners and the full image would be transposed.
    func testRotatedSourceIsUprightedBeforeCroppingAndIsNotPassedThrough() async throws {
        // 100 wide x 140 tall stored, tagged .right, so the upright image is
        // 140 wide x 100 tall.
        let stored = try XCTUnwrap(cornerFixtureImage(width: 100, height: 140).cgImage)
        let data = try jpegData(for: stored, orientation: .right)

        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: data,
            backData: data
        )
        defer {
            EbayListingPhotoExport.removeRun(
                at: output.urls.first?.deletingLastPathComponent()
            )
        }

        // The full image is transcoded, never passed through, because the
        // stored bytes are not upright.
        XCTAssertNotEqual(try Data(contentsOf: output.urls[0]), data)
        XCTAssertEqual(output.pixelDimensions[0].width, 140)
        XCTAssertEqual(output.pixelDimensions[0].height, 100)
        // 02-Front-TL is Int(140 * 0.60) x Int(100 * 0.60).
        XCTAssertEqual(output.pixelDimensions[1].width, 84)
        XCTAssertEqual(output.pixelDimensions[1].height, 60)
    }

    /// Reuses the four-corner colour fixture so the orientation test asserts on
    /// a source whose corners are individually identifiable.
    private func cornerFixtureImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let w = width / 3
            let h = height / 3
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            UIColor.green.setFill()
            context.fill(CGRect(x: width - w, y: 0, width: w, height: h))
            UIColor.blue.setFill()
            context.fill(CGRect(x: width - w, y: height - h, width: w, height: h))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 0, y: height - h, width: w, height: h))
        }
    }

    private func jpegData(
        for image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: 0.95,
                kCGImagePropertyOrientation: orientation.rawValue
            ] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
```

Add `import CoreGraphics` to the file's imports if the build reports
`CGImagePropertyOrientation` as unresolved (it is normally reachable through
`ImageIO`, which is already imported).

**Acceptance:** both assertions on transposed dimensions pass, proving the
transform is applied during the single decode and that the crops are taken from
the upright frame.

---

## F6 — Temporary roots are never swept across app launches

**Severity:** low-medium (unbounded temp growth; individual runs are large).

**Where:** [`EbayListingPhotoExport.RunDirectoryStore.beginRun`](../TradingCardScanner/Services/EbayListingPhotoExport.swift#L490)
and [`makeBatchDirectory`](../TradingCardScanner/Services/EbayListingPhotoExport.swift#L93).

**Why it is a defect:** `RunDirectoryStore` only remembers `previousDirectory`
for the lifetime of the process. If the app is force-quit, jetsammed, or crashes
while a run or batch exists, that directory and any `.zip` beside it are
orphaned. iOS purges `tmp` only under storage pressure, and each orphan can be
hundreds of megabytes of native-resolution JPEGs. The `.onDisappear` cleanup in
the view does not cover process death.

### Implementation

In `TradingCardScanner/Services/EbayListingPhotoExport.swift`, add this method
to the enum, immediately before `removeRun(at:)` (line 189):

```swift
    /// Deletes everything both temporary roots hold. Call once per app launch:
    /// a run that ended in a crash or jetsam leaves native-resolution JPEGs
    /// behind that no in-process bookkeeping can reclaim.
    static func removeOrphanedTemporaryDirectories() {
        for name in ["EbayListingPhotos", "EbayListingPhotoBatches"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
            removeRun(at: root)
        }
    }
```

Call it once, before any export can start. In
`TradingCardScanner/Views/EbayListingPhotosView.swift`, add a launch-scoped flag
and invoke it from the view's first appearance. Add to the `@State` block near
line 52:

```swift
    @State private var hasSweptTemporaryDirectories = false
```

and add this modifier to `body`, directly above the existing `.onDisappear` at
line 146:

```swift
        .onAppear {
            guard !hasSweptTemporaryDirectories else { return }
            hasSweptTemporaryDirectories = true
            // Safe here: nothing in this screen has produced output yet, and
            // both roots are owned exclusively by this feature.
            EbayListingPhotoExport.removeOrphanedTemporaryDirectories()
        }
```

**Ordering requirement:** this must run before `prepareSingle` can create a run
directory. `.onAppear` fires before `.task(id:)` performs any asynchronous work,
and `prepareSingle` returns immediately unless both `frontData` and `backData`
are already set — which cannot be true on first appearance. Do not move this
call into `beginRun`, which would delete a live sibling run.

**Acceptance:** entering the screen deletes any leftover
`tmp/EbayListingPhotos` and `tmp/EbayListingPhotoBatches` trees, and a
subsequent export in the same session still succeeds.

---

## F7 — Dead stored property on `CenteringCameraView`

**Severity:** low (cleanup only; include it with F3 since it touches the same file).

**Where:** [`TradingCardScanner/Views/CenteringCameraView.swift:264`](../TradingCardScanner/Views/CenteringCameraView.swift#L264).

`let configuration: CenteringCameraConfiguration` is assigned in `init` and never
read in `body`. The value is only needed by the controller, which already
receives it through its own initializer.

### Implementation

Delete line 264:

```swift
    let configuration: CenteringCameraConfiguration
```

and delete the corresponding assignment in `init` (line 271):

```swift
        self.configuration = configuration
```

Leave the `configuration` **parameter** on `init` — it is the public entry point
and is exercised by `UncoveredSurfaceTests`. Leave the `@StateObject` wrapper
construction untouched.

**Acceptance:** `CenteringCameraView(configuration: .listingPhotos, onCapture: { _ in })`
still compiles, and `UncoveredSurfaceTests.ViewConstructionSmokeTests` passes.

---

## Execution order and verification

Apply in this order; F1 and F2 are independent, F3 and F7 touch one file, F4
touches one file, F5 and F6 depend on F1–F4 being in place.

1. F2 (one-line change plus its test) — smallest, and it unblocks realistic
   large-image testing for everything else.
2. F1 (export service + two call sites).
3. F4 (view controls).
4. F3 and F7 together (`CenteringCameraView.swift`).
5. F5 (tests).
6. F6 (temp sweep).

After each step:

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

After the final step, run the focused suites:

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TradingCardScannerTests/EbayQuadrantCropperTests -only-testing:TradingCardScannerTests/EbayListingPhotoExportTests -only-testing:TradingCardScannerTests/ViewConstructionSmokeTests test
```

Expected: the existing 27 tests still pass, plus the two new export tests
(`testOversizedSourceStepsBelowQualityPointSevenFiveInsteadOfFailing`,
`testRotatedSourceIsUprightedBeforeCroppingAndIsNotPassedThrough`).

**Do not** merge to `main`, refresh centering evidence, or mark any gate in
`docs/plans/pro_tab_ebay_listing_photos_plan.md` as closed. The F3 acceptance
check in particular needs hardware and belongs to the already-open device gate.
Record F1–F7 as addressed in that plan's Slice B/C acceptance sections only once
the build and focused suites above are green.
