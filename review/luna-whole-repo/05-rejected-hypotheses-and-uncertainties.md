# Rejected Hypotheses and Uncertainties

## Prior defect hypotheses rechecked as fixed

The prior audit in `docs/audits/defect_review_pass_1.md` is historical evidence only. Its nine defects were re-opened against the current source and current test suite. D01–D08 are not current findings:

| Prior item | Current disposition | Current evidence |
| --- | --- | --- |
| D01 delayed newer source price | Rejected as current defect | `PriceObservationLog.isOutOfOrder` now compares source-published time when the provider publishes it and the prior observation is source-stamped; pricing tests cover the ordering boundary. |
| D02 graded identity too weak | Rejected as current defect | `GradedCardIdentity.matches` includes game/set/name/collector number and optional set slug/print-run constraints. |
| D03 graded refresh merges print runs | Rejected as current defect | V2 graded grouping and target identity include `pokemonPrintRun`. |
| D04 checkpoint watermark before durable save | Rejected as current defect | `JustTCGRefreshCoordinator` advances the complete-sync ledger only after the forced final checkpoint succeeds; `PriceRefreshController` owns terminal persistence. |
| D05 live replay misses a newly reconciled observation | Rejected as current defect | `PortfolioComputationActor.compute` uses an effective-through instant that reaches the current clock for live recomputation. |
| D06 live EUR contributes as USD | Rejected as current defect | `PortfolioEngine.applyPriceDeltas` and current valuation use `PortfolioPriceEligibility.eligibleUnitPrice`. F-006 is a different full-store transition divergence. |
| D07 freshness-only price changes invisible to revision | Rejected as current defect | `StoreRevisionMonitor` price fingerprints include fetched/checked/successful timestamps. |
| D08 graded Browse loses selected print run | Rejected as current defect | `GradedVariantPickerView` carries print-run choice through confirmation and `CollectionStore.addGraded`. |
| D09 failed scanner save contamination | Not promoted; remains unproven | Current source separates pending/failure state and shows visible failure handling, but the injected failed-save path has no complete end-to-end test proving that no subsequent retry can reuse contaminated state. This is a verification gap, not a confirmed defect. |

## Hypotheses explicitly not promoted

### Mixed Magic legacy/canonical projection

Initially, local migration runs before the first projection and deferred network migration runs after it, which looked capable of leaving a mixed projection. Reconciliation found that Magic key/treatment fields are included in the card fingerprint (`StoreRevisionMonitor.swift:450-497`), and the revision monitor rebuilds the projection when card fingerprints change (`StoreRevisionMonitor.swift:208-220`). The hypothesis is therefore **NOT PROVEN** as a persistent defect. A live CloudKit delivery trace would still be useful for transient UI ordering, but it is not a current formal finding.

### Negative provider quote acceptance

`Money` accepts finite negative values and some interactive/reference quote paths do not apply the same nonnegative guard as `PriceRecord.apply`. No current provider fixture or live response was found that sends a negative amount through those paths, and the collection/observation write path rejects negative amounts. Status: **uncertain edge case**, not promoted without a demonstrated external input and user-visible consequence.

### Global certification extraction or OCR qualifier omission

The scanner subreview considered label parsing, ROI, proximity, and certificate extraction. The current tests cover parser formats and state transitions; no source-only proof established a wrong certificate/qualifier for a supported label. Real label samples remain a coverage gap, not a confirmed misread.

### Detail/activity representative mismatch

Projection representative selection and some detail/activity fetches use different ordering strategies. The current store normally prevents duplicate exact keys, and the review found no demonstrated production state where equal-timestamp rows with conflicting metadata remain visible. Status: **not proven**; retain as a targeted duplicate-state test concern only.

### Magic snapshot freshness anomaly

The generated Magic snapshot metadata contains dates that should be checked against the intended release/source cutoff. This is provenance/freshness uncertainty, not proof that runtime lookup is wrong. The app’s manifests and resource counts are internally parseable; no network/source-of-truth comparison was available in this review.

## External uncertainties and proof boundaries

| Boundary | Status | What is not proven |
| --- | --- | --- |
| Physical camera/OCR | `BLOCKED-EXTERNAL` | 8 Hz tracking, missed/duplicate rate, slab label ROI on real labels, thermal behavior, camera restart, and tab-return behavior |
| CloudKit/account | `BLOCKED-EXTERNAL` | Store/account switching, record delivery order, late inventory arrival, private-container provisioning, and multi-device convergence |
| Live providers | `BLOCKED-EXTERNAL` | TCGdex/Scryfall/JustTCG current schemas, quotas, currencies, null/negative responses, live artwork, and transport retry behavior |
| Release signing | `BLOCKED-EXTERNAL` | Production bundle ID, provisioning, iCloud container ownership, Sign in with Apple entitlement, App Store archive/export |
| Performance | `BLOCKED-EXTERNAL` | Real-device cold collection first paint for ~1,500 cards, projection coalescing cost, live refresh profile, and memory/thermal behavior |
| UI route captures | `BLOCKED-EXTERNAL` for this review | Existing docs record simulator route captures, but no fresh manual route capture was created in this review; source/unit evidence is the basis for findings |

These are explicitly bounded external validation items, not hidden `NEEDS-FOLLOWUP` source classifications. The device procedures and available evidence are recorded in `06-device-and-environment-validation.md`.

## Adversarial self-review actions and result

This was a review pass over the completed artifacts, not a second list of untested suspicions.

- **Coverage challenge:** the least-detailed areas are leaf views, platform wrappers, and provider transport adapters classified `REVIEWED-CONTEXT`. Their callers, outputs, conditional compilation, and target membership were rechecked against the 105-file inventory; none is an unclassified production source or an unexamined target.
- **Finding challenge:** F-013 has the weakest user impact and is kept Low/conditional. F-001 was narrowed to label-first/unbound binding; F-002 was narrowed to invalidation paths that do not call `endSession`; F-006 was narrowed to a full-store non-USD transition. F-010 was rechecked against production-created graded rows rather than the existing synthetic fixture. No finding was retained solely because a comment or old audit called it a defect.
- **Architecture challenge:** the apparent mixed Magic projection issue was reopened across migration, revision fingerprinting, and projection rebuild callers and rejected as persistent. The source-of-truth map was updated to distinguish mutable records, append-only evidence, and derived snapshots; the architecture model did not need to be replaced.
- **Concurrency/lifecycle challenge:** task ownership, cancellation, migration/refresh gating, and scanner invalidation callers were traced again. This additional work confirmed F-002 and found no general claim that Swift concurrency annotations alone prove safety.
- **Performance challenge:** no theoretical complexity issue was promoted. The only cache finding is the future timestamp branch; cold launch, 8 Hz tracking, projection coalescing, and live refresh remain measurement gates in `06`.
- **Test challenge:** the 1,005-test result was treated as supporting evidence only. Existing test names and bodies were inspected for the exact paths behind F-001, F-006, F-008, F-010, and F-011; missing exact scenarios remain explicitly stated. No application test was altered or manufactured under the review contract.
- **Cross-system challenge:** collection identity, pricing currency, portfolio replay/current valuation, migration ordering, and Browse add paths were reconsidered together. That work promoted F-006/F-010/F-011, linked F-001/F-002, and retired the mixed-Magic hypothesis. No additional current-environment inspection remained capable of converting the listed external/fixture gaps into proof.

## Historical-document reconciliation

`progress.md` and `docs/plans/documentation_audit.md` state an older 940-test simulator baseline. The current Debug run discovered 1,005 tests with one skip and zero failures. Historical “closed” statements were retained only where current source/tests supported them; stale counts and historical artifact links were not used as completion proof. F-014 records the broken root README links; historical links inside older plan documents are treated as archival navigation debt unless they claim current release evidence.
