> **Legacy — reviewed plan snapshot.** Superseded by the [current implementation authority](../../plans/yugioh_code_implementation.md). Historical design and unchecked tasks below are not current instructions or evidence.

# Yu-Gi-Oh! implementation plan

**Status — 2026-10-21:** plan only, **revised after review** (§1.5). Nothing is
implemented, built or tested yet. Written against `main` at `06459ea` and
re-checked against `81a6f2c`, the commit that added this plan; no app source
changed between them. The research handoff it validates was
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
- Whether TCGCSV price rows list every physical edition of a product. §3.3 no
  longer assumes they do.
- YGOPRODeck `misc_info[].beta_name` coverage for renamed cards (§3.4). The
  builder must report it; it was not confirmed from a live JSON join.

### 1.5 Review corrections (2026-10-21)

A review of the first draft against the source at `81a6f2c` found that several
automatic-resolution rules were less safe than claimed. The risk is not failing
to recognize a card. It is reading enough to save the wrong printing or edition
with confidence. Each defect below was confirmed in the source or follows from
the algorithm as written. The sections it changed are listed.

| # | Defect in the first draft | Source evidence | Fix (section) |
|---|---|---|---|
| R1 | A short line reading only `EDITION` counted as 1st Edition. If OCR drops `LIMITED`, a Limited card is saved as 1st. | §4.5 as drafted | Bare `EDITION` is an unread marker. It excludes Unlimited but proves no edition (§4.5). |
| R2 | First vs Limited conflicts collapsed to `nil`. WP2.8 treated `nil` as "no evidence", so the edition lock applied again and a conflict could resolve to Unlimited. | §4.5, WP2.7–2.8 as drafted | Use a three-way evidence type: absent, observed, or conflicting/unread. Conflict and unread both disable the lock (§4.5, WP2.7, WP2.8). |
| R3 | `VariantResolver` returns `.uniqueInCatalog` for a single catalog edition before it looks at `printedFinish`. A 1st-only catalog entry wins even when the card was read as Limited. | `Services/VariantResolver.swift:136-143` | A pre-resolver gate that runs only when edition evidence is present. Only YGO produces that evidence, so other games keep their behavior (WP2.8). |
| R4 | Edition evidence was lost on retry, on unresolved-scan merges and on persisted Needs attention recovery. Those paths rebuild `ScanSubject` from its old fields. | `Views/ScannerViewModel.swift:1162-1189, 3671-3672`; `Services/UnresolvedScanStore.swift:200-262, 440-444` | Thread the field through every copy, merge, retry and persistence path, with backward-compatible decoding (WP2.11). |
| R5 | The completeness check compared rarity counts and names only. A missing printing with the same rarity, or a skipped product, left the check passing. That could leave one TCGplayer product, which would then be added automatically. | §3.4 as drafted | Check rarity agreement, printing coverage and edition coverage separately. Any skipped product makes its code incomplete (§3.3, §3.4). |
| R6 | Price rows defined the edition universe. A missing price row would make a printing look single-edition and resolve automatically. | §3.3 as drafted | Physical editions come from the set-level union of lanes. Priced lanes are a separate field (§3.3, §3.5, WP3.5). |
| R7 | `artworkID` was set to the printing UUID. The shared logic then reads any distinct `artworkID` plus a thumbnail as visual proof. Products with identical labels would pass as distinguishable when their scans may look the same. | `Games/Core/GameCatalogAdapter.swift:170-201` | `artworkID = nil` in v1. Identical-label families stay `.insufficient`, so they become `catalogIncomplete` (§5.1). |
| R8 | Renamed cards failed the name join. For example, PSV-EN049 is listed as *Harpie's Brother* on TCGplayer and *Sky Scout* on YGOPRODeck. The code became incomplete, and a name-derived card ID split the card's identity. | Public TCGplayer and YGOPRODeck pages; no live JSON join was run | Alias join through YGOPRODeck `beta_name` plus a reviewed alias file. The card ID comes from the YGOPRODeck card ID (§3.3, §3.4). |
| R9 | The tests left out the dangerous interactions and the end-to-end chain. | WP5 as drafted | New regression cases and a scan → save → relaunch chain (WP5, §9). |

Kept from the first draft: the bundled catalog first, separate printing and
edition identity, exact product/edition price joins with no low/mid
substitution, no visual rarity guessing, and adapter-owned OCR.

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

- New `scripts/build_yugioh_catalog.py` (Python 3, stdlib only), with a
  `--self-test` mode that builds from `scripts/fixtures/yugioh/` offline and
  asserts the §3.3–3.4 rules (WP5.1 lists the cases).
- New `scripts/fixtures/yugioh/` (small hand-written TCGCSV/YGOPRODeck JSON) and
  `scripts/yugioh_name_aliases.json` (reviewed renamed-card aliases).
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
- Priced lanes (`pe`): map the product's price rows by `subTypeName`:
  `{"1st Edition": "yugioh1stEdition", "Unlimited": "yugiohUnlimited", "Limited": "yugiohLimited"}`.
  Any other subtype on the product, or zero recognized subtypes → skip the
  product (exception `unknownSubtype` / `noEditionLane`).
- Physical editions (`e`): the union of priced lanes across every kept product
  in the same group. A price row proves a lane is priced. It does not prove that
  the product's other editions do not exist. Set-level union over-asks rather
  than under-asks: a printing priced only in 1st Edition, in a set that also has
  Unlimited products, offers both and asks unless the card's printed evidence
  decides it. `pe ⊆ e` always. An edition in `e` but not in `pe` can be owned,
  but its price is `.unavailable`.
- **Skipped products poison their code.** Any product skipped for `noRarity`,
  `unknownSubtype` or `noEditionLane` whose `number` still matches the code
  grammar adds that code to `incompleteCodes` with reason `skippedProduct`.
  Otherwise the code could keep one remaining product and be added
  automatically.
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
- `cardID` = v3 UUID of `"yugioh-card:" + "ygoprodeck:" + str(card.id)` when
  §3.4 matches the product to a YGOPRODeck card by name or alias. Otherwise use
  `"yugioh-card:" + "name:" + normalizedName`, where
  `normalizedName` = NFKD, lowercase, alphanumerics only, single spaces. The
  YGOPRODeck ID keeps a renamed card (printed under its old name) and its
  current-name reprints on one canonical identity.
- Image URL = the product `imageUrl` (the `_200w.jpg` thumbnail). The display
  image is the same URL with `_200w` replaced by `_in_1000x1000`.

### 3.4 Cross-check with YGOPRODeck (decides auto-resolve eligibility)

Build, across all YGOPRODeck cards:

- `ygoEntries[code]` = the list of `(set_name, set_rarity)` tuples from
  `card_sets[]`, keeping duplicates that differ by set name;
- `ygoRarities[code]` = the distinct `set_rarity` values;
- `ygoCards[code]` = the YGOPRODeck card IDs that list the code;
- `namesByCard[id]` = `{normalize(card.name)} ∪ {normalize(m.beta_name) for m in misc_info if beta_name}`
  ∪ the entries for `id` in a committed, reviewed
  `scripts/yugioh_name_aliases.json` (`{"<ygoprodeck id>": ["<printed name>", …]}`);
- `passcodes[id] = {card.id} ∪ {img.id for img in card_images}`.

A TCGplayer product **matches** card `id` when `id ∈ ygoCards[code]` and the
product's normalized `cardName` is in `namesByCard[id]`. A product matching more
than one card, or none, fails the name check.

Completeness has three separate parts. Each records its own reason:

1. **Rarity agreement** (`rarityShortfall`): the code is in `ygoRarities`, and
   `len(distinct TCGplayer Rarity values) >= len(ygoRarities[code])`. Rarity
   *names* are never joined (§1.2).
2. **Printing coverage** (`printingShortfall`): the number of distinct TCGplayer
   `(groupId, Rarity, artLabel)` printings for the code is at least
   `len(ygoEntries[code])`. This catches a missing same-rarity reprint, which
   rarity counts cannot see. There is no source for per-code artwork coverage,
   so artwork is not counted. Instead, any code whose family has an `artLabel`,
   or whose matched card has more than one `card_images` entry, is never
   eligible for an automatic add (rule 4 below).
3. **Name agreement** (`nameMismatch`): every product matches exactly one card,
   through names or aliases.

Plus:

4. **Automatic-add eligibility** (`autoEligible`, stored per code, not
   inferred): the code passes 1–3, has exactly one TCGplayer printing, has
   exactly one `ygoEntries` tuple, has no art label, and its matched card has
   exactly one `card_images` entry. A complete code that is not `autoEligible`
   can still be chosen manually and offers its printing choice. It is never
   added without a tap, even when the family has one printing.
5. Every `skippedProduct` code from §3.3 is incomplete.

Codes that fail 1, 2, 3 or 5 go into `incompleteCodes`, with every failing
reason recorded in the report. They stay in the seed so Browse and import still
work, but scanning returns `.catalogIncomplete`, never an automatic add.

Passcodes are attached per card from the match; there are none when nothing
matches. The report lists how many products matched only through
`beta_name` or the alias file. It must include PSV-EN049 (*Harpie's Brother* /
*Sky Scout*) as a fixture. If the live data does not join that pair, add it to
the alias file and record that.

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
    "pe": ["yugioh1stEdition"],
    "img": "https://tcgplayer-cdn.tcgplayer.com/product/551107_200w.jpg"
  }],
  "incompleteCodes": ["…"],
  "autoEligibleCodes": ["…"]
}
```

`k` is the index into `cards`, and `pn` is the exact TCGplayer product name the
transport validates against. `e` is the physical edition set and `pe` the
priced lanes (§3.3). Sort `printings` by `(c, d, r, art, p)`, where `d`
is the set release date (`publishedOn[:10]`, or `""`). The builder must fail
when: a printing ID is duplicated; a printing has an empty `e` or `pe`; `pe ⊄ e`;
one `(g, p)` appears twice; a code is in both `incompleteCodes` and
`autoEligibleCodes`; or the output code count is below 10,000 (sanity floor).

The report lists totals for groups, products, printings, codes, multi-printing
codes, incomplete codes by reason, `autoEligible` codes, printings where
`e ≠ pe`, alias-only matches, editions per lane and each exception class.

**Tradeoff, stated explicitly:** rule 4 in §3.4 means many single-printing
codes (any card with alternate artwork anywhere, which includes most staples)
ask for one confirming tap instead of saving silently. That slows bulk entry a
little. It is the cost of not adding a printing automatically when the catalog
cannot prove it is the only one. Revisit with device evidence (§10.4), not by
relaxing the rule in code.

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

### 4.5 Edition evidence (three-way, never inferred from absence)

New shared type in `Services/ScanParser.swift` (no game names):

```swift
/// What a frame's printed edition marker proved. `.absent` is not "Unlimited":
/// it means no marker was read. `.unreadable` means a marker was seen but its
/// edition was not legible, or two frames disagreed.
enum PrintedEditionEvidence: Hashable, Sendable, Codable {
    case absent
    case observed(PhysicalVariant)
    case unreadable
}
```

Classify each candidate line, over footer lines with `minX < 0.5` and
supplemental lines with `maxX <= 0.5` (the historical left marker), on lines of
≤ 40 UTF-16 units that contain `\bEDITION\b` (case-insensitive):

- `LIMITED\s*EDITION`, or a token before `EDITION` that is a ≥ 4-character
  fragment of `LIMITED` (`LIMI`, `IMITED`, `MITED`, …) → `.limited`.
- The token immediately before `EDITION` is 1–3 characters, contains a `1`,
  `I`, `l`, `T`, `S` or `s`, and is **not** a suffix of `LIMITED` (`D`, `ED`,
  `TED`) → `.first`. This keeps the measured misreads (`T Edition`,
  `1" Edition`, `1t Edition`, `s Edition`) as 1st Edition.
- Anything else, including a bare `EDITION`, a short `LIMITED` suffix, or an
  unrecognized prefix → `.unreadable`. **A bare `EDITION` never establishes
  1st Edition.** It does show that a marker exists, so it rules out an
  automatic Unlimited.

Frame result: no candidate lines → `.absent`. Exactly one distinct classified
edition and no `.unreadable` line → `.observed(edition)`. Otherwise
`.unreadable`. This covers a frame with both a 1st and a Limited reading.

The result travels in a new `ScanSubject.printedEdition: PrintedEditionEvidence`
(default `.absent`). It is **not** part of `ScanIdentifier` or the suppression
key. Being `.unreadable` should make the scanner try harder, not give up: the
confirmation window (WP2.7) merges later frames, so one clean read in the
window upgrades the result unless another frame contradicts it.

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
| Exactly 1 printing and the code is in `autoEligibleCodes` | `.resolved(…)`; the edition then goes through WP2.8 and `VariantResolver` |
| Exactly 1 printing, not `autoEligible` | `.needsPrintingChoice` with that one candidate: one confirming tap. This follows Lorcana's lone-oversized-record precedent (`Games/Lorcana/LorcanaGameRuntime.swift:58-68`) |
| More than 1 printing, all distinguishable | `.needsPrintingChoice(canonical:, candidates:)` |
| More than 1 printing, any with `.insufficient` selection evidence | `.catalogIncomplete(familySummary)` |

Candidate presentation (`PhysicalPrintingCandidate`):

- `releaseLabel` = set name
- `treatmentLabel` = rarity
- `distributionLabel` = art label
- `thumbnailURL` = image
- `artworkID` = **`nil`**. A distinct product ID does not prove distinct
  artwork. `selectionEvidenceByID` (`Games/Core/GameCatalogAdapter.swift:170-189`)
  counts distinct `artworkID`s plus thumbnails as visual proof, so setting this
  from the product would defeat the `.insufficient` safeguard. A later version
  may set it only from a reviewed artwork key, such as a verified passcode image
  ID, that is known to differ visibly.
- `distinctionLabels` = `nil`

`compactChoiceLabels` then shows just the rarity names for RA02-EN037, and
"Version 1/2/4" or set names for LDK2-ENK01. Two products whose labels match
exactly (same set, rarity, art label and release date) are `.insufficient`, so
their code becomes `catalogIncomplete`. That is the intended outcome. The
report lists these codes so their art labels can be reviewed.

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

`e` (the physical editions from §3.3) feeds `catalogVariants`. Decision table:
WP2.8's gate runs first, then `VariantResolver`.

| Catalog editions | `printedEdition` | Lock | Outcome |
|---|---|---|---|
| 1 | `.absent` | any | `.uniqueInCatalog`, zero taps |
| 1 | `.observed(v)`, v in catalog | any | `.uniqueInCatalog`, zero taps |
| 1 | `.observed(v)`, v **not** in catalog | any | `.needsChoice([only])`: one confirming tap, never silent. The card and catalog disagree |
| 1 | `.unreadable` | any | `.uniqueInCatalog` only if that edition is not Unlimited. Otherwise one confirming tap |
| ≥ 2 | `.observed(v)`, v in catalog | any | `.resolved(.printedLabel)`, zero taps. Printed evidence beats the lock |
| ≥ 2 | `.observed(v)`, v not in catalog | any | `.needsChoice`, lock ignored |
| ≥ 2 | `.unreadable` | any | `.needsChoice`, lock ignored, all catalog options shown |
| ≥ 2 | `.absent` | set | The existing lock behavior (`.finishLock`) |
| ≥ 2 | `.absent` | none | The existing one-tap variant choice |

An Unlimited lock with `.absent` evidence is the one remaining way to save
Unlimited without a tap. That is the user's explicit choice, not an inference.

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

- Add `PrintedEditionEvidence` (§4.5) with a static
  `merged(_ values: [PrintedEditionEvidence]) -> PrintedEditionEvidence`.
  Drop `.absent`. If nothing remains → `.absent`. If every remaining value is
  the same `.observed(v)` → `.observed(v)`. If at least one `.observed(v)`
  remains and the rest are `.unreadable` → `.observed(v)`, because a clean
  read beats an illegible one. Two different `.observed` values → `.unreadable`.
  Only `.unreadable` → `.unreadable`. **A conflict never becomes `.absent`.**
- Add `let printedEdition: PrintedEditionEvidence` and an init parameter
  `printedEdition: PrintedEditionEvidence = .absent`. Leave `suppressionKey`,
  `displayIdentifier` and `matchesKnownSlabIdentity` unchanged.
- Adding the field changes the synthesized `==`/`hash`. Grep every
  `ScanSubject` equality use (`lhs == rhs` in `CandidateConfirmationWindow.matches`
  for slabs, latch refinement, `isCurrent`, duplicate-choice identity). Confirm
  that none of them now splits two frames of one card that differ only in edition
  evidence. Where one would, compare `identifier`/`slab` explicitly instead.
- In `mergedSubject`, compute
  `let edition = PrintedEditionEvidence.merged(observations.map(\.printedEdition))`.
  Apply it on **every** return path, including the Pokémon branches, which
  always carry `.absent`. Return `candidate` unchanged only when
  `candidate.printedEdition == edition`.
- In `CardScanner.swift`, the slab re-wrap at ~2271 and the latched-slab
  refinement at ~2500 build new subjects. Pass `printedEdition` through, even
  though YGO is raw-only today. Every `ScanSubject(` call that copies an
  existing subject must copy the field. Plain constructions from a fresh
  identifier keep the `.absent` default.

**WP2.8 `TradingCardScanner/Views/ScannerViewModel.swift`:**

1. ~line 4288, the `VariantResolver.resolve` call. Add a game-neutral gate in
   `Services/VariantResolver.swift`. Do not change `resolve` itself, so the
   Pokémon, Magic, Lorcana and One Piece paths stay byte-for-byte the same:

   ```swift
   extension VariantResolver {
       /// Applies printed edition-marker evidence before the catalog's unique
       /// tier. Returns nil when the evidence is absent, leaving the existing
       /// resolver untouched for every game that never produces it.
       static func gate(_ evidence: VariantEvidence, printedEdition: PrintedEditionEvidence) -> VariantOutcome?
   }
   ```

   Implement §5.2's table using `evidence.catalogVariants`. The single-edition
   contradiction rows return `.needsChoice(options: [only], lockDidNotApply: nil)`.
   Before relying on that, check that the existing variant-choice presentation
   renders with one option. If it does not, route those rows to the existing
   Needs attention path with reason `.noConfirmedMatch`. Do not auto-save.

   ```swift
   let printedEdition = request.subject.slab == nil ? request.subject.printedEdition : .absent
   let outcome = VariantResolver.gate(evidence, printedEdition: printedEdition)
       ?? VariantResolver.resolve(
           evidence,
           finishLock: request.subject.slab == nil ? finishLocks[card.game] : nil,
           printedFinish: request.subject.slab?.printedFinish)
   switch outcome {
   ```

   The gate returns nil only for `.absent`. Once any marker was seen, the lock
   is never consulted.

2. Add `private static func revalidatesBundledAcquisition(_ game: CardGame) -> Bool { game == .lorcana || game == .yuGiOh }`
   and use it in place of `== .lorcana` at ~3491, ~3544, ~5389 and ~5483.
   Re-locate these by grepping `game == .lorcana`; line numbers drift.

**WP2.9 `TradingCardScanner/Services/CollectionStore.swift:874`:** change
`identifier.game == .lorcana` to
`[CardGame.lorcana, .yuGiOh].contains(identifier.game)`.

**WP2.10 `scripts/audit_game_boundaries.sh`:** extend the game regex to
`\.(pokemon|magic|onePiece|lorcana|yuGiOh)`.

**WP2.11 Edition evidence survives retry, merge and recovery** (review R4):

1. `Views/ScannerViewModel.swift` `retryUnresolvedLookup` (~3671): pass
   `printedEdition: request.subject.printedEdition`.
2. `Views/ScannerViewModel.swift` `mergedSubject(_:_:)` (~1162), which merges
   unresolved records: use `PrintedEditionEvidence.merged([lhs.printedEdition, rhs.printedEdition])`
   on both return paths.
3. The other subject rebuilds at ~3624 (Pokémon historical choice), ~4535 (slab
   conversion) and ~6350 copy or replace a subject. Copy the field wherever an
   existing subject is the source.
4. `Services/UnresolvedScanStore.swift` `UnresolvedScanRecord`: add
   `let printedEdition: PrintedEditionEvidence?`. It is optional so records
   written by existing clients still decode, and `nil` decodes as `.absent`.
   Write it in `init(scan:)` and pass it to `ScanSubject` in `rehydrate`
   (~440). Encode `PrintedEditionEvidence` as a tagged object
   (`{"kind": "observed", "variant": "<id>"}`) whose variant ID round-trips
   through `PhysicalVariant.known`. An unknown variant ID decodes as
   `.unreadable`, never `.absent`.
5. Any other place that copies an `UnresolvedScan` subject (grep
   `subject:` in `UnresolvedScan` updating helpers) copies the field.

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
        let editions: [YuGiOhEdition]        // physical (seed `e`)
        let pricedEditions: [YuGiOhEdition]  // priced lanes (seed `pe`), ⊆ editions
        let thumbnailURL: URL?; let imageURL: URL?
        var idString: String { id.uuidString.lowercased() }
    }
    enum LoadError: Error { case missingResource, invalidSchema, invalidRow(String) }

    let generation: String
    let capturedAt: Date
    let printingsByCode: [String: [Printing]]   // seed order
    let printingByID: [UUID: Printing]
    let incompleteCodes: Set<String>
    let autoEligibleCodes: Set<String>
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
- `e` and `pe` non-empty, all known editions, and `pe ⊆ e`;
- `incompleteCodes ∩ autoEligibleCodes` empty;
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
  code's family. `automatic` requires family count == 1, the code in
  `autoEligibleCodes` and not in `incompleteCodes`. Manual requires selection
  evidence that is not `.insufficient`.
- `candidate(_:)` sets `artworkID: nil` (§5.1).
- `validateVariantCorrection(printingID:variantID:)`: the variant must be in the
  printing's physical `editions` (not only `pricedEditions`).
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
  over every printing × priced edition.
- `refresh`:
  - the identity must match the current resolution and `request.variant` must
    be one of the printing's editions, else `identityMismatch`;
  - an edition in `editions` but not in `pricedEditions` → `.unavailable(.tcgCSV)`,
    with no network call;
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
   - No printing has empty editions, and `pricedEditions ⊆ editions` for all.
   - Malformed seeds are rejected: duplicate ID, empty `e`, `pe ⊄ e`, unknown
     edition, a code both incomplete and auto-eligible, wrong schema version.
   - Builder fixtures (run the Python builder against small committed fixture
     JSON under `scripts/fixtures/yugioh/`, offline):
     - a code where YGOPRODeck lists two same-rarity `(set, rarity)` entries but
       TCGplayer has one product → `printingShortfall`, incomplete;
     - a code with one kept product and one product skipped for
       `unknownSubtype` → `skippedProduct`, incomplete;
     - a renamed card (PSV-EN049 *Harpie's Brother* / *Sky Scout* shape) joins
       through `beta_name` or the alias file, is complete, and shares one
       `cardID` with its current-name reprint;
     - a single-printing code whose card has two `card_images` → complete but not
       `autoEligible`;
     - a product priced only in `1st Edition` in a group that also prices
       `Unlimited` → `e = [1st, Unlimited]`, `pe = [1st]`.
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
   - `"1t Edition"` in the footer → `.observed(.yugiohFirstEdition)`;
   - `"T Edition"` in the band's left side → `.observed(.yugiohFirstEdition)`;
   - `"LIMITED EDITION"` and `"IMITED EDITION"` → `.observed(.yugiohLimited)`;
   - a bare `"EDITION"`, `"D EDITION"` and `"TED EDITION"` → `.unreadable`
     (**never** `.first`);
   - 1st and Limited in one frame → `.unreadable`;
   - none → `.absent`.

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
   - `validateAcquisition(automatic: true)` throws for a complete single-printing
     code that is not `autoEligible`, and `lookup` returns a one-candidate
     `.needsPrintingChoice` for it.
   - Two products with identical labels → `.catalogIncomplete`, even though
     their product IDs and thumbnails differ (`artworkID` is nil).
   - Every row of §5.2's table, through `VariantResolver.gate` then `resolve`,
     including:
     - `[.first, .unlimited]` + `.unreadable` + an **Unlimited lock** →
       `.needsChoice`, never `.finishLock`;
     - `[.first, .unlimited]` + `.observed(.limited)` + an Unlimited lock →
       `.needsChoice`;
     - singleton `[.first]` + `.observed(.limited)` → `.needsChoice([.first])`,
       never `.uniqueInCatalog`;
     - singleton `[.unlimited]` + `.unreadable` → not resolved silently;
     - `.absent` → the gate returns nil, and the existing lock behavior is
       unchanged.
   - The gate returns nil for every existing game's evidence fixture, so the
     Pokémon/Magic/Lorcana/One Piece resolver tests run unchanged.
   - `CandidateConfirmationWindow`: `[.absent, .observed(.first)]` →
     `.observed(.first)`; `[.observed(.first), .observed(.limited)]` →
     `.unreadable` (not `.absent`); `[.unreadable, .observed(.first)]` →
     `.observed(.first)`. The suppression key is unchanged in every case.
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
7. **`YuGiOhRecoveryTests.swift`** (review R4)
   - `retryUnresolvedLookup` re-enqueues a subject that keeps
     `.observed(.yugiohFirstEdition)`.
   - Merging two unresolved records, one `.absent` and one `.observed(.first)`,
     keeps `.observed(.first)`. Merging `.observed(.first)` with
     `.observed(.limited)` gives `.unreadable`.
   - `UnresolvedScanRecord` round-trip: encode then rehydrate keeps all three
     evidence cases. A record JSON written without the key decodes as `.absent`.
     An unknown variant ID decodes as `.unreadable`.
   - After rehydration with `.observed(.first)` and an active Unlimited lock, the
     resolved variant is 1st Edition.
8. **Update existing tests**
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
| OCR reads only `EDITION` (e.g. `LIMITED` dropped) | `.unreadable`: never 1st Edition, lock ignored, ask |
| 1st and Limited both read, in one frame or across the window | `.unreadable`: lock ignored, ask. Never collapses to "no evidence" |
| Printed edition absent from a single-edition catalog entry | One confirming tap (or Needs attention). Never `.uniqueInCatalog` |
| Edition evidence then a retry, unresolved merge or app relaunch | Evidence preserved. A contrary lock cannot override it after recovery |
| A same-rarity reprint or a product the builder skipped | Code incomplete. No automatic add |
| A price row missing for an edition that exists in the set | Edition still offered. Price `.unavailable`, never borrowed from another lane |
| Two products with identical labels | `catalogIncomplete`. Product IDs are not visual evidence |
| Renamed card (PSV-EN049) | Joined through an alias; one canonical card ID |
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
- [ ] No files changed outside §6's list (check `git status`). §6 now includes
      `Services/VariantResolver.swift` (gate only), `Services/UnresolvedScanStore.swift`,
      the `ScanSubject` copy sites in `CardScanner.swift`/`ScannerViewModel.swift`
      (WP2.7, WP2.11), and the builder fixtures and alias file.
- [ ] `git diff` of `VariantResolver.resolve` itself is empty.
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
     -only-testing:TradingCardScannerTests/YuGiOhImportTests \
     -only-testing:TradingCardScannerTests/YuGiOhRecoveryTests
   ```

   Also run the builder fixtures offline:
   `python3 -I scripts/build_yugioh_catalog.py --self-test`.

3. Fix any failures, then run the regression neighbors once:
   `CardGameForwardCompatibilityTests`, `ScanParserTests`, `ScannerViewModelTests`,
   `CardLatchTests`, `LorcanaIntegrationTests`, `LorcanaPricingTests`,
   `OnePieceIntegrationTests`, `PricingTests`, `CSVImportResumeTests`,
   `CollectionKeyTests`.
4. Run one end-to-end chain with stubbed providers (a `ScannerViewModelTests`
   style test, or a UI test if one exists for Lorcana): a scan of a
   multi-rarity, multi-edition code → rarity choice → edition (from
   `.observed` evidence, then again by tap) → save → price refresh → CSV
   export → import into a fresh store → relaunch (rebuild the container from
   disk). The collection key, edition and price key must be identical at
   every step. Isolated adapter tests do not establish this chain.
5. Run the full suite only if step 3 touched shared behavior unexpectedly.
   Report pass, fail and skip counts against the documented pre-existing
   failures (`docs/AGENTS.md`).
6. Record the results in `progress.md` and this plan's status line. Make no
   device or release claims.

---

## 10. Owner gates (not closable by the implementing agent)

1. **Rights.** Approve TCGCSV/TCGplayer data and CDN image display, YGOPRODeck
   data use, and the Konami names/marks for App Store distribution.
2. **Device camera calibration.** On an iPhone, measure the band on at least 20
   cards: modern, LOB-era, Pendulum, Link, RA05 extended art, sleeved, glare,
   and at least 3 **Limited Edition** cards (no Limited misreads were measured
   for §4.5). Adjust `YuGiOhRecognitionAdapter.underArtRegion` only. Compare the
   `supplementalOCR` signpost cost to `footerOCR`. The target is under 15 ms
   median added on YGO frames and none on other games. Keep reproducible
   evidence: the redacted input crops plus the raw Vision lines and boxes as JSON,
   off-repo on the external SSD, with a redacted summary in the research
   folder. Narrative measurements alone do not close this gate. The five
   desk-measured TCGplayer scans in §1.2 make the band plausible; they do not
   validate it.
3. **Throughput regression.** Scan a 20-card stack each of Pokémon, Magic,
   Lorcana and One Piece, and confirm the YGO band never fires (signpost count 0).
4. **Wrong-printing safety.** In a 100-card YGO sample there must be zero wrong
   automatic adds and zero wrong automatic editions. Rarity choices must appear
   for multi-rarity codes. Record how often the `autoEligible` rule (§3.4) and
   `.unreadable` evidence (§4.5) forced a tap. That number is the input for any
   later relaxation.
5. **Catalog refresh cadence.** Re-run the builder for new sets. Each refresh is
   an app update until signed remote updates are scheduled.
