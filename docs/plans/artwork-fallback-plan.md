# Artwork fallback plan

**Status:** P0–P3, the 2026-09-15 Slice A remediation, the file-level A6
bundled-logo audit, the targeted TCGdex provider re-probe, and the automatic
set-art release path are implemented in the current working tree. Core and
offline publisher verification pass; broader provider/device validation and
image-licensing decisions remain open — reconciled 2026-09-21.

Open defects found in this contract on 2026-09-15 — the set tile requesting the
symbol rather than the logo, a bundled asset that is unreachable behind a remote
alternate-kind URL, three wrong vendored assets, and `MEE` missing from the
Limitless allow-list — are owned by Slice A of
[`browse_set_directory_remediation_plan.md`](browse_set_directory_remediation_plan.md).
The P2/P3 descriptions and vendored-asset inventory below reflect that slice.

The current code path is `PokemonArtworkFallbacks` for set artwork,
`CatalogCardArtworkSource` for card artwork, `LimitlessArtwork` for derived
Pokémon URLs, and `CatalogCachedImage` for ordered fallback traversal. Focused
Browse coverage and the Debug Browse build/capture are recorded in
[`../../progress.md`](../../progress.md). The remaining work is operational:
keep the vendored source commit current, measure provider/device behavior beyond
the targeted fallback probe, and resolve the licensing caveat below before
monetization or broad distribution.

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
- TCGdex set-art stems are not universally backed by `.png` derivatives. A
  2026-09-15 probe found three stored logo derivatives returning 404 —
  `sv01`/SVI, `ecard1`/EX, and `xy10`/FCO. Their bare stems returned HTTP 200
  guidance responses, while the explicit `.webp` derivatives returned image
  data. A 10-set symbol-prefix spot check found nine sampled `/univ/.../symbol.png`
  paths returning 404 while their `/en/` siblings returned PNG image data;
  `me05` was the inverse. Symbol fallback therefore preserves the stored path
  first, then adds its sibling prefix (`/univ/` ↔ `/en/`), with `.png`, bare
  stem, and `.webp` candidates for each TCGdex path.
- Limitless CDN: `…/tpci/<CODE>/<CODE>_<NUM>_R_EN.png` (+ `_XS` small tier).
  `_R_` is **constant**, not rarity. Numbering has two rules:
  - pure numeric → zero-pad to 3 (`SLG_1` 403, `SLG_001` 200)
  - alpha-prefixed → strip padding (`BRS_TG01` 403, `BRS_TG1` 200)
  Covers ~651 / 844 rows (77%). Absent keys return 403 (fails closed).
- `1niceroli/ptcg-assets`: flat `<pokemontcg.io-id>/logo.png|symbol.png`.
  Resolves **18 / 26** logo+symbol gaps, incl. every gallery subset and modern set.
  TCGdex→ptcg id rule: lowercase, strip leading zeros, `.` → `pt` (`sv08.5`→`sv8pt5`),
  except `swsh4.5sv`→`swsh45sv`, `sm3.5`→`sm35`.
- `CatalogCachedImage` (Views/BrowseView.swift) recurses through its typed
  candidate array and stops only after the ordered chain is exhausted, skipping
  missing bundled names without treating them as a provider failure.

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
traversal and retry behavior. For each TCGdex remote set-art URL ending in
`.png`, `PokemonArtworkFallbacks.setSource` preserves that URL first, adds its
extensionless stem immediately after it, and adds the explicit TCGdex `.webp`
derivative after the stem. For symbol candidates under `/univ/` or `/en/`, it
then adds the sibling-prefix URL variants without replacing the stored path.
The stem, WebP, and sibling-prefix transformations are all gated to
`assets.tcgdex.net`; other hosts' `.png` URLs remain untouched.

`CatalogImageCache` now downsamples/decodes each response before saving it to
the disk LRU. Disk hits are decoded too; an undecodable legacy entry is evicted
and the URL gets one network retry. Concurrent waiters remain coalesced through
that decode-and-persist step. Thus the current bare-stem HTML guidance response
is rejected but never persisted, and older builds' cached guidance responses do
not permanently suppress the later `.webp` candidate. Focused tests cover the
invalid-body, legacy-eviction, decoded-disk-hit, and coalesced-fetch cases.

### P2 — Derived Limitless card fallback — implemented

The current tree contains the pure `LimitlessArtwork` type:

    static func urls(setCode: String, collectorNumber: String) -> (small: URL, full: URL)?

Normalization:
- uppercase set code; reject codes not in an allow-list of TPCi-era sets
  (MEE is included; AQ/SK/EXU/BOG/XYA/EX5.5/MFB/RR remain explicit uncovered
  decisions where Limitless has no approved coverage)
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

> Superseded in part. Slice A2/A3 of
> [`browse_set_directory_remediation_plan.md`](browse_set_directory_remediation_plan.md)
> reorders the chain so a bundled asset of the *requested* kind outranks a remote
> URL of the alternate kind, and removes `sve_logo`, `bog_logo`, and
> `cel25cc_symbol` as wrong artwork. The bundled count becomes 33 image sets.

The remaining 33 PNGs are bundled at tile size and resolved by TCGdex provider
ID. For a Pokémon set logo, the typed chain is requested remote logo (stored
`.png`, then extensionless stem, then TCGdex `.webp`), requested bundled logo,
remote symbol with the same remote variants plus its `/univ/`/`/en/` sibling
prefix, inherited parent logo with the same remote order, and bundled symbol;
the Classic Collection explicitly puts its inherited Celebrations logo before
its bundled logo. Missing bundled names are skipped. The source commit SHA is
recorded below. The root game fan prioritizes the newest sets with bundled logo
artwork before filling remaining slots by release order, so the local logo
fallback remains reachable when the newest catalog rows have no bundled art.

### A6 file-level audit — 2026-09-15

The eight remaining promoted logo assets were checked against the known generic
`base1_logo` payload using SHA-256 and PNG dimensions. None is byte-identical to
that generic payload, and each has a distinct source dimension; no asset was
removed or substituted. The cheap MD5 pass agrees: the base payload is
`bea522d0f5a36c6c3833825b666ab583`, all eight promoted files have distinct MD5s,
and their sizes are plausible at 58–98 KB; the generic placeholder signature is
absent. The settled Browse capture then confirmed their semantic identities in
the rendered tiles: Stellar Crown, Surging Sparks, Prismatic Evolutions, the
four Trainer Gallery logos, and Shining Fates. The remaining provider behavior
gate is still separate from this asset audit.

| TCGdex id | Bytes | MD5 | PNG dimensions | SHA-256 prefix |
| --- | ---: | --- | ---: | --- |
| `sv07` | 61,892 | `5d2dc21c2e6f04539e804cf10de54bb0` | 320 × 128 | `f8f0001f3b94b99c…` |
| `sv08` | 91,028 | `6ffd8dd00ac7c55ed4f57cd5ef79459a` | 320 × 141 | `8b963d35f678109f…` |
| `sv08.5` | 81,802 | `6ea2565a08ef881498a7f2829c817f91` | 320 × 148 | `7f026f7b92834757…` |
| `swsh9tg` | 80,263 | `ff8e7817e252566299b63505cbc0f9d2` | 320 × 132 | `322cb1641c69c5d5…` |
| `swsh10tg` | 57,572 | `29cfcc43d84e7485fba85c4c20b4659f` | 320 × 118 | `04959890ced94ae1…` |
| `swsh11tg` | 68,165 | `00a25d3fcbb53d06c7cbc4660e78e36f` | 320 × 123 | `efdc2a5cd24c1168…` |
| `swsh12tg` | 83,342 | `def5a5fc5b8c7d1acd320b7e6bac83e5` | 320 × 150 | `92e647b4d20fc66f…` |
| `swsh4.5sv` | 97,840 | `c0ba8e31980c9997b5e3bd99d77cdb28` | 320 × 158 | `c566368d6653d15a…` |

### Automatic set-art release — implemented 2026-09-21

TCGdex remains the hard provider dependency and the first artwork source. The
publisher now admits zero-official-count subsets as browse-only descriptors,
derives safe same-series parent artwork without persisting a parent authority,
and publishes validated card-art fallback URLs in the signed descriptor. A
failed optional secondary provider therefore cannot abort the daily catalog.

The optional set-level secondary source is `api.pokemontcg.io/v2`, with image
URLs probed at `images.scrydex.com`. Matching scans the complete secondary
directory after normalizing names, codes, dates, and counts. It accepts only a
unique candidate with at least three signals, including an independent total or
exact-name signal; parent/subset name prefixes are corroborated by matching
totals. Ambiguous or unprobed artwork is discarded and reported. This is the
deliberate replacement for the former “pokemontcg.io is only Scrydex” decision:
the source is now used for bounded set-art/card-art recovery where TCGdex has
no usable coverage, not as a general card-art directory.

### Out of scope
- Magic: Scryfall already covers artwork and set icons; no change.
- Runtime queries to Limitless to *discover* cards. URLs are derived, never searched.

## Licensing caveat
"Free to access" is not "freely licensed." Pokémon card imagery remains
copyright Pokémon/Nintendo/Game Freak/Creatures; Limitless states this, and
ptcg-assets carries no clear commercial image licence. The automatic path now
also exposes imagery from `api.pokemontcg.io` and `images.scrydex.com`, widening
the third-party host/licensing surface. Revisit the image-source arrangement
before monetization. Keep provider identity in the model so the chain can be
re-pointed without touching call sites.

## Vendored asset refresh

- `1niceroli/ptcg-assets` source commit: `fdd292d5ddf483eadb3d5229d95e2d4dc13231b3`
- TCGdex-to-source mappings: `base1→base1`, `bog→bp`, `cel25cc→cel25c`,
  `me02→me2`, `sm3.5→sm35`, `sm7.5→sm75`, `sma→sma`, `sv05→sv5`,
  `sv07→sv7`, `sv08→sv8`, `sv08.5→sv8pt5`, `sve→sve`,
  `swsh9tg→swsh9tg`, `swsh10tg→swsh10tg`, `swsh11tg→swsh11tg`,
  `swsh12.5gg→swsh12pt5gg`, `swsh12tg→swsh12tg`, `swsh4.5sv→swsh45sv`.
- The remaining 33 PNGs are downscaled to a 320-pixel maximum dimension; the
  combined bundled payload is approximately 2.0 MB. Set artwork uses the
  requested bundled kind first and the alternate kind as a local fallback,
  with the inherited Classic Collection logo ahead of its local fallback.
  Provider `.png` candidates are retained first and followed by their
  extensionless TCGdex stems and the explicit TCGdex `.webp` derivative,
  including inherited parent-logo candidates. Symbol candidates retain their
  stored `/univ/` or `/en/` prefix first and then try the sibling prefix.
  `CatalogImageCache` validates decoding before persisting response bytes and
  evicts undecodable disk entries left by older versions.
