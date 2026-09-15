# Artwork fallback plan

**Status:** P0–P3 are implemented in the current working tree; runtime/provider
validation and image-licensing decisions remain open — reconciled 2026-09-14.

The current code path is `PokemonArtworkFallbacks` for set artwork,
`CatalogCardArtworkSource` for card artwork, `LimitlessArtwork` for derived
Pokémon URLs, and `CatalogCachedImage` for ordered fallback traversal. Focused
Browse coverage and the Debug Browse build/capture are recorded in
[`../../progress.md`](../../progress.md). The remaining work is operational:
recheck live-provider behavior, keep the vendored source commit current, and
resolve the licensing caveat below before monetization or broad distribution.

## Verified findings (probed 2026-09-14)

- TCGdex **has** Pitch Black (`me05`) card art. `me05/119/high.png` → 200/256 KB;
  `me05/999/high.png` → 404, so 200s are real, not blanket responses.
- Bundled snapshot: **844 / 31,872 card rows (2.6%) have no `imageURL`.**
  Concentrated in subsets/galleries/energy sets (SVE 128, SHF 122, SLG 78, DRM 78,
  CRZ 70, TG galleries 32 each, CEL 25, MEE 16) and e-card-era sets
  (AQ 49, MFB 48, SK 32, EXU 28, BOG 20).
- **21 / 160 sets lack `logoURL`, 24 lack `symbolURL`.** Includes modern sets
  (TEF, SCR, SSP, PRE) where TCGdex genuinely 404s on `symbol.png`.
- Gallery parent `symbol.png` endpoints also 404 for all six inherited parents;
  parent fallback therefore supplies the logo only.
- Limitless CDN: `…/tpci/<CODE>/<CODE>_<NUM>_R_EN.png` (+ `_XS` small tier).
  `_R_` is **constant**, not rarity. Numbering has two rules:
  - pure numeric → zero-pad to 3 (`SLG_1` 403, `SLG_001` 200)
  - alpha-prefixed → strip padding (`BRS_TG01` 403, `BRS_TG1` 200)
  Covers ~651 / 844 rows (77%). Absent keys return 403 (fails closed).
- `1niceroli/ptcg-assets`: flat `<pokemontcg.io-id>/logo.png|symbol.png`.
  Resolves **18 / 26** logo+symbol gaps, incl. every gallery subset and modern set.
  TCGdex→ptcg id rule: lowercase, strip leading zeros, `.` → `pt` (`sv08.5`→`sv8pt5`),
  except `swsh4.5sv`→`swsh45sv`, `sm3.5`→`sm35`.
- `CatalogCachedImage` (Views/BrowseView.swift) recurses through its `fallbacks`
  array and stops only after the ordered chain is exhausted.

## Phases

### P0 — Parent-set logo inheritance — implemented
Virtual/gallery sets (`swsh9tg`, `swsh10tg`, `swsh11tg`, `swsh12tg`,
`swsh12.5gg`, `swsh4.5sv`) have no TCGdex logo, but their parent does
(`swsh10/logo.png` → 200). The corresponding parent `symbol.png` endpoints
404, so `PokemonMasterSetChecklistBuilder.enrichedSet` inherits the parent
logo only. Removes ~6 set-tile placeholders for 0 bytes.

### P1 — N-link fallback chain — implemented

`CatalogCachedImage` uses `fallbacks: [URL]` and passes the remaining chain on
recursion. The current Browse source and focused tests cover ordered fallback
traversal and retry behavior.

### P2 — Derived Limitless card fallback — implemented

The current tree contains the pure `LimitlessArtwork` type:

    static func urls(setCode: String, collectorNumber: String) -> (small: URL, full: URL)?

Normalization:
- uppercase set code; reject codes not in an allow-list of TPCi-era sets
  (excludes AQ/SK/EXU/BOG/XYA/EX5.5 where Limitless has no coverage)
- split trailing digits from any alpha prefix
- no prefix → zero-pad digits to 3; prefix present → strip leading zeros
- reject anything with a letter suffix on the number (`040a`, `103b`) — these
  do not exist on Limitless and would risk serving the wrong card
Wire as the **last** link: TCGdex low → Limitless XS, TCGdex high → Limitless full.
Derived in a pure function so the live TCGdex path and the bundled snapshot both
get it with no build-time baking.

Tests: table-driven normalization cases (SLG 1→001, BRS TG01→TG1, CRZ GG01→GG1,
SHF SV001→SV1, CEL CC001→CC1, AQ 050a→nil, PBL 119→119).

### P3 — Bundled set logo/symbol assets — implemented

The 18 matched `logo.png`/`symbol.png` assets are bundled at tile size and
resolved by TCGdex provider ID. The current chain is TCGdex → parent set →
bundled asset → placeholder. The source commit SHA is recorded below.

### Out of scope
- Magic: Scryfall already covers artwork and set icons; no change.
- pokemontcg.io: its Pitch Black URLs now redirect to `images.scrydex.com`, so it
  is not an independent fallback — it is Scrydex by another name.
- Runtime queries to Limitless to *discover* cards. URLs are derived, never searched.

## Licensing caveat
"Free to access" is not "freely licensed." Pokémon card imagery remains
copyright Pokémon/Nintendo/Game Freak/Creatures; Limitless states this, and
ptcg-assets carries no clear commercial image licence. Revisit the image-source
arrangement before monetization. Keep provider identity in the model so the
chain can be re-pointed without touching call sites.

## Vendored asset refresh

- `1niceroli/ptcg-assets` source commit: `fdd292d5ddf483eadb3d5229d95e2d4dc13231b3`
- TCGdex-to-source mappings: `base1→base1`, `bog→bp`, `cel25cc→cel25c`,
  `me02→me2`, `sm3.5→sm35`, `sm7.5→sm75`, `sma→sma`, `sv05→sv5`,
  `sv07→sv7`, `sv08→sv8`, `sv08.5→sv8pt5`, `sve→sve`,
  `swsh9tg→swsh9tg`, `swsh10tg→swsh10tg`, `swsh11tg→swsh11tg`,
  `swsh12.5gg→swsh12pt5gg`, `swsh12tg→swsh12tg`, `swsh4.5sv→swsh45sv`.
- The 36 PNGs are downscaled to a 160-pixel maximum dimension; the combined
  bundled payload is 747,191 bytes.
