# Historical Magic recognition implementation plan

**Status:** general historical recognition and live printing-choice resolution
implemented and wired into normal scanning; physical-device acceptance and signed
profile publication remain open. The optional automatic index pilot stays disabled.
**Reviewed:** 2026-10-06 against `412a09d` plus existing local documentation changes.
**Current scope:** released English paper printings through 2014-07-17 with normal,
split, flip, transform or leveler layouts. Collector numbers assist choice ordering;
unnumbered/pre-Exodus cards use title-based printing choice. Foil, full-art,
alternate and planeswalker frames retain their exact printing/finish identity.
M15+ remains the existing modern path and a regression control.

## General implementation — user scope correction, 2026-10-06

The corpus is a frame/layout regression reference, **not an acquisition allowlist**.
The [general implementation report](../research/magic-historical-corpus/general-scanning.md)
supersedes the per-card pilot approach below. General OCR uses 14,384 historical
titles from the complete retained source, supports collector and title-only
evidence, and dispatches after modern recognition abstains without a fallback
block. It uses the raw guide or slab card window, same-frame text geometry and
bounded encounter confirmation. No exact card entry or expiring bundled receipt
is needed to recognize a historical printing family.

The `historical-live` adapter fetches complete current historical English/paper
printing searches, including pagination, then asks for the exact printing and
encounter-scoped English confirmation. Collector OCR never hides alternatives
or automatically selects a printing. Exact hydration, refreshed choice membership
and immediately pre-write validation preserve existing ownership/finish keys.
Normal, split, flip, transform and leveler are explicit supported layouts; digital,
oversized, token/art/emblem, non-English and modern/future printings reject.
Large printing families can be filtered by set or number in native Details.
The [additional edge-case review](../research/magic-historical-corpus/edge-cases.md)
records quoted/ligature titles, level-up cards, same-title logical identities,
ambiguous framing and provider completeness checks.

All 27 corpus reference titles now reach printing choices through actual Vision
OCR and retained provider captures, including both split cards, full-art basics,
flip cards and double-faced fronts. An unlisted Counterspell fixture verifies
the ordinary choice/English-confirmation/collection-writer path without any pilot
index. Final regression and rendered search evidence are recorded in the general
report. Static photographic evidence does not certify independent camera frames,
device accuracy, finish detection, thermal budgets or release readiness.

The dated B1/C/D sections below describe the preserved optional automatic pilot.
Its card review/index expiry gates do not govern the general manual printing-choice
route. The earlier requirement to deliver another per-card batch before broader
implementation is superseded by the user's explicit scope correction.

## Implementation evidence — 2026-10-06

At `412a09d` plus local changes, the first task now has a deterministic
[set-review inventory and evidence policy](../research/magic-historical-baseline/README.md),
version-1 app-local profiles, sparse exact-printing overrides, catalog/index/profile
generation tracking and compare-and-publish local activation. Unknown versions,
routes and invalid overrides reject; historical routes cannot enable acquisition.
The registry derives local defaults alongside its unchanged modern projections.
Signed schema 1, modern adapter generation, live discovery and `legacy-live`
configuration remain unchanged.

The pre-change baseline passed 130 simulator tests. The first implementation run
passed 136 focused simulator tests and 18 MagicCatalogCore tests. Inventory
regeneration is byte-identical. Result bundles and build/package artifacts are
on the external volume under `CodexBuilds/MagicHistorical`.

The next C slice now retains dated AllPrintings/EXO/Scryfall captures and a complete
123,822-source-row disposition ledger on the external drive. The
[pilot report](../research/magic-historical-pilot/README.md) hashes the sources,
ledger and 383,009-byte runtime artifact: 143 Exodus printing IDs reconcile
exactly across providers; seven cross-era name/collector collision identities
remain explicitly unverified. Source rows, faces and set counts are not a physical
printing denominator. Finish-specific source references remain under each
printing; inconsistent/partial face groups cannot create separate candidates.

Dictionary lookup retains every matching era/layout as collision evidence.
Version, identity, source, profile/index/catalog compatibility, per-key receipt
membership, expiry and external source-context checks fail closed. Compatible
profiles/index publish atomically and invalidate captured generations. The
initial C artifact had no completeness receipts or validity and no reviewed
visible numbers, so every query remained incomplete and no record was admitted for
automatic historical acquisition. Its completeness tests were synthetic. The D
evidence below supersedes that artifact and adds bounded provider reconciliation.

Final C verification passed 145 focused simulator tests and eight importer tests.
Regeneration preserves the pilot projection byte-for-byte except for the explicit
new receipt field; artifact/report hashes, counts and retained ledger provenance
were checked. Simulator load p50/p95 were 67.9/68.3 ms (10 samples); warm query
p50/p95 were 0.034/0.036 ms (1,000 samples). These are local measurements, not
device/thermal/memory budgets or optical accuracy.

A is **not complete**: source rows remain review leads, not a physical-printing
denominator. Labeled camera photographs, held-out optical cases and device
acceptance remain open. Provider-front review does not close those gates.

### D pilot integration and current reconciliation — 2026-10-06

The [review reconciliation report](../research/magic-historical-pilot/2026-10-06/review-reconciliation-report.json)
records all 150 exact printing identities reconciled, including seven collision
records. Complete single-page English/paper searches across all eras certify
three name/number keys for the dated receipt window ending 2026-10-07 UTC.
Provider-front images show Allay `1/143`, Cataclysm `3/143` and Monstrous Hound
`89/143`. Allay is the only automatically eligible singleton in this reviewed
subset; Cataclysm's V14 and Monstrous Hound's promo remain outside-era collision
blockers. The promo has a per-printing date before Exodus's enclosing set date.
Spanish/`es` language evidence normalizes without becoming English evidence.

An explicitly injected local pilot now reads same-frame title/number geometry
after the modern parser abstains, requiring two consecutive readings inside a
six-attempt/1.5-second window. It uses its own `historical` namespace and immutable
profile/index pins. Unsupported numerals, card geometry, cross-game titles and
unknown fields abstain. Modern codes/customWords and production activation stay
unchanged. Unknown encounter language requires the native printing picker's
unchecked English confirmation; an answer survives only that encounter's retries.

The adapter verifies exact-ID hydration independently of the modern date gate,
retains canonical oracle identity and existing printing/finish ownership keys,
and rechecks activation before and after awaits. Automatic lookup and immediately
pre-save acquisition require a bounded current-provider collision check; incomplete,
warned, changed, expired or offline evidence cannot certify uniqueness. Explicit
printing choice follows its own membership/hydration path. Recovery preserves the
evidence and rejects stale profile choices rather than silently rebasing them.

Final D verification passed 314 selected simulator tests and 13 Python tests.
Collection-save/recovery integration and final regression/rendered evidence are
recorded in the [pilot report](../research/magic-historical-pilot/README.md).
Production scanning remains off. The subsequently supplied
[historical image portfolio](../research/magic-historical-corpus/README.md)
now provides 27 decoded starting images: 20 photographic examples and seven
clean-front controls. This supersedes the earlier lack of a known local photo
folder. Exact printing labels, frozen held-out optical evaluation and physical
device acceptance remain open; intake alone does not certify the OCR pilot.

### Corpus-backed Exodus continuation — 2026-10-06

The [corpus evaluation](../research/magic-historical-corpus/README.md) now extends
the reviewed index with Survival of the Fittest `129/143`, reconciled by exact ID
and a complete current all-era printing search. Four keys have dated receipts;
150 identities and existing collision blockers remain. The live pilot and
evaluator share accurate card-relative title/footer Vision requests and source
geometry. No modern vocabulary, production activation or layout expansion follows.

Actual OCR over all 27 staged originals yields the one calibrated Exodus positive
and 26 current-pilot scope abstentions. The positive enters the normal scanner
choice/save path: unknown English writes nothing, explicit confirmation saves
the exact printing. Focused simulator 27/27, affected regression 316/316,
Python 20/20 and Debug build-for-testing pass.
This supersedes the prior absence of photographic optical integration evidence,
but manually annotated framing and repeated stills do not close held-out positive,
independent camera-frame, live-provider acquisition or device gates. Next is
reviewed collector-template expansion across the corpus's frame eras and a
separate held-out photographic batch; pre-Exodus and non-normal layouts retain
their original scope.

## Corrected proposal

Starting with collector-number-era Magic is a sensible first milestone. The
existing catalog/recognition seams support this without a wholesale redesign,
but changing two publisher files alone will not enable historical scanning.

| Proposed claim | Correction |
| --- | --- |
| The scanner gate is simply date plus a 3–4-character code. | `MagicCatalogPolicy.isScannerEligible` also requires Browse eligibility, excluding digital and several set types. Live set discovery duplicates that policy; ordinary card lookup separately rejects pre-2014 printings and several layouts. The parser requires a known set code, English marker and spatially valid collector evidence. |
| Three recognition eras can replace scanner eligibility. | Use those three routes as recognition capabilities, with an explicit unknown/disabled outcome. Dates provide defaults, not proof of a printing's visible features. Set defaults need reviewed printing exceptions. Keep capability activation separate from route classification. |
| Historical physical set codes are incorrectly excluded from the catalog. | Browse already accepts historical sets without the scanner's 3–4-character restriction; descriptor validation allows 1–8 alphanumeric characters. PLG20 demonstrates a scanner-discovery restriction, not universal catalog absence. A provider code also need not appear on the physical card. |
| The supplied generator produces a complete physical-printing index and exact filter diff. | It produces provider rows and omits current set-type exclusions, provider crosswalks, face consolidation and physical distinctions beyond finishes. It was excluded during intake. Build a validated importer using existing Magic tooling patterns; do not adopt that helper unchanged. |
| One name/number result can auto-select. | Only after strong same-card evidence, a complete candidate search for that evidence, and no unresolved physical distinctions. Uniqueness in a partial or historical-only index is insufficient. Finish/treatment resolution remains separate. |
| This is most historical coverage and can scan essentially any card in the range. | Neither proportion nor optical coverage has been measured. Publish a dated in-scope denominator, exceptions and measured outcomes; advertise only the validated scope. |

Wizards identifies Exodus, released in June 1998, as the introduction of collector
numbers. Its M15 frame description explains the later standardized number/rarity/
set/language block. Use Exodus's release boundary, not January 1998 or the
handoff generator's approximate June 1 threshold. Reviewed product dates and
physical examples must resolve edge cases. Sources:
[Wizards history](https://magic.wizards.com/en/news/making-magic/which-came-first-2022-03-14),
[official Exodus product page](https://mtg-jp.com/products/0000112/),
[M15 frame description](https://magic.wizards.com/en/news/making-magic/directors-chair-2013-2014-01-06).

The corrected first milestone is:

> Recognize collector-number-bearing English physical ordinary Magic printings
> from Exodus through July 17, 2014. Resolve the exact printing when visible
> evidence and reconciled candidate coverage justify it; otherwise offer verified
> candidates or abstain. Preserve existing M15+ behavior.

Numberless exceptions inside this interval remain cataloged with manual recovery.
Tokens, art cards, oversized/special layouts, stamped/event distinctions and other
languages remain separately inventoried and explicitly classified, rather than
being quietly declared solved. Phase 1 does not depend on artwork or set-symbol
machine learning. Accurate manual choice is an acceptable initial outcome.

## Original planning baseline — superseded by general implementation above

- [Policy](../../MagicCatalogCore/Sources/MagicCatalogCore/Policy.swift) and
  [builder](../../MagicCatalogCore/Sources/MagicCatalogCore/CatalogBuilder.swift)
  already separate Browse, scanner vocabulary and token/art child routing.
- [Catalog contract](../../MagicCatalogCore/Sources/MagicCatalogCore/CatalogContract.swift)
  is schema 1 and contains set descriptors, not card-level printings. App-local
  profiles can prove the bundled pilot first; remotely published profile semantics
  later require explicit schema, signature and authority-classification support.
- [Live service](../../TradingCardScanner/Services/TCGdexService.swift) independently
  filters set discovery and ordinary lookup. Its cutoff is inclusive at
  `2014-07-18`; the set predicate has no upper bound excluding future releases.
- [MagicScanProfile](../../TradingCardScanner/Services/ScanParser.swift) handles
  modern footer evidence. [CardScanner](../../TradingCardScanner/Services/CardScanner.swift)
  has same-frame secondary title OCR for historical Pokémon, not historical Magic.
- [MagicCatalogAdapter](../../TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift)
  requires a `LegacyScanIdentifier.magic` projection in preparation and lookup,
  and currently rejects printing-choice resolution. A generic historical namespace
  cannot pass those guards without an explicit adapter migration. The
  [shared catalog seam](../../TradingCardScanner/Games/Core/GameCatalogAdapter.swift)
  already supports `needsPrintingChoice`, `catalogIncomplete` and physical candidates.
- [Registry](../../TradingCardScanner/Services/MagicCatalogRegistry.swift) and
  [coordinator](../../TradingCardScanner/Services/MagicCatalogCoordinator.swift)
  compare scanner code/printed-size projections. Profile-only changes currently
  would not refresh that scanner projection.
- Production configuration remains `legacy-live`; the
  [Magic publication runbook](magic_catalog_key_handling_runbook.md) retains
  separate key/authority gates. Profile work does not authorize remote rollout.

## Implementation sequence

The original sequence below records the automatic-index design and its dependency
gates. The user's 2026-10-06 scope correction supersedes its per-card delivery
restriction for explicit manual printing choice. General recognition is now wired
into normal scanning; automatic historical selection remains separately gated.

### A. Freeze scope and build the evidence baseline

1. Produce a dated list of candidate sets/printings for the target interval and
   classify ordinary, special-layout, no-printed-number, unreleased, non-English
   and uncertain rows. Preserve all exclusions with reasons.
2. Record the existing modern parser, lookup, token/art routing, catalog activation
   and identity round-trip baseline before changing it.
3. Assemble labeled physical-front examples and OCR/geometry fixtures spanning
   Exodus-era frames, the Eighth Edition frame transition, late pre-M15 sets,
   split/double-faced cards, basic-land variations and promos. Include adversarial
   copyright years, power/toughness, rules-text numerals and cross-game cards.
4. Define the English-language evidence policy. Missing `EN` is expected in the
   legacy route. Title matching may identify a card but cannot establish language:
   proper nouns, short titles and cross-language names can coincide. Store
   independent language evidence and its provenance in the encounter evidence,
   with explicit unknown, corroborated-English, user-confirmed-English and
   conflicting/non-English states. Candidate generation may proceed while language
   is unknown; saving requires reliable independent English evidence or an explicit
   English confirmation for this card encounter. An English-filtered result or
   default picker selection is not confirmation.
5. Define `supportedLegacyLayouts` as a reviewed allowlist, initially `normal`
   only for the ordinary pilot. Split, transform and other layouts remain manual
   until their face/title/collector geometry fixtures and device cases pass.
   Unknown layouts fail closed; retain the modern route's existing layout policy.

**Exit:** reviewed scope/exceptions, provenance manifest and a fixed validation
corpus. Do not infer a denominator from provider counts.

### B1. Introduce app-local profiles without enabling new acquisition

1. Add `modernFooter`, `legacyCollectorNumber`, `legacyNoCollectorNumber` and
   unknown/disabled semantics to Magic's recognition policy. Prefer a set default
   plus sparse per-printing overrides over one rule for every product.
2. Keep `browseEnabled` independent. Keep `scanEnabled` as compatibility output
   for the modern set-code vocabulary during migration; adding a historical
   profile must not insert historical provider codes into the modern parser.
   Track whether each new route is actually enabled separately.
3. Keep signed schema 1, its builder output, verifier and publication semantics
   unchanged during the bundled pilot. Add a versioned app-local profile/index
   snapshot with deterministic mapping from existing descriptors; unknown local
   profiles fail closed. Do not interpret old `scanEnabled` as historical authority.
4. Make local profile/override/index changes participate in the historical adapter's
   generation, pending-choice invalidation and atomic local activation. Preserve
   current modern registry/coordinator behavior; local profile changes must not be
   missed merely because code/printedSize and Boolean flags remain equal.
5. Check bundled seed, compiled vocabulary and live discovery parity in existing
   rollout modes. Record the current catalog context for freshness checks without
   enabling remote publication. Defer wire migration to B2 after the D pilot.

**Exit:** existing releases still work, historical classification remains inert,
local profile-only changes invalidate the correct snapshot, schema 1 remains
unchanged, and no modern vocabulary or route changes accidentally.

### C. Build the historical index and reconcile physical identities

1. Retain a dated MTGJSON AllPrintings input with URL, metadata date, hash and
   processing version. Cross-check Scryfall printing IDs and set codes. Use exact
   mappings, never name-based joins to allocate identity. Reuse existing capture/
   generation conventions instead of introducing a second publication framework.
2. Generate the full historical reconciliation inventory, including pre-Exodus
   rows, but initially ship only the compact Phase-1 runtime projection and the
   cross-era collision information necessary to prevent false uniqueness.
   Cataloging Phase-2 data must not enable its recognizer or delay the pilot.
3. Store stable Scryfall printing ID, MTGJSON source ID, exact collector string,
   set ID/code/name, release date, language, layout, face names/aliases, finishes,
   frame/artwork references where available, recognition profile, provenance,
   eligibility and unresolved physical distinctions. Provider-assigned numbers
   need a separate visible-number flag; they are not automatically OCR evidence.
4. Define identity axes before importing: `PhysicalPrintingCandidate` identifies
   one printing independently of finish; its printing record carries supported
   finishes and treatment metadata. Variant resolution selects foil/nonfoil/etc.
   after printing selection. Finish-specific SKU IDs map to that printing plus
   finish, not additional printing-picker entries. Consolidate linked faces into
   their enclosing physical card and preserve distinct printing/artwork identities
   and explicit special-product differences. Preserve separately identified
   treatment printings and existing treatment qualifiers; this rule must not merge
   different provider printing IDs just because they share a name/number.
   Reject ambiguous/missing crosswalks into a review ledger rather than collapsing
   them by name/number or counting faces as independent physical printings.
5. Require explicit paper/English/released evidence for acquisition. Missing or
   contradictory metadata remains unknown. Produce counts by exact identities and
   dispositions, with repeatable diffs and no claims of global completeness.
6. Build local name/face-alias + collector-string lookup. Candidate generation must
   consider matching printings outside the target era: a recent reprint whose
   modern footer was missed must not become an old printing automatically.
   Missing reconciliation or possible distinctions force choice/incomplete status.
7. Give the candidate universe an explicit completeness/freshness stamp: input
   hashes and source-data timestamps, coverage/exceptions, reconciliation version,
   local profile/index generation, and the active Magic catalog context reconciled
   against. In `legacy-live`, retain a dated live directory context too. A set-only
   catalog generation cannot certify card-level completeness: printings/corrections
   can appear inside an existing set without changing its descriptors.
8. Automatic uniqueness requires a complete evidence-key candidate search and a
   still-valid freshness stamp at lookup and immediately before save. Define source
   refresh/expiry rules before enablement. Catalog drift, expired validity, missing
   shards, incomplete sources or new unreconciled printings invalidate automatic
   uniqueness. A matching generation or recent download timestamp alone is not
   proof of complete coverage. A frozen bundle must not continue auto-resolving
   solely because it once contained one result.
9. When freshness is unproven, return `catalogIncomplete` and retain recovery, or
   perform one bounded current-provider collision check for the evidence key.
   This is lookup work, never per-frame OCR work. Validate every response/page and
   match exact collector/name/face aliases across eras; only a complete supported
   reconciliation can renew freshness for that key. Timeout, truncation, outage or
   unresolved provider/physical differences cannot renew uniqueness. Offline may
   retain historical candidates for manual recovery but cannot silently certify
   the universe as current. An explicit reviewed printing choice remains distinct
   from automatic uniqueness and still must pass language, identity and finish gates.
10. Use a versioned bundled read-only artifact for the pilot. Include sufficient
   validated identity metadata for local candidate presentation; resolve/save only
   from a vetted compatible payload. If live hydration is still required, state
   that offline limit and retain retry rather than inventing provider data.
   Profile/index mismatches fail closed. Remote card-index publication is later,
   separately reviewed work under the existing runbook.

MTGJSON documents face links and optional Scryfall identifiers; these are useful
join inputs, not interchangeable physical UUIDs. Sources:
[card model](https://mtgjson.com/data-models/card/card-set/),
[identifier model](https://mtgjson.com/data-models/identifiers/).

**Exit:** deterministic index, collision/exception ledger and exact provider-ID
continuity; no truncated download, uncertain join, partial shard or stale universe
can imply uniqueness. Include expiry/drift behavior in the index acceptance tests.
Measure artifact size, load time, memory and query latency before choosing whether
the final runtime representation needs sharding. Avoid adding a database first.

### D. Deliver collector-number recognition for a small pilot

1. Add a separate legacy evidence parser/template. It reads name/face title plus
   collector number (and denominator where actually present), without requiring
   a printed textual set code or `EN`. Preserve suffixes and punctuation; reject
   body numbers, years, loyalty and power/toughness as collector evidence.
2. Dispatch modern recognition first. Run bounded secondary title/legacy OCR only
   for plausible legacy evidence after no modern identification and no explicit
   fallback block. Existing token/art markers and spatial rejections remain
   authoritative. Do not turn every unrecognized number into a Magic attempt.
3. Read title and number from the same oriented image/card encounter. Keep spatial
   provenance, consecutive-frame confirmation, TTL/retry bounds, cancellation and
   card-removal resets. Reuse proven OCR/latch mechanics while keeping Magic and
   Pokémon attempt state/evidence separate.
4. Add a Magic-owned historical evidence namespace to the generic `ScanIdentifier`
   fields, with index/profile generation and stable suppression identity. Extend
   retry/persistence serialization only where needed; do not fabricate a modern
   set-code identifier or add an unnecessary shared legacy enum case. Retain the
   language-evidence state/provenance from A4 in the historical evidence object,
   including explicit confirmation scoped to the current encounter. Separate
   independent language evidence from title/card-match evidence.
5. Refactor `MagicCatalogAdapter.prepareLookupIdentifier`, `identifierForRetry`,
   `lookup` and `resolve(candidate:for:)` to dispatch on Magic namespace (`card`
   versus `historical`), with per-namespace field/generation validation. Only the
   existing `card` branch projects through `LegacyScanIdentifier.magic`; historical
   lookup consumes generic evidence directly. Reject unknown namespaces and malformed
   fields. Preserve the modern/token/art path and its existing generation semantics.
   Query the local index through the historical branch, enforce C's freshness
   invariant, and return verified candidates through existing shared outcomes.
   Implement Magic's candidate resolution; revalidate membership, chosen printing,
   original evidence and captured generation before saving. Unknown language requires
   an explicit English confirmation; conflicting/non-English evidence cannot pass
   Phase-1 acquisition. A title match or one English result cannot bypass this gate.
6. Adapt ordinary lookup validation for an explicit, validated legacy route.
   Do not globally disable `requiresScannableCard` or date/layout/identity checks.
   Exact-ID hydration still verifies paper/language/layout/profile and the selected
   printing. Enforce `supportedLegacyLayouts` at candidate admission, automatic
   resolution and payload validation; the modern denylist must not authorize
   historical layouts. Reviewed additions require fixtures before activation.
   Keep modern and token/art lookup contracts intact.

**Exit:** one reviewed pilot batch can scan, choose, save and retry through the
normal app, with both identifier namespaces accepted by their proper adapter paths.
Strong unique evidence resolves only with valid candidate freshness, supported
layout and corroborated/confirmed language; competing printings open the picker;
weak/conflicting/incomplete evidence abstains without a write.

### E. Complete printing choice and broaden the era

1. Reuse the existing picker/recovery UI. Show set/release, exact number, artwork
   and the smallest verified distinctions needed to choose. Similar artwork or
   unavailable visual evidence must not preselect a candidate.
2. Resolve foil/nonfoil and treatment through the existing Magic variant policy
   after printing identity. One candidate with multiple possible finishes still
   needs finish evidence or user choice. Nonfoil/foil SKU mappings cannot duplicate
   printing candidates. Preserve treatment qualifiers and any separately identified
   treatment printing before selecting its supported finish. An unpriced card remains usable.
3. Verify the same exact printing/finish through scan, Browse/detail/add, CSV
   import/export, collection reopen and exact pricing joins. Preserve existing
   provider IDs and ownership keys; no automatic relabeling of owned printings.
4. Expand reviewed batches across the frame eras, supplemental releases and
   numbered promos. For unsupported layouts or visually missing numbers, retain
   manual recovery and explicit scope labels. Set symbol/year may assist ranking
   only when supplied evidence is reliable; artwork recognition is not a prerequisite.
5. Freeze new request/choice generations during activation. Cancel/revalidate stale
   requests and persisted choices; never reuse one user's printing answer for a
   later encounter sharing the same name/number.

**Exit:** every admitted Phase-1 identity has a supported recognition or documented
manual path, validated round-trips and explicit incomplete-family handling.

### F. Acceptance and controlled enablement

| Gate | Required evidence |
| --- | --- |
| Data | Repeatable provider reconciliation; unique stable IDs; face consolidation; printing candidates independent of finish; finish-specific SKUs join to printing plus variant; unknowns and exclusions retained. PLG20 is not excluded from physical catalog membership solely for code length. No optical claim follows from its provider code. |
| Freshness | Simulate a new colliding printing in a new set and inside an existing set, an expired stamp, newer catalog context, missing shards, incomplete pages and offline/outage. Formerly unique evidence cannot auto-resolve until complete reconciliation renews its validity. Recheck at save; activation during a pending choice cannot reuse stale uniqueness. |
| Adapter/evidence | Preparation, lookup, choice resolution, retry and persisted recovery accept `historical` evidence without a fabricated set code; `card` behavior stays unchanged. Unknown namespaces/malformed fields fail closed. Titles shared across languages and English-only result lists never establish language; explicit confirmation is encounter-scoped and survives that encounter's retry only. |
| Recognition | Separate success, wrong automatic selection, picker and abstention counts. Negative fixtures for weak titles, ambiguous OCR numbers, wrong language, partial indexes, missed modern footers, non-allowlisted/unknown legacy layouts and cross-game evidence. No known wrong automatic selections in the fixed validation corpus. |
| Modern regression | Existing modern footer behavior, suffixes, tokens/art cards, spatial rejection and multi-game arbitration remain passing. No historical codes flood modern customWords. |
| Product integrity | Choice/skip/cancel/retry/relaunch, same-number different printing, finish locks, persistence, CSV, Browse and exact/unpriced pricing retain identity. Stale choices cannot write. |
| Performance/offline | Record cold/warm index load, query/OCR p50/p95, memory and session thermal behavior on supported devices against the baseline. Freeze release budgets before tuning; avoid per-frame network calls, full-index scans or unbounded title OCR. Test empty-cache/warm-cache offline and outages; describe actual hydration/save limits. |
| Device acceptance | Physical samples across the frame eras and hard cases under ordinary lighting, wear, sleeves and glare. Keep tuning and held-out evaluation separate. Report sample size and auto-selection precision separately from retrieval/recognition coverage; do not infer optical accuracy from parser fixtures. |
| Rollout | Independently disable the new recognizer and preserve saved identities/modern scanning. Index/profile activation is atomic. Publication requires the existing Magic-specific signing/owner gates; do not switch away from `legacy-live` as a side effect. |

Begin with narrow MagicCatalogCore tests, then focused app parser/catalog/activation/
scanner/variant/collection tests. Expand to the full regression selection after
integration. Use the narrowest relevant `xcodebuild` build/test; put DerivedData,
package caches and result bundles on an available external SSD. Simulator evidence
does not close camera, provider, sync or release acceptance.

Enable historical scanning only after the pilot and held-out/device gates pass;
broaden the advertised scope batch by batch. If candidate retrieval is reliable
but automatic precision is not, ship choice-first behavior for that batch rather
than weakening evidence requirements.

### B2. Add signed profile publication only after the D pilot

This is deferred publication work, not a prerequisite for the bundled pilot or
local Phase-1 acceptance. Start it after D proves the recognition/evidence model
and remote profile publication is in scope; remote card-index publication remains
separately reviewed. The local sequence is A → B1 → C → D → E → F.

1. Introduce explicit schema-2 profile semantics. The new client accepts schema 1
   with its existing modern-only authority and schema 2 with validated profiles;
   unknown schema/profile values fail closed. Old clients must reject schema 2
   rather than ignore new authority. Plan versioned publication/client compatibility
   before switching hosted pointers. Verify original signed bytes, never reserialized
   old payloads.
2. Update builder, release validator, signatures, change classifier, registry
   projections and coordinator activation events together. Profile/override changes
   are scanner authority even when code/printedSize and Boolean flags are unchanged.
3. Verify migrations, schema-1 fallback, stale choice invalidation, atomic compatible
   profile/index activation and rollback. Signed set descriptors alone must not
   renew the card-level candidate-universe freshness stamp.
4. Apply the existing Magic-specific key/pin and protected publication gates.
   Do not silently change `legacy-live`, signing keys or supported-scope claims.

**Exit:** compatibility and authority tests plus publication approval/evidence.
No signing migration is required merely to evaluate historical optical performance.

## Phase 2: pre-Exodus and numberless exceptions

After Phase 1 acceptance, plan name + set-symbol/artwork/frame/copyright evidence,
including cards with no usable symbol and indistinguishable reprints. The boundary
is pre-Exodus plus reviewed numberless exceptions, not merely 1993–May 1998.
Reuse the identity index, evidence namespace, candidate outcomes and picker;
evaluate new visual classifiers separately. A provider collector number that is
not printed must never become inferred physical evidence.

## First implementation task and stop conditions

Start with A and B1 as an inert app-local profile slice: tests first, existing
schema-1 behavior and modern projection parity preserved, historical activation
off. Complete C for a small reviewed D pilot before broad data activation; D must
include the namespace-aware adapter, freshness, language and layout gates.
Defer CatalogBuilder/wire/signing migration to B2 after the pilot succeeds and
remote publication is needed. Policy and adapter seams are entry points, not the
entire first deployable change.

Stop automatic resolution for any incomplete candidate search, ambiguous identity
join, missing visible-number/language evidence, non-allowlisted legacy layout,
stale generation or expired/unreconciled candidate universe. Stop rollout
for reproducible wrong printing writes, modern regressions, unverifiable artifacts
or unmeasured device acceptance. These conditions retain manual/retry paths and
do not require deleting catalog records or owned cards.

This plan complements the [coverage audit](../audits/card-coverage-gaps-and-research.md)
and [useful data intake](../research/card-coverage-gap-data/README.md). It changes
neither the publication runbook's authority nor the current supported-scope claims.
