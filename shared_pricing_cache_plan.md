# Shared Pricing Cache — Implementation Plan

**CardScanner · Pricing Infrastructure**
Status: Draft validated, three gates open · Date: 28 August 2026 · Verdict: Proceed after Gate A

A server-side cache so one CardScanner user's price observation can serve the next, without
moving card identity, the collection, or the portfolio ledger off the device.

---

## 1. Verdict

The architecture is sound and I would build it. The draft's boundary — CardScanner owns card
identity, the backend owns provider access and caching, the local ledger owns historical truth —
is the right one and should be frozen as written.

What does not survive validation is the draft's picture of the *current* system. Three of its
premises are contradicted by the code in this repository, and one of those is a commercial
blocker that has to be resolved before any Firebase resource is created. The engineering plan
below is largely the draft's; the sequencing changes because Phase 0 is now a purchasing and
licensing decision rather than a contract-freezing exercise.

Everything the draft cites about JustTCG's published limits checks out. Everything it assumes
about CardScanner's pricing stack does not.

---

## 2. What validation changed

### Contradicted by the codebase

#### BLOCKER — There is no app-owned JustTCG credential to move, remove, or rotate

The draft's Phase 9 deletes a shipped API key and rotates it. That asset does not exist. Every
JustTCG request today is authenticated with a key **the user pasted into Settings themselves**,
held in their own Keychain.

> `Services/PriceVendorCredentials.swift` · `Views/ScannerSettingsView.swift`
> ```
> SecureField("API key", text: $vendorKeyEntry)  →  Keychain
> kSecAttrService = "com.tradingcardscanner.pricing"
> kSecAttrAccount = "justtcg.api-key"
> ```

This inverts the project's economics. The draft protects one precious app subscription shared by
all users. Today there is no app subscription at all — there are as many quotas as there are
users who bothered to get a key, and the app spends each user's own allowance on that user's own
cards.

#### BLOCKER — The current model is JustTCG's free tier, which forbids shipping to users

The app is built to free-tier numbers throughout, and its own Settings copy tells the user so.

> `Services/JustTCGTransport.swift`
> ```
> static let dailyHardLimit         = 95   // documented free tier is 100/day
> static let backgroundDailyCeiling = 75
> static let batchSize              = 20   // free tier batch size
> ```

JustTCG's commercial-use page is unambiguous about what the free tier is for: *"The free tier is
for personal, non-commercial use: prototyping, learning, side projects you aren't shipping to
users."* And: *"If you're putting a product in front of other people, you need a paid plan,
regardless of how few requests it makes."*

A shared server-side cache makes this decisive rather than arguable. The moment CardScanner
fetches a price under its own key and serves it to a second user, it is a product in front of
other people running on CardScanner's subscription. That is squarely permitted on a paid plan —
*"Cache responses server-side and store price points to power your app's features"* — and
squarely not permitted on free. **Buying a paid plan is a prerequisite, not a detail.**

#### SCOPE — JustTCG is an opt-in fallback, not the pricing system

The draft never mentions TCGdex, TCGplayer, Cardmarket, or Scryfall. Those are where the great
majority of prices actually come from. JustTCG is consulted only for what the catalogs cannot
price, and the whole path is off by default behind `usesPriceFallback = false`.

> `Models/PriceRecord.swift` · `PriceSource`
> ```
> case tcgplayer      // TCGdex → Pokémon, primary
> case scryfall       // Magic, primary
> case cardmarket     // euro fallback where TCGdex has no TCGplayer figure
> case justTCG        // "consulted only for cards the catalog cannot price"
> case importedCSV
> ```

So the shared cache serves the long tail — Japanese sets, promos, tokens, art cards — plus sealed
products and graded slabs, which also route through JustTCG. That is a real and growing surface,
and it is the expensive one per request. But the draft's headline metric, "upstream amplification
falls dramatically," will be measured against a slice of traffic, not against all pricing. Size
the project's expected value accordingly, and do not let the cache's hit rate be read as a
statement about pricing overall.

#### DE-RISKS — Most of the backend already exists, working, on the client

This is the plan's best news and the draft understates it. The server is largely a port of
shipped, exercised code rather than a greenfield build.

| Draft concept | Already exists as | What transfers |
|---|---|---|
| Quota governor, 429 backoff, batching | `JustTCGTransport` | Tier ceilings, headroom reserve, serialized pacing, batch arithmetic |
| `provider_mappings` | `ProductIdentity` + `ProductIdentityStore` | Vendor card/variant IDs keyed per printing *and* finish; negative caching via `unmatchedAt`; `attemptVersion` is the draft's mappingVersion |
| Non-collection price cache | `QuoteCache` + `ReferenceQuote` | Cache semantics deliberately isolated from the ledger |
| `PriceResult` states | `PriceLookup` | The `price` / `unavailable(source)` split already refuses to collapse "no price" into nil |
| Provenance on a quote | `NormalizedPrice` | Carries `sourceVariantID`, `sourceUpdatedAt`, `fetchedAt` — two of the draft's three timestamps |

`ProductIdentity` also carries a hard-won lesson the server must inherit verbatim: its comments
record a bug where two subsystems shared one timestamp and 248 cards were locked out of identity
resolution permanently. **A field has exactly one writer.** Carry that rule into the Firestore
schema.

### Checked against the provider's own documentation

Every quantitative claim in the draft verified, with one exception.

| Draft claim | Result | Detail |
|---|---|---|
| Paid tiers may cache server-side and retain price points | Confirmed | Explicitly permitted, "to power your app's features" |
| Redistribution / substitute pricing API prohibited | Confirmed | Also prohibits sharing one key "across separate businesses or products" |
| Rate limits per tier | Confirmed | Starter 10k/mo · 1k/day · 50/min; Pro 50k · 5k · 100/min; Enterprise 500k · 50k · 500/min |
| Batch 100 on Starter/Pro, 200 on Enterprise | Confirmed | Free 20 · Starter/Pro 100 · Enterprise 200 |
| 429 → honor Retry-After, exponential backoff with jitter | Confirmed | "Start at ~1s and double up to a sensible cap (~30s)" |
| Batch lookup by variant ID | Confirmed | `variantId` is a valid per-item identifier |
| `variantId` is documented as *stable* | **Not found** | The cards reference does not describe stability at all |
| `/games.last_updated` undocumented → defer generation sync | Agreed | Keep deferred; TTL remains the correctness rule |

The unverified stability claim matters more than it looks. The draft treats mapping fingerprints
as defence in depth against a mapping someone corrects by hand. If provider variant UUIDs can
also churn on the provider's side, the fingerprint is the *primary* mechanism keeping a stale
cache entry from being served under a re-pointed identifier. Build it as load-bearing, and open a
question with JustTCG rather than assuming.

---

## 3. Gates before any code

Three decisions gate the project. None are engineering decisions, and all three are cheaper to
make now than after a Firestore database exists in the wrong region under the wrong licence.

### Gate A — Buy a JustTCG plan and decide the key model  *(blocking)*

Pick a tier and subscribe under CardScanner's own account. Starter's 1,000/day is the floor worth
considering; Professional's 5,000/day and 100/min is the realistic starting point once sealed and
graded traffic is included, and its 100-item batch is what makes the draft's 100-request endpoint
cap coherent.

Then decide what happens to the user-supplied key. The recommendation is to keep accepting it
during migration as the *only* path for users on old builds, and remove the field entirely at
Phase 9 — but that decision changes the migration's user-visible story, so make it explicitly.

- **Cost owner:** a recurring monthly bill that scales with adoption, against today's zero.
- **Ceiling check:** at Professional, 5,000 upstream requests/day × 100 items = 500,000 variant
  refreshes/day, shared. Model this against projected installs before committing to a tier.
- **Do not proceed to Gate B until the subscription is active**; the whole cache design is
  unlicensed without it.

### Gate B — Firestore region, chosen once  *(irreversible)*

A Firestore database's location cannot be changed after creation. Choose deliberately against
expected user distribution, availability requirements and pricing, and place Cloud Functions in
the same region. For a primarily US audience a US multi-region or single region is likely right —
but write the reasoning down before clicking, because this is the one setup step with no undo.

### Gate C — Privacy surface and App Store disclosure  *(needs review)*

The draft's §51 correctly keeps collection contents off the server. It does not account for what
*is* newly collected. Anonymous Firebase Auth mints a durable installation identifier, and the
backend will hold that UID against a stream of card lookups — which is a behavioural profile of
what a person is scanning, even without a name attached.

- Update the App Store privacy nutrition label before the first build that calls the backend.
- Set a retention policy for request logs and per-UID counters — days, not forever — and write it
  into the plan rather than discovering it at review.
- Decide whether telemetry keyed by UID is needed at all, or whether aggregate counters suffice
  for the metrics in §9.

---

## 4. Architecture

Unchanged from the draft, with the provider layer drawn honestly: the backend fronts JustTCG
only, and the catalog providers keep their existing direct paths.

```
Camera → CardScanner identification            (unchanged)
        ↓
PhysicalCardIdentity + finish/printing         (unchanged)
        ↓
ValuationPolicy                                condition × market × currency
        ↓
PriceRepository                                ← the new seam
        ↓
   ┌────┴─────────────────────────────┐
   │                                  │
Catalog path                    RemotePriceRepository
TCGdex · Scryfall · Cardmarket   JustTCG-backed lookups only
direct, unchanged, uncached            │
                                       ↓
                            getPrices() callable
                            Auth + App Check + validation + dedupe
                                       ↓
                            Mapping resolver → shared Firestore cache
                                       ↓
                        ┌──────────────┴──────────────┐
                   Fresh entry                  Stale or missing
                   return immediately           refresh lease → quota governor
                                                → JustTCG → validate → write
                                       ↓
                      PriceQuote → existing PriceRecord / ledger
                      (local historical truth, unchanged)
```

### The migration rule, kept verbatim

The server may bypass its own cache. **The phone may never bypass the server.** A client-side
fallback to JustTCG would put the credential back in the app and forfeit the entire point of the
backend. Cache-bypass is the kill switch; client fallback is not.

### Scope note on the catalog path

Do not extend the backend to TCGdex or Scryfall in this project. They are free, public, already
cached locally, and carry none of the quota pressure that motivates the shared cache. Routing
them through Firebase would add latency and cost to the majority of lookups in exchange for
nothing, and would make the backend a hard dependency of the app's primary pricing path. Leave
them alone.

---

## 5. Contracts

Freeze these five before writing the server. Each must be defined in terms of the identity types
CardScanner already has — a second identity system is the failure mode this section exists to
prevent.

### Reuse, do not reinvent

The canonical price key already exists and already has the right shape.
`PriceRecord.key(game:printingID:variantID:)` produces `game|printingID|variantID`, and its
comment states the rule the whole pricing layer is built on: a handle belongs to a printing *and*
a finish, because "one handle per card would reintroduce the finish-collapsing bug the pricing
layer exists to prevent."

The server's `normalizedPriceKey` is therefore that key, extended with valuation policy and a
schema version, then hashed:

```
normalizedPriceKey = SHA256(
    game | canonicalPrintingID | variantID | language
    | valuationCondition | market | currency
    | keySchemaVersion
)
```

Never key on names. Document, in the Phase 0 commit, exactly which existing CardScanner type
supplies `canonicalPrintingID` — and add a test that fails if a second source of printing
identity appears.

### The five types

- **PhysicalCardIdentity** — game, canonical printing ID, finish, language. Condition is *not*
  part of it. The scanner does not determine that a card is Near Mint; the app assumes it.
- **ValuationPolicy** — condition, market, currency. v1 is Near Mint / US / USD, held explicitly
  so LP, graded, Japanese-market and multi-currency remain reachable later without touching
  identity.
- **PriceRequest** — request item ID, identity, policy. Deliberately no `provider` field;
  provider selection is a backend concern.
- **PriceQuote** — amount, currency, and full provenance: `sourceUpdatedAt`, `providerFetchedAt`,
  `servedAt`, freshness, opaque observation ID. Keep all three timestamps separate; they answer
  three different questions and `NormalizedPrice` already keeps two of them apart correctly.
- **PriceResult** — `priced`, `noPrice`, `mappingUnavailable`, `temporarilyUnavailable`,
  `invalidRequest`; a priced result additionally carries `freshCache`, `freshlyRefreshed`, or
  `staleFallback`.

### The repository seam

Plural from day one — `prices(for: [PriceRequest])`, never a singular variant. A scan passes one
request; a portfolio refresh passes hundreds; chunking to the tier's batch limit happens inside
`RemotePriceRepository` and is invisible to everything above it.

Make the chunk size tier-configured rather than a constant. It is 20 on free, 100 on Starter and
Professional, 200 on Enterprise, and `JustTCGTransport.batchSize` is hardcoded to 20 today.

---

## 6. Ledger safety rails

This is the section where a backend mistake becomes a portfolio mistake. The draft identified the
risk correctly; the codebase makes it precise, because the evidence model it must not corrupt
already exists and is already documented.

`PriceCheckDay` exists solely to record that the app *successfully* asked about one instrument on
one portfolio day. Its comment explains why it cannot be merged with a last-checked timestamp:

> `Models/PriceCheckDay.swift`
> "A field that records both success and failure cannot answer the question: a 3 PM failure would
> report as refreshed and simultaneously erase the proof of a good 9 AM check."

`PriceRecord` keeps the same split — `lastSuccessfulCheckAt` is separate from when the app last
asked. Coverage strings like "1,276 of 1,284 repriced today · 8 carried forward" are computed
from that evidence.

Therefore, mechanically:

| Result | Writes PriceCheckDay | Sets lastSuccessfulCheckAt | Updates displayed price |
|---|---|---|---|
| `priced · freshCache` | Yes | Yes | Yes |
| `priced · freshlyRefreshed` | Yes | Yes | Yes |
| `priced · staleFallback` | **No** | **No** | Keep existing value, show its real age |
| `noPrice` | Yes | Yes | Records a genuine absence |
| `temporarilyUnavailable` | No | No | Preserve previous value |
| `mappingUnavailable` | No | No | Preserve previous value |

A fresh cache hit is a successful check — the observation is current and the app verified it. A
stale fallback is not, and must never be allowed to look like one. That single row is the
difference between an honest coverage number and a portfolio that quietly claims to have been
repriced.

### The six rules, as acceptance criteria

- **R1** — A backend failure may make a price stale. It **may not** make CardScanner identify a
  different card.
- **R2** — A provider failure may preserve an old price. It **may not** replace a known price
  with zero or nil.
- **R3** — A stale fallback may preserve value. It **may not** masquerade as a successful fresh
  check.
- **R4** — A bad provider mapping may yield no new price. It **may not** silently cache a
  different card's price.
- **R5** — A quota failure may defer a refresh. It **may not** trigger uncontrolled provider
  fan-out.
- **R6** — A cache failure may force server-side bypass. It **may not** put the provider secret
  back in the app.

Each of these gets a named test in the matrix at §8. A rule with no test is a wish.

---

## 7. Server design

Adopted from the draft essentially unchanged — it is the strongest part of the document. Notes
below are corrections and tightenings only.

### Endpoint and limits

One callable, `getPrices([PriceRequest])`, with `enforceAppCheck: true`. It authenticates,
verifies App Check, validates, deduplicates within the call, resolves mappings, partitions
fresh/stale/missing, returns fresh hits immediately, coordinates refreshes under lease and quota,
validates provider responses, writes cache, and returns results in the caller's original request
order.

Cap unique requests per call at the tier's batch limit — 100 on Starter/Professional — so the
worst case of an all-miss call is one upstream batch. Enforce serialized size, field lengths,
enum validity, and duplicate amplification separately. All limits live in configuration, not
constants.

The client never reads Firestore. Security rules on the pricing collections deny client read and
write outright; the function reaches Firestore through the Admin SDK, which bypasses those rules
by design.

### Collections and versioning

Four collections: `provider_mappings`, `price_cache`, `provider_control`, `provider_budget`.
Resist adding telemetry collections early; Firestore is not the analytics warehouse.

A cache entry is valid only if *both* version boundaries hold:

```
cache.mappingFingerprint      == current mapping fingerprint
cache.providerStrategyVersion == active strategy version
```

The first invalidates a corrected mapping immediately. The second makes a future provider
migration self-invalidating, so an old JustTCG observation can never masquerade as one produced
by a new pricing strategy. Given that provider variant ID stability is *not* documented, treat
the fingerprint as primary protection, not a backstop.

Carry over the one-writer discipline from `ProductIdentity`: every field in these documents has
exactly one writer, named in a comment. Two subsystems sharing one timestamp is how 248 cards
were once locked out of identity resolution permanently.

### TTL and negative caching

Positive TTL 60 minutes, negative TTL 15 minutes, both configurable. The asymmetry is right: a
new release can go from no price at 10:00 to a real price at 10:45, and a six-hour negative cache
would hide that all morning.

Cache a genuine `noPrice`. Never negative-cache a provider error — that is
`temporarilyUnavailable`, which caches nothing and preserves whatever good value already exists.

JustTCG's own guidance puts price processing at roughly 6–7 hours per game, so 60 minutes is
conservative by design. Leave it conservative until telemetry justifies otherwise; the first hour
of caching captures nearly all of the benefit.

### Refresh leases

Acquire the lease in a Firestore transaction; call the provider strictly outside it. Transaction
functions can re-run on contention, and a network call inside one can therefore fire more than
once.

Before a refreshed result may overwrite the cache, re-verify all four: lease owner is still this
refresh, mapping fingerprint is unchanged, the returned variant is the variant requested,
strategy version is unchanged. Any mismatch discards the result rather than writing it.

State the guarantee honestly in the code comment: **at most one active refresh owner under normal
operation, with best-effort suppression of duplicates.** Not exactly-once. A crash between a
successful provider call and the Firestore write will produce a second upstream request, and that
is acceptable.

Non-owners with a previous value get the stale-good observation immediately. Non-owners with no
previous value get a short bounded wait and re-read, then `temporarilyUnavailable`. Never start a
second uncontrolled provider request, and never block scanner UX to shave seconds off freshness.

### Quota governor and circuit breaker

Budget state lives in Firestore, transactionally, because Cloud Functions 2nd gen runs many
requests per instance across many instances — an in-process counter is not a global quota.
Reserve before the call; roll minute, day and billing windows; reject when exhausted or when the
provider is blocked.

Hold an internal ceiling below the provider's published limit — 80% is a sound default, so
Starter permits 40/min against a documented 50 — leaving headroom for retries, probes and timing
error. Port the tier table and headroom logic from `JustTCGTransport` rather than rewriting it.

Circuit states: `healthy`, `temporarilyBlocked`, `probing`. On 429, honor `Retry-After` and set
`blockedUntil`. On repeated 5xx or timeouts, open and serve stale-good. On expiry, permit a
single small probe. Capture `apiRequestsRemaining` from response metadata as advisory telemetry —
never as the quota system itself.

App Check is not rate limiting. Anonymous Auth supplies a per-installation actor for throttling;
the two are complementary. Start with configurable per-UID ceilings on calls per minute and on
requests that actually consume upstream quota, and tune from telemetry.

### Failing closed

If Firestore is unreachable inside a working function, do not start upstream work. Coordination
is what keeps quota bounded; without it, every instance would bypass every limit at once and
drain the subscription. Return `temporarilyUnavailable` and let local values carry the
experience.

If the callable itself is down: scanning works, collection additions work, existing local prices
display with their real age, portfolio refresh preserves values and generates no false success
evidence. Card identification is never affected — that is R1.

---

## 8. Phases

Each phase advances only when its gate is met — not when a week has passed.

**Phase 0 — Commercial gates and frozen contracts.**
Clear Gates A, B and C. Freeze the five types. Document which existing type supplies the
canonical printing ID.
*Gate:* Paid JustTCG subscription active. Region decided and written down. Privacy disclosure
drafted. Existing scanner tests pass unchanged with the new types present.

**Phase 1 — Repository seam, no behaviour change.**
Wrap today's pricing path behind `PriceRepository`. No Firebase. No caching change. Nothing
user-visible. The safest possible first commit.
*Gate:* Price, scanner and portfolio behaviour byte-identical to today across the existing suite.

**Phase 2 — Firebase foundation.**
Project, Firestore in the chosen region, Functions 2nd gen, Secret Manager, anonymous Auth, App
Check with App Attest and a debug provider for simulator. No production traffic.
*Gate:* Emulator and deployed callable both work. Authenticated test client succeeds;
unauthenticated and bad-App-Check clients are rejected. iOS can read neither the secret nor the
pricing collections.

**Phase 3 — Server proxy, no cache.**
Deliberately boring, and the most important phase in the plan. It answers one question in
isolation: does moving the provider boundary to the server change pricing correctness?
*Gate:* For a fixture set, old and new paths agree exactly on canonical printing, provider card
UUID, provider variant UUID, condition, printing, language, price, and provider `lastUpdated`.
Any disagreement blocks Phase 4.

**Phase 4 — Read-through cache.**
60-minute positive TTL, 15-minute negative TTL, mapping fingerprint and strategy version
validation.
*Gate:* A fresh hit never calls JustTCG. A stale entry does. A fingerprint mismatch never serves.
`noPrice` negative-caches correctly. A provider failure never overwrites a good price *(R2)*.

**Phase 5 — Duplicate suppression.**
Refresh leases, tested under 50 simultaneous misses on one key.
*Gate:* Normal case: one owner, one upstream batch, 49 suppressed. Rare duplicates after crash or
timeout are acceptable. An old refresh overwriting a newer mapping or result is never acceptable
*(R4)*.

**Phase 6 — Abuse and quota controls.**
Per-UID throttling, global budgets, 429 backoff, circuit breaker, request-size enforcement,
provider headroom. Simulate 429s, outages, and exhausted daily and monthly budgets.
*Gate:* CardScanner cannot exceed the configured upstream ceiling merely because Cloud Functions
scaled horizontally *(R5)*.

**Phase 7 — Internal shadow comparison.**
100% shadow on internal and TestFlight builds. Log discrepancies by identity, provider IDs,
price, condition, printing, language and `lastUpdated`. The shadow result never mutates the
collection or the portfolio.
*Gate:* Mapping mismatch rate essentially zero. Price disagreements explained, not tolerated.

**Phase 8 — Sampled production rollout.**
5% → 20% → 50% → 100%, inspecting crash-free behaviour, cache hit rate, latency, price and
mapping mismatch rates, JustTCG consumption, stale fallback rate and backend errors at each step.
*Gate:* Advance because the prior cohort is correct, never because time passed.

**Phase 9 — Retire the client credential.**
Adjusted from the draft, because the credential is the user's. Remove the Settings API-key field
and `PriceVendorCredentials`, remove direct client provider requests, and delete any stored user
keys from the Keychain on upgrade. There is no app key to rotate — but do confirm no build still
reads one.
*Gate:* All JustTCG traffic originates from the server. No shipped build contains a provider
request path. Users who had supplied their own key have it removed cleanly and are not left with
a dead settings toggle.

**Phase 10 — Optimize only from telemetry.**
If a 60-minute TTL yields a high hit rate and modest API usage, stop — build nothing clever.
Longer TTLs, better batching, Cloud Tasks, Redis, and `updated_after` generation sync are each
unlocked by a specific measurement, not by anticipation.
*Gate:* No speculative infrastructure ships without a metric that demanded it.

### Test matrix

Repeatable coverage required before production, grouped as the draft has it: identity and mapping
(including a mapping corrected mid-refresh), cache states (fresh, expired, missing, negative,
expired negative, stale-good, schema and strategy mismatch), concurrency (two and fifty
simultaneous misses, lease expiry, owner crash, late owner return), provider failure (timeout,
429, 500, malformed, wrong variant, missing variant, partial batch), quota (each window
exhausted, per-UID exhausted, circuit open, probe succeeds, probe fails), and client behaviour
(backend offline, timeout, local value present or absent, scan, Price Check, portfolio refresh,
relaunch).

Plus one named test per safety rail R1–R6. The ledger cases are the ones to write first, because
they are the ones whose failure is silent.

---

## 9. Measurement

Five numbers decide whether this was worth building.

- **Cache hit rate** — fresh hits over total price requests *on the JustTCG path*. Report it
  scoped, so it is never mistaken for a claim about all pricing.
- **Upstream amplification** — JustTCG requests over CardScanner price requests. This is the
  number the project exists to drive down.
- **Latency** — cache-hit and upstream-refresh measured separately, or the average hides both.
- **Stale fallback rate** — a sustained rise means provider or backend health, not a
  cache-tuning problem.
- **Mapping mismatch rate** — should be indistinguishable from zero. Anything else is R4 failing.

Instrument from day one as structured counters, not verbose logs: requests, keys, fresh and stale
hits, misses, negative hits, upstream batches and variants, 429s, 5xx, timeouts, mapping failures
and mismatches, leases won and contended, quota reserved and remaining, cache age, and result
counts by status. Respect the Gate C retention policy.

### Costs to track from the start

| Line | Today | After |
|---|---|---|
| JustTCG subscription | $0 — users' own free keys | Recurring, tier-dependent, scales with installs |
| Cloud Functions invocations | $0 | One per price call, plus retries |
| Firestore reads/writes | $0 | ≥1 read per key; writes on every refresh and lease |
| Egress and Secret Manager | $0 | Small but non-zero |

Lease acquisition and budget reservation are transactional writes on hot documents. At
CardScanner's scale a Firestore coordinator is adequate — but watch write costs and contention on
`provider_budget` specifically, since every upstream request touches it.

---

## 10. Not in this project

Kept from the draft, and worth defending when the temptation arrives: Firebase-hosted
collections, cloud accounts and signup UX, cross-device sync, a central portfolio ledger, a
historical market warehouse, artwork caching, Redis, Cloud Tasks for interactive scans,
generation logic and `updated_after` sync, predictive warming, scheduled full-database refresh,
multi-provider blending, condition grading, graded-card pricing beyond today's behaviour, and
international market pricing.

Also explicitly out: routing TCGdex, Scryfall or Cardmarket through the backend. See §4.

The v1 system remains small — one callable, four collections, one provider adapter, one mapping
resolver, one cache coordinator, one quota governor, one Swift repository. That smallness is what
makes it a narrow infrastructure service rather than a rebuild of CardScanner, and it is worth
protecting.

---

## 11. Open questions

- **Is `variantId` stable across provider-side catalog revisions?** Ask JustTCG directly. The
  answer determines whether mapping fingerprints are primary protection or defence in depth.
- **Which tier?** Starter and Professional differ by 5× on daily quota and 2× on per-minute.
  Model against projected installs before committing, and confirm whether sealed and graded
  lookups share the same quota pool.
- **What happens to users on old builds** once the server path is live and their own key still
  works? Decide whether they are migrated, cut over, or left until they update.
- **Does the app still work for a user who never had a key?** Today the fallback is simply off
  for them. After the migration it is on for everyone at CardScanner's expense — which is a
  product improvement and a cost multiplier at the same time. Confirm that is intended.
- **Is `/games.last_updated` supported in production responses?** Only relevant at Phase 10, but
  worth asking in the same conversation as the first question.

---

*Validated against repository HEAD and JustTCG documentation, 28 August 2026.*
