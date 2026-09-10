# Card Scanner 1.0 Go/No-Go Framework

## Purpose

The objective is not to prove Card Scanner is bug-free.

The objective is to decide, consistently and without moving the goalposts, whether Card Scanner 1.0 is safe and useful enough to put in the hands of real paying users.

The governing product invariant is:

> Uncertainty and dependency failure may reduce automation; they may not silently reduce correctness.

Release readiness answers five separate questions:

1. Does any known deterministic/systemic defect make a critical workflow predictably wrong?
2. Does the inherently probabilistic recognition system perform within a pre-registered acceptable error budget?
3. Can important failures be detected and diagnosed?
4. Are remaining non-gating defects worth delaying launch to fix?
5. Has the release candidate reached the point where new findings are triaged rather than allowed to redefine “ready”?

---

## 1. Release-critical user flows

A defect can block 1.0 only in relation to a defined release responsibility.

### A. Clean install → usable app

A new user can:

* install on a supported device;
* launch from a clean state;
* complete required initialization;
* handle camera permissions;
* reach the scanner/collection;
* receive appropriate behavior when permissions are denied;
* initialize required local/cloud/catalog state;
* reach monetization without becoming stranded.

### B. Scan → identify → resolve → save

A supported physical card can either:

* resolve correctly and be saved; or
* remain appropriately uncertain and be presented for review.

The system must not invent certainty simply to finish the flow.

### C. Save → terminate → reload/refetch

Persisted identity survives termination, relaunch, synchronization and refetch without losing or changing meaningful modeled discriminators, including as applicable:

* game;
* set;
* collector number;
* variant;
* print run;
* finish/treatment;
* language;
* grading identity;
* quantity.

### D. Price → valuation → portfolio

Pricing information:

* binds to the intended product;
* uses the correct currency;
* respects authoritative chronology;
* behaves correctly through invalidation;
* agrees across Collection and Portfolio;
* degrades to unavailable/stale/unpriced when sufficient evidence is absent.

### E. Import/export

Supported fields survive documented collection import/export workflows without silent corruption or identity loss.

### F. Purchase → entitlement → restore

Card Scanner 1.0 is defined as a monetized release.

Therefore purchase behavior is not conditional or optional for release readiness.

The user must be able to:

* purchase the offered product;
* receive the intended entitlement;
* cancel/fail without receiving an incorrect entitlement;
* retain correct entitlement state;
* restore a legitimate purchase.

If the monetization model itself changes before RC, that is a scope change and must occur before the freeze described in §9.

Binder-page scanning and physical binder/page/slot mapping are explicitly outside the 1.0 critical flows.

---

## 2. Deterministic hard gates

Hard gates apply to known reproducible implementation failures, not the unavoidable stochastic error rate of computer vision/OCR.

A deterministic defect exists when a reproducible input/state causes an incorrect result because the application’s logic, data transformation, persistence, matching or integration rule itself is wrong.

Examples:

* choosing 1st Edition reliably loses that field on save;
* EUR is treated numerically as USD;
* a grouping key deterministically collapses two distinct product identities;
* chronological price observations are compared using the wrong clock.

### Automatic NO-GO conditions

#### G1 — Deterministic identity corruption

A known reproducible code/data path causes a supported identity to be persisted, transformed, matched or refetched incorrectly.

#### G2 — Deterministic valuation corruption

A known reproducible path causes:

* the wrong product’s price to be used;
* incorrect currency arithmetic;
* incorrect price chronology;
* inconsistent authoritative valuation state.

#### G3 — Deterministic collection-data loss

Supported collection information predictably disappears, collapses, duplicates or mutates without an intentional user action.

#### G4 — Deterministic purchase/entitlement failure

A normal supported purchase/restore path reproducibly grants, loses or restores the wrong entitlement.

#### G5 — Material security/privacy/compliance defect

A known defect creates material security/privacy exposure or prevents required release compliance.

#### G6 — Deterministic critical-flow availability failure

A realistically encountered supported critical flow contains a reproducible crash, deadlock, infinite load or unrecoverable state preventing completion.

There is deliberately no marketing/promise gate here. Marketing truthfulness is handled separately after empirical performance is known.

---

## 3. Gates require an affirmative search

The hard gates apply only to known defects, so each gate must have defined attempts to discover violations.

A gate cannot be marked clear merely because nobody happens to have noticed a problem.

| Gate | Minimum verification before GO |
| --- | --- |
| G1 Identity | Identity invariant suite; save/refetch tests; graded/raw matching tests; variant/print-run tests; adversarial identification testing |
| G2 Valuation | Fast-path/recompute equivalence; currency transitions; invalidation; delayed/out-of-order observation tests; vendor-product binding tests |
| G3 Collection data | Persistence round trips; clean relaunch; import/export round trips; quantity/update/delete tests; synchronization paths where applicable |
| G4 Purchase | StoreKit/TestFlight purchase matrix; cancellation; failure; entitlement persistence; restore |
| G5 Privacy/security | Privacy/data-flow review plus App Store privacy/compliance checklist |
| G6 Availability | Clean-install testing; full regression suite; critical-flow manual tests; TestFlight crash feedback; supported-device/OS smoke matrix |

Passing these searches does not prove that unknown defects do not exist.

It establishes that the release has made a defined, reproducible effort to find the defect classes that would block launch.

Any confirmed gate violation must have a regression test reproducing the failure before the fix where technically practical.

Broader invariants need not artificially fail against the pre-fix build if the current code already satisfies them.

---

## 4. Statistical recognition acceptance rule

Recognition errors are governed by an empirical error budget, not G1/G2, unless root-cause analysis reveals that the observed error was produced by deterministic logic.

The acceptance rule must be frozen before the release corpus is run.

### 4.1 Measurement pilot

Before freezing the release corpus, a small 30–50 card pilot may be used solely to:

* verify instrumentation;
* confirm outcome definitions;
* estimate test duration;
* identify ambiguous ground-truth procedures;
* make sure the test methodology works.

Pilot cards are excluded from the final acceptance corpus.

Pilot results may not be used as evidence that the release passed.

### 4.2 Normal release corpus

Use 500 distinct physical cards representative of the actual 1.0 supported population.

The distribution across games, eras, languages, finishes and card types is defined and frozen before testing.

Ground truth is established before Card Scanner sees the cards.

Each card receives one primary scan trial under the predetermined normal-use procedure.

#### Primary trust acceptance rule

Card Scanner passes the normal-corpus trust gate if it produces no more than 1 confidently-wrong exact identity in 500 scans.

Every confidently-wrong result must be root-caused.

If any such result is attributable to a deterministic implementation defect, the statistical allowance does not protect it:

it becomes a G1/G2 defect and blocks release until fixed.

If the result is genuinely stochastic recognition error, it remains part of the statistical count.

This threshold has an interpretable statistical meaning:

* 0 / 500 errors: one-sided 95% upper bound on the underlying error probability is approximately 0.60%.
* 1 / 500 errors: one-sided 95% upper bound is approximately 0.95%.

Therefore this corpus can support a defensible conclusion roughly equivalent to:

> “Observed performance is consistent with a confidently-wrong rate below approximately 1% under the tested normal conditions.”

It cannot establish a 0.25% true rate.

To support a roughly 0.25% upper bound after observing zero failures would require approximately 1,200 independent clean trials.

Card Scanner 1.0 does not need to purchase that level of statistical precision before launch.

### 4.3 Secondary usability floors

The normal corpus also measures:

* exact autonomous resolution;
* correct intervention;
* wrong-but-intercepted;
* no result;
* time to usable result.

Before the 500-card acceptance run, the release manager must freeze minimum acceptable values for these metrics.

Recommended initial floors are:

| Metric | Proposed 1.0 threshold |
| --- | --- |
| Confidently wrong | ≤1 / 500 |
| Safe outcome: correct automatic OR appropriately intercepted/reviewed | ≥99% |
| Exact autonomous resolution on normal supported cards | ≥95% |
| Complete no-result rate | ≤3% |

Throughput should be measured and recorded, but I would not make a competitor-relative speed target a hard launch criterion for 1.0 unless the experience is demonstrably too slow to perform the critical job.

A 30–50 card measurement pilot may justify changing the proposed usability floors before they are frozen, but not after the 500-card results are known.

---

## 5. Adversarial corpus

The adversarial corpus is a defect-discovery tool, not a statistically representative estimate of normal-user error.

Include approximately 150–250 deliberately difficult cards, such as:

* same-art reprints;
* similar collector numbers;
* 1st Edition / Unlimited;
* Shadowless;
* reverse/holo distinctions;
* Poké Ball / Master Ball;
* MTG reprints/treatments;
* Japanese/English ambiguity;
* promos;
* reflective sleeves/toploaders;
* glare;
* partially obscured identifiers;
* unusual layouts.

Every confidently-wrong result is root-caused.

### Adversarial decision rule

A single adversarial error does not automatically block launch merely because the corpus was constructed to produce difficult cases.

However:

Any deterministic cause → relevant hard gate.

And:

If the same stochastic failure mechanism produces confidently-wrong results on two or more distinct cards, that failure family must be explicitly reviewed before release.

The review must result in one of:

* mitigation;
* intentional intervention/abstention behavior;
* narrowing of supported scope;
* documented acceptance based on low normal-corpus exposure.

The adversarial set exists primarily to discover systematic weaknesses that an ordinary random sample may miss.

---

## 6. Competitor benchmarking is intelligence, not a launch gate

A competitor’s performance cannot determine whether Card Scanner itself is safe to release.

Therefore competitor benchmarking is not part of the GO/NO-GO arithmetic.

Use a time-boxed subset rather than reproducing the entire 500-card release test across every competitor.

Recommended:

* 75–100 representative normal cards;
* 75–100 high-value adversarial cards;
* serious competitors only.

Measure the same outcome categories.

This answers:

* whether the trust differentiator appears real;
* where Card Scanner wins/loses;
* which error classes remain market-wide;
* what claims may eventually be defensible.

If a competitor beats Card Scanner, that is strategically important.

It does not automatically turn into a release blocker unless the comparison reveals that Card Scanner itself fails one of its frozen release requirements.

---

## 7. Binary engineering invariants

Statistical recognition metrics and deterministic engineering tests are reported separately.

The deterministic suite must pass completely within its defined scope.

Required invariants include:

### Valuation

* Incremental price application converges to authoritative recomputation.
* Collection and Portfolio agree for identical holdings/observation state.
* USD→EUR, EUR→USD, invalidation and ordinary replacement behave correctly.
* Asynchronous arrival order does not alter the final state when source chronology is identical.

### Identity

* Persisted exact identity survives save/refetch without losing modeled discriminators.
* Distinct economic identities cannot accidentally share a pricing lookup due to a lossy intermediate projection.
* External vendor products are identity-validated before becoming authoritative.
* Uncertainty cannot silently harden into certainty by traversing another application layer.
* Print run survives the normal graded picker→confirmation→save path.

### Persistence/replay

Absent new user or external information:

persist → reload → recompute → persist

must not silently alter identity or valuation state.

### Import/export

Every field claimed as round-trippable survives the supported export→import cycle.

### Purchase

Every supported product, purchase, failure/cancellation and restore scenario in the defined 1.0 matrix produces the intended entitlement state.

These are “all specified tests pass” requirements.

They are not claims of 100% statistical product reliability.

---

## 8. Observability and diagnosis

Diagnosability is a prerequisite for risk acceptance.

Before an issue can be classified as mitigated or safely shippable, the project must answer:

> If this happens to a beta or launch user, how will I know enough to understand what happened?

The solution does not have to be centralized surveillance.

Card Scanner’s privacy/local-first positioning should constrain telemetry design.

### Minimum diagnostic capability before RC

For critical workflows, enough information must be available—through TestFlight diagnostics, crash reporting, local diagnostic logs, user-exportable support bundles or privacy-compatible telemetry—to reconstruct relevant state such as:

* app/build version;
* device/OS where relevant;
* failed critical-flow stage;
* scan outcome classification;
* identity/variant resolution provenance;
* unresolved versus user-confirmed state;
* pricing source/status;
* invalidation/staleness state where relevant;
* purchase/entitlement state transitions;
* import/export failure stage.

Raw card images or personally identifying collection information should not be captured merely for convenience unless separately justified and appropriately consented.

For beta specifically, a tester should be able to report/export enough diagnostic context that a serious identity or valuation failure is investigable.

If the answer to:

> “How would we diagnose this if a tester reported it tomorrow?”

is “we probably couldn’t,” then diagnosability receives no credit in defect triage.

---

## 9. Containment profile and whether R2 exists

The project must explicitly inventory the mitigation mechanisms that actually exist.

Do not assume web/SaaS-style instant rollback.

Before RC, record for each significant subsystem whether the following are available:

| Mechanism | Actually available? |
| --- | --- |
| Feature can be disabled remotely without binary review | Yes / No |
| Problematic pricing/catalog provider can be disabled or isolated remotely | Yes / No |
| Server-side bad data can be corrected without an app release | Yes / No |
| User has a safe documented workaround | Yes / No |
| Affected records can be identified and repaired | Yes / No |
| Failure can be diagnosed from available diagnostics | Yes / No |
| Shipping binary can be replaced only through another App Store review | Yes / No |

Only mechanisms that actually exist count.

Do not assume that phased-release functionality, remote configuration, kill switches or rollback are available unless they are actually implemented and applicable to the 1.0 release.

### Consequence for residual-risk classification

If a defect requires mitigation for safe release but:

* no remote containment exists;
* no safe user workaround exists;
* and correcting it requires a new binary;

then it cannot be called R2 merely because “we’ll monitor it.”

It must resolve to either:

#### R1 — fix before launch

or:

#### R3 — consciously accept it as sufficiently low impact/exposure to ship without mitigation.

R2 exists only when an actual mitigation exists.

---

## 10. Residual-defect triage

For anything that does not trip a hard gate, do not calculate an artificial 0–100 score.

Answer three things.

### Impact

What happens to the user if it occurs?

### Exposure

How likely is a realistic 1.0 user to encounter it?

### Fix economics

Compare the benefit of fixing now against:

* engineering effort;
* validation effort;
* regression risk created by touching the code;
* proximity to RC;
* expected launch-user exposure;
* recoverability;
* diagnostic capability;
* actual containment available;
* cost of delaying real-user evidence.

Then assign one category:

#### R1 — Fix before launch

Expected benefit of fixing clearly exceeds delay/regression cost.

#### R2 — Ship with actual mitigation

There is a concrete mitigation identified in §9 and the residual risk is acceptable with it.

#### R3 — Accept and backlog

The problem does not justify delaying release even without special mitigation.

The decision and rationale should be recorded so the same defect is not repeatedly re-litigated.

---

## 11. Explicitly account for the cost of not shipping

A release decision compares:

> risk of shipping

against

> risk and opportunity cost of continued delay.

For any proposed launch delay that does not result from a hard gate or failed frozen acceptance criterion, explicitly ask:

* How many initial users are realistically exposed?
* What is the plausible harm?
* Can the user recover?
* Can the failure be diagnosed?
* What actual containment exists?
* How expensive is the fix?
* What regression risk does fixing it introduce?
* What real-user information is being postponed?
* Is the delay addressing demonstrated user harm or anxiety about imperfection?

The initial install base is likely to be small, which bounds the blast radius of many ordinary defects.

That asymmetry should be recognized.

It does not override deterministic identity, valuation, data, security or entitlement gates.

---

## 12. Marketing claims follow measurement

Marketing truthfulness does not belong inside the deterministic code-defect gates.

After the recognition benchmark and beta evidence are available:

1. document what has actually been measured;
2. identify what can legitimately be claimed;
3. write App Store/onboarding language within those bounds.

For example:

If the evidence demonstrates low confidently-wrong behavior but no statistically sound superiority over competitors, appropriate messaging might emphasize:

> “Designed to surface uncertainty rather than guessing.”

It should not say:

> “The most accurate TCG scanner.”

unless comparative evidence actually supports that statement.

If a claimed feature turns out not to meet its description, the default remedy is to correct the claim rather than delay the binary—unless the feature is itself part of the frozen critical-flow scope.

---

## 13. Release-candidate freeze

This is the anti-goalpost-moving mechanism.

### Before RC

The project may still change:

* promised 1.0 scope;
* critical flows;
* hard gates;
* corpus construction;
* statistical acceptance rules;
* monetization design;
* diagnostic/containment mechanisms.

Changes must have an explicit reason.

### At RC

Freeze:

* v1 scope;
* monetization model;
* critical flows;
* G1–G6;
* verification matrix;
* normal corpus;
* adversarial methodology;
* statistical acceptance criteria;
* diagnostic requirements;
* containment profile;
* release claims.

After that point, a new finding can reopen GO/NO-GO only if it:

1. trips G1–G6;
2. causes an already-frozen deterministic invariant to fail;
3. causes the statistical acceptance criterion to fail;
4. invalidates the clean-install or purchase test matrix;
5. reveals a material security/privacy/compliance issue not covered by the prior review.

Otherwise it goes through R1/R2/R3 triage.

The operative post-RC question becomes:

> “Which frozen release criterion does this violate?”

If there is no answer, the finding does not automatically stop launch.

---

## 14. Current known defects

### Source chronology defect

Deterministic pricing logic failure.

G2 → NO-GO.

### EUR treated as USD

Deterministic valuation arithmetic failure.

G2 → NO-GO.

### Graded card can bind another set’s product

Deterministic identity/product association failure with valuation consequences.

G1 + G2 → NO-GO.

### Selected print run discarded during save

Deterministic persistent identity loss.

G1 + G3 → NO-GO.

### Binder-page scanning absent

No gate violated.

Outside 1.0 critical scope.

Post-launch candidate.

### Physical-location mapping absent

No gate violated.

Outside 1.0 critical scope.

Post-launch candidate.

---

## 15. Execution sequence

1. Fix existing G1/G2/G3 violations.
2. Establish the deterministic trust-invariant suite.
3. Implement/verify minimum diagnostic capability.
4. Inventory actual containment mechanisms.
5. Run the small measurement-methodology pilot.
6. Freeze the 500-card normal corpus and statistical acceptance rules.
7. Run the normal and adversarial Card Scanner tests.
8. Root-cause every confidently-wrong result.
9. Run the time-boxed competitor comparison for strategic intelligence.
10. Conduct structured external TestFlight testing.
11. Fix any newly discovered hard-gate violations.
12. Triage everything else R1/R2/R3 using fix economics.
13. Finalize monetization, App Store claims and launch materials using measured evidence.
14. Declare the release candidate.
15. Freeze the release framework.
16. Run the full clean-install, deterministic, persistence, purchase and critical-flow suite against that exact RC.
17. GO or NO-GO strictly against the frozen criteria.
18. Launch if GO.

---

## Final release rule

Card Scanner 1.0 ships when all of the following are true:

1. No known G1–G6 violation remains after the defined verification work has been performed.

2. All frozen deterministic identity, valuation, persistence, import/export and purchase invariants pass on the release candidate.

3. On the frozen 500-card normal corpus, Card Scanner produces no more than one confidently-wrong exact identity; every such result has been root-caused; none is attributable to unresolved deterministic logic.

4. The remaining statistical usability floors are met.

5. Adversarial testing has revealed no unresolved deterministic/systemic failure family.

6. External beta has revealed no unresolved systemic trust failure.

7. Minimum diagnostic capability exists for the critical workflows.

8. Any issue classified R2 has an actual, documented mitigation.

9. Remaining issues have been explicitly accepted as R3 or resolved as R1.

10. App Store claims accurately reflect what was measured.

11. The frozen RC passes clean-install and monetization testing.

At that point, additional improvement is no longer evidence that 1.0 is unready.

It is evidence that there should eventually be a 1.1.

The standard is:

> No known deterministic corruption; demonstrably low stochastic silent error; safe uncertainty; adequate diagnosis; bounded residual risk; and no moving the launch threshold after seeing the result.
