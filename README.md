# Trading Card Scanner MVP

A deliberately small iPhone MVP for identifier-first Pokémon card scanning.

## Core loop

Camera → Vision OCR → printed set code + collector number → TCGdex → visual validation → save to SwiftData collection.

## MVP scope

- iPhone, portrait orientation
- English Pokémon cards with modern printed expansion codes
- Scarlet & Violet through the current Mega Evolution-era sets in `SetCodeMap.swift`
- Internet connection required for TCGdex metadata, prices, and images
- No artwork recognition
- No accounts, cloud sync, manual search, old set-symbol recognition, foil recognition, or eBay comps

## Apple frameworks

- **AVFoundation**: live camera frames
- **Vision**: `VNRecognizeTextRequest`, `.accurate`, custom Pokémon set-code vocabulary, fixed scan ROI
- **SwiftUI**: interface
- **SwiftData**: local collection

## Run it

1. Open `TradingCardScanner.xcodeproj` in Xcode.
2. Select the `TradingCardScanner` target and choose your Apple Development team under Signing & Capabilities.
3. Connect a real iPhone. The camera scanner is not useful in the Simulator.
4. Build and run.
5. Grant camera permission.
6. Place the printed set code and collector number inside the yellow scan box.

## Current fast/accurate behavior

- Captures at 1080p.
- Starts OCR no more often than about every 240 ms; actual throughput is also limited by Vision's `.accurate` processing time.
- Uses Vision's `.accurate` recognition mode.
- Biases OCR with all supported printed set codes through `customWords`.
- Accepts common merged OCR output such as `OBF223/197` and narrow O/0 or I/L/1 number confusions.
- Requires the printed denominator to match the known set size.
- Confirms after **two matching candidates within the last four OCR passes**, so one missed frame does not reset progress.
- Pauses OCR while a result is being shown or fetched.
- Shows a warning haptic and one-line diagnostic if a confirmed identifier fails its TCGdex lookup.
- Defines the scan region once in Vision portrait coordinates, then explicitly rotates it into AVFoundation metadata coordinates for the visible yellow overlay.

The two main scan-tuning values are in `Services/CardScanner.swift` and `CandidateConfirmationWindow`:

```swift
private let minimumVisionInterval: CFAbsoluteTime = 0.24
private var confirmationWindow = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)
```

Do not tune them until real-card testing shows a speed or accuracy problem.

## Pricing

The app does not yet identify physical finish. If TCGdex exposes more than one TCGplayer market price, the result screen labels each available price (Normal, Holofoil, Reverse Holofoil) instead of guessing which one was scanned.

The TCGdex request uses normal HTTP cache validation so pricing can refresh rather than being pinned to the first cached response.

## Tests

`TradingCardScannerTests` is app-hosted and imports the `TradingCardScanner` module, so the tests exercise the same compiled parser code used by the app. Coverage includes:

- standard identifiers
- merged set-code/number OCR
- regulation-mark merges
- `l`/`1` confusion
- leading-zero local IDs
- current Mega Evolution set mappings
- illustrator-name substring rejection (for example, `MASCAGNI` must not match `ASC`)
- line-preserving set-code/number pairing and ambiguous two-card rejection
- zero collector-number rejection
- denominator rejection
- rolling confirmation with OCR misses

## Adding a set

Add one row to `Services/SetCodeMap.swift` with:

- printed three-letter code
- TCGdex set ID
- official denominator printed on the card

That automatically adds the code to Vision's custom vocabulary as well.

## TCGdex

The app calls:

`https://api.tcgdex.net/v2/en/sets/{setID}/{localID}`

Card images use TCGdex's PNG asset variants.

## First device run: confirm the ROI transform

`ScanRegion.metadataRect(fromVisionRect:)` assumes a particular rotation direction for
`.right`-oriented frames. Apple's wording admits the opposite reading, so confirm it before
trusting any OCR results.

In a DEBUG build the preview draws green boxes around every text observation Vision returns.
Those boxes are ground truth: they should sit directly on the printed words in the preview.

1. Set `ScanRegion.calibrationUsesFullFrameROI = true` in `Services/CardScanner.swift`.
   This widens Vision's ROI to the whole frame, so text is reported everywhere. Without it,
   a mirrored transform aims the ROI at the wrong end of the card, Vision finds nothing, and
   the overlay draws no boxes at all — no signal in exactly the failure case being diagnosed.
2. Run and point the camera at a card.
   - Green boxes land on the words: the transform is correct.
   - Green boxes are mirrored to the wrong vertical end: switch to the alternate transform
     documented in the comment on `metadataRect(fromVisionRect:)`.
3. Set the flag back to `false` and confirm the yellow band now sits over the identifier strip.

Vision normalizes observation bounding boxes against the request's `regionOfInterest`, not the
full frame. `ScanRegion.fullFrameVisionRect(fromObservationBoundingBox:in:)` maps them back
before conversion; that scaling is the identity only when the ROI is the full frame.

## Important MVP limitation

The scan region is still fixed rather than doing card-edge detection. That is deliberate. The first real-world test should focus on whether the identifier is read quickly and reliably under normal lighting, sleeves, glare, different card finishes, and a range of supported iPhones.
