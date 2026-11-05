# POP Series 1–9 finishes and exact product coverage

**Status:** two exact product exclusions authored locally; native candidate
emitted, artwork continuity failed; unsigned and unpublished — 2026-11-03.
Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9` plus preserved local changes.
Scope is **English-language physical cards only**, including English regional
distributions. Non-English printings are not catalog additions.
The [comprehensive ledger](../pokemon-broad-coverage-2026-11-02/README.md)
remains the overall authority. No app/Core code changed in this batch.

## Batched census and comparison

All nine [provider set directories](sets.json) and all **153 current cards**
were read successfully. Per-set receipts preserve the public identities,
variant objects, product IDs and response hashes:
[POP 1](provider-pop1.json), [POP 2](provider-pop2.json),
[POP 3](provider-pop3.json), [POP 4](provider-pop4.json),
[POP 5](provider-pop5.json), [POP 6](provider-pop6.json),
[POP 7](provider-pop7.json), [POP 8](provider-pop8.json),
[POP 9](provider-pop9.json). No numeric quotes are retained.

There are **226 detailed objects**: 159 Normal, 63 Holo and four Reverse;
ten explicitly name Cosmos and six Cracked Ice. Of **225 populated product
handles**, 224 match the reviewed base name and number; one points to another
card. [The object comparison](object-comparison.json) preserves every object,
including the missing stamped Pikachu handle. The exact `δ Rainbow Energy` /
`Delta Rainbow Energy` alias is explicitly reviewed. Name normalization is a
review aid, not physical-variant proof.

All **162 distinct linked primary products** returned HTTP 200;
[receipts](linked-products.json) retain identity metadata. Nine independent
discovery directories expose 169 products: 160 cards and nine sealed packs.
Eleven previously unread products were checked against primary metadata,
bringing this batch to **173 distinct successful primary product reads**.
[The inventory receipt](product-inventory.json) distinguishes discovery from
physical proof and does not count packs as missing cards.

Four World Championship Deck products belong to correctly player-stamped
Gallade/Kirlia/Ralts objects. Their marketplace group differs from POP, but
their names and numbers match. They are not wrong-product findings. Espeon
POP 5 16 already has Normal-only coverage and correct product 85329.

## Two applied exclusions

| Exact provider object | Product excluded from that object | Evidence and preserved control |
| --- | ---: | --- |
| Stantler POP 7 9, Cosmos Holo | 86467 | Primary product is Kirlia 008/017; independent Serebii lists Kirlia 8 and Stantler 9. Normal Stantler 89505 is preserved. |
| Umbreon ★ POP 5 17, unmarked Holo | 90153 | Pokumon's exact English card entry and CardTrader's exact numbered product identify Non-Holo. Normal Umbreon 90153 is preserved. |

The [exact records and source observations](review.json) retain at least two
independent authoritative hosts for each correction. The
[Serebii POP 7 inventory](https://www.serebii.net/card/popseries7/)
corroborates the Stantler/Kirlia mismatch. For Umbreon,
[Pokumon's per-card history](https://pokumon.com/card/umbreon-gold-star-17-17-pokemon-organized-play-events-pop-series-5/)
explicitly identifies English Non-Holo, and the
[CardTrader numbered entry](https://www.cardtrader.com/en-US/cards/124377-umbreon-gold-star-shiny-non-holo-promo-17-17-pop-series-5)
identifies the Non-Holo promo with an English language option. Its generic
Holo glossary is not card-specific evidence. Primary 90153 flags neither
Holo-only nor Normal-only, so a simple finish-flag comparison misses this case.

These use the already approved exact-object product exclusion mechanism.
They block the mismatched price identity on fresh/cached provider consumption;
they **do not remove disputed physical choices**, delete holdings, rekey Normal
or reconcile every saved-only historical quote/detail link. Umbreon's phantom
Holo choice still needs the separately proposed exact review support. No Cosmos
replacement is assigned to Stantler: 89505 is Normal-only and the physical
English Cosmos printing remains unproven. A pricing exclusion is not evidence
of physical absence.

## Adjacent English products retained for follow-up

The inventory found separate products for **Chimchar POP 8 12 Cracked Ice
(616999)** and **Pikachu POP 9 15 Pokémon Day 2009 (701479)**. Both primary
images were inspected; the receipt retains URLs/hashes rather than image files.
Chimchar shows English text, 12/17 and fractured foil outside its artwork.
Independent [per-card release history](https://pokumon.com/card/holofoil-chimchar-12-17-trainers-challenge-box-pop-series-8/)
and [reprint history](https://bulbapedia.bulbagarden.net/wiki/Chimchar_(Diamond_%26_Pearl_76))
identify the Trainer's Challenge Box Cracked Ice Reverse printing. Existing
84287 is not proven wrong merely because a separate pattern product exists.

Pikachu's English 15/17 image visibly bears the Pokémon Day 2009 stamp.
[The numbered release history](https://bulbapedia.bulbagarden.net/wiki/Pikachu_(POP_Series_9_15))
distinguishes that European English distribution from non-English Cosmos
printings. The unmarked product 88092 remains separate. Neither positive
binding is installed: named Cracked Ice and generic stamped Normal additions
exceed the current approved positive whitelist. French-only Cosmos printings
are outside scope. No generic Holo substitute is added.

## Candidate and verification boundary

All **138 earlier records and every other parsed authoring value remain exact**.
Input now contains **75 descriptors / 140 protected records**: 137 positive
records (76 Jumbo, Eevee Cosmos, 41 ordinary Holo minimums and 19 existing-Holo
DP product bindings), plus three exact product exclusions. Record counts are
not counts of new physical printings. The original XY review queue remains
121 unadmitted signals.

The first normal live validation exited 1 on an unrelated TCGdex HTTP 503 for
XY108. Its one retry emitted a complete final report and all three unsigned
candidate artifacts before the pause. The session handle was unavailable on
resume; no observed retry exit code is invented. CLI source emits the final
report after successful build and artifact writes. Independent offline normal
signature verification of the revision-20 baseline exits 0. See
[native report](native-review.json) and [validation receipt](validation.json).
The candidate carries all 140 input records exactly, all 95 active corrections,
all 75 provider fingerprints and 6,675 numbered summaries.

**Artwork continuity fails for these bytes:** 228 of 238 active mappings are
retained exactly, ten EX Trainer Kit Latias mappings are missing, none changed
and 28 are added. The secondary card-list request returned HTTP 502 despite
successful secondary set discovery. [The continuity receipt](artwork-continuity.json)
supersedes the preceding DP candidate's pass only for this artifact; historical
receipts are unchanged. Publication remains held. No additional full live retry,
app build, mechanism test, signature, deployment, commit or push was performed.
Physical-camera, paid-quote, saved-only reconciliation and exhaustive English
printing acceptance remain open.
