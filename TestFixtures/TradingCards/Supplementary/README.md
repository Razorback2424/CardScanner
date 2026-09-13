# Supplementary fixture status

The supplementary intake is now tracked by
[`corpus-manifest.json`](corpus-manifest.json). It covers the original ten
`DEV-HISTORICAL` fixtures plus 23 additional original HEIC captures and 11 PNG
reference images. The new intake is split into 24 `DEVELOPMENT` files and 10
cryptographically frozen `HOLDOUT-INTERIM` files.

The interim holdout was selected using provenance and visible category coverage
before new analyzer work. It has `sealed_not_evaluated` status and no new
ground truth. The manifest test verifies the file list, SHA-256 values, split,
and sealed status on the pinned iPhone 17 Pro / iOS 26.5 simulator.

This does not complete REQ-040. The camera captures are all from one iPhone 15
Pro Max, and the PNGs are conservatively recorded as a document/import cohort
with unknown camera capture role. The required wide-lens, additional-device or
photographer, in-app, EXIF-reencoded, and graded-slab coverage remains
unverified. Independent ground truth is still required before final holdout
evaluation.

REQ-040 still requires at least 30 qualifying new captures spanning varied
photographers or sessions, backgrounds, devices/lenses, capture paths, sleeve
state, card face/reference type, and slab status where available. The current
interim split is a development safeguard and must not be relabeled as final
generalization evidence.

See the [evidence table](../../../review/centering-evidence/evidence-table.md),
[implementation plan](../../../review/opus-card-centering-implementation-plan.md),
and [device status](../../../review/centering-evidence/after/simulator-status-2026-09-11.md).
