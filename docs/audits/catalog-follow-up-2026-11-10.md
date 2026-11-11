# Scan Stash catalog follow-up

**Status:** implementation and verification against the November 10 working tree, based on `f73d2e06983c3a2dfac277acdf7e650d4ca66751`. Dates on retained provider captures use UTC. The interrupted review produced excerpts and retained evidence. The complete report was unavailable.

The most serious confirmed defect was Pokémon's Normal-only data. It could feed both Browse and the scanner and make the scanner record a provisional finish with “Only variant printed.” The follow-up corrects 3,831 historical entries and corroborates finish membership for all 141 Delta Reign cards. The 72 remaining historical identities retain recovery paths. The app also removes two demonstrated classes of duplicate foil slots. Launch still depends on approved catalog delivery, independently reviewed physical coverage, and the device and service gates from the broader review. [Launch review](launch-review-2026-11-10.md).

## Coverage map

| Area | Evidence reviewed | Release position |
|---|---|---|
| Pokémon identity, recognition, and Browse | Bundled manifest and checklist resources, resolver and acquisition rules, installed cache paths, live TCGdex, TCGCSV, independently pinned Pokémon TCG Data, and production revision 22 | Scoped finish and cache fixes implemented. Delta Reign and part of the promo scope still depend on a successful signed publication. |
| Pokémon finish review and marketplace products | 24 retained reports, 48 matching raw market hashes, identity and product attribution, certification receipts, signed additional variants, and live flat and detailed lanes | The exact-set table has zero of 146 bundled provider sets certified. Whole-set review remains open. |
| Browse across games | Both name-search entry points, provider text, local matching, independent cursors, directory invalidation, pagination, and failed-set recovery | Preserves punctuation for provider requests, allows continuation after filtered empty pages, and supports skipping a failed set. |
| Magic | Production `legacy-live` rollout, Scryfall printing and name lookup, signed-only child routing, historical fallback, and the treatment catalog | The known ordinary finish list is per-printing provider evidence. Special treatments and historical identity keep their existing admission requirements. |
| Disney Lorcana | Production bootstrap and bundled discovery and physical catalogs. Discovery has 3,582 card rows. The reviewed catalog has 1,749 physical printings across sets 1–8. | Sets 9–14 contribute 1,460 discovery card rows and remain Browse-only under the current production policy. |
| Yu-Gi-Oh! | Bundled seed and exact source replay, TCGCSV candidate workflow, Konami and YGOPRODeck inventory, signed candidate verification, acquisition and edition rules | Bundled Ultimate Tournament Pack 2 is refreshed. The approved remote channel still requires production configuration. |
| One Piece | Production configuration, signed revision 1, public pointer and runtime capability admission | The verified signed seed is in the local Release build. Production rollout is disabled and collection writes are off. Hosted publication and installed Release acceptance remain open. [Production setup](../release/one-piece-production-setup-2026-10-23.md). |

## Findings and repairs

### Pokémon historical Normal placeholders

The raw bundle has 157 manifest entries, 146 distinct provider sets, and 18,902 distinct card IDs. Thirty-two provider sets had a single Normal slot for every card, totaling 4,063 IDs. The existing Hidden Fates Shiny Vault and Yellow A repairs account for 100 of those cards. The remaining 30 sets contain **3,963 IDs**, about 21% of the bundle. The interrupted review's 81-of-83 sample is its reported result. Its exact sample list was unavailable. The independent replay covered every scoped identity.

The generator matches bundle and live TCGdex set identities with a pinned Pokémon TCG Data catalog by set, collector number, and name. It then attaches only positive standard finish membership from an exact TCGCSV product. Collector annotations such as Team Plasma and Ancient Traits are recognized from the independent card record. Variant-specific products and unmatched names remain visible in the evidence ledger.

| Outcome | Cards |
|---|---:|
| Normal and Reverse | 2,689 |
| Holo only among corroborated lanes | 769 |
| Holo and Reverse | 364 |
| Normal only among corroborated lanes | 60 |
| Holo and Normal | 9 |
| No corroborated standard membership | 72 |

An exact certified finish list takes priority. For the scoped historical placeholders, the app requires an explicit finish decision when the projection yields only one corroborated choice. A matching printed label or explicit lock may resolve a corroborated option. With zero supported options, the identity stays discoverable and acquisition goes to the existing recovery path. Existing Normal holdings with uncorroborated membership are flagged for physical review through the price eligibility checks. Correcting a stored identity still requires the physical card. [Evidence producer](../../scripts/derive_pokemon_legacy_finishes.py), [variant model](../../TradingCardScanner/Models/TCGdexCard.swift), [resolver](../../TradingCardScanner/Services/VariantResolver.swift), [checklist projection](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift), [independent catalog snapshot](https://github.com/PokemonTCG/pokemon-tcg-data/tree/90f27d0e14cefe48ccb2b8922a7a356b2fcf0072/cards/en).

**Reperform.** Open Black & White Snivy `bw1-1` and XY Venusaur-EX `xy1-1` in the rebuilt offline checklist. Snivy offers Normal and Reverse. Venusaur-EX offers Holo and asks for confirmation in Auto. Inspect Treecko `ex5.5-1` for the unresolved path, including a Normal lock. Re-run `PokemonFinishEvidenceTests` and `RetailVariantTests` for current Browse/scan parity and exact certification precedence. [Snivy provider record](https://api.tcgdex.net/v2/en/cards/bw1-1), [Venusaur-EX provider record](https://api.tcgdex.net/v2/en/cards/xy1-1).

### Duplicate broad foil flags and certification disagreements

The retained Cosmos comparison covered 238 card records. For **120 IDs across 36 sets**, the broad Holo flag was accompanied only by standard English Cosmos Holo details and the provider carried no separate plain Holo lane. For Ascended Heroes, **138 of 140 captured candidates** had both a named ball or Team Rocket foil and Energy Symbol foil. The exact market products corroborated both named objects. The live provider and market both corroborated separate plain Reverse on `me02.5-183` and `me02.5-185`.

The live model treats the broad flag as an aggregate for those demonstrated shapes. A separate plain detail or matching flat market lane keeps plain Holo or Reverse eligible. The generated table repairs retained checklists that carry only the old flattened result. Browse also retains the existing distinction between standard and expanded slots. [Variant model](../../TradingCardScanner/Models/TCGdexCard.swift), [projection producer](../../scripts/derive_pokemon_legacy_finishes.py), [Ralts example](https://api.tcgdex.net/v2/en/cards/me01-058), [Erika's Oddish example](https://api.tcgdex.net/v2/en/cards/me02.5-001).

The 24 retained certification captures contain **4,433 card rows, including 622 original conflicts**. The revised comparison resolves 40 of those rows by exact title and product attribution, including 15 Prismatic Evolutions Poké Ball rows and eight Shrouded Fable card rows that shared numbers with other products. There are 582 raw checklist conflicts after that replay. Ascended Heroes accounts for 141, including 128 whose remaining difference is the duplicate Reverse. The revised comparison preserves 78 previously conflated or unidentified marketplace products as individually reviewable rows. The original excerpts' 618, 320, and 141 figures referred to an unfinished classification. This replay gives the counts for the retained input bytes. [Certifier](../../scripts/certify_pokemon_finish_coverage.py), [certifier tests](../../scripts/tests/test_certify_pokemon_finish_coverage.py).

**Reperform.** Compare Ascended Heroes Erika's Oddish against the exact market products for Normal, Poké Ball and Energy Symbol. Verify the separate plain Reverse controls above and the separate plain Holo control `sv06-060`. Inspect Prismatic Evolutions entries with “number (Poke Ball Pattern)” and Professor's Research entries with named bracketed qualifiers. Review `retained-comparison-final.json` for the other market products. A certificate still requires a capture-bound comparison with every unresolved row addressed and compatible signed membership.

### Browse search and background updates

Both Browse entry points passed punctuation-stripped input to the providers. The exact live Pokémon names returned 43 results for “Ho-Oh,” 40 for “Mr. Mime,” and 21 for “Farfetch'd.” The stripped requests returned one, zero, and zero respectively. Scryfall returned eight results for the escaped exact phrase “Urza's Saga.” The corrected flow preserves the trimmed input for transport and uses normalization for local matching and minimum length. [Browse service](../../TradingCardScanner/Services/BrowseCatalog.swift), [Browse view and model](../../TradingCardScanner/Views/BrowseView.swift).

The empty-page defect occurs when provider results are filtered against the local set directory but the provider has another page. Both search surfaces now expose “Continue search” in that state, and the continuation uses the retained cursor. When an all-cards page fails, Retry remains available and “Skip this set” advances to the next set when one exists. A publication for an unrelated set preserves already loaded pages when their directory prefix and search membership remain valid. Updates affecting displayed cards, active results, or authority still refresh the corresponding state.

The bundle stores the current probe-key spelling on 10 raw entries. All 157 entries have a decoded probe after the legacy fallback. The prior resets were real on per-set publications, even though many unchanged probes avoid a crawl. [Browse model and render tests](../../TradingCardScannerTests/BrowseFeatureTests.swift).

**Reperform.** Run `BrowseFeatureTests` and `BrowsePaginationRenderTests`. The mocked empty page returns a nonempty cursor and the next page returns the matching Pokémon card. The hosted search fixture publishes an unrelated set, preserves the loaded pages, then publishes the matching set and reloads them. The failed-set skip has source verification. Its remaining manual check uses two known sets. Force the first to fail, select “Skip this set,” and confirm the second loads. Repeat and use Retry to verify the original failure path.

### Pokémon signed scope, cache, and delivery

The public pointer verified with the production pin as revision 22 with 75 descriptors. Delta Reign released November 6. TCGdex lists `me06` with 141 total cards and an official denominator of 103. The bundle and the verified pointer omit its checklist or descriptor respectively. The scheduled live publisher now emits a warning for a released, discovery-eligible set still absent from a verified active release after 48 hours. The chosen interval allows an ordinary ingestion and approval cycle. The first live attempt returned HTTP 503 on the directory. The second emitted the `me06` warning before a card-detail HTTP 503. With two bounded transient GET retries, the live publisher validated and staged unsigned revision 23. [Pokémon announcement](https://www.pokemon.com/uk/news/the-pokemon-tcg-mega-evolution-delta-reign-expansion-is-available-now), [provider set](https://api.tcgdex.net/v2/en/sets/me06), [production pointer](https://catalog.scan-stash.com/v1/current.json), [publisher](../../PokemonCatalogCore/Sources/pokemon-catalog-publisher/main.swift).

The ordinary directory crawl filters several non-expansion categories. Signed promo reconciliation runs independently of that filter. Revision 22 contains eight promo descriptors with fingerprints, and the bundle contains zero of those eight. A hosted fixture confirms that a signed promo missing from both the directory and bundle becomes visible after an exact fingerprint match. The completed live publisher replay reproduces six current fingerprints. The current `mep` and `svp` fingerprints differ from revision 22. First-install Browse visibility for those two sets still depends on exact reconciliation after publication. [Reconciliation and authority](../../TradingCardScanner/Services/BrowseCatalog.swift), [hosted fixture](../../TradingCardScannerTests/PokemonCatalogSliceDTests.swift).

The staged revision is classified `newSet`. It adds `me06` as the `DLR` expansion, refreshes six content descriptors, and adds 45 finish supplements already present in publisher input for `bwp`, `dpp`, `pop5`, `pop7`, and `xyp`. Review these authority changes in the protected publication process. The candidate payload SHA-256 is `3506e8e558d826eb2678a0f21305b4ae3fc0af7be02d8a5451edaf04e3bfa328`. [Owner input](../../publisher/catalog-input.json).

The release check then found the same Normal placeholder on all 141 live Delta Reign records. Its generated app projection binds every card to the staged checklist and the retained provider identity, then verifies positive exact market membership against TCGCSV group 24831. It finds **77 Normal and Reverse, 48 Holo, 10 Holo and Reverse, and six Normal**. Exact collector numbers distinguish the six Left and Right listings. The abbreviated Energy names use the same exact product matching. Apply the generated app resource to the distribution candidate when enabling `DLR`. The publisher now warns on new expansions with this uniform provider shape. The 141-card recorded fixture reproduced the warning and the staged provider fingerprint. [Heracross provider record](https://api.tcgdex.net/v2/en/cards/me06-001), [Delta Reign market products](https://tcgcsv.com/tcgplayer/3/24831/products), [evidence producer](../../scripts/derive_pokemon_legacy_finishes.py).

The production price index and the sampled group 24722 product and price responses returned 200. Both sample hashes matched the index, which names the November 10 20:05:49 UTC source build. The regenerated Yu-Gi-Oh! seed makes 49 exact UP02 products eligible for the next scoped feed build. Its group was absent from the sampled live index. Delta Reign currently uses the ordinary Pokémon quote path. [Price index](https://catalog.scan-stash.com/market-prices/v1/index.json), [scope producer](../../scripts/market_price_feeds.py).

Disk cache entries now carry the signed provider fingerprint observed when they were resolved. A changed fingerprint makes an earlier cache hit ineligible, and a downloaded checklist whose known fingerprint conflicts with current authority cannot refill it. A cold reader can still use the installed fallback checklist. A lookup already bound to a superseded fingerprint requires exact offline parity or current provider resolution. Optional artwork recovery can fill the image on the matching entry without overwriting finish evidence. [Scanner adapter](../../TradingCardScanner/Games/Pokemon/PokemonCatalogAdapter.swift), [cache and offline factory](../../TradingCardScanner/Games/Pokemon/PokemonCatalogSupport.swift).

**Reperform.** Verify the pointer with `pokemon-catalog-publisher verify-release --path <capture> --environment production --expected-revision 22`. Use the public directory and pinned fingerprint function to compare the promo inputs. In the cache regression, seed a Normal from the provider, publish the old checklist, change the signed fingerprint, and resolve Holo. Reopen the disk cache and repeat from an empty cache against the older overlay. Keep the authority check separate from the provider's price timestamps.

### Yu-Gi-Oh! bundled freshness

The October 23 seed already listed the Ultimate Tournament Pack 2 group, but it held zero printings for it. The US release was November 4. The exact additive replay now includes 50 products in group 24806. Konami and YGOPRODeck corroborated 49 identities, and 48 of those have a Limited lane. Miracle Ejector `UP02-EN002` is linked and discoverable with no edition membership. Token `UP02-EN050` has exact market-only Limited membership and retains the explicit-choice policy. The replay removes zero products and keeps the prior canonical IDs and quote provenance. The producer now alerts when provider-dated groups acquire candidate printings and the approved parent still has zero.

Konami's raw hidden title attribute contained unescaped apostrophes. The parser had truncated eight retained inventory names. The corrected parser and exact same source hashes enable two earlier printing families under the existing rule, `DUNE-EN080` and `PSV-013`. The bundle has 46,592 printings and 262 eligible printing families. Edition selection still uses the app's separate membership and printed-label evidence. [Builder](../../scripts/build_yugioh_catalog.py), [Konami extractor](../../scripts/yugioh_official_inventory.py), [official release date](https://www.yugioh-card.com/en/products/tournament-packs/), [official card checklist](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=2000001720000&rp=99999&request_locale=en), [exact market group](https://tcgcsv.com/tcgplayer/2/24806/products).

**Reperform.** Run the builder replay below, compare existing products by marketplace product ID and canonical card ID, and verify that the only prior physical rows with changed fields are the two corroborated printing-family records. In the simulator suite, exercise Red-Eyes Black Dragon `UP02-EN001` through exact printing choice and Limited selection, and verify Miracle Ejector remains discoverable without an acquisition choice. [Native catalog and resolution tests](../../TradingCardScannerTests/YuGiOhIntegrationTests.swift).

### Largest text size

Collection search and price feedback now grow vertically with the system text size. The Portfolio movement heading gets a full-width row at accessibility sizes, followed by the explanation and See all actions. Portfolio card tiles also use the available scroll width at those sizes so a signed dollar amount stays readable.

Inspected the final iPhone and iPad Collection placeholders and the iPhone one-month Portfolio movement heading and price rail at the largest system text size. The render showed both Portfolio actions, full words and full amounts. The simulator typing action reported success while the field still showed the placeholder, so interactive typing was unverified. The query behavior is covered by the native Collection query tests. [Collection search](../../TradingCardScanner/Views/CollectionView.swift), [Portfolio movement section](../../TradingCardScanner/Views/PortfolioView.swift), [earlier reproductions](launch-review-2026-11-10.md#lr07--collection-search-clips-accessibility-text).

## Replaying the data

Evidence, logs, and simulator results are retained on the external SSD under `CodexBuilds/CatalogReviewFollowup-20261111-Codex`. Original Pokémon comparison reports and prices are retained under `launch-findings-2026-11-10`; the Yu-Gi-Oh! capture is under `YuGiOhSourceCache/2026-10-21`. Use separate replay output paths.

```sh
run="${CATALOG_REVIEW_ROOT:?Set this to an external SSD output directory}"
prior="${CATALOG_SOURCE_ROOT:?Set this to the external SSD containing retained captures}/launch-findings-2026-11-10"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/certify_pokemon_finish_coverage.py replay \
  --reports "$prior/FinishCoverageReview/docs/research/pokemon-finish-coverage" \
  --market-cache "$prior/TCGCSV" \
  --output "$run/replayed-comparisons.json"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/derive_pokemon_legacy_finishes.py \
  --evidence "$run/LegacyEvidence" \
  --foil-evidence "$run/FoilPatternEvidence" \
  --reverse-evidence "$run/ReversePatternEvidence" \
  --released-evidence "$run/DeltaReignEvidence" --candidate "$run/PokemonCandidate" \
  --output "$run/replayed-finish-evidence.json" \
  --report "$run/replayed-finish-review.json"
cmp "$run/replayed-finish-evidence.json" TradingCardScanner/PokemonChecklistSnapshot/legacy-finish-evidence.json
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*pokemon*'

replay="$run/YuGiOhReleasedReplay"
source="$CATALOG_SOURCE_ROOT/YuGiOhSourceCache/2026-10-21"
PYTHONDONTWRITEBYTECODE=1 python3 -I scripts/build_yugioh_catalog.py --offline \
  --cache-dir "$replay" --previous-seed "$run/YuGiOhBaseline/catalog.json" \
  --price-receipt "$replay/older-price-receipt.json" --price-receipt "$replay/new-price-receipt.json" \
  --official-inventory-html "$source/konami/mp24.html" \
  --official-inventory-html "$source/konami/dune.html" \
  --official-inventory-html "$source/konami/psv.html" \
  --out "$run/yugioh-replayed.json" --report "$run/yugioh-replayed.md"
cmp "$run/yugioh-replayed.json" TradingCardScanner/YuGiOhCatalogSeed/catalog.json
PYTHONDONTWRITEBYTECODE=1 python3 -I scripts/build_yugioh_catalog.py --self-test
```

The Pokémon resource SHA-256 is `8b17ec78aa97891c5c56e98b1fbfea0c5e28640ad3d1f2916c384a6d319ff272`. The Yu-Gi-Oh! resource SHA-256 is `6136ee9bb252e96c0c45b034aa1296d07ff65809cbc73afcc6f5c7e7e3af9b43`. The Yu-Gi-Oh! replay overlay links the original raw groups, includes the exact new group captures and stores the separately hashed secondary-source projection and disjoint price receipts.

## Verification

The broad iPhone 17 Pro iOS 27.0 simulator run passed **909 tests**, with three opt-in live-price tests skipped and zero failures. `CatalogFinalDelta.xcresult` contains the result. The selection covered Browse render and pagination, Pokémon recognition, variants, cache and quotes, all five game runtimes, TCGplayer links, and Collection queries. The initial Delta Reign provider-placeholder regression passed in that run.

The later final-title selection in `DeltaTitleAliases.xcresult` ran 13 tests
with one failure. The Delta Reign regression passed. The cache-reopen method
failed while removing a missing temporary directory. Its log also records
disk-full errors from the simulator cache and SQLite, so that run requires
verification under usable storage conditions. The final unsigned device
Release build in `delta-titles-release.log` succeeded.

The separate One Piece PR #21 at `7a6223c` ran its broader iOS selection on the
earlier committed source and reported 1,815 tests, four skips and seven failed
assertions across four methods. The failures concern missing finish evidence,
two pricing repair fixtures and a structural refresh fixture. This run preceded
the fixture corrections now on GitHub `main`. The focused rerun below covers
those corrections.
[PR validation](https://github.com/Razorback2424/CardScanner/actions/runs/42937316752).

The subsequent focused rerun on local `676503a` plus the two test corrections
ran `CollectionKeyTests`, `PokemonFinishEvidenceTests`,
`PokemonTCGCSVPriceTests` and `RefreshStructuralWriteTests`. It passed 90 tests
with one opt-in live-price skip and zero failures. The cache-reopen regression
passed. The missing-variants expectation now requires a finish choice, and the
structural refresh fixture supplies certified Normal coverage for its expected
pending finish. The pricing fixtures already had their certification
corrections. The result is retained at
The focused result bundle is retained on the external SSD under
`CodexBuilds/CatalogGateFollowup/Focused.xcresult`.
GitHub `main` was still `f73d2e0` during this rerun. The fixture corrections
subsequently reached GitHub `main` in `d1d7fb8`.

The device Release build compiled unsigned. Both packaged resource hashes match the verified replay outputs. Its minimum iOS version is 18.0. One Piece rollout is disabled with collection writes off, Magic is configured for legacy live delivery, and the Yu-Gi-Oh! rollout setting is absent. The privacy and support URLs are empty.

The Pokémon publisher package passed 90 tests with one opt-in live test skipped. The four offline selections passed 17 Pokémon, 36 Yu-Gi-Oh!, 18 price feed and 10 hosting restoration tests. The hosting configuration check passed. The staged live publisher candidate and the offline Delta Reign warning replay both completed.

Rendered evidence is under `UI/final-collection-phone-ax5`, `UI/final-collection-ipad-ax5`, and `UI/final-portfolio-phone-ax5` in the run directory. These screenshots used the same SwiftUI code before the final Delta Reign data refresh. The inspected Portfolio screen includes a populated one-month movers list and its accessible explanation and See all actions.

## Launch finish line

1. Publish an approved signed Pokémon candidate with Delta Reign and current promo fingerprints, verify the production pointer and immutable release, and exercise first-install reconciliation and fallback on the distribution build.
2. Resolve the remaining 72 historical identities and outstanding finish disagreements with independent physical evidence. Complete exact-set certification before reconsidering the global incomplete-singleton policy.
3. Decide the advertised launch scope for Lorcana discovery-only sets and One Piece. Any activation needs the existing signed approval and installed Release acceptance, including add, price, reopen, Undo and CSV.
4. Verify real-camera scans and interruptions, physical centering acceptance, pricing access and freshness, StoreKit and sync, and the installed Release journeys in the launch review. The simulator checks cover the local catalog and UI changes. [Release acceptance](../plans/release_followups.md).
