# Yu-Gi-Oh! implementation and verification

**Automatic scanning update — 2026-10-22, base `1ac6750`:** shared resolution
and final-save policy now separate verified printing families from exhaustive
edition coverage. Release-driven evidence admits 260 families across MP24,
Duelist Nexus and Pharaoh's Servant. Supported positive edition evidence skips
both questions; unresolved edition asks only that question for certified
families. This supersedes the blanket manual-printing contract below, but does
not certify all printings. See the [current automatic-family verification](../research/yugioh-catalog/automatic-family-verification.md)
for scope counts, commands, evidence gaps and validation status.

**Current bounded acceptance — 2026-10-23, base `7502144`:** shared quantity
intent and exact-provider history defects are fixed. Recovery-preflight
suspension/cancellation/authority replacement is native-verified. Scanner,
collection detail and portfolio use active-source price wording, rendered with
bundled and synthetic approved-source environments. Mixed-game quantities,
CSV reopen/resume and explicit additional copies pass native verification.
The latest combined selection passed 79 tests; this is not a full-suite result.
Actual mixed-game Files export/import/reopen and rendered totals remain open:
the Mac is locked at the system Files picker. Unlock and continue the dedicated
source/destination acceptance routes. See the
[current evidence and prepared owner handoff](../research/yugioh-catalog/audited-verification.md#correctness-and-bounded-local-acceptance-on-7502144--2026-10-23).
Production trust/hosting, durable approved-parent continuity and a bounded
new-bundle policy remain owner gates. No rollout or release readiness is claimed.

**Latest review corrections — 2026-10-22, base `9a1d8b0`:** approved releases now
support bounded signed-ancestor catch-up, the publisher validates with the app's
full catalog loader, and durable lineage arithmetic rejects overflow. The
focused final run passed 35 native and 40 Python tests. Approved delivery remains
disabled without owner configuration. See the
[review correction evidence](../research/yugioh-catalog/audited-verification.md#latest-review-corrections-on-9a1d8b0--2026-10-22)
for protocol limits and open acceptance gates.

**Completion checkpoint — 2026-10-21, base `eb12b5c` (superseded above):** the
cyclic correction Undo defect was reproduced and repaired at final-save
authority, with durable inverse-lineage and tamper regressions. Approved signed
delivery now has a shared wire format, local publisher, verified parent chain,
opt-in runtime coordinator and hosting preservation. Production configuration
is absent, so the normal app still uses the bundle. CSV export through Files
and seven-card import into a separate isolated store succeeded; a real hidden
confirmation-dialog bug was verified twice and fixed. The latest
[completion evidence](../research/yugioh-catalog/audited-verification.md#completion-checkpoint-on-eb12b5c--2026-10-21)
supersedes older CSV/system-sheet and candidate-only implementation limitations.
It also lists unfinished acceptance and external gates; this is not launch
certification. Earlier entries below are dated historical checkpoints.

**Interactive follow-up — 2026-10-21:** the owner-selected generic iPhone 17
now has rendered evidence for printing/edition selection, disabled discovery
choices in live/recovery pickers, cancellation/recovery, Browse Add, duplicate
handling, edits/delete/Undo, dated price display and reopen. See the
[interactive evidence](../research/yugioh-catalog/audited-verification.md#generic-iphone-17-interactive-acceptance--2026-10-21).
The older QA-device input blocker below no longer applies to those flows. At this
checkpoint, CSV export/import remained pending at the system Files save sheet;
the later completion checkpoint above records a successful isolated roundtrip.
Physical camera and production delivery remain open. The app still uses
historical bundled pricing. Follow-up native selections passed 54 and 37 tests
separately; they are not additive with prior results.

**Earlier status — 2026-10-21 residual corrective pass:** the three remaining F3/F4
paths identified at reviewed `09c4a40` now have focused source fixes and
real-store/recovery regressions: durable duplicate maintenance, mixed-game bulk
deletion, and Needs attention availability/dismissal. The
[residual verification](../research/yugioh-catalog/audited-verification.md#residual-f3f4-corrective-pass-after-09c4a40)
separates their executed native results from interactive acceptance. This
supersedes the earlier blanket F3/F4 closure claim; F1/F2/F5/F6 and diagnostic-only
F7 behavior remain intact. F4's residual paths are native-verified. F3's residual
bug is fixed/native-verified; interactive acceptance remains pending because a
reported successful Simulator tap did not dismiss a system camera alert. The earlier
[verification record](../research/yugioh-catalog/audited-verification.md#corrective-pass-after-four-commit-review)
separates bug fixes, executed tests, local delivery preparation and pending UI work.
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

Unknown exhaustive edition coverage does not block explicit choice or supported
positive edition text. It prevents inferring an edition from a singleton or lock.
Reliable copy-specific First/Limited text can resolve a supported edition after
either certified automatic printing resolution or explicit printing selection;
missing stamps never imply
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
migration/reset is required. Maintenance now has operation-specific authority:
the final validator reads the persisted starting holding in a separate context,
checks unchanged ownership identity and non-increasing quantity against staged
ledger deltas, and permits exact ledger-backed disposal reversal against a durable
removal snapshot. Discovery-only runtime availability no longer blocks these
operations. New identities, editions, increases and imports still require current
admission; correction destinations remain strict. Unproven legacy restoration
does not gain acquisition permission. Ledger transactions retain rollback.

## Normal workflows and delivery

Browse/search lists discovery records. Details disclose missing support,
unresolved linkage, representative images and bundled historical pricing.
Supported exact choices use existing printing/edition sheets, ownership,
quantities, correction, delete/undo, recovery and CSV flows. CSV preserves
printing UUID, edition, quantity and catalog metadata across reopen.

The YuGiOh adapter makes no direct device requests to TCGCSV. Bundled quotes
retain actual original snapshot dates and exact product/edition mappings;
manual freshness watermarks cannot turn an old bundle into a live refresh.
Missing historical market quotes report provider unavailable, including ordinary
nil-watermark refreshes, so they cannot create a current successful check or
coverage stamp. Prior prices remain intact. No alternate edition or listing
fallback is used and no history provider was added. Scanner, Browse, detail and
portfolio disclose the bundled capture date and lack of live refresh.

Unsupported scanner siblings remain visible with disabled actions and reasons.
Stale selection retains the family and shows a recovery explanation. The acceptance
route isolates both collection and recovery storage. Its Unknown sample explicitly
reports a recognition diagnostic; it does not fabricate a card or a recovery row.

The daily [candidate workflow](../../.github/workflows/yugioh-catalog.yml) runs
ingestion on a server, tests policy and stages immutable hashed artifacts in
the existing Firebase site's isolated namespace. It contains no deployment.
The app currently consumes the bundled snapshot only. A separate, unactivated
local consumer seam verifies Ed25519-signed manifests, hashes, policy, actual app
loader admission/provenance, monotonic revisions/snapshot dates and retained
identities. It reuses the existing signed two-slot store, returns catalog and price
authority together, and falls back to the verified previous slot or bundle.
The builder validates output before writing/staging; complete review contradictions
retract historical permission while retaining provenance. Ordinary price absence
still retains historical membership. Quarantined rows cannot become automatic.

Production still needs the existing publisher/signing owner to establish YGO
trust pins and signed publish/restore conventions, supply a durable verified
previous-approved catalog to `--previous-seed`, and separately authorize endpoint
activation/deployment. The scheduled candidate job still starts from the checked-in
bundle, so daily approved continuity is not claimed. No new backend, production
credentials, service, deployment, purchase or commercial permission was created.

## Remaining acceptance

- Complete production distribution/activation and rights review before claiming
  live provider service.
- Resolve 436 missing-identity records and review unsupported grammar as bounded
  follow-up evidence, without expanding into OCG/Rush/non-English.
- Perform owner camera checks for real footer layouts, foil glare, alternate art,
  same-code reissues, stamps, stack/duplicate behavior and interruption/reopen.
- Keep physical-camera, CloudKit, archive/TestFlight and release certification
  separate from Simulator and fixture OCR evidence.
