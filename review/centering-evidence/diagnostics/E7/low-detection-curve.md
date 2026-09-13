# E7 low-resolution detection with full-resolution refinement

> **Artifact state:** This tracked snapshot was emitted during the intermediate
> transition-width-guard invariant run, before the final E-REQ044 per-side
> fallback. It is not the final post-change curve. The original signed
> pre-E-REQ044 bundle is retained as
> `req027-groundtruth-e7-refresh.xcresult` on the external SSD; a complete
> post-per-side-fallback rerun remains pending.

Vision and scalar outline detection run at the detection maximum; the profile stage runs at the working maximum. Ground truth was rederived under REQ-027, so the ratio-error columns are adjudicable; this benchmark does not by itself close the broader L1/REQ-045 gate.

| Working max | Detection max | Median seconds | Max seconds | Confident | Ratio pass at 2 pp |
|---:|---:|---:|---:|---:|---:|
| 1200 | 1200 | 2.722 | 2.975 | 9/10 | 2/10 |
| 1600 | 1200 | 3.153 | 3.337 | 9/10 | 1/10 |
| 2000 | 1200 | 3.401 | 3.570 | 9/10 | 1/10 |
| 2400 | 1200 | 3.685 | 3.861 | 9/10 | 1/10 |

## Per-fixture records

| Fixture | Working max | Detection max | Seconds | Working size | Card H px | State | LR error pp | TB error pp |
|---|---:|---:|---:|---:|---:|---|---:|---:|
| `IMG_0347` | 1200 | 1200 | 2.722 | 913x1210 | 1076.4 | confident | 19.961 | 0.623 |
| `IMG_0348` | 1200 | 1200 | 2.566 | 900x1200 | 1100.1 | confident | 0.941 | 8.499 |
| `IMG_0349` | 1200 | 1200 | 2.975 | 912x1209 | 1138.3 | confident | 0.257 | 21.954 |
| `IMG_0350` | 1200 | 1200 | 2.763 | 900x1200 | 1120.4 | confident | 16.300 | 0.198 |
| `IMG_0351` | 1200 | 1200 | 2.662 | 900x1200 | 1100.8 | confident | 2.120 | 2.597 |
| `IMG_0352` | 1200 | 1200 | 2.719 | 909x1207 | 1074.9 | confident | 1.850 | 1.139 |
| `IMG_0780` | 1200 | 1200 | 2.817 | 900x1200 | 1111.3 | confident | 5.623 | 21.123 |
| `IMG_0781` | 1200 | 1200 | 2.675 | 900x1200 | 1108.1 | confident | 3.247 | 7.467 |
| `IMG_0782` | 1200 | 1200 | 2.821 | 900x1200 | 1111.2 | declined | — | — |
| `IMG_0783` | 1200 | 1200 | 2.714 | 900x1200 | 1106.2 | confident | 12.820 | 6.520 |
| `IMG_0347` | 1600 | 1200 | 3.088 | 1217x1613 | 1436.8 | confident | 19.973 | 0.006 |
| `IMG_0348` | 1600 | 1200 | 3.094 | 1200x1600 | 1466.9 | confident | 0.941 | 8.499 |
| `IMG_0349` | 1600 | 1200 | 3.337 | 1216x1612 | 1517.7 | confident | 0.910 | 21.925 |
| `IMG_0350` | 1600 | 1200 | 3.143 | 1200x1600 | 1494.1 | confident | 16.312 | 0.183 |
| `IMG_0351` | 1600 | 1200 | 3.042 | 1200x1600 | 1469.0 | confident | 2.316 | 11.444 |
| `IMG_0352` | 1600 | 1200 | 3.097 | 1212x1609 | 1433.2 | confident | 2.139 | 0.940 |
| `IMG_0780` | 1600 | 1200 | 3.319 | 1200x1600 | 1482.8 | confident | 5.082 | 21.182 |
| `IMG_0781` | 1600 | 1200 | 3.162 | 1200x1600 | 1477.8 | confident | 3.578 | 7.176 |
| `IMG_0782` | 1600 | 1200 | 3.199 | 1200x1600 | 1481.9 | declined | — | — |
| `IMG_0783` | 1600 | 1200 | 3.153 | 1200x1600 | 1475.1 | confident | 12.943 | 6.505 |
| `IMG_0347` | 2000 | 1200 | 3.349 | 1522x2016 | 1796.4 | confident | 10.213 | 0.080 |
| `IMG_0348` | 2000 | 1200 | 3.329 | 1500x2000 | 1833.6 | confident | 0.941 | 8.499 |
| `IMG_0349` | 2000 | 1200 | 3.545 | 1520x2015 | 1897.3 | confident | 0.017 | 25.910 |
| `IMG_0350` | 2000 | 1200 | 3.401 | 1500x2000 | 1867.1 | confident | 16.327 | 0.103 |
| `IMG_0351` | 2000 | 1200 | 3.267 | 1500x2000 | 1836.9 | confident | 2.059 | 3.401 |
| `IMG_0352` | 2000 | 1200 | 3.349 | 1515x2012 | 1791.6 | confident | 2.659 | 0.851 |
| `IMG_0780` | 2000 | 1200 | 3.570 | 1500x2000 | 1854.2 | confident | 19.082 | 76.431 |
| `IMG_0781` | 2000 | 1200 | 3.369 | 1500x2000 | 1847.3 | confident | 2.986 | 7.700 |
| `IMG_0782` | 2000 | 1200 | 3.421 | 1500x2000 | 1852.6 | declined | — | — |
| `IMG_0783` | 2000 | 1200 | 3.416 | 1500x2000 | 1844.1 | confident | 12.833 | 6.533 |
| `IMG_0347` | 2400 | 1200 | 3.616 | 1826x2419 | 2155.9 | confident | 19.890 | 0.106 |
| `IMG_0348` | 2400 | 1200 | 3.571 | 1800x2400 | 2200.3 | confident | 0.941 | 8.499 |
| `IMG_0349` | 2400 | 1200 | 3.861 | 1824x2418 | 2277.5 | confident | 0.822 | 25.878 |
| `IMG_0350` | 2400 | 1200 | 3.692 | 1800x2400 | 2241.0 | confident | 9.452 | 0.099 |
| `IMG_0351` | 2400 | 1200 | 3.516 | 1800x2400 | 2205.6 | confident | 2.245 | 2.972 |
| `IMG_0352` | 2400 | 1200 | 3.665 | 1818x2414 | 2149.9 | confident | 2.377 | 0.835 |
| `IMG_0780` | 2400 | 1200 | 3.852 | 1800x2400 | 2225.0 | confident | 5.510 | 21.335 |
| `IMG_0781` | 2400 | 1200 | 3.633 | 1800x2400 | 2216.5 | confident | 3.247 | 7.467 |
| `IMG_0782` | 2400 | 1200 | 3.722 | 1800x2400 | 2223.4 | declined | — | — |
| `IMG_0783` | 2400 | 1200 | 3.685 | 1800x2400 | 2212.9 | confident | 12.566 | 6.516 |
