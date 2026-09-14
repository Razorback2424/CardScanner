# CardScanner Collection Integrity Strategy

## 1. Product thesis

CardScanner should evolve from a highly capable card scanner and collection manager into a **verified system of record for a physical trading-card collection**.

The product promise is:

> **Make your digital collection agree with your real one — and make keeping them in agreement easy.**

The core product loop is:

**Scan / Import → Resolve → Place → Verify → Reconcile → Verify Again**

Each stage has a distinct job:

**Scan** creates or updates the digital record.

**Resolve** establishes what the card actually is and preserves meaningful uncertainty rather than inventing certainty.

**Place** connects a digital record to a physical object and location.

**Verify** observes physical reality and compares it with the expected digital state.

**Reconcile** resolves discrepancies between reality and the database.

**Verify Again** creates the recurring job and determines whether integrity
maintenance has recurring user value.

The first public release is free. Any future packaging or monetization decision
must follow observed retention behavior and receive a separately versioned
experiment. This is the decision framework for the current roadmap.

A feature that does not materially improve identity, physical organization, verification, reconciliation, migration, valuation integrity, or maintenance efficiency should face a much higher bar for near-term development.

---

# PHASE 0 — Freeze the experiment

Before adding the new system, define what is being tested.

The hypothesis is not:

> Collectors want binder locations.

It is:

> **Collectors with sufficiently large or dynamic collections experience enough drift between their physical cards and their digital records that they will repeatedly use tools that make detecting and correcting that drift substantially easier.**

There is no willingness-to-pay hypothesis in this experiment. The first version
exists to test whether the recurring integrity job exists and whether serious
collectors return to it after real-world change. Grade/Sell and economic
workflows receive a separate future monetization experiment.

Do not require the first version to prove the entire long-term vision.

### Primary behavioral chain

The minimum successful behavior is:

**Import/catalog → Place → Verify → find discrepancy → Reconcile → physical collection changes → voluntarily Verify again**

The most important event in that chain is not the first Verify.

It is the **second Verify after real-world change**.

That is evidence of a recurring job.

### Initial success criteria

For an intentionally targeted early cohort of approximately 15 serious collectors, the results would be encouraging if roughly:

- 10+ establish meaningful physical locations;
- 8+ complete a real verification;
- 5+ discover and resolve at least one genuine discrepancy;
- 4+ voluntarily perform another verification or verify another meaningful location;
- 4+ complete a repeat Verify after a qualifying physical collection change within 42 days.

These are directional validation thresholds, not statistical proof.

Praise is not validation.

The behavioral sequence is validation.

---

# PHASE 1 — Make the existing product worthy of a trust promise

Before introducing Collection Integrity publicly, eliminate known behavior that can silently make the digital collection wrong.

This phase should not become a general refactoring project.

The standard is narrower:

> **Can anything currently cause the application to silently store, interpret, total, identify, or display materially incorrect collection information?**

Prioritize known and newly discovered issues involving:

| Integrity area | Required state |
|---|---|
| Exact card identity | No known silent wrong-printing behavior |
| Variant / finish | Ambiguity represented explicitly when necessary |
| Quantity | Collection quantities remain consistent through all workflows |
| Graded/sealed identity | Print identity preserved correctly |
| Import/export | Round-trip identity does not silently degrade |
| Currency | Non-USD values cannot silently behave as USD |
| Price source | Source and observation semantics remain accurate |
| Price freshness | Newer valid observations cannot be rejected incorrectly |
| Collection vs portfolio totals | Same underlying facts produce consistent results |
| Persistence | Restarts cannot silently change collection state |
| Scanner modes | Price Check and Collection behavior remain correctly separated |

This is also when the scanner itself should receive a final integrity-focused review, but do not hold the strategy hostage to perfection in unrelated polish.

### Exit criterion

There should be no known **silent collection-integrity defect** that materially contradicts the proposed trust positioning.

---

# PHASE 2 — Build the correct physical-inventory domain model

This is the most consequential engineering decision in the strategy.

Do not attach `binderName`, `page`, and `slot` directly to an aggregated card record and call the problem solved.

Separate three concepts.

## Catalog identity

This describes the abstract printing:

> Pokémon / Umbreon VMAX / Evolving Skies / 215/203 / English / Alternate Art

It answers:

> **What is this?**

## Owned holding / physical copy

This describes what the collector owns.

For meaningful cards, an owned object should be capable of having its own:

- stable identifier;
- catalog identity;
- finish/treatment;
- language;
- condition;
- graded status;
- acquisition metadata where relevant;
- identity-resolution provenance;
- current inventory state.

It answers:

> **Which physical thing do I own?**

Not every bulk card needs heavyweight copy-level management.

The model should support both:

**individualized copies** when physical distinction matters; and

**aggregated holdings** where multiple interchangeable bulk copies can reasonably be treated together.

Avoid forcing warehouse-level bookkeeping onto casual users.

## Placement

Placement answers:

> **Where should this physical thing currently be?**

Placement must be separate from identity.

A card can move without becoming a different card.

A minimum placement model should support:

- unplaced;
- container;
- optional page/row;
- optional slot/position.

The model should be extensible enough to represent binders and boxes without designing an elaborate generic warehouse-management engine.

### Container examples

Binder  
Box  
Slab case  
Trade binder  
Deck or deck box eventually  
Temporary intake / unsorted area

Only the types necessary for the initial experiment need polished UX.

## Stable identity

Every independently managed physical holding should have a stable internal identifier that does not change when:

- the card is moved;
- its condition is updated;
- its placement changes;
- its verification state changes;
- its valuation changes.

This becomes essential for audit history.

## Migration

Existing collections must migrate safely.

A current record representing:

> Card X, quantity = 4

should not automatically become four unnecessarily heavyweight physical-copy records unless the workflow requires it.

Design an explicit migration policy for:

- aggregated existing holdings;
- graded cards;
- sealed items;
- imported records;
- known per-copy information.

Preserve compatibility with current CSV/import/export behavior.

### Exit criterion

The application can represent:

> “I own three copies of this printing. One is in Binder A / Page 3 / Slot 4; another is in my Trade Binder; one is currently unplaced.”

without abusing folders, duplicating catalog identity, or corrupting existing collection semantics.

---

# PHASE 3 — Build Place before Verify

Place must be useful even before the verification system exists.

The UX goal is:

> **Connecting a physical card to a location should be faster than maintaining the same information manually.**

## Container setup

Creating a physical container should be extremely lightweight.

For a binder:

Name → page layout → optional starting page.

For a box:

Name → optional row/section structure.

Do not require collectors to fully configure a warehouse ontology before placing their first card.

## Manual placement

A user must be able to open a holding and say:

> Move to → Alt Arts Binder → Page 7 → Slot 4

This is the baseline.

## Scan-to-Place

This is the important workflow.

The collector selects:

> **Adding to: Alt Arts Binder → Page 7**

Then begins scanning.

The location context remains active.

Each successful scan can automatically advance:

Slot 1 → Slot 2 → Slot 3...

The collector should not repeatedly enter location information.

The UX should support:

- skip empty slot;
- move backward;
- replace a placement;
- undo last placement;
- resolve an uncertain card without losing the placement sequence.

## Unplaced queue

“Unplaced” must be a legitimate state rather than an error.

Newly scanned/imported cards can exist in:

> **Unfiled / location unknown**

The user can later work through that queue.

This avoids making physical rigor mandatory for ordinary collection use.

### Free product requirement

Basic placement must be available free.

Users need to understand the physical-inventory model before being asked to pay for maintaining it.

### Exit criterion

A collector can physically organize a real binder using CardScanner without the process feeling meaningfully more burdensome than simply putting cards into the binder.

---

# PHASE 4 — Build sequential Verify

Do not wait for binder-page computer vision.

Version 1 should deliberately use the scanning technology that already exists.

Verification asks a fundamentally different question from scanning.

Normal scan:

> **What card is this?**

Verify:

> **Does what I am physically observing agree with what the database says should be here?**

## Starting a verification

The user selects:

> Alt Arts Binder → Page 7 → Verify

The system loads the expected state.

Example:

Slot 1: Umbreon  
Slot 2: Rayquaza  
Slot 3: empty  
Slot 4: Gengar  
...

Then the user sequentially presents the actual cards.

Because the expected state is known, verification can potentially use that prior information to improve confidence without silently forcing a match.

## Verification outcomes

A physical observation should produce explicit outcomes such as:

**Match**

Expected item observed in expected position.

**Identity uncertainty**

Observed card is likely the expected printing but important identity/variant evidence remains unresolved.

**Wrong position**

Known holding observed in a different position.

**Unexpected card**

Observed item was not expected in this position/container.

**Expected card missing**

Nothing corresponding to the expected holding was observed.

**Quantity discrepancy**

Relevant where aggregated holdings are used.

**Duplicate/conflict**

Observation suggests the same tracked physical holding cannot simultaneously exist in both recorded locations.

Do not silently repair these.

Verification discovers differences.

Reconciliation decides what they mean.

## Confidence discipline

Do not let “expected card = X” cause the scanner to simply declare the observation X.

Expected state can constrain candidate evaluation, but contradictory evidence must remain visible.

Otherwise Verify becomes self-confirming theater.

### Exit criterion

A user can sequentially verify a real container and receive a trustworthy comparison between **expected state and observed physical state**.

---

# PHASE 5 — Build Reconciliation

Verify becomes strategically useful only if disagreements are easy to resolve.

The user should leave a verification session with a concise discrepancy queue.

Example:

> **Binder verification complete**
>
> 68 matches  
> 2 moved cards  
> 1 missing card  
> 1 unexpected card  
> 1 variant needs confirmation

Each discrepancy should have a small set of understandable actions.

## Examples

### Card found in wrong position

Expected:

> Slot 8 — Gengar

Observed:

> Slot 9 — Gengar

Actions:

**Update placement to Slot 9**  
**Move physical card back to Slot 8**  
**Review manually**

The app cannot know which reality is intended.

It should not invent that answer.

### Unexpected card

Actions might include:

**Add this physical copy here**  
**Move existing holding here**  
**Replace expected card**  
**Leave unresolved**

### Missing card

Actions:

**Mark location unknown**  
**Mark as moved / temporarily unplaced**  
**Remove from collection** only through an intentional ownership action  
**Leave discrepancy open**

A failed verification should never automatically conclude:

> “You no longer own this card.”

### Variant mismatch

Reuse the existing identity/variant-resolution philosophy.

Present exactly what disagrees and what evidence exists.

### Exit criterion

A collector can complete Verify and return the collection to a coherent state without manually editing database records across several screens.

---

# PHASE 6 — Add verification provenance

Do this before turning Collection Health into a major UI feature.

Every verification should create evidence.

For a physical holding, the product should eventually be capable of saying:

> Alt Arts Binder → Page 7 → Slot 4  
> Placed September 14  
> Last physically verified October 3  
> Verified by sequential scan  
> Exact printing confirmed  
> Finish user-confirmed  
> No open discrepancies

The specific data model should support:

- verification timestamp;
- verification session identifier;
- physical location observed;
- method of verification;
- identity result;
- unresolved uncertainty;
- reconciliation events afterward.

Do not confuse “was once placed here” with “was physically verified here.”

These are distinct facts.

## State hierarchy

A useful conceptual hierarchy is:

**Cataloged**  
A collection record exists.

**Identified**  
The printing identity is established.

**Resolved**  
Important ambiguity has been handled.

**Placed**  
The expected physical location is known.

**Verified**  
The physical object has actually been observed in agreement with that record.

**Freshly verified**  
That observation is recent enough to remain useful.

The product does not need to plaster these labels everywhere.

They should, however, be real concepts underneath the UX.

### Exit criterion

“Verified” has an auditable meaning and cannot simply mean “our scanner was confident.”

---

# PHASE 7 — Build transparent Collection Health

Do not initially collapse everything into a proprietary 0–100 score.

Show the real dimensions.

Example:

> **Collection Integrity**
>
> Identity complete — 98%  
> Variants resolved — 94%  
> Physically located — 72%  
> Verified in last 90 days — 46%  
> Open discrepancies — 7  
> Import records needing review — 19

This makes sophisticated underlying infrastructure understandable.

Each dimension should lead somewhere actionable.

Tap:

> **7 open discrepancies**

and see the reconciliation queue.

Tap:

> **428 unplaced**

and enter a placement workflow.

Tap:

> **19 unresolved imports**

and review them.

Collection Health should be an operational dashboard, not a vanity dashboard.

## Freshness

Do not assert that an old verification has become “wrong.”

Instead:

> Last verified 187 days ago.

Potentially classify freshness bands later based on user behavior.

Avoid fake precision.

### Exit criterion

A collector can answer within seconds:

> **What parts of my collection record can I trust, and what needs attention?**

---

# PHASE 8 — Turn migration into acquisition

Import is not merely file compatibility.

It should become a product experience.

## Source-aware adapters

Prioritize import formats based on real migration demand and feasibility.

Potential sources include:

Collectr  
TCGplayer  
Dex  
ManaBox where appropriate  
generic CSV

Do not attempt every platform simultaneously.

Start with the formats most likely to deliver large collections from your actual target users.

## Staged import

Never make the experience:

> 3,184 rows processed. Import complete.

Instead, classify the result.

Example:

> **3,184 records imported**
>
> 2,941 confidently mapped  
> 173 variant records need review  
> 54 possible duplicate/conflict records  
> 16 unresolved
>
> Physical verification: Not started

Then:

> **Make this collection authoritative →**

This transition is strategically important.

The user's old database becomes the prior state.

CardScanner helps determine how trustworthy it actually is.

## Import provenance

Preserve:

- source application;
- imported source identifiers where useful;
- original source fields where needed for debugging/reconciliation;
- mapping confidence;
- user corrections.

Import should never silently convert uncertainty into certainty.

## Export

Basic export remains free.

The product promise should eventually be explicit:

> **Your collection belongs to you. Export it anytime.**

Do not create trust through lock-in.

### Exit criterion

A collector with thousands of cards can realistically try CardScanner without rebuilding years of work.

---

# PHASE 9 — Separate future packaging from the free 1.0 release

The public 1.0 contains the complete currently implemented scanner, collection,
pricing, portfolio, import/export, graded, and sealed capabilities without a
purchase gate. Place, Verify, Reconcile, Collection Health, and any future
Grade/Sell workflow remain outside this binary.

After the retention experiment has produced evidence, a separate plan may
define packaging around ongoing integrity maintenance. It must preserve data
portability and must not gate the first meaningful value loop before that loop
has been validated.

The free release does not define entitlement boundaries for this future
subsystem. Any later packaging should preserve the complete first meaningful
integrity loop and be based on observed maintenance value.

### Exit criterion

The retention evidence clearly answers whether collectors return to Verify after
real collection change. Packaging and pricing are deferred until that evidence
is available.

---

# PHASE 10 — Instrument the product around behavioral truth

Do not judge this strategy by App Store downloads or compliments.

Instrument the funnel.

The core events should allow you to determine:

| Event | Why it matters |
|---|---|
| Import started/completed | Acquisition from incumbent |
| Records confidently/unconfidently mapped | Migration quality |
| Container created | User understands physical model |
| First placement | Place activation |
| Meaningful placement count | Real use rather than experimentation |
| First Verify started | Differentiated feature reached |
| First Verify completed | Workflow usable |
| Discrepancy discovered | Product generated new information |
| Discrepancy reconciled | Product helped solve problem |
| Collection changed later | Real drift opportunity |
| **Second Verify** | **Evidence of recurring job** |
| Later packaging discussion after integrity event | Future product decision context |
| Repeat Verify after qualifying change | Recurring-job evidence |

Respect the app's privacy/local-first principles.

Do not collect detailed private inventories merely because analytics would be convenient.

Aggregate behavior where possible.

---

# PHASE 11 — Private product validation

Before public marketing of the integrity thesis, recruit approximately 10–20 serious collectors.

Do not recruit average App Store users.

Seek people with:

- multiple binders;
- boxes;
- thousands of cards;
- decks;
- active trades;
- grading submissions;
- duplicate purchases;
- existing digital inventories;
- frustration with locating cards;
- migration problems.

Friends can use TestFlight.

Unknown users should ideally encounter the public App Store build rather than being asked to install a development beta.

## Observation

Do not ask:

> “Do you like Verify?”

Ask users to use their actual collection.

Observe:

- Did they bother creating real locations?
- Did they understand expected vs observed state?
- Was placement too much work?
- Did verification find anything real?
- Did reconciliation feel trustworthy?
- Did they voluntarily continue?
- Did Verify feel valuable enough to repeat?

The strongest possible signal is spontaneous behavior:

> “I traded some cards yesterday, so I ran Verify again.”

---

# PHASE 12 — Run the retention experiment

Once the end-to-end loop works, test whether the recurring integrity job exists.

Do not purchase advertising.

Manually recruit the first serious users through relevant collector communities, personal connections, local collectors, and targeted communities where appropriate.

The message should not be:

> “Try my card scanner.”

It should increasingly become:

> **Already have a collection somewhere else? Bring it with you.**
>
> CardScanner helps identify what can be trusted, shows what still needs review, connects your digital inventory to where the physical cards actually live, and lets you verify that the two still agree.

That communicates the differentiation.

## Interpret results honestly

### Scenario A

Users Place → Verify → Verify again.

**Strong retention validation.**

Invest further.

### Scenario B

Users Place → Verify → Verify again, with no monetization decision attached.

The recurring job probably exists. Investigate frequency, targeting, speed,
and perceived value before designing a separate packaging experiment.

### Scenario C

Users Place and Verify once but do not return.

Potential one-time organization utility.

Do not rationalize this into a recurring retention conclusion.

Investigate whether another recurring job exists before making large investments.

### Scenario D

Users import but do not Place.

Physical setup friction is too high or the job is not important enough.

Improve Place before building more Verify technology.

### Scenario E

Users Verify but almost never find discrepancies.

Either drift is too rare to matter, the workflow is targeting the wrong collections, or Verify needs additional recurring value.

### Scenario F

Users repeatedly Verify and complain that it takes too long.

**This is the ideal signal for binder-page computer vision.**

Now the expensive technical investment has evidence behind it.

---

# PHASE 13 — Binder-page recognition only after validation

Do not build this merely to match PokéLenz.

Build it to accelerate a proven workflow.

The progression becomes:

Current:

> Verify nine slots sequentially.

Future:

> Point camera at entire page.

Result:

> **Page 14 — 7/9 verified**
>
> ✓ seven expected cards  
> ⚠ one finish uncertain  
> ↔ one card shifted position  
> ? one unexpected card  
> ! one expected card not found

The differentiation is not detecting nine cards.

It is reconciling nine physical observations against nine expected records.

That distinction should remain central to the implementation.

---

# PHASE 14 — Deepen the integrity system

Only after repeated verification has demonstrated real user value should the product expand vertically.

Potential next layers:

## Faster physical management

QR container labels  
Location shortcuts  
Batch moves  
Pull lists  
Seller pick lists  
Grading-submission states

## Stronger integrity automation

Stale-verification detection  
Verification reminders  
Cross-container inconsistencies  
Unexpected quantity movement  
Duplicate-placement detection

## Valuation integrity

Named price-source provenance  
Freshness  
Cross-source disagreement  
Outlier detection  
Low-liquidity warnings  
Condition uncertainty

Do not claim “true market value.”

Represent uncertainty.

## Documentation

Timestamped collection reports  
Verification history  
Insurance exports  
Estate/inventory reports  
Photos where useful

These could become meaningful premium features.

---

# PHASE 15 — Develop the long-term moat

The moat is not:

Binder fields  
QR codes  
Audit mode  
Multi-card scanning

All can be copied.

The long-term advantage is accumulated evidence and a coherent integrity model.

Over time the system can learn:

- which catalog records frequently cause ambiguity;
- which variants users frequently correct;
- which scanner signals are reliable;
- which imports commonly mis-map;
- which price sources produce anomalies;
- how often particular verification states drift;
- which physical workflows create the least user burden;
- which uncertainty mechanisms actually predict user correction.

That produces a flywheel:

**More verification → more correction evidence → better identity/integrity logic → fewer silent mistakes → more trust → more users willing to treat CardScanner as authoritative → more verification.**

Protect privacy throughout.

Trust is part of the product, not merely a compliance requirement.

---

# Product principles that should govern implementation

## Never invent certainty

Unknown is better than confidently wrong.

This already exists in parts of the architecture and should become a visible product philosophy.

## Verification must be falsifiable

Expected state can inform recognition.

It cannot force recognition.

Verify must be capable of telling the user:

> “Reality does not match what we expected.”

## Do not silently reconcile

Detection and correction are separate.

The user should understand meaningful changes to the authoritative inventory.

## Reduce bookkeeping rather than creating it

The product fails if maintaining rigorous inventory feels like running a warehouse.

Every integrity capability must reduce effort compared with the manual alternative.

## Protect portability

Basic export remains free.

Import should preserve provenance.

User data remains the user's data.

## Preserve casual use

A collector who simply wants to scan a card and check its price should still be able to do that without participating in the entire inventory system.

Do not turn rigor into mandatory bureaucracy.

## Treat regression risk seriously

CardScanner is already mature.

Implement this in coherent, bounded slices.

Each new slice should preserve existing scanner, collection, pricing, import/export, graded/sealed, and portfolio behavior.

---

# What should explicitly be frozen for now

Unless required by the integrity experiment, defer:

Additional TCG breadth beyond current priorities  
Marketplace functionality  
Social network functionality  
Major deck-building expansion  
Automated grading as a strategic wedge  
New generic portfolio dashboards  
Insurance tooling  
Household/shared collections  
Seller-specific tooling  
QR hardware workflows  
Binder-page recognition  
Large speculative architecture rewrites  
New scanner technology merely because competitors have it

Existing useful functionality should remain.

The instruction is not to delete breadth.

It is to **stop adding unrelated breadth while the central hypothesis remains untested.**

---

# Recommended engineering execution pattern

Each phase should follow the same discipline:

**Plan → verify plan → implement bounded slice → regression test → inspect rendered workflow → adversarial review → accept or correct → move on.**

For significant structural work, especially the holdings/placement migration:

- produce explicit invariants before implementation;
- preserve legacy import/export behavior;
- test migration from existing persisted collections;
- test graded/sealed and quantity edge cases;
- avoid unrelated refactors;
- establish rollback/migration safety;
- verify both new and existing workflows.

For UX-heavy slices:

- inspect the real rendered experience;
- judge effort and clarity rather than merely code correctness;
- test with actual card/binder workflows;
- remove steps before adding explanatory text.

---

# The sequence I would execute from today

## Milestone A — Trustworthy baseline

Complete known integrity remediation.

**Done when:** no known silent material collection-integrity bugs remain.

## Milestone B — Physical truth model

Implement holding/copy + placement architecture and safe migration.

**Done when:** multiple physical copies can have distinct locations without corrupting existing collection semantics.

## Milestone C — Place

Implement containers, manual placement, unplaced state, and Scan-to-Place.

**Done when:** a real binder can be cataloged naturally.

## Milestone D — Verify

Implement sequential expected-vs-observed verification.

**Done when:** a real binder/container can be physically checked against the database.

## Milestone E — Reconcile

Implement discrepancy resolution.

**Done when:** Verify can actually restore consistency rather than merely report differences.

## Milestone F — Provenance

Persist what was physically verified, when, where, and with what uncertainty.

**Done when:** “verified” has defensible meaning.

## Milestone G — Collection Integrity dashboard

Expose identity, placement, verification freshness, discrepancies, and unresolved records.

**Done when:** the user can understand collection trustworthiness without understanding internal architecture.

## Milestone H — Migration wedge

Build one or two excellent incumbent import flows plus reconciliation.

**Done when:** a serious collector can realistically switch without manually rebuilding thousands of records.

## Milestone I — Future packaging decision

Only after the retention evidence exists, define any separate packaging or
entitlement boundary without compromising portability or the first meaningful
integrity loop.

**Done when:** a separately approved experiment has a clear value and policy
question. This milestone is not part of the free 1.0 release.

## Milestone J — Behavioral validation

Put it in the hands of serious collectors.

**Done when:** enough actual behavior exists to determine whether Verify is recurring.

## Milestone K — Decision gate

If repeated verification is validated:

**invest further.**

If verification is liked but not repeated:

**do not build binder-page CV yet. Reassess the recurring job.**

If repeated verification occurs and speed becomes the limiting factor:

**binder-page CV becomes the next major engineering priority.**

---

# Definition of strategic success

Do not define success as:

> “We shipped physical locations.”

Do not define success as:

> “Users think Verify is cool.”

Do not define success initially as a commercial conversion event.

The strongest evidence is:

> **A serious collector experiences real-world collection drift, voluntarily returns to CardScanner to Verify it, uses the product to reconcile reality with the database, and wants the application to continue doing that job.**

At that point the strategic thesis has moved from desk research into observed behavior.

Then the business becomes:

> **CardScanner is where collectors maintain the authoritative record of what they physically own.**

Scanning is how cards enter.

Placement connects them to reality.

Verification establishes evidence.

Reconciliation repairs drift.

Any future packaging decision follows the measured maintenance burden; it is
not part of the free 1.0 launch contract.

And everything else should become progressively easier to prioritize against that central purpose.
