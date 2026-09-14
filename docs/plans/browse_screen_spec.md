# Catalog (Browse) screen — implementation spec (codebase-corrected)

Target: `BrowseScreen.dc.html`, two artboards — **Catalog** (root) and **Pokémon sets** (game → set
list). Written against `main` @ 2026-09-13, verified line-by-line against `BrowseView.swift`
(1718 lines), `BrowseCatalog.swift` (1180), `BrowseCatalogModels.swift` (753),
`SealedBrowseViews.swift`, `JustTCGMarketModels.swift`, and `ContentView.swift`.

> **Corrections are marked ⚠️.** Everything unmarked matched the codebase as written.

Files touched:

- `TradingCardScanner/Views/BrowseView.swift` — `BrowseView.body`, `gameChooser`, `sealedChooser`,
  `CatalogSetListView`, `CatalogSetOrdering`; deletion of the `browseScope` segmented picker
- `TradingCardScanner/Models/BrowseCatalogModels.swift` — new set-list sort/filter types (§6)
- One new file: `TradingCardScanner/Views/CatalogSetTile.swift` (the grid tile, §4)
- ⚠️ Possibly `TradingCardScanner/Views/ContentView.swift` — **only if** the tab decision in §0 goes
  that way. Do not touch it otherwise.
- ⚠️ `Assets.xcassets` gains one colour set group for tile backgrounds — see §4.3. It currently
  contains only `AppIcon.appiconset`; there are still no colour sets in the project.

---

## 0. ⚠️ The two artboards disagree about the tab bar, and one of them deletes Portfolio

`BrowseScreen.dc.html` renders its tab bar as:

```js
tabs: [ collection, catalog, scan, centering ]   // value="catalog"
```

`AppScreen.dc.html` — the Portfolio artboard in the same export — renders:

```js
tabs: [ portfolio, collection, scan, centering ] // value="portfolio"
```

The second matches the shipped app exactly (`ContentView.swift:90–121`: Portfolio, Collection, Scan,
Centering). The first **replaces Portfolio with Catalog**.

Today Browse is not a tab at all. It is a push destination owned by Collection:

```swift
// CollectionView.swift:314
case .browse:
    BrowseView(catalog: catalog)
```

So the mockup implies a structural change that is nowhere stated: promoting Browse to top level, and
— as drawn — **removing the Portfolio tab**, which is the entire surface behind the portfolio
engine, replay, history, and daily closes.

**Do not implement the four-tab bar as drawn.** This is a product decision, not a layout detail.
Three options, in the order I would recommend them:

1. **Keep Browse as a push destination** (no `ContentView` change). Everything else in this spec
   still applies; the Catalog artboard gains a back chevron to Collection and loses nothing else.
   Cheapest, and preserves both features.
2. **Add Catalog as a fifth tab.** Five tabs fit on iPhone without a "More" overflow. Requires a
   `Tab.catalog` case, a tab item, and a decision about whether Collection keeps its `.browse`
   destination (it should, for deep links — `ContentView.swift:66` routes a `"Browse"` debug route
   through `initialTab = .collection`).
3. **Replace Portfolio with Catalog** as drawn. Only if the user explicitly confirms Portfolio is
   moving somewhere else. Nothing in the export says it is.

Pick one before writing any code in §1–§6. Options 1 and 2 leave `ContentView.swift` alone or add to
it; option 3 is a deletion and needs its own plan.

---

## 1. The root screen: one search, no scope picker

The artboard's stated intent is in its own caption:

> "One search over cards and sealed. No scope picker — the kind is a property of a result, not a
> mode you choose first."

That is a genuine improvement and it is implementable. What it replaces:

```swift
// BrowseView.swift:263–270 — delete this
Picker("Browse scope", selection: $browseScope) {
    if model.isSearching { Text("All").tag(BrowseScope.all) }
    Text("Cards").tag(BrowseScope.cards)
    Text("Sealed").tag(BrowseScope.sealed)
}
.pickerStyle(.segmented)
```

⚠️ **`BrowseScope` is load-bearing beyond the picker.** Deleting the control is not enough:

- `BrowseView.swift:271–278` switches on `browseScope` to choose between `searchBody`,
  `gameChooser`, and `sealedChooser`.
- `BrowseView.swift:316–325` has two `.onChange` handlers that flip `browseScope` to `.all` when a
  search begins and back to `.cards` when it ends, and mirror it into `model.searchScope`.
- `BrowseViewModel.searchScope` (`:24`) is `.cards` by default and `didSet`-triggers `scheduleSearch()`.
- `searchBody` (`:485`) gates its Cards section on `browseScope != .sealed`.

**Required behavior after the change:**

- `BrowseViewModel.searchScope` defaults to `.all` and is never reassigned from the view.
- Idle (no query): render the "Just released" rail (§2) then the game rows (§3). No chooser switch.
- Searching: render one result list with a **Cards** section and a **Sealed** section, both always
  present when non-empty, in that order. Keep the existing per-game sub-sectioning inside Cards.
- Keep `BrowseScope` the type — it still describes what a *result* is, and `searchScope` is how the
  model asks the catalog for both lanes. Only the picker and the mode-switching go away.

Navigation title becomes **"Catalog"** (`BrowseView.swift:285` currently `"Browse"`). The settings
toolbar button at `:287–295` stays exactly as it is; the artboard draws it in the same position.

---

## 2. "Just released" rail

A horizontal rail of up to three set cards, 248pt wide, 134pt artwork box, `NEW` pill on the two
newest.

**Data.** `CatalogSet.releaseDate` and `CatalogSet.sortRank` already exist
(`BrowseCatalogModels.swift:33–37`). Use `CatalogSetOrdering.newestFirst` (`BrowseView.swift:584`),
which is already the app's ordering rule and already handles the Pokémon/Magic difference:

```swift
// BrowseCatalogModels.swift:45–49
var releaseOrder: Int {
    game == .pokemon ? sortRank
                     : releaseDate.map { Int($0.timeIntervalSince1970 / 86_400) } ?? sortRank
}
```

⚠️ **Do not define "just released" as a date window.** Pokémon ordering is `sortRank`, not a date, so
"released in the last 90 days" is not expressible for half the catalog. Define it as **the first N
sets of `CatalogSetOrdering.newestFirst` across both games, interleaved** — take the top 2 per game,
then sort those by `releaseOrder`. That is deterministic, works offline, and needs no new data.

⚠️ **The `NEW` pill needs a rule, and the mockup gives it to two of three tiles with no stated
threshold.** Use: the pill appears on a set whose `releaseDate` is within 45 days of `Date.now`, and
never when `releaseDate` is nil. Pokémon sets built from the snapshot path have
`releaseDate: nil` (`PokemonChecklistSnapshot.swift:178`) while the live path populates it (`:309`),
so a nil-safe rule is mandatory or the pill will flicker between launches.

Tapping a rail tile pushes the same destination a grid tile does (§4) — `CatalogSetCardsView`.
"All sets" on the right of the header pushes the game's set list; ⚠️ the mockup does not say *which*
game, and with two games it cannot be one link. **Make the rail header a plain section header with
no trailing link**, or scope the rail per game. Do not ship an ambiguous "All sets" affordance.

---

## 3. "Everything in the catalog" — the two game rows

Each row: a 96×62 fan of three card thumbnails, game name, a counts line, chevron. Replaces
`gameChooser` (`BrowseView.swift:446–483`), which currently draws an SF Symbol in a rounded square
and the text `"Browse \(sets.count) sets"`.

**Counts line.** The mockup reads `168 sets · 21,940 cards · 1,204 sealed`.

- `sets` — available: `model.sets[game]?.count`. ✅
- `cards` — ⚠️ **a lower bound, not a total.** `CatalogSet.cardCount` is `Int?`
  (`BrowseCatalogModels.swift:35`) and is nil whenever the provider omitted it
  (`BrowseCatalog.swift:357–363` builds `countsByID` from `compactMap`, so missing counts are simply
  absent). Summing `compactMap(\.cardCount)` silently under-reports. Either label it honestly or drop
  it. **Drop it.** "168 sets" is true; "21,940 cards" is a number the app cannot stand behind.
- `sealed` — ⚠️ **not available at all.** See §5.

So the shipped counts line is `"\(setCount) sets"`, which is what `gameChooser` already says. The
row's value over today's is the artwork fan, not the numbers.

**The fan.** Three `CatalogCachedImage` views at 38×52, rotated −7°, 0°, +7°, offset left 2/24/44pt,
top 6/3/6pt. ⚠️ **There is no "representative cards for a game" query.** Do not invent one and do not
hardcode card IDs — the mockup's are literal Scryfall/TCGdex URLs for specific cards. Two defensible
sources, in order:

1. The three most recently **owned** cards for that game, from
   `projectionStore.snapshot` — already an `@EnvironmentObject` in this file
   (`BrowseView.swift:595`, `:861`). Makes the row personal and needs no network.
2. If the user owns nothing for that game, fall back to the three newest sets' `logoURL`.

Never leave three empty slots; an empty fan reads as a loading failure.

---

## 4. The set grid

Two columns, 16pt gutter, grouped under uppercase year headers. Per tile: a 104pt artwork box with a
0.5pt hairline and a tinted background, then name (15/19 semibold), then a metadata line
(12/16, tabular), then — **only when something is owned** — a 4pt progress bar and an owned count.

This replaces the `List` in `CatalogSetListView` (`BrowseView.swift:878–930`), which is a single
column of 42pt symbols with an always-present `ProgressView`.

### 4.1 Progress — already correct, just re-skinned

`CatalogOwnershipIndex.progress(for:)` (`BrowseCatalogModels.swift:241–251`) already returns
`SetCompletion(owned:total:unit:)` with a `fraction`, and `CatalogSetListView:894` already calls it.
Keep all of it. The only change is presentation:

- Show the bar and the count **only when `completion.owned > 0`**. The mockup does this — Surging
  Sparks and Shrouded Fable have no bar; Stellar Crown, Twilight Masquerade and Obsidian Flames do.
- Bar: 4pt tall, 2pt radius, track `rgba(60,60,67,0.12)`, fill `#2E8C57`.
- Trailing number is `completion.owned` alone (`41`, `163`, `221`), not `"41 of 175"`.
- ⚠️ Keep the existing accessibility label verbatim (`BrowseView.swift:922–924`). It reads
  "*N of M cards collected*" and is the only place the denominator survives; a sighted user loses it
  in this design, a VoiceOver user must not.
- ⚠️ `completion.fraction` is nil when `total` is nil. Guard the bar on `fraction != nil`, not on
  `owned > 0` alone, or a set with unknown size renders a zero-width fill.

### 4.2 Metadata line

Mockup: `SSP · 252 cards · 14 sealed`. Ship `"\(set.code) · \(count) cards"`, and omit the card
clause entirely when `cardCount` is nil. The sealed clause is removed — §5.

### 4.3 ⚠️ Tile background tints are light-mode-only literals

The mockup assigns a different pastel per tile (`#F4F1FA`, `#FAF3EF`, `#EFF3F7`, `#F6F0F3`,
`#F3F0EC`, `#FAF1EF`) against a white screen. The app has no forced colour scheme, so these become
near-white rectangles with a near-white hairline in dark mode — the tile disappears.

**Do not ship them as `Color(red:green:blue:)` literals.** Either:

- add one colour set per tint to `Assets.xcassets` with a dark variant (the same remedy §3 of
  `collection_tile_footer_spec.md` prescribes for the status colours), or
- derive the tint at runtime from the set's own artwork and composite it over
  `Color(.secondarySystemGroupedBackground)` at low opacity.

The second is less work and self-maintaining. Either way the hairline must be
`Color(.separator)`, not `rgba(60,60,67,0.14)`.

### 4.4 ⚠️ Magic set symbols are SVG and will not render

```swift
// BrowseCatalog.swift:410–417 — both fields are the same SVG
logoURL:  row.iconSVGURI,
symbolURL: row.iconSVGURI,
```

`CatalogCachedImage` decodes through `CGImageSourceCreateThumbnailAtIndex`
(`BrowseView.swift:1508–1520`). **ImageIO does not decode SVG on iOS**, and a grep for `svg` across
`BrowseView.swift` returns zero matches — there is no special case anywhere. The mockup's Duskmourn
tile points at `https://svgs.scryfall.io/sets/dsk.svg`, so as drawn **every Magic tile is empty**.

This is the single largest implementation risk in the screen. Options:

1. Render Magic symbols with `SVGView`/`WebKit` — a new dependency or a `WKWebView` per tile. Too
   heavy for a grid.
2. Rasterise on the fly: fetch the SVG, render once through `WKWebView` offscreen, cache the PNG in
   the existing `CatalogCachedImage` disk cache. One-time cost per set, then free.
3. **Ship Magic tiles with a typographic fallback**: the set code in a rounded rect, which is what
   `CatalogCachedImage`'s `placeholderSymbol` slot is for. Pokémon keeps its PNG logo
   (`PokemonChecklistSnapshot.swift:170` — `assetURL(row.symbol, suffix: ".png")`).

Start with (3) so the screen ships, and treat (2) as a follow-up. Do **not** start with (2); it turns
a layout change into an image-pipeline project.

### 4.5 Year headers

Uppercase, 13/16 semibold, `letter-spacing: 0.04em`, `rgba(60,60,67,0.6)` → `Color(.secondaryLabel)`.

⚠️ Group by `Calendar.current.component(.year, from: releaseDate)`, and put every set whose
`releaseDate` is nil into a single trailing **"Earlier"** bucket rather than a year. Pokémon sets from
the snapshot path have no date (`PokemonChecklistSnapshot.swift:178`); a nil-crashing or
1970-bucketing implementation will look fine in the simulator and wrong on a cold offline launch.

Within a year, order by `CatalogSetOrdering.newestFirst`. Do not re-sort by name.

---

## 5. ⚠️ "· N sealed" cannot be built, and the architecture says so explicitly

The mockup puts a sealed count on every set tile and every game row. That requires joining the card
catalog's set directory to the sealed one. The codebase refuses that join, in a comment written for
exactly this situation:

```swift
// JustTCGMarketModels.swift:484–489
/// A set as the vendor groups it, with its sealed inventory count.
///
/// Sealed browse uses the vendor's own set directory rather than TCGdex's or
/// Scryfall's, because mapping between the two groupings is unreliable and a
/// wrong mapping would show the wrong products.
struct SealedSetSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let sealedCount: Int
    ...
}
```

`sealedCount` exists — but keyed by the **vendor's** set id, not `CatalogSetID`. There is no mapping,
and building one by name match is the precise failure the comment forbids: a wrong match shows the
wrong products under a real set.

Two further blockers:

- Sealed is **credential-gated**. `SealedBrowseModel.isConfigured` (`SealedBrowseViews.swift:68`)
  returns `PriceVendorCredentials.hasKey`. Without a key the count is not merely stale, it is absent.
- Sealed sets load lazily per game (`loadSetsIfNeeded(game:)`, `:243`). The Catalog root would have
  to force-load both games' sealed directories before first paint to render counts — a network
  round-trip on a screen that is otherwise fully offline.

**Remove every "· N sealed" clause from this screen.** Sealed remains reachable as a section in
search results (§1) and through the existing sealed browse path. If per-set sealed counts are wanted
later, they need their own plan with a real identity mapping and a stated confidence rule — not a
string interpolation on a tile.

---

## 6. Sort control and filter chips

The Pokémon-sets artboard adds a `swap_vert` toolbar button and a chip rail:
`All sets · Started · Scarlet & Violet · Sword & Shield`.

⚠️ **`CatalogSetSort` and `CatalogOwnershipFilter` already exist and are the wrong types.**
`BrowseCatalogModels.swift:634` and `:652` define them, and `BrowseView.swift:943–944, 1034, 1045`
use them — but they filter and sort **cards inside one set**. Their cases are
`priceHighToLow / numberLowToHigh` and `owned / notOwned`. Reusing them for a list of sets would be a
name collision with no meaning. Declare new types:

```swift
enum CatalogSetListSort: String, CaseIterable, Identifiable, Sendable {
    case newestFirst, oldestFirst, nameAToZ, mostComplete
}
```

`mostComplete` sorts by `completion.fraction ?? -1` descending, so unknown-size sets sort last.

**Chips.** `All sets` and `Started` are implementable now — `Started` is
`completion.owned > 0`, from the same index §4.1 uses.

⚠️ **`Scarlet & Violet` and `Sword & Shield` have no data source.** `CatalogSet` carries no series,
era, or block field — a grep across `BrowseCatalogModels.swift` for `series`/`era` returns only
unrelated matches. TCGdex publishes a series per set and Scryfall publishes `block`, but neither is
decoded today (`BrowseCatalog.swift:405–418` decodes `code`, `name`, `iconSVGURI`, `cardCount`,
`releasedAt`, `setType` and nothing else).

Ship **two** chips (`All sets`, `Started`) in this slice. Era chips need a decoder change on both
providers plus a migration of the cached set directory, and that is a separate slice — the cache
envelope is versioned (`CatalogCacheStore`, `BrowseCatalog.swift:903–911`) and adding a field
invalidates it for every user.

---

## 7. Dynamic Type

The mockup is drawn at the default size. Two rules:

- The metadata line (`SSP · 252 cards`) and the owned count must use `.monospacedDigit()`; the
  mockup's `font-variant-numeric: tabular-nums` is not decoration, it stops the grid jittering as
  counts change. `PriceLabel` in `CollectionView.swift` already establishes this pattern.
- The 104pt artwork box is fixed; the text below it is not. At accessibility sizes the two-column
  grid must collapse to one column. Use `@Environment(\.dynamicTypeSize)` and switch the `GridItem`
  count on `dynamicTypeSize.isAccessibilitySize` — that is the exact idiom already in
  `CollectionView.swift:62` and `CollectionCardDetailView.swift:1784, 1804`. Do not hand-roll a
  `>= .accessibility1` comparison.

---

## 8. What must not change

- **`CatalogOwnershipIndex.progress(for:)` and `owns(_:)`** (`BrowseCatalogModels.swift:241–288`).
  This is the ownership contract the whole set-completion feature rests on, including Pokémon print
  runs, stamped releases and Magic treatments. This screen re-skins its output and nothing more.
- **`CatalogSetOrdering.newestFirst`** (`BrowseView.swift:584`). Both games' ordering already routes
  through it, including the Pokémon `sortRank` special case.
- **`CatalogCachedImage`'s cache and in-flight coalescing** (`BrowseView.swift:1308–1520`). The grid
  makes more image requests than the list did; it must reuse this, not fetch directly.
- **The sealed browse path and its credential gate.** §5 removes a count, not a feature.
- **`CatalogSetFilterSheet`** (`BrowseView.swift:1665`). It is reached from search, not from the set
  list, and this screen does not replace it.
- **`backfillPokemonReleaseOrder()`** (`BrowseView.swift:326`) and its `.task` call. It repairs
  `setReleaseOrder` on owned rows and must keep running when the root screen appears.

---

## 9. Order of work

1. **Settle §0** — the tab question. Nothing else is safe to start until this is answered.
2. `CatalogSetTile` in a new file, with the §4.4 typographic fallback for Magic. Build it against a
   preview with a nil `cardCount`, a nil `releaseDate` and `owned == 0`, because all three occur.
3. Replace `CatalogSetListView`'s `List` with the grouped grid (§4, §4.5). Keep the accessibility
   label. This is the highest-value half of the screen and is independently shippable.
4. `CatalogSetListSort` + the two chips (§6). Do not add era chips.
5. Root screen: delete the scope picker and rewire `searchScope` (§1). Verify the sealed section
   still appears in search results — that is the regression this step risks.
6. Game rows with the artwork fan (§3), counts reduced to `"N sets"`.
7. "Just released" rail (§2), including the nil-safe `NEW` rule.
8. Dark-mode colour sets or runtime tinting (§4.3), and Dynamic Type collapse (§7).

Steps 2–4 touch only the Pokémon-sets artboard and can ship before 5–7.

---

## 10. Deferred, with reasons

| Item | Why it is not in this slice |
| --- | --- |
| Per-set and per-game sealed counts | No reliable identity mapping; the architecture explicitly rejects it (§5) |
| Era/series chips | No decoded field on either provider; needs a cache-invalidating migration (§6) |
| Magic SVG symbols as artwork | Needs an offscreen rasteriser and a cache format change (§4.4) |
| Aggregate card counts per game | `cardCount` is optional per set, so any sum under-reports (§3) |
| Portfolio tab removal | Not a layout change; contradicts `AppScreen.dc.html` (§0) |
