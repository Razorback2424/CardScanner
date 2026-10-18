# Lorcana representative real-card corpus — research package

**Research date:** 2026-10-12  
**Authority:** Public publisher and specialist collector/card-catalog references; **not** a signed Lorcana release.  
**Coverage:** 29 source-documented card / physical-form *candidates* in 35 source references, with explicitly unaccepted finishes, physical identities and images.  
**Status:** **Source selection complete; real physical-corpus acceptance OPEN.** No app-owned physical UUIDs, real-specimen images, finish measurements, content-authorized schema-2 records or production enablement were created.

This package is a working set of *real, named Lorcana products and printings* for validating the project's schema-2 physical-printing contract, rather than a synthetic roster of invented cards. The sources establish that the cards or editions exist; **they do not substitute for inspecting physical specimens, verifying every claimed exact printing, or closing the universe of printings sharing the same footer.**

## Package contents

- `lorcana_real_card_corpus.json`: 29 source-documented reference records. Source URLs and specific claims are embedded for each. All records have `physical_uuid: null`, `eligible_finish_ids: null`, `activation_permitted: false`.
- `acceptance_scenarios.json`: 23 deterministic candidate-level and end-to-end acceptance checks, *specified but not executed*.
- `physical_review_evidence_template.json`: one blank evidence packet for collecting front/back, exact footer, physical size, finish, provenance and two independent reviewer approvals.
- `validate_corpus.py`: offline structural and safety validation. This asserts source traceability and that unreviewed candidates cannot accidentally look like an activation manifest.
- `README.md`: expected outcomes, acquisition/capture order, stop/go rules and identified gaps.

This is **separate from** the local `lorcana-source-corpus.md` checkpoint; no access to its raw capture receipts or the uncommitted checkout was available here, and no provider aliases were joined.

## The capture set: what to examine first

The initial specimen target is approximately **20 actual instances/photos**, organized into **13 reviews** below. Several can be collected from a single gift set or starter/Quest product; a permissioned first-hand image from a collector can substitute for buying an expensive reference card for **catalog research**, but it does **not** establish device-camera/foil/physical-scale performance.

| Tier | Real cards / observed footer | Required physical distinction | Expected catalog behavior *after* reviewed local seed activation |
|---|---|---|---|
| **A** | Hades – King of Olympus, `5/204 · EN · 1`: ordinary nonfoil, ordinary foil, Gift Set oversized foil | **Same footer**, normal vs oversized, then exact finish | `needsPrintingChoice` when size cannot be determined. Resolve selected standard/oversized UUID and then ask only for eligible finishes. Never silently choose normal size. |
| **A** | Mulan – Imperial Soldier, `118/204 · EN · 1`: playable foil + oversized Gift Set foil | Second independent same-footer/size family | The same ambiguity and labels as Hades; prove this is not a Hades-specific exception. |
| **A** | Stitch – Rock Star, `23/204 · EN · 1` versus `3/204 · EN · 9` | Gameplay reprint across The First Chapter / Fabled | Different physical UUIDs and ownership keys, even when gameplay completion groups them as the same card. |
| **A** | Elsa – Spirit of Winter, `42/204 · EN · 1` vs Enchanted `207/204 · EN · 1` | Ordinary vs new artwork/premium numerator | Two physical identities; never model Enchanted as a finish of `42/204`. An expensive Enchanted need not be purchased if permitted specimen evidence is available. |
| **A** | Dalmatian Puppy – Tail Wagger, `4a/204`, `4b/204` (expand to c–e), all `EN · 3` | Lettered numerators and distinct artworks | Literal `4a` ≠ `4b`; explicit separate artwork physical UUIDs. If current OCR parser cannot accept lettered numerators, remain recoverably incomplete until a measured extension. |
| **A** | Motunui – Island Paradise, `170/204 · EN · 3` | Landscape Location, ordinary finish pair | Real orientation/ROI test; finish never inferred from market data. |
| **A** | Ursula's Contract, `30/31 · EN · Q1` | Literal `Q1` set marker, 31-card denominator, gold-backed scenario deck | Recognize exact token if supported; preserve nonstandard raw kind/back; **hold collection writes** pending item-kind contract and physical review. |
| **A** | Mickey Mouse – Playful Sorcerer, `187/204 · EN · 4` and special `225/204 · EN · 4` | Deep Trouble decorated frame, premium numerator **not Enchanted** | Separate UUIDs; no inference that numerator above denominator always indicates Enchanted rarity. |
| **A** | Vine Entrance – Ominous Passageway, `207/207 · EN · 13` | New denominator 207 and landscape Location | Literal denominator/marker; accepts numerator equal to denominator. |
| **B** | Cinderella – Stouthearted, `177/204 · EN · 2` + `177/204 · FR · 2` | Language changes physical identity | Separate UUIDs, OCR never defaults unknown language to English. |
| **B — HOLD** | Cinderella – Stouthearted Challenge, `3/C1 · EN · 2`, nonfoil/foil | Two documented finish/distribution channels; token `C1` | Keep finish/physical UUID decision in review. Different event prize channel does not by itself prove extra artwork/stamp. No implicit foil or extra UUID. |
| **B — HOLD** | 2022 D23 promos: Mickey `1TFC · EN · 1/P1`, Stitch `1TFC · EN · 2/P1` | Older *reversed* footer and D23/“1st” stamps | Do not rewrite into a normal `number/denominator EN marker` footer. Held until recognized by a measured, explicitly supported alternate grammar; preserve recovery evidence. |
| **B — HOLD** | Oversized Ursula – Ruler of Lorcana, **unnumbered** | No footer, oversized scenario object | Never manufacture a footer or force into the ordinary card type. May only be resolved by separate exact UUID/physical selection after support and review. |

*“A” means sample first, **not authorized for immediate writes**. The 2022 D23 promos, Elsa Enchanted and Challenge foil are costly/rare; use authorized collector/retailer reference images rather than purchasing only for test coverage. Collecting their photos does not grant image redistribution rights.*

### Sources demonstrating the high-value boundaries

- [Ravensburger — The First Chapter Gift Set](https://www.disneylorcana.com/en-US/product): both playable foils and oversized foils for Hades and Mulan. For Hades' literal `5/204` claim see [Hades – King of Olympus card reference](https://lorcanaplayer.com/card/hades-king-of-olympus/) and [oversized catalog entry](https://www.ebay.com/p/3072738661).
- [Ravensburger — Fabled release notes](https://www.disneylorcana.com/en-US/news/2025/08/2025-8-release-notes-fabled): Stitch cross-set reprint; gameplay identity is preserved, despite different collector printing.
- [Ravensburger — Elsa Enchanted](https://cards.disneylorcana.com/en-US/?cardId=207) and [Enchanted reveal](https://www.disneylorcana.com/en-US/news/enchanted-reveal): premium alternate artwork and higher-than-denominator numbering. These are **not** finish aliases of the ordinary version.
- [Lorcana Player — Into the Inklands setlist](https://lorcanaplayer.com/lorcana-card-list/), [the five Dalmatian arts](https://lorcanaplayer.com/card/dalmatian-puppy-tail-wagger-a/) and [finish catalog](https://inkdecks.com/cards/details-dalmatian-puppy-tail-wagger): exact `4a` through `4e` numbering and distinct drawings.
- [Ravensburger — Deep Trouble](https://www.disneylorcana.com/en-US/product/deep-trouble), [official Ursula's Contract record](https://cards.disneylorcana.com/en-US/?cardId=943), [special Mickey frame](https://lorcanaplayer.com/card/mickey-mouse-playful-sorcerer-deep-trouble/).
- [Ravensburger official Vine Entrance record](https://cards.disneylorcana.com/en-US/?cardId=3178): real `207/207 · EN · 13` landscape Location.
- [Lorcana Player — 2022 D23 promo printing](https://lorcanaplayer.com/set/promo-set-1/) and [2022 stamped finish background](https://lorcanaplayer.com/set/d23-expo/).
- [Lorcana Player — Cinderella Challenge promo](https://lorcanaplayer.com/card/cinderella-stouthearted-challenge-promo/), [foil counterpart](https://lorcanaplayer.com/card/cinderella-stouthearted-challenge-promo-foil/), [French printings](https://www.lorcards.fr/cards/ascension-des-floodborn-177-204-cendrillon-coeur-vaillant).

**A documented discrepancy to retain:** Official Ravensburger gallery currently describes Cinderella's D23 printing as `2/D23 · EN · 2`, while collector catalogues list `02/D23 · EN · 2`. Our record `LRC-017` includes both claims and remains **held** until the *printed physical* form is examined. Do not normalize/remove leading zero on a guess. See [official gallery](https://cards.disneylorcana.com/en-US/?cardId=1192) and [collector record](https://lorcanaplayer.com/card/cinderella-stouthearted-d23-collection/).

## Evidence collection — no imaginary authority

Create **one evidence packet per real card specimen** (finish A and finish B require separate packets). Store the actual photos privately and point to them by path and SHA-256 digest rather than embedding external card imagery in a redistributed catalog.

1. **Origin and rights.** Date observed, product source or collector, region/language, loan/owned/permissioned-photo provenance and permitted retention/use. For screenshots or listings, note that they are secondary evidence; do not label them as card-in-hand photos.
2. **Card front/back.** Uncropped front and back at adequate resolution; add a physical ruler/reference in frame if the size distinction matters. For Q1 record the gold back; for oversized compare against standard in the *same* scale frame if possible.
3. **Footer and distinctive artwork.** Straight-on macro showing literal `numerator/denominator`, language, marker, spaces and separators; for 2022 D23 explicitly photograph left/right bottom sequence and `1st`/D23 marks; close-up artwork/stamp/frame differences.
4. **Finish inspection.** Shoot normal and foil under neutral and angled lighting with multiple orientations. Do not infer a finish from prices, rarity, artist, or reflective screen images.
5. **Actual scanner observation.** Record an unaltered device ROI/photo and OCR output, lighting/orientation and whether multiple footer fragments appear on separate lines. This item may stay `pending` for the later real-device camera gate; synthetic text is **not** a device-capture pass.
6. **Physical review.** Two independent reviewers separately mark `confirmed`, `contradicted` or `pending` for number, layout, size, artwork, distribution/stamp and permitted finish. A reviewer signs the *exact evidence hashes and scope*, not a generic game/version.

The `physical_review_evidence_template.json` enforces the distinction among **published claim**, **physical observation**, **reviewed physical printing** and **signed activated record**. Keep source body/receipt hashes from the separate Lorcast ingestion archive linked rather than copying reconstructed provider IDs into these records.

## How to translate accepted specimens into the local Lorcana contract

**Do not feed this raw JSON into `LorcanaCatalogRegistry` as a schema-2 reviewed manifest.** These are *source-backed research candidates*; their temporary `LRC-...` labels are neither UUIDs nor collector ownership keys.

For an accepted exact printing, the promotion step must:

1. Produce an explicit reviewer-approved `footerMappingReference` based on literal verified footer and preserve the **provider set code separately**. Do not conflate `3/C1`, `Q1`, `13`, `D23`, `1TFC`, Lorcast provider codes or language.
2. Document the **complete candidate universe for the explicitly supported footer scope**. If Hades `5/204 · EN · 1` includes both standard and jumbo, both must appear and be distinguishable. If evidence is incomplete, return `catalogIncomplete` rather than an invented singleton or a silently favored candidate.
3. Establish canonical gameplay relationships without merging distinct physical printings: same gameplay Stitch across sets; Cinderella across EN/FR; five alternate Dalmatian artworks; Enchanted and Quest frame printings. Allocate **app-owned, permanently stable physical UUIDs** only after review. A publisher image URL, source alias, case ID or gameplay ID must never become that UUID.
4. Review exact printing's **eligible finishes** from physical samples and permitted sources, with corrections tested against that printing. Different *physical* artwork, stamped identity or size normally have different UUIDs; **finish** changes ordinarily remain beneath an exact printing. Cinderella `3/C1` must not be split into new UUIDs merely because event channels differed *unless* its verified physical/stamp/distribution identity contract establishes the split.
5. Produce a new reviewed manifest with evidence references and protected transition history, then use the **existing explicit isolated `LorcanaLocalReviewKit` signed seed**. Activate through `CardGameRuntimeContainer.bound(to:isCurrent:)` so catalog, recognition, variants, Browse, import and collection guard share a generation. Do not add central game switches or make global storage changes.
6. Only set `.collectionWrite` inside the isolated debug review kit after verified local seed + end-to-end authority tests. Do **not** register production `appDefaults` or enable CloudKit/shared sync, pricing or sealed/graded functionality.

### Expected behaviors during evaluation

- **Ambiguous footer:** A real Hades or Mulan footer is insufficient to determine standard vs oversized. Use printing choice + finish choice, or incomplete if distinct options cannot be meaningfully compared. A singleton oversized *still* requires size confirmation.
- **Unavailable evidence:** The existing generic unresolved scan/retry must retain the original literal footer, encounter identity and unknown-game/finish row; don't merge or delete independent scans of two copies.
- **Unrecognized printed syntax:** `4a` and 2022 `1TFC · EN · 1/P1` must be distinguished: the former is a lettered collector numerator within the ordinary three-component order; the latter has a different order altogether. If the current recognizer cannot parse either, it must fail closed with retained raw evidence. Do not transform them to the nearest known numeric row.
- **Wrong/unreviewed finish:** Save/correction/import must refuse without changing quantity, collection history or a prior valid record. Provider normal/foil price fields do not establish finish authority.
- **Catalog revision:** Old choice tokens, stale in-flight lookups and import adapters must not save against new semantics; explicit recovery retry can rebase the literal footer but must re-ask for printing when evidence changes.
- **Scope:** Browse completion counts reviewed physical printings, not the theoretical entire set; gameplay completion is distinct. CSV requires the **exact reviewed physical UUID** and current known finish; a source alias can enrich only when exact UUID accompanies it.

## Stop/go: when can Slice 2 physical corpus be checked off?

**Minimum first real-seed subset:** Physical evidence + two approvals for Hades normal/oversized pair; Stitch across sets; one ordinary normal/foil pair; one ordinary Location; premium numerator Elsa **or another equally discriminating permitted Enchanted pair**; and a non-204-denominator card (such as `207/207`). Add Q1, D23, C1 and all 4a–4e cases as *held evidence* unless their exact physical grammar/identity/finishes are reviewed. The held classes must prove **safe incompleteness**, not a false resolution.

**Go** only if each included reviewed printing has literal footer photos, evidenced physical identity and complete scoped candidate universe, reviewed finish, valid stable UUID, valid manifest transition, negative/ambiguity tests, and replayable raw source receipts. Run `acceptance_scenarios.json` against isolated storage and retain simulator artifacts. Separately measure signed activation time/memory and visually examine scanner/choice/save/Browse/CSV flows; those are still *open* until executed.

**No-go** if a printed suffix cannot be distinguished, if size is guessed, if a source family/provider ID is substituted for a physical UUID, if reviewer signoff/rights are missing, if a finish is inferred from price or rarity, if active catalog authority is bypassed, or if a stamped/Quest/oversized item kind is forced into generic collection ownership without contract review.

## Explicitly not covered yet

The corpus is **representative, not complete**. No claim is made about all releases, all language printings, all promos/distribution paths, prize cards, event stamps, Errata, later Quest expansions, Epic/Iconic specialties, serialized/special card types, puzzles, sealed products, graded cards or complete artwork/finish universes. The published Lorcast set list cannot establish this completeness; all-print cards/search may change pagination semantics ([Lorcast docs](https://lorcast.com/docs/api/cards)). Optical foil recognition, live camera accuracy, accessibility and device performance, rights to redistribute illustrations, signed production keys/hosting, pricing joins, CloudKit mixed-client enforcement and release acceptance also remain separate gates.

## Index of all source-documented candidates

The footer shown here is a **published claim** until a corresponding physical specimen macro is retained. A blank footer is intentional for the unnumbered oversized Ursula object. Every entry in the companion JSON contains its evidence references and individual acceptance tags.

| ID | Name | Published footer | Distinction | Review status | Supporting source |
|---|---|---|---|---|---|
| LRC-001 | Hades – King of Olympus | `5/204 · EN · 1` | The First Chapter standard artwork/standard card | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/product) |
| LRC-002 | Hades – King of Olympus | `5/204 · EN · 1` | The First Chapter Gift Set oversized artwork matched to standard card | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/product) |
| LRC-003 | Mulan – Imperial Soldier | `118/204 · EN · 1` | The First Chapter standard-size physical card | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/product) |
| LRC-004 | Mulan – Imperial Soldier | `118/204 · EN · 1` | The First Chapter Gift Set jumbo | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/product) |
| LRC-005 | Elsa – Spirit of Winter | `42/204 · EN · 1` | The First Chapter ordinary illustration | `source_documented_physical_unreviewed` | [Source](https://inkdecks.com/cards/details-elsa-spirit-of-winter) |
| LRC-006 | Elsa – Spirit of Winter | `207/204 · EN · 1` | The First Chapter Enchanted different illustration | `source_documented_physical_unreviewed` | [Source](https://cards.disneylorcana.com/en-US/?cardId=207) |
| LRC-007 | Stitch – Rock Star | `23/204 · EN · 1` | The First Chapter normal illustration | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/news/2025/08/2025-8-release-notes-fabled) |
| LRC-008 | Stitch – Rock Star | `3/204 · EN · 9` | Fabled reprint of The First Chapter artwork | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/news/2025/08/2025-8-release-notes-fabled) |
| LRC-009 | Stitch – Rock Star | `1TFC · EN · 2/P1` | D23 2022 Collector Set promotional artwork with event/first marks | `held_unsupported_footer_layout` | [Source](https://wiki.mushureport.com/wiki/Stitch_-_Rock_Star) |
| LRC-010 | Mickey Mouse – Brave Little Tailor | `115/204 · EN · 1` | The First Chapter ordinary illustration | `source_documented_physical_unreviewed` | [Source](https://lorcanaplayer.com/card/mickey-mouse-brave-little-tailor-d23-expo/) |
| LRC-011 | Mickey Mouse – Brave Little Tailor | `1TFC · EN · 1/P1` | D23 2022 first-edition stamped promo | `held_unsupported_footer_layout` | [Source](https://lorcanaplayer.com/card/mickey-mouse-brave-little-tailor-d23-expo/) |
| LRC-012 | Motunui – Island Paradise | `170/204 · EN · 3` | Into the Inklands horizontal Location | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Into_the_Inklands_Card_List) |
| LRC-013a | Dalmatian Puppy – Tail Wagger | `4a/204 · EN · 3` | Into the Inklands illustration a (one of five distinct arts) | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger) |
| LRC-013b | Dalmatian Puppy – Tail Wagger | `4b/204 · EN · 3` | Into the Inklands illustration b (one of five distinct arts) | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger) |
| LRC-013c | Dalmatian Puppy – Tail Wagger | `4c/204 · EN · 3` | Into the Inklands illustration c (one of five distinct arts) | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger) |
| LRC-013d | Dalmatian Puppy – Tail Wagger | `4d/204 · EN · 3` | Into the Inklands illustration d (one of five distinct arts) | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger) |
| LRC-013e | Dalmatian Puppy – Tail Wagger | `4e/204 · EN · 3` | Into the Inklands illustration e (one of five distinct arts) | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger) |
| LRC-014 | Cinderella – Stouthearted | `177/204 · EN · 2` | Rise of the Floodborn ordinary English printing | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Cinderella_-_Stouthearted) |
| LRC-015 | Cendrillon – Cœur vaillant | `177/204 · FR · 2` | Rise of the Floodborn ordinary French printing, same gameplay identity | `source_documented_physical_unreviewed` | [Source](https://www.lorcards.fr/cards/ascension-des-floodborn-177-204-cendrillon-coeur-vaillant) |
| LRC-016 | Cinderella – Stouthearted | `3/C1 · EN · 2` | Challenge Set 1 promo artwork; nonfoil and foil distributed by different event channels | `held_requires_distribution_identity_policy` | [Source](https://wiki.mushureport.com/wiki/Cinderella_-_Stouthearted) |
| LRC-017 | Cinderella – Stouthearted | `02/D23 · EN · 2` | D23 Expo 2024 promo with special event edition/mark | `held_printed_footer_lexeme_conflict` | [Source](https://wiki.mushureport.com/wiki/Cinderella_-_Stouthearted) |
| LRC-018 | Ursula's Contract | `30/31 · EN · Q1` | Deep Trouble gold-backed scenario card | `held_scenario_itemkind_authority` | [Source](https://www.disneylorcana.com/en-US/product/deep-trouble) |
| LRC-019 | Mickey Mouse – Playful Sorcerer | `187/204 · EN · 4` | Ursula's Return ordinary printing | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Mickey_Mouse_-_Playful_Sorcerer) |
| LRC-020 | Mickey Mouse – Playful Sorcerer | `225/204 · EN · 4` | Deep Trouble deck exclusive inky frame; not Enchanted | `source_documented_physical_unreviewed` | [Source](https://www.disneylorcana.com/en-US/product/deep-trouble) |
| LRC-021 | Yen Sid – Powerful Sorcerer | `59/204 · EN · 4` | Ursula's Return ordinary printing | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Illumineer%27s_Quest_-_Deep_Trouble) |
| LRC-022 | Yen Sid – Powerful Sorcerer | `223/204 · EN · 4` | Deep Trouble decorated inky border foil | `source_documented_physical_unreviewed` | [Source](https://wiki.mushureport.com/wiki/Illumineer%27s_Quest_-_Deep_Trouble) |
| LRC-023 | Ursula – Ruler of Lorcana | `—` | Unnumbered oversized boss/representational card from Deep Trouble | `held_unnumbered_no_footer` | [Source](https://www.disneylorcana.com/en-US/product/deep-trouble) |
| LRC-024 | The Vine – Towering Stalk | `197/207 · EN · 13` | Attack of the Vine! normal character | `source_documented_physical_unreviewed` | [Source](https://cards.disneylorcana.com/en-US/?cardId=3168) |
| LRC-025 | Vine Entrance – Ominous Passageway | `207/207 · EN · 13` | Attack of the Vine! landscape Location | `source_documented_physical_unreviewed` | [Source](https://cards.disneylorcana.com/en-US/?cardId=3178) |
