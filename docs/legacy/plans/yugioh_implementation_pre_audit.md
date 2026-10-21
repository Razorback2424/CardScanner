> **Legacy — superseded 2026-10-21.** Historical pre-audit implementation and exhaustive-coverage gates. See the [current authority](../../plans/yugioh_code_implementation.md).

# Yu-Gi-Oh! implementation and verification

**Status — 2026-10-20:** merged-review fixes are implemented; production runtime
is unavailable while no printing is acquisition eligible. See the
[review follow-up](../../research/yugioh-catalog/review-fixes.md). Earlier focused
simulator verification passed at the revision recorded below.
Bundled catalog construction succeeded, but physical edition coverage remains
unverified for all 46,504 products. Production acquisitions are quarantined.
Synthetic fixtures exercise enabled acquisition and pricing contracts; they do
not certify physical catalog coverage or real-camera accuracy.

Starting checkout: clean `main`, `81a6f2c`. The requested reviewed revision
`fd917fd583a0bd49b3439d74ee480f520c7f4800` was fetched and compared: its only
intervening change is this plan. Its complete text is preserved in the
[reviewed-plan archive](yugioh_code_implementation_reviewed.md).
This document supersedes its conflicting three-state evidence, short-token
heuristic, group edition union, permanent price whitelist, and deferred-only
verification instructions. At the time this implementation plan was prepared,
branch merges, commits and pushes were not authorized; the user's later request
now authorizes those repository operations.

## Scope and work packages

English TCG raw singles only. Bundled catalog, adapter-owned recognition, exact
TCGCSV product/edition quotes, existing printing/variant choice and Needs
attention flows. Existing collection keys, correction contracts, CSV import and
export remain authoritative. Pokémon, Magic, Lorcana and One Piece keep absent
edition evidence and their existing resolution behavior.

Excluded: slabs, graded YGO, non-English/OCG/Rush, rarity image classification,
new remote distribution/providers/marketplaces, pricing history mapping,
universal identity redesign, broad UI changes, physical-device installation,
publishing, commercial authorization and release enablement.

| Work package | Implementation |
|---|---|
| WP1 | `scripts/build_yugioh_catalog.py`, offline fixtures, alias metadata, product-specific physical edition review file, bundled seed and provenance report |
| WP2 | Generic supplemental OCR dispatch, independent edition evidence, confirmation/recovery propagation, coverage gate, bundled acquisition revalidation |
| WP3 | Seven `Games/YuGiOh/` files: catalog, recognizer, catalog/Browse/import/price adapters and runtime |
| WP4 | Explicit Xcode app/test source and seed-folder registration with `F40A`/`F40B` identifiers |
| WP5 | `YuGiOhIntegrationTests.swift` contains catalog, recognition, supplemental registry, resolution, recovery, pricing, import and workflow test classes; Python fixture tests live under `scripts/fixtures/yugioh/` |
| WP6 | This authority, documentation map/audit and root progress evidence |

## Correction 1: preserve contradictory positives

`PrintedEditionEvidence` stores `observed: Set<PhysicalVariant>` independently
of `illegible: Bool`. `.absent` is empty/false, `.unreadable` is empty/true.
No game is encoded in the shared evidence type. A conflict is an observed set
with more than one member. Merging unions the sets and ORs illegibility; it is
associative, commutative and idempotent. A later clean reading can improve an
illegible-only result; it cannot remove either positive side of a conflict.

Evidence is excluded from suppression identity. Confirmation accumulates it
even when frame counts age out. Failed OCR clears confirmation counts while
retaining edition evidence. Explicit encounter reset clears the accumulator;
confirmed subjects carry their evidence into the request and recovery record.
For unconfirmed cards, a successfully read empty band sustained for the latch's
two-second exit interval clears evidence before another physical card arrives.
Failures interrupt that timer. Disk/runtime recovery merges union their evidence.
Retries, printing selection, unresolved merges, historical/slab subject copies
and tagged persistence retain it. Existing games default to `.absent`.

Tagged JSON uses `kind`, sorted `variants` IDs and `illegible`. Missing legacy
record evidence means absent; unknown variants or tags mean illegible and
retain all recognized positive IDs. Conflict always enters Needs attention,
including singleton First, Limited and Unlimited catalogs. Neither a clean
frame, a catalog singleton nor an edition lock resolves a known conflict.

There is no implicit conflict-clearing retry. Start a new physical encounter
after removing the unresolved card to obtain fresh evidence. The original
Needs attention record keeps its evidence until deliberately dismissed.

## Correction 2: conservative edition parsing

Read edition markers only on the left footer or historical left under-art
band, in valid lines at most 40 UTF-16 units long. Accept digit-led `1st`, `1t`
or `1\"` followed by EDITION as First. Accept LIMITED and the unambiguous
four-or-more-character fragments LIMI/LIMITE/IMITED/MITED/ITED as Limited.
Bare EDITION, LIM/MIT/ITE, T/S/I and other ambiguous fragments are unreadable.
The old contains-I/T/S rule is removed. Absence never implies Unlimited.
Two positive classifications, on one line or across frames, retain conflict.
Synthetic OCR tests validate rules only; real-camera calibration remains open.

## Correction 3: physical editions and coverage are separate from prices

Each seed printing stores:

| Field | Meaning |
|---|---|
| `e` | Independently supported physical edition IDs for this exact product |
| `ec` | Independently verified completeness of that physical edition universe |
| `ee` | Supporting review reference; required for verified coverage |
| `pe` | Edition lanes observed in the build's price response, including null prices |

`scripts/yugioh_physical_editions.json` is a bounded product-ID override
mechanism with `editions`, `complete` and `evidence`. It is currently empty;
the fetched feeds do not independently establish physical completeness.
No edition union is applied across groups. No edition is inferred from a
missing stamp, another product's lane, a lock, or absent price rows. Unknown
coverage permits empty `e` and enters quarantine. No persisted unknown-edition
ownership identity is introduced. Verified rows require nonempty `e`, a review
reference, and agreement with observed product lanes. A valid physical edition
may be absent from every price row, including the entire group's response.

`VariantEvidence.physicalCoverageVerified` defaults to true for existing
adapters. YGO supplies its verified product coverage. Both the generic gate
and resolver prevent locks/singletons from bypassing false coverage. The YGO
catalog adapter rejects unverified acquisition, correction, Browse and import
resolutions rather than showing a one-option prompt with missing alternatives.

### Decision table (gate before the existing resolver)

| Coverage | Edition evidence | Outcome |
|---|---|---|
| Unknown | Any, including lock or singleton | Needs attention; no write |
| Verified | Conflict | Needs attention; no write |
| Verified | Positive edition absent from product | Needs attention; no contradictory one-option prompt |
| Verified | One supported positive edition | Resolve printed label; lock ignored |
| Verified | Illegible only | Existing explicit variant choice; lock ignored |
| Verified | Absent | Existing resolver: verified singleton, applicable lock or explicit choice |

### Builder and catalog safeguards

Fetch categories, all groups, all group products/prices and one YGOPRODeck v7
cardinfo response. Validate success/errors and result counts. Cache source
bytes on the external SSD, retain timestamps/provider timestamps and SHA-256
provenance, pace requests and retry failures. Offline mode requires every
input. Failed input or invariant validation leaves existing outputs untouched.
Outputs sort deterministically; generation hashes the seed with an empty
generation field. Replaying identical cache and metadata must be byte-identical.

Accept `PREFIX-ENxxx`, early `PREFIX-Exxx` and regionless numeric `PREFIX-000`
with 2–4 alphanumeric prefix characters. Regionless alphabetic suffixes and
non-English codes are rejected. Keep exact TCGplayer rarity names. Drop known
rarity suffixes; retain art/distribution/version suffixes as visible labels.
Printing UUID remains MD5 v3 of `yugioh-printing:tcgplayer:2:<productID>`.
Canonical UUID uses `yugioh-card:ygoprodeck:<id>` after an exact code/name,
beta-name or reviewed alias match; unmatched names have a deterministic
`yugioh-card:name:<normalizedName>` fallback. PSV-EN049 Harpie's Brother / Sky
Scout is covered by a committed alias fixture. No rarity-name joins.

Per-code completeness checks rarity counts, same-rarity printing counts,
name matches, skipped products and indistinguishable labels. Automatic
eligibility also requires one printing, one YGOPRODeck tuple/image, no art
label, and verified physical edition coverage. Product IDs and CDN thumbnails
never establish distinct artwork: candidate `artworkID` is nil. Selection and
write-time acquisition checks remain mandatory.

The report distinguishes observed lanes, verified coverage, quarantined
products, incomplete reasons, aliases and automatic/manual eligibility.
Minimum broad-catalog sanity floor is 10,000 codes. Catalog loading validates
schema, identities, indices, code grammar, editions, evidence and eligibility.

## Correction 4: discover newly available quotes

`pe` is report evidence, never a network whitelist. For independently
supported physical editions the price authority and adapter use the exact
category 2 / group / product / subtype mapping. Every supported mapping can
reach the existing transport on refresh, including when the seed had no lane.
Missing rows and null market prices stay unavailable. No other edition, low
price or mid price substitutes for the exact market quote.

Mapping identity is `tcgcsv:2:<group>:<product>:<subtype>`. Existing identity,
freshness, finite/nonnegative USD, cancellation, cooldown, and stored-printing
refresh checks remain active. Provider fallback is disabled.

## Recognition and integration

The shared scanner remains free of `.yuGiOh` branches. Only raw frames with
no identified footer can request the YGO band, triggered by KONAMI, EDITION or
an eight-digit passcode. Supplemental text reaches only its requesting
adapter. The card-relative band is `(x:.03,y:.20,w:.94,h:.11)` in Vision's
bottom-left coordinates. OCR is accurate/en-US, language correction off and
empty custom words. Other games retain footer-only dispatch.

Right-side under-art and left-footer catalog codes are accepted literally or
through bounded catalog-constrained OCR confusion readings (at most six
positions/64 candidates). Multiple accepted codes are ambiguous. A conflicting
known passcode blocks fallback. No edit-distance identity guessing.

Runtime registration precedes the LOCAL_ONLY_SIGNING early returns. Seed
failure puts YGO in unavailable descriptors while preserving existing games.
Raw collection key is the existing codec over `yu-gi-oh:<printingUUID>` plus
edition. Prices use the same printing UUID and edition ID. Browse and import
require the exact physical UUID, supported edition and ownership key.

## Verification and remaining gates

Repository-required narrow intermediate builds/tests supersede the reviewed
plan's absolute no-intermediate-tests instruction. Run focused YGO/seam tests,
then the neighboring regression sequence once; fix failures and rerun affected
tests. Avoid repeated full suites. Use the external SSD for all build artifacts.
See [build report](../../research/yugioh-catalog/build-report.md) for source counts.

The regression matrix includes conflict followed by First, all singleton
conflicts, merge order/grouping, aging, retry/recovery/tagged persistence, bare
and short Limited fragments, unknown coverage/lock rejection, missing valid
editions across entire groups, product-specific support, later price discovery,
null/missing lanes, alias/canonical IDs, incomplete codes, indistinguishable
artwork, generation checks, other-game regressions and the isolated stubbed
scan → printing → edition → save → refresh → CSV → fresh store → reload chain.
Conflicting/ambiguous scans must not write before resolution.

The [verification record](../../research/yugioh-catalog/verification.md) contains
exact commands, attempt-by-attempt counts, changed files and catalog limits.
Final focused/scanner run: 319 passed, zero failures/skips. Final affected
Price Check/pricing/workflow run: 9 passed, zero failures/skips. Neighboring
run: 543 passed, one collection-key failure, three opt-in skips (547 executed).
The collection-key failure reproduces identically at unchanged `81a6f2c`.
The final two explicit catalog boundary regressions also pass (two tests).
These suites overlap; do not sum them. The offline builder self-test passes
11 cases. The strict boundary audit retains 48 pre-existing branches with
identical matching text. Full-suite, hardware and release gates remain open.

### HIG design gate (source review)

Verdict: **RISK** until physical catalog coverage permits usable acquisitions.
Top issues: no reviewed production edition universes; rendered accessibility
and real-camera usability remain unverified. Minimal fix: review a bounded
product subset through the metadata file, then validate existing rendered
choice/attention surfaces on supported cards. No redesign is required.

| Category | Status | Rationale / minimum action |
|---|---|---|
| Platform patterns | PASS | Reuses printing choice, variant choice, failure note and Needs attention |
| Clarity | RISK | All unreviewed products are unavailable for acquisition; disclose this gate |
| Typography | PASS (source) | No type sizes or text-layout controls changed; rendered QA remains open |
| Accessibility | PASS (source) | Existing control labels/focus/layout retained; rendered QA remains open |
| Interaction cost | PASS | Deterministic evidence resolves supported editions; uncertainty uses existing choices, conflicts file to attention |
| App Review design | RISK | Complete physical coverage review and owner release acceptance before enablement |

Price Check uses its existing failure note and resumes scanning when the gate
has no safe edition options. It never claims a collection-only recovery write.

Remaining owner gates: independently reviewed physical edition metadata;
provider/data/image rights; real-camera calibration and throughput; physical
device performance; CloudKit acceptance; archive/App Store approval and release
enablement. Source/simulator completion does not close these gates. No physical
device work or Journey process/save was authorized in this pass.
