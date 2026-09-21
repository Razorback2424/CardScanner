# REQ-042 candidate recall diagnostic

This is the signed 2026-09-12 pre-remediation snapshot. The 2026-09-20
rerun writes to simulator temporary storage and is summarized in the
[diagnostic README](README.md), rather than overwriting this tracked artifact.

Signed DEBUG analyses on the original HEIC fixtures using the iOS 26.5 iPhone 17 Pro simulator.
The ledger is observational. `bestErrorPx` is the maximum perpendicular distance of the candidate line's reported points from the corresponding GT edge; it is not a production selection score.

| Fixture | GT inner | State | Inner source | Family | Side | Candidates | Best error px | Tolerance px | Best source | Best role | Within GT tolerance |
|---|---|---|---|---|---|---:|---:|---:|---|---|---|
| IMG_0347 | printed_border | confident | profile | outer | left | 15 | 11.31 | 10.23 | scalar.gradient.outer | physical_outer_candidate | false |
| IMG_0347 | printed_border | confident | profile | inner | left | 44 | 12.70 | 12.64 | scalar.gradient.inner | untyped_inner_reference | false |
| IMG_0347 | printed_border | confident | profile | outer | top | 18 | 10.46 | 9.03 | vision.card_rectangle | physical_outer_candidate | false |
| IMG_0347 | printed_border | confident | profile | inner | top | 51 | 6.64 | 12.64 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0347 | printed_border | confident | profile | outer | right | 16 | 21.18 | 19.11 | scalar.gradient.outer | physical_outer_candidate | false |
| IMG_0347 | printed_border | confident | profile | inner | right | 33 | 7.42 | 12.64 | scalar.border_walk | untyped_inner_reference | true |
| IMG_0347 | printed_border | confident | profile | outer | bottom | 17 | 1.99 | 19.25 | vision.card_rectangle | physical_outer_candidate | true |
| IMG_0347 | printed_border | confident | profile | inner | bottom | 54 | 4.28 | 12.64 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0348 | art_window | confident | visionArtWindow | outer | left | 12 | 19.26 | 27.43 | scalar.silhouette | physical_outer_candidate | true |
| IMG_0348 | art_window | confident | visionArtWindow | inner | left | 27 | 9.51 | 12.68 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0348 | art_window | confident | visionArtWindow | outer | top | 17 | 23.82 | 16.52 | vision.card_rectangle | physical_outer_candidate | false |
| IMG_0348 | art_window | confident | visionArtWindow | inner | top | 34 | 12.51 | 12.68 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0348 | art_window | confident | visionArtWindow | outer | right | 13 | 7.93 | 9.06 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0348 | art_window | confident | visionArtWindow | inner | right | 24 | 6.45 | 12.68 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0348 | art_window | confident | visionArtWindow | outer | bottom | 17 | 38.21 | 9.87 | vision.card_rectangle | unknown_outer_candidate | false |
| IMG_0348 | art_window | confident | visionArtWindow | inner | bottom | 42 | 14.98 | 12.68 | scalar.gradient.inner | untyped_inner_reference | false |
| IMG_0349 | art_window | confident | profile | outer | left | 16 | 12.18 | 27.61 | vision.card_rectangle | physical_outer_candidate | true |
| IMG_0349 | art_window | confident | profile | inner | left | 54 | 7.15 | 13.32 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0349 | art_window | confident | profile | outer | top | 16 | 7.57 | 13.51 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0349 | art_window | confident | profile | inner | top | 51 | 10.08 | 13.32 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0349 | art_window | confident | profile | outer | right | 13 | 4.45 | 11.38 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0349 | art_window | confident | profile | inner | right | 41 | 4.31 | 13.32 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0349 | art_window | confident | profile | outer | bottom | 13 | 12.32 | 20.64 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0349 | art_window | confident | profile | inner | bottom | 37 | 13.00 | 13.32 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0350 | printed_border | confident | profile | outer | left | 17 | 7.47 | 12.87 | vision.card_rectangle | physical_outer_candidate | true |
| IMG_0350 | printed_border | confident | profile | inner | left | 50 | 5.12 | 13.13 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0350 | printed_border | confident | profile | outer | top | 17 | 8.20 | 10.70 | vision.card_rectangle | physical_outer_candidate | true |
| IMG_0350 | printed_border | confident | profile | inner | top | 51 | 3.22 | 13.13 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0350 | printed_border | confident | profile | outer | right | 16 | 3.13 | 11.07 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0350 | printed_border | confident | profile | inner | right | 39 | 7.06 | 13.13 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0350 | printed_border | confident | profile | outer | bottom | 19 | 11.17 | 18.15 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0350 | printed_border | confident | profile | inner | bottom | 52 | 8.39 | 13.13 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0351 | art_window | confident | profile | outer | left | 14 | 5.49 | 29.56 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0351 | art_window | confident | profile | inner | left | 56 | 2.86 | 12.82 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0351 | art_window | confident | profile | outer | top | 17 | 14.80 | 14.40 | scalar.gradient.outer | physical_outer_candidate | false |
| IMG_0351 | art_window | confident | profile | inner | top | 51 | 11.06 | 12.82 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0351 | art_window | confident | profile | outer | right | 15 | 7.66 | 13.03 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0351 | art_window | confident | profile | inner | right | 45 | 11.62 | 12.82 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0351 | art_window | confident | profile | outer | bottom | 18 | 11.80 | 20.71 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0351 | art_window | confident | profile | inner | bottom | 48 | 13.71 | 12.82 | profile.normalized_gradient | untyped_inner_reference | false |
| IMG_0352 | printed_border | confident | profile | outer | left | 13 | 15.88 | 16.46 | vision.card_rectangle | physical_outer_candidate | true |
| IMG_0352 | printed_border | confident | profile | inner | left | 45 | 17.10 | 12.63 | profile.normalized_gradient | untyped_inner_reference | false |
| IMG_0352 | printed_border | confident | profile | outer | top | 13 | 4.91 | 13.96 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0352 | printed_border | confident | profile | inner | top | 63 | 5.19 | 12.63 | scalar.border_walk | untyped_inner_reference | true |
| IMG_0352 | printed_border | confident | profile | outer | right | 11 | 2.39 | 9.02 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0352 | printed_border | confident | profile | inner | right | 47 | 4.45 | 12.63 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0352 | printed_border | confident | profile | outer | bottom | 15 | 19.84 | 25.78 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0352 | printed_border | confident | profile | inner | bottom | 59 | 8.74 | 12.63 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0780 | art_window | confident | profile | outer | left | 13 | 5.42 | 17.39 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0780 | art_window | confident | profile | inner | left | 36 | 0.98 | 13.03 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0780 | art_window | confident | profile | outer | top | 14 | 2.01 | 9.31 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0780 | art_window | confident | profile | inner | top | 33 | 6.16 | 13.03 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0780 | art_window | confident | profile | outer | right | 11 | 23.82 | 28.10 | scalar.silhouette | physical_outer_candidate | true |
| IMG_0780 | art_window | confident | profile | inner | right | 35 | 15.46 | 13.03 | scalar.gradient.inner | untyped_inner_reference | false |
| IMG_0780 | art_window | confident | profile | outer | bottom | 13 | 5.31 | 9.31 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0780 | art_window | confident | profile | inner | bottom | 38 | 236.42 | 13.03 | vision.card_rectangle | unknown_inner_candidate | false |
| IMG_0781 | printed_border | confident | scalarInner | outer | left | 14 | 3.56 | 14.23 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0781 | printed_border | confident | scalarInner | inner | left | 61 | 12.58 | 13.03 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0781 | printed_border | confident | scalarInner | outer | top | 18 | 1.36 | 9.31 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0781 | printed_border | confident | scalarInner | inner | top | 55 | 0.50 | 13.03 | scalar.gradient.inner | untyped_inner_reference | true |
| IMG_0781 | printed_border | confident | scalarInner | outer | right | 13 | 11.42 | 20.38 | scalar.mask_outline | physical_outer_candidate | true |
| IMG_0781 | printed_border | confident | scalarInner | inner | right | 51 | 5.89 | 13.03 | scalar.border_walk | untyped_inner_reference | true |
| IMG_0781 | printed_border | confident | scalarInner | outer | bottom | 16 | 2.87 | 9.31 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0781 | printed_border | confident | scalarInner | inner | bottom | 44 | 57.03 | 13.03 | vision.card_rectangle | printed_border | false |
| IMG_0782 | none | declined | none | outer | left | 12 | 3.90 | 11.31 | scalar.mask_outline | physical_outer_candidate | true |
| IMG_0782 | none | declined | none | inner | left | 39 | — | — | — | — | — |
| IMG_0782 | none | declined | none | outer | top | 11 | 2.59 | 9.31 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0782 | none | declined | none | inner | top | 44 | — | — | — | — | — |
| IMG_0782 | none | declined | none | outer | right | 9 | 10.42 | 17.15 | scalar.mask_outline | physical_outer_candidate | true |
| IMG_0782 | none | declined | none | inner | right | 37 | — | — | — | — | — |
| IMG_0782 | none | declined | none | outer | bottom | 11 | 4.33 | 11.94 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0782 | none | declined | none | inner | bottom | 34 | — | — | — | — | — |
| IMG_0783 | printed_border | confident | profile | outer | left | 12 | 3.75 | 10.63 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0783 | printed_border | confident | profile | inner | left | 55 | 7.68 | 13.01 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0783 | printed_border | confident | profile | outer | top | 19 | 2.36 | 9.29 | scalar.gradient.outer | physical_outer_candidate | true |
| IMG_0783 | printed_border | confident | profile | inner | top | 62 | 1.21 | 13.01 | profile.normalized_gradient | untyped_inner_reference | true |
| IMG_0783 | printed_border | confident | profile | outer | right | 12 | 9.76 | 19.54 | scalar.mask_outline | physical_outer_candidate | true |
| IMG_0783 | printed_border | confident | profile | inner | right | 44 | 5.44 | 13.01 | scalar.border_walk | untyped_inner_reference | true |
| IMG_0783 | printed_border | confident | profile | outer | bottom | 16 | 0.53 | 9.32 | outer_refinement.normal_profile | physical_outer_candidate | true |
| IMG_0783 | printed_border | confident | profile | inner | bottom | 43 | 65.58 | 13.01 | profile.normalized_gradient | untyped_inner_reference | false |
