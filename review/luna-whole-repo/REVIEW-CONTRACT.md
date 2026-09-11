Luna Max Pursue Goal — Exhaustive Whole-Repository Review Contract

0. Authority and Purpose of This Document

This document is the authoritative specification for the active Pursue Goal.

Read this entire file before beginning work.

Treat every requirement, prohibition, required artifact, review phase, evidence rule, and completion criterion in this document as binding.

Do not modify this contract.

Do not weaken, reinterpret, delete, replace, or silently omit requirements in order to make the goal easier to complete.

If repository reality makes part of this contract ambiguous or impossible, preserve the original intent of the review, document the conflict explicitly, and continue all work that remains possible. Do not invent a convenient interpretation merely to reach completion.

After significant context compaction or loss of working context, reorient yourself by rereading:

1. this contract;
2. the durable review artifacts created under this contract;
3. applicable repository instructions such as AGENTS.md;
4. and the actual source code necessary to verify the current state.

Immediately before deciding that the goal is complete, reread this entire contract again.

The current worktree and directly observed command, test, build, and source evidence are authoritative. Conversation memory, previous summaries, earlier assumptions, and your own prior conclusions are not proof.

⸻

1. Mission

Perform an exhaustive, evidence-driven review of the entire relevant production repository and create a durable body of repository understanding and review evidence for a subsequent independent Opus review.

Your role is to be the:

* exhaustive investigator;
* repository cartographer;
* dependency and call-path tracer;
* architecture mapper;
* evidence collector;
* hypothesis tester;
* contradiction finder;
* adversarial first-pass reviewer;
* and coverage auditor.

Your job is to maximize the quality, breadth, traceability, and usefulness of the evidence available to the subsequent Opus reviewer.

The subsequent Opus model will independently verify your conclusions, identify anything you missed or misunderstood, make final architectural judgments, and write the actual implementation plan.

You ARE responsible for

* understanding the repository as a system;
* systematically inspecting the relevant production code;
* understanding major architecture and subsystem boundaries;
* tracing important behavior across files and subsystems;
* identifying and validating defects, risks, inconsistencies, and meaningful improvement opportunities;
* distinguishing evidence from speculation;
* attempting to disprove suspected problems;
* documenting meaningful rejected hypotheses;
* identifying cross-cutting architectural issues;
* identifying unresolved questions and environment/device limitations;
* and leaving behind durable evidence that another model can efficiently verify.

You are NOT responsible for

* implementing fixes;
* refactoring production code;
* changing architecture;
* rewriting tests to make behavior pass;
* creating the final implementation plan;
* deciding the final target architecture;
* sequencing remediation work;
* estimating implementation effort;
* committing or pushing changes;
* or declaring that a particular fix should be implemented merely because it appears obvious.

A short explanation of a likely root cause or the conceptual nature of a correction is acceptable when necessary to explain a finding.

Do not turn findings into an implementation roadmap.

⸻

2. Fundamental Review Standard

The goal is NOT:

Find a lot of issues.

The goal is:

Develop and document the most complete, accurate, evidence-supported understanding reasonably obtainable of this repository, its important behaviors, its cross-system interactions, and its material problems within the available environment.

Finding many problems is not proof that the review is comprehensive.

Passing tests are not proof that the review is comprehensive.

Successfully building the application is not proof that the review is comprehensive.

Inspecting every file superficially is not proof that the review is comprehensive.

Failing to notice additional issues is not proof that none remain.

Completion must be demonstrated through coverage, evidence, reconciliation, and the binding Definition of Done at the end of this document.

⸻

3. Safety and Repository Preservation

This is a review task, not an implementation task.

Before substantive review:

1. inspect the current Git/worktree state;
2. record relevant pre-existing modifications;
3. identify the current repository structure and applicable repository instructions;
4. establish which files belong to production code, tests, generated code, third-party/vendor code, tooling, documentation, and build configuration.

Do not erase, reset, revert, overwrite, clean, or otherwise disturb pre-existing user work.

Do not:

* modify production source code;
* modify existing tests;
* alter dependencies;
* alter dependency lockfiles;
* change project configuration;
* change signing configuration;
* change schemes;
* change entitlements;
* commit;
* push;
* create or switch branches;
* rewrite Git history;
* deploy;
* publish;
* or access destructive external operations.

Build products, DerivedData, caches, and equivalent disposable tool output are acceptable when naturally produced by safe inspection/build/test commands.

The only intentional tracked-file writes permitted by this contract are the review artifacts defined below, unless an applicable higher-priority instruction says otherwise.

⸻

4. Durable Review Workspace

Create a dedicated review workspace at:

review/luna-whole-repo/

If that exact path conflicts with an established repository convention, use the closest existing review/documentation convention and record the chosen location in the control file.

Create and maintain these artifacts:

00-review-control.md

Owns:

* review scope;
* baseline repository state;
* phase progress;
* coverage counts;
* major unresolved review gaps;
* timestamps or checkpoints useful for recovery;
* final Definition-of-Done reconciliation.

This is the control surface for the Pursue Goal.

Do not use it as a narrative transcript.

01-repository-map.md

Owns:

* repository structure;
* production targets;
* important modules/subsystems;
* architectural responsibilities;
* important dependencies between them;
* major entry points;
* ownership boundaries;
* external dependencies relevant to behavior.

02-coverage-ledger.md

Owns:

* the complete in-scope production-file inventory;
* review classification of every in-scope file;
* subsystem assignment;
* reason for exclusion where applicable;
* follow-up status where applicable.

03-flows-and-invariants.md

Owns:

* important end-to-end flows;
* important state/data/resource flows;
* cross-cutting invariants;
* ownership assumptions;
* lifecycle assumptions;
* subsystem contracts;
* conflicts between those assumptions.

04-findings.md

Owns:

* validated review findings;
* their evidence;
* confidence;
* impact;
* causal explanation;
* counterevidence;
* verification path.

This is the canonical finding ledger.

05-rejected-hypotheses-and-uncertainties.md

Owns:

* meaningful suspected issues that were disproved;
* unresolved hypotheses;
* weak or conflicting evidence;
* questions that require stronger evidence before becoming findings.

06-device-and-environment-validation.md

Owns:

* issues or behaviors that cannot be reliably established in the current environment;
* exact additional validation required;
* physical-device-only questions;
* environment-specific limitations.

07-opus-handoff.md

Owns:

* the final concise synthesis for the independent Opus reviewer;
* the repository model;
* review coverage;
* most important findings;
* most important uncertainties;
* cross-cutting themes;
* and areas Opus should independently challenge.

Do not duplicate entire sections between artifacts.

Each artifact has a defined ownership boundary. Link between canonical artifacts rather than copying large amounts of material.

These files are durable working memory. Update them as material discoveries occur instead of attempting to reconstruct the review from conversational memory at the end.

⸻

5. Phase 1 — Establish the Review Universe

Before hunting for defects, establish what actually exists.

Inventory the repository and determine:

* production application targets;
* supporting packages/modules;
* test targets;
* extensions;
* shared frameworks;
* build configuration;
* important assets/configuration affecting behavior;
* generated code;
* third-party/vendor code;
* scripts/tooling;
* documentation;
* and anything else materially relevant to the shipped application.

Determine the boundaries of the production system rather than assuming that directory structure perfectly represents architecture.

The default scope is all code and configuration capable of materially affecting the behavior, correctness, reliability, performance, data integrity, or lifecycle of the shipped application.

Tests are supporting evidence and must be inspected when relevant, but they do not require the same file-by-file production coverage classification unless they themselves contain architecture or infrastructure material to the conclusions.

Generated and third-party code may normally be excluded from deep review unless:

* application behavior depends on an unusual integration with it;
* the code has been locally modified;
* or direct inspection becomes necessary to validate a finding.

Record exclusions. Do not silently ignore them.

⸻

6. Phase 2 — Build an Accurate Repository and Architecture Map

Before drawing broad conclusions, understand how the application is actually put together.

Identify and document every materially important subsystem, including where applicable:

* application/bootstrap lifecycle;
* SwiftUI view hierarchy and navigation;
* state ownership and observation;
* view models/controllers/coordinators;
* domain models;
* repositories/stores;
* persistence;
* networking/API clients;
* caching;
* image loading and processing;
* camera ownership and AVFoundation lifecycle;
* Vision/OCR/recognition;
* card identification and matching;
* confidence/ambiguity handling;
* duplicate protection;
* collection management;
* search/filter/sort;
* pricing;
* undo or transactional behavior;
* background tasks;
* concurrency boundaries;
* shared services;
* analytics/logging;
* configuration;
* feature flags;
* external SDKs/services;
* and important platform abstractions.

For each important subsystem, determine from source evidence:

* its responsibility;
* its important files and symbols;
* its entry points;
* what owns it;
* what it owns;
* what state it reads;
* what state it writes;
* its sources of truth;
* its dependencies;
* its consumers;
* important asynchronous work;
* persistence behavior;
* lifecycle assumptions;
* cleanup/invalidation behavior;
* and its relationships with neighboring subsystems.

Do not infer architecture solely from names, folders, comments, or apparent intent.

Trace enough code to establish how the application actually behaves.

⸻

7. Phase 3 — Establish Demonstrable File Coverage

Create a concrete inventory of all relevant production source files.

Every relevant production file must ultimately receive exactly one primary coverage classification:

REVIEWED-DEEP

The file’s behavior, important symbols, interactions, assumptions, and risks were substantively inspected.

Use this for architecturally important or behaviorally consequential files.

REVIEWED-CONTEXT

The file was directly inspected and understood sufficiently to establish that deeper review was unnecessary given its limited role.

This must still represent actual inspection, not merely seeing the filename.

EXCLUDED-GENERATED

Generated source not appropriate for direct review.

EXCLUDED-THIRD-PARTY

External/vendor source not owned by the application and not requiring deeper investigation.

EXCLUDED-NONPRODUCTION

Test fixtures, previews, samples, scripts, or other files correctly outside production-code coverage.

EXCLUDED-IRRELEVANT

A production-adjacent file that demonstrably cannot materially affect the review objectives.

Include a reason.

DEVICE-DEPENDENT

Source whose material behavior was inspected but whose important conclusions require physical-device evidence.

NEEDS-FOLLOWUP

The file cannot yet be honestly classified as sufficiently reviewed.

The Goal may not complete while any avoidable NEEDS-FOLLOWUP classifications remain.

For each production file, record:

* path;
* subsystem;
* classification;
* short review note;
* related finding IDs if any.

Coverage is a gate, not a vanity metric.

Do not inflate coverage by classifying a file as reviewed merely because it appeared in a search result or was opened briefly.

⸻

8. Phase 4 — Deep Subsystem Review

Review every materially important subsystem on its own terms.

Evaluate applicable concerns including, but not limited to:

Correctness and state

* incorrect logic;
* invalid assumptions;
* incomplete state transitions;
* stale state;
* duplicated state;
* conflicting sources of truth;
* invalid optional/error-state modeling;
* incorrect derived state;
* incorrect equality/identity assumptions;
* edge cases;
* race-sensitive behavior;
* ordering dependencies;
* failure recovery.

Architecture and responsibility

* hidden coupling;
* inappropriate responsibility sharing;
* duplicated responsibility;
* architectural drift;
* abstractions whose actual responsibility differs from their apparent contract;
* bypassed abstractions;
* circular relationships;
* multiple competing ownership models;
* code paths that violate intended subsystem boundaries.

Swift concurrency

* actor-isolation assumptions;
* MainActor correctness;
* task ownership;
* structured versus unstructured tasks;
* cancellation;
* task lifetime;
* Sendable assumptions where relevant;
* races;
* reentrancy;
* work occurring on inappropriate executors;
* asynchronous operations that can outlive their owners;
* ordering assumptions that async behavior does not guarantee.

Do not infer concurrency safety merely because code compiles.

Lifecycle and resource ownership

* object lifetime;
* view lifecycle;
* camera/session lifetime;
* tab/navigation transitions;
* foreground/background transitions;
* initialization;
* teardown;
* cancellation;
* observers;
* notifications;
* subscriptions;
* timers;
* resources that may survive too long;
* resources that may be destroyed too early;
* repeated setup/teardown.

Performance

Look for evidence of material performance risk, including:

* unnecessary main-thread work;
* repeated expensive computation;
* repeated decoding/parsing;
* inefficient collection operations on hot paths;
* excess allocations;
* expensive image processing;
* unnecessary camera/session recreation;
* redundant networking;
* cache misses caused by bad identity/invalidation;
* SwiftUI body/recomputation problems;
* observation triggering excessive updates;
* inappropriate eager work;
* unnecessary serialization;
* avoidable disk I/O;
* avoidable work per camera frame;
* hot-path logging;
* unnecessary data copying.

Do not turn theoretical micro-optimizations into findings without evidence that the path is material.

Persistence and data integrity

* canonical data ownership;
* schema/encoding assumptions;
* writes and read-after-write behavior;
* transactional behavior;
* migration concerns;
* stale persistence;
* duplicate records;
* undo consistency;
* crash/interruption behavior;
* reconciliation between in-memory and persisted state.

Networking and cache behavior

* request ownership;
* retry behavior;
* cancellation;
* stale/fresh semantics;
* cache invalidation;
* cache keys;
* fallback behavior;
* error mapping;
* partial results;
* offline/degraded behavior;
* duplicate requests;
* conflicting sources of remote/local truth.

SwiftUI and UI-state correctness

Review code-level UI behavior such as:

* navigation state;
* identity;
* observation boundaries;
* duplicated UI/domain state;
* lifecycle effects;
* sheet/navigation ownership;
* unnecessary rerenders;
* task modifiers;
* state restoration;
* user-action races;
* stale displayed state.

Do not turn this review into a subjective visual-design audit unless visual implementation exposes a code-level correctness or consistency issue.

Error handling and resilience

* swallowed errors;
* impossible-state assumptions;
* silent failure;
* incorrect fallback;
* retry loops;
* failure-state recovery;
* user-visible inconsistencies;
* partial completion;
* cleanup after failure.

Memory/resource behavior

* retain cycles;
* strong ownership where weak ownership is required;
* caches without appropriate bounds;
* large object/image retention;
* session/resource leakage;
* observer/subscription lifetime;
* closures retaining long-lived owners.

Security and privacy where applicable

* accidental secrets;
* sensitive logging;
* incorrect permission assumptions;
* insecure storage;
* data exposure;
* privacy-sensitive camera/photo behavior;
* trust of unvalidated external data.

Maintainability with real consequence

Report maintainability issues only when they create meaningful risk, such as:

* duplicated business logic likely to diverge;
* highly coupled behavior that makes correctness difficult to preserve;
* unreachable/dead paths that obscure current behavior;
* inconsistent semantics across equivalent operations;
* abstractions that actively mislead future changes;
* testability problems around important behavior.

Do not fill the report with formatting preferences or cosmetic style commentary.

⸻

9. Phase 5 — Trace Important End-to-End Flows

File-by-file inspection is insufficient.

Identify the application’s important user and system flows and trace them across subsystem boundaries.

For this application, explicitly investigate where present:

* cold launch;
* warm launch/resume;
* navigation into scanning;
* scanner/camera session startup;
* frame acquisition;
* recognition;
* printed-identifier extraction;
* card candidate resolution;
* confidence/ambiguity handling;
* successful identification;
* failed/uncertain identification;
* duplicate protection;
* adding a card to the collection;
* undo;
* Price Check behavior;
* collection loading;
* search;
* filtering;
* sorting;
* image retrieval/caching;
* pricing retrieval/caching;
* tab switching away from and back to the scanner;
* foreground/background transitions;
* network failure;
* cancellation;
* persistence failure;
* and any other flow clearly central to the current repository.

For each material flow, establish:

* entry condition;
* initiating action/event;
* important call path;
* state ownership;
* state transitions;
* asynchronous boundaries;
* data transformation;
* persistence effects;
* caching effects;
* failure paths;
* cancellation;
* cleanup;
* final user-visible/system state.

Look especially for failures that are invisible within individual files but emerge only when the complete flow is considered.

⸻

10. Phase 6 — Establish and Test Cross-Cutting Invariants

As repository understanding develops, identify assumptions that must remain true across multiple systems.

Document them in 03-flows-and-invariants.md.

Examples include:

* which object is authoritative for scanner state;
* who owns the camera session;
* when that session should exist;
* what constitutes a unique card identity;
* where a tentative recognition becomes authoritative;
* how duplicate detection relates to collection insertion;
* what state survives navigation or tab transitions;
* which collection representation is authoritative;
* when persisted data becomes visible in UI state;
* whether caches are advisory or authoritative;
* what invalidates each cache;
* what must execute on the main actor;
* which async work must be cancelled when ownership ends;
* which subsystem owns network freshness;
* what guarantees undo depends upon.

Then actively test the repository against those invariants.

Search for callers or subsystems that violate them.

Look for places where two individually reasonable components make incompatible assumptions.

Cross-cutting contradictions are among the highest-value findings in this review.

⸻

11. Phase 7 — Finding Validity Gate

Do not promote a suspicion into 04-findings.md merely because it sounds plausible.

Before confirming a finding, establish enough evidence to answer:

1. Is the relevant code reachable or behaviorally relevant?
2. What exact condition produces the problem or risk?
3. What is the causal chain from implementation to consequence?
4. Is another layer already preventing or compensating for it?
5. Do callers use this code the way the concern assumes?
6. Do tests or other safeguards contradict the hypothesis?
7. Does current repository state still contain the problem?
8. Is the claimed impact proportional to the evidence?
9. Is this one finding or a symptom of a broader root cause?

Actively seek counterevidence.

A hypothesis that survives adversarial verification is stronger than one produced by first-pass pattern matching.

If evidence remains incomplete, place it in the uncertainty ledger instead of presenting it as fact.

⸻

12. Finding Schema

Every canonical finding must have a stable ID such as F-001.

For each finding record:

ID and title

Concise, stable identification.

Classification

Use one:

* Confirmed defect
* Strongly supported risk
* Architectural concern
* Performance concern
* Data-integrity concern
* Lifecycle/concurrency concern
* Security/privacy concern
* Maintainability concern
* Test/verification gap
* Device-dependent concern

Severity

Use:

* Critical
* High
* Medium
* Low

Calibrate conservatively.

Critical should be reserved for evidence-supported failures with unusually severe consequences such as broad data loss, severe security/privacy exposure, effectively unusable core functionality, or similarly exceptional impact.

Do not escalate severity to make the review appear important.

Confidence

Use:

* High
* Medium
* Low

A Low-confidence concern normally belongs in the uncertainty ledger unless there is a compelling reason to retain it as a formal finding.

Affected scope

Identify affected subsystem(s), flow(s), and behavior.

Evidence

Identify exact repository-relative files and relevant symbols.

Use line references when stable/useful, but prefer symbols and causal explanation over brittle line numbers alone.

Causal chain

Explain how the code produces or permits the claimed outcome.

Impact

Explain what actually matters to the application or user.

Do not substitute generic statements such as “could cause issues.”

Conditions

Describe when the issue can occur.

Counterevidence investigated

Describe meaningful evidence you examined that could have disproved or narrowed the finding.

Existing test coverage

State whether relevant tests exist and what they actually establish.

Do not treat a green suite as evidence beyond its demonstrated scope.

Verification path

Explain how Opus can independently confirm or reject the finding efficiently.

Related findings

Link findings that may share a root cause without prematurely collapsing distinct behaviors.

Do NOT prescribe the final implementation.

⸻

13. Phase 8 — Rejected Hypotheses and Uncertainty

Maintain 05-rejected-hypotheses-and-uncertainties.md throughout the review.

Rejected hypotheses

Record meaningful concerns that looked credible but were disproved.

For each, include:

* hypothesis;
* why it appeared plausible;
* evidence inspected;
* decisive counterevidence;
* conclusion.

Do not record every trivial dead end.

Record cases likely to save Opus from repeating expensive investigation or cases that materially demonstrate why a tempting finding is invalid.

Uncertainties

Record concerns for which the available evidence is insufficient or conflicting.

For each, explain:

* what is known;
* what remains unknown;
* why current evidence is insufficient;
* what additional evidence would resolve it.

Never convert uncertainty into certainty for the sake of finishing the review.

⸻

14. Phase 9 — Use Automated Evidence Intelligently

Where safe and materially useful, use:

* repository searches;
* compiler diagnostics;
* existing test suites;
* targeted existing tests;
* clean builds where practical;
* static analysis already available in the project;
* dependency inspection;
* configuration inspection;
* source-control history only when it materially clarifies current behavior;
* lightweight temporary analysis commands/scripts that do not alter production behavior.

Automated evidence is supporting evidence, not a substitute for reasoning.

Before relying on a test, establish what the test actually covers.

Before relying on a search, establish whether the search pattern could miss semantically equivalent behavior.

Before using successful compilation as evidence, establish what property compilation actually proves.

Do not manufacture tests simply to create confirmation for your own hypothesis. The subsequent planning/implementation phase owns new application tests.

If temporary untracked analysis material is created, keep it within the review workspace or another clearly disposable location and identify it as temporary.

⸻

15. Phase 10 — Physical-Device and Environment Boundary

Static review, simulator behavior, tests, and builds cannot establish every property of an iOS application.

Do not fake precision where current evidence is insufficient.

Explicitly consider whether important conclusions require physical-device evidence for areas such as:

* real camera behavior;
* AVFoundation startup/teardown characteristics;
* real frame throughput;
* scan latency;
* thermal behavior;
* memory pressure;
* actual CPU/GPU characteristics;
* animation/frame pacing;
* real permission flows;
* camera interruption;
* foreground/background transitions;
* device rotation where relevant;
* image capture quality;
* network transitions;
* real-world recognition conditions;
* battery/resource behavior;
* or hardware-specific APIs.

For every device/environment-dependent item, record in 06-device-and-environment-validation.md:

* what is currently established;
* what remains unknown;
* why existing evidence cannot settle it;
* exact validation procedure;
* relevant device/environment conditions;
* observable pass/fail evidence where a binary gate is justified;
* statistical measurement approach where behavior is stochastic.

Do not classify an untested device hypothesis as a confirmed runtime defect solely because one outcome is theoretically possible.

⸻

16. Phase 11 — Cross-Subsystem Reconciliation Pass

After the primary subsystem and flow reviews are substantially complete, perform a distinct repository-wide reconciliation pass.

This is mandatory.

Do not treat earlier thoroughness as a substitute.

Stop thinking primarily file-by-file and reconsider the application as one integrated system.

Explicitly investigate:

* competing sources of truth;
* contradictory ownership;
* lifecycle assumptions that differ across callers;
* multiple components independently managing the same resource;
* navigation behavior versus resource lifetime;
* duplicated business rules;
* identity semantics that differ between layers;
* cache semantics that differ between producers and consumers;
* invalidation inconsistencies;
* persistence versus in-memory-state disagreement;
* UI state versus domain-state disagreement;
* async operations whose assumed lifetime differs from actual owner lifetime;
* cancellation inconsistencies;
* errors swallowed at subsystem boundaries;
* performance costs created by subsystem interaction;
* duplicated work initiated by different layers;
* divergent definitions of the same domain concept;
* old and new architecture coexisting inconsistently;
* abstractions that no longer correspond to actual responsibility.

Then reconcile the finding ledger:

* merge true duplicates;
* link related but distinct findings;
* identify shared root causes;
* downgrade findings weakened by broader evidence;
* reject findings disproved by broader evidence;
* escalate scope only when broader evidence supports it;
* revise causal explanations when the system-level picture changes them.

Record whether this reconciliation materially changed earlier conclusions.

⸻

17. Phase 12 — Architecture Challenge Pass

Perform a separate conceptual challenge to your own repository model.

Ask:

* Have I correctly identified the application’s real sources of truth?
* Have I confused naming conventions with actual ownership?
* Where does responsibility cross architectural boundaries unexpectedly?
* Are two systems solving the same problem independently?
* Does any subsystem depend on undocumented side effects elsewhere?
* Are there behaviors that work only because operations happen in a particular incidental order?
* Are there lifecycle guarantees that nobody actually owns?
* Are there caches or derived-state layers whose consistency assumptions are implicit?
* Are there abstractions that look clean locally but create global complexity?
* Are several findings symptoms of one deeper architectural mismatch?
* Is anything surprisingly robust that my initial model incorrectly treated as fragile?

Update the repository map and findings when this pass changes your understanding.

⸻

18. Phase 13 — Adversarial Self-Review

Before completion, act as a skeptical independent senior engineer reviewing your own work.

Explicitly challenge:

Coverage

* Which production subsystem received the least scrutiny?
* Which important files received only contextual review?
* Were any difficult areas effectively skipped?
* Did search-driven investigation bias attention toward expected problems?
* Are there configuration or integration surfaces that escaped the production-file inventory?

Findings

* Which finding has the weakest causal chain?
* Which relies most heavily on inference?
* Which has the least demonstrated impact?
* Which could be intentional behavior?
* Which could be handled by code outside the path initially inspected?
* Which finding did I become attached to too early?
* Did I mistake unusual code for incorrect code?

Architecture

* Which architectural assumption am I taking for granted?
* Could my source-of-truth model be wrong?
* Could a hidden ownership relationship explain an apparent inconsistency?
* Did I trace enough callers and consumers before generalizing?

Concurrency

* Did I infer safety from annotations or compilation without tracing actual task behavior?
* Did I inspect cancellation and owner lifetime?
* Did I account for reentrancy and ordering?
* Did I distinguish theoretical races from reachable ones?

Performance

* Did I report micro-optimizations with no evidence of meaningful execution frequency?
* Did I inspect actual hot paths?
* Could apparently expensive work already be cached or amortized elsewhere?
* Did I confuse theoretical complexity with practical user impact?

Tests

* Did I assume passing tests prove more than they do?
* Did I ignore useful test evidence because it contradicted a finding?
* Did I inspect whether tests exercise realistic paths?

Cross-system reasoning

* Did I produce a collection of good local reviews without truly synthesizing them?
* Which behaviors span the greatest number of subsystems?
* Have I specifically revisited those behaviors after understanding the entire repository?

Perform additional inspection wherever this challenge exposes a meaningful, resolvable gap.

Do not merely write answers to these questions and continue.

Use them to trigger additional work.

⸻

19. Phase 14 — Final Coverage Reconciliation

Reconcile 02-coverage-ledger.md against the actual repository again.

Do not trust the initial inventory.

Check for:

* files added or missed;
* production files incorrectly excluded;
* files reviewed only indirectly;
* important extensions or configuration;
* additional source roots;
* packages;
* target-specific code;
* conditional compilation;
* code not obvious from the main app directory.

Resolve every avoidable NEEDS-FOLLOWUP.

Calculate and record:

* total in-scope production files;
* REVIEWED-DEEP;
* REVIEWED-CONTEXT;
* each excluded category;
* DEVICE-DEPENDENT;
* unresolved files, if any.

Do not claim 100% meaningful coverage merely because every row contains a label.

The classifications must be defensible.

⸻

20. Phase 15 — Prepare the Independent Opus Handoff

Create 07-opus-handoff.md.

This document should allow Opus to begin at the highest-value reasoning layer without blindly trusting your conclusions.

It must be concise relative to the underlying evidence.

Include:

Repository model

Explain the application’s architecture in a compact way.

Focus on:

* major subsystems;
* major sources of truth;
* important ownership boundaries;
* important flows;
* important dependencies.

Review coverage

Report what was reviewed, how deeply, and what was excluded.

Include coverage counts and any meaningful limitations.

Highest-value validated findings

Identify the findings most consequential to correctness, reliability, performance, data integrity, lifecycle, or architecture.

Reference canonical finding IDs rather than duplicating full finding text.

Cross-cutting themes

Explain systemic relationships among findings.

Examples:

* common root causes;
* repeated ownership problems;
* recurring invalidation problems;
* architectural drift;
* state duplication;
* lifecycle inconsistencies.

Findings most deserving independent skepticism

Identify conclusions Opus should verify especially carefully because they are:

* high impact;
* architecturally consequential;
* unusually subtle;
* based on complicated causal chains;
* or supported by evidence that remains less direct than ideal.

Important rejected hypotheses

Identify false positives that Opus is particularly likely to rediscover.

Important unresolved uncertainties

Identify what remains genuinely unknown.

Device/environment validation

Reference all material items requiring evidence unavailable to Luna.

Areas where Opus should search for omissions

Identify parts of the repository or conceptual relationships where your confidence in completeness is comparatively lowest.

Suggested verification order

Recommend an efficient order for Opus to independently validate the evidence.

This may be based on impact, uncertainty, architectural centrality, or dependency.

It must NOT become a remediation sequence or implementation roadmap.

Explicit handoff boundary

State clearly:

Luna’s findings are evidence-supported review conclusions, not final truth. Opus should independently inspect the repository and relevant evidence, reject or revise unsupported conclusions, search for important omissions, synthesize the verified findings, and only then create the implementation plan.

Do not write that implementation plan yourself.

⸻

21. Evidence Rules

Throughout the review:

Prefer primary evidence

Strongest evidence usually includes:

* current source code;
* actual call paths;
* runtime/build/test results;
* project configuration;
* directly observed behavior;
* authoritative framework behavior when necessary.

Comments, names, TODOs, stale documents, and previous model output may guide investigation but do not override current implementation evidence.

Match evidence scope to claim scope

A narrow test cannot prove a repository-wide claim.

One call site cannot establish behavior for all call sites.

One successful simulator scenario cannot establish physical-device reliability.

A grep with no results cannot always establish semantic absence.

A successful build cannot establish runtime correctness.

Separate observation from inference

When documenting a finding, distinguish:

* what the repository directly shows;
* what you infer from it;
* what impact follows if the inference is correct.

Do not use absence of discovered evidence as positive proof

“I did not find another owner” is weaker than demonstrating ownership from construction and call paths.

“I found no test failure” is weaker than a test specifically exercising the claimed property.

The review should seek affirmative evidence wherever practical.

⸻

22. Review Quality Rules

Do not optimize for number of findings.

Do not pad the report.

Do not report ordinary stylistic preferences.

Do not relabel speculative concerns as architectural risks simply to retain them.

Do not create decorative precision.

Do not assign severity based on how complicated a fix might be.

Do not assume old code is wrong because it looks unusual.

Do not assume new code is correct because it looks modern.

Do not assume tests are correct simply because they exist.

Do not assume comments accurately describe behavior.

Do not assume an abstraction is authoritative merely because its name implies authority.

Do not assume concurrency correctness from annotations alone.

Do not assume performance problems solely from theoretical complexity.

Do not confuse possible with probable.

Do not confuse probable with confirmed.

Do not confuse code quality with product impact.

When uncertain, investigate.

When investigation cannot settle the matter, preserve the uncertainty.

⸻

23. Efficiency Rules

Exhaustiveness does not mean spending equal effort everywhere.

Allocate depth according to architectural importance and potential impact.

Use:

* inventories;
* targeted searches;
* dependency tracing;
* call-site tracing;
* subsystem grouping;
* existing tests;
* architecture maps;
* coverage ledgers;
* and durable notes

to avoid repeatedly rediscovering the same information.

Once simple leaf code has been directly inspected and reasonably classified as low-risk context, move on.

Spend disproportionate attention on:

* central state owners;
* heavily shared services;
* high-frequency execution paths;
* persistence;
* asynchronous boundaries;
* scanner/camera lifecycle;
* identification logic;
* destructive or transactional operations;
* resource ownership;
* cross-subsystem contracts;
* and code implicated by multiple independent findings.

Do not substitute token expenditure for reasoning quality.

⸻

24. Recovery After Context Compaction or Long Continuation

If your immediate context no longer contains enough detail to continue confidently:

1. reread this contract;
2. read 00-review-control.md;
3. read the relevant canonical review artifacts;
4. inspect current git status;
5. inspect the current source state relevant to the next task;
6. continue from authoritative repository evidence.

Do not attempt to reconstruct precise technical conclusions from vague conversational memory.

Do not assume a previous finding remains valid if current evidence has changed.

Keep 00-review-control.md current enough that a fresh instance with access only to:

* the repository;
* this contract;
* and the review workspace

could determine what has been completed, what remains, and why.

⸻

25. Genuine Blockers

Difficulty is not a blocker.

Large scope is not a blocker.

Uncertainty is not automatically a blocker.

A failing build is not automatically a blocker.

A suspected issue requiring more tracing is not a blocker.

Continue whenever meaningful investigative progress remains possible.

Examples of genuine external boundaries may include:

* required physical-device evidence unavailable in the environment;
* unavailable credentials genuinely necessary to observe external behavior;
* inaccessible external systems;
* a user/product decision without which a conclusion cannot logically be established.

Even when a blocker exists for one item, continue reviewing all other areas that remain possible.

Document blocked evidence rather than inventing it.

⸻

26. BINDING DEFINITION OF DONE — EVERY ITEM REQUIRED

The Pursue Goal may be declared complete only when current authoritative evidence establishes ALL of the following:

1. This contract has been read in full.
2. Applicable repository instructions have been identified and followed.
3. The initial repository/worktree state has been recorded without disturbing pre-existing user work.
4. The relevant production-code universe has been identified.
5. A defensible repository and architecture map exists.
6. Every relevant production source file has a defensible coverage classification.
7. No avoidable NEEDS-FOLLOWUP file classifications remain.
8. Every architecturally important subsystem has received substantive review.
9. Important state ownership and sources of truth have been identified.
10. Important subsystem dependencies have been traced.
11. Important end-to-end application flows have been traced across subsystem boundaries.
12. Important cross-cutting invariants have been identified.
13. Those invariants have been tested against relevant implementation evidence rather than merely documented.
14. Candidate findings have been challenged with counterevidence before confirmation.
15. Every canonical finding contains sufficient evidence for an independent reviewer to locate, understand, and test the conclusion.
16. Findings distinguish observation, inference, causal mechanism, and impact.
17. Severity and confidence have been calibrated rather than inflated.
18. Meaningful false-positive hypotheses have been documented.
19. Meaningful unresolved hypotheses have been preserved as uncertainties instead of being promoted to findings.
20. Existing automated/build/test evidence has been used where materially helpful and its scope has not been overstated.
21. Physical-device and environment-dependent conclusions have been clearly separated from conclusions established in the current environment.
22. A distinct repository-wide cross-subsystem reconciliation pass has been completed.
23. Findings were reconciled after that pass for duplicates, shared root causes, changed scope, weakened evidence, and contradictions.
24. A separate architecture challenge pass has been completed.
25. A genuine adversarial self-review has been performed.
26. Material gaps exposed by adversarial self-review were investigated where current-environment investigation remained possible.
27. The production-file inventory was independently reconciled against the repository near the end of the review.
28. Coverage counts in the control/handoff artifacts reflect current repository evidence.
29. The Opus handoff has been completed.
30. The Opus handoff explicitly preserves Opus’s independence rather than presenting Luna’s conclusions as final truth.
31. No production implementation changes were made.
32. No existing application tests were altered.
33. No final implementation plan was written.
34. No requirement in this contract was weakened, silently skipped, or reinterpreted merely to permit completion.
35. All remaining unknowns genuinely require evidence, access, device testing, external change, or human/product judgment unavailable in the current environment.
36. There is no additional review work required by this contract that can reasonably be performed with the current repository and available environment.

⸻

27. Mandatory Final Completion Audit

Before declaring the Goal complete:

1. Reread this entire contract from disk.
2. Treat completion as unproven.
3. Walk through every numbered Definition-of-Done criterion individually.
4. For each criterion, identify the current authoritative evidence proving it.
5. Record the reconciliation in 00-review-control.md.

Use one of these statuses for each criterion:

* PROVEN
* NOT PROVEN
* BLOCKED-EXTERNAL

Do not use PROVEN when evidence is merely:

* plausible;
* indirect;
* remembered;
* consistent with completion;
* or based on failure to notice contrary evidence.

If any criterion is NOT PROVEN and meaningful work can still be performed in the current environment, continue working.

If an item is BLOCKED-EXTERNAL, document:

* the precise blocker;
* why it prevents proof;
* why no further meaningful current-environment investigation can resolve it;
* and what evidence would resolve it later.

Do not declare completion merely because:

* the review has run for a long time;
* the context window has been compacted;
* token usage is high;
* the findings are already valuable;
* the application builds;
* tests pass;
* most files have been reviewed;
* the remaining work seems low value;
* or a polished handoff already exists.

The completion audit must prove that the review contract has been satisfied.

⸻

28. Final Response After the Goal Is Truly Complete

Do not reproduce the entire review in the final chat response.

Report concisely:

* that the Pursue Goal review is complete;
* location of the review workspace;
* total in-scope production files;
* count of REVIEWED-DEEP;
* count of REVIEWED-CONTEXT;
* excluded-file counts by category;
* number of canonical findings by severity and classification;
* number of meaningful rejected hypotheses;
* number of unresolved uncertainties;
* number of device/environment-dependent items;
* whether the cross-subsystem reconciliation materially changed earlier findings;
* whether the architecture challenge materially changed the repository model;
* whether every Definition-of-Done criterion was PROVEN or whether any unavoidable BLOCKED-EXTERNAL items remain;
* and the path to 07-opus-handoff.md.

End by stating that the repository and evidence package are ready for the independent Opus verification and planning pass.

Do not summarize proposed fixes.

Do not produce an implementation plan.

Do not begin implementation.
