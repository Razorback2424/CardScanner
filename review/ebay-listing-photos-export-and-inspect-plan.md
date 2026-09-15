# Implementation plan — ZIP export, Save to Photos, and full-resolution inspection

**Base:** `pro-implementation` with Slices A–C and fixes F1–F7 / N1–N3 applied.
**Source:** two gaps reported from the live app — no ZIP option and no
save-to-Photos option in single-card mode, and tapping a result photo does
nothing.

**Decisions already taken (do not revisit):**

- "Export to CSV" was a misstatement; the request is **ZIP**. No CSV work here.
- The inspector decodes at a **4096 px cap** on the long edge, not native
  resolution. That is ~2x the pixel density of the largest iPhone screen and
  keeps peak memory near 50 MB instead of ~195 MB for a 48 MP source. True
  native pixels stay reachable through Share → Files.
- **Save to Photos is single-card mode only.** Photos discards both filenames
  and folder grouping; folder grouping is the entire value of a batch, so the
  batch deliverable stays the ZIP. The existing footnote already warns about
  filenames and becomes actionable once the button exists.

**Three slices. D and E are independent of F. D2 is a prerequisite for D1 —
see the note in D1.**

---

## Slice D — ZIP export for single-card mode

### Why this is not a one-line change

`makeBatchArchive` already produces a ZIP, so single mode could reuse it as-is.
It must not, for a reason visible only when the archive is opened:
`NSFileCoordinator` with `.forUploading` zips *the directory it is given*, and
the archive's single top-level entry is that directory's own name. Both run
directories are named with a raw `UUID().uuidString`, so today's **batch** ZIP
already expands to a folder like `9F3C1A8E-…-B77D/Card-01/`. Shipping a single
-card ZIP with the same shape would hand the user a UUID folder containing
their ten photos.

D2 therefore renames the packaging layer first, and fixes the existing batch
archive at the same time.

### D2 — Give every run a friendly archive root

**New layout.** Each run gets a UUID *container* whose child is a
human-readable *content directory*; the archive is built beside the content
directory, inside the same container. Deleting the container cleans everything
for that run in one call.

```
tmp/EbayListingPhotos/<uuid>/eBay Listing Photos/01-Front.jpg …
tmp/EbayListingPhotos/<uuid>/eBay Listing Photos.zip
tmp/EbayListingPhotoBatches/<uuid>/eBay Listing Photos/Card-01/01-Front.jpg …
tmp/EbayListingPhotoBatches/<uuid>/eBay Listing Photos.zip
```

**Step D2.1.** In `TradingCardScanner/Services/EbayListingPhotoExport.swift`,
add these members directly below `previewMaximumPixelDimension` (line 12):

```swift
    /// The folder name every archive expands to. `NSFileCoordinator`'s
    /// `.forUploading` zips the directory it is handed and names the archive's
    /// single root entry after it, so this name — not a UUID — is what the
    /// person who opens the ZIP sees.
    static let archiveRootName = "eBay Listing Photos"
```

**Step D2.2.** Add a container helper and an `Output` convenience. Put the
helper immediately above `removeRun(at:)`, and the convenience inside
`struct Output` after `reducedQualityNames`:

```swift
    /// The UUID directory that owns a content directory, its card folders, and
    /// any archive built beside it. Deleting it cleans up the whole run.
    static func container(of contentDirectory: URL) -> URL {
        contentDirectory.deletingLastPathComponent()
    }

    /// Deletes the whole run container that owns `contentDirectory`.
    static func removeRunContainer(forContentDirectory contentDirectory: URL?) {
        guard let contentDirectory else { return }
        removeRun(at: container(of: contentDirectory))
    }
```

```swift
        /// Where the ten files live. Every file in `urls` shares this parent.
        var contentDirectory: URL? { urls.first?.deletingLastPathComponent() }
```

**Step D2.3.** Rewrite `makeBatchDirectory()` (currently line 97) to create the
container-plus-content pair and return the content directory:

```swift
    /// Creates the temporary package used by the batch workflow and returns the
    /// directory the card folders go into. Its parent is the run container.
    static func makeBatchDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EbayListingPhotoBatches", isDirectory: true)
        do {
            let directory = root
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(archiveRootName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            throw Error.writeFailed(name: "the batch directory (\(error.localizedDescription))")
        }
    }
```

**Step D2.4.** Rewrite `RunDirectoryStore.beginRun()` the same way. Replace its
whole body with:

```swift
        func beginRun() throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("EbayListingPhotos", isDirectory: true)
            do {
                if let previousContainer {
                    do {
                        try FileManager.default.removeItem(at: previousContainer)
                    } catch {
                        // A prior run may already have been cleaned by the view.
                    }
                }
                let container = root
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let directory = container
                    .appendingPathComponent(archiveRootName, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                previousContainer = container
                return directory
            } catch {
                throw EbayListingPhotoExport.Error.writeFailed(name: "the temporary listing-photo directory")
            }
        }
```

and rename its stored property from `private var previousDirectory: URL?` to
`private var previousContainer: URL?`.

**Step D2.5.** Rename the archive API so it reads correctly for both modes, and
point it at the container. In `EbayListingPhotoExport.swift`:

- Rename `makeBatchArchiveSynchronously(at:)` → `makeArchiveSynchronously(at:)`
  and `makeBatchArchive(at:)` → `makeArchive(at:)`, updating the one internal
  call site inside the async wrapper.
- Inside `makeArchiveSynchronously`, the `archiveURL` line already resolves to
  `<container>/<archiveRootName>.zip` once D2.3/D2.4 land, because
  `deletingLastPathComponent()` of the content directory is now the container.
  **Leave that line unchanged** — verify it reads:

```swift
        let archiveURL = batchDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(batchDirectory.lastPathComponent).zip")
```

  and rename its parameter label from `batchDirectory` to `contentDirectory`
  throughout both functions for accuracy.

**Step D2.6.** Point every cleanup call site at the container. These are the
complete set — change all of them and no others.

In `EbayListingPhotoExport.swift`:

| Location | Current | Replacement |
| --- | --- | --- |
| `makeListingPhotos` catch block | `removeRun(at: directory)` | `removeRun(at: container(of: directory))` |
| `moveOutputSynchronously`, success tail | `if let sourceDirectory = output.urls.first?.deletingLastPathComponent() { removeRun(at: sourceDirectory) }` | `removeRunContainer(forContentDirectory: output.contentDirectory)` |

Leave `moveOutputSynchronously`'s `catch` branch calling
`removeRun(at: cardDirectory)` **unchanged** — `cardDirectory` is a per-card
folder inside the batch, not a run container.

In `TradingCardScanner/Views/EbayListingPhotosView.swift`:

| Location | Current | Replacement |
| --- | --- | --- |
| `prepareSingle`, superseded-result branch | `EbayListingPhotoExport.removeRun(at: output.urls.first?.deletingLastPathComponent())` | `EbayListingPhotoExport.removeRunContainer(forContentDirectory: output.contentDirectory)` |
| `removeSingleArtifacts` | `EbayListingPhotoExport.removeRun(at: singleOutputDirectory)` | `EbayListingPhotoExport.removeRunContainer(forContentDirectory: singleOutputDirectory)` |
| `processBatch`, all four cleanup sites | `EbayListingPhotoExport.removeBatch(directory: directory, archive: batchArchiveURL)` | `EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)` |
| `processBatch`, archive-failure catch | `EbayListingPhotoExport.removeRun(at: directory)` | `EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)` |
| `removeBatchArtifacts` | `EbayListingPhotoExport.removeBatch(directory: batchDirectory, archive: batchArchiveURL)` | `EbayListingPhotoExport.removeRunContainer(forContentDirectory: batchDirectory)` |

In `TradingCardScannerTests/EbayQuadrantCropperTests.swift`, every `defer` block
that reads:

```swift
            EbayListingPhotoExport.removeRun(
                at: output.urls.first?.deletingLastPathComponent()
            )
```

becomes:

```swift
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
```

**Step D2.7.** `removeBatch(directory:archive:)` now has no callers. Delete it.
Confirm with `grep -rn "removeBatch" --include='*.swift' .` before deleting; the
only remaining hits should be none.

### D1 — Build and offer the single-card ZIP

**Step D1.1.** Add state to `EbayListingPhotosView`, next to
`singleOutputDirectory` (line 61):

```swift
    @State private var singleArchiveURL: URL?
```

**Step D1.2.** Build the archive at the end of a successful single export. In
`prepareSingle`, replace:

```swift
            singleOutput = output
            singleOutputDirectory = output.urls.first?.deletingLastPathComponent()
            isPreparingSingle = false
```

with:

```swift
            singleOutput = output
            singleOutputDirectory = output.contentDirectory
            isPreparingSingle = false
            await buildSingleArchive(generation: generation, directory: output.contentDirectory)
```

and add this method directly below `prepareSingle`:

```swift
    /// Builds the shareable ZIP for a finished single-card export. The ten
    /// loose files stay shareable even if this fails, so a zip failure is
    /// reported without discarding the export.
    private func buildSingleArchive(generation: Int, directory: URL?) async {
        guard let directory else { return }
        do {
            let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
            // The archive worker is not cancellation-aware and finishes even
            // when this run was superseded, so re-check before publishing it.
            guard !Task.isCancelled, generation == singleGeneration else {
                EbayListingPhotoExport.removeRun(at: archive)
                return
            }
            singleArchiveURL = archive
        } catch {
            guard generation == singleGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
```

The post-await generation re-check is the same defect class as N1. Do not omit
it.

**Step D1.3.** Clear the archive with the rest of the single-mode artifacts. In
`removeSingleArtifacts`, add after the `removeRunContainer` call:

```swift
        singleArchiveURL = nil
```

No separate delete is needed: the archive lives inside the run container that
`removeRunContainer` just deleted.

**Step D1.4.** Replace the single-mode toolbar item (currently lines 98–105)
with a menu that exposes all three exports:

```swift
            if mode == .single, let singleOutput, singleOutput.urls.count == 10 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let singleArchiveURL {
                            ShareLink(item: singleArchiveURL) {
                                Label("Export ZIP", systemImage: "doc.zipper")
                            }
                        }
                        ShareLink(items: singleOutput.urls) {
                            Label("Export 10 Photos Individually", systemImage: "photo.on.rectangle")
                        }
                        Button("Export 10 Photos to Photos App", systemImage: "square.and.arrow.down") {
                            saveSingleOutputToPhotos()
                        }
                        .disabled(isSavingToPhotos)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Export listing photos")
                }
            }
```

`ShareLink` inside a `Menu` is supported on the iOS 17 deployment target.
`saveSingleOutputToPhotos` and `isSavingToPhotos` arrive in Slice E — if you are
landing D before E, stub the button out and add it with E rather than shipping a
menu item that does nothing.

**Step D1.5.** Rename the batch toolbar label for symmetry. Change
`Label("Share batch archive", systemImage: "square.and.arrow.up")` to
`Label("Export batch ZIP", systemImage: "doc.zipper")` and its
`accessibilityLabel` to `"Export the batch ZIP"`.

### D — Acceptance

- Single mode: after an export, the toolbar menu offers **Export ZIP**, **Export
  10 Photos Individually**, and **Export 10 Photos to Photos App**.
- Both ZIPs expand to a folder named `eBay Listing Photos`, not a UUID. Verify
  by AirDropping to a Mac and double-clicking, or with
  `unzip -l <archive>.zip | head`.
- Leaving the screen leaves no `EbayListingPhotos` or `EbayListingPhotoBatches`
  content behind — check with
  `xcrun simctl get_app_container <device> <bundle-id> data` and inspect `tmp/`.

---

## Slice E — Save to Photos

### E1 — Usage description

In `TradingCardScanner/Info.plist`, add directly after the existing
`NSCameraUsageDescription` pair:

```xml
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>Save prepared eBay listing photos to your photo library.</string>
```

Add-only access needs `NSPhotoLibraryAddUsageDescription`, not
`NSPhotoLibraryUsageDescription`. Do not add the read key — the app reads photos
through `PhotosPicker`, which needs no entitlement at all, and adding the read
key would widen the permission prompt for no reason.

### E2 — The saver

Create `TradingCardScanner/Services/ListingPhotoLibrarySaver.swift`:

```swift
import Foundation
import Photos

/// Adds finished listing photos to the user's photo library, in listing order.
/// Kept separate from `EbayListingPhotoExport` so the export pipeline stays
/// free of photo-library authorization and its UI-facing failure modes.
enum ListingPhotoLibrarySaver {
    enum SaveError: Swift.Error, LocalizedError {
        case notAuthorized
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Photos access is off. Turn on Add Photos Only for this app in Settings to save listing photos."
            case let .saveFailed(reason):
                return "The listing photos could not be saved to Photos: \(reason)"
            }
        }
    }

    /// Adds every URL as a photo asset. Throws without writing anything if the
    /// user declines, and writes all or nothing otherwise: `performChanges`
    /// applies the whole block atomically.
    static func save(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }

        // Photos orders by creation date, and assets added inside one change
        // block otherwise land on the same timestamp in an arbitrary order.
        // Spacing them one second apart is what preserves 01…10 in the
        // library, since the numbered filenames themselves are not kept.
        let base = Date()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (index, url) in urls.enumerated() {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    // The export owns these files and deletes them itself.
                    options.shouldMoveFile = false
                    options.originalFilename = url.lastPathComponent
                    request.addResource(with: .photo, fileURL: url, options: options)
                    request.creationDate = base.addingTimeInterval(Double(index))
                }
            }
        } catch {
            throw SaveError.saveFailed(error.localizedDescription)
        }
    }
}
```

### E3 — Wiring

**Step E3.1.** Add state to `EbayListingPhotosView`, below `singleArchiveURL`:

```swift
    @State private var isSavingToPhotos = false
    @State private var saveConfirmation: String?
```

**Step E3.2.** Add the action method, directly below `buildSingleArchive`:

```swift
    private func saveSingleOutputToPhotos() {
        guard let singleOutput, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        saveConfirmation = nil
        errorMessage = nil
        let urls = singleOutput.urls
        let generation = singleGeneration
        Task {
            do {
                try await ListingPhotoLibrarySaver.save(urls)
                guard generation == singleGeneration else { return }
                isSavingToPhotos = false
                saveConfirmation = "Saved 10 photos to Photos in listing order."
            } catch {
                guard generation == singleGeneration else { return }
                isSavingToPhotos = false
                errorMessage = error.localizedDescription
            }
        }
    }
```

**Step E3.3.** Surface progress and confirmation in `singleContent`. Directly
above the existing `if let errorMessage` block, insert:

```swift
                if isSavingToPhotos {
                    ProgressView("Saving to Photos…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let saveConfirmation {
                    Text(saveConfirmation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
```

**Step E3.4.** Clear the confirmation whenever the single output is replaced.
Add `saveConfirmation = nil` to `beginLoading(side:)`, `receiveCameraCapture`,
and `startOverSingle`, beside the existing `errorMessage = nil` line in each.

### E — Acceptance

- First tap shows the system add-only prompt with the Info.plist string.
- Declining shows the `notAuthorized` message and writes nothing.
- Accepting writes ten assets; opening Photos → Recents shows them in 01…10
  order, oldest first.
- Photo-library permission cannot be unit tested. This is a **manual gate** and
  belongs with the existing open device gates — do not mark it closed from a
  simulator run.

---

## Slice F — Tap a photo to inspect it

### F1 — Capped inspection decode

In `TradingCardScanner/Services/EbayListingPhotoExport.swift`, add the constant
beside `previewMaximumPixelDimension`:

```swift
    /// The inspector's decode ceiling on the long edge. Roughly twice the pixel
    /// density of the largest iPhone screen, so a fitted image is already
    /// oversampled and stays sharp through the zoom range a corner check needs,
    /// while peak memory stays near 50 MB instead of the ~195 MB a 48 MP source
    /// would cost. Raise this only with a device memory check.
    static let inspectionMaximumPixelDimension = 4096
```

Add the loader beside `makeInputPreview` (after line 90):

```swift
    /// Decodes one exported file for on-screen review, capped at
    /// `inspectionMaximumPixelDimension`. Reads through a URL-backed image
    /// source so the JPEG is streamed from disk instead of being loaded whole.
    static func makeInspectionImage(at url: URL) async throws -> UIImage {
        let worker = Task.detached(priority: .userInitiated) {
            try inspectionImageSynchronously(at: url)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
```

and the worker beside `inputPreviewSynchronously`:

```swift
    private static func inspectionImageSynchronously(at url: URL) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Error.decodeFailed(side: url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: inspectionMaximumPixelDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Error.decodeFailed(side: url.lastPathComponent)
        }
        return UIImage(cgImage: image)
    }
```

### F2 — The inspector view

Create `TradingCardScanner/Views/ListingPhotoInspectorView.swift`:

```swift
import SwiftUI
import UIKit

/// Full-screen review of one exported listing photo. The zoom and pan gestures
/// mirror `CardCenteringView.imageReview` so the two Pro tools behave the same
/// way under the finger.
struct ListingPhotoInspectorView: View {
    let url: URL
    let nativeDimensions: EbayListingPhotoExport.PixelDimensions

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loadError: String?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    private var isDownsampled: Bool {
        max(nativeDimensions.width, nativeDimensions.height)
            > EbayListingPhotoExport.inspectionMaximumPixelDimension
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(panOffset)
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoom = min(6, max(1, lastZoom * value.magnification))
                                }
                                .onEnded { _ in
                                    lastZoom = zoom
                                    if zoom == 1 {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard zoom > 1 else { return }
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    if zoom > 1 {
                                        lastPanOffset = panOffset
                                    } else {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoom = zoom > 1 ? 1 : 3
                                panOffset = .zero
                            }
                            lastZoom = zoom
                            lastPanOffset = .zero
                        }
                        .accessibilityLabel("\(url.deletingPathExtension().lastPathComponent), \(nativeDimensions.width) by \(nativeDimensions.height) pixels")
                } else if let loadError {
                    ContentUnavailableView(
                        "Cannot Open Photo",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack {
                    Spacer()
                    caption
                }
            }
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                image = try await EbayListingPhotoExport.makeInspectionImage(at: url)
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var caption: some View {
        VStack(spacing: 3) {
            Text("\(nativeDimensions.width) × \(nativeDimensions.height) px")
                .font(.caption.monospacedDigit())
            if isDownsampled {
                Text("Shown at reduced size for review. Share → Files keeps every pixel.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.bottom, 24)
    }
}
```

### F3 — Make the grid cells tappable

**Step F3.1.** Add the presentation model and state to `EbayListingPhotosView`.
Put the struct beside `BatchProgress` (line 47):

```swift
    private struct InspectedPhoto: Identifiable {
        let id: Int
        let url: URL
        let dimensions: EbayListingPhotoExport.PixelDimensions
    }
```

and the state below `saveConfirmation`:

```swift
    @State private var inspectedPhoto: InspectedPhoto?
```

**Step F3.2.** Wrap each grid cell in a button. In `outputGrid`, replace the
`ForEach` body's opening `VStack(alignment: .leading, spacing: 5) {` and its
closing brace so the cell content sits inside a `Button`:

```swift
                ForEach(output.urls.indices, id: \.self) { index in
                    Button {
                        inspectedPhoto = InspectedPhoto(
                            id: index,
                            url: output.urls[index],
                            dimensions: output.pixelDimensions[index]
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            // … existing Image / Text / Text cell body, unchanged …
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this photo for full-size review")
                }
```

Leave the cell body exactly as it is — only the wrapper changes.
`.buttonStyle(.plain)` is required; without it the captions pick up the accent
tint.

**Step F3.3.** Present the inspector. Add beside the existing
`.fullScreenCover(item: $cameraSide)`:

```swift
        .fullScreenCover(item: $inspectedPhoto) { photo in
            ListingPhotoInspectorView(
                url: photo.url,
                nativeDimensions: photo.dimensions
            )
        }
```

`fullScreenCover(item:)` builds a fresh view per presentation, so zoom and pan
start at rest every time without an explicit reset.

**Step F3.4.** Dismiss the inspector when its file is about to be deleted. Add
`inspectedPhoto = nil` as the first line of `removeSingleArtifacts()`. Without
this, tapping **Start Over** while the inspector is open leaves it displaying an
image whose backing file has been removed.

### F — Acceptance

- Tapping any of the ten cells opens a full-screen view; pinch zooms to 6x,
  double-tap toggles 3x, drag pans only while zoomed, Done dismisses.
- The caption shows the true native pixel dimensions, and the reduced-size note
  appears only for images above 4096 px on the long edge.
- Opening the 48 MP full-front image does not spike memory past ~60 MB in the
  Xcode memory gauge.

---

## Project registration

Two new files need target membership in
`TradingCardScanner.xcodeproj/project.pbxproj`. Follow the existing explicit-ID
convention; `A0010113`–`A0010116` and `B0010113`–`B0010116` are taken, so use:

| File | Build file ID | File ref ID | Group | Sources phase |
| --- | --- | --- | --- | --- |
| `Services/ListingPhotoLibrarySaver.swift` | `A0010117` | `B0010117` | Services (beside `B0010114`) | app target |
| `Views/ListingPhotoInspectorView.swift` | `A0010118` | `B0010118` | Views (beside `B0010116`) | app target |

Add one `PBXBuildFile`, one `PBXFileReference`, one group child entry, and one
`PBXSourcesBuildPhase` entry per file, matching the shape of the `B0010114` /
`A0010114` lines already present.

---

## Tests

Add to `final class EbayListingPhotoExportTests` in
`TradingCardScannerTests/EbayQuadrantCropperTests.swift`:

```swift
    /// The archive expands to a readable folder name. Before the packaging
    /// change it expanded to the run's raw UUID.
    func testArchiveIsNamedForItsContentDirectoryNotTheRunUUID() async throws {
        let sourceData = try jpegData(for: try XCTUnwrap(sourceFixture().cgImage))
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        let directory = try XCTUnwrap(output.contentDirectory)
        XCTAssertEqual(directory.lastPathComponent, EbayListingPhotoExport.archiveRootName)

        let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
        XCTAssertEqual(
            archive.lastPathComponent,
            "\(EbayListingPhotoExport.archiveRootName).zip"
        )
        // The archive sits inside the run container, so one delete cleans both.
        XCTAssertEqual(
            archive.deletingLastPathComponent(),
            EbayListingPhotoExport.container(of: directory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    /// The inspector decode is capped and keeps the source's aspect ratio.
    func testInspectionImageIsCappedOnTheLongEdge() async throws {
        let sourceData = try jpegData(for: try XCTUnwrap(sourceFixture().cgImage))
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        let image = try await EbayListingPhotoExport.makeInspectionImage(at: output.urls[0])
        // The fixture is far below the cap, so it comes back at native size.
        XCTAssertEqual(Int(image.size.width), 100)
        XCTAssertEqual(Int(image.size.height), 140)
        XCTAssertLessThanOrEqual(
            Int(max(image.size.width, image.size.height)),
            EbayListingPhotoExport.inspectionMaximumPixelDimension
        )
    }
```

Do **not** add a large-image cap test — that is what made the earlier byte-budget
test take 179 seconds. The cap is a single `kCGImageSourceThumbnailMaxPixelSize`
value; assert the plumbing, not ImageIO's behaviour.

Add to `ViewConstructionSmokeTests` in
`TradingCardScannerTests/UncoveredSurfaceTests.swift`, beside the existing
`_ = EbayListingPhotosView()`:

```swift
        _ = ListingPhotoInspectorView(
            url: URL(fileURLWithPath: "/dev/null"),
            nativeDimensions: EbayListingPhotoExport.PixelDimensions(width: 100, height: 140)
        )
```

---

## Execution order and verification

1. **D2** (packaging) — nothing user-visible, but it touches every cleanup call
   site. Land and test it alone before anything else.
2. **D1** (single ZIP + menu), with the Save-to-Photos item stubbed.
3. **E** (Photos), which fills in the stub.
4. **F** (inspector).

After each step:

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

After the final step:

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TradingCardScannerTests/EbayQuadrantCropperTests -only-testing:TradingCardScannerTests/EbayListingPhotoExportTests -only-testing:TradingCardScannerTests/ViewConstructionSmokeTests test
```

Expected: the existing 14 tests plus the two new export tests, all green, and
the whole file still well under 15 seconds.

**Gates that stay open.** Save-to-Photos authorization, the ZIP round trip on a
real device, and 48 MP inspector memory all need hardware. Do not mark them
closed from a simulator run, do not merge to `main`, and do not refresh
centering evidence. `docs/plans/pro_tab_ebay_listing_photos_plan.md` should gain
these three items as new Slice D/E/F acceptance rows once the build and focused
suites above are green.
