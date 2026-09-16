# Documentation Contribution Guide

**Status:** current documentation guidance — 2026-09-14

This file applies to documentation under `docs/`. Start with the [documentation
map](README.md) and the [repository documentation audit](plans/documentation_audit.md).

## Current state

- Source code, tests, build settings, and evidence from the current checkout
  outrank plans and chronological notes.
- Current release status is **not certified**. The latest recorded full
  simulator run at `a4375df` executed 1,277 tests with 6 skipped and 40
  failures. A 2026-09-16 PBX resource-ID fix made the committed centering
  corpus reachable; the focused follow-up reported 28 passed, 9 test cases
  failed on centering assertions, and 1 canceled profile-dump test, so it is
  not a full suite baseline. Browse has focused 133/133 evidence and its A8/B6
  capture; physical-device, provider, CloudKit/ownership, centering,
  archive/TestFlight, and App Store gates remain open.
- `docs/legacy/` contains preserved completed, superseded, or snapshot-specific
  documents. `review/legacy/` serves the same purpose for repository reviews.
  Their branches, SHAs, test counts, checkboxes, and “current” wording are
  historical unless a current authority explicitly reruns and adopts them.

## Update rules

1. Verify claims against the current source, tests, build configuration, or
   dated evidence before changing a status. Record the branch/SHA and date when
   candidate identity matters.
2. Keep one current authority per concern. Put a status/date near the top of
   current plans and distinguish implemented code, deterministic verification,
   manual/device/provider evidence, and owner-controlled gates.
3. When a document is completed, superseded, or stale, move it to
   `docs/legacy/` with `git mv`; do not delete it. Add a clear legacy banner and
   a link to the current replacement. Keep a pointer at the old path when
   callers or workflows still depend on that path.
4. Update the smallest relevant current plan, checklist, or release ledger,
   then add a dated entry to the root `progress.md` for verified implementation
   or evidence changes. Do not mark a hardware, provider, CloudKit, or release
   gate complete from source inspection alone.
5. Reconcile contradictions between plans explicitly in
   `plans/documentation_audit.md`. Prefer the current code and approved product
   decision; retain the older claim only in a marked archive.
6. Keep links relative and validate them after moves. Before handoff, run a
   Markdown-link check and `git diff --check`.

## Writing conventions

- Use Markdown headings, short paragraphs, tables for status/contradiction
  matrices, and checkboxes only for live work.
- Label dated snapshots as **Historical** or **Legacy**; never leave an old
  unchecked task looking like a current TODO.
- Keep documentation privacy-safe: do not commit credentials, account IDs,
  raw CloudKit identifiers, personal collection exports, or unredacted device
  evidence.
- Do not rewrite history to make a test count, route, branch, or release claim
  appear current. Update the authority boundary instead.
