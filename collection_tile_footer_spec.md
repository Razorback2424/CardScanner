# Collection tile footer — implementation spec (codebase-corrected)

Target: `CollectionScreen.dc.html` (direction **2a**, "Lit from within"). Written against `main`
@ 2026-09-09, verified line-by-line against `CollectionView.swift` (1233 lines),
`CollectionQuery.swift`, and `CollectionCardDetailView.swift`.

> **Corrections are marked ⚠️.** Everything unmarked matched the codebase as written.

Files touched:

- `TradingCardScanner/Views/CollectionView.swift` — `CollectionCardTile`, `PriceLabel`,
  `collectionSummary`, deletion of `CollectionBadgeWrapLayout`
- One new file: `TradingCardScanner/Views/CollectionFinishDot.swift`
- ⚠️ **`TradingCardScanner/Views/Components/AppCardBadge.swift` does not exist.** There is no
  `Views/Components/` directory. `AppCardBadge` is declared in `CollectionCardDetailView.swift`
  (line 1056) and is used by Browse/Sealed/detail. It needs no change — correct conclusion, wrong
  path.
- ⚠️ **`Assets.xcassets` gains a colour set group** — see §3. It currently contains only
  `AppIcon.appiconset`; there are no colour sets in the project at all.

---

## 0. ⚠️ The mockup is dark mode; the app is not

`CollectionScreen.dc.html` renders on `#000` with `rgba(235,235,245,…)` labels — those are iOS
**dark** semantic colours. Every literal hex in §3 (`#40C8E0`, `#CF8AF7`, `#7B79FF`, `#C5A57E`,
`#FF6E86`) is picked for a black background and **fails 4.5:1 on white**. The app has no forced
colour scheme, so a light-mode collection grid would get pale pastel status labels on white.

**Do not ship these as `Color(red:green:blue:)` literals.** Add one colour set per status to
`Assets.xcassets` with a Any/Dark pair — dark = the mockup hex, light = the existing
`.teal`/`.purple`/`.indigo`/`.brown`/`.pink` system colour (which is what the app shows today and
already passes on white). Then `Color("FinishReverse")` etc. resolve per appearance.

This applies to the dot gradients in §3 too, and to the glow in §4 (a 0.55-opacity radial on white
reads as a wash, not a glow — see §4).

---

## 1. The rule that drives everything: four fixed rows

Verified: today's footer is `VStack(alignment: .leading, spacing: 5)` containing name (`minHeight:
36`), `identityLine`, then a `ViewThatFits(in: .horizontal)` over two arrangements wrapping
`AppCardBadge`s through `CollectionBadgeWrapLayout`. The diagnosis is correct — no two tiles are the
same height, so the price floats.

⚠️ Note the row **order changes**, not just the shape: today identity sits *above* price. The target
puts price second and identity third.

| # | Row | Height | Font | Colour |
| --- | --- | --- | --- | --- |
| 1 | Name | `minHeight: 40`, `.lineLimit(2)`, top-leading | `.subheadline.weight(.semibold)` (15pt ✓ mockup) | primary |
| 2 | Price + quantity | 26 | see §2 | see §2 |
| 3 | Identity (`setCode · cardNumber`) | 16 | `.caption` monospaced digit (12pt ✓) | secondary |
| 4 | Status | 16 | `.caption.weight(.semibold)` (12pt ✓) | finish tint (§3) |

Footer spacing **6** ✓ (mockup `gap:6px`), artwork-to-footer **8 → 12** ✓ (mockup `gap:12px`).

```swift
VStack(alignment: .leading, spacing: 6) {
    Text(row.name)
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)

    HStack(alignment: .firstTextBaseline, spacing: 6) {
        PriceLabel(price: row.price, style: .compact)
            .fixedSize(horizontal: true, vertical: false)
        if row.quantity > 1 {
            Text("×\(row.quantity)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        if let priceCaveat {                       // ⚠️ see below
            Text(priceCaveat)
                .font(.footnote)
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
        Spacer(minLength: 0)
    }
    .frame(height: rowHeights.price)               // ⚠️ optional, see §7

    Text(identityLine)
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, height: rowHeights.meta, alignment: .leading)

    statusRow
        .frame(maxWidth: .infinity, height: rowHeights.meta, alignment: .leading)
}
.frame(maxWidth: .infinity)
```

### ⚠️ The unpriced caveat must not depend on a diagnostic being present

The spec gates the orange text on `if let unpricedReason, row.price.amount == nil`. Two problems:

1. **Today the badge shows whenever `unpricedReason != nil`**, regardless of price state. Adding
   `amount == nil` silently drops the diagnostic from any row that has both a price and a
   diagnostic. That may be intended — but it is a behaviour change, not a restyle.
2. **When `unpricedReason` is nil but the price is `.unknown`/`.unavailable`, the tile shows a bare
   `—` with no explanation.** The mockup never does this: its Ragavan tile shows `—` *and*
   "Not checked yet". `PriceLabel` already owns that copy for `.detailed` style.

Fall back to the price state's own words:

```swift
private var priceCaveat: String? {
    guard row.price.amount == nil else { return unpricedReason?.title }
    if let unpricedReason { return unpricedReason.title }
    return row.price.state() == .unavailable ? "Price unavailable" : "Not checked yet"
}
```

### Deletions — all verified safe

- `CollectionBadgeWrapLayout` (lines 1069–~1160): 2 references total, both inside this file. Safe.
- `inlineBadgeRow` (2 refs), `badgeContent` (3 refs), the `ViewThatFits` wrapper (1 ref): all local.
- `finishSymbol(for:)` (2 refs): local. ✓ Delete.
- ⚠️ **Keep `finishTint(for:)` and `itemKindTint(for:)`** — §3 still needs both (2 refs each today).

### `identityLine` loses the set name ✓

Verified today's version joins `[row.setCode, row.cardNumber, row.setName]`. Dropping `setName` is
correct and matches the mockup (`HOC · 84`, `OBF · 223`, and bare `PRE` for the sealed box — the
existing `.filter { !$0.isEmpty }` already handles a missing card number).

`row.setName` stays in the accessibility label (line 947) — verified unchanged.

---

## 2. Price: rounded, tabular, and the largest thing in the footer

Verified: `PriceLabel` (line 1193) has `enum Style { case compact, detailed }`, and `amount(_:)`
renders `.title3.weight(.semibold).monospacedDigit()` with `.minimumScaleFactor(0.8)`. The
`.unavailable` / `.unknown` branches render `—` in compact with `.secondary` / `.tertiary`. ✓

⚠️ **`PriceLabel` is not shared.** Its only two call sites are lines 930 and 937 — both inside
`CollectionCardTile`. Browse and the detail screen do **not** use it (they use
`CardDetailPriceValue` and their own labels), so the claim that they "inherit" these changes is
wrong. That is good news: the change is contained, and no other screen needs re-checking.

⚠️ **Font size.** The mockup is `700 22px/26px` — 22pt, i.e. `.title2`, not `.title3` (20pt). A
22pt bold line in a 26pt fixed row is tight but matches the mockup's own `line-height:26px`. Use
`.system(size: 22, weight: .bold, design: .rounded)` and confirm no clipping at default Dynamic
Type; fall back to `.title3` if it clips.

⚠️ **`.contentTransition(.numericText())` is a no-op as specified.** There is **no `withAnimation`
anywhere in `CollectionView.swift`**, and the three `.animation(.easeOut(duration: 0.2), value:)`
modifiers (lines 368–370) are keyed on `filters`, `sort` and `searchQuery` only — never on the
snapshot or a price. A content transition only runs inside an animation transaction, so as written
nothing would move.

This is already true of the header: the existing `.contentTransition(.numericText())` on
`shownValue` (line 383) has never animated either.

Pair each with an explicit value-keyed animation, exactly as the Portfolio hero does
(`PortfolioView.swift`: `.contentTransition(.numericText())` + `.animation(.snappy, value:)`):

```swift
// in PriceLabel.amount(_:)
.contentTransition(.numericText())
.animation(.snappy, value: price.amount)

// in collectionSummary
.animation(.snappy, value: snapshot.shownValue)
```

Also note `amount(_:)` serves the `.stale` branch too (line 1206), so the rounded/bold treatment
correctly applies to stale prices — which is what the mockup shows.

Quantity moves beside the price as `×N`, `.footnote` secondary ✓ (mockup `400 13px/18px`).

---

## 3. The finish dot

⚠️ **`Color(hex:)` does not exist in this project.** The spec uses it three times. Either add an
extension or — preferred, see §0 — use asset colour sets so the values are appearance-aware:

```swift
extension Color {
    static let finishFoilHigh   = Color("FinishFoilHigh")    // #E9B8FF dark / .purple light
    static let finishFoilMid    = Color("FinishFoilMid")     // #BF5AF2
    static let finishFoilLow    = Color("FinishFoilLow")     // #7A2FA8
    // …reverse: #7FE7F6 / #40C8E0 / #1E7F92
}
```

New file `CollectionFinishDot.swift` — otherwise as specified (7×7, `.accessibilityHidden(true)`,
conic sweep for treatment, linear gradients for foil/reverse, flat for graded/sealed, hollow ring
for plain). ⚠️ The mockup's treatment sweep is
`conic-gradient(from 210deg, #FF375F,#FFD60A,#3DD68C,#40C8E0,#BF5AF2,#FF375F)` — use those stops,
not `.pink/.yellow/.green/.teal/.purple`.

⚠️ **Reorder the status priority: graded/sealed must come first.**

The spec ranks treatment above everything. `displayedMagicTreatmentEvidence` is on `CollectionRow`
independent of `itemKind`, so a **graded Magic card with a treatment would display "Surge Foil" and
lose "PSA 10"** — the grade is the defining fact about a slab, and today's tile always shows it.
Correct order:

1. **Graded / sealed** (`row.itemKind == .gradedCard || .sealedProduct`) → `.flat(itemKindTint(for:))`,
   label `row.displayKindLabel`.
2. **Treatment** (`displayedMagicTreatmentEvidence.displayLabels.first`) → `.treatment`, pink label.
   `+N` suffix for extras ✓.
3. **Finish** (`row.variant`, when `!row.displayedMagicTreatmentEvidence.impliesFinish(variant)`) —
   verified both `row.variant` (computed, `CollectionQuery.swift:55`) and `impliesFinish` exist.
4. **Fallback** → `.plain`, `variant?.label ?? "Nonfoil"`.

The variant→material mapping mirrors the existing `finishTint(for:)` switch exactly (`reverse`;
`foil`/`holo`/`etched`; `pokeBall`/`masterBall`/`firstEdition`; `normal`/`nonfoil`; default) — all
of those `PhysicalVariant` statics are verified present.

⚠️ The mockup exposes "always show a row for plain nonfoil" as a **toggleable prop**
(`showDefaultFinish`, default `true`). Shipping it always-on matches the default and keeps the
fourth row from collapsing — but it is a design question the mockup deliberately left open.

---

## 4. The glow

⚠️ **The mockup's insets are percentages; the spec converted them to points.** Mockup:
`left:10%; right:10%; top:18%; bottom:-4%; border-radius:20px;
radial-gradient(60% 60% at 50% 60%, C 0%, transparent 72%); blur(16px); opacity:0.55`.

At a 165pt-wide tile the artwork is ~231pt tall, so 10% = 16.5pt (not 12), 18% = 41.6pt (not 18),
−4% = −9.2pt (not −4), and the 60% radius ≈ 69pt (not 90). Using the spec's fixed points puts the
glow far too high and too tight. Express them relatively:

```swift
.background {
    GeometryReader { geo in
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [glowColor.opacity(0.55), .clear],
                    center: .init(x: 0.5, y: 0.6),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.6
                )
            )
            .blur(radius: 16)
            .padding(.horizontal, geo.size.width * 0.10)
            .padding(.top, geo.size.height * 0.18)
            .padding(.bottom, -geo.size.height * 0.04)
    }
    .allowsHitTesting(false)
}
```

⚠️ Attach this to the **artwork**'s frame (the `ZStack` at line 903, which already carries
`.aspectRatio(5/7)`), not to the tile — a `.background` on the tile would sit behind the footer text
too.

⚠️ **`ArtworkAccentExtractor` already exists** (`CollectionCardDetailView.swift:2444`, internal, with
`struct ArtworkAccent` at 2434). It already does exactly what §4 describes — a `CIAreaAverage` over a
**cropped centre region**, chosen so "the backdrop follows the subject rather than turning every card
gray". Reuse it; do not write a second averaging path. `ArtworkAccent` is `Equatable, Sendable`, so
it can live on `CollectionRow` (which is `Sendable`) directly — no hex round-trip needed.

⚠️ `CollectionRow` is built by `CollectionProjectionActor` and defined in
`Services/CollectionQuery.swift`. Adding a field means touching the projection actor and anything
that constructs a row; give it a default (`var artworkAccent: ArtworkAccent? = nil`) so every
existing construction site keeps compiling — the file already uses that pattern for
`priceStorageKey`, `magicTreatmentIDsRaw` and `itemKind`.

⚠️ **Light mode.** A 55%-opacity coloured radial behind artwork on white washes the tile out rather
than lighting it. Gate the glow to dark mode (`@Environment(\.colorScheme)`), or drop its opacity to
~0.22 in light. Verify both before merging.

Performance rules ✓ as written (no `.drawingGroup()`, no animation, honour
`.accessibilityReduceTransparency`). ⚠️ There is no `CollectionView.body` signpost — `signpost`
appears 40× in the project but not in this file; add one or measure with Instruments instead.

---

## 5. The sheen

⚠️ **This already exists.** `CardFinishOverlay` (`CollectionCardDetailView.swift:1495`) is a
tilt-driven specular sweep taking `variant`, `resolution`, `treatments`, `cornerRadius`, already
gated on both `accessibilityReduceMotion` and `accessibilityReduceTransparency`, with multi-band
phase logic that distinguishes a Surge Foil ripple from a plain foil pass. Do not build a parallel
implementation.

Two things block reuse, and both must be fixed rather than worked around:

1. ⚠️ **It is `private`**, as is its `CardFinishMotionModel` (line 1424). Move both into their own
   file (`CardFinishOverlay.swift`) at internal access.
2. ⚠️ **`CardFinishMotionModel` owns a `CMMotionManager` per instance at 60 Hz**, held via
   `@StateObject` — one per view. On the detail screen that is one. On a grid of ~20 visible tiles
   it is **20 motion managers at 60 Hz**, which is precisely the battery bug the spec warns about.
   Refactor it into a single shared source injected through the environment, started in
   `onAppear` of `content(_:)` and stopped in `onDisappear`, and have both the detail overlay and
   the grid tiles read it. The spec's 30 Hz for the grid is the right call; the detail screen can
   keep 60.

The `hasSpecularFinish` predicate is new and correct as written — ⚠️ but verify against the mockup:
tile 2 is "Reverse holo" and **does** carry a sheen, so `.reverse` must stay in the set (it is), and
the PSA 10 and Sealed tiles correctly have none.

Add it to `CollectionRow` in `CollectionQuery.swift` as a computed property (no projection change
needed — it reads `itemKind`, `displayedMagicTreatmentEvidence` and `variant`, all already present).

---

## 6. Header

Verified `collectionSummary(_:)` at line 373: `shownValue` already renders
`.system(.title2, design: .rounded).weight(.bold)` + `.monospacedDigit()` +
`.contentTransition(.numericText())`, with `PriceRefreshActivityRow(refresh: refresh)` beneath. ✓

⚠️ **`Color.moneyGreen` does not exist, and "the same token Portfolio's gain colour uses" is the
wrong token.** The mockup's total is `#2E8C57`. `PortfolioPalette.gain` is `#1E8E3E` (darkened for
contrast on tint fills); the `#2E8C57` money-green in the app is `PortfolioPalette.refreshAccent`.
Use that — and since it is now used by two screens, rename it to something screen-neutral
(`PortfolioPalette.money`) or lift it to a shared `Color.money`.

⚠️ Mockup total is `700 28px/32px` — 28pt (`.title`), not the current 22pt `.title2`. Raise it if
matching the mockup; the spec's "it already is" is only true of the design and weight.

⚠️ **`Snapshot` has no `unpriced` count** (`CollectionView.swift:509` — it holds `all`, `entries`,
`shownValue`). Derive it where the snapshot is built, not in `body`:
`entries.filter { $0.row.price.amount == nil }.count`.

⚠️ The count is currently a **trailing element in an `HStack`** beside the value (line 387), not a
line below it. The mockup puts `6 items · 1 unpriced` on the value's **baseline, 8pt to its right**
(`align-items:baseline; gap:8px`). Move it into the value's `HStack(alignment: .firstTextBaseline)`
to match, and check truncation at 28pt + a long count on a 375pt screen.

⚠️ **`refresh.isRunning` does not exist.** `PriceRefreshController` publishes `status`; the
in-repo pattern (`PortfolioRefreshButton`) is:

```swift
private var isRefreshing: Bool {
    if case .refreshing = refresh.status { return true }
    return false
}
```

⚠️ **Do not put `@ObservedObject var refresh` on the header.** Refresh progress publishes on a
one-second cadence, and both `ContentView` and `PortfolioView` carry explicit comments about
isolating it into a leaf view for exactly this reason — observing it in `collectionSummary` would
re-evaluate the header, and potentially the grid, four times a second during a pass. Put the button
in its own small view that observes `refresh` and nothing else, mirroring `PortfolioRefreshButton`.

⚠️ Button shape: the mockup is a **capsule** (`border-radius:100px`, h44, fill `rgba(46,140,87,0.18)`,
label `#3DD68C`, `600 13px/18px`, `autorenew` glyph at 18px). `.bordered` renders a rounded
rectangle with a different tint treatment — use a capsule background explicitly if matching.

---

## 7. Dynamic Type

✓ Verified `columns` (line 93) already drops to one column via `dynamicTypeSize.isAccessibilitySize`.

⚠️ `CollectionCardTile` does **not** currently read `dynamicTypeSize` — the environment value lives
on `CollectionView`. Add `@Environment(\.dynamicTypeSize) private var dynamicTypeSize` to the tile,
then:

```swift
private var rowHeights: (price: CGFloat?, meta: CGFloat?) {
    dynamicTypeSize > .xxxLarge ? (nil, nil) : (26, 16)
}
```

Note `.frame(height:)` accepts an optional `CGFloat?`, so passing `nil` correctly yields the
intrinsic height — this is why the snippet in §1 passes `rowHeights.price` rather than a literal.

---

## 8. What must not change

✓ Verified — with one wording fix: ⚠️ the `Button`, `.buttonStyle(.plain)` and `.contentShape(.rect)`
are in **`CollectionView`'s grid** (lines 334–347), not inside `CollectionCardTile`. The tile itself
is a plain `VStack` ending in `.accessibilityElement(children: .combine)` + the combined label
(lines 945–948). The guarantee holds; the location differs.

✓ `LazyVGrid(columns:, spacing: 22)` and `GridItem(.adaptive(minimum: 165), spacing: 16, alignment: .top)`
verified at lines 328 and 97. (Mockup uses `gap:24px 16px` — 22 vs 24 is within tolerance.)

⚠️ Press feedback: `.buttonStyle(.plain)` does **not** dim on its own. A custom
`ButtonStyle` applying `.opacity(configuration.isPressed ? 0.65 : 1)` must actually be written and
applied in place of `.plain` at line 343 — and `.contentShape(.rect)` must stay, since a custom
style has the same hit-testing behaviour as `.plain`.

✓ `unpricedReason` / `artworkReason` plumbing (31 refs), `isLogicalConflict`, and the
`.animation(.easeOut(duration: 0.2), value:)` triple (lines 368–370) are untouched.

---

## 9. Order of work

1. §1 + §2 — fixed rows, `identityLine`, `PriceLabel` rounded + `numericText` **+ its animation**.
   Delete `CollectionBadgeWrapLayout`. This is the correctness win; ship it first.
2. §0 + §3 — colour sets, `CollectionFinishDot`, `statusRow` with **graded/sealed first**.
   Contrast-check in both appearances.
3. §6 — header token, unpriced tally, isolated refresh button.
4. §4 — reuse `ArtworkAccentExtractor`, add `artworkAccent` to the projection, relative-inset glow,
   light-mode check.
5. §5 — **extract and share** `CardFinishOverlay` + a single motion source. Last, and the only step
   that can regress scroll performance.
