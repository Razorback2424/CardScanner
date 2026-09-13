# E-C raw-HEIC resolution-normalized metamorphic diagnostic

E-C is the named replacement for the earlier E1 harness. Each variant starts
from the original HEIC bytes, decodes through `UIImage(data:)` so the fixture's
display orientation is retained, and then applies only the requested mirror,
quarter-turn, or scale transform. The retained records are in
`resolution.json`; they contain source storage/display dimensions, raw and
equalized GT-derived working dimensions, both analyzer measurements, and both
confidence states.

The run covers `IMG_0783` and `IMG_0347`, the clean and sleeved fixtures used by
E0. Both source files decode as 4032×3024 storage pixels and 3024×4032 display
pixels. The analyzer's 1200-pixel working cap is already active for the raw
variants, so the GT-derived working short edge is effectively constant before
equalization: 643.2 px for IMG_0783 and 631.2 px for IMG_0347. Every raw and
equalized record is within the required ±0.5% of its fixture's base short edge;
the equalization assertion passed. The requested scale remains 0.6 for the
0.6× variant because no additional scale is needed to reach the base effective
resolution.

The harness correction is therefore validated, but it does not by itself make
the analyzer invariant pass. At this fixed effective resolution IMG_0783 is
confident for all six variants. IMG_0347 is confident for base, mirrorX,
rot180, and scale0.6, but declines for rot90 and rot270 in both the raw and
equalized records. This is evidence of orientation-dependent branch behavior, not
a claim that the analyzer invariants or L1 accuracy pass. The checked-in GT is now
the rederived analyzer-free set; current production-entry-point failures against it
are recorded in the REQ-027 result bundle and status documents.

The earlier pre-downsampled E1 values remain historical under the E1 section of
`experiments-log.md`. E0 remains a diagnostic-only, pre-downsampled profile
localization harness. No production code or ground-truth record was changed by
E-C.
