# Pokéween 2025–2026 stamped-printing review

**Status:** four corroborated corrections prepared for review, **not installed** —
2026-11-03. Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9` began clean.
The proposal's preparation checkpoint was 75 descriptors and 95 protected records,
SHA-256 `b72c8ca9220ead96326af9e4a1225b25f037796c17a8c3b9e9a0470f7e824baa`.
This extends the [comprehensive coverage ledger](../pokemon-broad-coverage-2026-11-02/README.md)
into event stamps, separately from ordinary finishes and oversized cards.

## Complete named event cohorts

The manufacturer's announcements name [Spiritomb in 2025](https://www.pokemon.com/fr/actualites/rendez-vous-dans-le-play-pokemon-store-pres-de-chez-vous-pour-feter-pokeween)
and [Zubat, Golbat and Crobat in 2026](https://www.pokemon.com/uk/news/celebrate-pokeween-with-play-pokemon-events).
Exact English numbers and separate Pokéween products are corroborated by primary
TCGplayer metadata and independent retailers' explicit Reverse Holofoil listings.

| Printing | Exact TCGplayer product | Current provider gap | Independent finish source |
| --- | ---: | --- | --- |
| Spiritomb MEG 087/132, 2025 | 661700 | Trick or Trade row is Normal, lacks a TCGplayer handle and omits the Play! mark | [Card Caster](https://www.cardcastergames.com/products/spiritomb-087-132-pokeween-2025-mcap-087-132) |
| Zubat CRI 049/086, 2026 | 722836 | No stamped row | [EB Games](https://www.ebgames.com.au/product/toys-and-collectibles/386425-pokemon-tcg-miscellaneous-cards-products-zubat-pokeween-2026-reverse-holofoil-049086-nmm) |
| Golbat CRI 050/086, 2026 | 722837 | No stamped row | [EB Games](https://www.ebgames.com.au/product/toys-and-collectibles/386426-pokemon-tcg-miscellaneous-cards-products-golbat-pokeween-2026-reverse-holofoil-050086-nmm) |
| Crobat CRI 051/086, 2026 | 722838 | No stamped row | [EB Games](https://www.ebgames.com.au/product/toys-and-collectibles/386427-pokemon-tcg-miscellaneous-cards-products-crobat-pokeween-2026-reverse-holofoil-051086-nmm) |

[Live evidence](live-evidence.json) retains four successful card reads, six
ordinary/2025 product reads and three 2026 product reads, with raw-response hashes
and no numeric prices. The 2026 product IDs were discovery leads until their
primary responses verified the exact names, event, numbers and foil-only status.
They are distinct from the ordinary products, including Crobat's legitimate
separate Non-Holo product 694636.

All four [primary product images](image-review.json) were visually inspected:
English footer, expected collector number, orange Pikachu pumpkin mark and
Play! Pokémon logo behind the rules text. These are public product renders,
not physical-camera acceptance or an image-only inference of foil treatment.
The retailers independently specify Reverse Holofoil; TCGplayer metadata
confirms foil-only products. No artwork file is installed in the app.

Manufacturer page text was inspected through indexed official article bodies.
Direct GETs returned HTTP 200 challenge wrappers, not the article; no article
body hash, direct official-image inspection or challenge bypass is claimed.
No raw challenge response is retained in the repository. This review does not
infer an absent annual set merely because compiled Trick or Trade lists end in
2024, nor assert that no other seasonal products exist.

## Observed app/catalog coverage

The [bundled rows](bundled-rows.json) have no correct Pokéween slot for any of
the four cards. Spiritomb instead exposes
`pokemonStamp|normal|trick-or-trade|` as an expanded slot. Live provider evidence
has that same Normal object and no TCGplayer handle. The other three have only
ordinary finishes; Crobat's ordinary Non-Holo is supported by its own product
and is not part of the correction.

Existing generic stamp serialization can represent the corrected identities.
The protected signed validator, however, currently admits only Jumbo, Cosmos,
unstamped ordinary finish minimums and exact product exclusions. Ordinary
memberships explicitly require empty `providerStamps`. The exclusion mechanism
cannot express a physical-review hold for a wrong object with no bad product
handle. A data-only edit cannot safely deliver this cohort through normal signing.

## Concrete minimal support proposal

[The review JSON](review.json) contains four proposed signed records, each with
the existing canonical stamp ID shape:
`pokemonStamp|reverse|play-pokemon,trick-or-trade|`. The new `play-pokemon` token
describes the visible Play! logo; `trick-or-trade` retains the existing pumpkin
mark vocabulary. This is a proposed exact identity, not a claimed upstream token.
All records bind their own product and four evidence hosts.

The required support changes are limited to:

1. Admit and project ordinary stamped records using the existing stamp
   serializer, display labels and protected signed correction array. Keep them
   in expanded checklist membership and preserve incomplete-coverage review.
2. Match exact size, finish and full stamp arrays for signed product extraction,
   embedded quotes and marketplace destinations. Preserve conflict checks,
   signature verification, cache application and withdrawal behavior.
3. Add one optional same-card `requiresReviewVariantIDs` field on Spiritomb's
   record for `pokemonStamp|normal|trick-or-trade|`. Withhold that exact legacy
   object from scanner choices, checklist membership and pricing/links pending
   physical review. Keep ordinary Normal/Reverse and all stored holding keys,
   quantities, provenance and ledger entries unchanged; never automatically
   relabel a saved holding as the corrected object.

The third item must cover saved-only detail links as well as identified cards;
those links currently trust stored metadata. Acceptance must check this exact
case rather than claiming the earlier open link-reconciliation issue is solved.
Scanner recognition algorithms and portfolio calculations are outside this
proposal. The generic stamp picker already exists.

Because the owner's current restriction allows catalog data changes and earlier
specific signed-support exceptions, implementing this further consumer/contract
extension requires explicit approval. No app/Core source, production authoring
input, signing configuration or production release changed during this review.
The initial proposal projected 99 records from its 95-record checkpoint.
The subsequently authorized [ordinary Red & Blue batch](../pokemon-red-blue-collections-2016-2026-11-03/README.md)
brings current input to 99 without installing any stamp proposal. If these four
stamped records are later approved, the total would be 103: 102 memberships and
one price-only exclusion. The legacy review hold is metadata, not another
membership. The review JSON retains its original preparation hash/count scope.

## Acceptance milestone after approval

Use one focused shared/iOS milestone for canonical stamp validation, exact
products, raw-provider conflicts, ordinary sibling isolation, incomplete-evidence
choice, offline checklist projection, activation/cache/withdrawal, and saved
legacy holdings through refresh/reopen without rekeying or ledger changes.
Verify all detail-link routes for the held object. Then run normal native
publisher validation against the current signed production baseline and inspect
artwork continuity. Do not sign or publish from this review.

No build or test was run for this documentation/evidence-only batch. JSON,
input-hash preservation, relative documentation links and `git diff --check`
are the applicable checks. Exhaustive English coverage remains open.
