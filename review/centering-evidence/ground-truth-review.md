# Ground-truth visual review

Review date: 2026-09-12 (rederived and amended from the 2026-09-11 audit)

Reviewer: Codex visual pass and provenance audit

The current records are produced by two independent analyzer-free luminance
profile passes followed by visual adjudication against the physical silhouette.
They are no longer the five-pixel-grid records audited on 2026-09-11. The
previous records and their misleading provenance are preserved at
`ground-truth/provisional-2026-09-11/` for chronology only.

The rederivation is procedural ground-truth evidence, not a claim that every
edge is high-confidence: sleeved images sometimes lack a stable sleeve
transition, so their separately reviewed virtual sleeve traces are retained as
encasement geometry and are excluded from ratio derivation. The complete
analyzer-free profiles, candidate selections, and manifest are retained under
`diagnostics/GT-rederived/`.

The ten `<FIXTURE>_gt.png` sheets were reviewed against the oriented source
images. The red quad follows the physical card cut edge, the amber quad is
outside it where a sleeve is visible, and the cyan quad follows the selected
printed/art reference. Corner labels are ordered TL/TR/BR/BL. `IMG_0782` has
no cyan quad because its light-grey internal field is an explicit decline case.
The earlier analyzer-free E4 profile-candidate report remains separately under
`diagnostics/E4` as historical candidate evidence. It was not the final
selection source for the current records.

Checklist:

- [x] 10/10 sheets present and named after the fixture.
- [x] All sheets use the same oriented 3024 × 4032 coordinate space.
- [x] Sleeve boundaries are recorded separately on sleeved Pokémon captures.
- [x] Inner reference is absent only for the documented `IMG_0782` decline.
- [x] Edge-band values are printed on every sheet and schema-validated.
- [x] Each sheet is below the 1.5 MB tracked-artifact limit.
- [x] The reference records are not initialized from `CardCenteringAnalyzer`
      output.
- [x] Two independent analyzer-free subpixel profile passes and reconciliation
      are complete, with pre-reconciliation `agreementPx` recorded.
- [x] At least one coordinate is non-integral; the records are not a repeated
      five-pixel-grid estimate.
- [x] `ambiguousEdges` exactly follows the measured-band rule.
- [x] IMG_0349's disputed right edge is resolved inward onto the reviewed
      physical silhouette, rather than tuned to the detector.

The visual review is intentionally recorded separately from the XCTest schema
check. The provenance test, schema/aspect checks, and overlay packaging passed
in the current ground-truth test run. The current signed post-E-REQ044 suite
still fails the production accuracy entries, including the IMG_0349/IMG_0783/
IMG_0351 ratio assertions, the IMG_0780 and IMG_0348 art-window checks, and
the L1 geometry/ratio gate. These are adjudicable detector results, not
provisional-GT results. See `baseline-post-ereq044-2026-09-12.md` for the exact
result-bundle failure identifiers.

Revision-E caveat: IMG_0783's recorded `agreementPx` is 4.43156 px, about
1.6x the next-largest record. Its exact selected physical-card and
printed-border transitions must receive one focused analyzer-free visual
re-audit before its error magnitude drives candidate tuning. This scoped
re-audit does not return the other nine records, or the overall current
accuracy result, to provisional status.
