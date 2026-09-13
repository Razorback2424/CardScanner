# E7 low-resolution detection with full-resolution refinement

This is the current post-E-REQ044 low-detection/full-resolution-refinement
curve generated on 2026-09-12 by the complete signed run on the pinned iPhone
17 Pro / iOS 26.5 simulator. Vision and scalar outline detection run at the
detection maximum; the profile stage runs at the working maximum. Ground truth
was rederived under REQ-027, so the ratio-error columns are adjudicable; this
benchmark does not by itself close the broader L1/REQ-045 gate.

| Working max | Detection max | Median seconds | Max seconds | Confident | Ratio pass at 2 pp |
|---:|---:|---:|---:|---:|---:|
| 1200 | 1200 | 2.786 | 2.960 | 9/10 | 3/10 |
| 1600 | 1200 | 3.173 | 3.378 | 9/10 | 3/10 |
| 2000 | 1200 | 3.403 | 3.590 | 9/10 | 3/10 |
| 2400 | 1200 | 3.716 | 3.916 | 9/10 | 3/10 |

## Per-fixture records

| Fixture | Working max | Detection max | Seconds | Working size | Card H px | State | LR error pp | TB error pp |
|---|---:|---:|---:|---:|---:|---|---:|---:|
| `IMG_0347` | 1200 | 1200 | 2.735 | 913x1210 | 1076.4 | confident | 2.887 | 0.684 |
| `IMG_0348` | 1200 | 1200 | 2.609 | 900x1200 | 1100.1 | confident | 0.941 | 8.499 |
| `IMG_0349` | 1200 | 1200 | 2.960 | 912x1209 | 1138.3 | confident | 0.300 | 26.002 |
| `IMG_0350` | 1200 | 1200 | 2.798 | 900x1200 | 1120.4 | confident | 0.525 | 0.117 |
| `IMG_0351` | 1200 | 1200 | 2.650 | 900x1200 | 1089.4 | confident | 2.175 | 9.727 |
| `IMG_0352` | 1200 | 1200 | 2.786 | 909x1207 | 1077.9 | confident | 0.563 | 0.960 |
| `IMG_0780` | 1200 | 1200 | 2.834 | 900x1200 | 1111.3 | confident | 5.623 | 21.123 |
| `IMG_0781` | 1200 | 1200 | 2.680 | 900x1200 | 1108.1 | confident | 3.247 | 7.467 |
| `IMG_0782` | 1200 | 1200 | 2.848 | 900x1200 | 1111.2 | declined | — | — |
| `IMG_0783` | 1200 | 1200 | 2.715 | 900x1200 | 1106.2 | confident | 12.820 | 6.520 |
| `IMG_0347` | 1600 | 1200 | 3.109 | 1217x1613 | 1436.8 | confident | 2.916 | 0.025 |
| `IMG_0348` | 1600 | 1200 | 3.126 | 1200x1600 | 1466.9 | confident | 0.941 | 8.499 |
| `IMG_0349` | 1600 | 1200 | 3.378 | 1216x1612 | 1517.9 | confident | 0.280 | 25.956 |
| `IMG_0350` | 1600 | 1200 | 3.157 | 1200x1600 | 1494.0 | confident | 0.377 | 0.134 |
| `IMG_0351` | 1600 | 1200 | 3.042 | 1200x1600 | 1452.9 | confident | 2.221 | 8.956 |
| `IMG_0352` | 1600 | 1200 | 3.173 | 1212x1609 | 1437.3 | confident | 0.749 | 0.973 |
| `IMG_0780` | 1600 | 1200 | 3.345 | 1200x1600 | 1482.8 | confident | 5.082 | 21.182 |
| `IMG_0781` | 1600 | 1200 | 3.156 | 1200x1600 | 1477.8 | confident | 3.578 | 7.176 |
| `IMG_0782` | 1600 | 1200 | 3.248 | 1200x1600 | 1481.9 | declined | — | — |
| `IMG_0783` | 1600 | 1200 | 3.193 | 1200x1600 | 1475.1 | confident | 12.943 | 6.505 |
| `IMG_0347` | 2000 | 1200 | 3.341 | 1522x2016 | 1796.4 | confident | 2.988 | 0.022 |
| `IMG_0348` | 2000 | 1200 | 3.374 | 1500x2000 | 1833.6 | confident | 0.941 | 8.499 |
| `IMG_0349` | 2000 | 1200 | 3.590 | 1520x2015 | 1897.9 | confident | 0.005 | 22.045 |
| `IMG_0350` | 2000 | 1200 | 3.391 | 1500x2000 | 1867.1 | confident | 0.348 | 0.032 |
| `IMG_0351` | 2000 | 1200 | 3.286 | 1500x2000 | 1816.2 | confident | 1.737 | 9.807 |
| `IMG_0352` | 2000 | 1200 | 3.392 | 1515x2012 | 1797.2 | confident | 0.881 | 0.720 |
| `IMG_0780` | 2000 | 1200 | 3.576 | 1500x2000 | 1854.2 | confident | 19.082 | 76.431 |
| `IMG_0781` | 2000 | 1200 | 3.403 | 1500x2000 | 1847.3 | confident | 2.986 | 7.700 |
| `IMG_0782` | 2000 | 1200 | 3.471 | 1500x2000 | 1852.6 | declined | — | — |
| `IMG_0783` | 2000 | 1200 | 3.490 | 1500x2000 | 1844.1 | confident | 12.833 | 6.533 |
| `IMG_0347` | 2400 | 1200 | 3.662 | 1826x2419 | 2155.9 | confident | 2.905 | 0.131 |
| `IMG_0348` | 2400 | 1200 | 3.654 | 1800x2400 | 2200.3 | confident | 0.941 | 8.499 |
| `IMG_0349` | 2400 | 1200 | 3.916 | 1824x2418 | 2277.4 | confident | 0.798 | 21.933 |
| `IMG_0350` | 2400 | 1200 | 3.750 | 1800x2400 | 2241.0 | confident | 0.352 | 0.094 |
| `IMG_0351` | 2400 | 1200 | 3.594 | 1800x2400 | 2179.5 | confident | 2.194 | 8.840 |
| `IMG_0352` | 2400 | 1200 | 3.716 | 1818x2414 | 2156.1 | confident | 0.940 | 0.916 |
| `IMG_0780` | 2400 | 1200 | 3.842 | 1800x2400 | 2225.0 | confident | 5.510 | 21.335 |
| `IMG_0781` | 2400 | 1200 | 3.689 | 1800x2400 | 2216.5 | confident | 3.247 | 7.467 |
| `IMG_0782` | 2400 | 1200 | 3.738 | 1800x2400 | 2223.4 | declined | — | — |
| `IMG_0783` | 2400 | 1200 | 3.687 | 1800x2400 | 2212.9 | confident | 12.566 | 6.516 |
