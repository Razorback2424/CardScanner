# Pricing proxy

**Status:** implemented and tested locally on 2026-11-24 (stub upstream, in-memory store). Not deployed; the
Firestore store and the App Check path have not run yet.
Design authority: [launch slice](../docs/plans/shared_pricing_cache_plan.md#launch-slice--2026-11-24-current-build-plan).

A Cloud Functions 2nd-gen HTTPS function, `justtcgProxy`, that the app calls instead of JustTCG. It holds the
JustTCG key server-side, caches responses across users, de-duplicates concurrent misses, enforces global and
per-install quotas, and serves dated stale data only while the paid subscription is active.

## Layout

| File | Role |
| --- | --- |
| `src/proxy.ts` | Request handling: cache, leases, quota, stale fallback, batch splitting |
| `src/routes.ts` | Allow-list of the app's four JustTCG request shapes; cache keys |
| `src/config.ts` | Tier limits, TTLs, headroom, lane shares, per-install caps |
| `src/store.ts` | Coordination interface and shared quota arithmetic |
| `src/firestoreStore.ts` | Production store (transactions, TTL purge fields) |
| `src/memoryStore.ts` | Test store |
| `src/upstream.ts` | The only code that calls JustTCG |
| `src/index.ts` | Cloud Functions entry: App Check, install ID, wiring |

## Develop

Dependencies install on the external SSD; `node_modules` is a symlink to it.

```bash
npm install --cache "/Volumes/Keller Family Photos/TradingCardScannerDerivedData/pricing-proxy/npm-cache"
```

```bash
npm test
```

```bash
npm run typecheck
```

The Firestore emulator needs a Java runtime, which this Mac does not have yet. Until one is installed,
`FirestoreStore` is type-checked but has not run.

## App contract

The app calls `<base>/v1/justtcg/<path>`, where `<path>` is the JustTCG path, and sends these headers:

- `X-Firebase-AppCheck`: an App Attest token.
- `X-ScanStash-Install`: a random install ID of 16–64 characters.
- `X-ScanStash-Lane`: `interactive` or `background`.

Response bodies are JustTCG's own JSON with `_metadata` removed. Each response also carries:

| Header | Meaning |
| --- | --- |
| `X-ScanStash-Cache` | `hit`, `miss` or `stale`. Never record `stale` as a successful price check. |
| `X-ScanStash-Data-As-Of` | The oldest provider fetch time in the body. Delta-refresh cutoffs must not advance past it. |
| `X-ScanStash-Unavailable` | Why nothing was served: `quota`, `provider-rate-limit`, `circuit`, `provider`, `provider-auth`, `busy`, `subscription` or `install-limit`. |
| `Retry-After` | Sent on 429, and on 503 `busy`. |

## Launch-day deployment

These steps cost money and are deferred until launch preparation, before the final candidate is tested:

1. Upgrade the Firebase project to Blaze and set a budget alert.
2. Create Firestore in `us-central1`. This can't be changed later.
3. Add TTL policies on these fields: `pricingCache.purgeAt`, `pricingLeases.expiresAtTS`,
   `pricingInstalls.purgeAt` and `pricingQuota.purgeAt`.
4. Buy the JustTCG paid plan, then set the secrets:
   `firebase functions:secrets:set JUSTTCG_API_KEY` and `PRICING_INSTALL_SALT` (a random 32-byte value).
5. Set `JUSTTCG_TIER` if the plan isn't `starter`.
6. Register the iOS app for App Check with the App Attest provider, then enforce it. In the app's
   `Config/PokemonCatalogProduction.xcconfig`, set `PRICING_APP_CHECK_APP_ID` (the Firebase iOS app ID) and
   `PRICING_APP_CHECK_API_KEY` alongside `JUSTTCG_PROXY_BASE_URL`. The `Release` configuration uses
   [`TradingCardScanner-Release.entitlements`](../TradingCardScanner/TradingCardScanner-Release.entitlements)
   to select the production App Attest environment. Restrict the API key to the App Check API and the
   app's bundle ID.
7. Create the `pricingControl/main` document with `subscriptionActive: true`. If it's missing, the proxy serves
   nothing. Set it to `false` the day the subscription ends.
8. Deploy only this codebase: `firebase deploy --only functions:pricing,firestore:rules`. Catalog workflows
   deploy `--only hosting:production` and are unaffected.
9. Run J06 on a physical device with a fresh install and no key.
