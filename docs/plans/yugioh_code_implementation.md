# Yu-Gi-Oh! implementation plan

**Status — 2026-10-20:** plan only. Nothing is implemented, built or tested yet.
Written against `main` at `06459ea`. The research handoff it validates was
written against `c8f89ce`, which is 23 commits older (41 app files changed since
then, including `CardScanner.swift` and `CollectionStore.swift`). Every line
reference here is to `06459ea`; re-locate by symbol if lines drift.

**Execution mode:** finish line first. Implement every work package in order,
**with no `xcodebuild` runs, no simulator use and no test runs in between**.
Write tests as you go, but do not run them. All compiling, testing and audits
happen once, in [§9 Deferred verification](#9-deferred-verification-run-once-after-wp1wp6),
after the code is complete. Device, camera, provider-rights and release gates
stay open for the owner ([§10](#10-owner-gates-not-closable-by-the-implementing-agent)).

This document is the implementation authority. It supersedes the external
"CardScanner — Yu-Gi-Oh! Research & Implementation Plan" handoff (20 Oct 2026).
That handoff was not committed; §1 records which of its claims hold and which
do not.

---

## 1. Validation of the research handoff

Every claim was checked against the current source, live public provider data
(TCGCSV and YGOPRODeck on 2026-10-20), or on-device Vision OCR of real card scans
run on this Mac. Verdicts:

### 1.1 Confirmed

| Claim | Evidence |
|---|---|
| TCGplayer/TCGCSV Yu-Gi-Oh! is `categoryId = 2` | `tcgcsv.com/tcgplayer/categories`: `(2, "YuGiOh")`. There are 659 groups. |
| `RA02-EN037` is one code with 7 rarities | TCGCSV group 23416 has 7 products numbered `RA02-EN037` (productIds 551101–551107). |
| `GENF-EN098` *A Hero Lives* is Ultra + Ultimate Rare, each in 1st Ed + Unlimited | Group 209: product 48117 (UR) and 58403 (UTR), each with `1st Edition` and `Unlimited` price rows. |
| `L26D-ENM26` has an alphanumeric suffix | Group 24549 *Legendary Modern Decks 2026*: product 683145 *Number 60: Dugares the Timeless*, Common, 1st Edition. |
| `LOB-001` and `LOB-EN001` are distinct printings | `LOB-001` is in group 330 (2002). `LOB-EN001` is in group 23050 *LOB 25th Anniversary Edition*. YGOPRODeck also lists `LOB-E001`. |
| The passcode is not a printing identity | YGOPRODeck *Blue-Eyes White Dragon* lists many printings under one card. |
| YGOPRODeck v7 no longer returns `tcgplayer_data` | The live `cardinfo.php` keys are `atk, attribute, banlist_info, card_images, card_prices, card_sets, def, desc, frameType, humanReadableCardType, id, level, misc_info, name, race, type, typeline, ygoprodeck_url`. |
| TCGCSV joins prices by `productId + subTypeName`, and `marketPrice` can be null | `LOB-001` 1st Edition `marketPrice` is `null`; Unlimited is 125.98. |
| Footer ROI is `x=.025,y=.015,w=.95,h=.15`, card ratio is hard-coded 2.5:3.5, Vision uses a bottom-left origin, and full-card OCR runs only on a `.nothing` outcome | `TradingCardScanner/Services/CardScanner.swift:14-37`, `:3802-3816`. |
| Recognizers compete; more than one identity is rejected | `GameRecognitionRegistry.aggregate`, `Games/Core/GameRecognitionAdapter.swift:80-98`. |
| Confirmation needs 2 matches in 4 observations | `CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)`, `Services/ScanParser.swift`. |
| A YGO card is about 59×86 mm (ratio ≈ 0.686) | The 5 TCGplayer scans measured in §1.2 have aspect 0.675–0.690. |

### 1.2 Corrected (the handoff is wrong or misleading)

| Handoff claim | Correction | Consequence |
|---|---|---|
| **Under-art ROI starts at `x=.03, y=.28, w=.94, h=.17`** | On real scans (Vision, bottom-left, card-relative) the set code's box starts at **y ≈ 0.244–0.262** with height ≈ 0.022: `LOB-001` y=.244, `RA02-EN037` y=.262, `L26D-ENM26` y=.259. A band from y=.28 to .45 covers lower artwork and misses most of the code line. | Use **`x=.03, y=.20, w=.94, h=.11`** (y 0.20–0.31). That covers the code with ±0.04 tolerance for the 2.5:3.5 guide versus the 0.686 card (§4.3). |
| RA02-EN037 rarities are "Super, Ultra, Secret, Ultimate, Platinum Secret, Collector's, Quarter Century Secret" | TCGplayer lists **Prismatic Ultimate Rare** and **Prismatic Collector's Rare**. YGOPRODeck calls the same two "Ultimate Rare"/"Collector's Rare". | Rarity labels come from TCGplayer `extendedData.Rarity` verbatim. The rarity names from the two sources are never joined; only rarity *counts* are compared (§3.4). |
| RA02 example shows `"edition": "unresolved"` | All seven RA02-EN037 products have **only** a `1st Edition` lane. | Edition is unambiguous for most modern sets. Only real multi-edition printings prompt. |
| "Card guide and OCR crops must be recalibrated for 0.686, not 0.714" | The fixed guide (`cardVisionRect`) differs by about 4% of height. A taller band absorbs that offset (§4.3). | Do **not** add a YGO framing profile or touch the guide. Re-check on device only. |
| Edition marker: "printed `1st Edition`… positive OCR evidence" | Vision reads the superscript badly: `"T Edition"`, `"1\" Edition"`, `"1t Edition"`, `"s Edition"`. | Edition parsing keys on the word `EDITION` plus position, not on the literal `1st` (§4.5). |
| "Introduce `YuGiOhCatalogCore` Swift package, signed snapshots, publisher" | Not needed to ship. Lorcana is in production from a **bundled, unsigned** catalog (`LorcanaDiscoveryCatalog.bundledMarket`, `requiresLaunchActivation: false`). | Use the bundled-seed path. Signing and remote updates are deferred (§2). |
| Collection ID shape `${game}:${familyUUID}#${variantID}` with structured multi-axis variants | The existing model already separates the axes: **one physical-printing UUID per TCGplayer product** (code + rarity + art + release), and **edition as the `PhysicalVariant`**. That matches TCGplayer exactly (product = rarity/art, subtype = edition) and reuses the printing-choice and variant-choice UI, edition correction, Finish Lock, `PriceRecord.key` and the collection-key codec unchanged. | No new identity schema and no `VariantResolver` redesign. |
| Stable IDs require an assignment ledger | TCGplayer `productId`s are stable, and `DeterministicUUID.make` exists (`Services/DeterministicUUID.swift`). | Printing UUID = `DeterministicUUID.make(namespace: "yugioh-printing:", material: "tcgplayer:2:<productId>")`. No ledger file. |
| JustTCG is a pricing input for v1 | `JustTCGV1Client.gameSlug(for:)` has no YGO slug. The free tier is noncommercial. | Leave JustTCG out of v1. TCGCSV only. |

### 1.3 Missing from the handoff (now covered by this plan)

1. **The shared TCGCSV transport would reject every YGO price.**
   `TCGCSVProductPriceSource.quote` (`Services/TCGCSVProductPriceSource.swift:48`)
   accepts only lanes `["Normal","Foil","Cold Foil","Holofoil"]`. The YGO
   subtypes are `1st Edition`, `Unlimited` and `Limited`; live counts across 7
   sampled groups were 1782, 490 and 21 rows, plus 16 `Normal`. WP2.4 adds them.
2. **One printed code can cover several artworks and several releases.**
   `LDK2-ENK01` has 3 products in group 1841 (2016) and 3 in group 23469 (2024
   reprint), named "(Version 1/2/4)". The reprint has Unlimited only. These are
   printing choices with distinct labels: set name + art label (§3.3, §5.1).
3. **TCGplayer names carry suffixes that are not part of the card name.** The
   rarity suffixes are `(UR)`, `(PUR)`, `(PCR)`, `(UTR)`, `(Secret Rare)` and
   others. The art/distribution suffixes are `(Extended Art)`,
   `(Alternate Art)`, `(Version N)`, `(Stamp)`, `(Retail Exclusive)`,
   `(2024 Reprint)`, `(J)`/`(K)`. The builder strips rarity suffixes and keeps the
   others as the art label (§3.3).
4. **The rarity universe can be incomplete.** If YGOPRODeck lists more rarities
   for a code than TCGplayer has products for, auto-adding the only TCGplayer
   product could assign the wrong rarity. Such codes are marked incomplete and
   never auto-resolve (§3.4).
5. **Footer vocabulary pollution.** `customWords` is global to the shared footer
   request. YGO must contribute `[]` there and read its own band with language
   correction off (§4.2).
6. **Several write-time branches are hard-coded to `.lorcana`.** They are
   `ScannerViewModel.swift:3491, 3544, 5389, 5483` and `CollectionStore.swift:874`.
   Without YGO in them, YGO skips the revalidation step before a write (WP2.8).
7. **`appDefaults()` returns early inside `LOCAL_ONLY_SIGNING` branches.** The YGO
   module must be appended **before** the One Piece block, next to Lorcana, or
   local builds silently omit it (WP3.7).
8. **The boundary audit** (`scripts/audit_game_boundaries.sh`) must learn
   `yuGiOh`, and central files must stay free of `.yuGiOh` branches. The scanner
   seam is therefore adapter-driven (WP2.5–2.6).
9. **Image rights.** YGOPRODeck forbids hotlinking images, and its renders omit
   the set code and passcode. The plan uses the TCGplayer CDN `imageUrl` that
   TCGCSV publishes. This is an owner rights gate, not a code blocker (§10).

### 1.4 Not verified (left to the owner/device phase)

- Pendulum set code inside the existing footer band. TCGplayer documents it at
  bottom-left; no Pendulum scan was available.
- Link Monster code position, which no sampled OCR run read.
- RA05 extended-art code position.
- Commercial terms for TCGCSV, YGOPRODeck and Konami.
- The existence of `L26D` in Konami's own database (TCGplayer confirms it).

---

## 2. Scope decisions (ship-fast)

**In v1:** English TCG raw singles from every TCGCSV category-2 group whose
products carry a parseable English code (region `EN`, early-European `E`, or
regionless 2002-era `LOB-001`). This includes Speed Duel, OTS and promo groups,
which share the standard layout. Capabilities: `[.scan, .browse, .pricing, .collectionWrite]`.

**Deferred** (record them in the plan's ledger when work begins; do not build
them now):

- Signed or remote catalog updates (`YuGiOhCatalogCore`, publisher, keys).
  Catalog refresh means re-running the builder and shipping an app update, as
  Lorcana does.
- JustTCG pricing, graded/slab YGO, sealed YGO, non-English, OCG/Rush Duel.
- Passcode-based **artwork** disambiguation. In v1 the passcode only *rejects*
  conflicting reads.
- A rarity lock. The edition lock comes free through `GameVariantPolicy`.
- Foil or rarity image classification. Never auto-select rarity in v1.
- Price-history chart market mapping (`CardMarketHistoryService.resolvingMarketMapping`).
- Series 1 cards with no printed code. They stay unrecognized, which is safe.

---

## 3. Catalog builder and bundled seed (WP1)

### 3.1 Files

- New `scripts/build_yugioh_catalog.py` (Python 3, stdlib only).
- New `TradingCardScanner/YuGiOhCatalogSeed/catalog.json`, generated and
  committed. Lorcana's seed is about 9 MB, so a similar size is acceptable.
- New `docs/research/yugioh-catalog/build-report.md`, generated: counts plus up
  to 50 examples per exception class. Do **not** put the report inside the seed
  folder; the whole folder is bundled.

### 3.2 Fetch (run once; raw cache on the external SSD)

```
python3 -I scripts/build_yugioh_catalog.py \
  --cache-dir "/Volumes/Keller Family Photos/YuGiOhSourceCache/2026-10-20" \
  --out TradingCardScanner/YuGiOhCatalogSeed/catalog.json \
  --report docs/research/yugioh-catalog/build-report.md
```

(Match the volume by prefix; it sometimes mounts as `… Photos 1`. Fall back to
the session scratchpad only if no SSD is mounted.)

1. `GET https://tcgcsv.com/tcgplayer/categories`: assert one row
   `categoryId == 2`, `name == "YuGiOh"`.
2. `GET https://tcgcsv.com/tcgplayer/2/groups`.
3. For each group: `GET …/2/{groupId}/products` and `GET …/2/{groupId}/prices`.
   Wait 0.25 s between requests, retry 3× with backoff, and cache raw bytes as
   `tcgcsv/{groupId}-products.json` / `-prices.json`. Reuse the cache when
   `--offline` is passed. Abort if any response has `success == false` or
   non-empty `errors`.
4. `GET https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes` **once** (all
   cards, a single request, well inside the 20 req/s limit). Cache it as
   `ygoprodeck/cardinfo.json`.

### 3.3 Normalize (deterministic; sort every output list)

For each TCGCSV product:

- `number` = `extendedData["Number"]`, uppercased and stripped. Skip the product
  if it is missing; that is sealed product (exception `noNumber`).
- Code grammar: `^[A-Z0-9]{2,4}-(?:EN|E)?[A-Z0-9]{3}$`, and **regionless codes
  must end in 3 digits**. Anything else → exception `nonEnglishOrUnparsed`.
- `rarity` = `extendedData["Rarity"]` verbatim; required (exception `noRarity`).
- Editions: map the product's price rows by `subTypeName`:
  `{"1st Edition": "yugioh1stEdition", "Unlimited": "yugiohUnlimited", "Limited": "yugiohLimited"}`.
  Any other subtype on the product, or zero recognized subtypes → skip the
  product (exception `unknownSubtype` / `noEditionLane`).
- Name and art label: repeatedly strip a trailing `\s*\(([^()]*)\)\s*$`. A
  suffix is a **rarity suffix** (dropped) if, compared case-insensitively, it
  equals the product's `Rarity`, or it is in
  `{UR, SR, SCR, SE, UTR, ULR, PUR, PCR, PSR, QCSR, QCR, GR, STR, CR, R, C, SP, SSP, MSR, ESR, GSR, PGR}`.
  Otherwise prepend it to `artLabels`. `cardName` = the remaining name;
  `artLabel` = `" · ".join(artLabels)` or `null`.
- `printingID` = v3 UUID of `"yugioh-printing:" + "tcgplayer:2:" + str(productId)`,
  lowercased. Python must match `DeterministicUUID.make`: take
  `md5((namespace+material).utf8)` as bytes, set
  `b[6] = (b[6] & 0x0F) | 0x30` and `b[8] = (b[8] & 0x3F) | 0x80`, then format
  it as a standard UUID.
- `cardID` = v3 UUID of `"yugioh-card:" + normalizedName`, where
  `normalizedName` = NFKD, lowercase, alphanumerics only, single spaces.
- Image URL = the product `imageUrl` (the `_200w.jpg` thumbnail). The display
  image is the same URL with `_200w` replaced by `_in_1000x1000`.

### 3.4 Cross-check with YGOPRODeck (decides auto-resolve eligibility)

Build `ygoRarities[code] = set(card_sets[].set_rarity)` and
`ygoNames[code] = set(card.name)` across all YGOPRODeck cards, plus
`passcodes[normalizedName] = {card.id} ∪ {img.id for img in card_images}`.

A code is **complete** only when all of these hold:

- the code exists in `ygoRarities`;
- `len(distinct TCGplayer Rarity values for the code) >= len(ygoRarities[code])`;
- every TCGplayer `cardName` for the code normalizes to a member of
  `ygoNames[code]`.

Codes that fail go into `incompleteCodes`, with the reason recorded in the
report. They stay in the seed so Browse and import still work, but scanning
returns `.catalogIncomplete`, never an automatic add.

Passcodes are attached per card from the YGOPRODeck name match; there are none
when the name does not match.

### 3.5 Seed schema (`schemaVersion: 1`, compact JSON, short keys)

```json
{
  "schemaVersion": 1,
  "generation": "yugioh-en-<first 12 hex of sha256 of the file with generation=\"\">",
  "capturedAt": "2026-10-20T00:00:00Z",
  "sets":  [{"g": 23416, "n": "25th Anniversary Rarity Collection II", "a": "RA02", "d": "2024-05-24"}],
  "cards": [{"id": "<uuid>", "n": "Number 60: Dugares the Timeless", "pc": [66011101]}],
  "printings": [{
    "id": "<uuid>", "c": "RA02-EN037", "g": 23416, "k": 0,
    "r": "Prismatic Collector's Rare", "art": null,
    "p": 551107, "pn": "Number 60: Dugares the Timeless (PCR)",
    "e": ["yugioh1stEdition"],
    "img": "https://tcgplayer-cdn.tcgplayer.com/product/551107_200w.jpg"
  }],
  "incompleteCodes": ["…"]
}
```

`k` is the index into `cards`, and `pn` is the exact TCGplayer product name the
transport validates against. Sort `printings` by `(c, d, r, art, p)`, where `d`
is the set release date (`publishedOn[:10]`, or `""`). The builder must fail
when: a printing ID is duplicated; a printing has an empty `e`; one `(g, p)`
appears twice; or the output code count is below 10,000 (sanity floor).

The report lists totals for groups, products, printings, codes, multi-printing
codes, incomplete codes, editions per lane and each exception class.

---

## 4. Recognition design

### 4.1 Flow per OCR frame (raw subject mode only)

```
footer OCR (unchanged) → profile.identify(footerLines)          // all games, footer only
  if outcome == .nothing and some adapter needsSupplementalText(footerLines):
      for each requested SupplementalTextRegion (YGO: one band):
          run supplementalTextRequest on that band
      outcome = profile.identify(footerLines:, supplementalLines: [regionID: lines])
          // only the owning adapter sees its band; the others re-run on footer only
  existing full-card fallback / Magic historical / Pokémon historical (unchanged; skipped once identified)
```

Supplemental OCR therefore runs only when no game identified the footer **and**
the footer shows YGO evidence. On Pokémon/Magic/Lorcana/One Piece frames that
identify, it never runs. On empty frames it never runs.

### 4.2 OCR request for the band

`supplementalTextRequest`: `.accurate`, `["en-US"]`, `usesLanguageCorrection = false`,
`customWords = []`. Correction off keeps `RA02-EN037` literal. That setting is
measured: all 3 legible codes in the 5 TCGplayer scans read exactly with
correction off. Do not add
YGO words to the shared footer vocabulary.

### 4.3 Band geometry (card-relative, Vision bottom-left)

`CGRect(x: 0.03, y: 0.20, width: 0.94, height: 0.11)`. Tolerance check: a YGO
card fitted to the guide's **height** keeps measured y (code 0.244–0.284). One
fitted to the guide's **width** is 4% taller, giving code y ≈ 0.234–0.275. Both
fall inside 0.20–0.31.

### 4.4 Code acceptance rules

- **Supplemental band:** the code line's ROI-relative `boundingBox.midX >= 0.45`
  (right side, under the art).
- **Footer band:** the code line's `boundingBox.minX < 0.5` (Pendulum,
  bottom-left).
- Lines with `boundingBox == nil` (unit tests) are accepted in either band.
- Token regex on the uppercased line:
  `(?<![A-Z0-9])([A-Z0-9]{2,4})\s?[-–—]\s?([A-Z0-9]{3,5})(?![A-Z0-9])`, giving
  `PREFIX-SUFFIX`.
- If the exact reading is in `catalog.printingsByCode`, use it alone. Otherwise
  generate confusion readings, substituting `O↔0, I→1, L→1, S↔5, B↔8, Z↔2` at
  up to 6 positions (≤ 64 readings), and keep those that are catalog members.
  Exactly one member → accept. More than one → `.ambiguous`. None → ignore the
  token. Never use edit distance or nearest-match.
- Distinct accepted codes across both bands: 0 → `.nothing`, more than 1 →
  `.ambiguous`.
- **Passcode guard:** 8-digit tokens `(?<![0-9])[0-9]{8}(?![0-9])` from footer
  lines with `minX < 0.45`. If any were read and the code's card passcode set is
  non-empty and shares none of them →
  `.rejected(.init(reason: "Passcode conflicts with printed code", blocksFallbackRecognition: true))`.
  A missing passcode is never a reason to reject.

### 4.5 Edition evidence (positive only)

Over footer lines with `minX < 0.5` and supplemental lines with `maxX <= 0.5`
(the historical left marker):

- `LIMITED\s*EDITION` (case-insensitive) → `.limited`.
- Otherwise `\bEDITION\b` (case-insensitive) on a line ≤ 40 UTF-16 units →
  `.first`. This tolerates `T Edition`, `1" Edition`, `1t Edition` and
  `s Edition`.
- Both kinds seen → `nil` (conflict). Nothing seen → `nil`. Absence never means
  Unlimited.

The result travels in a new `ScanSubject.printedEdition: PhysicalVariant?`. It
is **not** part of `ScanIdentifier` or the suppression key.

### 4.6 Trigger (`needsSupplementalText`)

True if any footer line (≤ 120 UTF-16 units) contains `KONAMI`
(case-insensitive), or an 8-digit token, or `\bEDITION\b`. Measured on 5 low-res
TCGplayer scans (200–500 px wide), at least one trigger token was read on 4. The
miss was the 200 px image. `KONAMI` was also read on all 6 YGOPRODeck renders.
Camera frames are far higher resolution; confirm on device (§10).

---

## 5. Resolution and UX design

### 5.1 Lookup outcomes (`YuGiOhCatalogAdapter.lookup`)

| Catalog state for the code | Outcome |
|---|---|
| Code in `incompleteCodes` | `.catalogIncomplete(familySummary)` → existing Needs attention row |
| Exactly 1 printing | `.resolved(…)`; the edition then goes through `VariantResolver` |
| More than 1 printing, all distinguishable | `.needsPrintingChoice(canonical:, candidates:)` |
| More than 1 printing, any with `.insufficient` selection evidence | `.catalogIncomplete(familySummary)` |

Candidate presentation (`PhysicalPrintingCandidate`):

- `releaseLabel` = set name
- `treatmentLabel` = rarity
- `distributionLabel` = art label
- `thumbnailURL` = image
- `artworkID` = printing UUID (each TCGplayer product image is its own scan)
- `distinctionLabels` = `nil`

`compactChoiceLabels` then shows just the rarity names for RA02-EN037, and
"Version 1/2/4" or set names for LDK2-ENK01.

### 5.2 Edition (variant) resolution

The editions are `PhysicalVariant`s, fixed constants defined in `CardVariant.swift`:

| Variant | id | label | `choicePriority` |
|---|---|---|---|
| `.yugiohFirstEdition` | `yugioh1stEdition` | `1st Edition` | 0 |
| `.yugiohUnlimited` | `yugiohUnlimited` | `Unlimited` | 1 |
| `.yugiohLimited` | `yugiohLimited` | `Limited Edition` | 2 |

They are added to `PhysicalVariant.known` so persisted IDs map back to their
labels. The `choicePriority` values must not disturb existing cases; give them
explicit `case`s.

- One edition → `.uniqueInCatalog`, zero taps.
- Several editions plus `subject.printedEdition` in the set →
  `.resolved(.printedLabel)`, zero taps.
- Several editions, no evidence → the existing one-tap variant choice.
- A Finish Lock (the edition lock, from `YuGiOhVariantPolicy`) applies only when
  there is no printed evidence. Printed evidence beats a lock (WP2.7).

The worst case (multi-rarity **and** multi-edition, no stamp read) is two
sequential taps, rarity then edition. That is the smallest honest question set,
and the edition can be corrected later through the existing edition-correction
flow.

### 5.3 Ownership and pricing identity

- Collection key: `ResolvedCatalogCard.collectionKey(variant:)`, i.e.
  `yu-gi-oh:<printingUUID>` qualified by the edition variant, through the
  existing codec. Rarities and editions never share a row.
- Price key: `PriceRecord.key(game: .yuGiOh, printingID:, variantID: edition.id)`
  → TCGCSV `(category 2, group, productId, pn, number = code, lane = edition subtype)`.

---

## 6. Work packages (implement in order, no builds in between)

Conventions: match the surrounding style. Lorcana is the template for most new
files; copy its structure rather than inventing new patterns. Use `apply_patch`
or an equivalent minimal edit, and do not reformat untouched code.

### WP1 — Catalog seed

Implement §3 and run the builder once. Commit `catalog.json` and the report.
Afterwards spot-check with `python3 -I` that `RA02-EN037` has 7 printings, each
with `e == ["yugioh1stEdition"]`; that `GENF-EN098` has 2, each with both
editions; and that `LOB-001`, `LOB-EN001` and `L26D-ENM26` exist. A JSON
spot-check is not a build, so this is allowed.

### WP2 — Shared seams (small, generic edits)

**WP2.1 `TradingCardScanner/Models/CardGame.swift`:** add
`static let yuGiOh = CardGame(rawValue: "yu-gi-oh")`.

**WP2.2 `TradingCardScanner/Models/CardGameRegistry.swift` (`standard`):**
append `.init(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4, capabilities: [])`.

**WP2.3 `TradingCardScanner/Models/CardVariant.swift`:** add the three
statics from §5.2 under a `// Yu-Gi-Oh! editions.` comment and include them in
`known`. Add their `choicePriority` cases.

**WP2.4 `TradingCardScanner/Services/TCGCSVProductPriceSource.swift:48`:**
extend the lane whitelist to
`["Normal", "Foil", "Cold Foil", "Holofoil", "1st Edition", "Unlimited", "Limited"]`.

**WP2.5 `TradingCardScanner/Games/Core/GameRecognitionAdapter.swift`:**

```swift
/// A narrow card-relative band (Vision, bottom-left origin) read only for the
/// adapter that requests it. Other adapters never receive its text.
struct SupplementalTextRegion: Hashable, Sendable {
    let id: String
    let cardRelativeRect: CGRect
}

protocol GameRecognitionAdapter: Sendable {
    // existing requirements…
    var supplementalRegion: SupplementalTextRegion? { get }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome
}

extension GameRecognitionAdapter {
    var supplementalRegion: SupplementalTextRegion? { nil }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool { false }
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome {
        identify(footerLines)
    }
}
```

In `GameRecognitionRegistry` add:

```swift
func supplementalRegions(afterFooterLines lines: [RecognizedLine]) -> [SupplementalTextRegion] {
    var seen: Set<String> = []
    return recognizers.compactMap { adapter in
        guard let region = adapter.supplementalRegion,
              adapter.needsSupplementalText(afterFooterLines: lines),
              seen.insert(region.id).inserted else { return nil }
        return region
    }
}

func identify(footerLines: [RecognizedLine],
              supplementalLines: [String: [RecognizedLine]]) -> RecognitionOutcome {
    let outcomes = recognizers.map { adapter -> (CardGame, GameRecognitionOutcome) in
        guard let region = adapter.supplementalRegion, let lines = supplementalLines[region.id] else {
            return (adapter.game, adapter.identify(footerLines))
        }
        return (adapter.game, adapter.identify(footerLines: footerLines, supplementalLines: lines))
    }
    return aggregate(outcomes)
}
```

Note: the new two-argument method name differs from the existing
`identify(footerLines:fullCardLines:)` by its label. Keep both.

**WP2.6 `TradingCardScanner/Services/CardScanner.swift`** (keep it game-neutral;
the boundary audit forbids `.yuGiOh` here):

1. `CardFramingRegion`: change `private static func cardRelativeRect` to
   `static func cardRelativeRect` (internal), so the band can be converted.
2. `RecognitionProfile`: add pass-throughs.

   ```swift
   func supplementalRegions(afterFooterLines lines: [RecognizedLine], outcome: RecognitionOutcome) -> [SupplementalTextRegion] {
       guard outcome == .nothing else { return [] }
       return recognizers.supplementalRegions(afterFooterLines: lines)
   }
   func identify(footerLines: [RecognizedLine], supplementalLines: [String: [RecognizedLine]]) -> RecognitionOutcome {
       recognizers.identify(footerLines: footerLines, supplementalLines: supplementalLines)
   }
   ```

3. Add `private var supplementalTextRequest = VNRecognizeTextRequest()` next to
   `fullCardTextRequest` (~line 869). Configure it in the text-request setup
   (~line 1691): `.accurate`, `["en-US"]`, `usesLanguageCorrection = false`.
   Recreate it in `rebuildTextRequests()` (~line 1708).
4. In `processFrame`, inside the `footerParse` `do` block, immediately after
   `outcome = profile.identify(lines)` and **before** the existing
   `needsFullCardText` block:

   ```swift
   if subjectMode == .raw {
       let regions = profile.supplementalRegions(afterFooterLines: lines, outcome: outcome)
       if !regions.isEmpty {
           let state = PerformanceSignpost.beginInterval("supplementalOCR", id: PerformanceSignpost.makeID(),
               "encounter=\(latchEncounterID?.uuidString ?? "none")")
           var supplemental: [String: [RecognizedLine]] = [:]
           for region in regions {
               let r = region.cardRelativeRect
               supplementalTextRequest.regionOfInterest = CardFramingRegion.cardRelativeRect(
                   x: r.minX, y: r.minY, width: r.width, height: r.height)
               try handler.perform([supplementalTextRequest])
               supplemental[region.id] = recognizedLines(from: supplementalTextRequest,
                   roi: supplementalTextRequest.regionOfInterest, sourceSize: sourceSize)
           }
           PerformanceSignpost.endInterval("supplementalOCR", state,
               "encounter=\(latchEncounterID?.uuidString ?? "none")")
           outcome = profile.identify(footerLines: lines, supplementalLines: supplemental)
       }
   }
   ```

   Match the exact `PerformanceSignpost` call shapes already used for
   `footerOCR` in this function.

**WP2.7 `TradingCardScanner/Services/ScanParser.swift` (`ScanSubject`,
`CandidateConfirmationWindow`):**

- Add `let printedEdition: PhysicalVariant?` and an init parameter
  `printedEdition: PhysicalVariant? = nil`. Leave `suppressionKey`,
  `displayIdentifier` and `matchesKnownSlabIdentity` unchanged.
- In `mergedSubject`, compute
  `let editions = Set(observations.compactMap(\.printedEdition))` and
  `let edition = editions.count == 1 ? editions.first : nil`. In the `default:`
  branch return `candidate` unchanged when `candidate.printedEdition == edition`.
  Otherwise return
  `ScanSubject(identifier: candidate.identifier, slab: candidate.slab, inferredNameReadings: candidate.inferredNameReadings, printedEdition: edition)`.
  The Pokémon branches are untouched; they never carry an edition.

**WP2.8 `TradingCardScanner/Views/ScannerViewModel.swift`:**

1. ~line 4288, the `VariantResolver.resolve` call:

   ```swift
   let printedEdition = request.subject.slab == nil ? request.subject.printedEdition : nil
   switch VariantResolver.resolve(
       evidence,
       finishLock: request.subject.slab == nil && printedEdition == nil ? finishLocks[card.game] : nil,
       printedFinish: request.subject.slab?.printedFinish ?? printedEdition
   ) {
   ```

2. Add `private static func revalidatesBundledAcquisition(_ game: CardGame) -> Bool { game == .lorcana || game == .yuGiOh }`
   and use it in place of `== .lorcana` at ~3491, ~3544, ~5389 and ~5483.
   Re-locate these by grepping `game == .lorcana`; line numbers drift.

**WP2.9 `TradingCardScanner/Services/CollectionStore.swift:874`:** change
`identifier.game == .lorcana` to
`[CardGame.lorcana, .yuGiOh].contains(identifier.game)`.

**WP2.10 `scripts/audit_game_boundaries.sh`:** extend the game regex to
`\.(pokemon|magic|onePiece|lorcana|yuGiOh)`.

### WP3 — `TradingCardScanner/Games/YuGiOh/` module (new files)

**WP3.1 `YuGiOhCatalog.swift`** holds the model, decoding and indexes.

```swift
enum YuGiOhEdition: String, CaseIterable, Codable, Sendable {
    case first = "yugioh1stEdition", unlimited = "yugiohUnlimited", limited = "yugiohLimited"
    var variant: PhysicalVariant { switch self { case .first: .yugiohFirstEdition; case .unlimited: .yugiohUnlimited; case .limited: .yugiohLimited } }
    var tcgplayerSubtype: String { switch self { case .first: "1st Edition"; case .unlimited: "Unlimited"; case .limited: "Limited" } }
}

struct YuGiOhCatalog: Sendable {
    struct SetInfo: Hashable, Sendable { let groupID: Int; let name: String; let abbreviation: String; let releaseDate: Date? }
    struct Card: Hashable, Sendable { let id: UUID; let name: String; let passcodes: Set<Int> }
    struct Printing: Hashable, Sendable {
        let id: UUID; let code: String; let set: SetInfo; let card: Card
        let rarity: String; let artLabel: String?
        let productID: Int; let productName: String
        let editions: [YuGiOhEdition]; let thumbnailURL: URL?; let imageURL: URL?
        var idString: String { id.uuidString.lowercased() }
    }
    enum LoadError: Error { case missingResource, invalidSchema, invalidRow(String) }

    let generation: String
    let capturedAt: Date
    let printingsByCode: [String: [Printing]]   // seed order
    let printingByID: [UUID: Printing]
    let incompleteCodes: Set<String>
    let setsByGroupID: [Int: SetInfo]

    init(data: Data) throws   // decode the private short-key Codable structs; validate
    static let bundled: Result<YuGiOhCatalog, Error> = Result {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed")
        else { throw LoadError.missingResource }
        return try YuGiOhCatalog(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
    var runtime: CardGameRuntime { YuGiOhGameRuntime(catalog: self).runtime }
}
```

Validation in `init(data:)`, throwing on any failure:

- `schemaVersion == 1`, and `generation` is non-empty with prefix `yugioh-en-`;
- printing IDs unique and lowercase;
- every `k` within `cards`;
- every `g` within `sets`;
- `e` non-empty and all known editions;
- code matches §3.3's grammar.

Do **not** recompute MD5 UUIDs at launch; a test does that.

**WP3.2 `YuGiOhRecognitionAdapter.swift`** implements §4.4–4.6.

```swift
struct YuGiOhRecognitionAdapter: GameRecognitionAdapter {
    static let underArtRegion = SupplementalTextRegion(id: "yugioh.under-art",
        cardRelativeRect: CGRect(x: 0.03, y: 0.20, width: 0.94, height: 0.11))
    let catalog: YuGiOhCatalog
    var game: CardGame { .yuGiOh }
    var customWords: [String] { [] }
    var supplementalRegion: SupplementalTextRegion? { Self.underArtRegion }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool { … §4.6 }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome { identify(footerLines: lines, supplementalLines: []) }
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome { … §4.4–4.5 }

    static func identifier(code: String, generation: String) throws -> ScanIdentifier {
        try .init(game: .yuGiOh, namespace: "printed-set-code",
                  fields: [.init(key: "code", value: code)],
                  displayIdentifier: code, suppressionIdentity: "code:\(code)",
                  catalogGeneration: generation)
    }
}
```

Reuse Lorcana's line-validity guard: skip lines longer than 1,024 UTF-16 units
and lines whose bounding box is non-finite or outside the unit rect.

**WP3.3 `YuGiOhCatalogAdapter.swift`** conforms to `GameCatalogAdapter`.
Mirror `LorcanaCatalogAdapter` (`Games/Lorcana/LorcanaGameRuntime.swift:3-189`)
method by method:

- `code(for:)`: the identifier must be `.yuGiOh`, namespace `printed-set-code`,
  have the single field `code`, a matching `displayIdentifier`, and suppression
  `code:<code>`. Otherwise throw `.invalidAdapterOutcome`.
- `prepareLookupIdentifier` / `validateLookupContext` / `identifierForRetry`:
  check the generation, then `code(for:)`. `identifierForRetry` rebuilds with
  the current generation.
- `identifierForCatalogSelection(printingID:original:)`: lowercase UUID must be
  in `printingByID`; return an identifier for that printing's code.
- `lookup`: follow §5.1. Family summary is
  `CanonicalCardSummary(id: card.id.uuidString.lowercased(), game:, name: card.name, printedIdentifier: code, language: "en")`;
  when names differ across the family, use the first printing's card.
- `resolve(candidate, for:)`: the candidate must equal the freshly built
  candidate for a family member, and its selection evidence must not be
  `.insufficient`.
- `validateAcquisition(_:printingID:automatic:)`: the printing must be in the
  code's family. `automatic` requires family count == 1 and the code not in
  `incompleteCodes`. Manual requires selection evidence that is not
  `.insufficient`.
- `validateVariantCorrection(printingID:variantID:)`: the variant must be in the
  printing's editions.
- `validateCollectionMutation(...)`: `itemKindRaw == CollectionItemKind.rawCard.rawValue`;
  lowercase UUID; `catalogProviderID` is nil or equal; the edition belongs to
  the printing; and `collectionKey == card.collectionKey(variant: edition.variant)`.
- `resolution(forPrintingID:)`: used by Browse, import and pricing.
- `resolution(_ printing:)` builds `ResolvedCatalogCard` with:

  ```swift
  try ResolvedCatalogCard(game: .yuGiOh, physicalPrintingID: p.idString,
      canonicalCardID: p.card.id.uuidString.lowercased(), language: "en",
      name: familyCount > 1 ? "\(p.card.name) · \(compactLabel)" : p.card.name,
      setName: p.set.name, setCode: p.set.abbreviation, cardNumber: p.code,
      printedIdentifier: p.code, rarity: p.rarity,
      displayImageURL: p.imageURL, thumbnailImageURL: p.thumbnailURL,
      setReleaseOrder: yyyymmdd(p.set.releaseDate),
      variantEvidence: .init(game: .yuGiOh, setID: "tcgplayer-group:\(p.set.groupID)",
          cardNumber: p.code, catalogVariants: p.editions.map(\.variant)))
  ```

  then `.init(card, retrievedAt: catalog.capturedAt, path: .cacheHit)`.
  `compactLabel` comes from `PhysicalPrintingCandidate.compactChoiceLabels(among:)`.

**WP3.4 `YuGiOhBrowseAdapter.swift`:** copy `LorcanaBrowseAdapter`. Sets are
TCGCSV groups: `CatalogSetID(game: .yuGiOh, providerID: "tcgplayer-group:\(g)")`,
name = set name, code = abbreviation, `releaseDate` from the seed. Order sets by
release date descending, then ID; order cards by code, then rarity, then ID.
Search text = normalized name, code, rarity, art label and set name.
`details(for:)` → `CatalogCardDetails(card:set:retrievedAt:)` from
`resolution(forPrintingID:)`. Build the indexes once in `init`.

**WP3.5 `YuGiOhPriceAdapter.swift`:** copy `LorcanaPriceAdapter`, without the
coordinator (no activation source).

- The source protocol is `YuGiOhMarketPriceSource`. The default implementation
  calls
  `TCGCSVProductPriceSource.shared.quote(category: 2, group: p.set.groupID, productID: p.productID, name: p.productName, number: p.code, lane: edition.tcgplayerSubtype, generation: catalog.generation, minimumFetchedAt:)`.
- `mappingIdentity(p, edition)` = `"tcgcsv:2:\(groupID):\(productID):\(subtype)"`
  as a plain string; no hashing.
- `priceAuthority(catalog)` → `GameCatalogPriceAuthority(game: .yuGiOh, managedSources: [.tcgCSV], identityByPriceKey:)`
  over every printing × edition.
- `refresh`:
  - the identity must match the current resolution and `request.variant` must
    be one of the printing's editions, else `identityMismatch`;
  - an edition with no lane → `.unavailable(nil)`;
  - validate the USD, finite, non-negative and freshness rules exactly as
    Lorcana does;
  - stamp `price.catalogIdentity`;
  - `allowsProviderFallback = false`, `supportsStoredPrintingRefresh = true`.

**WP3.6 `YuGiOhImportAdapter.swift`:** copy `LorcanaImportAdapter`. Drop the
`sourceAliases` branch: `sourceProviderID` must equal the UUID. Number matching
accepts `entry.cardNumber == code` or empty. Language is `en`/`english`/`eng`.

**WP3.7 `YuGiOhGameRuntime.swift`:**

```swift
struct YuGiOhVariantPolicy: GameVariantPolicy {
    let selectableVariants: [PhysicalVariant] = YuGiOhEdition.allCases.map(\.variant)
}

struct YuGiOhGameRuntime: Sendable {
    static let descriptor = CardGameDescriptor(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4, capabilities: [])
    let catalog: YuGiOhCatalog
    var runtime: CardGameRuntime {
        .init(descriptor: .init(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4,
                                capabilities: [.scan, .browse, .pricing, .collectionWrite]),
              variantPolicy: YuGiOhVariantPolicy(),
              pricing: YuGiOhPriceAdapter(catalog: catalog),
              recognizer: YuGiOhRecognitionAdapter(catalog: catalog),
              catalog: YuGiOhCatalogAdapter(catalog: catalog),
              browse: YuGiOhBrowseAdapter(catalog: catalog),
              importer: YuGiOhImportAdapter(catalog: catalog),
              priceAuthority: YuGiOhPriceAdapter.priceAuthority(catalog),
              requiresLaunchActivation: false)
    }
}
```

Register it in `CardGameRuntimeContainer.appDefaults()`
(`Games/Core/CardGameRuntime.swift`), **immediately after the Lorcana
`do/catch`** and before any `#if … LOCAL_ONLY_SIGNING` early return:

```swift
do {
    modules.append(try YuGiOhCatalog.bundled.get().runtime)
} catch {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
        .error("Yu-Gi-Oh! seed rejected; existing games remain available")
    unavailable.append(YuGiOhGameRuntime.descriptor)
}
```

Also check the two `return try! Self(runtimes: modules)` calls that omit
`unavailable` in the DEBUG branches. Leave them as they are; YGO is appended
before them.

### WP4 — Xcode project registration (`TradingCardScanner.xcodeproj/project.pbxproj`)

The project uses hand-assigned IDs, not synchronized folders. Use the unused
prefixes `F40A…` (PBXBuildFile) and `F40B…` (PBXFileReference). Copy the
Lorcana entries exactly:

| Lorcana entry to copy | YGO addition |
|---|---|
| `F30B…0002` (`path = Lorcana/LorcanaRecognitionAdapter.swift`), in the **Games** group children list, line ~774 | 7 app files, `path = YuGiOh/<File>.swift`, in the same group's children |
| `F30A…0002`, in the app target's **Sources** build phase | A Sources entry for each of the 7 app files |
| `F30B…0004` (`LorcanaIntegrationTests.swift`), in the test group, line ~1050, and the test target's **Sources** phase | Each new test file, in the test group and the test Sources phase |
| `F30B…0014` (`path = ../LorcanaCatalogSeed`, `lastKnownFileType = folder`) and `F30A…0014`, in the app **Resources** phase | `YuGiOhCatalogSeed` folder reference |

Keep IDs 24 hex characters, unique and sequential (`F40A00000000000000000001`, …).

### WP5 — Tests (write now; run only in §9)

Create these test files, using `LorcanaIntegrationTests` and `LorcanaPricingTests`
for fixture style and URLProtocol stubbing:

1. **`YuGiOhCatalogTests.swift`**
   - The bundled seed loads and its generation has prefix `yugioh-en-`.
   - Every printing ID equals
     `DeterministicUUID.make(namespace: "yugioh-printing:", material: "tcgplayer:2:\(productID)")`.
   - `RA02-EN037` has 7 printings with 7 distinct rarities, all `[.first]`.
   - `GENF-EN098` has 2 printings, each `[.first, .unlimited]`.
   - `LOB-001` and `LOB-EN001` are both present with different printing IDs.
   - `L26D-ENM26` is present.
   - `LDK2-ENK01` has more than one printing, and the candidates' compact labels
     are pairwise distinct.
   - No printing has empty editions.
   - Malformed seeds are rejected: duplicate ID, empty `e`, unknown edition,
     wrong schema version.
2. **`YuGiOhRecognitionTests.swift`** (synthetic `RecognizedLine`s with boxes).
   *Positive cases:*
   - an under-art right-side code is identified;
   - the same code on the left in the band gives `.nothing`;
   - a footer bottom-left code (Pendulum) is identified;
   - `RAO2-EN037` is repaired to `RA02-EN037`.

   *Rejections:*
   - a non-catalog code gives `.nothing`;
   - two valid codes give `.ambiguous`;
   - a conflicting passcode gives `.rejected`;
   - a matching or absent passcode is identified.

   *Edition evidence:*
   - `"1t Edition"` in the footer → `.yugiohFirstEdition`;
   - `"T Edition"` in the band's left side → `.yugiohFirstEdition`;
   - `"LIMITED EDITION"` → `.yugiohLimited`;
   - both → `nil`;
   - none → `nil`.

   *Trigger:*
   - `needsSupplementalText` is true for `©2020 Studio Dice/SHUEISHA, TV TOKYO, KONAMI`
     and for `66011101`;
   - it is false for a Pokémon footer `123/198` and a Magic footer `0123 R MKM • EN`.

   *Cross-game:*
   - `OP01-001` (One Piece) and the Lorcana/Pokémon/Magic sample footers give the
     YGO adapter `.nothing`.
3. **`GameRecognitionRegistrySupplementalTests.swift`**
   - A stub adapter records what it received: supplemental lines reach only the
     owning adapter, and the others get footer lines only.
   - `supplementalRegions` deduplicates by ID and is empty when no adapter asks.
   - `RecognitionProfile.supplementalRegions` is empty when the outcome is not
     `.nothing`.
   - Aggregation still returns `.ambiguous` for two identities.
4. **`YuGiOhResolutionTests.swift`**
   - `lookup(RA02-EN037)` → `.needsPrintingChoice` with 7 candidates.
   - A single-printing code → `.resolved`.
   - An incomplete code → `.catalogIncomplete`.
   - A stale generation → `staleCatalog`.
   - `validateAcquisition(automatic: true)` throws for multi-printing codes and
     passes for single-printing ones.
   - `validateCollectionMutation` passes for a valid printing/edition/key and
     fails for a wrong edition, a wrong key or an uppercase UUID.
   - `VariantResolver.resolve` with `[.first, .unlimited]`: no evidence →
     `.needsChoice`; `printedFinish: .yugiohFirstEdition` → `.resolved(.printedLabel)`;
     `printedFinish: .yugiohLimited` → `.needsChoice`.
   - `CandidateConfirmationWindow` merges an edition seen in one of two matching
     observations, drops conflicting editions, and leaves the suppression key
     unchanged.
5. **`YuGiOhPricingTests.swift`**
   - A stubbed source receives category 2, the right group/product, and lane
     `1st Edition` / `Unlimited`.
   - A variant not on the printing → `identityMismatch`.
   - The price authority has one key per printing × edition.
   - `TCGCSVProductPriceSource` accepts `Unlimited` and still rejects `Reverse
     Holofoil`; stub the HTTP like the Lorcana pricing tests do.
6. **`YuGiOhImportTests.swift`**
   - A valid row passes.
   - Missing finish → `.missingFinish`.
   - Wrong edition → `.unsupportedFinish`.
   - Wrong key → `.invalidOwnershipKey`.
   - A non-UUID provider → `.invalidPrinting`.
7. **Update existing tests**
   - `CardGameForwardCompatibilityTests.swift:381`: add `("Yu-Gi-Oh!", .yuGiOh)`
     if that list enumerates the standard registry.
   - Add one test that `CardGameRuntimeContainer.appDefaults().registry`
     supports `.yuGiOh` for `.scan`, `.browse`, `.pricing` and `.collectionWrite`.

### WP6 — Documentation

- `docs/README.md` links this plan in the "Yu-Gi-Oh! integration" row. Update
  that row's status text when implementation lands.
- Add a dated root `progress.md` entry when the code lands, stating exactly what
  §9 verified.

---

## 7. Edge cases the implementation must hold

| Case | Required behavior |
|---|---|
| RA02-EN037 (7 rarities, 1st only) | One rarity tap, no edition tap, never auto-pick the first rarity |
| GENF-EN098 (2 rarities × 2 editions) | Rarity tap. Edition tap unless a stamp was read |
| LOB-001 vs LOB-EN001 vs LOB-E001 | Exact string match only. Never normalize the region away |
| L26D-ENM26 | Alphanumeric suffix accepted through catalog membership |
| LDK2-ENK01 (3 arts × 2 releases) | Choice shows set name and Version label. Insufficient labels → catalogIncomplete |
| Pendulum Monster | Code read from the footer band (left side) |
| Missing stamp on a 1st/Unlimited printing | Ask. Never infer Unlimited |
| Passcode contradicts the code | Reject the frame (blocks fallback) |
| Another game's card in frame | YGO band never runs when the footer identified a card. YGO never sees other games' bands |
| YGO code text in effect text or on the left of the band | Ignored by position and membership |
| Seed fails to load | YGO goes to `unavailableGames`; the other four games work |
| Null TCGCSV market price | `.unavailable(.tcgCSV)` "no current market quote". Never substitute low/mid |
| Provider down | Existing cooldown/`providerUnavailable`. The previous valid quote is retained by the shared store |

---

## 8. Done-definition for the implementing agent (before §9)

- [ ] WP1–WP6 complete, and the seed plus report committed.
- [ ] `rg -n "\.yuGiOh" TradingCardScanner/Services/{BrowseCatalog,CardScanner,CardCatalog,PriceQuoteService,CollectionCatalogNormalizer}.swift`
      returns nothing.
- [ ] No files changed outside §6's list (check `git status`).
- [ ] Then run §9 once.

---

## 9. Deferred verification (run once, after WP1–WP6)

Put every artifact on the external SSD (match `/Volumes/Keller Family Photos*`).
Pick an available simulator UDID with
`xcrun simctl list devices available | grep -m1 "iPhone"`. These are headless
`xcodebuild` test runs; no interactive simulator use is needed.

1. Boundary audit and whitespace checks:

   ```bash
   scripts/audit_game_boundaries.sh && git diff --check
   ```

2. Build the app and tests once, then run the focused YGO and seam tests:

   ```bash
   xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug \
     -destination "platform=iOS Simulator,id=$SIM" \
     -derivedDataPath "$SSD/CardScannerBuilds/yugioh/DerivedData" \
     -clonedSourcePackagesDirPath "$SSD/CardScannerBuilds/yugioh/SourcePackages" \
     -resultBundlePath "$SSD/CardScannerBuilds/yugioh/focused.xcresult" \
     -only-testing:TradingCardScannerTests/YuGiOhCatalogTests \
     -only-testing:TradingCardScannerTests/YuGiOhRecognitionTests \
     -only-testing:TradingCardScannerTests/GameRecognitionRegistrySupplementalTests \
     -only-testing:TradingCardScannerTests/YuGiOhResolutionTests \
     -only-testing:TradingCardScannerTests/YuGiOhPricingTests \
     -only-testing:TradingCardScannerTests/YuGiOhImportTests
   ```

3. Fix any failures, then run the regression neighbors once:
   `CardGameForwardCompatibilityTests`, `ScanParserTests`, `ScannerViewModelTests`,
   `CardLatchTests`, `LorcanaIntegrationTests`, `LorcanaPricingTests`,
   `OnePieceIntegrationTests`, `PricingTests`, `CSVImportResumeTests`,
   `CollectionKeyTests`.
4. Run the full suite only if step 3 touched shared behavior unexpectedly.
   Report pass, fail and skip counts against the documented pre-existing
   failures (`docs/AGENTS.md`).
5. Record the results in `progress.md` and this plan's status line. Make no
   device or release claims.

---

## 10. Owner gates (not closable by the implementing agent)

1. **Rights.** Approve TCGCSV/TCGplayer data and CDN image display, YGOPRODeck
   data use, and the Konami names/marks for App Store distribution.
2. **Device camera calibration.** On an iPhone, measure the band on at least 20
   cards: modern, LOB-era, Pendulum, Link, RA05 extended art, sleeved, and glare.
   Adjust `YuGiOhRecognitionAdapter.underArtRegion` only. Compare the
   `supplementalOCR` signpost cost to `footerOCR`. The target is under 15 ms
   median added on YGO frames and none on other games.
3. **Throughput regression.** Scan a 20-card stack each of Pokémon, Magic,
   Lorcana and One Piece, and confirm the YGO band never fires (signpost count 0).
4. **Wrong-printing safety.** In a 100-card YGO sample there must be zero wrong
   automatic adds. Rarity choices must appear for multi-rarity codes.
5. **Catalog refresh cadence.** Re-run the builder for new sets. Each refresh is
   an app update until signed remote updates are scheduled.
