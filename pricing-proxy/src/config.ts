// Every limit lives here so a tier upgrade or TTL change is configuration,
// not code. Published JustTCG limits, checked 2026-11-10 (see
// docs/plans/shared_pricing_cache_plan.md §2).

export interface TierLimits {
  readonly perMinute: number;
  readonly perDay: number;
  readonly perMonth: number;
  /** Items per POST /v1/cards batch. */
  readonly batchSize: number;
}

export const TIERS: Readonly<Record<string, TierLimits>> = {
  // Free is for local prototyping only; JustTCG's terms forbid serving it to users.
  free: { perMinute: 10, perDay: 100, perMonth: 1_000, batchSize: 20 },
  starter: { perMinute: 50, perDay: 1_000, perMonth: 10_000, batchSize: 100 },
  professional: { perMinute: 100, perDay: 5_000, perMonth: 50_000, batchSize: 100 },
  enterprise: { perMinute: 500, perDay: 50_000, perMonth: 500_000, batchSize: 200 },
};

export interface ProxyConfig {
  readonly tier: TierLimits;
  /** Fraction of each published window the proxy may spend (retry/probe headroom). */
  readonly headroom: number;
  /** Fraction of the spendable window that background work may use. */
  readonly backgroundShare: number;
  readonly ttlMs: {
    readonly sets: number;
    readonly quote: number;
    readonly history: number;
    /** A genuine "nothing found" (empty data or 404). Provider errors are never cached. */
    readonly negative: number;
  };
  /** Stale entries stay servable (while the subscription is active) this long past expiry. */
  readonly staleRetentionMs: number;
  readonly perInstall: { readonly perMinute: number; readonly perDay: number };
  readonly leaseMs: number;
  /** How long a request waits for another caller's in-flight refresh of the same key. */
  readonly leaseWaitMs: number;
  readonly leasePollMs: number;
  readonly upstreamTimeoutMs: number;
  /** Firestore documents max out at 1 MiB; larger bodies are served but not cached. */
  readonly maxCachedBytes: number;
  /** Consecutive upstream failures that open the circuit, and for how long. */
  readonly circuitFailureThreshold: number;
  readonly circuitOpenMs: number;
  readonly upstreamBaseURL: string;
}

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export function defaultConfig(tierName: string = "starter"): ProxyConfig {
  const tier = TIERS[tierName];
  if (!tier) throw new Error(`Unknown JustTCG tier: ${tierName}`);
  return {
    tier,
    headroom: 0.8,
    backgroundShare: 0.6,
    ttlMs: { sets: DAY, quote: HOUR, history: 12 * HOUR, negative: 15 * MINUTE },
    staleRetentionMs: 30 * DAY,
    perInstall: { perMinute: 30, perDay: 600 },
    leaseMs: 20_000,
    leaseWaitMs: 4_000,
    leasePollMs: 250,
    upstreamTimeoutMs: 20_000,
    maxCachedBytes: 900_000,
    circuitFailureThreshold: 3,
    circuitOpenMs: 30_000,
    upstreamBaseURL: "https://api.justtcg.com",
  };
}
