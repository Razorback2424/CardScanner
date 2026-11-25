import { quotaVerdict, windowIDs } from "./store.ts";
import type { CacheEntry, Control, QuotaDecision, QuotaRequest, Store } from "./store.ts";

/** Single-process Store for tests and the local harness. Not a global quota. */
export class MemoryStore implements Store {
  readonly cache = new Map<string, CacheEntry>();
  readonly leases = new Map<string, { owner: string; expiresAt: number }>();
  readonly counters = new Map<string, number>();
  private readonly quota = new Map<string, { total: number; background: number }>();
  private readonly installs = new Map<string, number>();
  control: Control = { subscriptionActive: true, blockedUntil: 0 };
  failures = 0;

  async getEntries(keys: readonly string[]): Promise<Map<string, CacheEntry>> {
    const found = new Map<string, CacheEntry>();
    for (const key of keys) {
      const entry = this.cache.get(key);
      if (entry) found.set(key, entry);
    }
    return found;
  }

  async putEntries(entries: ReadonlyMap<string, CacheEntry>): Promise<void> {
    for (const [key, entry] of entries) this.cache.set(key, entry);
  }

  async acquireLease(key: string, owner: string, now: number, leaseMs: number): Promise<boolean> {
    const current = this.leases.get(key);
    if (current && current.owner !== owner && current.expiresAt > now) return false;
    this.leases.set(key, { owner, expiresAt: now + leaseMs });
    return true;
  }

  async releaseLease(key: string, owner: string): Promise<void> {
    if (this.leases.get(key)?.owner === owner) this.leases.delete(key);
  }

  private bucket(id: string): { total: number; background: number } {
    let b = this.quota.get(id);
    if (!b) {
      b = { total: 0, background: 0 };
      this.quota.set(id, b);
    }
    return b;
  }

  async reserveQuota(request: QuotaRequest): Promise<QuotaDecision> {
    const ids = windowIDs(request.now);
    const used = { minute: this.bucket("m" + ids.minute), day: this.bucket("d" + ids.day), month: this.bucket("mo" + ids.month) };
    const verdict = quotaVerdict(used, request);
    if (verdict.granted) {
      for (const b of [used.minute, used.day, used.month]) {
        b.total += 1;
        if (request.lane === "background") b.background += 1;
      }
    }
    return verdict;
  }

  quotaUsed(now: number): { minute: number; day: number; month: number } {
    const ids = windowIDs(now);
    return { minute: this.bucket("m" + ids.minute).total, day: this.bucket("d" + ids.day).total, month: this.bucket("mo" + ids.month).total };
  }

  async admitInstall(installHash: string, now: number, perMinute: number, perDay: number): Promise<boolean> {
    const ids = windowIDs(now);
    const mKey = `${installHash}|${ids.minute}`;
    const dKey = `${installHash}|${ids.day}`;
    const m = this.installs.get(mKey) ?? 0;
    const d = this.installs.get(dKey) ?? 0;
    if (m >= perMinute || d >= perDay) return false;
    this.installs.set(mKey, m + 1);
    this.installs.set(dKey, d + 1);
    return true;
  }

  async getControl(): Promise<Control> {
    return this.control;
  }

  async openCircuit(until: number): Promise<void> {
    this.control = { ...this.control, blockedUntil: Math.max(this.control.blockedUntil, until) };
  }

  async recordUpstreamFailure(): Promise<number> {
    this.failures += 1;
    return this.failures;
  }

  async recordUpstreamSuccess(): Promise<void> {
    this.failures = 0;
  }

  async count(counter: string, by = 1): Promise<void> {
    this.counters.set(counter, (this.counters.get(counter) ?? 0) + by);
  }
}
