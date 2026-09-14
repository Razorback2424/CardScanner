# CardScanner App Review Preflight

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task; this is not a substitute for an independent reviewer report.

Candidate: `fix/app-review-preflight` at baseline `a115e4e` with the existing
working-tree implementation changes preserved.

The candidate remains NO-GO. The supplied review identified four storage
blockers, one background-refresh regression, two specification/evidence gaps,
and a screenshot-tool bundle-identifier regression. External enrollment,
physical-device, and public-link gates remain separate and are not sufficient
to close these source-level findings.

## Eligible remediation scope

- Blocker: make local/cloud storage configuration truthful and fail closed.
- Blocker: validate the manifest, store URL, SQLite sidecars, and opaque file
  identity before opening any replacement store.
- Blocker: claim a new remote anchor before constructing an exporting store.
- Blocker: keep restoration readiness fail-closed until an evidence mechanism is
  implemented and tested; add the missing observability/continuity harnesses.
- High: make background refresh work from a fresh process only after a persisted
  readiness/checkpoint preflight.
- High: fence Magic treatment migration with the storage generation.
- High: repair the screenshot verification bundle identifier.
- Specification gap: add production-entry ownership-ledger coverage and retain
  the ledger as non-authoritative until that coverage passes.

## Explicitly not certified here

Physical Task 4B architecture selection, CloudKit production schema,
two-device convergence, archive/TestFlight, public URLs, and full XCTest
execution still require their owner-controlled environments.
