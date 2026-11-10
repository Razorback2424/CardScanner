# Review and Evidence Guide

**Scope:** `review/` (centering harness, centering evidence, review plans, and `legacy/`). Also follow the root [`AGENTS.md`](../AGENTS.md); documentation edits also follow [`docs/AGENTS.md`](../docs/AGENTS.md).

## Pick the right authority first

Centering work has three acceptance contexts with different requirements. Check [`docs/README.md`](../docs/README.md) for the current owner of each before interpreting a result:

| Context | Current authority |
| --- | --- |
| Guided repair (user-assisted measurement) | [`docs/audits/centering-guided-repair.md`](../docs/audits/centering-guided-repair.md) |
| Automatic detection and held-out acceptance | [`opus-card-centering-implementation-plan.md`](opus-card-centering-implementation-plan.md) |
| Harness tooling and its rules | [`centering-harness/README.md`](centering-harness/README.md) |

Dated measurements and screenshots live in [`centering-evidence/`](centering-evidence/). [`legacy/`](legacy/) is historical: its SHAs, counts, and "current" wording are not current unless a current authority reruns and adopts them. Do not edit legacy findings to look current.

## Running investigations

- Write each run to a **new** output directory, preferably on the external SSD. The harness refuses to overwrite an existing output (`corpus_main.swift`, `edge_annotation_audit.py`); do not work around that.
- Record candidate identity (SHA, dirty-tree state), input hashes, configuration/settings, outputs, and failures for every run. Inputs are hash-checked against the manifest; a mismatch is a stop, not a warning.
- Use development fixtures while developing. Never read, tune against, or report interim numbers from sealed holdout/supplementary sets; preserve their split assignments.
- Keep ground truth independent of the detector under evaluation. Detector candidates (for example the E4 candidates) must never be copied into `*.gt.json` or promoted to ground truth.
- Production corpus output is **unscored** without reviewed references; say so rather than implying accuracy.

## Claims

- A mathematical, synthetic, or harness-only result is not demonstrated physical-image accuracy. Investigation tooling here does not replace the required app-target tests (see [`../TradingCardScannerTests/AGENTS.md`](../TradingCardScannerTests/AGENTS.md)).
- Inspect the relevant image output (overlays, crops, review renders) before making a visual claim.
- Keep conclusions proportional to the evidence: state the fixture set, the split, and what was not covered.
- Evidence files must stay privacy-safe: no personal collection exports, account identifiers, or unredacted device logs.
