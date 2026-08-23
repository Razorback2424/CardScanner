# Trading Card Scanner

A high-throughput, high-trust collection intake system for iPhone. The camera and
OCR are the mechanism; the product is being able to move through a stack of cards
rhythmically while the software stays out of the way.

## Three principles

**Fast.** Speed comes from removing interactions that carry no information and
from overlapping work, never from deciding earlier.

**Accurate.** When the app can know, it acts. When it cannot, it asks for the
smallest possible piece of human information. It never guesses to appear
confident.

**A joy to use.** Certainty determines friction: high certainty is zero friction,
one missing human fact is one tap, low certainty is no mutation at all.

Every interaction has to pass one test — *does this give the system information it
does not already have?* If not, it is removed.

## Scanner

### The acceptance pipeline

```
OCR observation
      ↓  card latch          (is this a new physical presentation?)
plausible identifier ────────→ speculative catalog fetch
      ↓  rolling confirmation (two matches inside four passes)
      ↓  latch admission      (has the consumed card really left?)
identity established
      ↓  catalog validation   (does the record agree with the print?)
      ↓  variant resolver
      ├── deterministic → auto-add
      └── genuinely ambiguous → one inline tap → add
      ↓
receipt · recent rail · latched
```

Externally that is: card → tick → card → tick → card → tap → tick.

### Never pausing

Recognition does not stop on success. There is no result screen, no confirm step
and no dismiss animation between cards — card two is already being read while
card one's receipt is still on screen. `Services/CardLatch.swift`, not a pause, is
what stops one card being counted twice. Recognition pauses only while an
unanswered finish choice is on screen, because accepting another card could
otherwise replace the one question that still needs a human answer.

### The card latch

`CardLatch` turns a stream of OCR readings back into physical events.

- A continuously visible printing can be added exactly once, no matter how many
  times it is read.
- The latch releases only on evidence the card changed: the identifier stops
  being read for several consecutive passes, or a *different* card confirms. One
  stray reading is never enough, because a single garbage frame releasing the
  latch would let the card still sitting there be added twice.
- Two identical copies back to back are deliberately not solved optically. The
  first has to leave before the second is accepted. A missed card costs one more
  pass; a phantom duplicate quietly corrupts a five-thousand-card collection.
- When the same card has been sitting in the band for a while, the scanner says
  so rather than silently ignoring it.

### Hiding network latency

`Services/CardCatalog.swift` starts a catalog request the moment an identifier is
*plausible*, while Vision is still looking for its second matching pass. The cost
becomes `max(confirmation, network)` instead of their sum, with no reduction in
accuracy: a speculative result is only ever consumed by the exact identifier that
was confirmed, and a speculation that turns out to be a misread is inert. Cards
already resolved this session need no round trip at all.

### Finish resolution

The pipeline is not `identify → add`. It is:

```
exact printing → possible physical variants → trusted evidence → resolved, or one tap
```

`Services/VariantResolver.swift` asks which variants the printing *physically
exists in*, never what the shiny thing looks like. In order:

1. catalog uniqueness → auto-resolve
2. a set-specific rule this app owns narrows to one → auto-resolve
3. Finish Lock names a variant the catalog agrees is possible → auto-resolve
4. two or more remain → ask, with one tap that means *this variant and save it*

There is no probability threshold anywhere in that list. Optical finish
recognition may one day *rank* the options under the user's thumb; it may not
answer for them.

**Finish Lock** is contextual evidence the user supplies — a stack of Master Ball
parallels really is a fact about the cards on the table. It is not an override:
the catalog stays authoritative about what is physically possible, and a lock
that does not apply produces the options plus an explanation.

**The supplemental rules layer** (`PokemonVariantRules`) carries physical facts
TCGdex does not model, such as the Poké Ball and Master Ball parallels. Each row
is a claim about printed product and needs verifying against real cards. Being
wrong by *adding* a variant costs one tap; being wrong by *omitting* one silently
writes the wrong finish into the collection.

### Provenance

Records store *why*, not only *what*:

- `identityResolution` — how identity was established (printed identifier)
- `variantResolution` — `uniqueInCatalog`, `deterministicSetRule`, `finishLock`,
  `userConfirmed`, `catalogSilent`

These are two different facts. Identity can be certain from printed identifiers at
the same moment the finish is a hand-made choice. If a rule is later found to be
incomplete, every record that leaned on it can be found and reassessed without
disturbing the ones a person confirmed.

### The accuracy policy

- Automatic identity requires validated identifier evidence *and* a real catalog
  match.
- Automatic finish assignment requires deterministic evidence.
- Appearance alone can never confirm a finish.
- One continuously visible printing cannot increment quantity more than once.
- Two simultaneous valid identifiers are ambiguous and are rejected, not ranked.
- A network response cannot override contradictory OCR evidence.
- No amount of confidence may invent a physically impossible variant.

## Collection

The scanner reduces friction according to certainty. The collection reduces it
according to intent. Four chips and one sort menu answer nearly every question a
collector actually asks, and **none of them touch the network** — filtering and
sorting are local computation over data already loaded.

```
Collection                              428 cards
$12,482.17 priced value
Prices current as of 1:42 PM                    ↻

[ Game ] [ Set ] [ Price ] [ Finish ]     Sort ↕
```

### One entry per owned physical variant

The collection contains entries, not cards. A Master Ball copy and a reverse holo
copy of PRE 074/131 share a printing identity but are separate rows: different
prices, filtered separately, independent quantities.

```
CollectedCard (one owned physical variant)
      │ printing + variant
      ▼
PriceRecord (market price · source · source updated · fetched)
```

A card does not cost $42 forever. What is true is that a physical variant's
latest known market price was $42 as of a moment, from a source. That is a
mutable observation with its own lifecycle, and it is shared by every copy owned —
eight copies are one price to refresh, not eight.

### Filters

- **Game** is the first-level namespace. Choosing Pokémon means the Set and Finish
  filters offer Pokémon choices.
- **Set** and **Finish** list only what the collection actually contains, with
  counts, and allow multi-selection.
- **Price** is the current market price of *one copy*: ten copies of a $2 card is
  still a $2 card. Bands rather than a slider, because card prices are
  distributed far too unevenly for a slider to land anywhere useful. Custom
  min/max covers the rest.

They compose. Pokémon → Prismatic Evolutions → Master Ball → $10–25 is a
sophisticated inventory query built from four taps and no search syntax. The
header always says `17 of 428` while filters are active, and the priced value
follows the filter.

### Sorting

`Card Number`, `Set + Card Number`, `Price: High to Low`, `Price: Low to High`.

- Collector numbers are not integers. `CollectorNumber` splits a leading prefix, a
  number and a suffix, so `009` sorts before `010` and `GG01` before `GG10`.
- `Set + Card Number` groups by game, then by set in release order newest first,
  then binder order within each set. Pokémon release indexes and Magic release
  dates live on different scales and are never compared against each other.
- Unpriced cards sink to the bottom of *both* price sorts. Unknown is not
  worthless.

### The pricing promise

- **Never substitute another finish's price.** A price belongs to
  `printing + variant`. TCGdex's current pricing object exposes normal, holofoil
  and reverse-holofoil; a Master Ball parallel has no listing of its own, so it
  reads `Price unavailable` rather than borrowing the reverse holo's number.
- **Never present a stale price as current.** Two timestamps are stored and they
  mean different things: `sourceUpdatedAt` is when the market data is current
  through, `fetchedAt` is when this app looked. A price checked at 3:20pm whose
  data is from 1:07pm is *current as of 1:07pm*. Providers that publish no
  timestamp of their own (Scryfall) only ever earn "checked at".
- **Never call a check an update.** A refresh that finds no newer market data says
  exactly that.
- **Never replace a real price with nothing.** A failed refresh keeps the previous
  price, labelled with its real age, and notes the failure.
- **Never fold unknowns into a total.** The header shows priced value plus a count
  of what was left out.

Price states are distinct: current · stale · unavailable · not checked · refresh
failed.

### Refreshing

Automatic when the collection appears and the last check is more than 8 hours old
— quietly, in the background, with existing prices visible the whole time. There
is no blank grid and no blocking spinner. Manual via the header button or
pull-to-refresh. Refresh is per unique printing-and-variant, limited to four
concurrent requests, in display order so what the user is looking at becomes
fresh first.

Scanning and price refreshing are never in the same critical path. The core
transaction is *I own this physical card*; pricing is secondary mutable metadata
that rides along in the catalog response the identification already made.

## Apple frameworks

- **AVFoundation** — live camera frames, macro (ultra wide) lens selection
- **Vision** — `VNRecognizeTextRequest`, `.accurate`, set-code vocabulary, fixed ROI
- **SwiftUI** — interface
- **SwiftData** — local collection and price records

## Run it

1. Open `TradingCardScanner.xcodeproj` in Xcode.
2. Select the `TradingCardScanner` target and choose your team under Signing &
   Capabilities.
3. Connect a real iPhone. The scanner is not useful in the Simulator.
4. Build, run, grant camera permission.
5. Put the printed set code and collector number inside the green scan box.

## Scan tuning

The two main values are in `Services/CardScanner.swift`:

```swift
private let minimumVisionInterval: CFAbsoluteTime = 0.24
private var confirmationWindow = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)
```

Do not tune them until real-card testing shows a speed or accuracy problem. Note
that recognition now runs continuously rather than pausing between cards, so the
duty cycle is higher than it was; if battery becomes a problem, the interval is
the lever.

`CardLatch`'s two constants are the duplicate-protection budget:

```swift
CardLatch(releaseAfterAbsences: 4, minimumAbsenceBeforeRelatch: 1.2)
```

Raising either makes duplicates harder and back-to-back identical copies slower.

## Adding a set

Add one row to `Services/SetCodeMap.swift` with the printed three-letter code, the
TCGdex set ID, the official denominator, and its release index. That also adds the
code to Vision's custom vocabulary.

If the set prints parallel patterns TCGdex does not model, add a row to
`PokemonVariantRules` as well — after checking real cards.

## Tests

`TradingCardScannerTests` is app-hosted and imports the `TradingCardScanner`
module, so it exercises the same compiled code the app runs.

- `ScanParserTests` — identifiers, merged OCR, `l`/`1` confusion, illustrator-name
  rejection, two-card ambiguity, denominators, rolling confirmation
- `CardLatchTests` — the duplicate-protection guarantees, written as the physical
  situations they stand for
- `VariantResolverTests` — the finish hierarchy, Finish Lock as evidence rather
  than override, the supplemental rules layer
- `CollectionKeyTests` — catalog decoding, variant rows, legacy key preservation
- `CollectionQueryTests` — natural collector-number order, filter composition,
  unit-price semantics, unpriced sorting
- `PricingTests` — the pricing promise, freshness states, refresh scheduling

## First device run: confirm the ROI transform

`ScanRegion.metadataRect(fromVisionRect:)` assumes a particular rotation direction
for `.right`-oriented frames. Apple's wording admits the opposite reading, so
confirm it before trusting any OCR results.

In a DEBUG build the preview draws green boxes around every text observation
Vision returns. Those boxes are ground truth: they should sit directly on the
printed words.

1. Set `ScanRegion.calibrationUsesFullFrameROI = true` in
   `Services/CardScanner.swift`. This widens Vision's ROI to the whole frame.
   Without it, a mirrored transform aims the ROI at the wrong end of the card,
   Vision finds nothing, and the overlay draws no boxes at all — no signal in
   exactly the failure case being diagnosed.
2. Run and point the camera at a card.
   - Boxes land on the words: the transform is correct.
   - Boxes are mirrored to the wrong vertical end: switch to the alternate
     transform documented on `metadataRect(fromVisionRect:)`.
3. Set the flag back to `false` and confirm the green band sits over the
   identifier strip.

Vision normalizes observation bounding boxes against the request's
`regionOfInterest`, not the full frame.
`ScanRegion.fullFrameVisionRect(fromObservationBoundingBox:in:)` maps them back.

## Known limits

- The scan region is fixed rather than doing card-edge detection. Deliberate: the
  first real-world test should be about whether the identifier is read quickly and
  reliably under normal lighting, sleeves, glare, and different finishes.
- `PokemonVariantRules` currently claims Poké Ball and Master Ball parallels for
  `sv08.5`, `sv10.5b` and `sv10.5w`. Verify against physical product.
- The persisted entity is still named `CollectedCard` even though it models an
  owned physical variant. Renaming a SwiftData entity needs a versioned schema
  migration, which is not worth risking a local collection over.
- Magic prices come from Scryfall, which publishes no per-price timestamp, so
  Magic prices can only ever be reported as "checked at".
