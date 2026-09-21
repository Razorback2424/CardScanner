# REQ-041 named stage timing profile

Signed DEBUG analyses on the iOS 26.5 iPhone 17 Pro simulator. Each fixture was analyzed twice.
The attribution fraction is the sum of the named stage timers divided by the independently measured wall time.

| Stage | Median seconds | Max seconds | Median share of wall time |
|---|---:|---:|---:|
| `decodeOrientationDownscale` | 0.1937 | 0.2012 | 0.073 |
| `colorPreparation` | 0.1237 | 0.1307 | 0.044 |
| `visionRequests` | 0.0201 | 0.0220 | 0.008 |
| `scalarFields` | 1.4322 | 1.6177 | 0.546 |
| `outerCandidateRefinement` | 0.1174 | 0.1211 | 0.044 |
| `innerCandidateGeneration` | 0.8190 | 0.8348 | 0.307 |
| `jointSelection` | 0.0000 | 0.0000 | 0.000 |
| `rectification` | 0.0001 | 0.0001 | 0.000 |
| `resultConstruction` | 0.0000 | 0.0000 | 0.000 |

Named-stage attribution median/max: 1.000 / 1.000
Wall-time median/max: 2.6636 / 2.8773 seconds
