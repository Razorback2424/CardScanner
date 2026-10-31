# One Piece catalog and scanner integration

**Status:** current catalog design; implementation authorized and in progress in
the isolated `one-piece-integration` worktree; production support disabled.
**Reconciled:** 2026-10-04 against uncommitted implementation at base `69c714f`.
The original source/design review used `dd2a1e3` and its working tree; subsequent
code status and delivery priorities live in the
[implementation ledger](one_piece_code_implementation.md).
**Draft provenance:** owner-supplied audit drafted more than a month earlier,
including an explicitly dated 2026-08-26 provider comparison. Its missing citation
markers were not source URLs. Historical counts and forecasts below are retained
as supplied claims, not independently reproduced evidence.

## Decision and scope

Plan English One Piece support around official discovery, multiple-source
reconciliation, and permanent app-owned physical-printing IDs. Bandai discovers
canonical cards and artwork; Limitless helps reconcile physical releases;
TCGCSV/TCGplayer adds broad market-product discovery; Scrydex remains a candidate
enrichment and raw-market provider. No single vendor's
catalog, naming scheme, or expansion count defines completeness.

Identification must remain independent of pricing. A new card can be represented
without a market quote. A printed One Piece number identifies the canonical card,
not necessarily its physical release, artwork, stamp, or finish. Unknown physical
identity must never receive a base-card price or become a confidently owned
parallel through inference alone.

Initial scope is English numbered raw cards. DON!! has a separately gated visual
catalog. Graded One Piece pricing, sealed products, non-English recognition, and
automatic optical finish assignment are separate follow-ups. Do not promise
day-one coverage or production readiness until the relevant corpus, rights,
provider, device, and rollout evidence exists.

## Architecture contracts and current adaptation

The 2026-10-04 code audit includes tracked and untracked work. Shared identities,
runtime adapters, One Piece core/local projections and fixture flows now exist.
The real review registry now contains 2,745 printing records (2,490 verified), with
dated source observations and retained hashes; synthetic fixtures still cover
some stress distinctions. This does not establish full physical completeness.
Recovery revalidation and compact Pokémon/Magic-style printing choice now exist.
The owner-rejected verbose picker is historical. Real scanner/device and
collector-distinguishability acceptance remain open; retain separate printing
and finish stages.
Remaining write boundaries and actual seed/publication/device/sync acceptance
remain open.
The implementation ledger is the current execution/status authority; this table
retains the design contract without treating earlier source locations as current.

| Current source boundary | Adaptation of the older draft |
| --- | --- |
| [`CardGame`](../../TradingCardScanner/Models/CardGame.swift), [`ScanIdentifier`](../../TradingCardScanner/Services/ScanParser.swift), and [`ResolvedCatalogCard`](../../TradingCardScanner/Models/ResolvedCatalogCard.swift) are generic values with legacy bridges | Retain single-string game encoding and existing Pokémon/Magic keys; One Piece uses its registered adapters. Audit remaining central legacy routing before claiming the next game requires no central edits. |
| [`RecognitionProfile`](../../TradingCardScanner/Services/CardScanner.swift) aggregates registered recognizers | Retain cross-game/internal ambiguity rejection and language evidence; no game toggle or confidence contest. Real-card validation remains open. |
| [`CardCatalog`](../../TradingCardScanner/Services/CardCatalog.swift) dispatches registered catalog adapters alongside legacy paths | One Piece candidates come from its validated local release, not per-scan upstream requests. Canonical-number validation precedes physical-printing choice; incomplete coverage must not manufacture uniqueness. |
| [`VariantResolver`](../../TradingCardScanner/Services/VariantResolver.swift) uses deterministic catalog evidence, applicable user locks, and validated printed-label evidence | Optical similarity may rank candidate artwork/printing choices. It cannot silently decide an ambiguous finish, stamp, or identical-art reprint. The draft's “high confidence → auto-select” is not the current acceptance contract. |
| [`CollectedCard`](../../TradingCardScanner/Models/CollectedCard.swift) preserves legacy keys, physical variants and provenance, and now retains unknown game strings | Keep stable One Piece UUID identity without rekeying existing games or renaming the SwiftData entity. Old installed clients still have unsafe fallback behavior; preserve the creation/sync gate and close remaining unsupported-row mutation paths. |
| [`PriceRecord`](../../TradingCardScanner/Models/PriceRecord.swift) keys by game, printing, variant, and applicable Magic treatment | Map One Piece prices to exact local printing/physical-variant identities. Market IDs stay provider mappings, separate from ownership. Preserve existing freshness and unavailable-price semantics. |
| Pokémon/Magic stores share signed storage mechanics; One Piece has its own core, registry, coordinator and bounded update client | Preserve separate schemas, trust keys and physical identities. Signing/preparation and fixture activation do not establish a reviewed real catalog or production delivery. All shared-site deployments must preserve the new namespace. |
| [`shared_pricing_cache_plan.md`](shared_pricing_cache_plan.md) is a future backend with independent gates | This plan does not install a Scrydex backend or authorize price redistribution. Reconcile provider access and retention with [`browse_pricing_coverage_plan.md`](browse_pricing_coverage_plan.md) before selecting the price path. |

The signed-catalog precedents are
[`automatic_pokemon_catalog_updates_plan.md`](automatic_pokemon_catalog_updates_plan.md),
[`magic_catalog_key_handling_runbook.md`](magic_catalog_key_handling_runbook.md),
[`PokemonCatalogCore`](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogContract.swift),
and [`MagicCatalogCore`](../../MagicCatalogCore/Sources/MagicCatalogCore/CatalogContract.swift).
Their implementation and rollout statuses remain separate; this design does
not mark their open operational gates complete.

## Source roles and evidence boundary

| Source | Planned responsibility | Constraint |
| --- | --- | --- |
| Official English Bandai catalog and announcements | Canonical numbers, official metadata, artwork discovery, release/event evidence | A source artwork occurrence is not a permanent physical-printing identity; official availability does not grant hosting or commercial rights. |
| Limitless | Expected physical prints, product appearances, release reconciliation, discrepancy checks | Use during ingestion/review through permitted access. Product rows may group distinctions more coarsely than collector treatments. |
| TCGCSV / TCGplayer category 68 | Broad market-product discovery, exact source names, product/group aliases and optional source price lanes | Retain paced daily source captures and explicit inventory gaps. A product is not an app-owned physical UUID, and this export lacks SKU-level language/printing/condition identity. |
| Scrydex | Candidate variant vocabulary, variant imagery, cross-expansion associations, exact raw quotes | Enumerate paginated card/search results and reconcile them independently. Expansion totals and variant names are not completeness proofs or IDs. |
| App-owned registry | Permanent printing IDs, source aliases, reviewed joins, unresolved distinctions, release history | Identity persists across URL, vendor-name, and source-index changes. |

A limited public-source check on 2026-10-03 establishes the following, not a fresh
all-history coverage audit:

**2026-10-04 discovery update:** the [stress review corpus](../../OnePieceCatalogCore/ReviewCorpus/english-stress/README.md)
now includes a reproducible category-68 capture: 7,408 review rows across 87 groups,
with one empty presale inventory explicitly incomplete. This supersedes the earlier
absence of broad market discovery, not physical completeness or rights gates.
Thirty-one market observations cover Shanks/Nami/Luffy; seven illustration
correspondences and a missing Nami thumbnail are recorded separately. Current
digital Bandai block-1 footers are not proof of original physical release footers.
Do not promote source product rows or artwork matches to verified printing UUIDs.

- The [official English card list](https://en.onepiece-cardgame.com/cardlist/)
  remains an accessible discovery source.
- [Scrydex's card schema](https://scrydex.com/docs/onepiece/cards) documents
  card-level printing associations and collectible variants with their own
  printing associations, images, and prices. Schema capability is not proof that
  every real printing has a correct row.
- [Limitless's Shanks entry](https://onepiece.limitlesstcg.com/cards/en/OP01-120)
  provides a concrete printing-reconciliation source.
- The [optcg-data repository](https://github.com/michalkiral/optcg-data) documents
  official-source scraping through vegapull and separate alternate-art entries.
  Its tooling is extraction evidence, not a production data license or dependency.

Recheck source terms, authorized automation, attribution, commercial display,
image download/hosting, derived recognition artifacts, retention, and pricing
redistribution before ingesting or publishing production assets. The draft's
image-cache permission and raw/graded coverage claims require current provider
verification. No authenticated Scrydex contract or complete live feed was tested
for this documentation change.

## Identity and reconciliation contract

Model four distinct concepts:

1. **Canonical card:** game, language, printed number, and game metadata.
2. **Artwork:** an app-owned artwork identity with source occurrences and image
   fingerprints. Artwork can be reused across physical printings.
3. **Physical printing:** permanent UUID plus canonical card, language/region,
   artwork, release/distribution, treatment, stamp, block/copyright details, and
   evidence for applicable finishes. Distinct releases remain distinct when
   artwork is identical. Store multiple product appearances when supported by
   evidence; do not invent a new physical identity for every vendor product row.
4. **Market mapping:** provider, product/variant IDs, market, currency, condition,
   and finish qualifiers for that printing. Several SKUs can refer to one
   printing. A serialized prize treatment is a printing distinction; an individual
   serial number belongs to an owned instance, not a new catalog UUID per copy.

UUIDs are assigned once and kept in a durable registry across ingestion runs.
Bandai `_pN` suffixes, Scrydex variant names, image URLs, and marketplace product
IDs are namespaced aliases with provenance. Retain aliases and explicit reviewed
supersession records for corrections. Never silently merge owned records or
discard user-confirmed distinctions when correcting a provider join.

Do not duplicate the same distinction in both the UUID and variant layer. A
fixture-driven schema review must decide which physical finish choices remain
under a printing versus which treatments/releases require separate UUIDs, then
verify consistent collection, Browse, export/import, and price keys.

For each source observation, retain source identifier, URL, observed date,
language, payload/content fingerprint, and join evidence. Keep catalog
reconciliation, scan resolution, and market mapping as separate statuses:

| Catalog status | Meaning and allowed behavior |
| --- | --- |
| Provisional | Official discovery with incomplete physical-release reconciliation. May show a canonical candidate or explicit provisional choice; cannot pretend all possible prints are known. |
| Verified | Reviewed evidence agrees on the specific physical printing and required qualifiers; at least two corroborating signals are preferred. |
| Conflicted/quarantined | Contradictory image, release, stamp, or identity evidence; excluded from automatic physical resolution and exact quoting until reviewed. |

An unverified review printing may have an empty `supportedVariantIDs` list when
its finish evidence is unresolved. Do not invent a normal/foil finish to satisfy
the schema. Verified printings must have at least one registered supported
variant. Unresolved printings remain in the candidate universe and block
automatic uniqueness; learning a finish does not allocate a replacement UUID.
Promotion to verified status is a protected publisher review change.

Rules version 2 requires a `finish` review entry covering every supported finish
of a verified printing. A catalog observation may specify one `finishVariantID`
or a JSON string array in `finishVariantIDs`, but cannot supply both. Evidence
must agree with the canonical number, language and release. Market observations,
watermarked renders and physical-card photographs alone cannot authorize a
finish. Missing or contradictory evidence rejects the candidate; rules-version-1
releases require evidence migration and protected re-publication before activation.

Two websites repeating the same Bandai image are not automatically independent
evidence of a stamp, finish, or distribution. Verification requires evidence for
the actual distinction. A verified catalog row still does not prove which
printing the camera sees. An exact market mapping can exist without a price;
a vendor quote can exist without a sufficiently exact mapping and must then
remain unusable for that owned object.

## Ingestion and release pipeline

```text
Bandai English discovery + product/event evidence
                      ↓
normalized observations + image evidence
                      ↓
app-owned reconciliation registry
       ← Limitless print/product evidence
       ← Scrydex variant/image observations
                      ↓
validated candidate: stable IDs + complete candidate indexes
                      ↓
classified, reviewed when required, signed release
                      ↓
on-device catalog activation + last-known-good fallback
```

Discover additions independently of pricing and vendor aggregate counts. Crawl
permitted paginated collections to exhaustion and compare source inventories;
distinguish incomplete pagination, provider failure, and deleted observations
from real catalog removals. Use content fingerprints to detect changed cards,
images, source aliases, and previously known promos, not only newly named sets.

Download permitted reference assets and calculate SHA-256 on exact bytes. Add a
versioned perceptual hash, and embeddings only if justified by measured accuracy,
storage, and device performance. Exact hashes detect unchanged bytes; resized,
watermarked, cropped, or recompressed images require other evidence. Similarity
generates join candidates, not proof of physical equivalence. Compare stamp,
footer, copyright, and block regions separately; preserve identical-art reprints.

Define a One Piece release contract with monotonic revisions, pinned game-specific
public keys, asset integrity checks, schema compatibility, referential integrity,
and deterministic candidate indexes. Bundle an offline seed; persist validated
current/previous releases with atomic activation. Failed refreshes retain the
last-known-good catalog and cannot alter an in-flight scan's immutable snapshot.
Size the compact index and reference assets from the corpus; “2–10 candidates”
from the draft is an expectation, never a hard truncation that drops rare promos.

New games, new sets, physical-ID joins/splits, changes to candidate possibilities,
scanner authority, and unknown changes require protected review. Permit automatic
publication only for an explicitly approved content-only allow-list. Source
freshness never bypasses signature validation, identity review, or rights gates.
Use separate One Piece signing custody and rollout configuration; do not reuse
Pokémon/Magic secrets or widen their existing publication allow-lists.

## Scanner and product integration

```text
combined recognition profile → confirmed canonical identifier → local candidates
    → deterministic physical evidence → exact printing + allowed physical variant
    → unresolved artwork/release/stamp/finish → one-tap reviewed choice
    → incomplete or conflicting catalog → Needs attention, without ownership guess
```

Retain rolling confirmation, physical-card latch, speculative lookup validation,
stale-result cancellation, raw/slab separation, and ownership provenance. A
One Piece footer number can narrow artwork choices but cannot establish a
cross-product reprint. Finish Lock must only apply where the selected exact
printing supports it, and must not answer a release/stamp question.

Stage image comparison as candidate ranking first. Automatic artwork recognition
requires a separately reviewed, measured acceptance contract; it must still leave
unresolved physical distinctions for the user. Capture why the card, printing,
and variant were resolved. Show informative thumbnail/release/treatment choices
instead of exposing `_p4` or opaque vendor labels.

Connect Browse set/product membership, collection grouping, set completion,
manual lookup/correction, unresolved-scan recovery, price totals/history,
CSV/import/export, slab mappings, and accessibility through the same stable IDs.
Review every game switch and CloudKit compatibility path. Older-client handling
must preserve unknown game rows instead of treating them as Pokémon. Leave
existing Pokémon/Magic identity and price keys intact.

DON!! needs artwork-based discovery and a separate index, parser/recognition
entry point, ambiguity handling, and fixture/device evidence. It must not enter
the ordinary footer-number path through invented IDs. Scope and ship its visual
recognition separately from numbered-card support.

## Pricing contract

Scrydex is a candidate, not a selected production entitlement or installed app
provider. Compare its current exact raw coverage, terms, costs, quota behavior,
credentials, and permitted device/server retention with the current pricing
architecture before choosing a path. Do not assume the existing JustTCG key
model, shared cache, or Pokémon bulk-provider arrangements cover One Piece.

Serve a quote only for an exact printing/variant/condition/market mapping. An
unresolved manga, serialized, stamped, or premium reprint cannot borrow the base
quote. Preserve source-update versus fetch timestamps, stale observations on
failure, unpriced counts, and separate unavailable/not-checked/failed states.
Catalog ingestion and scanning never wait for quote coverage. No graded pricing
claim or “Fair Value” methodology is established by this audit.

## Implementation slices and acceptance

The owner subsequently authorized code implementation; the
[implementation ledger](one_piece_code_implementation.md) records its current
state, audit findings and execution order. Production publication, provider
entitlements and sync activation still require their stated acceptance gates.
The original documentation-only provenance is historical, not a prohibition on
the authorized work. The 2026-10-04 audit was restricted to plan updates.

These design gates use A–H, whereas the code-level ledger uses A–N. They are
different checklists: design A maps mainly to code G; design B to code G;
design C to code F/H; design D to code C/D/E/I; design E to code A/J/K;
design F to code L; design G to code M/N; and design H to code acceptance/rollout.
Passing a fixture checkpoint in the code ledger does not close a corpus,
provider, device or operational design gate here.

- [ ] **A — Corpus and access:** establish current English inventory, dated
  source observations, permitted access/asset use, discrepancy ledger, and
  documented physical distinctions for every stress fixture below.
- [ ] **B — Identity/core:** durable registry, source adapters, reconciliation
  statuses, deterministic builder/validator, idempotent regeneration, explicit
  corrections, and no duplicate or missing physical candidate identities.
- [ ] **C — Signed delivery:** independent release schema/key pin, candidate
  classification, bundled seed, offline indexes, current/previous persistence,
  corrupted/tampered/unsupported payload rejection, atomic activation, and rollback
  rehearsal without rewriting owned identities.
- [ ] **D — Numbered recognition:** combined parser, ambiguity rejection, local
  lookup, deterministic selection and one-tap choice, latch/confirmation behavior,
  cancellation, catalog-incomplete recovery, and real-card glare/sleeve/stamp tests.
- [ ] **E — Persistence/product:** backward-compatible game decoding, collection
  and ownership identity, Browse membership/completion, correction/import/export,
  provenance, accessibility, and mixed-version CloudKit/device evidence.
- [ ] **F — Exact pricing:** selected provider contract, exact mapping fixtures,
  condition/finish isolation, expensive-parallel/base separation, null-price and
  freshness behavior, plus live-provider evidence and applicable retention rights.
- [ ] **G — DON!! and visual ranking:** separately scoped corpus, visual ambiguity
  tests, image-ranking performance/accuracy evidence, and an explicit decision
  before any new automatic optical resolution behavior.
- [ ] **H — Rollout:** focused regressions then warranted broader checks, device
  speed/accuracy/offline validation, signed baseline rehearsal, owner-controlled
  publication and release gates, and monitoring response procedure.

Measure known-corpus discovery coverage, reconciled-print coverage, exact-market
mapping coverage, scan false selection/abstention rates, candidate counts, payload
size, and cold/offline/warm latency separately. Use a reviewed denominator and
dated corpus; completeness cannot be inferred from a vendor total or price count.

## Historical audit retained as acceptance inputs

The older audit's durable finding is feasibility through reconciliation rather
than dependence on a perfect single-source catalog. Preserve these hard cases:

| Fixture | Historical supplied observation | Required validation |
| --- | --- | --- |
| OP01-120 Shanks | Limitless five main print rows; Scrydex seven labels, including non-textured manga and serialized foil | Distinguish artwork, reprint treatment, texture, serialized prize, and market SKUs without equating provider row counts. |
| ST01-007 Nami | Eight Scrydex treatments including Treasure Rare, Championship/Film Red, tournament, winner, and New Year variants | Preserve stamps/distributions and exact quotes despite a shared starter number. |
| P-001 Luffy | Eight Scrydex categories and eight major Limitless rows spanning launch/prerelease, 25th, Gift, Regional, and Fest/prize releases | Reconcile the actual releases rather than assuming equal counts imply one-to-one matches. |
| ST01-012 Luffy | Nine Scrydex treatments: foil, wanted, first anniversary, signature, championship, Treasure Cruise and third-anniversary stamps/winners | Prevent finish locks or identical art from silently choosing an event printing. |
| OP05-119 Luffy | Eight Limitless market rows across OP05 base/AA/manga, OP09, PRB01, OP11 and second anniversary | Prove base/premium isolation in ownership and pricing. |
| OP01-016 Nami; OP01-017 Nico Robin | Eight Nami rows and multiple Nico Robin promotional releases | Cross-product appearances and canonical-number reuse must survive ingestion. |
| P-106; newly discovered P-series parallels | Draft reports P-106 despite a Scrydex Promo total of 103 | Test search/pagination and aggregate lag; provisional discovery must not imply physical certainty. |
| ST32-004 and newest OP/EB/PRB/ST releases | Draft reports official discovery and different vendor release horizons | Test fresh official additions without enrichment or prices; distinguish announcement, language, and release availability. |
| DON!! | Draft identifies curated visual-image coverage outside ordinary footer recognition | Separate visual index; no invented canonical footer. |

Other historical claims awaiting a new dated audit: Scrydex's index ending at
OP16/ST30 while Limitless listed OP17/ST31–ST36 on 2026-08-26; approximately
600×838 official PNGs; variant-specific Scrydex image sizes/cache permission;
raw NM-through-damaged pricing without graded One Piece support; an independent
API claiming 4,347+ cards/51 sets; an April-2025 English vegapull-records snapshot;
and an image project listing OP01–OP17/ST01–ST36/EB01–EB04/PRB01–PRB02/P/DON
while excluding `_pN` parallels. None is a current completeness or licensing gate.

The draft estimated 99%+ canonical coverage, ~99% booster exact prints,
98–99% major premiums, 95–98% promos, and ~99% newest-set discovery via Bandai.
These are the author's feasibility estimates, not measured app acceptance
thresholds. Its comparison with Pokémon difficulty and “production-grade/strong
enough to ship” conclusion are hypotheses pending the slices above. The explicit
acknowledgment that some stamps/treatments require user confirmation is retained.

## Monitoring

On 2026-10-03 a thread automation named **Monitor new One Piece variants** was
created, active weekly on Monday at 09:00 in the configured local schedule. It
checks official English discovery first, then public Limitless/Scrydex evidence,
and reports source-dated material changes and ingestion gaps in the task thread.
It establishes its inventory baseline on its first run; this document is not
a complete current-release inventory. Scheduling is not evidence of execution.

Watch new products, changed existing card artwork, promos/events, winner stamps,
serialized prizes, anniversary/Treasure Rare treatments, premium reprints, and
DON!! designs. Report canonical number, language, distribution, source links,
first observation, source disagreement, and whether identity/image/market coverage
is missing. Access failures mean unknown coverage, not nonexistent cards.

The monitor proposes focused plan updates. It does not automatically edit app
code, ingest or publish production catalogs, buy provider access, or change
ownership/prices. Ingestion automation and production publication need their
own implementation and acceptance evidence.
