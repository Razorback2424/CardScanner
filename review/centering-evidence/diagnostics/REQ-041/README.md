# REQ-041 stage profiling

This diagnostic measures the existing analyzer without changing any detector
decision. The production analyzer emits the timings only in `DEBUG` through
the existing `CardCenteringAnalysisDiagnostic` sink; the release path has no
new timing work or API.

## Completed run

The signed test
`CardCenteringInvariantTests/testREQ041ProfilesNamedStageTimingsAcrossAllFixtures`
ran on the required iPhone 17 Pro / iOS 26.5 simulator
(`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`) on 2026-09-12. It analyzed all ten
development HEIC fixtures twice, for 20 analyses, and independently measured
wall time around each public analyzer call.

The retained result bundle is
`revision-e-req041-profile-retry2-2026-09-12.xcresult` on the configured
external SSD. The tracked records are:

- [`stage-timings.json`](stage-timings.json), the 20 raw records;
- [`stage-timings.md`](stage-timings.md), median/max summaries.

Named stages accounted for a median and maximum of `0.999` of wall time. The
median wall time was `2.7548 s`; the maximum was `3.0003 s`.

| Stage | Median | Max | Median share |
|---|---:|---:|---:|
| scalar fields | 1.4909 s | 1.6716 s | 54.6% |
| inner candidate generation | 0.8349 s | 0.8561 s | 30.0% |
| decode/orientation/downscale | 0.2058 s | 0.3636 s | 7.6% |
| colour preparation | 0.1324 s | 0.1385 s | 4.5% |
| outer candidate/refinement | 0.1180 s | 0.1223 s | 4.1% |
| Vision requests | 0.0216 s | 0.0511 s | 0.8% |

Joint selection, rectification, and result construction were each below
`0.0001 s` at the reported precision. The measured cost centre is therefore
the scalar/profile candidate-generation work, not Vision and not image
resolution alone. The next optimization must preserve candidate-level
recall and the 1200-pixel safety cap; this result does not authorize reopening
the closed sampling experiment class or changing the latency budget.

## Discarded attempt

An earlier version tried 30 analyses in one XCTest method. It produced 23
valid timing lines, then the test process was killed while CoreSimulatorService
became unavailable. The result bundle reports `signal kill`, followed by a
test-bundle load error. It had no assertion failure and generated no complete
artifact, so it is retained only as a harness/watchdog observation and is not
counted as REQ-041 evidence. The final test uses two passes to remain below the
per-test watchdog while still providing repeated measurements.
