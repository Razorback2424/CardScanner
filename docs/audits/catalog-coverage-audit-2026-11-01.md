# Catalog coverage and printing identity audit — 2026-11-01

**Baseline:** `main@a2b11ade7ce37888ea4ca3debb8923b11a79b3bc`.
**Delivery:** [PR #10](https://github.com/Razorback2424/CardScanner/pull/10), unmerged.
**Scope:** Pokémon, Magic, One Piece, Lorcana and Yu-Gi-Oh; recognition,
catalog resolution, physical-printing choice, finishes, import, offline data
and catalog ingestion. This is a dated audit and regression record, not an
all-card or physical-camera certification.

## Finding

There are verified recognition and mapping defects, plus substantial known
coverage limits. A card appearing in a provider directory or a bundled file
does not prove that its printed identifier reaches the right physical printing,
or that every marketed finish is represented. The fixes in this PR use exact
reviewed identities and preserve ambiguity. They do not promote held records,
replace permanent printing IDs, or publish a signed catalog.

Two important wrong-printing risks remain: modern Magic reprints can retain an
original printing's footer, and the signed One Piece owner catalog is missing
three already-reviewed alternatives. These cannot be described as complete
coverage after the scoped fixes below.

## Method and evidence boundaries

The audit follows each representation separately: provider/discovery record,
reviewed catalog membership, printed OCR identity, shared catalog outcome,
printing/finish choice, ownership/import and exact market lane. It checks
positive examples and contradictory or incomplete evidence. Existing release
and product decisions remain in their game-specific authorities.

The new [offline census](../../scripts/audit_catalog_coverage.py) reads the
retained five-game data, checks structural integrity, and records SHA-256 hashes
of the exact inputs. Its [summary](../research/catalog-coverage-2026-11-01/summary.json)
and [discrepancy ledger](../research/catalog-coverage-2026-11-01/discrepancies.csv)
separate intentional holds, source risks, signed-adoption gaps and informational
differences. A discrepancy row is **not** necessarily a missing card or a defect.
The retained run covers 912 source files, reports zero structural errors and
2,568 informational/review rows. The source hashes identify the measured bytes.
The census executes neither OCR nor the native picker and does not verify the
One Piece envelope signature. Native regressions cover the affected runtime
paths separately.

Bounded current provider reads and official checklists corroborate individual
changes. This was not an exhaustive November 1 crawl of every provider or every
released physical product. Dates and different count semantics are retained
below instead of combining the inventories into a misleading coverage percent.
The [Magic provider/image receipts](../../TestFixtures/TradingCards/MagicCatalogCoverageAudit/review.json)
retain the exact inspected printing IDs, immutable response/image hashes and
the three-identifier List lookup reproduction.

## Retained inventory

| Game | Measured inventory | What the count establishes |
| --- | --- | --- |
| Pokémon | 157 checklist entries, 146 provider sets, 18,902 distinct provider card IDs and 31,918 physical-slot rows | Bundled checklist snapshot generated October 20. Multiple print runs/finishes can share a card ID. Live and signed descriptors are separate inventories. |
| Magic | 910 set descriptors; 353 scan-enabled and 662 browse-enabled; 352 compiled cold-start codes before this PR, 353 after | September 20 seed and older compiled vocabulary; this PR closes the sole SLZ vocabulary difference. Card-level resolution remains live under `legacy-live`. |
| Magic treatment evidence | 5,150 runtime printing enrichments; 41,142 audited rows in 1,049 test-only set entries | Treatment enrichment and retained research, not the supported physical-printing universe. The research includes excluded, foreign and digital records. |
| One Piece | Owner seed: 2,692 canonical cards, 2,745 printings, 2,490 verified English printings | Signed owner-local revision 2, October 7. Production rollout is disabled. The review corpus has 2,748 printings and 2,493 verified. |
| Lorcana | 3,582 discovery cards; 1,749 reviewed physical printings in 1,748 footer families; 3,364 exact finish mappings | October 10 discovery and October 15 physical review. Discovery-only rows do not authorize acquisition. |
| Yu-Gi-Oh | 14,736 canonical cards, 46,542 printings, 37,869 distinct printed codes, 659 set groups | October 23 retained seed. 46,303 have supported edition-selection membership; 239 remain discovery-only. |

The Yu-Gi-Oh seed has 260 automatic families and 46,043 other supported
printings requiring explicit selection. Those are membership-policy counts,
not a claim that every family has passed camera or picker rendering tests.
The audit does not infer complete edition coverage from a supported membership.

## Verified fixes

### Pokémon: Shiny Vault numbers were not routed

The historical number parser accepted H, TG, GG and RC subsets but omitted SV.
The subset resolver likewise lacked the two SV denominator routes. All 216
bundled Shiny Vault card IDs were therefore outside this recognition path.

The correction preserves the prefix and routes only `SV…/SV94` to `sma` and
`SV…/SV122` to `swsh4.5sv`. It does not reinterpret SV as a modern set code or
promo prefix. The regression traverses each of the 94 + 122 real bundled IDs
through parsed number/name evidence, candidate-set selection and offline
identity resolution. Wrong denominators, mismatched prefixes and competing
subset evidence remain unresolved.

Evidence: the official [Hidden Fates checklist](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/sm115_web_cardlist_en.pdf)
and [Shining Fates checklist](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/swsh45_web_cardlist_en.pdf),
plus both exact bundled inventories. Changes are in `ScanParser.swift`,
`TCGdexService.swift` and `ScanParserTests.swift`.

### Pokémon: DP and HGSS promo prefixes and separated denominators

The existing promo framework omitted DP and HGSS. Exact current inventories
contain DP01–DP56 and HGSS01–HGSS25. The new definitions preserve the provider
prefix and two-digit padding in both the bundled seed and publisher input.
Tests replay all 81 identifiers, with prefix, padding and invalid-input cases.

The same review reproduced a distinct parser flaw: a space before `/` let a
fraction-shaped reading be accepted as a denominator-free promo. The parser
now rejects both adjacent and whitespace-separated denominators for every
configured promo prefix.

These descriptor changes are an application/publisher candidate. Existing
installations using a signed remote-authority registry need the normal reviewed
catalog release before they receive the added descriptors. This PR does not
claim that release was published. DP evidence includes the official
[Black Star card list](https://assets.pokemon.com/assets/cms/pdf/tcg/carddex/black_star_modified.pdf)
and exact [DP](https://api.tcgdex.net/v2/en/sets/dpp) and
[HGSS](https://api.tcgdex.net/v2/en/sets/hgssp) provider inventories.

### Pokémon: Hidden Fates Shiny Vault had an incorrect Normal finish

All 94 retained `sma-SV1` through `sma-SV94` rows used a generated Normal
placeholder. The official foil checklist and 94 exact product/collector joins
establish Holofoil for this bounded cohort. The evidence is retained in
[the reviewed crosswalk](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/hidden-fates-shiny-vault-review.json),
including source receipts. Direct market sources are
[group 2594 products](https://tcgcsv.com/tcgplayer/3/2594/products) and
[prices](https://tcgcsv.com/tcgplayer/3/2594/prices).

The existing reviewed-variant mechanism now returns Holo for these exact IDs.
The existing read-time checklist projection repairs bundled and persisted
placeholder slots without rewriting source resources, manifest fingerprints
or permanent IDs. Unsupported IDs and the other Shiny Vault set are untouched.

Regression coverage checks all 94 cards, live-style placeholder records,
offline/persisted slots, idempotence, finish provenance and pricing. A real
Holo quote can be used; an old Normal quote cannot price Holo. A missing Holo
quote stays missing. Explicit user/import/printed-label finish evidence is not
silently replaced by the automatic saved-finish repair.

### Pokémon: Celebrations Classic used provider IDs that were not printed on cards

The 25-card checklist uses synthetic `CC001`–`CC025` collectors. Physical
Celebrations Classic cards retain original printed numbers. The registry
previously had no exact membership crosswalk for this set, so a recognizable
original footer did not expose its Celebrations alternative.

The PR adds **24 reviewed fraction memberships**, preserving both original and
reprint IDs. Each was checked against the official checklist, exact product
image, source product number and original catalog identity. The
[25-row evidence ledger](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/celebrations-classic-membership-review.json)
retains each image/source hash and marks the exception explicitly. The inspected
product images were available at 200 pixels wide; unavailable high-resolution
images are not claimed as inspected.

Birthday Pikachu (`CC008`) physically prints standalone `24`. Its supplier
field says `24/53`, which is not its printed footer. It receives no invented
fraction route and remains in the existing Browse checklist. Supporting its
scan still needs a reviewed denominator-free identity path.

Twenty-three originals are present offline; the original POP Series 5 Umbreon
is absent. Both offline and live automatic resolution now refuse to select a
sole reviewed Celebrations reprint from an incomplete or contradictory family.
A full family preserves the existing original/reprint choice, and an explicit
selection still resolves the exact reprint. Tests cover all 24 mappings,
removing each original, incomplete live directories/rows, contradictory titles,
wrong denominators and exact selected-card identity.

Base Set physically says “Impostor Professor Oak,” while Celebrations says
“Imposter Professor Oak.” A whole-title alias conservatively retains both
printing choices for either spelling; one OCR e/o substitution cannot choose
an edition. Longer titles are not affected. The bundled and publisher
memberships have a parity regression; signed remote-authority adoption remains
a separate release step.

### Magic: incomplete promo evidence could select an ordinary printing

`Tarkir Dragonfury` participated in exact promo matching but disappeared when
the number/denominator did not match. For example, `136/264 C Tarkir Dragonfury`
with `DTK EN` fell through to the ordinary DTK identity. Splitting the release
label between adjacent OCR observations also bypassed the initial guard.

Recognition and rejection now use the same bounded three-observation windows.
Positive promo evidence without a reviewed complete mapping blocks fallback.
The six existing PLG20/PTKDF mappings and ordinary unmarked DTK remain covered
by regressions. Wrong numbers, denominators, foreign language, missing fields
and split labels are included.

### Magic: one modern Rafiq printing fell between era-based routes

Rafiq of the Many ALA 250 is a 2022 printing inside a set whose date is 2008.
Its inspected image prints `250 M` / `ALA • EN`. The modern directory filter
excluded its set, while historical resolution excludes its modern printing
date. Both the retained record and [the exact current provider response](https://api.scryfall.com/cards/ala/250/en)
identify UUID `2e181878-d9fb-44d5-98ce-2899793ab2e7`.

The recognition adapter adds an exact exception for regular English ALA 250,
with adjacent ALA/EN evidence, no contradictory language and no denominator.
Other ALA collectors and original `173/249`-style cards do not gain blanket
modern support. Tests cover OCR forms, competing identities, geometry, foreign
language, suffix/token/denominator rejection, and exact provider validation of
printing UUID, set, collector, language and release era.

### Magic: imported List printings were matched by name instead of exact collector

List/ULST import enrichment discarded the collector number and requested one
name/set match. That is not a complete printing family. A current exact
reproduction for Entreat the Angels returns PLST `AVR-20` by name, while
`MM3-4` is a different printing with different finish support. The retained
snapshot contains both UUIDs:
`0c8e0b8f-fd4a-46fb-8eac-7be0dad65c26` and
`0659529d-1328-47de-9910-cce5b744aedf` respectively.

Enrichment now preserves exact composite collectors and uses an existing valid
Scryfall UUID when available. Plain-number/name-only reprint rows without an
exact UUID stay unresolved. Bounded requests require one response matching the
exact key, English physical-card scope, name, set and collector. Duplicate,
conflicting, missing and out-of-order responses cannot choose another printing.
Ordinary numbered imports remain supported.

The metadata version advances so still-unresolved rows can retry. This is not
a speculative migration of already-enriched rows: an earlier wrong attachment
with complete metadata needs a separate evidence-backed repair. Tests cover
the real two-printing collision, List/ULST and ordinary imports, exact UUID
routes, partial responses and contradictory provider data.

### Magic: the compiled startup vocabulary lagged the reviewed seed

SLZ was the sole scan-enabled seed code missing from the compiled vocabulary.
The exact current SLZ 1 image prints `C 0001` / `SLZ • EN` with no denominator;
the provider response, retained audit and seed agree. Adding only `(SLZ, nil)`
restores startup parity without inventing a printed size. A bidirectional
seed/snapshot assertion and footer regression keep this difference visible.

This is readiness for the reviewed release: the
[official shipping notice](https://magic.wizards.com/en/news/announcements/an-update-on-the-zeta-set-sale)
estimates North American shipping from November 5, after this audit date. The provider's September 2 release field
does not establish that customers already possess delivered cards. Sources:
[set](https://api.scryfall.com/sets/slz) and
[exact card](https://api.scryfall.com/cards/slz/1/en).

### Yu-Gi-Oh: legitimate code families failed the shared catalog boundary

Three supported printed-code families span more than one canonical card:
`CH02-EN004`, `LOD-050` and `OP09-EN026` (eight retained printing rows in total).
The game adapter returned their whole family with the first card's canonical
summary. Shared validation required every candidate to have that summary ID,
so it rejected the outcome before a user could select a printing.

The summary now has a temporary `yugioh-code:…` group ID for a multi-canonical
code family. Each choice retains its actual canonical and printing IDs. The
shared gate accepts this group only with exact Yu-Gi-Oh code, namespace,
language, suppression key and canonical-UUID evidence. Existing current
generation/membership validation remains in the resolver; no such family
becomes automatically selectable.

The new native sweep traverses every valid bundled code through the shared
catalog. Focused checks preserve all three conflict families, resolve their
choices, reject forged/stale choices and prohibit automatic selection.

A second recognition fix preserves conflicting passcode evidence. Previously
one matching passcode could erase a contradictory second reading. All observed
passcodes must now belong to the known family when known passcodes exist.
Repeated matching readings remain valid.

### One Piece: import could reinterpret an unknown item kind as a raw card

The CSV parser keeps an unknown source `item_kind` but projects its enum to
raw card. The One Piece adapter ignored the retained source value. Consequently,
an otherwise exact row with `item_kind=future-kind` could become raw ownership.

The adapter now requires missing or explicitly raw source kind and rejects
contradictory graded, Magic and standalone JustTCG metadata. A direct adapter
language guard supplements the shared parser's existing non-English rejection.
Valid English aliases and existing exact UUID/finish/key rules are preserved.

The new CSV-to-apply regression verifies rejected rows create no collection,
inventory, activity or price-observation writes. Direct adapter tests cover
accepted English aliases and contradictory retained metadata. This is not a
claim that ordinary foreign-language CSV previously bypassed the shared parser.

### Lorcana: ordinary ingestion bypassed review boundaries

The ordinary 1–204 / None+Silver branch accepted its finish policy before
checking source/footer set agreement, distribution, layout, rarity, duplicate
finish declarations or image scope. Later sets with denominator 204 could enter
without the explicit later-expansion review option. A selected marketplace
group from another original expansion could also match.

The ordinary rule is now restricted to its reviewed sets 1–8 and exact evidence
shape. Marketplace group IDs are bound to the corresponding expansion. Later,
Disney100 and Enchanted paths retain their separate rules.

Before the fix the new negative tests produced 14 failing subcases. Afterwards
all 27 Lorcana tests pass, including a preservation comparison of all 1,748
adopted mapped printings: 1,616 ordinary and 132 Enchanted. Their UUIDs, finishes,
provider lanes and groups remain unchanged. No discovery row was promoted and
no catalog signature or identity ledger was regenerated.

## Remaining issues and closure criteria

| Priority / issue | Exact evidence and consequence | Required closure |
| --- | --- | --- |
| High: Magic original-footer reprints | Inspected PLST `2X2-208` Elsha and PAFR `100s` Ebondeath retain original `2X2 208/331` and `AFR 100/281` footers. The ordinary route can select the original printing. | Reviewed alias families keyed by printed identity; explicit original/reprint choice unless sufficient reviewed stamp evidence exists; current family validation and finish preservation. |
| High: One Piece signed-catalog lag | Three verified alternatives for OP01-001 / OP01-120 exist only in the review corpus. The installed owner seed has one standard printing for each number, so its current owner-directed singleton policy can select standard. | Adopt a reviewed signed release with the existing permanent alternate IDs and trusted pins; verify the actual installed bundle presents the choice. Do not bypass signing or silently reverse the owner's selection policy. |
| High: Pokémon finish data beyond the reviewed fixes | Raw snapshot contains 39 all-Normal set entries / 4,421 cards. Excluding the already-reviewed six Yellow A cards and this PR's 94 Shiny Vault cards leaves 37 sets / 4,321 cards needing finish review. This is a risk cohort, not 4,321 proven errors. | Independent per-card physical finish evidence and exact market joins; reviewed corrections only; provenance and saved-data regressions. |
| Medium: Pokémon denominator-free historical subsets | 38 IDs across AR (9), SH (12), SL (11) and RT (6) lack a supported denominator-free historical identity route. Celebrations Birthday Pikachu is a separate confirmed standalone-number case. | Model the actual printed identifiers without fabricating denominators; retain name/set ambiguity and test every reviewed member. |
| Medium: Lorcana discovery exceeds adopted physical coverage | 1,833 discovery-only rows: 1,460 in sets 9–14, 34 in sets 1–8 and 339 in other scopes. | Review physical size/stamp/distribution/finish universes and exact product joins; use the existing approval/identity pipeline. |
| Medium: One Piece held cards | 221 canonical numbers have no verified printing; the owner seed includes 224 provisional and 31 conflicted printing records. | Resolve provenance/conflicts before verified membership; retain permanent IDs and do not equate canonical-card count with addable coverage. |
| Medium: signed-descriptor activation and freshness | Pokémon added descriptors are not an already-published remote release; Magic remains `legacy-live`; retained data dates differ. | Verify normal signed publication, installed adoption, new-set latency, empty/warm offline behavior and provider-outage recovery in their existing release workflows. |
| Separate acceptance: physical scanning | Deterministic OCR text and provider fixtures establish logic, not glare/rotation/crop performance or held-out card accuracy. | A dated physical-card corpus covering ordinary, promo, subset, reprint and finish distinctions, with wrong-identity rate measured separately from unresolved scans. |

The exact One Piece alternatives awaiting adoption are:

| Number / printing | Existing reviewed UUID |
| --- | --- |
| OP01-001 alternate artwork | `66334969-8762-4141-b78b-2fed7165a53c` |
| OP01-120 alternate artwork | `915c6133-40be-4e95-9287-23014d5f0ec0` |
| OP01-120 manga artwork | `1eb727b5-eadd-4e50-89c6-a8bd7b7a05c8` |

Magic's broader retained data contains 291 List/base joins and 1,922 promo/base
joins. These are discovery candidates, not individually verified physical
aliases and not permission to generate universal `PLST`, `s` or `p` mappings.
Wizards documents the original-format reprints and distinguishing stamp in
[Unraveling Mystery Booster](https://magic.wizards.com/en/news/feature/unraveling-mystery-booster-2019-11-14)
and [The List for Wilds of Eldraine](https://magic.wizards.com/en/news/announcements/whats-new-on-the-list-for-wilds-of-eldraine).

There are also 74 provider-directory Pokémon entries absent from the retained
offline snapshot in the dated comparison; 15 are digital Pocket. The other
59 need classification and exact physical-card reconciliation. They are not
59 proven missing physical sets. Low manifest display counts likewise do not
establish missing payload rows. See the generated ledger for each distinction.

## Verification and repeatability

The PR adds a native CI selection for scanner, catalog, printing, finish and
import regressions and a separate offline ingestion/census job. It does not
invoke publication jobs. Native verification status and exact final counts
will be recorded here after the final PR revision is tested.

Repeat the offline work from the repository root:

```sh
python3 -m unittest discover -s scripts/tests -v
PYTHONPATH=scripts python3 -m unittest discover -s scripts/fixtures/yugioh -v
python3 scripts/audit_catalog_coverage.py --repo . --output /tmp/catalog-coverage
```

The census is deterministic for the same input bytes. It fails for malformed
structural data; intentional holds and unresolved review gaps remain visible
in the ledger without being mislabeled as test failures. A green census does
not mean complete physical coverage. Newly discovered card families still need
independent evidence and regression cases before changing membership or finish
authority.

## Related authorities

- [Earlier coverage research](card-coverage-gaps-and-research.md) and
  [October 15 evidence](../research/catalog-variant-coverage-2026-10-15/README.md).
- [Pokémon catalog updates](../plans/automatic_pokemon_catalog_updates_plan.md).
- [Magic publication](../plans/magic_catalog_key_handling_runbook.md) and
  [historical recognition](../plans/magic_historical_recognition_plan.md).
- [One Piece implementation](../plans/one_piece_code_implementation.md) and
  [release acceptance](../plans/one_piece_release_acceptance.md).
- [Lorcana implementation](../plans/lorcana_code_implementation.md).
- [Yu-Gi-Oh implementation](../plans/yugioh_code_implementation.md).
