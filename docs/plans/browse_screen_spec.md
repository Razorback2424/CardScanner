# Catalog / Browse — implementation plan

Status: current Browse contract, with the implementation landed in the working
tree — reconciled 2026-09-14. This document replaces the earlier artboard-led
plan. The requirements below remain the acceptance contract; the current
implementation/evidence state is recorded first so the older imperative wording
cannot be mistaken for an unfinished task list.

The detailed sections below are retained for acceptance traceability and design
rationale. They are not a second status ledger: completed implementation is
reported in the status block above, while the current checklist and release
follow-ups own remaining manual, provider, and device work.

Current implementation state:

- `CollectionView.Destination.browse` pushes Catalog from the Collection tab;
  Browse is not a fifth native tab.
- Unified card/sealed search, game-level Cards/Sealed navigation, cached sealed
  browsing, release rail, game summaries, set sorting/progress, artwork
  fallbacks, and grouped Pokémon finish tiles are implemented.
- The latest focused Browse/Catalog selectors pass 46 tests with 0 failures;
  the final Debug build and settled iPhone 17 Pro capture pass.
- Remaining pre-release manual checks are set-tile accessibility output,
  DisclosureGroup expand/collapse behavior, and dark-mode/AX5 badge contrast.

Baseline checked against:

- `TradingCardScanner/Views/BrowseView.swift`
- `TradingCardScanner/Views/CatalogSetTile.swift`
- `TradingCardScanner/Views/SealedBrowseViews.swift`
- `TradingCardScanner/Models/BrowseCatalogModels.swift`
- `TradingCardScanner/Services/BrowseCatalog.swift`
- `TradingCardScanner/Views/CollectionView.swift`
- `TradingCardScanner/Views/ContentView.swift`
- `TradingCardScannerTests/BrowseFeatureTests.swift`
- `TradingCardScannerTests/UncoveredSurfaceTests.swift`

## 1. Target navigation model

Use one hierarchy:

```text
Collection tab
└── Catalog
    ├── search result (card or sealed product)
    └── game
        ├── Cards
        │   ├── all cards
        │   └── sets → set → grouped card/finish tiles
        └── Sealed (vendor-grouped sets) → products
```

Sealed is a content kind within a game, not a second top-level game directory. The vendor's set
identity remains independent from `CatalogSetID`; this plan changes navigation, not catalog
identity. Do not join card sets to `SealedSetSummary` by name, code, or fuzzy matching.

Keep Catalog as a push destination owned by the Collection tab. `CollectionView.Destination.browse`
already establishes that route, and `ContentView.Tab` intentionally has Portfolio, Collection,
Scan, and Centering. Therefore Collection remaining selected on Catalog and its descendants is the
correct tab state. Do not rename the Collection tab, add a Catalog tab, or remove Portfolio in this
slice. Screenshot acceptance must assert that Collection stays selected while Catalog is open.

## 2. Implementation map and type-level contract

### `TradingCardScanner/Views/BrowseView.swift`

- Delete `sealedChooser` and remove its call from the idle root.
- Replace `CatalogGameCardsView` with `CatalogGameBrowseView`, or rename it and extend it in place.
  It owns a local `CatalogGameContentKind` selection (`cards`, `sealed`) and renders a segmented
  control immediately below the navigation title.
- Preserve the current Cards implementation and its Sets toolbar destination under `.cards`.
- Under `.sealed`, render the vendor set directory for the already-selected game. Label the content
  `Vendor catalog` in supporting copy so the data grouping is honest.
- Pass an `onOpenSettings` closure from `BrowseView` into `CatalogGameBrowseView`; use the existing
  `isShowingSettings` sheet at the root instead of presenting a second Settings sheet.
- Replace sectioned search rendering with the unified result model in §4.
- Update `CatalogSetOrdering.justReleased` as specified in §7.
- Surface set sorting in the chip row and replace the master-rules disclosure styling (§8).
- Add bottom safe-area spacing to root, game, set-list, and set-detail scroll content (§9).
- Replace `CatalogCardGrid`'s one-summary-per-tile input with display groups (§10).

### `TradingCardScanner/Views/SealedBrowseViews.swift`

- Extract the body of `SealedSetDirectoryView` into an embeddable content view that does not set a
  navigation title and does not install its own `.searchable` modifier. Because the host screen owns
  the single `.searchable` field (§5), the content view cannot keep `searchText` as private `@State`.
  Use:

```swift
struct SealedSetDirectoryContent: View {
    let game: CardGame
    @ObservedObject var model: SealedBrowseModel
    let searchText: String
    var onOpenSettings: (() -> Void)? = nil
}
```

  The existing `normalizedSearch` / `visibleSets` filtering moves in unchanged and reads the passed
  `searchText`. Keep the empty-state overlays, including `No Matching Sets`, which still needs the
  raw `searchText` for its message.
- Keep `SealedSetDirectoryView` as a thin wrapper that owns `@State private var searchText`, the
  navigation title, and `.searchable`, so existing direct/deep-link callers are unchanged.
- When credentials are absent and no cached directory is usable, show one full-width
  `Button("Set up sealed browsing", systemImage: "key")` and explanatory text; the button calls
  `onOpenSettings`. Replace the current `unconfigured` `Label` with this. When `onOpenSettings` is
  nil (the standalone wrapper), keep the current non-interactive `Label` copy instead of rendering a
  button that does nothing.
- Move the `.task(id: game) { await model.loadSetsIfNeeded(game: game) }` into the content view and
  guard it: `guard model.isConfigured || !model.sets.isEmpty else { return }`. Without this guard the
  unconfigured-and-uncached state in §5 still issues a provider request.
- Do not create game rows or product links in the unconfigured state. Cached sealed content may
  remain browsable without credentials, matching `SealedBrowseModel`'s existing cache contract.

### `TradingCardScanner/Models/BrowseCatalogModels.swift`

Add presentation-only models; do not alter persisted catalog or collection identity:

```swift
enum CatalogResultKind: String, Hashable, Sendable { case card, sealed }

enum CatalogSearchResult: Identifiable, Hashable, Sendable {
    case card(CatalogCardSummary)
    case sealed(game: CardGame, product: SealedProductSummary)

    var kind: CatalogResultKind { ... }
    var game: CardGame { ... }
    var name: String { ... }
    var id: String { ... }
}

struct CatalogCardDisplayIdentity: Hashable, Sendable {
    let game: CardGame
    let setID: CatalogSetID
    let providerID: String
    let collectorNumber: String

    /// Stable string form so the display group can be `Identifiable`.
    var id: String {
        [game.rawValue, setID.id, providerID, collectorNumber].joined(separator: "|")
    }
}

struct CatalogCardDisplayGroup: Identifiable, Hashable, Sendable {
    let identity: CatalogCardDisplayIdentity
    let summaries: [CatalogCardSummary]

    var id: String { identity.id }
    var preferredSummary: CatalogCardSummary { ... }
}
```

`CatalogCardDisplayGroup` must declare `id` explicitly; `identity` is a `Hashable` value, not an
`Identifiable` one, so the group does not synthesize an id. `CatalogResultKind` and
`CatalogSearchResult.game` are not decoration: they are the badge sources in §4 and the tie-break
keys in the §4 ranking, so expose them rather than re-switching on the enum at each call site.

`CatalogSearchResult.id` must be namespaced so kinds cannot collide:

- card: `"card:" + summary.id`
- sealed: `"sealed:" + [game.rawValue, product.id, product.variantID ?? ""].joined(separator: ":")`

`SealedProductSummary.variantID` is `String?`. Build the id by joining components, never by
interpolating the optional directly — `"\(product.variantID)"` would emit `Optional("...")` or
`nil` into a user-invisible but test-visible identity.

`CatalogCardDisplayIdentity` is a UI grouping key only. For Pokémon, group summaries that differ
only by `masterSetVariant`; for Magic, keep treatment-qualified summaries separate. Use
`SetCompletionCalculator.canonicalNumber` for the collector number, and because it returns `String?`,
fall back to `summary.collectorNumber.lowercased()` when it returns nil so an unparseable number
still produces a deterministic key and never silently merges two cards under an empty string. Do not
change `CatalogCardSummary.id`, collection keys, progress calculation, pricing keys, or detail
loading.

Grouping by `providerID` is correct against the current builders and must be asserted by test rather
than assumed: `PokemonMasterSetChecklistBuilder.build` produces every `masterSetVariant` of one card
from the same `providerID` and `setID`, and `BrowseCatalog.magicCards` assigns each Magic printing
the Scryfall card id, so distinct treatments already carry distinct `providerID`s.

### `TradingCardScanner/Views/CatalogSetTile.swift`

- Change the progress footer from the bare numerator to `"<owned> of <total>"` when total is known,
  or `"<owned> owned"` when it is not.
- Centralize count copy so `1 card` / `2 cards` and `1 set` / `2 sets` are correct.
- Add a game badge for rail layout.
- Replace the generic failed-art look with the deliberate missing-art state in §6.

### Tests

Extend `TradingCardScannerTests/BrowseFeatureTests.swift` for pure ordering, ranking, grouping,
pluralization, summary counts, and state reduction. Extend `UncoveredSurfaceTests.swift` only for
construction/smoke coverage of changed views. Add a UI test or deterministic debug-route screenshot
coverage for visual and navigation assertions in §12.

## 3. Root screen

The idle root contains, in order:

1. search field (`Search the catalog`),
2. release rail when eligible,
3. one `Browse by game` section,
4. one row per loaded `CardGame`.

Keep the existing per-game failure branch inside the `Browse by game` section: when
`model.sets[game]` is nil and `model.setErrors[game]` is set, still render the current
`Couldn't load <game> sets` block with its retry action, in that game's slot. This plan removes the
sealed hierarchy, not set-load error recovery.

There is no top-level Sealed section. Replace `Everything in the catalog` with `Browse by game`.
Use `.headline` or `.title3.weight(.semibold)` for this section, leaving `Just released` as the only
`.title2.bold()` hero heading.

Each game row navigates to `CatalogGameBrowseView` and displays:

```text
Pokémon
160 sets · 412 cards owned
```

Define `cards owned` as the sum of positive quantities for that game's projection rows whose
`itemKind.countsTowardSetCompletion` is true. Exclude sealed rows. Keep the three most recent
eligible rows only for the artwork fan, but calculate the ownership count from all eligible rows;
the current `recentOwnedRowsByGame` prefix must not be reused for the count. If the count is zero,
show `160 sets · No cards owned`.

Introduce a small pure helper, e.g. `CatalogGameSummary`, which accepts a game, that game's
`[CatalogSet]`, and the unfiltered `[CollectionRow]` from `projectionStore.snapshot?.rows`, and
produces `setCount`, `ownedCardQuantity`, and the (at most three) recent artwork rows. The helper —
not the view — applies the `quantity > 0 && itemKind.countsTowardSetCompletion` filter and the
`dateAdded` descending, `id` ascending sort, so both outputs derive from one filtered collection and
cannot drift. Unit-test it so display counts cannot accidentally become limited to the fan's three
rows.

## 4. Unified search

Delete `BrowseScope` and `BrowseViewModel.searchScope`, including its `didSet { scheduleSearch() }`.
The root has no kind scope picker and the model always requests cards plus sealed products for the
selected game(s). Keep the game menu and set-filter sheet. The set filter applies to card searches
only; add the accessibility hint `Filters card results only` to avoid implying that vendor sets share
`CatalogSetID`.

`runSearch` currently awaits `searchCardLanes` to completion before it calls `sealedModel.search`.
Now that both kinds are always requested, run them concurrently — `async let` or a task group over
the two — so sealed results are not gated on the slower card provider. Both are `@MainActor`, and
they write disjoint state (`lanes` versus `sealedModel.searchLanes`), so concurrency here is a
scheduling change, not a data-race change. Keep the existing `generation` token checks on both
paths.

Replace `searchBody`, `sealedSearchContent`, `searchSection`, and `sealedSearchSection` with one
`LazyVStack`/`ForEach` over `[CatalogSearchResult]`. Do not render Cards, Sealed, or per-game
headers. Every result row/tile must carry visible badges:

- kind: `Card` or `Sealed`,
- game: `Pokémon` or `Magic`.

Navigation switches on the result enum:

- `.card(summary)` → `CatalogCardDetailView(summary:catalog:)`
- `.sealed(game, product)` → `SealedProductDetailView(game:product:)`

Ranking is deterministic and independent of network completion order. Normalize the query and
candidate name with `CardNameSearch.normalize`, then sort by:

1. exact normalized-name match,
2. normalized name starts with the query,
3. a token starts with the query,
4. normalized name contains the query,
5. all other provider-returned matches,
6. within the same relevance bucket, localized name,
7. then kind raw value, game raw value, and stable result id.

Do not boost a kind or game. Recompute the merged sorted array when any lane changes. Keep the
provider calls parallel and the existing 400 ms debounce/generation cancellation behavior.

Pagination remains per underlying lane. Add `BrowseViewModel.loadMoreSearchResults()` that starts
one next-page request for every requested non-loading lane that still has a cursor/offset, using a
task group over the existing `loadMore(_ game:)` and `sealedModel.loadMoreSearch(game:query:)`
entry points, then rebuild the merged list. Specifics that are easy to get wrong:

- Pass the current `normalizedQuery` to `loadMoreSearch`; it re-normalizes and compares against its
  own `searchQuery`, so a raw `searchText` or a stale query silently no-ops.
- Honour the same `query.count >= 2` guard the debounce uses, and capture `generation` before the
  task group so a query change mid-page discards the result.
- The two lane families key on disjoint state, so the task group is safe, but each game's card lane
  and sealed lane must remain separate tasks — do not serialize them.
- `SealedBrowseModel.loadMoreSearch` appends with `+=` and does not deduplicate. Deduplicate sealed
  pages on `(id, variantID)`, not `id` alone: `SealedProductSummary.id` is the product id and two
  variants of one product share it. Card lanes keep the existing `deduplicated(_:)` on
  `CatalogCardSummary.id`.

Trigger pagination from one progress row at the bottom of the unified list. Do not attach pagination
tasks to each result.

Search state is reduced across all requested card and sealed lanes. Define a lane as *requested*
only if it could produce results: every card lane for a selected game, and a sealed lane for a
selected game only when `sealedModel.isConfigured` is true or that lane has cached products.
`SealedBrowseModel.search` already materializes a `Lane` for every requested game even when
unconfigured and uncached, so the reducer must apply this predicate itself rather than treat the
presence of a key in `searchLanes` as proof that a lane was requested. Otherwise an unconfigured
build reports a terminal-empty sealed lane and the `No catalog results` and `Search failed` branches
become unreachable in the wrong direction.

Evaluate exactly one state, in this order — the branches are mutually exclusive and the order is the
tie-breaker where several conditions hold at once:

1. There is at least one result: show the results. If some requested lanes failed, add one compact
   `Some results could not load` banner with Retry above the list; never insert error or empty rows
   between results. No credential copy appears in this state.
2. No results and any requested lane is loading: show one `Searching…` state.
3. No results, every requested lane is terminal, and at least one failed: show one `Search failed`
   state with Retry. A mix of failed and empty lanes still resolves here, because an empty result
   set that is partly explained by a failure must not be reported as a confident `No catalog
   results`.
4. No results, every requested lane is terminal and empty, and sealed was skipped for missing
   credentials: show one `No catalog results` state with the `Set up sealed browsing` CTA beneath
   it. This is the single place credential copy may appear in the result list, and it replaces
   rather than duplicates the empty state.
5. No results, every requested lane is terminal and empty, credentials present or cached sealed
   results usable: show one `No catalog results` state with no CTA.

Missing credentials never block or fail the card search, and never produce a lane-level error
message in the list.

Remove/replace the tests `testBrowseCardsScopeDoesNotStartSealedSearch` and
`testBrowseSealedScopePassesTheSelectedGameAndSkipsCardSearch`. Keep and update the debounce test to
prove both kinds start, the selected game limits both providers, and no UI scope state exists.

## 5. Game screen: Cards and Sealed

Add:

```swift
private enum CatalogGameContentKind: String, CaseIterable, Identifiable {
    case cards = "Cards"
    case sealed = "Sealed"
}
```

`CatalogGameBrowseView` owns `@State private var contentKind: CatalogGameContentKind = .cards` and
uses a segmented Picker. The navigation title is only the game name (`Pokémon`, `Magic`), not
`Pokémon Cards`; the selected segment supplies the kind context.

Cards retains the existing all-card feed, card search, and pagination. Sealed embeds
`SealedSetDirectoryContent`.

Search field: the screen keeps exactly one `.searchable`, owned by `CatalogGameBrowseView`, and its
prompt follows the segment — `Search <game> cards` under `.cards`, `Search <game> sets` under
`.sealed`. Clear the shared search text on segment change; carrying a card query into a vendor-set
filter produces a silently empty directory. Pass the text down to `SealedSetDirectoryContent` as
described in §2 and keep it feeding the existing card-search `.task(id:)` under `.cards`.

Sets toolbar link: show it only under `.cards`. It navigates to `CatalogSetListView`, which is
card-set scoped and has no meaning while the vendor directory is on screen.

Preserving state across segment switches is a correctness requirement, not a nicety. The existing
card feed keeps `cards`, `nextSetIndex`, `activeSetIndex`, `cursor`, and the search fields in
`@State`, and SwiftUI destroys `@State` when a view leaves an `if`/`else` branch — so a naive
`if contentKind == .cards { … } else { … }` discards every loaded page and re-runs
`.task { await loadDefaultMore() }` on each toggle, spending provider requests. Either keep both
subtrees alive and toggle visibility (a `ZStack` with `opacity`/`allowsHitTesting`, or `.hidden`),
or hoist the card feed's state out of the subview into the container. Add a test or an instrumented
check that toggling Cards → Sealed → Cards issues no new card request when a page is already
loaded. `SealedBrowseModel` is a reference type owned by `BrowseViewModel`, so its cache and lanes
survive either approach.

Credential behavior:

- configured: show/load the vendor directory on first selection of Sealed;
- unconfigured with cached directory: show cached sets and a non-blocking stale/setup note;
- unconfigured without cached directory: show only the Settings CTA, no empty game/set rows and no
  provider request. This requires the `.task` guard in §2; `loadSetsIfNeeded` does not check
  `isConfigured` itself.

`SealedBrowseModel.sets` holds one game's directory at a time (`loadedGame`). Entering Sealed for a
second game replaces it, which is the existing contract — do not treat the replacement as a bug or
add a per-game directory cache in this slice.

## 6. Artwork and missing-art states

The release rail must not make a generic symbol-on-flat-color placeholder look like failed content.
For a set whose artwork URL is nil or whose fetch/decode fails, render a text-forward state *inside
the artwork box*:

```text
<full set name, up to 3 lines>
<set code> · Artwork lookup will retry later
```

`CatalogSetTile` already renders `set.name` below the artwork box and `set.code` in its metadata
line. When the missing-art state is showing, suppress those two so one tile does not print the name
twice and the code twice. State that explicitly in the implementation rather than leaving it to the
reader.

Precedence, so the rules in this section and §7 cannot contradict each other:

1. `set.game == .magic` → keep the existing typographic set-code fallback. Magic never enters the
   missing-art state, because Scryfall set symbols are SVG and a Magic tile is not failing when it
   shows its code. Note that a Magic rail tile then shows its code in the artwork box, its metadata
   line, *and* a game badge (§7) — drop the metadata-line code for Magic rail tiles to avoid
   printing it twice.
2. Pokémon with both `symbolURL` and `logoURL` nil → missing-art state immediately, with no loader
   involvement.
3. Pokémon with a URL → placeholder/spinner while loading, missing-art state only on terminal
   failure.

The state must be visually deliberate: use the existing stable tint, no broken-image symbol, and
keep the title readable at default and accessibility Dynamic Type sizes.

To distinguish loading from failure, extend `CatalogCachedImage` with an optional phase callback or
extract a `CatalogSetArtwork` loader that reuses the same memory/disk cache and in-flight
coalescing. Do not add a second URLSession/cache implementation. Two details in the current loader
make a naive phase callback wrong:

- `CatalogImageLoader.load(nil, …)` returns with `failed == false` and `isLoading == false`. A nil
  URL never produces a failure phase, so case 2 above must be decided by the caller from the URLs,
  not by waiting for the loader.
- `CatalogCachedImage` recurses through `fallbacks` when the primary fails. Terminal failure is only
  reached when the *last* URL in that chain fails; a callback fired from the outer view would report
  failure while the fallback is still loading and flash the missing-art state over a request that is
  about to succeed. Report the phase from the innermost view in the chain, or resolve the chain in
  the extracted loader.

Because a nil-URL set has nothing to retry until the next catalog refresh, keep the copy as the
neutral `Artwork lookup will retry later` in §11 and make sure a catalog refresh does re-evaluate
the URL; do not promise a retry the tile itself will never perform. Pokémon keeps PNG artwork.

## 7. Release rail

Replace catalog-order-only `justReleased` with a truthful dated-first policy. Use these constants so
the rule is testable and not scattered through the view:

```swift
static let newReleaseWindow: TimeInterval = 45 * 86_400
static let minimumRailCardCount = 10
static let releaseRailLimit = 3
static let railPerGameFallbackLimit = 2
```

`CatalogSetOrdering.isNew` already hard-codes `window: TimeInterval = 45 * 86_400`. Change its
default to `newReleaseWindow` in the same change so the two cannot drift apart.

Signature, with `now` injected so the dated branch is testable without freezing the clock globally:

```swift
static func releaseRail(
    from setsByGame: [CardGame: [CatalogSet]],
    now: Date = .now
) -> CatalogReleaseRail
```

The current `justReleased(from:perGameLimit:limit:)` is replaced by this; update the call site at
`BrowseView.justReleasedSets` to consume the returned value rather than re-deriving the title or the
badge flag.

Algorithm at `now`:

1. Exclude sets with known `cardCount < 10`. Unknown counts remain eligible because absence of a
   provider count is not proof that the set is a stub.
2. Build `datedRecent` by flattening every game's eligible sets: `releaseDate` is non-nil, not in
   the future relative to `now`, and within `newReleaseWindow` of `now`. Reuse `isNew(_:now:window:)`
   so one predicate defines "new" everywhere.
3. If `datedRecent` is non-empty, sort by actual `releaseDate` descending with an `id` ascending
   tie-break, take `releaseRailLimit`, title the rail `Just released`, and show `NEW` on every tile.
   There is deliberately no per-game cap on this branch: if one game genuinely shipped the three
   most recent sets, the rail says so. Cover that case in a test so a later reader does not
   "fix" it.
4. Only when `datedRecent` is empty, take up to `railPerGameFallbackLimit` eligible sets per game via
   `newestFirst`, merge, re-sort with `newestFirst`, take `releaseRailLimit`, title the rail
   `Recent sets`, and show no `NEW` badge. This is an explicit fallback, not a claim about release
   recency.

Note that `CatalogSet.releaseOrder` is `sortRank` for Pokémon and a date-derived integer for Magic,
so `newestFirst` is a catalog-order sort and is not comparable across games as a date. That is
precisely why branch 3 sorts on `releaseDate` directly and branch 4 does not claim recency.

Return `CatalogReleaseRail(title:sets:showsNewBadges:)` rather than making the view infer which path
won; an empty `sets` means the view renders no rail at all. Keep the existing
`isCatalogLoadedForRail` gate so the rail does not render a half-loaded catalog. Update existing
ordering tests to cover dated inclusion boundaries (exactly at `now`, exactly at the window edge,
one second past it), future dates, one-card exclusion, unknown counts, mixed games, one game
supplying all three, and fallback naming/badge behavior.

Each rail tile shows its game badge. Size tiles relative to the horizontal scroll viewport rather
than at a fixed 248 points:

```swift
.containerRelativeFrame(.horizontal) { width, _ in
    min(max(width * 0.72, 220), 300)
}
```

Remove the existing `.frame(width: 248)` from the rail tile when adding this; leaving both applies
a fixed width inside a container-relative one. Keep 12-point spacing and two/three-line title
clamping inside the tile. At a standard iPhone width,
the first tile must be complete and a consistent portion of the second visible; no title may be
clipped by the viewport. Reduce `CatalogSetTileLayout.rail.artworkHeight` from 134 to 112 points and
use 8-point artwork padding. Available artwork scales to fit the full container; missing artwork
uses the text-forward state from §6. This prevents the rail from spending a third of the viewport on
mostly empty color fields.

## 8. Set directory corrections

### Progress and grammar

> Superseded in part by Slice B of
> [`browse_set_directory_remediation_plan.md`](browse_set_directory_remediation_plan.md)
> (audit C-13). The `n of m` shape, the `3 owned` fallback, the hidden-when-zero
> rule, and the shared pluralization helper below all stand. What changes is the
> source of both numbers: they come from the built master-set checklist rather
> than from `set.cardCount`, and the Pokémon unit becomes `variations` so the
> tile and the set screen state the same total. Rewrite this subsection when that
> slice lands.

`CatalogSetTile.completionFooter` shows `3 of 207`, not `3`. When total is unknown it shows
`3 owned` and omits the progress bar. Continue hiding the footer when owned is zero. Keep the
existing VoiceOver label and update it to share the same pluralization helper.

All count copy uses a helper, for example:

```swift
func countLabel(_ count: Int, singular: String, plural: String) -> String
```

Required outputs include `1 card`, `2 cards`, `1 set`, `2 sets`, `1 sealed product`, and
`2 sealed products`.

### Filters and sort

Remove the top-bar sort menu. In `setListFilters`, render these controls in one horizontal row:

- selectable `All sets`,
- selectable `Started`,
- a Menu whose label is the active sort, e.g. `Newest first` plus a down chevron.

The sort chip's visible label must update immediately for `Oldest first`, `Name A–Z`, and
`Most complete`. Keep `CatalogSetListSort` and `CatalogSetListFilter`; they already have the correct
separation from card-level sort/filter types.

Carry the removed toolbar item's accessibility label onto the chip (`Sort sets, <sort.label>`) so
the control is still announced as a sort control and not as bare text. The chip row is a horizontal
`ScrollView` with `contentMargins` and negative horizontal padding; keep that container and add the
Menu as a third item rather than restructuring the row, and confirm the Menu's popover anchors
correctly from inside a scroll view at accessibility Dynamic Type sizes.

### Master set rules

Replace the navigation-looking DisclosureGroup label with a custom full-width Button and content:

- collapsed indicator: `chevron.down`,
- expanded indicator: rotate the same glyph 180 degrees or use `chevron.up`,
- animate only the indicator and inserted explanatory text,
- preserve a 44-point target and expose expanded/collapsed accessibility value.

The control must not use blue navigation-link styling or `chevron.right`.

## 9. Layout hierarchy and safe areas

Use one visual hierarchy on the root:

- navigation title: `Catalog`, inline;
- hero section: `Just released` / `Recent sets`, `.title2.bold()`;
- game section: `Browse by game`, `.headline` or `.title3.semibold`;
- no third Sealed heading.

Add `.safeAreaPadding(.bottom, 24)` (or an equivalent `safeAreaInset` spacer) to scroll content on
Catalog, game, set-list, and set-detail screens. Apply it to content, not a background overlay. Test
on the real tab-hosted route so the final text/control is fully visible above the tab bar and home
indicator.

At accessibility Dynamic Type sizes, keep the existing set-grid one-column collapse. Release tiles
may grow vertically; do not fix the entire tile height. Keep metadata digits monospaced.

## 10. One card tile, multiple finish variants

The Pokémon checklist deliberately expands a numbered card into multiple
`CatalogCardSummary` values (`masterSetVariant`), but the visual grid must group those summaries.

Build groups before `CatalogCardGrid` renders:

- Pokémon grouping identity: game + set ID + provider ID + canonical collector number, ignoring
  `masterSetVariant`. `CatalogCardSummary.id` is already `setID.id : providerID :
  masterSetVariant?.id`, so this is exactly that identity minus the variant component;
- Magic summaries bypass grouping and each produce a singleton display group, so distinct
  treatments can never collapse accidentally;
- preserve first-seen group order so current sorting remains stable;
- order Pokémon variants using an explicit rank: Normal, Reverse Holo, Poké Ball, Master Ball,
  Dusk Ball, Friend Ball, Quick Ball, Love Ball, then unknown labels alphabetically.

Render one artwork/name/number block per group. Under it, render a wrapping chip row for all
available summaries. Each chip uses `masterSetVariantLabel` (or `Standard` when nil), and visually
indicates ownership using `CatalogOwnershipIndex.owns(_:)`; include `Owned` in its accessibility
label. This makes the finish distinction readable without duplicating artwork.

Do not nest NavigationLinks. The artwork/name area navigates to the preferred summary (Normal when
present, otherwise the first ranked variant). Each variant chip is its own NavigationLink to
`CatalogCardDetailView` with that exact summary.

A group with one summary keeps one whole-tile navigation target, and may omit the chip **only when
that summary's `masterSetVariantLabel` is nil**. When a card's sole slot is a named finish — the
builder sets `isSoleSlotForCard` with a non-nil `masterSetVariant` for exactly this case — keep the
chip. Dropping it would hide that the single owned-or-missing slot is, say, Reverse Holo rather than
Normal, which is the distinction this whole section exists to make visible.

Price display must not silently merge variants. If prices differ, show price on the corresponding
variant chip or omit group-level price; only show a group-level price when every summary resolves to
the same amount. Ownership quantity follows the same rule: do not sum variants into a number that
looks like one finish's quantity.

Add tests proving:

- Normal and Reverse summaries become one display group with two chips;
- different numbered cards never group;
- Pokémon print-run-specific set IDs never group (`CatalogSetID.id` already carries
  `pokemonPrintRun`, so assert the behaviour rather than adding a second guard for it);
- different Magic treatments never group, and each yields a distinct group `id`;
- a group whose sole summary has a non-nil `masterSetVariantLabel` still renders its chip;
- a summary whose collector number does not canonicalize still produces a distinct group;
- group `id`s are unique across a whole set's grouped output, so `ForEach` cannot collapse rows;
- tapping/selecting a variant routes the exact original summary;
- set completion still counts summary slots and is unchanged by display grouping.

## 11. Copy inventory

Use these strings exactly unless product copy is revised separately:

| Surface | Copy |
| --- | --- |
| Root search placeholder | `Search the catalog` |
| Root game section | `Browse by game` |
| Dated rail | `Just released` |
| Undated fallback rail | `Recent sets` |
| Empty unified search | `No catalog results` |
| Game segments | `Cards`, `Sealed` |
| Sealed directory explanation | `Sets are grouped by the pricing vendor.` |
| Missing artwork | `Artwork lookup will retry later` |
| Credential CTA | `Set up sealed browsing` |

Delete `Everything in the catalog`, `Search cards and sealed products`, per-game `No … printings
found`, per-game `No … sealed products found`, and the root `Sealed products` heading.

## 12. Verification and acceptance

### Unit tests

Run `TradingCardScannerTests/BrowseFeatureTests` and add coverage for:

- unified-result IDs and relevance ordering;
- state reduction for loading, partial success, total empty, partial failure, and total failure;
- selected-game propagation to both providers;
- no-credential behavior with and without cached sealed results;
- game ownership counts using all rows while fan artwork uses only three;
- release-rail dated/fallback policy and minimum count;
- singular/plural copy and `owned of total` formatting;
- card display grouping, variant ordering, and group-id uniqueness;
- segment switching preserving loaded card pages and issuing no redundant provider request;
- no sealed directory request while unconfigured and uncached;
- existing set sort, grouping, completion, cache, and pagination tests remain green.

Delete `BrowseFeatureTests.testBrowseCardsScopeDoesNotStartSealedSearch` and
`testBrowseSealedScopePassesTheSelectedGameAndSkipsCardSearch`, and drop the
`XCTAssertEqual(model.searchScope, .all)` assertion and the `model.searchScope = …` lines from the
remaining tests; `BrowseScope` no longer exists, so leaving any of them breaks compilation of the
test target rather than failing a test.

### UI / screenshot matrix

Capture the actual Collection → Catalog route at minimum in:

1. credentials configured, default Dynamic Type, light mode;
2. credentials absent, default Dynamic Type, light mode;
3. search with mixed card/sealed results;
4. search with one successful result and all other lanes empty;
5. total-empty search;
6. set directory with `1 card` and with owned progress (`3 of 207`);
7. release rail with missing artwork and mixed games;
8. Pokémon set with Normal + Reverse variants;
9. dark mode;
10. accessibility Dynamic Type.

For every capture verify:

- Collection is the selected tab and Catalog has a normal back path;
- root has one game row per game and no separate sealed hierarchy;
- sealed is reachable inside each game;
- no dead sealed links exist without credentials;
- result rows are globally interleaved and carry kind/game badges;
- only one empty statement appears for a fully empty query;
- rail tiles show an intentional peek, clamp titles, and name their game;
- no content is obscured by the tab bar or home indicator;
- the set progress denominator is visible;
- duplicate finish artwork is eliminated;
- missing artwork explains itself.

### Regression constraints

Do not change:

- `CatalogSetID`, `CatalogCardSummary.id`, or collection key construction;
- vendor-native `SealedSetSummary.id` or infer a card-set/sealed-set mapping;
- `CatalogOwnershipIndex` / `SetCompletionCalculator` ownership semantics;
- sealed request budgeting, caching, or credential storage;
- `backfillPokemonReleaseOrder()` or its task;
- Portfolio, Scan, or Centering tab structure;
- detail add-to-collection behavior.

## 13. Implementation order

1. Add pure presentation models/helpers and their tests: count grammar, game summary, release rail,
   unified-result ranking/state, and card display grouping.
2. Refactor sealed directory into embeddable content without changing its data model.
3. Replace the root parallel sealed hierarchy with the game-level Cards/Sealed container and wire
   the Settings closure.
4. Replace sectioned search with the unified result list and consolidated state/pagination.
5. Correct release eligibility, tile sizing, game badges, and missing-art handling.
6. Correct set progress copy, sort chip, disclosure indicator, hierarchy, and bottom safe area.
7. Group card variants in the grid while preserving exact-summary navigation and ownership.
8. Run the focused suites, then the full test target, then complete the screenshot matrix.

Steps 2–4 are one architectural slice and should land together: deleting the root sealed chooser
without adding the in-game destination would temporarily remove discoverability. Step 4 also deletes
`BrowseScope`, so the scope-based tests named in §12 must be removed in that same commit or the test
target stops compiling. Step 7 should land
with its grouping tests because it changes presentation identity while persistence identity must
remain untouched.
