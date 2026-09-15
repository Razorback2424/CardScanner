# Pro tab — card centering and eBay listing photos

**Status:** current plan — proposed 2026-09-15, revised 2026-09-15, **not
implemented**. No code in this plan has landed; every acceptance box below is
open. The source-behavior claims in *Ported behavior* were read from
`/Users/seankeller/Documents/eBay Photos/process_and_organize.py` on 2026-09-15
(that tool is a separate, unversioned working copy outside this repository and
is not a dependency of this app).

**Concern owned:** the tab that today shows only card centering becomes a **Pro**
tab hosting several seller tools, and the first new tool in it generates the ten
eBay listing photos (a full front, four overlapping front corner crops, a full
back, four overlapping back corner crops) for a card, at the source photo's
native resolution.

**Code owned:** the `Tab` enum, `TabView`, and debug-route switch in
[`ContentView.swift`](../../TradingCardScanner/Views/ContentView.swift);
[`CardCenteringView.swift`](../../TradingCardScanner/Views/CardCenteringView.swift)
(navigation-container refactor only);
[`CenteringCameraView.swift`](../../TradingCardScanner/Views/CenteringCameraView.swift)
(capture-configuration parameter only); and the new `ProView`,
`EbayListingPhotosView`, `EbayQuadrantCropper`, and `EbayListingPhotoExport`
files listed per slice.

This plan does not restate the centering contract. The active centering
accuracy, invariant, latency, and device gates stay in
[`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md);
this plan changes where that screen is *presented* and adds a parameter to the
camera it shares, never how it measures. Both changes are recorded in
*Reconciliation*.

---

## Product shape

The Pro tab is a module list, not a single screen. Its root is one
`NavigationStack` whose content is a short list of tools, each pushing a full
screen:

| Module | Status after this plan | Source |
| --- | --- | --- |
| Card Centering | existing behavior, moved one level deeper | `CardCenteringView` |
| eBay Listing Photos | new | `EbayListingPhotosView` |

Both modules share one contract: **capture or pick images → derive an artifact →
share it out**. Neither writes to the collection, and neither takes a
`CollectedCard`. The eBay module is card-independent by decision, not by
deferral: a user preparing a listing may not have the card in their collection
yet, and the ten images are consumed by eBay's uploader immediately.

---

## Resolution policy

**The outputs are native-resolution slices of the source photo. Nothing is
downscaled, upscaled, or resampled.** A crop is a rectangular region of the
decoded source pixels, re-encoded once as JPEG. A 48 MP front photo yields a
48 MP full front and four ~17.6 MP corner crops.

This is a firm constraint, and it is what makes the corner crops worth taking:
their whole purpose is to show edge wear and surface defects that a resampled
image destroys. Three consequences are designed for rather than worked around:

1. **Memory.** A 48 MP image decodes to roughly 195 MB of RGBA. The pipeline
   therefore holds **one decoded side at a time** and never materializes ten
   decoded images. `CGImage.cropping(to:)` returns a lazy view that retains its
   parent without copying pixels, so each crop costs only its encode buffer.
   Peak footprint is one parent plus one encode, independent of how many crops
   or (in Slice C) how many pairs are queued.
2. **One decode, already oriented.** Baking EXIF orientation with a
   `UIGraphicsImageRenderer` redraw would allocate a second full-size buffer.
   Instead, read `kCGImagePropertyPixelWidth`/`PixelHeight` via
   `CGImageSourceCopyPropertiesAtIndex`, then decode through
   `CGImageSourceCreateThumbnailAtIndex` with
   `kCGImageSourceCreateThumbnailWithTransform: true` and
   `kCGImageSourceThumbnailMaxPixelSize` set to `max(pixelWidth, pixelHeight)`.
   ImageIO applies the transform and **does not upscale**, so this returns the
   full-resolution, correctly-oriented image in a single buffer. Using `max` of
   both dimensions also sidesteps the width/height swap that EXIF orientations
   5–8 introduce. This is the same ImageIO idiom as
   `CollectionArtworkStore.downsampledImage`
   ([`CollectionCardDetailView.swift:2459`](../../TradingCardScanner/Views/CollectionCardDetailView.swift:2459)),
   with the cap raised to the image's own size instead of a display bound.
3. **File size, not pixel size, is the pressure valve.** eBay enforces a
   per-image file-size ceiling on upload. If a native-resolution JPEG exceeds
   the configured byte budget, **reduce JPEG quality, never dimensions** —
   stepping `0.95 → 0.85 → 0.75` and stopping at the first encode that fits.
   Record which outputs, if any, were re-encoded below 0.95 so a quality
   question later has an answer. The exact eBay ceiling is not asserted here;
   confirming the current published limit is a task in *Verification*.

**The two full images avoid re-encoding entirely where possible.** Outputs 01
and 06 are the source photos unmodified. When the source is already JPEG *and*
its EXIF orientation is `.up`, copy the original file bytes verbatim — no
decode, no re-encode, no generation loss. Transcode only when the source is
HEIC (eBay does not accept it) or carries a non-identity orientation.

---

## Ported behavior (what the Python tool actually does)

The web worker always calls `process_scans(..., use_full_frame=True)`. That
branch (`process_and_organize.py:1352-1470`) skips contour detection,
perspective warp, OCR, and the Pokémon TCG API lookup entirely; the only pixel
work it performs is writing the untouched front and back plus
`create_quadrant_crops` on each (`process_and_organize.py:1216-1240`):

```python
ratio = max(0.5, min(0.9, float(crop_ratio)))   # 0.60 front, 0.63 back
crop_w, crop_h = int(W * ratio), int(H * ratio) # truncation, not rounding
TL: (0,        0,        crop_w, crop_h)
TR: (W-crop_w, 0,        W,      crop_h)
BR: (W-crop_w, H-crop_h, W,      H)
BL: (0,        H-crop_h, crop_w, H)
```

That geometry is ported exactly, truncation included. Five places where this
plan knowingly differs, and why:

| # | Python | This plan | Why |
| --- | --- | --- | --- |
| 1 | Clamps the ratio into `[0.5, 0.9]` and silently skips a degenerate quadrant | Throws outside `0.5...0.9`; throws on a degenerate crop | A primitive that quietly rewrites its caller's argument hides mistakes. The two production ratios are unaffected. |
| 2 | JPEG at OpenCV's default quality 95 | Quality 0.95, with the size-driven step-down above | Parity, plus a defined behavior at eBay's upload ceiling. |
| 3 | `cv2.imread(..., IMREAD_UNCHANGED)` ignores EXIF, so a rotated phone photo crops rotated | Orientation applied during the single decode | The original is wrong here; reproducing the bug would put the "top-left" crop on the physical bottom-right. |
| 4 | Writes `Card_0001_FRONT_TL.jpg` into per-card folders, delivers a zip | Numbered names `01-Front.jpg` … `10-Back-BL.jpg` | eBay uploads in arrival order. Files and AirDrop preserve names; Photos does not, and the UI says so. |
| 5 | Processes many front/back pairs per job (`photo_prep_app/app.py` tracks `pair_count` / `processed_pairs`) | Slice B does one pair; Slice C adds batching | Batching is a real part of the workflow, scheduled rather than dropped. |

Not ported, at any horizon: contour/multi-card detection, perspective warp,
OCR, Pokémon-TCG auto-naming, the job database. All are dead in the tool's
production path, and porting them would add CV/OCR dependencies for behavior the
user never exercises.

---

## Slice A — the Pro tab shell

**Goal:** the fourth tab is "Pro", centering is reachable from inside it, and no
centering behavior, route, or evidence script changes meaning.

### A1. `CardCenteringView` gives up its navigation container

`CardCenteringView.body` currently owns a `NavigationStack`
([`CardCenteringView.swift:332`](../../TradingCardScanner/Views/CardCenteringView.swift:332)).
Pushed into the Pro tab's stack it would nest one stack inside another.

- Move the `NavigationStack { … }` wrapper out of `CardCenteringView`. Keep
  `.navigationTitle("Centering")`, the keyboard `ToolbarItemGroup`, the trailing
  `ShareLink`/camera/photo/file toolbar items, every `.sheet`, the file
  importer, and all `#if DEBUG` hooks exactly where they are — a pushed view
  contributes those to the enclosing stack unchanged.
- Add `.navigationBarTitleDisplayMode(.inline)` so the pushed title does not
  fight the Pro root's large title.
- The screen must still compile standalone for previews and for the debug
  route; if any existing caller relies on it being self-contained, wrap that
  call site rather than reinstating the inner stack.

### A2. `ProView` (new, `Views/ProView.swift`)

```swift
struct ProView: View {
    private enum Module: Hashable { case centering, ebayPhotos }
    @State private var path: [Module] = []
    ...
}
```

- One `NavigationStack(path:)` with `.navigationTitle("Pro")`.
- Body is a `List` of module rows, each a `NavigationLink(value:)` with a
  `Label` (SF Symbol + title) and a one-line `Text` subtitle in `.secondary`.
  Follow the existing list/row idiom in `ScannerSettingsView` rather than
  inventing a card style, and apply `.contentWidthLimit(.standard)` as the other
  scrolling roots do.
- `.navigationDestination(for: Module.self)` maps `.centering` →
  `CardCenteringView()` and `.ebayPhotos` → `EbayListingPhotosView()`.
- The Settings toolbar button currently on the centering screen stays there; the
  Pro root adds no toolbar of its own in this slice.
- Module rows come from one `static let modules: [Module]` array so a third tool
  is a one-line addition.

### A3. `ContentView` wiring

In [`ContentView.swift`](../../TradingCardScanner/Views/ContentView.swift):

- Rename `Tab.centering` → `Tab.pro`.
- Replace the fourth tab's content with `ProView()`, its `tabItem` label with
  `Label("Pro", systemImage: "wand.and.stars")`, and its tag with `Tab.pro`.
  Any SF Symbol is acceptable; `square.dashed.inset.filled` must **not** be
  reused, since it is the centering module's own icon one level down.
- In the `init()` debug-route switch
  ([`ContentView.swift:70`](../../TradingCardScanner/Views/ContentView.swift:70)),
  keep `"Centering", "CenteringExpanded"` mapped to the renamed case. **Do not
  rename the route strings** — `scripts/centering_ui_build_and_shoot.sh:49`
  passes `-ui_debug_route CenteringExpanded`, and the centering evidence ledger
  is keyed to those names.

### A4. Deep-link the debug routes past the module list

The centering screenshot script settles on a view that is now one push deeper.
In `ProView`, add a `#if DEBUG` initial-path seed: when `-ui_debug_route` is
`Centering` or `CenteringExpanded`, initialize `path = [.centering]`. Read the
argument in `init()`, matching how `ContentView` and `CardCenteringView` already
read `ProcessInfo.processInfo.arguments`, so the push happens before first
render rather than in an `onAppear` the screenshot could race.

### A5. Xcode project registration

`TradingCardScanner.xcodeproj` is `objectVersion = 56` — no
filesystem-synchronized groups. Every new `.swift` file in this plan must be
added to the `TradingCardScanner` target (test files to
`TradingCardScannerTests`) with an explicit `PBXBuildFile`/`PBXFileReference`
pair and group membership. A file on disk but absent from the pbxproj compiles
nowhere and fails silently at runtime.

### A6. Slice A acceptance

- [ ] Fourth tab reads "Pro"; tapping it shows the module list.
- [ ] Centering module pushes and behaves identically: analysis, rotation, guide
      editing, export `ShareLink`, camera, photo picker, file importer, Settings.
- [ ] `scripts/centering_ui_build_and_shoot.sh` still produces its settled
      marker and screenshot with no script edit.
- [ ] Focused build plus the existing centering unit tests pass.

---

## Slice B — eBay Listing Photos, one card

**Goal:** from the Pro tab, capture or pick a front and a back photo and hand ten
native-resolution images to the share sheet in listing order. Nothing is written
to SwiftData, the collection, or the schema.

### B1. `Services/EbayQuadrantCropper.swift` (new)

A pure geometry primitive. It computes rects; it never holds decoded images.

```swift
enum EbayQuadrantCropper {
    enum Quadrant: CaseIterable { case topLeft, topRight, bottomRight, bottomLeft }
    enum CropError: Error { case unsupportedRatio, degenerateImage }

    static let frontRatio = 0.60
    static let backRatio = 0.63

    /// Matches the Python original's `int()` truncation exactly.
    static func cropRects(
        imageWidth: Int,
        imageHeight: Int,
        ratio: Double
    ) throws -> [Quadrant: CGRect]

    static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage
}
```

- `cropRects` computes `cropW = Int(Double(imageWidth) * ratio)` and
  `cropH = Int(Double(imageHeight) * ratio)`, then the four integer-origin rects
  in TL, TR, BR, BL order. Throws `.degenerateImage` when either dimension is
  `<= 0` or either crop dimension truncates to `0`; throws `.unsupportedRatio`
  outside `0.5...0.9`.
- `Quadrant.allCases` order **is** the listing order; downstream numbering
  depends on it, so state that in a doc comment.
- `crop(_:to:)` wraps `CGImage.cropping(to:)`, which is a non-copying view of the
  parent — that laziness is the memory strategy, so say so in the doc comment
  and do not "helpfully" force a copy.
- No UIKit, no SwiftData, no file I/O. This is the unit-testable core.

### B2. `Services/EbayListingPhotoExport.swift` (new)

Owns decode, orientation, crop sequencing, JPEG encoding, and temp-file
placement, under the *Resolution policy* above.

```swift
enum EbayListingPhotoExport {
    struct Output: Sendable {
        let urls: [URL]          // 10 file URLs in listing order
        let previews: [UIImage]  // 10 small thumbnails for the grid
        let reducedQualityNames: [String]  // outputs encoded below 0.95, if any
    }
    static func makeListingPhotos(frontData: Data, backData: Data) async throws -> Output
}
```

Requirements:

- **Per side, in sequence:** decode once at native resolution with the transform
  applied (policy §2) → emit the full image (byte passthrough when the source is
  `.up` JPEG, otherwise transcode) → for each quadrant, crop, encode, write,
  release → release the parent before starting the other side. Wrap each output
  in an `autoreleasepool` so ImageIO's buffers drain inside the loop rather than
  at the end of it.
- **Build previews in the same pass**, at ~320 px long edge, so the grid never
  re-decodes a 48 MP file. Previews are the only downscaled images the feature
  produces, and they are never exported.
- **Run off the main actor, moving only `Sendable` values.** `CGImage` is not
  `Sendable`: take `Data` in, return `[URL]` plus already-rendered previews, and
  keep every `CGImage` inside one `Task.detached(priority: .userInitiated)`.
- **Write to a fresh subdirectory of `FileManager.default.temporaryDirectory`**
  (`…/EbayListingPhotos/<UUID>/`), not Application Support. These files exist to
  be handed to the share sheet; they are derived and reproducible and must not
  accumulate in the backed-up container. Delete the previous run's directory
  when a new run starts and on view dismissal.
- **Filenames encode listing order:** `01-Front.jpg`, `02-Front-TL.jpg`,
  `03-Front-TR.jpg`, `04-Front-BR.jpg`, `05-Front-BL.jpg`, `06-Back.jpg`,
  `07-Back-TL.jpg`, `08-Back-TR.jpg`, `09-Back-BR.jpg`, `10-Back-BL.jpg`.
- Errors surface as `CropError` or an `EbayListingPhotoExport.Error` for
  decode/encode/write failure. No `try?` swallowing at this layer.

### B3. Capture path — reuse `CenteringCameraView` with a configuration

An earlier revision of this plan claimed `CenteringCameraView` was too coupled to
the centering overlay to reuse. **That was wrong.** It already exposes exactly
the right interface — `let onCapture: (Data) -> Void`
([`CenteringCameraView.swift:226`](../../TradingCardScanner/Views/CenteringCameraView.swift:226)) —
and its overlay is a generic grid plus a level indicator, both of which help a
listing photo as much as a centering photo. Reuse it, with one configuration
parameter, because two capture configurations genuinely differ:

| | Centering (today) | Listing photos |
| --- | --- | --- |
| Lens | ultra-wide macro when available ([`:142`](../../TradingCardScanner/Views/CenteringCameraView.swift:142)) | **main wide camera** — on 48 MP devices the ultra-wide tops out far lower |
| Photo dimensions | `sessionPreset = .photo` default, ~12 MP | **`photoOutput.maxPhotoDimensions` set to the active format's `supportedMaxPhotoDimensions.max`**, and the same value on each `AVCapturePhotoSettings` |
| Focus range | `autoFocusRangeRestriction = .near` | `.near` is still correct for a card at arm's length |

Add a `CenteringCameraConfiguration` (or similarly named) enum parameter with
cases `.centering` and `.listingPhotos`, defaulting to `.centering` so no
existing call site changes. Deployment target is iOS 17, so `maxPhotoDimensions`
is available unconditionally.

**Without the `maxPhotoDimensions` change the camera path silently captures
12 MP** while the library path delivers 48 MP — the exact resolution loss this
feature exists to avoid. Treat it as required, not as polish.

### B4. `Views/EbayListingPhotosView.swift` (new)

Pushed from `ProView`; takes no parameters.

1. Empty state uses `ContentUnavailableView` with the affordance shape the
   centering screen's empty state already uses
   ([`CardCenteringView.swift:388`](../../TradingCardScanner/Views/CardCenteringView.swift:388)):
   a **Front** slot and a **Back** slot, each offering *Take Photo* (presents
   `CenteringCameraView(configuration: .listingPhotos)`) and *Choose Photo*
   (`PhotosPicker`, `matching: .images`). Show which slots are filled.
2. Both paths produce `Data` — the camera via `onCapture`, the picker via
   `loadTransferable(type: Data.self)`. Hold the raw `Data`, not a `UIImage`:
   `makeListingPhotos` takes `Data`, and this avoids a redundant full-size
   decode on the main actor.
3. Once both sides are present, a `.task(id:)` keyed on a monotonic generation
   counter runs `makeListingPhotos`. Use the cancellation-safe generation idiom
   already in `saveSelectedArtwork`
   ([`CollectionCardDetailView.swift:898`](../../TradingCardScanner/Views/CollectionCardDetailView.swift:898))
   and in `CardCenteringViewModel`'s `loadGeneration`/`analysisGeneration`: a
   result from a superseded generation is discarded and its temp directory
   deleted.
4. While running, `ProgressView("Preparing listing photos…")`.
5. On success, a `LazyVGrid` of the ten previews, each captioned with its export
   name and pixel dimensions (`01 Front · 8064 × 6048`) — the dimensions are the
   feature's promise, so show them. If `reducedQualityNames` is non-empty, note
   it in a footnote.
6. A trailing toolbar `ShareLink(items: urls)`, enabled only when
   `urls.count == 10`, matching the prepared-`exportURL` pattern the centering
   toolbar already uses
   ([`CardCenteringView.swift:435`](../../TradingCardScanner/Views/CardCenteringView.swift:435)) —
   prepare first, let `ShareLink` own the presentation so it anchors correctly
   as a popover on iPad.
7. A one-line note that saving to Photos discards filenames, and that Files or
   AirDrop preserves the numbered upload order.
8. "Start Over" clears both slots, bumps the generation, and deletes the temp
   directory.
9. Failures set `errorMessage`, rendered as the centering screen renders them
   (footnote in `.red` beneath the content), not as an alert — this screen has
   no destructive action to interrupt.
10. `.onDisappear` deletes the run's temp directory. State is intentionally not
    restored across a tab switch in v1.

### B5. `TradingCardScannerTests/EbayQuadrantCropperTests.swift` (new)

Flat file in the existing test target, `XCTest`, `@testable import
TradingCardScanner`, following `CenteringExportTests.swift`'s shape (private
fixture helpers at the top, `// MARK:` sections, a doc comment on each test
saying what behavior it protects).

Because `cropRects` is pure geometry, most cases need no bitmap:

- Truncation matches the original: `1001 × 1401` at `0.60` → `600 × 840`, not
  601/841.
- The four rects for a realistic card frame (`900 × 1260`, ratio `0.60`) sit at
  the expected origins, and TL/TR, TR/BR, BR/BL, BL/TL overlap — overlap is the
  product requirement, so assert it directly rather than inferring it from sizes.
- Front (`0.60`) and back (`0.63`) both produce four rects fully inside bounds.
- A realistic 48 MP frame (`8064 × 6048`, ratio `0.60`) truncates to
  `4838 × 3628` and stays in bounds — the native-resolution case, asserted so a
  future "round instead of truncate" refactor cannot pass silently.
- `Quadrant.allCases` is TL, TR, BR, BL (the listing-order contract).
- Ratios `0.49` and `0.91` throw `.unsupportedRatio`; a zero-size image and a
  ratio truncating a dimension to zero throw `.degenerateImage`.
- One pixel-level test through `crop(_:to:)`: build a synthetic `CGImage` with a
  distinct solid color per corner region (`UIGraphicsImageRenderer`, `scale = 1`,
  as `CenteringExportTests.photo` does), crop each quadrant, and sample its
  outermost corner pixel to confirm the crop came from the corner it claims.
- A crop's pixel dimensions equal its rect's — the no-resampling guarantee,
  asserted at the primitive so the policy has a test and not just a paragraph.

### B6. Slice B acceptance

- [ ] `EbayQuadrantCropperTests` passes.
- [ ] Ten previews render in listing order with correct captions and dimensions.
- [ ] Exported full images match the source pixel dimensions exactly; each corner
      crop matches `Int(dimension × ratio)` exactly. No output is resampled.
- [ ] A JPEG source with `.up` orientation passes its full images through
      byte-for-byte (compare file hashes against the source).
- [ ] Share sheet receives ten items; Files/AirDrop shows the numbered names.
- [ ] Re-running with new photos leaves exactly one temp directory behind;
      leaving the screen leaves none.
- [ ] Camera capture on a 48 MP device produces a 48 MP front (device evidence).
- [ ] A 48 MP HEIC pair completes without memory-pressure termination (device
      evidence).

---

## Slice C — batching

**Goal:** prepare several cards in one pass, as the Python tool's job does.

Deliberately a separate slice: the pairing UI is the whole difficulty, and the
Slice B pipeline is already batch-shaped — sequential, one decoded side at a
time, peak footprint independent of queue length.

- **Input.** One `PhotosPicker` with `maxSelectionCount` unset (or a multi-shot
  camera loop). The user picks an even number of photos; the tool pairs them
  **in selection order**, front-then-back, exactly as the Python job's paired
  inputs do. An odd count is a validation error, not a silent drop.
- **Review before processing.** Show the derived pairs as front/back thumbnail
  rows with a swap control per row, because a mis-paired batch is otherwise
  discovered only in the output. This is the one place iOS should be better
  than the web tool, where pairing is positional and invisible.
- **Processing.** Pairs run strictly sequentially through
  `makeListingPhotos`, with per-pair progress ("Card 3 of 12") and cancellation.
  A failed pair is reported and skipped; the rest of the batch still completes.
- **Output packaging.** Per-card directories named `Card-01`, `Card-02`, … each
  holding the same ten numbered files, mirroring the Python tool's per-card
  folders. For a batch, share **one zip** rather than 10 × N loose files:
  produce it with `NSFileCoordinator`'s `.forUploading` reading intent on the
  batch directory, which yields a zip with no third-party dependency. A
  single-pair run keeps Slice B's loose-file behavior, since eBay's uploader
  takes those directly.
- **Optional naming.** A per-pair text field renaming `Card-03` to the card's
  name, since the folder name is the only label surviving into the zip. The
  Python tool got names from OCR and the TCG API; typing one is strictly more
  reliable and costs no dependency.
- Acceptance: a 12-pair batch completes, peak memory stays at the single-pair
  level (device evidence), the zip contains 12 directories × 10 correctly
  numbered files, and a swapped row lands in the output swapped.

---

## Out of scope

- **Contour/multi-card detection, perspective warp, OCR, Pokémon-TCG
  auto-naming.** Dead in the tool's production path.
- **Persisting photo sets against a `CollectedCard`.** The module is
  card-independent by decision. If it is ever wanted, the shape is a device-local
  `@Model` beside `LocalArtworkOverride`
  ([`CollectedCard.swift:610`](../../TradingCardScanner/Models/CollectedCard.swift:610))
  holding one ordered `[String]` of filenames, registered in
  `CollectionStorageModelSchema.localOnly` and `.full` but **never** `synced`
  ([`CollectionStorageBootstrap.swift:278`](../../TradingCardScanner/Services/CollectionStorageBootstrap.swift:278)),
  with files under Application Support, the write-then-save-then-delete ordering
  of `saveSelectedArtwork`
  ([`CollectionCardDetailView.swift:898`](../../TradingCardScanner/Views/CollectionCardDetailView.swift:898)),
  and — non-negotiably — orphan cleanup on card deletion plus a launch sweep,
  which nothing in the current tree owns.
- **Zip packaging for a single pair.** Loose files upload directly.
- **A crop-ratio preference.** Ratios stay `static let`, matching the original's
  fixed configuration. If per-card-type tuning is wanted,
  `@AppStorage("ebayFrontCropRatio")` / `@AppStorage("ebayBackCropRatio")` would
  follow the `usesPriceFallback` pattern
  ([`ScannerSettingsView.swift:594`](../../TradingCardScanner/Views/ScannerSettingsView.swift:594)).
- **Direct eBay API listing upload.** Out of scope at every horizon here.

---

## Reconciliation

| Document | Change this plan introduces | Action when the slice lands |
| --- | --- | --- |
| [`docs/README.md`](../README.md) | Adds a current authority row for the Pro tab | Added with this plan |
| [`documentation_audit.md`](documentation_audit.md) | Adds a Pro tab row to the authority-boundary table | Added with this plan |
| [`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md) | Centering is presented one level deeper and no longer owns its own `NavigationStack`; its camera gains a configuration parameter that defaults to today's behavior; route strings unchanged | Note the presentation and camera-parameter changes when Slice A/B land. The centering configuration must remain byte-identical in effect — macro lens, `.near` focus restriction, existing preset — or the centering accuracy gates are invalidated. |
| [`scripts/centering_ui_build_and_shoot.sh`](../../scripts/centering_ui_build_and_shoot.sh) | No edit expected — A4 preserves the route's landing screen | Re-run and confirm before claiming Slice A complete |
| [`progress.md`](../../progress.md) | Dated entry per landed slice | Required by [`docs/AGENTS.md`](../AGENTS.md) rule 4 |

---

## Verification

Deterministic, per [`AGENTS.md`](../../AGENTS.md) ("narrowest relevant
`xcodebuild` build/test first"):

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TradingCardScannerTests/EbayQuadrantCropperTests -only-testing:TradingCardScannerTests/CenteringExportTests test
```

Centering-route regression after Slice A:

```bash
./scripts/centering_ui_build_and_shoot.sh
```

Manual (simulator) — records behavior, not release readiness:

1. Pro tab shows both modules; centering pushes and works end to end.
2. Pick a front and a back; confirm ten previews in listing order, each corner
   crop visibly overlapping its neighbors, each full image uncropped.
3. Include a photo shot in landscape and one shot upside down — the orientation
   case the Python original gets wrong. Corner crops must correspond to the
   card's physical corners, not the sensor's.
4. Inspect the exported files: dimensions equal source dimensions and
   `Int(dimension × ratio)` respectively; no output is smaller than its rect.
5. Saving to Files yields `01-Front.jpg` … `10-Back-BL.jpg`.
6. Leave and re-enter the screen; confirm no temp directory survives.
7. Confirm eBay's current published per-image file-size limit and check a
   native-resolution 48 MP JPEG against it; if it exceeds, confirm the quality
   step-down engages and is reported in the UI.

Device-only (**cannot be claimed from the simulator**, per
[`AGENTS.md`](../../AGENTS.md)):

8. Camera capture on a 48 MP device produces a 48 MP image, not 12 MP.
9. A 48 MP HEIC front/back pair completes without memory-pressure termination;
   record peak footprint.
10. (Slice C) A 12-pair batch holds that same peak footprint.

Not claimed by this plan: physical-device, provider, CloudKit, archive, or
release readiness.
