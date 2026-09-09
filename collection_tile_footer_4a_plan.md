# Collection tile footer — direction 4a, "Price leads the quiet line"

Target: `CollectionTileFooter.dc.html` **`#4a`** (lines 26–123 of the third export). Reconciled
against the shipped 2a implementation in `CollectionView.swift` as it stands today.

> 4a's own description: *"Name 18px, set 13px at higher contrast, price 15px on the last line with
> the finish opposite it. Money still starts the line, so the price column stays alignable — it
> simply stops out-shouting the card."*

## Scope: footer only

`CollectionScreen.dc.html` is **byte-identical** between the second and third exports and still
carries all five artwork glows and all five sheens. `CollectionTileFooter.dc.html` is a footer
*typography* study — every direction in it, 4a included, draws plain `rgba(235,235,245,0.08)`
artwork wells because the artwork treatment is not what those directions are comparing.

**So `CollectionArtworkGlow`, `CardFinishOverlay`, `CardFinishMotionSource`, `ArtworkAccentStore`,
and the `artworkAccent` projection field all stay exactly as they are.** Nothing from §4/§5 of the
last pass is undone.

## What actually changes

| | Shipped (2a) | 4a |
| --- | --- | --- |
| Footer rows | 4 fixed-height | **3** — name+identity pair, then one combined line |
| Name | `.subheadline.weight(.semibold)` (15pt), `minHeight: 40` | **18pt semibold**, tracking −0.18, 2-line clamp |
| Identity | `.caption` (12pt) `.secondary`, `setCode · cardNumber` | **13pt medium at 0.75**, **`setName · cardNumber`** |
| Price | 22pt **bold rounded**, own row | **15pt semibold, not rounded**, 0.9 white, shares the last line |
| Quantity | `.footnote` `.secondary` after price | unchanged in kind (13pt at 0.6), same position |
| Unpriced | `—` plus an orange caveat beside it | orange reason **replaces the price**; no em-dash |
| Status | its own row, leading-aligned | **trailing on the price line**, pushed by a spacer |
| Artwork→footer | 12 | **10** |
| Grid row spacing | `LazyVGrid(spacing: 22)` | **28** |
| Dot, status label | 7pt dot, 12pt semibold | unchanged |

Two content reversals worth calling out before anything else:

1. **The set name comes back.** 2a deliberately dropped it (`identityLine` is
   `[setCode, cardNumber]`) because at 165pt it truncated to `The Hobbi…`. 4a puts it back at
   higher contrast and *drops the set code*: the mockup reads `The Hobbit Eternal · 84`,
   `Obsidian Flames · 223`, `Modern Horizons 2 · 138`. It will still truncate on long set names —
   that is now an accepted cost, bought back by the name above it being 18pt instead of 15pt.
2. **The price stops being the loudest thing in the footer.** It drops from 22pt bold rounded to
   15pt semibold in the system face. This undoes `compactPriceFont` and the rounded/portfolio-hero
   kinship that 2a introduced.

---

## 1. Tile body (`CollectionCardTile`, ~line 995–1080)

Outer spacing 12 → **10**. Footer becomes a two-part stack rather than four fixed rows:

```swift
VStack(spacing: 10) {
    artwork                                  // unchanged, keeps .background { CollectionArtworkGlow(…) }

    VStack(alignment: .leading, spacing: 4) {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.name)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.18)                       // −0.01em at 18pt
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: nameMinHeight, alignment: .topLeading)

            Text(identityLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary.opacity(1.25))   // see §2 on the 0.75 shade
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        quietLine
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity)
}
```

`rowHeights` (the `(price: 26, meta: 16)` tuple) is deleted — 4a has no fixed price or meta row.
It is replaced by `nameMinHeight`, see §5.

## 2. The identity line

```swift
private var identityLine: String {
    [row.setName, row.cardNumber]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}
```

`row.setName` is already on `CollectionRow` (`CollectionQuery.swift:13`) and is already read by the
accessibility label, so nothing new is plumbed. The sealed case degrades correctly on its own — the
mockup's sealed tile shows just `Prismatic Evolutions`, which is what the existing
`filter { !$0.isEmpty }` produces when there is no collector number.

**The 0.75 shade needs a real token, not `.secondary.opacity(…)`.** iOS `secondaryLabel` is 0.60 in
light and 0.60 in dark; the mockup wants 0.75 in dark. `.secondary.opacity(1.25)` is not valid —
opacity multiplies down, never up. Add a colour set `TileIdentity` (dark
`rgba(235,235,245,0.75)`, light `rgba(60,60,67,0.75)`) beside the existing `Finish*` sets and use
`Color("TileIdentity")`. This is the same pattern the last pass established for the finish tints.

## 3. The quiet line

```swift
@ViewBuilder
private var quietLine: some View {
    HStack(alignment: .center, spacing: 8) {
        if let caveat = priceReplacementCaveat {
            Text(caveat)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            PriceLabel(price: row.price, style: .tile)
                .fixedSize(horizontal: true, vertical: false)
        }

        if row.quantity > 1 {
            Text("×\(row.quantity)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }

        Spacer(minLength: 4)

        if let status = CollectionFinishStatus.resolve(row: row, showDefaultFinish: showDefaultFinish) {
            HStack(spacing: 5) {
                CollectionFinishDot(style: statusDotStyle(for: status))
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint(for: status))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)          // see below
        }
    }
}
```

`statusRow` is deleted; `CollectionFinishStatus.resolve`, `statusDotStyle(for:)`,
`statusTint(for:)`, `CollectionFinishDot` and every colour set are reused **unchanged**. The status
group's `margin-left:auto` in the mockup is the `Spacer(minLength: 4)`.

⚠️ **Truncation contention is the real risk in this row.** At a 165pt tile the line must fit
`$1,234.56` + `×2` + a 7pt dot + `Reverse holo`. That does not fit, and SwiftUI will shrink whichever
side loses. Decide explicitly rather than letting layout decide:

- Price and quantity are `fixedSize` — they are exact figures and must never truncate.
- The status label carries `.lineLimit(1)` + `.truncationMode(.tail)` and yields first
  (`Reverse holo` → `Reverse ho…`). Giving it `layoutPriority(1)` keeps it from collapsing to
  nothing when the price is long; drop the priority if you would rather it disappear than truncate.

The mockup never shows this collision because its tiles are ~188pt and its longest pairing is
`$182.40 ×2` + `Reverse holo`. Check `$1,234.56 ×12` + `Reverse holo` on a 165pt tile before
merging.

## 4. `PriceLabel` gains a `.tile` style

`PriceLabel` has exactly two call sites, both inside `CollectionCardTile`, so this is contained.
Add a third case rather than mutating `.compact` — Browse and the detail screen do not use this
type, but the `.detailed` branch is still exercised elsewhere in this file.

```swift
enum Style { case compact, detailed, tile }

private var tilePriceFont: Font {
    .system(size: 15, weight: .semibold).monospacedDigit()
}
```

`amount(_:)` selects `tilePriceFont` for `.tile` and keeps `.foregroundStyle(shade)`. Retain
`.contentTransition(.numericText())` **and** `.animation(.snappy, value: price.amount)` — the pair
added last pass is what makes a refresh settle instead of swap, and it is unaffected by 4a.

The mockup's price is `rgba(235,235,245,0.9)`, i.e. slightly under full white. `.primary` at 1.0 is
close enough that a token is not worth it; if you want the exact value, the `.current` branch can
take `.primary.opacity(0.9)`.

⚠️ For `.tile`, the `.unavailable` / `.unknown` branches must **not** render `—`. In 4a the orange
reason occupies the price slot outright (`Not checked yet` on the Ragavan tile). Handled by
`priceReplacementCaveat` in §3, so `PriceLabel(style: .tile)` is only ever constructed when
`row.price.amount != nil`.

## 5. Renaming `priceCaveat` → `priceReplacementCaveat`

Today's `priceCaveat` is additive — it sits *beside* an em-dash. In 4a it *is* the price slot:

```swift
private var priceReplacementCaveat: String? {
    guard row.price.amount == nil else { return nil }
    if let unpricedReason { return unpricedReason.title }
    return row.price.state() == .unavailable ? "Price unavailable" : "Not checked yet"
}
```

Note the behaviour change this implies and confirm it is wanted: today a row that has *both* a
price and an `unpricedReason` shows the reason beside the price. Under 4a there is nowhere to put
it, so it drops off the tile and survives only in the accessibility label
(`diagnosticAccessibilityText`, unchanged) and on the detail screen.

## 6. The baseline — the one deviation I recommend

4a as drawn uses `-webkit-line-clamp:2` with **no minimum height**, so a one-line name and a
two-line name produce footers 23px apart, and the price line stops aligning across a row. That is
precisely the property the 2a work existed to establish, and the 4a mockup only appears to keep it
because its six tiles happen to pair 1-line with 1-line and 2-line with 2-line.

Recommendation: keep a two-line floor on the name, gated the way `rowHeights` was:

```swift
private var nameMinHeight: CGFloat? {
    dynamicTypeSize > .xxxLarge ? nil : 46   // 2 × 23pt line height at 18pt
}
```

At accessibility sizes the grid is already one column (`columns`, line 96), where there is no
cross-tile baseline to protect — same reasoning as the old gate. If you would rather match 4a
literally, pass `nil` unconditionally and accept ragged price lines.

## 7. Grid spacing

`LazyVGrid(columns: columns, spacing: 22)` (line 337) → **28**, matching 4a's `gap:28px 16px`. The
column gap is already 16 via `GridItem(.adaptive(minimum: 165), spacing: 16, alignment: .top)`.

## 8. Accessibility

The combined label (line 1082) already reads name, set name, price, status, quantity and both
diagnostic titles, and it stays correct — the set name it speaks is now also visible, and
`accessibleStatus` still resolves through `CollectionFinishStatus`. One adjustment: when
`priceReplacementCaveat` is non-nil the visible text and `accessiblePrice` should agree; today
`accessiblePrice` says "price not checked" while the tile would read "Not checked yet". Harmless,
but worth aligning the wording while you are in there.

## 9. Unchanged

`CollectionArtworkGlow` and its accent plumbing, `CardFinishOverlay` + the shared
`CardFinishMotionSource`, `CollectionFinishDot` and all 17 colour sets, `CollectionTileButtonStyle`,
`hasSpecularFinish`, the `Button` / `.contentShape(.rect)` wrapper, `GridItem(.adaptive(minimum: 165))`,
the header (`collectionSummary`, money-green total, unpriced tally, refresh button), the sort menu,
and every diagnostic plumbing path.

## 10. Order of work and verification

1. §7 grid spacing + §1 tile structure — the layout skeleton.
2. §2 identity line + the `TileIdentity` colour set.
3. §3 quiet line + §4 `.tile` price style + §5 caveat rename. Delete `statusRow` and `rowHeights`.
4. §6 `nameMinHeight`.

Verify:

- Build, then the focused collection suite (959 tests last pass; `CollectionQueryTests` covers
  `hasSpecularFinish` and should be untouched).
- Screenshot the grid against `#4a` in `CollectionTileFooter.dc.html` side by side at the same
  width — check the name/identity pairing, that the price no longer dominates, and that the status
  sits hard against the trailing edge.
- **Long-content pass:** a card with a long set name (`The Hobbit Eternal`), a long status
  (`Reverse holo`), a 4-digit price and `×12`, all in one 165pt tile. This is where 4a is tightest.
- Mixed 1-line/2-line names in the same grid row — confirm the price lines still align with
  `nameMinHeight` in place.
- Light mode, dark mode, and one accessibility Dynamic Type size (grid drops to one column, name
  floor releases).
- Confirm the glow and sheen still render — they are untouched by this change and a regression
  there would mean the artwork stack was disturbed.
