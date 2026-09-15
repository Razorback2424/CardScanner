# CardScanner App Review Preflight

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task; this is not a substitute for an independent reviewer report.

**Current checkout:** `codex/scanning-workflow-review-remediation` at
`0b4ac34`. This is the current preflight summary; the candidate identity below
is retained as historical context from the earlier remediation pass.

**Historical candidate:** `fix/app-review-preflight` at baseline `a115e4e`, with
the earlier working-tree implementation changes preserved.

The candidate remains NO-GO. The latest remediation pass applies source-level
fixes for the four storage/readiness findings: cached-empty checkpoints,
explicit replica-state classification and identity rotation, current-anchor
validation in headless preflight, and same-process storage-session reuse.
External enrollment, physical-device, and public-link gates remain separate and
are not sufficient to certify the candidate.

## Eligible remediation scope

- Blocker: make local/cloud storage configuration truthful and fail closed.
- Blocker: validate the manifest, store URL, SQLite sidecars, and opaque file
  identity before opening any replacement store.
- Blocker: claim a new remote anchor before constructing an exporting store.
- Blocker: keep restoration readiness fail-closed until an evidence mechanism is
  implemented and tested; add the missing observability/continuity harnesses.
- Blocker: reject cached empty readiness and require a current remote-generation
  match before even a cached populated checkpoint may be used; cached populated
  state remains non-authoritative.
- Blocker: classify absent replicas, orphaned journals, missing sidecars, and
  mismatched sidecars separately; only a completely absent replica may enter
  automatic restoration, and a restored physical store receives a new identity
  at physical store replacement before container construction; readiness
  authority remains checkpoint-only.
- High: make background refresh work from a fresh process only after a persisted
  readiness/checkpoint preflight.
- High: fetch and validate the current CloudKit anchor during headless preflight,
  and reuse an active process-authoritative session rather than constructing a
  second container or rotating the foreground generation.
- High: fence Magic treatment migration with the storage generation.
- High: repair the screenshot verification bundle identifier.
- Specification gap: add production-entry ownership-ledger coverage and retain
  the ledger as non-authoritative until that coverage passes.

## Explicitly not certified here

Physical Task 4B architecture selection, CloudKit production schema,
two-device convergence, archive/TestFlight, public URLs, and a clean full-suite
pass still require owner-controlled follow-up. The current host has recorded
focused storage results; the latest logged full run discovered 1,256 tests and
reported 48 fixture/source-environment or signal-kill failures. The current
release ledger is the evidence authority.
