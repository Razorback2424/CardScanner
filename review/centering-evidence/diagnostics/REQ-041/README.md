# REQ-041 stage profiling

This diagnostic measures the existing analyzer without changing any detector
decision. The production analyzer emits the timings only in `DEBUG` through
the existing `CardCenteringAnalysisDiagnostic` sink; the release path has no
new timing work or API.

## Controlled generator A/B — 2026-09-21

The new `CardCenteringInvariantTests/testREQ041ControlledFrontBottomGeneratorAB`
ran the same ten raw HEIC fixtures in one DEBUG simulator session with the
observational front-bottom generator disabled and enabled. Named-stage
attribution remained a test-harness check; this run was used to isolate the
generator's cost, not to revise the latency contract.

| Arm | Analyses | Inner-generation median | Inner-generation max | Wall median | Wall max |
|---|---:|---:|---:|---:|---:|
| without front-bottom generator | 10 | 0.7869 s | 0.8243 s | 2.5304 s | 2.8168 s |
| with front-bottom generator | 10 | 1.0085 s | 1.2611 s | 2.7284 s | 3.2677 s |

The enabled arm adds `0.2216 s` to the inner-generation median and `0.1980 s`
to the wall median in this controlled DEBUG comparison. The call site is now
inside `#if DEBUG`, so Release does not pay this discarded observational cost.
The original `0.80/1.50 s` budget remains unmet; no budget or threshold was
changed. Raw A/B records were written to simulator temporary storage.

## Post-remediation checkpoint — 2026-09-20

The redirected profile test passed 1/1 over 20 analyses after the registered
back-template and front-bottom generator changes. Named-stage attribution was
`0.9991` median / `0.9995` max; independent wall time was `2.7409/3.2918 s`
median/max. Scalar fields measured `1.4068 s` median and inner candidate
generation `1.0140 s` median. The original `0.80/1.50 s` budget remains open.
The generated records are in simulator temporary storage; the checked-in
records below remain the 2026-09-12 baseline snapshot.

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
