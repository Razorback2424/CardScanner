# Card coverage gaps and research priorities

**Reviewed:** 2026-10-05
**Candidate:** `f40e704` plus existing local changes.
**Status:** research backlog based on source, bundled data and recorded evidence; not an exhaustive upstream inventory or device acceptance report.

## Finding and proposed scope

We cannot substantiate support for every reasonable Magic, Pokémon and One Piece card. Some exclusions are explicit, some physical printings remain unresolved, and other coverage has not been measured against an independent inventory.

For the first completeness milestone, use **released English physical singles, including ordinary expansions, starters, promos, alternate arts and marketed finishes**. This is a proposed research baseline, not a new product decision. Track tokens, art cards, DON!!, stamped/event/prize cards, serial-numbered editions and other languages separately. Do not quietly exclude widely collected cards merely because they are difficult to identify. Digital-only cards, sealed products, unofficial cards and manufacturing errors need separate scope decisions.

Measure five capabilities independently: catalog identity, camera recognition, exact physical variant selection, Browse/import/collection round-trip, and pricing. A missing quote does not make a card nonexistent; a canonical number does not prove every printing is represented. Manual selection is acceptable when visual evidence cannot distinguish printings, provided the catalog presents all verified possibilities and does not guess.

## Confirmed boundaries and research backlog

Priority **P0** protects correct identity and establishes a measurable denominator. **P1** closes substantial collectible-card gaps and operational uncertainty. **P2** expands explicitly separate scope.

### Magic

| ID / priority | Evidence and present boundary | Research needed | Closure criterion |
| --- | --- | --- | --- |
| M1 / P1 | Ordinary scanner vocabulary and lookup use a `2014-07-18` cutoff. Original older printings are excluded by the ordinary path, even if Scryfall catalogs them. | Inventory pre-cutoff English printings; classify printed collector numbers, set symbols, names and other usable evidence. Prototype historical identification with explicit ambiguity handling. Do not merely remove the cutoff: the existing parser expects modern footer evidence. | Each included older printing has a catalog path and tested recognition or manual recovery path; ambiguous historical printings cannot be auto-selected. |
| M2 / P1 | Ordinary lookup denies vanguard, scheme, planar, augment and host layouts. Token/emblem/art-series layouts also fail ordinary lookup, but token and art-card adapters already exist. | Enumerate each collectible excluded layout and test its appropriate recognition route. Audit token/art parent-to-child routing, particularly multiple child sets and regional promos; the existing preferred-child rule is not proof of exhaustive coverage. | Every scoped layout and child printing has a tested route or an explicit documented exclusion. Existing token/art support remains working. |
| M3 / P0 | Ordinary set discovery accepts only non-digital sets released after the cutoff with alphanumeric codes of 3–4 characters. | Diff a dated physical Scryfall inventory against the exact app filter; distinguish intended digital exclusions from physical cards accidentally excluded by code, date, set type or metadata. | A per-printing exclusion list has reviewed reasons; every unintended filter miss has a regression case and working resolution. |
| M4 / P1 | Production treatment evidence is a compact reviewed projection plus live signals; manual enrichment covers distinctions such as NEO Neon Ink color. The full treatment snapshot is test-only. | Audit alternate-art, etched/other foil, serialized, stamped and treatment-color identities against actual product evidence. Identify cases where one provider record represents multiple physical objects. | Each supported treatment has exact identity and finish rules, or an explicit uncertain choice; supplemental mappings have source provenance and an update procedure. |
| M5 / P1 | Compiled vocabulary supports startup/offline recognition, while ordinary catalog lookup still uses Scryfall. Vocabulary availability alone does not establish first-launch offline card resolution. Magic signed rollout is recorded as `legacy-live`. | Test empty-cache offline, warmed-cache offline, provider outage and newly released sets. Review signed rollout status in its existing runbook rather than assuming a planned mode is active. | Document actual offline guarantees and release-discovery latency; verify recovery and last-known-good behavior on device. |

Source anchors: [Scryfall service and filters](../../TradingCardScanner/Services/TCGdexService.swift), [Magic adapter and child routing](../../TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift), [treatment catalog](../../TradingCardScanner/Services/MagicTreatmentCatalog.swift), [Magic publication runbook](../plans/magic_catalog_key_handling_runbook.md), [product README](../../README.md).

### Pokémon

| ID / priority | Evidence and present boundary | Research needed | Closure criterion |
| --- | --- | --- | --- |
| P1 / P0 | The bundled checklist is dated `2026-09-15T23:26:30Z`, with 157 entries representing 146 distinct provider set IDs. Those totals are not a denominator for all released cards, and downloaded overlays can change installed coverage. | Enumerate a dated English physical inventory, compare exact collector identities against bundled and active signed inventories, and separately reconcile promos, subsets and print runs. Do not compare set totals alone. | Every expected card has a matching identity or a documented discrepancy; bundled and active-release coverage are reported separately. |
| P2 / P0 | Eight manifest entries have `set.cardCount` below `standardSlotCount`; their referenced payloads nevertheless contain at least the recorded standard number of rows. These are metadata discrepancies, not demonstrated missing-card counts. | Determine whether `cardCount` records sparse provider summaries, stale metadata or a count with different semantics. Verify unique card numbers and physical slots separately, including secret cards and multiple variants. Fix misleading metadata at its producer if confirmed. | Count semantics are explicit; payload completeness is checked by identities/slots rather than this metadata field; set totals presented to users are accurate. |
| P3 / P0 | README explicitly leaves physical validation open for Poké Ball/Master Ball parallel rules in `sv08.5`, `sv10.5b` and `sv10.5w`. | Build a per-card eligibility matrix from official product/checklist evidence and physical samples, including card types that cannot receive these parallels. Compare live provider flags and offline-expanded variants. | Every generated parallel slot is physically possible; omissions and false positives have fixtures, and uncertainty never fabricates a finish. |
| P4 / P1 | Historical and modern lookup engines exist; their presence does not certify every promo, stamp, edition or reprint. | Reconcile first edition/shadowless/unlimited, corrected/revised cards, event/prerelease/promotional stamps, alternate distributions and collector-number collisions. Exercise name/number/set evidence and the print-run chooser. | Distinct scoped physical objects remain distinct through scan, Browse, import/export and collection; unresolved print-run evidence requires a choice. |
| P5 / P1 | The pricing plan records a two-set TCGCSV fallback for `30th` and `30th-c`; a general bulk-provider replacement remains unresolved. | Measure exact USD quote availability per finish across all sets and providers, including newly released sets and promos. Separate unsupported identity, missing quote, credentials, rate limits and outage. | Publish a finish-specific pricing coverage ledger; supported provider fallbacks use reviewed exact mappings, and unpriced cards remain usable. |
| P6 / P1 | Automatic-update code and revision-1 rehearsal are recorded, while live-provider, physical-device/offline and first real update acceptance remain open in the current documentation map. | Observe actual deployed discovery/publication configuration and a real new-set update on device. Compare expected release timing with signed descriptor/checklist activation and interrupted downloads. | A newly released set reaches recognition and Browse with a complete validated checklist; offline and interrupted-update behavior preserve the last good release. |
| P7 / P2 | The service exposes English and Japanese locales for catalog reads; that does not prove Japanese camera/Browse/variant parity, or support for every other language. | Map language support separately for scanning, import, Browse, pricing and offline data. Compare region-specific set numbering and physical variants before sharing identities. | A language-by-capability matrix has measured evidence; currency and regional printings cannot silently collapse into English identities. |

Source anchors: [checklist manifest](../../TradingCardScanner/PokemonChecklistSnapshot/manifest.json), [offline/historical support](../../TradingCardScanner/Games/Pokemon/PokemonCatalogSupport.swift), [Pokémon adapter](../../TradingCardScanner/Games/Pokemon/PokemonCatalogAdapter.swift), [update plan](../plans/automatic_pokemon_catalog_updates_plan.md), [pricing plan](../plans/browse_pricing_coverage_plan.md), [known limits](../../README.md).

#### Pokémon count discrepancies to investigate

Direct read of the bundled manifest and its referenced payloads:

| Provider set / print run | Manifest `cardCount` | Standard slots | Payload rows |
| --- | ---: | ---: | ---: |
| `bw10` — Plasma Blast | 6 | 108 | 108 |
| `bw3` — Noble Victories | 4 | 104 | 104 |
| `bw5` — Dark Explorers | 15 | 111 | 111 |
| `gym2` — Gym Challenge, first edition | 130 | 132 | 133 |
| `sm10` — Unbroken Bonds | 2 | 235 | 235 |
| `sm11` — Unified Minds | 4 | 260 | 260 |
| `sm6` — Forbidden Light | 2 | 147 | 147 |
| `sm9` — Team Up | 2 | 197 | 197 |

Rows can represent multiple physical slots for one collector number. Neither matching row counts nor matching unique-number counts alone establish completeness. This corrects the earlier conversational implication that low manifest values demonstrated missing cards.

### One Piece

The [current retained-corpus audit](one-piece-variants-catalog-edge-cases.md) records 2,692 canonical cards and 2,745 physical UUIDs: 2,490 verified English printings, 224 provisional and 31 conflicted records. It records 221 canonical numbers with no eligible printing, 19 numbers with multiple eligible printings and 1,961 exact aggregate USD TCGCSV mappings. These are snapshot findings, not a current worldwide inventory. All canonical physical-coverage flags remain false.

| ID / priority | Evidence and present boundary | Research needed | Closure criterion |
| --- | --- | --- | --- |
| O1 / P0 | 221 retained canonical numbers have no eligible printing; provisional/conflicted rows cannot be acquired as verified cards. | Export a privacy-safe discrepancy ledger, group records by release and rejection reason, and resolve official release/language/physical identity evidence. Determine which records are released within scope versus announced or outside scope. | Every in-scope released number has at least one verified eligible printing; excluded or held records retain explicit reasons. |
| O2 / P0 | All physical-coverage flags are false. A single eligible candidate therefore does not prove the complete physical candidate universe is known. | Reconcile alternate arts, reprints, manga treatments, stamps, prize/serialized cards, product appearances and block/revision changes. Start with OP01-120 Shanks, OP01-001 Roronoa Zoro, OP01-003 Luffy, P-001 Luffy and ST11-003 Backlight; then enumerate every product/event distribution. | Mark completeness only for independently reconciled families; printing pickers include all verified candidates, and no incomplete family earns automatic uniqueness. |
| O3 / P1 | The implementation ledger retains 257 discrepancies and describes remaining special/reprint/revision evidence work. Ordinary discovery/adoption is already implemented. | Classify discrepancies as duplicate artwork occurrences, actual separate printings, conflicting language/release evidence, or market-product joins. Resolve with official product/event evidence and independent provider comparison. | Each discrepancy has a disposition and source evidence; permanent UUIDs and existing ownership are preserved or migrated with an explicit plan. |
| O4 / P1 | DON!! and non-English acquisition remain separately gated. Ordinary text-number recognition cannot identify every DON!! design. | Define a DON!! visual catalog and recognition/selection strategy; separately inventory English regional distributions and non-English cards. | Scoped DON!! designs resolve without invented footer numbers; language/region acquisition has verified identity and tested round-trips. |
| O5 / P1 | Exact aggregate mappings number 1,961; pricing coverage is separate from 2,490 eligible printings. Graded/sealed coverage is separate scope. | Identify eligible finishes lacking mappings; reconcile special/reprint market products against exact number, release, treatment and finish. Do not infer a one-to-one deficit merely by subtracting totals. | Every mapped quote identifies the exact physical target; unmatched targets have explicit unpriced status and a tracked cause. |
| O6 / P1 | Local retained-corpus and simulator evidence do not establish production publication, device camera accuracy, sync compatibility or current live-provider/artwork authorization. | Complete the existing release acceptance checklist: physical samples, new-release freshness, signed production activation, provider/artwork permissions and ownership/sync compatibility. | Device/provider/release evidence is recorded against the actual shipping configuration; gates close individually. |

Source anchors: [edge-case audit](one-piece-variants-catalog-edge-cases.md), [implementation ledger](../plans/one_piece_code_implementation.md), [catalog integration plan](../plans/one_piece_catalog_integration_plan.md), [release acceptance](../plans/one_piece_release_acceptance.md).

## Research sources and boundaries

- **Magic:** Scryfall physical printing inventory, paired with official Wizards product/treatment information and physical samples. An attempt to read [Scryfall bulk-data documentation](https://scryfall.com/docs/api/bulk-data) during this review returned HTTP 403; no fresh complete Magic feed was captured.
- **Pokémon:** official regional set/product/checklist evidence, TCGdex set/card data, and independent Pokémon TCG data comparisons. [TCGdex documentation](https://tcgdex.dev/) explicitly says language completion levels differ; multilingual API availability is not exhaustive coverage. No full provider crawl was performed here.
- **One Piece:** [Bandai English card list](https://en.onepiece-cardgame.com/cardlist/), product and event announcements, then independent Limitless/Scrydex and market comparisons already identified in the integration plan. A single card-list view is discovery evidence, not a full inventory or proof of physical printing identity. Verify release dates and region; do not treat announced cards as released cards.

Retain source URL, observation date, language/region, release status and exact identity for every discrepancy. Access failures mean unknown coverage. Provider counts, artwork counts and price-product counts measure different things; none alone is a physical-card denominator. Evaluate relevant terms before choosing new storage/redistribution workflows; this report makes no legal conclusion or new publication decision.

## Recommended sequence and deliverables

1. **Establish the denominator (P0):** agree the first milestone scope and produce dated per-game inventories with exact identities, release status and intentional exclusions. Compare bundled, active signed and live provider data separately.
2. **Resolve present uncertainty (P0):** triage One Piece's 221 held-only numbers and incomplete printing families; verify Pokémon parallel eligibility and count semantics; enumerate Magic's filter exclusions.
3. **Fill substantial supported-scope gaps (P1):** historical Magic, special/stamped/reprint identities, exact-price joins, and new-release/device/offline acceptance. Reuse existing ingestion and update infrastructure.
4. **Expand separate scope (P2):** DON!! and language/region coverage after their recognition and identity models are defined.

The primary deliverable should be a discrepancy ledger with columns: game, canonical ID, physical printing/finish, language/region, release/product, source/date, expected capability, observed failure, known gap versus unverified, priority, disposition, owner and closure evidence. Track coverage percentages only where the expected universe has been reconciled. Keep pricing percentages separate from identity and recognition.

For each implementation fix, add a meaningful deterministic regression for the real failure, verify scan/Browse/import/collection parity where relevant, then use physical samples for optical claims. Report recognition success, incorrect selection and abstention separately. Completing a fixture suite does not close device accuracy or worldwide completeness.

## Verification of this report

**2026-10-06 data follow-up:** [Useful handoff tables](../research/card-coverage-gap-data/README.md)
retain exact Pokémon parallel eligibility, Magic PLG20 regressions and One Piece
printing candidates. Duplicate/unsupported inputs were excluded; no catalog
adoption or completeness gate was closed. Family names above were corrected
against the retained registry.

Read-only inspection of current source, bundled Pokémon payloads, current plans and retained One Piece audit evidence. No app source or catalog records changed. No build, physical-device test, full upstream enumeration or authenticated pricing-provider check was performed. Documentation links and whitespace are checked at handoff. Existing game-specific plans remain the implementation and acceptance authorities.
