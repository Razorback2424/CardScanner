# REQ-041 named stage timing profile

Signed DEBUG analyses on the iOS 26.5 iPhone 17 Pro simulator. Each fixture was analyzed twice.
The attribution fraction is the sum of the named stage timers divided by the independently measured wall time.

| Stage | Median seconds | Max seconds | Median share of wall time |
|---|---:|---:|---:|
| `decodeOrientationDownscale` | 0.1989 | 0.2199 | 0.072 |
| `colorPreparation` | 0.1292 | 0.1377 | 0.045 |
| `visionRequests` | 0.0204 | 0.0225 | 0.008 |
| `scalarFields` | 1.4807 | 1.6622 | 0.546 |
| `outerCandidateRefinement` | 0.1214 | 0.1252 | 0.044 |
| `innerCandidateGeneration` | 0.8305 | 0.8633 | 0.304 |
| `jointSelection` | 0.0000 | 0.0000 | 0.000 |
| `rectification` | 0.0001 | 0.0001 | 0.000 |
| `resultConstruction` | 0.0000 | 0.0000 | 0.000 |

Named-stage attribution median/max: 1.000 / 1.000
Wall-time median/max: 2.7412 / 2.9733 seconds
