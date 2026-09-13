# Screenshot metadata artifacts

Contains the per-fixture JSON emitted beside each screenshot. The current naming
is `centering-<FIXTURE>.json`; each record
includes the fitted image frame, screen scale, coordinate mapping, detected and
ground-truth screen quads, confidence/decline state, and mapped metric deltas.
These records belong to the pre-E-B screenshot snapshot, not the current E-A/E-B
analyzer rerun. Independent screenshot-pixel validation and the manual-correction
capture remain open; see
[`../simulator-status-2026-09-11.md`](../simulator-status-2026-09-11.md).
