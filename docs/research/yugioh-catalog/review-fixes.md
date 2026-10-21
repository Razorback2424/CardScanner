# Yu-Gi-Oh! merged review follow-up — 2026-10-20

> **Historical snapshot.** The [audited contract](../../plans/yugioh_code_implementation.md) supersedes this document's complete-family prerequisite and starter-catalog gate. Its earlier repair/test evidence remains historical; see [current verification](audited-verification.md).

Base: clean `main` at `4c3e53c`. This follow-up records corrections made after
the initial implementation verification.
The [earlier verification](verification.md) remains historical evidence for its
stated revision. This follow-up does not approve a production starter catalog.

## Availability and integrity

The runtime exposes no capabilities or adapters when no printing passes the
acquisition resolver. App defaults report the bundled Yu-Gi-Oh! catalog as
unavailable. All 46,504 bundled printings remain quarantined; the edition review
file and bundled seed are unchanged. A genuinely reviewed subset can enable
the runtime; no price observation or group-wide edition union enables it.

The direct printing resolver now rejects incomplete codes, partially reviewed
families and insufficiently distinguishable choices, consistently with scanning.
Browse, CSV validation/metadata and collection mutation validation use this
resolver. Existing-holding identity/edition validation is separate for variant
correction and exact pricing authority; collection mutation validation remains
strict and no general maintenance exception authorizes acquisitions.

An empty edition-choice gate now files the original evidence to Needs attention,
fails the recognition acknowledgement, closes the scan interval and offers a
fresh scan. Conflicting evidence explicitly explains that a new scan is needed.
The recovery record remains intact through lookup retry.

Release order now uses epoch days, matching Browse Add. Workflow regressions
compare the persisted scan row with a real Browse Add write and a fresh-store
CSV import followed by the same catalog normalization used by Settings.
The test exposed an additional import gap: CSV omits release order, and rows
that already have artwork/catalog identity skip normalization. Import adapters
can now supply verified local metadata inside the CSV transaction; Yu-Gi-Oh!
uses its acquisition resolver to restore epoch-day order immediately. Other
adapters default to no local metadata and keep their existing behavior.

## Builder correspondence

Equal rarity/printing counts are only necessary checks. Every product must also
correspond to an existing source card/set/rarity row, and the matched rows must
cover the source rows for the code. Exact normalized labels can corroborate a
match; differing provider names require product-specific review metadata:

```json
{
  "editions": ["yugioh1stEdition"],
  "complete": true,
  "evidence": "independent physical-edition evidence reference",
  "sourcePrintings": [
    {"cardID": 123, "setName": "Exact source set name", "rarity": "Exact source rarity"}
  ],
  "correspondenceEvidence": "independent product-to-source correspondence reference"
}
```

This is a schema example, not an approved product. Missing, stale or contradictory
correspondence quarantines the entire code. Manual-eligibility statistics also
require the whole family's physical edition coverage. The committed broad seed
has not been regenerated under these stronger checks and remains unusable.
Regenerate offline before approving/enabling a starter subset.

## Starter catalog boundary

A bounded source check found Konami's
[Rarity Collection II product description](https://www.yugioh-card.com/en/products/ra02/)
and [2016 Mega-Tins description](https://www.yugioh-card.com/en/products/past_products/tin-2016megatin/).
They establish product configurations and rarities, but do not enumerate the
complete product-specific First/Unlimited/Limited edition universe needed for
approval. They are insufficient grounds to set `complete: true`. No production
product was approved on this evidence. Remaining work is independent physical
edition/correspondence review of a bounded representative subset, offline seed
rebuild, and the full workflow on that real subset. Synthetic chains do not
substitute for that gate or physical-camera validation.

## Verification

Logs and result bundles use the external SSD under
`CardScannerBuilds/yugioh/`; simulator work used only the dedicated
`YuGiOh Integration QA` simulator.

| Run | Result |
|---|---|
| Python builder self-test | 14 passed, including equal-count/singleton mismatches and reviewed correspondence |
| `review-fixes-1.xcresult` | 21 tests, 6 assertion failures: four obsolete enabled-capability expectations and two CSV release-order assertions |
| `review-fixes-2.xcresult` | 139 tests, 4 assertion failures: normalization was skipped for imports already carrying artwork/catalog identity, leaving order zero |
| `review-fixes-3.xcresult` | **170 passed, 0 failed, 0 skipped** after local import metadata repair |
| Boundary audit | Fails with 48 existing branches; none of its five scanned files changed |
| Local Markdown links and `git diff --check` | Pass |

The final Swift run covers `YuGiOhCatalogTests`, `YuGiOhResolutionTests`,
`YuGiOhWorkflowTests`, `YuGiOhImportTests`, `YuGiOhPricingTests`,
`ScannerViewModelTests`, `CSVImportResumeTests` and `CatalogNormalizationTests`.
The full test target was not run. Reproduce it with:

```bash
out='/Volumes/<external-SSD>/CardScannerBuilds/yugioh'
classes=(YuGiOhCatalogTests YuGiOhResolutionTests YuGiOhWorkflowTests
  YuGiOhImportTests YuGiOhPricingTests ScannerViewModelTests
  CSVImportResumeTests CatalogNormalizationTests)
only=(); for cls in $classes; do only+=(-only-testing:TradingCardScannerTests/$cls); done
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=YuGiOh Integration QA' \
  -derivedDataPath "$out/DerivedData" -clonedSourcePackagesDirPath "$out/SourcePackages" \
  -parallel-testing-enabled NO $only CODE_SIGNING_ALLOWED=NO
python3 -I scripts/build_yugioh_catalog.py --self-test
bash scripts/audit_game_boundaries.sh
git diff --check
```

HIG gate (source review): **Verdict PASS; top issues: none in this scoped change.**

| Category | Status and rationale | Minimal fix remaining |
|---|---|---|
| Platform patterns | PASS: existing acknowledgement/retry presentation; no navigation changes | None |
| Clarity | PASS: conflict message explains that another scan is needed | None |
| Typography | PASS: no changes to existing type styles | None |
| Accessibility | PASS: existing text/retry presentation retained; no new motion, geometry or visual-only status | None |
| Interaction cost | PASS: one existing retry action; no blocking prompt added | None |
| Design risk | PASS: terminal failure replaces a saving spinner with a truthful outcome | None |

No rendered UI, physical camera/device, provider rights, CloudKit, archive or
release acceptance is claimed. Real starter-catalog workflow validation remains
open; both full persistence chains here use synthetic reviewed fixtures.
