# Collection tile — quantity, artwork resolution, footer, finish badges

Historical implementation plan. The investigation below is retained because
it explains the design tradeoffs, but the collection-tile recommendations have
landed in the current code and were exercised by the deterministic
`CollectionTiles` route. Current evidence/status is summarized in
[`documentation_audit.md`](documentation_audit.md); this file is not a live
unchecked work queue.

Two of the four turned out to have a shared root cause worth fixing once, and
the investigation surfaced a separate latent memory hazard that is present
today and unrelated to the reported issues. That is called out in §2.

---

## 1 — The `×2` badge

**What it does now.** `CollectionCardTile` overlays the badge on the artwork at
`.topTrailing` (`CollectionView.swift:966-975`):

```swift
AppCardBadge(text: "×\(row.quantity)", systemImage: "number", tint: .teal)
```

Three separate problems, all visible in the Radagast capture:

- `systemImage: "number"` renders an SF `#` glyph, so the badge reads **`# ×2`**.
  The `×` already says "quantity"; the `#` is noise and reads as a card number.
- `AppCardBadge`'s background is translucent (`CollectionCardDetailView.swift:962`,
  material unless Reduce Transparency), so busy artwork shows through. On
  Radagast it lands on the mana cost and the two collide.
- Top-trailing is where every Magic card puts its own mana cost, so the badge
  covers the card's most recognisable corner.

**Fix.** Move it into the footer badge row (see §3), drop `systemImage`
entirely, keep the teal tint. `×2` on an opaque footer needs no material and
never fights the art.

**Trade being accepted:** quantity is slightly less glanceable when scanning a
long grid, because it is no longer in a fixed corner position. In exchange it is
always legible. This is the reported preference.

**Same-rule sites:** `PortfolioView.swift:928` and `:972` use the identical
`systemImage: "number"` quantity badge. Drop the glyph there too so the
vocabulary stays one thing.

---

## 2 — Artwork resolution, and what it costs

### The measurement

`CollectionCardArtwork` deliberately requests the thumbnail
(`CollectionView.swift:1117-1121`), with a comment arguing the full-size asset
is "megabytes per tile for no visible gain". That was true of the old tile size;
it is not true now.

- Grid: `GridItem(.adaptive(minimum: 165), spacing: 16)` inside `.padding(12)`
  (`CollectionView.swift:174`, `:411`). On a 402 pt-wide iPhone that is two
  columns of ~181 pt → **~543 device pixels** at 3×.
- `row.lowImageURL` for Magic is Scryfall `small`, documented **146 × 204**.
  That is being upscaled **~3.7×**. This is exactly the blur reported.
- `row.highImageURL` is Scryfall `normal`, **488 × 680** — a 0.9× fit for a
  543 px slot, i.e. effectively native.

So shrinking the presentation does not rescue `small`: even at three columns
(~120 pt → 360 px) it is still a 2.5× upscale. **The tile has to move to
`normal`.**

### What that costs, honestly

`CatalogImageCache.image(for:)` (`BrowseView.swift:1379-1392`) does
`UIImage(data:)` — a **full-resolution decode with no downsampling** — and
costs the entry at `bytesPerRow * height`.

| | decoded bitmap | cached at 60 objects |
|---|---|---|
| `small` 146×204 | ~0.12 MB | ~7 MB |
| `normal` 488×680 | ~1.33 MB | ~80 MB, over the 48 MB cost limit |

`NSCache` is `countLimit 60`, `totalCostLimit 48 MB` (`BrowseView.swift:1357-1362`).
At `normal` the cost limit binds first, holding ~36 images instead of 60, so
scrolling a large collection re-decodes more often. Disk is capped at 60 MB with
5 MB per asset (`:1350-1351`); `normal` JPEGs are ~10× `small`, so the disk cache
holds roughly 450 cards' art instead of several thousand. First paint of each
tile also transfers ~10× the bytes.

None of that is fatal, and none of it is a reason to keep a blurry grid. But
swapping the URL alone leaves the real defect in place, which is that **nothing
in this app downsamples at decode**.

### The structural fix, which pays for the change

Replace `UIImage(data:)` with `CGImageSourceCreateThumbnailAtIndex` +
`kCGImageSourceThumbnailMaxPixelSize`, decoding to the pixel size the consumer
actually draws, and key the cache on `(url, targetPixelSize)`. That bounds every
consumer independently and fixes two existing wrongs at once:

- **Portfolio decodes at full size for a tiny slot.** `PortfolioHoldingSnapshot`
  takes `card.highImageURL` as primary (`PortfolioReplaySnapshot.swift:138`) and
  `PortfolioArtwork` draws it at **34 × 46 pt** (`PortfolioView.swift:1035`).
  That is a ~1.33 MB decode for a ~102 × 138 px slot. The app currently gets
  resolution wrong in *both* directions — Collection under-fetches, Portfolio
  over-decodes.
- **User artwork is an unbounded decode, today.** `CollectionArtworkStore.save`
  writes the original Photos `Data` with no resize or recompression
  (`CollectionCardDetailView.swift:2522-2531`), and `image(filename:)` does
  `UIImage(contentsOfFile:)` — full resolution
  (`:2541-2543`). A 48 MP photo set as custom artwork decodes to roughly
  **190 MB** for one 181 pt tile. The `NSCache` cost limit evicts it afterwards,
  but the allocation happens first. This is a present crash risk on the grid,
  independent of everything else on this list, and it is the strongest argument
  for doing the downsampling work rather than only swapping a URL.

**Net expectation:** Collection goes from ~0.12 MB to ~1.3 MB per visible tile
(unavoidable — it is the price of a sharp image), Portfolio drops from ~1.33 MB
to ~0.06 MB per row, and user artwork stops being unbounded. Total footprint
should land at or below today's.

**Sequencing:** land the downsampling cache **before** the URL swap, so the
grid's step up in resolution arrives with the bound already in place. Retune
`totalCostLimit` from measurement, not by guess.

**Also fix while here:** `CollectionArtworkStore.save` should downscale and
re-encode to a sane maximum (the detail hero's need, roughly 1600 px on the long
edge) before writing. Storing a 48 MP original serves nothing.

---

## 3 — The footer

**What it does now** (`CollectionView.swift:977-1042`) — five full-width,
left-aligned rows of near-equal weight:

```
Radagast of Rhosgobel        .headline, up to 2 lines
$5.44                        PriceLabel .compact — also headline weight
The Hobbit  ·  HOB  ·  136   .subheadline .secondary, up to 2 lines
[✨ Foil]                     badges, inside a horizontal ScrollView
[⚠ reason]                   .caption, up to 2 lines
```

Specific faults, each visible in one of the two captures:

1. **No hierarchy.** Name and price are both headline-weight; the identity line
   at `.subheadline` is barely smaller. Four stacked full-width rows at the same
   optical weight read as a list, not a card.
2. **The identity line wraps.** In The One Ring capture, `The Hobbit Eternal ·
   HOC · 84` breaks to a second line and orphans `· 84`.
3. **Set name leads with the least identifying token.** `HOC · 84` identifies the
   printing; the set name is the part that can be dropped, yet it is first and
   takes the width.
4. **`"  ·  "` — double-spaced middots.** This is the specific typographic tell
   behind "feels very 1999".
5. **A horizontal `ScrollView` nested in a grid cell inside a vertical
   `ScrollView`** (`:995`). Gesture conflict, and badges can sit off-tile with no
   affordance that they exist.
6. **Ragged tile heights.** Name 1–2 lines, identity 1–2, badges 0–1, reason
   0–2, with `alignment: .top` — so neighbouring tiles never line up.

**Proposed layout:**

```
Radagast of Rhosgobel          name  .subheadline.weight(.semibold), lineLimit(2), reserved height
HOB · 136 · The Hobbit         .caption .secondary, lineLimit(1), single-spaced middots
$5.44            [Foil] [×2]   price .title3.weight(.semibold).monospacedDigit + trailing badges
```

- **Name steps down** from `.headline` to `.subheadline.semibold`. It is a grid
  cell, not a section header, and it should stop competing with the price.
- **Price steps up** and becomes the largest thing in the footer, with
  `monospacedDigit` so a column of prices aligns down the grid.
- **Identity collapses to one line**, reordered to `code · number · set name` so
  the set name is what truncates. Single-spaced `·`.
- **Badges move onto the price line, trailing.** This is where `×2` lands from
  §1, and after §4 there is normally exactly one finish/treatment badge beside
  it. Replace the nested `ScrollView` with a wrapping layout that clips rather
  than scrolls.
- **Reserve the name's two-line height** so tiles align across a row.
- **Unpriced reason** becomes a compact badge in the same trailing row rather
  than a fifth full-width line, capped at one line.
- **Dynamic Type:** at accessibility sizes, `ViewThatFits` drops the badges to
  their own line under the price rather than shrinking either.

---

## 4 — `Foil` and `Surge Foil` together

**Why it happens.** The tile draws the finish badge and the treatment badges as
two independent loops (`CollectionView.swift:1000-1029`): `row.variant` produces
`Foil`, and `row.displayedMagicTreatmentEvidence.displayLabels` produces
`Surge Foil`.

**Why it is safely fixable.** The model already knows the implication:
`MagicTreatment.requiredFinish` returns `.foil` for both `.surgeFoil` and
`.neonInk`, and `nil` for `.unclassified` (`MagicTreatment.swift:50-57`).
`applicableTreatments(for:)` (`:141-147`) already guarantees a displayed
treatment is compatible with the owned finish.

**Rule:** suppress the finish badge when any displayed treatment's
`requiredFinish` equals `row.variant`. Surge Foil and Neon Ink then render
alone; an `.unclassified` treatment has no known finish relationship, so both
badges stay — which is the existing, deliberate "never guess a finish" position
in that file's comments.

This is a display rule only. It must **not** touch
`displayedMagicTreatmentEvidence`, `applicableTreatments`, or anything that
feeds pricing identity — treatment-qualified price keys stay exactly as they
are.

**Same-rule site:** `IdentifiedCard.finishAndTreatmentDisplayLabel(for:)`
(`Models/TCGdexCard.swift:852-862`) composes the same redundant pair as a
string (`"Foil · Surge Foil"`). The current implementation applies the same
implication rule there, so the scanner and grid no longer describe one card two
ways. The wording above is retained as the historical problem statement.

---

## Sequencing

1. §4 badge rule — smallest, self-contained, no layout risk. **Landed.**
2. §1 quantity badge into the footer row.
3. §3 footer rebuild — subsumes 1 and 2's placement, so land them first and
   move the finished badge row wholesale.
4. §2a downsampling image cache keyed by target size, plus the artwork-save
   downscale.
5. §2b Collection grid primary `low → high`, and Portfolio's `high → low` for
   its 34 pt thumb, both only after 4 is in.

## Verification

- Deterministic captures on the Collection route in light, dark, and
  accessibility-large, for: a plain card, a Surge Foil card, `×2`, an unpriced
  card, and a long set name. Compare against the two reported captures.
- Confirm tile heights align across a grid row after the reserved-height change.
- Allocations instrument on a scroll through a large collection before and after
  §2, recording peak decoded-image bytes. The claim to prove is that total
  footprint does not exceed today's despite the grid's higher resolution.
- A unit test on the §4 rule: `.surgeFoil` + `.foil` yields one badge;
  `.unclassified` + `.foil` yields two.
- Existing suite stays green (873 tests, 1 skipped at time of writing).

## Implementation record — 2026-09-07

The quantity/footer hierarchy, finish/treatment suppression, target-sized
artwork decoding, bounded local artwork storage, and `CollectionTiles` QA route
were implemented. Focused treatment/downsampling tests, dark/light and
accessibility-large captures, and the current full simulator suite pass. Any
future cache-limit tuning belongs in the measurement gates in
[`release_followups.md`](release_followups.md), not as an implied unfinished
collection-tile slice.
