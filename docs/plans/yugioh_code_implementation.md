# Yu-Gi-Oh! implementation and verification

**Status — 2026-10-21:** audited provider-membership contract implemented in a
candidate based on `402c7655be3ad94b08986d9d1b41d9b8774db2f0`; its dated
verification evidence is recorded separately.
Broad explicit acquisition is enabled. Automatic acquisition remains disabled;
physical exhaustiveness, physical-camera acceptance and production delivery
remain unverified. See the [current evidence](../research/yugioh-catalog/audited-verification.md)
and [deterministic rebuild](../research/yugioh-catalog/audited-rebuild.md).
The [previous implementation](../legacy/plans/yugioh_implementation_pre_audit.md)
is preserved as historical evidence.

## Implemented contract

Scope is English TCG raw singles. Preserve category/product printing UUIDs,
canonical UUIDs, release/group, printed code, rarity, raw product name, art
label and owner edition. Canonical enrichment never merges physical products.
All 46,504 original printing/canonical IDs and physical distinctions are preserved.

Product identity, membership, family coverage, quote availability and owner
confirmation are separate facts. Policy `yugioh-provider-membership-v1-2026-10-21`
admits explicit selection only for a valid exact marketplace association with
recognized English grammar, usable rarity, distinguishable physical labels,
supported exact-product editions, source provenance and no identity contradiction.
Missing secondary canonical linkage is disclosed, rather than treated as a contradiction.
Raw product names retain visible renamed-card and token-art distinctions.

Recognized exact-product price subtypes need finite positive numeric evidence
and no invalid fields or conflicting duplicate rows. Identical rows may be
deduplicated within one hashed response. Market-backed and listing-backed
membership remain distinct; listing values never become market valuations.
Independent product-specific review may support membership without complete
coverage or a quote. All-null/zero-only/unknown rows cannot create support.

The membership array records edition, source grade, original response SHA-256,
snapshot/capture time and timestamp semantics; the seed records policy version.
The [build report](../research/yugioh-catalog/audited-rebuild.md) pins every raw
input. Missing future rows retain historical membership through
`--previous-seed`; explicit conflicting revisions remove only the affected
edition. Historical values are not copied into a new quote.

Unknown exhaustive coverage does not block explicit choice. It always prevents
singleton/lock inference. Reliable copy-specific First/Limited text can resolve
a supported edition only after printing selection; missing stamps never imply
Unlimited. Conflicting positives enter Needs attention. No stock-image stamp or
canonical image array resolves the owner's printing or edition.

## Correspondence and corrected source semantics

The [versioned rules](../../scripts/yugioh_correspondence_rules.json) bind RA02
taxonomy to category 2/group 23416, English RA02 codes and the exact expected
product-response hash. All 162 affected rows correspond under the scoped rule.
Drift disables that correspondence locally; it does not invent contradictions
or disable unrelated products. No Worldwide English, anniversary or reissue
release distinctions are stripped. Products 476160 and 486054 remain distinct.

Group `publishedOn` is retained as creation metadata; unknown physical release
dates remain unknown. Unverified chronology is no longer displayed as a release
date. Valid independently supplied dates retain epoch-day sorting. Primary
canonical IDs within the printed-passcode range are kept separately from image
resource IDs and oversized provider IDs. Non-rarity YGO labels cannot add
physical rarity variants or change canonical UUIDs. IOC-SE1 through IOC-SE4 are
bounded grammar exceptions; unsupported grammar is not called foreign.

No YGO marketplace display is counted as independent TCGCSV corroboration.
Images remain representative marketplace images, without an asserted physical
artwork mapping. No YGOPRODeck artwork hotlinking was introduced.

## Coverage and compatibility

| Retained app products | Count |
|---|---:|
| Automatic acquisition eligible | 0 |
| Explicit-choice-only eligible | 46,303 |
| Discovery-only | 239 |
| Quarantined | 0 |
| Total retained | 46,542 |

The baseline retained 46,504 products. Four IOC products are newly supported;
34 unsupported-code records are now discoverable with blocked collection writes.
The retained catalog has 59,965 supported product/edition pairs, 58,264 exact
market quotes and 1,701 listing-only pairs. Every product still has unknown
physical-world coverage. These counts are not recognition accuracy.

Across all 47,910 raw products, the mutually exclusive partition is 0 automatic,
46,303 explicit, 675 discovery/review (239 in-app and 436 missing printed identity
in the diagnostic ledger), 0 quarantine and 932 excluded. The 932 consist of
51 explicit foreign-language codes and 881 sealed/accessory name matches.
The [full upstream ledger](../research/yugioh-catalog/audited-rebuild.exclusions.json)
preserves all 1,368 omitted records. The 436 pending records are not silently
declared invalid cards or manufactured into scan identities.

The JSON schema remains backward compatible; older reviewed fixtures still
load. Existing ownership IDs/edition keys are unchanged and no owner-data
migration/reset is required. The final mutation validator now uses supported
exact-product membership independent of family completeness, matching correction
preflight. This uses the same safe predicate for explicit acquisition and
maintenance; there is no forged-existing-row or import bypass. Unsupported
target editions remain rejected, and ledger transactions retain rollback.

## Normal workflows and delivery

Browse/search lists discovery records. Details disclose missing support,
unresolved linkage, representative images and bundled historical pricing.
Supported exact choices use existing printing/edition sheets, ownership,
quantities, correction, delete/undo, recovery and CSV flows. CSV preserves
printing UUID, edition, quantity and catalog metadata across reopen.

The YuGiOh adapter makes no direct device requests to TCGCSV. Bundled quotes
retain actual original snapshot dates and exact product/edition mappings;
manual freshness watermarks cannot turn an old bundle into a live refresh.
Missing market quotes remain unavailable; no alternate edition or listing
fallback is used and no history provider was added.

The daily [candidate workflow](../../.github/workflows/yugioh-catalog.yml) runs
ingestion on a server, tests policy and stages immutable hashed artifacts in
the existing Firebase site's isolated namespace. It contains no deployment.
The app currently consumes the bundled snapshot only. Adopting durable daily
membership continuity, signed production publication/restoration and remote
activation through the existing hosted catalog architecture remains a release
gate. A device-side cache is not a compliant substitute. No credentials,
service, deployment, purchase or commercial permission was created.

## Remaining acceptance

- Complete production distribution/activation and rights review before claiming
  live provider service.
- Resolve 436 missing-identity records and review unsupported grammar as bounded
  follow-up evidence, without expanding into OCG/Rush/non-English.
- Perform owner camera checks for real footer layouts, foil glare, alternate art,
  same-code reissues, stamps, stack/duplicate behavior and interruption/reopen.
- Keep physical-camera, CloudKit, archive/TestFlight and release certification
  separate from Simulator and fixture OCR evidence.
