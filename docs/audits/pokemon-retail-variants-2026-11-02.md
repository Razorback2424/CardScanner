# Pokémon retail promo and jumbo investigation

**Status: historical investigation; local repairs now implemented in the
[follow-up](pokemon-retail-repairs-2026-11-02.md), unsigned and unpublished.**
The constraints and repair holds below describe the earlier investigation,
before the owner's explicit implementation and signed-support authorization.
2026-11-02, checkout `9413e906cab65c1d8c61882d8eb6f137bf44617e` with existing
uncommitted sharing/pricing/browse work preserved. Source hashes and price-free
provider observations are in the [census](pokemon-retail-variants-2026-11-02.json).

## Latest maintenance constraints and signing boundary

The owner's subsequent instructions require two authoritative sources for
every physical-printing change, batched review, milestone-only builds/tests,
and catalog-only updates through the existing signing process. The visible
variant label for the SVP 196 card must be **Jumbo**. Lenticular describes the
evidence for its physical treatment; it is not the requested picker label.

This turn's draft Swift logic and tests were withdrawn after that scope change;
all pre-existing user changes were preserved. No production catalog change,
signature, publication or device repair is claimed. One draft native build
failed on test-only access to a fileprivate helper. The corrected rerun was
stopped when the owner restricted implementation scope; neither is passing
repair evidence.

The [batch review queue](pokemon-retail-variant-review-2026-11-02.json)
retains all 20 observed jumbo identities. SVP 196 has two authoritative sources
for the distinct Jumbo identity: the live TCGdex record above and the
[TCGplayer Jumbo 196 product](https://www.tcgplayer.com/product/641615/pokemon-jumbo-cards-charizard-ex-196?page=1).
The other 19 remain on hold for second-source review. No source-derived numeric
price is installed. A provider's third-party product handle is not by itself
independent corroboration.

For Eevee, [TCGplayer's indexed Blister Exclusives listing](https://www.tcgplayer.com/search/product/all?page=1&productLineName=product&seller=2370ea08&setName=all&view=grid)
explicitly names the 116/128 Cosmos Holo. [Cardmarket's additional-printing directory](https://www.cardmarket.com/en/Pokemon/Products/Singles/30th-Celebration-Additionals)
independently lists retail Eevee 116, but the retrieved evidence does not show
the exact foil description. That is a useful second-source lead, not a completed
two-source finish receipt. The candidate product number 717879 from aggregators
is not installed as a reviewed price binding.

The current signed `PokemonCatalogSetDescriptor` contains set recognition,
artwork, membership recognition and a provider fingerprint. Its human input
has no per-card finish, size or product-binding override. Signing a changed
fingerprint requests fresh provider materialization; it does not deliver a
replacement detailed card record. Therefore a local checklist edit or arbitrary
extra JSON field cannot deliver these repairs through the normal signing route.
This limitation is verified in
[`CatalogContract.swift`](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogContract.swift),
[`ProviderModels.swift`](../../PokemonCatalogCore/Sources/PokemonCatalogCore/ProviderModels.swift)
and the [publication runbook](../plans/pokemon_catalog_key_handling_runbook.md).
Both reported fixes remain held under the owner's no-logic-change constraint;
do not bypass signature validation or imply that this review queue is deployable
publisher input. A future authorized implementation would need a compatible
signed variant-data mechanism and consumer support, or an upstream correction
the existing consumer can actually represent.

## Reported cards

| Card | Confirmed evidence | App gap |
| --- | --- | --- |
| Eevee 30C 116/128, Knock Out Collection Cosmos Holo | User's physical observation; official product announcement confirms a foil Eevee in the collection. Public TCGdex `30th-116` supplies only generated Normal. Independent collector catalog distinguishes Holo and Cosmos Holo. | `TCGdexCard.catalogVariants` returns `[.holo]` immediately for reviewed 30th mappings, before detailed variants and supplemental parallels. No reviewed Eevee Cosmos entry exists. Upstream refresh alone cannot repair today's missing membership. |
| Charizard ex SVP 196 / PAF 054 lenticular jumbo | User confirmed both visible numbers. TCGdex `svp-196` explicitly publishes `type: lenticular`, `size: jumbo`, TCGplayer 641615 and Cardmarket 821617, separately from standard SVP 196 (641610 / 821616). | `isStandardEnglish` excludes jumbo; `physicalVariant` does not recognize lenticular even if that exclusion were removed. No distinct Pokémon jumbo choice is available. |

The second card belongs to the **Charizard ex Special Collection**, rather than
being the ordinary OBF 125 jumbo. The PAF-facing image needs an explicit alias
to the same lenticular object; it must not acquire the standard PAF 054 identity
or price. TCGdex `sv04.5-054` currently lists only standard Holo. TCGdex
`sv03-125` separately lists a jumbo (TCGplayer 581987 / Cardmarket 749033).
That product must remain distinct from the lenticular card.

Sources accessed 2026-11-02:

- [Official 30th product announcement](https://press.pokemon.com/en-CA/MEDIA-ALERT-The-Pokemon-Company-International-Reveals-Product-Lineup-f): confirms foil Eevee, but does not establish its number or Cosmos finish by itself.
- [Eevee Holo / Cosmos catalog](https://holofile.app/pokemon/sets/mega-evolution/30th-celebration/116-eevee): corroboration, not independently verified marketplace binding.
- [Official Charizard product page](https://www.pokemon.com/uk/pokemon-tcg/product-gallery/charizard-ex-special-collection): search-indexed; full body blocked by the site's protection during this investigation.
- [Charizard product history](https://bulbapedia.bulbagarden.net/wiki/Scarlet_%26_Violet_TCG_Series_merchandise#Charizard_ex_Special_Collection): identifies the SVP 196 / PAF 054 lenticular and PAF 007/008 Cosmos companions. Early previews referring to OBF are weaker than the released identity and live provider record.
- Public provider: [Eevee](https://api.tcgdex.net/v2/en/cards/30th-116), [SVP Charizard](https://api.tcgdex.net/v2/en/cards/svp-196), [PAF Charizard](https://api.tcgdex.net/v2/en/cards/sv04.5-054), [OBF Charizard](https://api.tcgdex.net/v2/en/cards/sv03-125).

## Systematic adjacent census

The read-only [script](../../scripts/audit_pokemon_retail_variants.py) fetched all
158 records in `30th`, all 226 in `svp`, and ten targeted controls: OBF
026/027/125/166, PAF 007/008/054, Marshadow me05-040, Team Rocket's Mimikyu
me02.5-097 and Gengar me03-050. **394/394 succeeded.** The initial pass had
81 HTTP 503 responses; a failure-only retry recovered all 81. This is a
provider-family census, not a claim of exhaustive physical-product coverage.

| Finding | Scope and implication |
| --- | --- |
| Jumbo omission affects 20 card identities | 19 SVP identities plus OBF 125. SVP: 004, 018, 049, 067, 068, 072, 078, 081, 084, 086, 100, 126, 162, 177, 193, 196, 205, 208, 500. All have at least one provider jumbo record filtered by the same size predicate. |
| Only unhandled provider type in this sample is `lenticular` | SVP 196 demonstrates both a size and a type failure. Simply admitting jumbo rows would collapse ordinary jumbo Holos into standard Holo keys. |
| All 158 30th records have the Holo-only reviewed shortcut | No fetched 30th detailed row contains a discriminating pattern/stamp/jumbo. The provider cannot reveal Eevee's retail omission through that field today. Other unlisted physical variants cannot be ruled out. |
| PAF Charmander 007 / Charmeleon 008 Cosmos are already cataloged | Live detailed rows say Cosmos; exact supplemental entries and bundled expanded checklist slots exist. These companions are positive controls, not new missing memberships. Their retained plain Holo rows need separate product review; no deletion is justified here. |
| SVP is absent from bundled browse checklists | Current 146-set bundle has 32,428 rows / 18,902 distinct card IDs, no jumbo/lenticular variant IDs, and no SVP entry. Browse directory deliberately excludes promos and jumbos. SVP scan routing does exist, so browse omission must not be described as all promo scans being unsupported. |
| OBF Prize Pack rows need further discrimination review | Three standard detailed records on OBF 125 share the same type/stamp/subtype but have distinct Cardmarket IDs (756342, 782239, 811099). This is an unresolved provider-object collision lead, not proof of three independently selectable printings. |
| Provider IDs require validation before pricing | SVP 162's jumbo `tcgplayer` value 791832 is suspicious; SVP 081 shares Cardmarket 751806 across sizes. Do not mechanically promote the census IDs into paid lookups. Public TCGCSV product endpoints returned HTTP 401 during this investigation. |

## Repair order and acceptance criteria

1. Add evidence-backed Eevee Cosmos membership under `30th-116`, retaining
   ordinary Holo. Refactor the reviewed 30th correction to correct unsupported
   Normal without bypassing exact supplemental/detailed memberships. Cover
   live, stale cache, checklist projection and refresh paths. Keep Cosmos out
   of booster Master requirements; include it in cataloged Grand Master.
   Do not alias its price to ordinary Holo without an exact product receipt.
2. Model Pokémon physical size/treatment with a durable distinct identity,
   using SVP 196 lenticular as the first case. Map both visible faces to that
   object, offer explicit standard/jumbo selection where ambiguous, and scope
   prices and saved holdings to that choice. Preserve existing collection keys.
   Keep jumbo collection support separate from the existing checklist decision
   to exclude oversized cards from Master/Grand Master.
3. Apply the same mechanism to the other 19 observed jumbo identities only
   after product review. Add fixtures for ordinary/jumbo separation, lenticular
   type, both face routes, unknown treatment, size-scoped quote selection and
   stale-cache behavior. Validate the reported cards on a physical device;
   a source/provider investigation cannot prove optical recognition behavior.
4. Maintain a retail-product manifest listing every included card, number,
   size, treatment, stamp, language and evidence source. Diff that independent
   inventory against each provider refresh. Provider self-censuses alone miss
   exactly the Eevee case demonstrated here. Extend next to 30th boxed promos,
   ex-box oversizes and two-pack blisters, then SV-era collection products.

Reproduce (network required):

```sh
python3 scripts/audit_pokemon_retail_variants.py --fetch --output /tmp/pokemon-retail.json
python3 scripts/audit_pokemon_retail_variants.py --fetch --retry-errors --output /tmp/pokemon-retail.json
```

No app, catalog membership, price bindings, holdings or signed feed was changed.
No native build or device scan was run; changes are the investigation utility
and evidence. JSON integrity, local report links and `git diff --check` were
validated. Existing unrelated user changes remain intact.
