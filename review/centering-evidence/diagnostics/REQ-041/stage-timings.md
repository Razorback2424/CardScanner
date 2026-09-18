# REQ-041 named stage timing profile

Signed DEBUG analyses on the iOS 26.5 iPhone 17 Pro simulator. Each fixture was analyzed twice.
The attribution fraction is the sum of the named stage timers divided by the independently measured wall time.

| Stage | Median seconds | Max seconds | Median share of wall time |
|---|---:|---:|---:|
| `decodeOrientationDownscale` | 0.1883 | 0.1958 | 0.071 |
| `colorPreparation` | 0.1220 | 0.1286 | 0.044 |
| `visionRequests` | 0.0204 | 0.0223 | 0.008 |
| `scalarFields` | 1.4116 | 1.5731 | 0.544 |
| `outerCandidateRefinement` | 0.1148 | 0.1184 | 0.044 |
| `innerCandidateGeneration` | 0.8033 | 0.8227 | 0.308 |
| `jointSelection` | 0.0000 | 0.0000 | 0.000 |
| `rectification` | 0.0001 | 0.0001 | 0.000 |
| `resultConstruction` | 0.0000 | 0.0000 | 0.000 |

Named-stage attribution median/max: 0.999 / 1.000
Wall-time median/max: 2.6045 / 2.8260 seconds
