# Signed catalog artwork follow-up

**Status: three set-artwork input pins validated; unsigned and unpublished.**
Reviewed 2026-11-02 (native run timestamp 2026-11-03 UTC), checkout
`9413e906cab65c1d8c61882d8eb6f137bf44617e` plus preserved local changes.
This corrects the [Jumbo cohort report](../pokemon-jumbo-products-2026-11-02/README.md)
and its earlier raw-content review hold.

## What the five content flags actually meant

Comparing signed revision-19 descriptors with both native candidates shows
**unchanged `providerFingerprint` values for all 33 existing sets**, including
`30th-c`, `bwp`, `me02`, `mep` and `smp`. The earlier report incorrectly called
these raw provider-content fingerprint changes. The publisher's broader
content classification also includes enriched artwork metadata.

[ProviderFingerprint.swift](../../../PokemonCatalogCore/Sources/PokemonCatalogCore/ProviderFingerprint.swift)
includes the physical variant flags, detailed type/subtype, stamp, foil, size,
variant ID and language inputs. Publisher artwork enrichment is excluded.
Matching fingerprints support an unchanged consumed variant input for this
comparison; they do not establish worldwide completeness or marketplace-price
correctness. Marketplace handles and quotes are outside this fingerprint.

| Set | Earlier candidate versus revision 19 | Latest native candidate |
| --- | --- | --- |
| `30th-c` | 30 card-art mappings and three fallback URLs omitted; logo/symbol changed | All 30 mappings and fallback URLs retained; logo/symbol explicitly pinned |
| `bwp` | Three card-art mappings omitted | Descriptor unchanged; all three retained |
| `me02` | Symbol URL changed | Same verified URL explicitly pinned |
| `mep` | 40 card-art mappings and three fallback URLs added | Same addition retained |
| `smp` | 64 card-art mappings omitted | Descriptor unchanged; all 64 retained |

No numbered card IDs were added or deleted in these five sets. Only 40 MEP
numbered summaries changed, each in `imageURL`. The latest normal native run
reported `secondaryProviderAvailable: true`; its successful enrichment recovered
the 97 mappings omitted by the earlier run. This demonstrates source-availability
sensitivity, not new physical cards or a repair to card recognition.

## Changes and verified public assets

The only input changes in this follow-up use existing authoring fields:

- `30th-c.logoURL`: `https://assets.tcgdex.net/en/me/30th/logo.png`
- `30th-c.symbolURL`: `https://assets.tcgdex.net/en/me/30th/symbol.png`
- `me02.symbolURL`: `https://assets.tcgdex.net/en/me/me02/symbol.png`

All three returned HTTP 200 with PNG content. The Classic Collection already
has signed parent `30th`; this preserves its existing parent-artwork relationship.
No card membership, variant, price binding, scanner, portfolio or publisher
algorithm changed. The [receipt](receipt.json) records the exact three-field
input diff, asset hashes, fingerprints and candidate hashes.

The two-source rule for physical-item changes is unaffected: no physical item
was added, removed or modified in this artwork-only follow-up. The existing
19 Jumbo and one Eevee Cosmos supplements remain byte-for-byte equal as parsed
authoring objects.

## Card-image review queue

[Legacy probes](legacy-image-probes.json) record 194 thumbnail/high-image URLs
for the 97 affected card identities. Every request returned HTTP 403 in this
environment. Separate plain GET controls for one Scrydex and one Pokémon TCG
image URL also returned 403, while TCGdex and TCGplayer control images returned
200. This does not prove these URLs fail on every device. The final native
candidate retains all 97 mappings; URL availability remains a separate concern.

[Replacement candidates](replacement-candidates.json) record fresh TCGdex
identity receipts for all 97 cards, with separate TCGplayer product metadata
for 94. Their set/name/number joins were reviewed against the existing catalog
identities; Classic Collection physical numbers use the previously reviewed
membership table rather than the provider's synthetic ordinal. All 94 candidate
marketplace images downloaded and decoded successfully; hashes and dimensions
are in [image probes](replacement-image-probes.json). This is image availability
and metadata evidence, not visual inspection of every image or new price evidence.

No replacement was installed. The three BW objects lack an exact product join
in this receipt (`bwp-BW04`, `bwp-BW05`, `bwp-BW96`). The current authoring input
also lacks a per-card artwork field; adding that publisher behavior goes beyond
these existing-field data pins. Do not hand-edit a candidate payload or invent
a variant to carry an image. Future replacement work should review that limited
publisher support, image identity/quality and source-use requirements separately.

## Validation and limits

The normal native publisher completed `validate --live true` against the
signature-verified production revision 19 with exit code zero. The unsigned
revision-20 candidate contains **75 sets, 6,675 numbered cards and 20 reviewed
supplements**, classified as protected `newSet`. Its remaining content flags
are `30th-c`, `me02` and `mep`; authority changes remain `30th`, `sv03`, `svp`.
Generated artifacts reside at `/Volumes/T7/CodexBuilds/CardScannerArtworkPins20261102`.

No app/Core source changed in this follow-up, so their prior test milestones
were not rerun. The normal live publisher validation is the relevant data check.
No signing secret, production signature, deployment, commit or push was used.
Physical-camera, paid-pricing, PAF 054 alternate-face canonical routing, remaining
historical gaps and exhaustive English-printing coverage remain open.
