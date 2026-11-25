// Coordination state shared by every function instance. Production uses
// Firestore (firestoreStore.ts); tests use MemoryStore. In-process counters
// are never a global quota: Cloud Functions scales across instances.

export type Lane = "interactive" | "background";

export interface CachedResponse {
  readonly kind: "response";
  readonly status: number;
  /** Sanitized body (provider `_metadata` removed). */
  readonly body: string;
  readonly link: string | null;
  readonly fetchedAt: number;
  readonly expiresAt: number;
  readonly negative: boolean;
}

export interface CachedItem {
  readonly kind: "item";
  /** Provider card objects that answered this one batch item. Empty when negative. */
  readonly cards: unknown[];
  readonly fetchedAt: number;
  readonly expiresAt: number;
  readonly negative: boolean;
}

export type CacheEntry = CachedResponse | CachedItem;

export interface QuotaRequest {
  readonly lane: Lane;
  readonly now: number;
  readonly limits: { readonly perMinute: number; readonly perDay: number; readonly perMonth: number };
  /** Background may spend only this fraction of each window. */
  readonly backgroundShare: number;
}

export type QuotaDecision = { readonly granted: true } | { readonly granted: false; readonly retryAt: number; readonly window: "minute" | "day" | "month" };

export interface Control {
  /**
   * JustTCG permits serving stored data only while the paid plan is active.
   * When false the proxy serves nothing, cached or live.
   */
  readonly subscriptionActive: boolean;
  /** Circuit open (429 Retry-After or repeated failures) until this time. */
  readonly blockedUntil: number;
}

export interface Store {
  getEntries(keys: readonly string[]): Promise<Map<string, CacheEntry>>;
  putEntries(entries: ReadonlyMap<string, CacheEntry>, purgeAfterMs: number): Promise<void>;
  /** True when this owner now holds the refresh lease for `key`. */
  acquireLease(key: string, owner: string, now: number, leaseMs: number): Promise<boolean>;
  releaseLease(key: string, owner: string): Promise<void>;
  /** Atomically reserves one upstream request in every window, or refuses. */
  reserveQuota(request: QuotaRequest): Promise<QuotaDecision>;
  /** Counts one proxy call for an install; false when it is over its limit. */
  admitInstall(installHash: string, now: number, perMinute: number, perDay: number): Promise<boolean>;
  getControl(): Promise<Control>;
  openCircuit(until: number): Promise<void>;
  /** Returns the consecutive failure count after recording this failure. */
  recordUpstreamFailure(): Promise<number>;
  recordUpstreamSuccess(): Promise<void>;
  /** Aggregate counters only; never per-card or per-install. */
  count(counter: string, by?: number): Promise<void>;
}

// UTC window identifiers shared by the stores.
export function windowIDs(now: number): { minute: string; day: string; month: string } {
  const iso = new Date(now).toISOString(); // 2026-11-24T15:18:02.000Z
  return { minute: iso.slice(0, 16), day: iso.slice(0, 10), month: iso.slice(0, 7) };
}

export function windowResets(now: number): { minute: number; day: number; month: number } {
  const d = new Date(now);
  const minute = Math.floor(now / 60_000) * 60_000 + 60_000;
  const day = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
  const month = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
  return { minute, day, month };
}

/** Shared admission rule so both stores enforce identical arithmetic. */
export function quotaVerdict(
  used: { minute: { total: number; background: number }; day: { total: number; background: number }; month: { total: number; background: number } },
  request: QuotaRequest,
): QuotaDecision {
  const resets = windowResets(request.now);
  const windows = [
    ["minute", request.limits.perMinute, used.minute, resets.minute],
    ["day", request.limits.perDay, used.day, resets.day],
    ["month", request.limits.perMonth, used.month, resets.month],
  ] as const;
  for (const [name, limit, counts, resetAt] of windows) {
    if (counts.total >= limit) return { granted: false, retryAt: resetAt, window: name };
    if (request.lane === "background" && counts.background >= Math.floor(limit * request.backgroundShare)) {
      return { granted: false, retryAt: resetAt, window: name };
    }
  }
  return { granted: true };
}
