# E7 resolution and latency curve

> **Artifact state:** This tracked snapshot was emitted during the intermediate
> transition-width-guard invariant run, before the final E-REQ044 per-side
> fallback. It is not the final post-change curve. The original signed
> pre-E-REQ044 bundle is retained as
> `req027-groundtruth-e7-refresh.xcresult` on the external SSD; a complete
> post-per-side-fallback rerun remains pending.

This diagnostic uses the production analyzer entry point with only its DEBUG benchmark resolution override. Ground truth was rederived under REQ-027; `ratioPassAt2PP` is adjudicable against the current records but does not by itself close the broader L1/REQ-045 gate.

| Max working dimension | Median seconds | Max seconds | Gradeable/confident | Ratio pass at 2 pp |
|---:|---:|---:|---:|---:|
| 1200 | 2.733 | 2.972 | 9/10 | 2/10 |
| 1600 | 3.895 | 4.703 | 7/10 | 1/10 |
| 2000 | 5.316 | 6.558 | 7/10 | 1/10 |
| 2400 | 7.974 | 9.748 | 8/10 | 1/10 |

## Per-fixture records

| Fixture | Working max | Detection max | Seconds | Working size | Card H px | State | LR error pp | TB error pp |
|---|---:|---:|---:|---:|---:|---|---:|---:|
| `IMG_0347` | 1200 | 1200 | 2.704 | 913x1210 | 1076.4 | confident | 19.961 | 0.623 |
| `IMG_0348` | 1200 | 1200 | 2.574 | 900x1200 | 1100.1 | confident | 0.941 | 8.499 |
| `IMG_0349` | 1200 | 1200 | 2.972 | 912x1209 | 1138.3 | confident | 0.257 | 21.954 |
| `IMG_0350` | 1200 | 1200 | 2.782 | 900x1200 | 1120.4 | confident | 16.300 | 0.198 |
| `IMG_0351` | 1200 | 1200 | 2.635 | 900x1200 | 1100.8 | confident | 2.120 | 2.597 |
| `IMG_0352` | 1200 | 1200 | 2.733 | 909x1207 | 1074.9 | confident | 1.850 | 1.139 |
| `IMG_0780` | 1200 | 1200 | 2.830 | 900x1200 | 1111.3 | confident | 5.623 | 21.123 |
| `IMG_0781` | 1200 | 1200 | 2.643 | 900x1200 | 1108.1 | confident | 3.247 | 7.467 |
| `IMG_0782` | 1200 | 1200 | 2.789 | 900x1200 | 1111.2 | declined | — | — |
| `IMG_0783` | 1200 | 1200 | 2.719 | 900x1200 | 1106.2 | confident | 12.820 | 6.520 |
| `IMG_0347` | 1600 | 1600 | 3.900 | 1217x1613 | 1428.5 | confident | 4.467 | 2.507 |
| `IMG_0348` | 1600 | 1600 | 3.778 | 1223x1617 | 1470.7 | declined | 11.015 | 29.210 |
| `IMG_0349` | 1600 | 1600 | 4.569 | 1217x1613 | 1518.6 | declined | — | — |
| `IMG_0350` | 1600 | 1600 | 4.703 | 1200x1600 | 1494.0 | confident | 9.743 | 0.249 |
| `IMG_0351` | 1600 | 1600 | 3.871 | 1200x1600 | 1468.8 | confident | 2.142 | 11.888 |
| `IMG_0352` | 1600 | 1600 | 4.090 | 1213x1610 | 1432.5 | confident | 2.482 | 1.071 |
| `IMG_0780` | 1600 | 1600 | 3.757 | 1200x1600 | 1482.4 | confident | 4.974 | 21.037 |
| `IMG_0781` | 1600 | 1600 | 3.838 | 1200x1600 | 1477.5 | confident | 9.119 | 7.176 |
| `IMG_0782` | 1600 | 1600 | 3.883 | 1200x1600 | 1482.1 | declined | — | — |
| `IMG_0783` | 1600 | 1600 | 3.895 | 1200x1600 | 1475.1 | confident | 5.694 | 17.251 |
| `IMG_0347` | 2000 | 2000 | 5.240 | 1522x2016 | 1785.8 | confident | 4.549 | 2.344 |
| `IMG_0348` | 2000 | 2000 | 5.042 | 1517x2013 | 1831.7 | declined | 10.889 | 30.965 |
| `IMG_0349` | 2000 | 2000 | 6.558 | 1514x2011 | 1896.4 | declined | — | — |
| `IMG_0350` | 2000 | 2000 | 5.371 | 1500x2000 | 1867.4 | confident | 16.360 | 0.129 |
| `IMG_0351` | 2000 | 2000 | 5.187 | 1500x2000 | 1835.8 | confident | 1.821 | 3.438 |
| `IMG_0352` | 2000 | 2000 | 5.628 | 1515x2011 | 1790.9 | confident | 2.901 | 1.219 |
| `IMG_0780` | 2000 | 2000 | 5.296 | 1500x2000 | 1853.3 | confident | 5.808 | 21.040 |
| `IMG_0781` | 2000 | 2000 | 5.727 | 1500x2000 | 1847.5 | confident | 25.707 | 17.058 |
| `IMG_0782` | 2000 | 2000 | 5.264 | 1500x2000 | 1853.6 | declined | — | — |
| `IMG_0783` | 2000 | 2000 | 5.316 | 1500x2000 | 1844.3 | confident | 4.919 | 19.273 |
| `IMG_0347` | 2400 | 2400 | 7.435 | 1826x2419 | 2143.7 | confident | 5.011 | 2.280 |
| `IMG_0348` | 2400 | 2400 | 7.170 | 1838x2429 | 2205.4 | declined | 10.801 | 31.709 |
| `IMG_0349` | 2400 | 2400 | 8.411 | 1828x2421 | 2277.0 | confident | 42.830 | 39.673 |
| `IMG_0350` | 2400 | 2400 | 7.906 | 1800x2400 | 2240.8 | confident | 16.363 | 0.299 |
| `IMG_0351` | 2400 | 2400 | 7.351 | 1800x2400 | 2202.6 | confident | 1.599 | 11.567 |
| `IMG_0352` | 2400 | 2400 | 7.974 | 1818x2414 | 2149.2 | confident | 3.129 | 1.318 |
| `IMG_0780` | 2400 | 2400 | 7.603 | 1800x2400 | 2224.4 | confident | 5.456 | 21.184 |
| `IMG_0781` | 2400 | 2400 | 9.748 | 1800x2400 | 2217.5 | confident | 27.678 | 17.576 |
| `IMG_0782` | 2400 | 2400 | 8.135 | 1800x2400 | 2224.0 | declined | — | — |
| `IMG_0783` | 2400 | 2400 | 9.670 | 1800x2400 | 2212.7 | confident | 8.786 | 22.281 |
