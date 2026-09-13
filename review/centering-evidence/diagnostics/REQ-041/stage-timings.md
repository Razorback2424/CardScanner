# REQ-041 named stage timing profile

Signed DEBUG analyses on the iOS 26.5 iPhone 17 Pro simulator. Each fixture was analyzed twice.
The attribution fraction is the sum of the named stage timers divided by the independently measured wall time.

| Stage | Median seconds | Max seconds | Median share of wall time |
|---|---:|---:|---:|
| `decodeOrientationDownscale` | 0.1980 | 0.2079 | 0.072 |
| `colorPreparation` | 0.1305 | 0.1380 | 0.046 |
| `visionRequests` | 0.0203 | 0.0222 | 0.008 |
| `scalarFields` | 1.4617 | 1.6679 | 0.547 |
| `outerCandidateRefinement` | 0.1197 | 0.1240 | 0.044 |
| `innerCandidateGeneration` | 0.8293 | 0.8503 | 0.307 |
| `jointSelection` | 0.0000 | 0.0000 | 0.000 |
| `rectification` | 0.0001 | 0.0001 | 0.000 |
| `resultConstruction` | 0.0000 | 0.0000 | 0.000 |

Named-stage attribution median/max: 1.000 / 1.000
Wall-time median/max: 2.7195 / 2.9462 seconds
