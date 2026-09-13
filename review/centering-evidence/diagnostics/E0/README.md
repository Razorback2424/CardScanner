# E0 differential profile diagnostic

E0 compares per-edge profile selections for IMG_0783 and IMG_0347 across the
base, mirror, quarter-turn, and 0.6x variants. The raw per-variant records are
in this directory and the signed-line summary is `comparison.md`.

Important limitation: E0 starts from the harness's pre-normalized bitmap and
its variant card size changes with the transform and scale. `outerQuadNative`
in the comparison is native to each rendered diagnostic input; using
`outerQuadWorking` there would double-count the analyzer downscale. The table
is therefore useful for locating behavior inside this harness only. It is not
production-equivalent accuracy evidence and must not be used to tune the
detector. REQ-036's raw-HEIC/equalized replacement is complete and retained
under `../E1/resolution.json`; E0 remains a historical localization record.
