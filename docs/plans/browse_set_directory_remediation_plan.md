# Browse set directory — artwork, counts, and price sort

**Status:** current plan — proposed 2026-09-15, **not implemented**. No code in
this plan has landed; every acceptance box below is open. Probe results in
*Verified findings* were taken against the bundled snapshot in this checkout and
against live TCGdex/Limitless on 2026-09-15.

**Concern owned:** three defects reported from the Pokémon set directory and set
screen, and the shared cause behind them.

1. Set tiles show a set symbol for some sets and a set logo for others, and
   three bundled assets are the wrong artwork.
2. The set directory prints a card count that is zero for 45 sets and disagrees
   with the set screen's denominator for 134 of 160 sets.
3. Sorting a set by price blocks until every card in the set has been priced.

**Code owned:** [`CatalogSetTile.swift`](../../TradingCardScanner/Views/CatalogSetTile.swift),
[`ArtworkFallbacks.swift`](../../TradingCardScanner/Services/ArtworkFallbacks.swift),
`PokemonMasterSetDefinition` / `CatalogCacheStore` / `BrowseCatalog` in
[`BrowseCatalog.swift`](../../TradingCardScanner/Services/BrowseCatalog.swift),
`CatalogSetListView` / `CatalogSetGrid` / `CatalogSetCardsView` in
[`BrowseView.swift`](../../TradingCardScanner/Views/BrowseView.swift),
`PokemonChecklistSnapshotEntry` / `PokemonMasterSetChecklistBuilder` in
[`PokemonChecklistSnapshot.swift`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift),
and `CatalogOwnershipIndex` / `CatalogSet` in
[`BrowseCatalogModels.swift`](../../TradingCardScanner/Models/BrowseCatalogModels.swift).

This plan does not restate the Browse contract. The acceptance contract stays in
[`browse_screen_spec.md`](browse_screen_spec.md); the artwork fallback chain
stays in [`artwork-fallback-plan.md`](artwork-fallback-plan.md). Where this plan
changes either, the change is recorded in *Reconciliation* below and must be
carried into those documents when the slice lands.

---

## Verified findings

### F1 — the set tile asks for the wrong artwork kind

`CatalogSetTile` requests `kind: .symbol`
([`CatalogSetTile.swift:43`](../../TradingCardScanner/Views/CatalogSetTile.swift:43)).
The root release rail requests `kind: .logo`
([`BrowseView.swift:675`](../../TradingCardScanner/Views/BrowseView.swift:675)).

`PokemonArtworkFallbacks.setSource`
([`ArtworkFallbacks.swift:86`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:86))
orders remote candidates as *requested kind → alternate kind → parent logo*. The
tile therefore shows a symbol wherever TCGdex publishes one and a logo wherever
it does not. In the bundled snapshot:

| Condition | Sets | Tile shows today |
| --- | --- | --- |
| `logoURL` and `symbolURL` both present | 132 | symbol |
| `symbolURL` only | 4 (`bog`, `sma`, `sp`, `sv05`) | symbol |
| `logoURL` only | 3 | logo |
| neither | 21 | bundled asset, else missing-art state |

This is the reported "Pitch Black has no set artwork": `me05` publishes both, so
the tile renders the small `PBL` symbol plaque, while `me03`/`me04`/`me02.5`
publish no symbol and render full logos beside it.

### F2 — two bundled set assets are the wrong artwork

The 36 bundled PNGs were vendored from `1niceroli/ptcg-assets`
(see [`artwork-fallback-plan.md`](artwork-fallback-plan.md) § *Vendored asset
refresh*). Three are wrong for this app's use:

| Asset | Problem | Evidence |
| --- | --- | --- |
| `PokemonSetArtwork_sve_logo` | Generic "Pokémon Trading Card Game" wordmark, not an SVE identity. Byte-identical to `PokemonSetArtwork_base1_logo` (`md5 bea522d0f5a36c6c3833825b666ab583`). | Upstream `sve/logo.png` is the repository's default placeholder. |
| `PokemonSetArtwork_bog_logo` | Same generic wordmark at a different size (`md5 a5f19cdd1bc97eb3b62d6b5bd8505184`). | Upstream `bp/logo.png` is the same default. |
| `PokemonSetArtwork_cel25cc_symbol` | Unrelated glyph; not the Classic Collection identity. This is the reported "Celebrations Classic Collection artwork makes no sense". | Upstream `cel25c/symbol.png`. `PokemonSetArtwork_cel25cc_logo` in the same catalog *is* the correct Celebrations wordmark. |

`base1_logo` is **not** a defect: the printed Base Set logo is the Pokémon
Trading Card Game wordmark. Do not remove it.

### F3 — the bundled logo asset is unreachable when only a remote symbol exists

`SetSource` places every remote URL ahead of every local asset, so for a set with
no `logoURL` but a `symbolURL`, a `kind: .logo` request still resolves to the
remote symbol and the bundled logo is never reached. Affects `bog`, `sma`,
`sv05`, `cel25cc`, `sm3.5`, `sm7.5`, `sve`, and the six gallery subsets.

### F4 — `masterCount` reads a published zero as a published value

`PokemonMasterSetDefinition.masterCount`
([`BrowseCatalog.swift:1061`](../../TradingCardScanner/Services/BrowseCatalog.swift:1061))
falls back to `cardCount.total` only when `normal` and `holo` are both `nil`.
TCGdex publishes **zeros, not nulls**, for the whole BW/XY/SM era:

```text
GET https://api.tcgdex.net/v2/en/sets/sm115   (Hidden Fates)
cardCount = { firstEd: 0, holo: 0, normal: 0, official: 68, reverse: 0, total: 69 }
masterCount = (0 + 0) + 0 = 0
```

45 of 160 bundled entries carry `cardCount: 0` for this reason — every `bw*`,
`xy*`, and `sm*` set plus `dc1`, `det1`, `dv1`, `g1`, `sma`, `rc`, `sp`, `wp`,
`xya`. This is the reported "0 cards on the list, cards when you tap in": the
set screen's denominator comes from the built checklist (69 rows for `sm115`),
not from `cardCount`.

Side effect to preserve deliberately: `CatalogSetOrdering.releaseRail`
([`BrowseView.swift:918`](../../TradingCardScanner/Views/BrowseView.swift:918))
excludes sets with `cardCount < 10`, so those 45 sets are currently rail-ineligible
by accident. Fixing F4 makes them eligible again, which is correct.

### F5 — the tile and the set screen count different things

| Surface | Numerator | Denominator | Unit |
| --- | --- | --- | --- |
| Tile, via `CatalogOwnershipIndex.progress(for:)` ([`BrowseCatalogModels.swift:927`](../../TradingCardScanner/Models/BrowseCatalogModels.swift:927)) | distinct collector numbers owned | `set.cardCount`, a provider-derived estimate | `cards` |
| Set screen, via `progress(for: slots)` ([`BrowseCatalogModels.swift:944`](../../TradingCardScanner/Models/BrowseCatalogModels.swift:944)) | master-set slots owned | built checklist length | `variations` |

Measured across the bundled snapshot, `entry.set.cardCount` differs from the
standard-tier slot count for **134 of 160 entries**, independently of F4:

| Set | Tile denominator | Set-screen denominator (standard) |
| --- | --- | --- |
| `me01` MEG | 359 | 328 |
| `me02.5` ASC | 629 | 484 |
| `me04` CRI | 207 | 203 |
| `me05` PBL | 200 | 199 |
| `sm115` HIF | 0 | 69 |

F4 is a subset of F5. Fixing F4 alone changes 45 tiles from `0` to a number that
still does not match the set screen.

### F6 — one Limitless set code is missing from the allow-list

844 of 31,872 bundled card rows have no `imageURL`, spread over 22 set codes.
`LimitlessArtwork.supportedSetCodes`
([`ArtworkFallbacks.swift:178`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:178))
already covers all but nine of them. Probed 2026-09-15 against
`https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci`:

| Code | Rows | In allow-list | Probe | Disposition |
| --- | --- | --- | --- | --- |
| `MEE` Mega Evolution Energy | 16 | no | `MEE_001…MEE_008_R_EN_XS.png` → 200 | **Add.** This is the reported "Mega Evolution energy cards have no artwork". |
| `BOG` | 20 | no | `BOG_001` → 403 | Keep excluded |
| `AQ` | 49 | no | no coverage | Keep excluded |
| `SK` | 32 | no | no coverage | Keep excluded |
| `EX5.5` | 5 | no | no coverage | Keep excluded |
| `EXU` | 28 | no | no coverage | Keep excluded |
| `MFB` | 48 | no | `MFB_001` → 403 | Keep excluded |
| `RR` | 2 | no | `RR_001` → 403 | Keep excluded |
| `XYA` | 6 | no | no coverage | Keep excluded |

`MEE` has eight official cards; the 16 rows are two variant slots each, so all
16 resolve from `MEE_001`–`MEE_008`. The existing collector-number
normalization is correct and needs no change — re-probed `ASR_TG1` 200 /
`ASR_TG01` 403, `SHF_SV1` 200 / `SHF_SV001` 403, `CRZ_GG1` 200 / `CRZ_GG01` 403,
`SLG_001` 200 / `SLG_1` 403.

`SVE` (128 rows) and `CEL`/`cel25cc` (26 rows) are already in the allow-list and
already resolve (`SVE_001` → 200, `CEL_CC1` → 200). They need no change.

### F7 — three bundled sets have no cards at all

`rc` (Radiant Collection), `sp` (Sample), and `wp` (W Promotional) have zero
checklist rows and no artwork of any kind. They occupy directory tiles that can
never be opened usefully. `PokemonMasterSetDefinition.includesInSetDirectory`
([`BrowseCatalog.swift:1045`](../../TradingCardScanner/Services/BrowseCatalog.swift:1045))
filters by name phrase only and does not exclude them.

### F8 — price sort is an unbounded per-slot crawl behind a blocking gate

Three compounding causes:

1. **Per-card network.** `BrowseCatalog.sortPrice(for:)`
   ([`BrowseCatalog.swift:316`](../../TradingCardScanner/Services/BrowseCatalog.swift:316))
   calls `details(for:)`, which calls `pokemonTransport.fetchCard(id:)`. One
   HTTP request per card, six concurrent
   ([`BrowseCatalog.swift:287`](../../TradingCardScanner/Services/BrowseCatalog.swift:287)).
   TCGdex publishes no bulk price endpoint — probed the REST `/cards?set=` list
   projection and the v2 GraphQL schema on 2026-09-15; neither exposes
   `pricing`. The request count is therefore irreducible below one per
   *distinct card*.
2. **Per-slot duplication.** `detailCache` is keyed on `summary.id`, which
   includes `masterSetVariant?.id`
   ([`BrowseCatalogModels.swift:186`](../../TradingCardScanner/Models/BrowseCatalogModels.swift:186)).
   Every variant slot of one card is a separate cache entry and a separate
   fetch. `sve` is 128 slots over 18 cards (7×); `me01` is 372 slots over 132
   cards (~2.8×).
3. **Blocking gate.** `visibleCards`
   ([`BrowseView.swift:1694`](../../TradingCardScanner/Views/BrowseView.swift:1694))
   substitutes `.numberLowToHigh` until `hasLoadedPrices`, and `sortPrices`
   returns only after its whole task group drains
   ([`BrowseView.swift:1918`](../../TradingCardScanner/Views/BrowseView.swift:1918)).
   Nothing reorders until the last card resolves.

`sortPriceCache` and `resolvedSortPrices` are in-memory actor state discarded on
`didReceiveMemoryWarning` ([`BrowseCatalog.swift:382`](../../TradingCardScanner/Services/BrowseCatalog.swift:382)),
so the crawl repeats on the next launch.

---

## Governing constraints

These bound every slice. Violating one is a defect, not a tradeoff.

- **No fabricated counts.** A denominator shown to the user must be a number the
  app can derive from a checklist it actually holds, or the provider's own
  printed denominator. Never an interpolation between the two.
- **One denominator per set.** After Slice B the set tile and the set screen must
  display the same total for the same set and the same master-set tier. A test
  asserts this directly; it is not an eyeball check.
- **No new provider.** Card artwork comes from TCGdex, the derived Limitless URL,
  and the bundled assets, in that order. Derived URLs only — never a Limitless
  search or discovery request ([`artwork-fallback-plan.md`](artwork-fallback-plan.md)
  § *Out of scope*).
- **Snapshot schema compatibility.** A downloaded overlay written by an older
  build must keep decoding, or `PokemonChecklistSnapshotVersion.schema` must be
  bumped so `isSupported` rejects it. Silent partial decode is not acceptable.
- **No blocking work on the main actor** in the set directory. 160 tiles must not
  each touch the checklist store.

---

## Slice A — one artwork kind, and correct bundled assets

Independent of B and C. Land first; it is the smallest change with the largest
visible effect.

### A1 — request the logo in the set grid

In [`CatalogSetTile.swift:43`](../../TradingCardScanner/Views/CatalogSetTile.swift:43),
change `kind: .symbol` to `kind: .logo`.

That is the whole change. `CatalogSetTileLayout` has no per-layout kind and must
not gain one: the grid and the rail show the same set and must show the same
artwork.

### A2 — prefer a bundled asset of the requested kind over a remote alternate kind

Resolves F3. In `PokemonArtworkFallbacks.setSource`
([`ArtworkFallbacks.swift:86`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:86)),
the candidate order becomes:

1. remote URL of the **requested** kind, when present
2. bundled asset of the **requested** kind, when present
3. remote URL of the **alternate** kind, when present
4. inherited parent logo, when present (Pokémon only, `kind == .logo`)
5. bundled asset of the **alternate** kind, when present

`SetSource` currently models this as `primaryURL` + `fallbacks: [URL]` +
`localAssetName` + `localFallbackAssetNames`, which cannot express a local asset
in the middle of a remote chain. Replace the four fields with one ordered array:

```swift
enum Candidate: Equatable, Sendable {
    case remote(URL)
    case bundled(String)
}

struct SetSource: Equatable, Sendable {
    let candidates: [Candidate]
}
```

`CatalogCachedImage`
([`BrowseView.swift:2228`](../../TradingCardScanner/Views/BrowseView.swift:2228))
already recurses through an ordered chain; extend it to take
`candidates: [PokemonArtworkFallbacks.Candidate]` and, on `.bundled`, render
`UIImage(named:)` and report `.loaded` when the image exists or advance to the
next candidate when it does not. Keep the existing `url` / `fallbacks` /
`localAssetName` initializer as a thin shim so `CatalogGameArtwork`
([`BrowseView.swift:675`](../../TradingCardScanner/Views/BrowseView.swift:675))
and `CatalogArtworkView` need no change in this slice.

Preserve both existing behaviours exactly:

- the phase callback still fires from the **innermost** view in the chain only
  ([`browse_screen_spec.md`](browse_screen_spec.md) § 6), so a mid-chain failure
  never flashes the missing-art state;
- `CatalogSetTile.isMissingArtwork` still resolves from the candidate list, not
  from a load phase, when the list is empty.

### A3 — remove the three wrong bundled assets

`git rm -r` these image sets and their `Contents.json`:

- `TradingCardScanner/Assets.xcassets/PokemonSetArtwork_sve_logo.imageset/`
- `TradingCardScanner/Assets.xcassets/PokemonSetArtwork_bog_logo.imageset/`
- `TradingCardScanner/Assets.xcassets/PokemonSetArtwork_cel25cc_symbol.imageset/`

Do **not** replace them with substitutes. After removal each set resolves
honestly through A2:

| Set | Resolves to |
| --- | --- |
| `sve` | bundled `sve_symbol` — the real printed SVE symbol plaque |
| `bog` | remote `symbolURL` |
| `cel25cc` | inherited Celebrations logo from A4, with bundled `cel25cc_logo` behind it |

`PokemonArtworkFallbacks.localSourceIDs`
([`ArtworkFallbacks.swift:50`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:50))
maps provider ID → source ID and is not per-kind, so it needs no edit;
`localAssetName(forProviderID:kind:)` returns a name whose asset no longer
exists, and A2's candidate walk skips a `.bundled` candidate that
`UIImage(named:)` cannot load. Assert that skip in a test rather than relying on
it.

### A4 — inherit the Celebrations logo for the Classic Collection

Add to `PokemonArtworkFallbacks.parentSetIDs`
([`ArtworkFallbacks.swift:38`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:38)):

```swift
"cel25cc": "cel25"
```

`parentLogoURL` hardcodes the `swsh` series path segment. `cel25` is also in the
`swsh` series (`https://assets.tcgdex.net/en/swsh/cel25/logo.png`, probed 200 on
2026-09-15), so the existing builder is correct as written. If a future parent
falls outside `swsh`, carry the series in the map value rather than adding a
second URL builder.

### A5 — add `MEE` to the Limitless allow-list

Add `"MEE"` to `LimitlessArtwork.supportedSetCodes`
([`ArtworkFallbacks.swift:178`](../../TradingCardScanner/Services/ArtworkFallbacks.swift:178)).
Add nothing else. The eight other uncovered codes in F6 are deliberate
exclusions and their rationale already lives in
[`artwork-fallback-plan.md`](artwork-fallback-plan.md) § P2.

### A6 — audit the remaining bundled logos

A1 promotes the bundled logo from a rarely-reached fallback to the artwork most
tiles resolve to, so every remaining bundled logo must be looked at once.
Verified already on 2026-09-15 as correct: `base1`, `cel25cc`, `me02`, `sm3.5`,
`sm7.5`, `sma`, `sv05`, `swsh12.5gg`. Remaining to check: `sv07`, `sv08`,
`sv08.5`, `swsh9tg`, `swsh10tg`, `swsh11tg`, `swsh12tg`, `swsh4.5sv`.

The failure signature is the upstream default: the generic "Pokémon Trading Card
Game" wordmark standing in for a set that has its own logo. Remove any such
asset per A3 rather than substituting one.

### A7 — deterministic verification

Add to `BrowseFeatureTests`
([`BrowseFeatureTests.swift:5`](../../TradingCardScannerTests/BrowseFeatureTests.swift:5)).

- [ ] `setSource(for:kind:.logo)` on a set with both URLs yields `logoURL` first.
- [ ] `setSource(for:kind:.logo)` on a set with `symbolURL` only and a bundled
      logo yields the bundled logo before the remote symbol (F3).
- [ ] `setSource(for:kind:.logo)` on `cel25cc` yields the `cel25` parent logo
      before any bundled asset (A4).
- [ ] A `.bundled` candidate naming a non-existent asset is skipped and the next
      candidate is used (A3).
- [ ] `setSource` on a Magic set yields no bundled candidates and no parent logo.
- [ ] `LimitlessArtwork.urls(setCode: "MEE", collectorNumber: "001")` is non-nil
      and ends `MEE/MEE_001_R_EN_XS.png` / `MEE_001_R_EN.png`.
- [ ] Every set code appearing on an `imageURL`-less row of the bundled snapshot
      is either in `supportedSetCodes` or in an explicit
      `knownUncoveredSetCodes` constant. This test is the regression guard for
      F6 and must fail when a future snapshot introduces a new uncovered code.
- [ ] Existing `CatalogCachedImage` fallback-traversal and phase-callback tests
      stay green unchanged.

### A8 — visual verification

- [ ] Debug Browse capture via `scripts/ui_build_and_shoot.sh` at the Pokémon set
      directory, light and dark, settled.
- [ ] Confirm in the capture: `me05` PBL, `me04` CRI, `me03` POR, and `me02.5`
      ASC all render logos at comparable weight; `cel25cc` renders the
      Celebrations wordmark; `sve` renders the SVE symbol plaque.
- [ ] Capture recorded under `artifacts/` per existing checklist practice and
      referenced from [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md).

---

## Slice B — one denominator per set

**Sequencing rule (blocking).** B1, B2, and B3 land together in one change.
Landing B1 or B2 without B3 produces a tile that divides a collector-number
count by a variation-slot count — a worse number than the one being replaced.
B4 is independent and may land separately.

### B1 — treat an all-zero variation breakdown as unpublished

In `PokemonMasterSetDefinition.masterCount`
([`BrowseCatalog.swift:1061`](../../TradingCardScanner/Services/BrowseCatalog.swift:1061)),
replace the `nil`-only guard:

```swift
let breakdown = (cardCount.normal ?? 0) + (cardCount.holo ?? 0) + (cardCount.reverse ?? 0)
let publishedBase: Int
if breakdown > 0 {
    publishedBase = (cardCount.normal ?? 0) + (cardCount.holo ?? 0)
} else {
    // TCGdex publishes zeros rather than nulls for the BW/XY/SM era. A zero
    // breakdown is an absent breakdown, not a set with no cards.
    publishedBase = cardCount.total
}
```

`reverse` participates in the emptiness test but not in `publishedBase`; the
existing `base + (cardCount.reverse ?? 0)` line is unchanged, so a set that
publishes only `reverse` is still counted correctly. The `firstEd` branch and
`adjustedCount` are unchanged.

This function keeps exactly one caller-visible meaning: *the best master-set
estimate derivable from the provider's set directory row, for a set whose
checklist has not been built*. After B2 it is used only on the live directory
path.

### B2 — carry the built checklist's slot counts in the manifest

Add to `PokemonMasterSetChecklistBuilder.BuiltSet`
([`PokemonChecklistSnapshot.swift:145`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift:145)),
computed in `build(providerSet:baseSet:cardDetails:)`
([`PokemonChecklistSnapshot.swift:189`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift:189))
from the `summaries` array it already produces:

```swift
let standardSlotCount: Int   // summaries.filter { !$0.isExpandedMasterSetVariant }.count
let expandedSlotCount: Int   // summaries.count
```

Add the same two fields to `PokemonChecklistSnapshotEntry`
([`PokemonChecklistSnapshot.swift:26`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift:26))
as `Int?`, defaulted to `nil` in the memberwise initializer next to the existing
`officialCount`, and populate them in
`PokemonChecklistSnapshot.from(builtSets:generatedAt:)`
([`PokemonChecklistSnapshot.swift:114`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift:114)).

They are `Int?` deliberately: Swift's synthesized `init(from:)` uses
`decodeIfPresent` for optionals, so a downloaded overlay written by an older
build keeps decoding and `PokemonChecklistSnapshotVersion.schema` stays at `1`.
An entry with `nil` counts falls back exactly as today.

Do **not** put these on `CatalogSet`. `CatalogSet` is persisted by
`CatalogCacheStore.storeSets` for both games and by every manifest; adding a
Pokémon-checklist-derived field to it would put a snapshot concept into the
Magic cache. Instead, resolve the display total at the point of use (B3).

Regenerate the bundled snapshot after this change:

```bash
./scripts/generate_pokemon_snapshot.sh
```

This is a network crawl of the whole TCGdex catalog and rewrites
`TradingCardScanner/PokemonChecklistSnapshot/`. Review the manifest diff before
committing: `entries` count must stay at 160 (161 if B4 has not landed yet
minus the three F7 rows — see B4) and `directoryFingerprint` will change.

### B3 — resolve tile completion from the checklist, not from `cardCount`

Introduce one owner for set-directory completion so both surfaces read the same
numbers.

**B3a — a value type for the answer.** In `BrowseCatalogModels.swift`:

```swift
struct CatalogSetCompletionIndex: Equatable, Sendable {
    /// Keyed by `CatalogSetID.id`.
    private let completions: [String: SetCompletion]
    func completion(for set: CatalogSet, tier: PokemonMasterSetTier) -> SetCompletion?
}
```

**B3b — an actor that builds it.** A new
`CatalogSetCompletionBuilder` actor (new file
`TradingCardScanner/Services/CatalogSetCompletion.swift`) with:

```swift
func build(
    sets: [CatalogSet],
    ownership: CatalogOwnershipIndex,
    tier: PokemonMasterSetTier
) async -> CatalogSetCompletionIndex
```

Algorithm, in this order:

1. Read `PokemonChecklistStore.shared.mergedEntries()`
   ([`PokemonChecklistSnapshot.swift:586`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift:586)).
   This is manifest-only and loads no checklist file.
2. For every set, the **denominator** is the first non-`nil` of:
   `entry.standardSlotCount` / `entry.expandedSlotCount` for the requested tier
   → `entry.officialCount` → `set.cardCount`. Magic sets always use
   `set.cardCount`.
3. Determine the sets the user could have progress in, from
   `ownership` alone: a set is a candidate when the ownership index holds at
   least one row whose normalized set code equals the set's code, or whose
   provider ID has the prefix `"\(set.providerID.lowercased())-"`. Expose this
   from `CatalogOwnershipIndex` as
   `func ownedSetKeys() -> (codes: Set<String>, providerIDs: Set<String>)` so the
   builder does not reach into its private storage.
4. Load `mergedChecklist(for:)` **only** for candidate sets, and compute the
   numerator with the existing `ownership.progress(for: slots)`
   ([`BrowseCatalogModels.swift:944`](../../TradingCardScanner/Models/BrowseCatalogModels.swift:944)),
   filtering to `!isExpandedMasterSetVariant` when `tier == .standard` — the
   identical filter `CatalogSetCardsView.masterSetSlots` uses
   ([`BrowseView.swift:1710`](../../TradingCardScanner/Views/BrowseView.swift:1710)).
5. Every non-candidate set gets `SetCompletion(owned: 0, total: <denominator>,
   unit: "variations")` with no file I/O. A set with no entry and no
   `cardCount` gets `total: nil`, which `completionFooter` already renders as
   `n owned` with no bar.

A typical collection touches a handful of sets, so step 4 loads a handful of
checklist files rather than all 160 (14 MB). Bound it anyway: if the candidate
count exceeds 40, keep the manifest denominator and the collector-number
numerator for the overflow and mark those completions `unit: "cards"`. State
that bound in the source comment; the mixed-unit case is honest because the
label carries the unit.

**B3c — a main-actor store.** `CatalogSetCompletionStore: ObservableObject`
alongside `CollectionProjectionStore`, publishing
`@Published private(set) var index: CatalogSetCompletionIndex?`. Rebuild when
`projectionStore.revision` changes, when the set list first appears, and when
`masterSetTier` changes. Coalesce overlapping rebuilds the way
`CollectionProjectionStore.rebuild` does
([`CollectionProjectionActor.swift:31`](../../TradingCardScanner/Services/CollectionProjectionActor.swift:31)) —
newest request wins, no dropped request.

**B3d — call sites.**

- `CatalogSetGrid` ([`BrowseView.swift:1647`](../../TradingCardScanner/Views/BrowseView.swift:1647))
  takes the index and passes
  `index?.completion(for: set, tier:) ?? owned.progress(for: set)` to
  `CatalogSetTile`. The existing call is the fallback for the first frame and
  for Magic.
- `CatalogSetListView` ([`BrowseView.swift:1392`](../../TradingCardScanner/Views/BrowseView.swift:1392))
  reads `@AppStorage("pokemonMasterSetTier")` — the same key
  `CatalogSetCardsView` uses ([`BrowseView.swift:1683`](../../TradingCardScanner/Views/BrowseView.swift:1683)) —
  and passes the tier down. Do not add a second tier control to the list screen;
  the list follows the tier the user set on a set screen.
- `CatalogSetOrdering.ordered(_:by:ownership:)` `.mostComplete`
  ([`BrowseView.swift:958`](../../TradingCardScanner/Views/BrowseView.swift:958))
  gains an optional `completions: CatalogSetCompletionIndex?` parameter and
  prefers it, so the sort orders by the fraction the tile displays. Keep the
  existing `ownership.progress(for:)` path as the fallback when the index is
  `nil`.

`CatalogSetTile.metadata` ([`CatalogSetTile.swift:95`](../../TradingCardScanner/Views/CatalogSetTile.swift:95))
keeps showing `set.cardCount`. After B1 and B2 that value is no longer zero, and
the metadata line answers "how big is this set" while the footer answers "how far
am I" — different questions, and the footer now carries an explicit unit.

### B4 — drop empty sets from the directory

Resolves F7. In `PokemonMasterSetDefinition.includesInSetDirectory`
([`BrowseCatalog.swift:1045`](../../TradingCardScanner/Services/BrowseCatalog.swift:1045)),
add to the existing id exclusion list beside `basep`/`swshp`/`svp`:

```swift
if ["rc", "sp", "wp"].contains(id) { return false }
```

An explicit id list, not a `cardCount == 0` rule: after B1 a genuine zero means
"the provider published nothing yet", and a set that has not yet had cards
uploaded must still appear. Regenerating the snapshot (B2) drops these three
entries; the manifest then holds 157 entries.

### B5 — deterministic verification

Add to `PokemonChecklistBrowseTests`
([`BrowseFeatureTests.swift:2199`](../../TradingCardScannerTests/BrowseFeatureTests.swift:2199)).

- [ ] `masterCount` with `{normal: 0, holo: 0, reverse: 0, total: 69}` returns
      `69`, not `0` (F4, exact `sm115` values).
- [ ] `masterCount` with `{normal: 40, holo: 0, reverse: 72, total: 24}` returns
      `112` — the published-breakdown path is unchanged (exact `sve` values).
- [ ] `masterCount` with `{normal: 0, holo: 0, reverse: 8, total: 8}` returns
      `8` — a reverse-only breakdown is not treated as empty.
- [ ] `masterCount` with `printRun: .firstEdition` and a zero breakdown still
      prefers `firstEd` when non-zero.
- [ ] `adjustedCount`'s Base Set Unlimited −1 rule still applies through the new
      branch.
- [ ] `BuiltSet.standardSlotCount` equals
      `cards.filter { !$0.isExpandedMasterSetVariant }.count` and
      `expandedSlotCount` equals `cards.count`, for a fixture with both tiers.
- [ ] A `PokemonChecklistSnapshotEntry` decoded from JSON with no
      `standardSlotCount` / `expandedSlotCount` keys decodes successfully with
      both `nil`, and `isSupported` stays `true` (schema compatibility).
- [ ] **Denominator parity (the Slice B acceptance test).** For every entry in
      the bundled snapshot, the total
      `CatalogSetCompletionBuilder` produces for the standard tier equals
      `mergedChecklist(for:).filter { !$0.isExpandedMasterSetVariant }.count`,
      and the same for the expanded tier against the unfiltered count. This is
      the test that fails today for 134 of 160 sets.
- [ ] A set with no owned rows yields `owned: 0` and does **not** trigger a
      `mergedChecklist` load — assert via a checklist store test double that
      counts loads.
- [ ] A set with owned rows yields the same `SetCompletion` value the set screen
      computes for the same tier.
- [ ] Above the 40-candidate bound the overflow completions carry
      `unit: "cards"` and the under-bound ones carry `unit: "variations"`.
- [ ] `includesInSetDirectory` rejects `rc`, `sp`, `wp` and still accepts a
      normal set whose `cardCount` is `nil`.
- [ ] `CatalogSetOrdering.releaseRail` still excludes sets below
      `minimumRailCardCount`, now measured against a non-zero count.
- [ ] Regenerated manifest has 157 entries and no entry with
      `standardSlotCount == nil`.

### B6 — visual verification

- [ ] Capture the Pokémon set directory and confirm `HIF` reads a non-zero card
      count, and that tapping `CRI` shows the same denominator its tile showed.
- [ ] Confirm `rc`, `sp`, `wp` tiles are gone.

---

## Slice C — price sort that responds immediately

Independent of A and B. C1 is a pure win and may land alone.

### C1 — dedupe the detail fetch by provider card

Resolves F8 cause 2. In `BrowseCatalog`:

- Key `detailCache` ([`BrowseCatalog.swift:47`](../../TradingCardScanner/Services/BrowseCatalog.swift:47))
  on `"\(summary.game.rawValue):\(summary.providerID.lowercased())"` instead of
  `summary.id`. The cached `CatalogCardDetails` holds the provider card and its
  set; neither depends on the variant slot, so this is a correctness-neutral
  key narrowing.
- In `sortPrices` ([`BrowseCatalog.swift:287`](../../TradingCardScanner/Services/BrowseCatalog.swift:287)),
  build the work list from **distinct provider IDs**, not from `cards`. Fetch
  each once, then map the result back onto every slot that shares the provider
  ID. Variant-specific pricing selection stays in `sortPrice(for:)`
  ([`BrowseCatalog.swift:316`](../../TradingCardScanner/Services/BrowseCatalog.swift:316)),
  which reads `summary.masterSetVariant` from the *slot*, so each slot still
  gets its own price from the one shared fetch.
- Keep `resolvedSortPrices` keyed on `summary.id`: resolution is per slot,
  because a slot with no matching variant price resolves to `nil` legitimately.

Add an in-flight coalescing map so two slots of the same card requested
concurrently share one `Task`, rather than both missing the cache.

### C2 — publish prices incrementally

Resolves F8 cause 3. Change `BrowseCatalogProviding`
([`BrowseCatalogModels.swift:1150`](../../TradingCardScanner/Models/BrowseCatalogModels.swift:1150))
from

```swift
func sortPrices(for cards: [CatalogCardSummary]) async -> [String: Double]
```

to a streaming form:

```swift
func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]>
```

Each element is a cumulative price map. Emit on a fixed cadence — every 25
resolved cards or every 250 ms, whichever comes first — so a large set produces
tens of updates, not hundreds. The stream finishes when the task group drains.
Cancelling the stream cancels the group.

Update the stub in
[`CatalogCardDetailView.swift:479`](../../TradingCardScanner/Views/CatalogCardDetailView.swift:479)
and every test double in the same change.

In `CatalogSetCardsView.loadPrices`
([`BrowseView.swift:1894`](../../TradingCardScanner/Views/BrowseView.swift:1894)),
consume the stream and merge into `prices` on each element. Keep every existing
guard — `contentGeneration`, `priceRequestID`, and the `whileLoadingCards`
pagination gate — and re-check `contentGeneration == contentRequestID` inside
the loop, not only before it, so a set change mid-stream drops the remainder.

### C3 — sort with what is known

In `visibleCards` ([`BrowseView.swift:1694`](../../TradingCardScanner/Views/BrowseView.swift:1694)),
delete the `sort.needsPrices && !hasLoadedPrices` substitution and always pass
`sort`. `CatalogSetQuery.apply` must order an unpriced card **after** every
priced card for both price directions, with `.numberLowToHigh` as the tiebreak
among unpriced cards, so the list is stable while it fills rather than
reshuffling from the bottom.

Keep `hasLoadedPrices` — it is still the honest input to the
"Loading prices for this set…" banner
([`BrowseView.swift:1746`](../../TradingCardScanner/Views/BrowseView.swift:1746)).
Change the banner copy to name what is happening, for example
`"Sorting by price — <n> of <total> priced"`, so a partial order is not mistaken
for a final one.

### C4 — persist the sort price cache

Resolves the relaunch cost. Add to `CatalogCacheStore`
([`BrowseCatalog.swift:802`](../../TradingCardScanner/Services/BrowseCatalog.swift:802)):

```swift
private static let sortPriceMaxAge: TimeInterval = 24 * 60 * 60
func sortPrices(for setID: String) -> Cached<[String: Double]>?
func storeSortPrices(_ prices: [String: Double], for setID: String)
```

Stored under a `SortPrices/` subdirectory keyed by `filename(for:)` on
`"sortprices|\(setID)"`, with the existing `trim(_:maximumBytes:)` applied at a
5 MB budget. Load into `sortPriceCache` when a set's price request starts; write
back when its stream finishes.

**This cache is for ordering only.** It must not feed `PriceRecord`,
`PriceObservation`, `PriceCheckDay`, the portfolio replay, or any displayed
"checked at" time. A stale ordering price is acceptable; a stale valuation is
not. Say so in the source comment.

### C5 — prefetch on set open

In `CatalogSetCardsView.load(reset:)`
([`BrowseView.swift:1867`](../../TradingCardScanner/Views/BrowseView.swift:1867)),
after the page is applied, start the price stream at `.utility` priority even
when `sort.needsPrices` is false. It shares `priceRequestID`, so a later sort
change joins the request in flight instead of starting a second one.

Gate it: skip the prefetch when the set has more than 400 slots after C1's
dedupe, and skip it when `ProcessInfo.processInfo.isLowPowerModeEnabled`. A
user who never sorts by price should not cost the provider 400 requests.

### C6 — deterministic verification

- [ ] Two summaries sharing a `providerID` but differing in `masterSetVariant`
      cause exactly **one** `fetchCard` call — assert against a counting
      transport double.
- [ ] Both of those summaries still receive their own variant-specific price.
- [ ] `sortPrices` emits at least two elements for a 60-card fixture with a
      slow transport, and the final element equals the whole-set map the current
      implementation returns.
- [ ] `CatalogSetQuery.apply` with `.priceHighToLow` and a partial price map
      orders priced before unpriced, descending among priced, by number among
      unpriced — for `.priceLowToHigh` too.
- [ ] A content change mid-stream discards the remaining elements and leaves
      `isLoadingPrices == false` and `hasLoadedPrices == false`.
- [ ] Cancelling the consuming task cancels the underlying task group.
- [ ] `storeSortPrices` / `sortPrices(for:)` round-trip, and a map older than
      `sortPriceMaxAge` reports `isFresh == false`.
- [ ] The existing sort/pagination/price-request-identity tests in
      `BrowseCollectionTests` ([`BrowseFeatureTests.swift:1256`](../../TradingCardScannerTests/BrowseFeatureTests.swift:1256))
      stay green after the protocol change.

### C7 — measurement (not retired by the simulator)

- [ ] Time to first reorder after choosing "Price: High to Low" on `me02.5` ASC
      (629 slots, 484 standard), recorded before and after.
- [ ] Total `fetchCard` count for that sort, before and after C1.
- [ ] Confirm the prefetch gate keeps a cold `me02.5` open from issuing requests
      when the user never sorts.

---

## Out of scope

- **Removing the missing-art state.** After Slice A only five sets reach it
  (`ex5.5`, `exu`, `mee`, `mfb`, `xya`). The state and its precedence rules stay
  exactly as specified in [`browse_screen_spec.md`](browse_screen_spec.md) § 6.
- **Magic set artwork.** Scryfall symbols are SVG and the typographic set-code
  fallback stands ([`CatalogSetTile.swift:172`](../../TradingCardScanner/Views/CatalogSetTile.swift:172)).
- **A bulk price provider.** JustTCG batch pricing exists
  ([`JustTCGV1Client.swift:36`](../../TradingCardScanner/Services/JustTCGV1Client.swift:36))
  but is quota-bound by `JustTCGQuota` and owned by collection refresh. Browse
  sorting must not spend that allowance. Recorded as a rejected option; reopen
  only with a new dated plan that states the allowance budget.
- **Bundling card artwork.** The licensing caveat in
  [`artwork-fallback-plan.md`](artwork-fallback-plan.md) is unchanged and must be
  resolved before monetization regardless of this plan.
- **Changing master-set rules.** `PokemonMasterSetDefinition.requiredVariants`,
  `excludes`, `virtualSets`, and `printRuns` are untouched. This plan changes
  which number is *displayed*, never which slots exist.

---

## Reconciliation

Carry these into the named documents as each slice lands. Until then this
section is the record required by [`../AGENTS.md`](../AGENTS.md) rule 5.

| Document | Statement | Change |
| --- | --- | --- |
| [`browse_screen_spec.md`](browse_screen_spec.md) § 8, *Progress and grammar* | "`CatalogSetTile.completionFooter` shows `3 of 207`" — a collector-number numerator over `set.cardCount`. | Slice B3 keeps the `n of m` shape and the `n owned` / hidden-when-zero rules, and changes the source of both numbers to the built checklist. The Pokémon unit becomes `variations`, matching the set screen. Update § 8 when B lands. |
| [`browse_screen_spec.md`](browse_screen_spec.md) § 6 | Missing-art precedence and the phase-callback rule. | Unchanged. Slice A2 must preserve both; A7 asserts them. |
| [`artwork-fallback-plan.md`](artwork-fallback-plan.md) § P2 | Allow-list "excludes AQ/SK/EXU/BOG/XYA/EX5.5 where Limitless has no coverage." | Still correct, re-probed 2026-09-15. `MEE` was an omission, not an exclusion; add it and record the probe. |
| [`artwork-fallback-plan.md`](artwork-fallback-plan.md) § P3 / *Vendored asset refresh* | "The 18 matched `logo.png`/`symbol.png` assets are bundled." | Slice A3 removes three; the count becomes 33 image sets. The chain description becomes the A2 candidate order. |
| [`release_followups.md`](release_followups.md) | — | Add Slice C7 as a measurement item; it cannot be closed from a simulator run. |

---

## Verification order

1. Slice A in full, including the A8 capture. It is independently shippable.
2. Slice C1 alone, with its two C6 fetch-count assertions. Independently
   shippable and reduces provider load immediately.
3. Slice B1 + B2 + B3 as one change, then regenerate the snapshot, then B5's
   denominator-parity test. B4 may ride along or follow.
4. Slice C2–C5 with C6, then the C7 measurements.

Run the narrowest relevant selectors first per [`../../AGENTS.md`](../../AGENTS.md):

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TradingCardScannerTests/BrowseFeatureTests -only-testing:TradingCardScannerTests/BrowseCollectionTests -only-testing:TradingCardScannerTests/PokemonChecklistBrowseTests test
```

Snapshot regeneration is a separate, network-dependent step:

```bash
./scripts/generate_pokemon_snapshot.sh
```

## Re-run rule

Update the smallest relevant box above as each slice lands, then add one dated
line to [`../../progress.md`](../../progress.md). Slice C7 is a measurement gate
and must be closed in [`release_followups.md`](release_followups.md), not by
weakening a claim here. Do not mark A8 or B6 complete from source inspection; a
capture is required. When this plan is complete or superseded, move it to
[`../legacy/`](../legacy/) with a banner per [`../AGENTS.md`](../AGENTS.md)
rule 3, update the [documentation map](../README.md), and record the disposition
in [`documentation_audit.md`](documentation_audit.md).
