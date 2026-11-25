import type { ProxyConfig } from "./config.ts";
import { classify, itemKey, requestKey } from "./routes.ts";
import type { BatchItem, QueryPair, Route } from "./routes.ts";
import type { CacheEntry, CachedItem, CachedResponse, Control, Lane, Store } from "./store.ts";
import type { Upstream, UpstreamRequest } from "./upstream.ts";
import { retryAfterMs } from "./upstream.ts";

// Core request handling, independent of Cloud Functions so it can be tested
// against MemoryStore and a stub upstream.
//
// Response contract with the app (JustTCGTransport):
// - Bodies are JustTCG's own JSON with `_metadata` removed: that block reports
//   the shared account's usage and would throttle every install's local ledger.
// - X-ScanStash-Cache: hit | miss | stale. `stale` means at least part of the
//   body is past its TTL; the app must not record it as a successful check.
// - X-ScanStash-Data-As-Of: the oldest provider fetch time in the body. Delta
//   refresh cutoffs must not advance past it.
// - 429 + Retry-After when no usable data exists because of quota or a provider
//   rate limit; 503 + X-ScanStash-Unavailable for provider, busy and
//   subscription outages.

export interface ProxyRequest {
  readonly method: string;
  readonly path: string;
  readonly query: QueryPair[];
  readonly body: unknown;
  /** Hashed per-install identifier; null only in tests that skip throttling. */
  readonly installHash: string | null;
  readonly lane: Lane;
}

export interface ProxyResponse {
  readonly status: number;
  readonly body: string;
  readonly headers: Record<string, string>;
}

export interface ProxyDeps {
  readonly config: ProxyConfig;
  readonly store: Store;
  readonly upstream: Upstream;
  now(): number;
  sleep(ms: number): Promise<void>;
  newOwner(): string;
}

type CacheState = "hit" | "miss" | "stale";

type FetchOutcome =
  | { readonly kind: "ok"; readonly status: number; readonly body: string; readonly link: string | null }
  /** A provider 4xx other than 404: the request itself was rejected. Never cached. */
  | { readonly kind: "client-error"; readonly status: number; readonly body: string }
  | { readonly kind: "limited"; readonly retryAt: number; readonly reason: "quota" | "provider-rate-limit" | "circuit" }
  | { readonly kind: "failed"; readonly reason: "provider" | "provider-auth" };

const JSON_TYPE = "application/json; charset=utf-8";

function json(status: number, value: unknown, extra: Record<string, string> = {}): ProxyResponse {
  return { status, body: JSON.stringify(value), headers: { "Content-Type": JSON_TYPE, "Cache-Control": "no-store", ...extra } };
}

function retryHeader(retryAt: number, now: number): string {
  return String(Math.max(1, Math.ceil((retryAt - now) / 1000)));
}

function limitedResponse(retryAt: number, now: number, reason: string): ProxyResponse {
  return json(429, { error: "Pricing is temporarily rate limited." }, { "Retry-After": retryHeader(retryAt, now), "X-ScanStash-Unavailable": reason });
}

function unavailable(reason: string, now: number, retryAt?: number): ProxyResponse {
  const headers: Record<string, string> = { "X-ScanStash-Unavailable": reason };
  if (retryAt !== undefined) headers["Retry-After"] = retryHeader(retryAt, now);
  return json(503, { error: "Pricing is temporarily unavailable." }, headers);
}

/** Removes the provider's account-wide `_metadata`; leaves non-JSON bodies alone. */
export function sanitize(body: string): string {
  try {
    const parsed: unknown = JSON.parse(body);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed) && "_metadata" in parsed) {
      const copy = { ...(parsed as Record<string, unknown>) };
      delete copy._metadata;
      return JSON.stringify(copy);
    }
  } catch {
    // Not JSON; pass through unchanged.
  }
  return body;
}

function dataArray(body: string): unknown[] | null {
  try {
    const parsed: unknown = JSON.parse(body);
    if (parsed && typeof parsed === "object" && Array.isArray((parsed as { data?: unknown }).data)) {
      return (parsed as { data: unknown[] }).data;
    }
  } catch {
    // Fall through.
  }
  return null;
}

class Handler {
  private readonly deps: ProxyDeps;
  private readonly control: Control;
  private readonly lane: Lane;
  private readonly owner: string;

  constructor(deps: ProxyDeps, control: Control, lane: Lane) {
    this.deps = deps;
    this.control = control;
    this.lane = lane;
    this.owner = deps.newOwner();
  }

  private get config(): ProxyConfig {
    return this.deps.config;
  }

  private now(): number {
    return this.deps.now();
  }

  private fresh(entry: CacheEntry | undefined): boolean {
    return entry !== undefined && entry.expiresAt > this.now();
  }

  /** Stored data may be served past its TTL only while the paid licence is active. */
  private staleUsable(entry: CacheEntry | undefined): boolean {
    return entry !== undefined && this.control.subscriptionActive && this.now() - entry.expiresAt < this.config.staleRetentionMs;
  }

  private ttl(kind: "sets" | "quote" | "history", negative: boolean): number {
    return negative ? this.config.ttlMs.negative : this.config.ttlMs[kind];
  }

  private async count(counter: string): Promise<void> {
    await this.deps.store.count(counter);
  }

  private async fetchUpstream(request: UpstreamRequest): Promise<FetchOutcome> {
    const store = this.deps.store;
    const now = this.now();
    if (this.control.blockedUntil > now) {
      await this.count("circuit_open");
      return { kind: "limited", retryAt: this.control.blockedUntil, reason: "circuit" };
    }
    const tier = this.config.tier;
    const decision = await store.reserveQuota({
      lane: this.lane,
      now,
      limits: {
        perMinute: Math.floor(tier.perMinute * this.config.headroom),
        perDay: Math.floor(tier.perDay * this.config.headroom),
        perMonth: Math.floor(tier.perMonth * this.config.headroom),
      },
      backgroundShare: this.config.backgroundShare,
    });
    if (!decision.granted) {
      await this.count(`quota_denied_${decision.window}`);
      return { kind: "limited", retryAt: decision.retryAt, reason: "quota" };
    }
    await this.count("upstream_request");
    const result = await this.deps.upstream.send(request);
    if (result.kind === "network-error" || result.status >= 500) {
      await this.count(result.kind === "network-error" ? "upstream_network" : "upstream_5xx");
      await this.failure();
      return { kind: "failed", reason: "provider" };
    }
    if (result.status === 429) {
      await this.count("upstream_429");
      const retryAt = retryAfterMs(result.retryAfter, this.now(), 60_000);
      await store.openCircuit(retryAt);
      return { kind: "limited", retryAt, reason: "provider-rate-limit" };
    }
    if (result.status === 401 || result.status === 403) {
      // Our key is missing, expired or revoked. Never surface this as the
      // user's problem: the app no longer has a key to fix.
      await this.count("upstream_auth");
      await this.failure();
      return { kind: "failed", reason: "provider-auth" };
    }
    await store.recordUpstreamSuccess();
    if (result.status >= 400 && result.status !== 404) {
      return { kind: "client-error", status: result.status, body: sanitize(result.body) };
    }
    return { kind: "ok", status: result.status, body: sanitize(result.body), link: result.link };
  }

  private async failure(): Promise<void> {
    const failures = await this.deps.store.recordUpstreamFailure();
    if (failures >= this.config.circuitFailureThreshold) {
      await this.deps.store.openCircuit(this.now() + this.config.circuitOpenMs);
    }
  }

  /** Polls for another caller's in-flight refresh; returns whichever keys became fresh. */
  private async waitForFresh(keys: string[]): Promise<Map<string, CacheEntry>> {
    const found = new Map<string, CacheEntry>();
    const deadline = this.now() + this.config.leaseWaitMs;
    let pending = keys;
    while (pending.length > 0 && this.now() < deadline) {
      await this.deps.sleep(this.config.leasePollMs);
      const entries = await this.deps.store.getEntries(pending);
      for (const [key, entry] of entries) if (this.fresh(entry)) found.set(key, entry);
      pending = pending.filter((key) => !found.has(key));
    }
    return found;
  }

  private respond(entry: CachedResponse, state: CacheState): ProxyResponse {
    const asOf = new Date(entry.fetchedAt).toISOString();
    const headers: Record<string, string> = {
      "Content-Type": JSON_TYPE,
      "Cache-Control": "no-store",
      "X-ScanStash-Cache": state,
      "X-ScanStash-Fetched-At": asOf,
      "X-ScanStash-Data-As-Of": asOf,
    };
    if (entry.link) headers.Link = entry.link;
    return { status: entry.status, body: entry.body, headers };
  }

  async get(route: Extract<Route, { kind: "get" }>): Promise<ProxyResponse> {
    const store = this.deps.store;
    const key = requestKey(route);
    const existing = (await store.getEntries([key])).get(key) as CachedResponse | undefined;
    if (existing && this.fresh(existing)) {
      await this.count("hit");
      return this.respond(existing, "hit");
    }

    if (!(await store.acquireLease(key, this.owner, this.now(), this.config.leaseMs))) {
      if (existing && this.staleUsable(existing)) {
        await this.count("stale");
        return this.respond(existing, "stale");
      }
      const waited = (await this.waitForFresh([key])).get(key) as CachedResponse | undefined;
      if (waited) {
        await this.count("hit");
        return this.respond(waited, "hit");
      }
      await this.count("busy");
      return unavailable("busy", this.now(), this.now() + 2_000);
    }

    try {
      const outcome = await this.fetchUpstream({ method: "GET", path: route.path, query: route.query });
      if (outcome.kind === "ok") {
        const fetchedAt = this.now();
        const data = dataArray(outcome.body);
        const negative = outcome.status === 404 || (data !== null && data.length === 0);
        const entry: CachedResponse = {
          kind: "response",
          status: outcome.status,
          body: outcome.body,
          link: outcome.link,
          fetchedAt,
          expiresAt: fetchedAt + this.ttl(route.ttl, negative),
          negative,
        };
        if (Buffer.byteLength(entry.body) <= this.config.maxCachedBytes) {
          await store.putEntries(new Map([[key, entry]]), this.config.staleRetentionMs);
        } else {
          await this.count("uncacheable_size");
        }
        await this.count("miss");
        return this.respond(entry, "miss");
      }
      if (outcome.kind === "client-error") {
        return { status: outcome.status, body: outcome.body, headers: { "Content-Type": JSON_TYPE, "Cache-Control": "no-store" } };
      }
      if (existing && this.staleUsable(existing)) {
        await this.count("stale");
        return this.respond(existing, "stale");
      }
      if (outcome.kind === "limited") return limitedResponse(outcome.retryAt, this.now(), outcome.reason);
      return unavailable(outcome.reason, this.now());
    } finally {
      await store.releaseLease(key, this.owner);
    }
  }

  async batch(route: Extract<Route, { kind: "batch" }>): Promise<ProxyResponse> {
    const store = this.deps.store;
    const keyed = route.items.map((item) => ({ item, key: itemKey(item, route.includePriceHistory) }));
    const existing = await store.getEntries(keyed.map((k) => k.key));
    const served = new Map<string, { entry: CachedItem; state: CacheState }>();
    const needed: typeof keyed = [];
    for (const k of keyed) {
      const entry = existing.get(k.key) as CachedItem | undefined;
      if (entry && this.fresh(entry)) served.set(k.key, { entry, state: "hit" });
      else needed.push(k);
    }

    const owned: typeof keyed = [];
    const others: typeof keyed = [];
    for (const k of needed) {
      if (await store.acquireLease(k.key, this.owner, this.now(), this.config.leaseMs)) owned.push(k);
      else others.push(k);
    }

    let failure: FetchOutcome | null = null;
    // Cards the provider returned that could not be tied to a requested item.
    // They are passed through, and their presence forbids negative caching.
    let extras: unknown[] = [];
    try {
      const query: QueryPair[] = [{ name: "include_price_history", value: route.includePriceHistory ? "true" : "false" }];
      // One upstream call per plan-sized chunk; each costs one request of quota.
      for (let start = 0; start < owned.length && failure === null; start += this.config.tier.batchSize) {
        const chunk = owned.slice(start, start + this.config.tier.batchSize);
        // Always fetch full state; `updated_after` is applied to cached data on the way out.
        const outcome = await this.fetchUpstream({
          method: "POST",
          path: "v1/cards",
          query,
          body: chunk.map(({ item }) => ({ [item.key]: item.value })),
        });
        const cards = outcome.kind === "ok" && outcome.status < 300 ? dataArray(outcome.body) : null;
        if (cards !== null) {
          const fetchedAt = this.now();
          const matched = new Map<string, unknown[]>();
          const correlated = new Set<unknown>();
          for (const { item, key } of chunk) {
            const hits = cards.filter((card) => matches(card, item));
            hits.forEach((card) => correlated.add(card));
            matched.set(key, hits);
          }
          const chunkExtras = cards.filter((card) => !correlated.has(card));
          extras = extras.concat(chunkExtras);
          const writes = new Map<string, CacheEntry>();
          for (const { key } of chunk) {
            const hits = matched.get(key) ?? [];
            const negative = hits.length === 0;
            const entry: CachedItem = {
              kind: "item",
              cards: hits,
              fetchedAt,
              expiresAt: fetchedAt + this.ttl(route.includePriceHistory ? "history" : "quote", negative),
              negative,
            };
            served.set(key, { entry, state: "miss" });
            const cacheable = !(negative && chunkExtras.length > 0) && Buffer.byteLength(JSON.stringify(entry.cards)) <= this.config.maxCachedBytes;
            if (cacheable) writes.set(key, entry);
          }
          if (writes.size > 0) await store.putEntries(writes, this.config.staleRetentionMs);
          await this.count("miss");
        } else {
          failure = outcome.kind === "client-error" ? outcome : outcome.kind === "ok" ? { kind: "failed", reason: "provider" } : outcome;
          if (outcome.kind === "client-error") {
            return { status: outcome.status, body: outcome.body, headers: { "Content-Type": JSON_TYPE, "Cache-Control": "no-store" } };
          }
          // This chunk and any not yet attempted fall back to stale data.
          for (const k of owned.slice(start)) {
            const entry = existing.get(k.key) as CachedItem | undefined;
            if (entry && this.staleUsable(entry)) served.set(k.key, { entry, state: "stale" });
          }
        }
      }
    } finally {
      await Promise.all(owned.map((k) => store.releaseLease(k.key, this.owner)));
    }

    if (others.length > 0) {
      const waited = await this.waitForFresh(others.map((k) => k.key));
      for (const k of others) {
        const fresh = waited.get(k.key) as CachedItem | undefined;
        const entry = existing.get(k.key) as CachedItem | undefined;
        if (fresh) served.set(k.key, { entry: fresh, state: "hit" });
        else if (entry && this.staleUsable(entry)) served.set(k.key, { entry, state: "stale" });
      }
    }

    // Omitting an item would read as "not found" to the app, so an incomplete
    // answer fails the whole batch instead.
    if (keyed.some((k) => !served.has(k.key))) {
      if (failure && failure.kind === "limited") return limitedResponse(failure.retryAt, this.now(), failure.reason);
      if (failure && failure.kind === "failed") return unavailable(failure.reason, this.now());
      await this.count("busy");
      return unavailable("busy", this.now(), this.now() + 2_000);
    }

    const states = [...served.values()];
    const state: CacheState = states.some((s) => s.state === "stale") ? "stale" : states.some((s) => s.state === "miss") ? "miss" : "hit";
    await this.count(state === "hit" ? "hit" : state);
    const asOf = Math.min(...states.map((s) => s.entry.fetchedAt));

    const seen = new Set<string>();
    const data: unknown[] = [];
    const add = (card: unknown) => {
      const filtered = route.updatedAfter === null ? card : filterUpdatedAfter(card, route.updatedAfter);
      if (filtered === null) return;
      const identity = cardIdentity(filtered);
      if (seen.has(identity)) return;
      seen.add(identity);
      data.push(filtered);
    };
    for (const k of keyed) for (const card of served.get(k.key)!.entry.cards) add(card);
    for (const card of extras) add(card);

    const iso = new Date(asOf).toISOString();
    return {
      status: 200,
      body: JSON.stringify({ data }),
      headers: {
        "Content-Type": JSON_TYPE,
        "Cache-Control": "no-store",
        "X-ScanStash-Cache": state,
        "X-ScanStash-Fetched-At": iso,
        "X-ScanStash-Data-As-Of": iso,
      },
    };
  }
}

function field(record: Record<string, unknown>, ...names: string[]): string | null {
  for (const name of names) {
    const value = record[name];
    if (typeof value === "string" || typeof value === "number") return String(value);
  }
  return null;
}

function variants(card: Record<string, unknown>): Record<string, unknown>[] {
  return Array.isArray(card.variants) ? (card.variants.filter((v) => v && typeof v === "object") as Record<string, unknown>[]) : [];
}

/** Whether a returned card answers one batch item, by the identifier the item used. */
export function matches(card: unknown, item: BatchItem): boolean {
  if (!card || typeof card !== "object") return false;
  const c = card as Record<string, unknown>;
  switch (item.key) {
    case "variantId":
      return variants(c).some((v) => field(v, "uuid") === item.value || field(v, "id") === item.value);
    case "tcgplayerSkuId":
      return variants(c).some((v) => field(v, "tcgplayerSkuId", "tcgplayer_sku_id") === item.value);
    case "tcgplayerId":
      return field(c, "tcgplayerId", "tcgplayer_id") === item.value;
    case "mtgjsonId":
      return field(c, "mtgjsonId", "mtgjson_id") === item.value;
    case "scryfallId":
      return field(c, "scryfallId", "scryfall_id") === item.value;
    case "cardId":
      return field(c, "uuid") === item.value || field(c, "id") === item.value;
    default:
      return false;
  }
}

function cardIdentity(card: unknown): string {
  if (card && typeof card === "object") {
    const c = card as Record<string, unknown>;
    const id = field(c, "uuid", "id");
    if (id) return `id:${id}`;
  }
  return `json:${JSON.stringify(card)}`;
}

/**
 * Mirrors the provider's `updated_after`: keeps variants updated after the
 * cutoff (and variants without a timestamp, conservatively). Returns null when
 * nothing in the card qualifies.
 */
export function filterUpdatedAfter(card: unknown, cutoffSeconds: number): unknown | null {
  if (!card || typeof card !== "object") return card;
  const c = card as Record<string, unknown>;
  if (!Array.isArray(c.variants)) return card;
  const kept = variants(c).filter((v) => {
    const raw = v.lastUpdated;
    if (typeof raw !== "number") return true;
    const seconds = raw > 1e12 ? raw / 1000 : raw;
    return seconds > cutoffSeconds;
  });
  if (kept.length === 0) return null;
  return { ...c, variants: kept };
}

export async function handle(request: ProxyRequest, deps: ProxyDeps): Promise<ProxyResponse> {
  const classified = classify(request.method, request.path, request.query, request.body, deps.config);
  if (!classified.ok) return json(classified.status, { error: classified.reason });

  const control = await deps.store.getControl();
  if (!control.subscriptionActive) {
    await deps.store.count("subscription_off");
    return unavailable("subscription", deps.now());
  }

  if (request.installHash !== null) {
    const { perMinute, perDay } = deps.config.perInstall;
    if (!(await deps.store.admitInstall(request.installHash, deps.now(), perMinute, perDay))) {
      await deps.store.count("install_denied");
      return limitedResponse(deps.now() + 60_000, deps.now(), "install-limit");
    }
  }

  const handler = new Handler(deps, control, request.lane);
  return classified.route.kind === "get" ? handler.get(classified.route) : handler.batch(classified.route);
}
