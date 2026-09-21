# CardScanner App Review Preflight

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task; this is not a substitute for an independent reviewer report.

**Current checkout:** `feature/catalog-and-scanner-hardening` at `7dbaf40`
(2026-09-20). This is the intended current
preflight summary. The focused remediation evidence below was recorded against
the preceding remediation commits and remains evidence for those specific runs;
no full suite was rerun at this HEAD.

**Historical candidate:** `fix/app-review-preflight` at baseline `a115e4e`, with
the earlier working-tree implementation changes preserved.

The candidate remains NO-GO. The latest remediation pass applies source-level
fixes for the four storage/readiness findings: cached-empty checkpoints,
explicit replica-state classification and identity rotation, current-anchor
validation in headless preflight, and same-process storage-session reuse.
External enrollment, physical-device, and public-link gates remain separate and
are not sufficient to certify the candidate.

## Pass-2 F01–F03 status — 2026-09-19

The requested source remediation is present in the current committed tree. F01 now has a
safe local fallback and a recoverable failed-restoration action; F02 derives the
headless container mode from the manifest and publishes the resulting active
mode; and F03 retains a pending scanner answer until its resolution task is
accepted. F03 uses recoverable retention and retry rather than a formal proof
that the busy interleaving is unreachable.

Focused simulator evidence passes the 64 storage/policy/continuity tests in
Debug and DebugProduction, the 20 readiness tests, and the new F03 regression.
The exact-candidate full simulator run at `7dbaf40` executed 1,278 tests with
6 skipped and 4 failures (1 unexpected). The candidate remains NO-GO because
this does not establish entitled-device,
CloudKit production, clean-install, background-task, archive, or full-suite
readiness.

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
focused storage results; the latest complete full run is the historical
`a4375df` run with 1,277 executed, 6 skipped, and 40 failures. No full suite was
rerun at current candidate `7dbaf40`; the current release ledger is the evidence
authority.
