import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { quotaVerdict, windowIDs } from "./store.ts";
import type { CacheEntry, Control, QuotaDecision, QuotaRequest, Store } from "./store.ts";

// Firestore-backed coordination. Every collection here is server-only:
// firestore.rules denies all client access and the function uses the Admin SDK.
//
// Field ownership (one writer per field, see shared_pricing_cache_plan.md §7):
//   pricingCache/{key}        written only by putEntries
//   pricingLeases/{key}       written only by acquire/releaseLease
//   pricingQuota/{window}     written only by reserveQuota
//   pricingInstalls/{id}      written only by admitInstall
//   pricingControl/main       subscriptionActive: operator only (console);
//                             blockedUntil/failures: openCircuit/record*
//   pricingCounters/{day}     written only by count
//
// TTL policies (configured at deploy): pricingCache.purgeAt,
// pricingLeases.expiresAtTS, pricingInstalls.purgeAt, pricingQuota.purgeAt.

const CACHE = "pricingCache";
const LEASES = "pricingLeases";
const QUOTA = "pricingQuota";
const INSTALLS = "pricingInstalls";
const CONTROL = "pricingControl";
const COUNTERS = "pricingCounters";

const DAY = 86_400_000;
/** getAll is limited per call; batches are at most 200 items. */
const READ_CHUNK = 100;

interface Bucket {
  total: number;
  background: number;
}

function bucket(data: FirebaseFirestore.DocumentData | undefined): Bucket {
  return { total: Number(data?.total ?? 0), background: Number(data?.background ?? 0) };
}

export class FirestoreStore implements Store {
  private readonly db: Firestore;

  constructor(db: Firestore) {
    this.db = db;
  }

  async getEntries(keys: readonly string[]): Promise<Map<string, CacheEntry>> {
    const found = new Map<string, CacheEntry>();
    for (let i = 0; i < keys.length; i += READ_CHUNK) {
      const refs = keys.slice(i, i + READ_CHUNK).map((key) => this.db.collection(CACHE).doc(key));
      if (refs.length === 0) continue;
      const snapshots = await this.db.getAll(...refs);
      for (const snap of snapshots) {
        const data = snap.data();
        if (!data) continue;
        const entry = JSON.parse(String(data.entry)) as CacheEntry;
        found.set(snap.id, entry);
      }
    }
    return found;
  }

  async putEntries(entries: ReadonlyMap<string, CacheEntry>, purgeAfterMs: number): Promise<void> {
    const writer = this.db.bulkWriter();
    for (const [key, entry] of entries) {
      writer.set(this.db.collection(CACHE).doc(key), {
        // Stored as one string so provider JSON never needs Firestore-safe keys.
        entry: JSON.stringify(entry),
        purgeAt: Timestamp.fromMillis(entry.expiresAt + purgeAfterMs),
      });
    }
    await writer.close();
  }

  async acquireLease(key: string, owner: string, now: number, leaseMs: number): Promise<boolean> {
    const ref = this.db.collection(LEASES).doc(key);
    // The provider is never called inside this transaction: transactions retry.
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.data();
      if (current && current.owner !== owner && Number(current.expiresAt) > now) return false;
      tx.set(ref, { owner, expiresAt: now + leaseMs, expiresAtTS: Timestamp.fromMillis(now + leaseMs + DAY) });
      return true;
    });
  }

  async releaseLease(key: string, owner: string): Promise<void> {
    const ref = this.db.collection(LEASES).doc(key);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.data()?.owner === owner) tx.delete(ref);
    });
  }

  async reserveQuota(request: QuotaRequest): Promise<QuotaDecision> {
    const ids = windowIDs(request.now);
    const refs = {
      minute: this.db.collection(QUOTA).doc(`m_${ids.minute}`),
      day: this.db.collection(QUOTA).doc(`d_${ids.day}`),
      month: this.db.collection(QUOTA).doc(`mo_${ids.month}`),
    };
    return this.db.runTransaction(async (tx) => {
      const [m, d, mo] = await tx.getAll(refs.minute, refs.day, refs.month);
      const used = { minute: bucket(m?.data()), day: bucket(d?.data()), month: bucket(mo?.data()) };
      const verdict = quotaVerdict(used, request);
      if (verdict.granted) {
        const purgeAt = Timestamp.fromMillis(request.now + 62 * DAY);
        const bg = request.lane === "background" ? 1 : 0;
        for (const [name, ref] of Object.entries(refs) as [keyof typeof used, FirebaseFirestore.DocumentReference][]) {
          tx.set(ref, { total: used[name].total + 1, background: used[name].background + bg, purgeAt });
        }
      }
      return verdict;
    });
  }

  async admitInstall(installHash: string, now: number, perMinute: number, perDay: number): Promise<boolean> {
    const ids = windowIDs(now);
    const ref = this.db.collection(INSTALLS).doc(`${installHash}_${ids.day}`);
    return this.db.runTransaction(async (tx) => {
      const data = (await tx.get(ref)).data();
      const day = Number(data?.day ?? 0);
      const minute = data?.minuteID === ids.minute ? Number(data?.minute ?? 0) : 0;
      if (day >= perDay || minute >= perMinute) return false;
      // Hashed install ID only; purged after 7 days (privacy label commitment).
      tx.set(ref, { day: day + 1, minute: minute + 1, minuteID: ids.minute, purgeAt: Timestamp.fromMillis(now + 7 * DAY) });
      return true;
    });
  }

  async getControl(): Promise<Control> {
    const data = (await this.db.collection(CONTROL).doc("main").get()).data();
    // Missing control document means not yet licensed: serve nothing.
    return { subscriptionActive: data?.subscriptionActive === true, blockedUntil: Number(data?.blockedUntil ?? 0) };
  }

  async openCircuit(until: number): Promise<void> {
    const ref = this.db.collection(CONTROL).doc("main");
    await this.db.runTransaction(async (tx) => {
      const current = Number((await tx.get(ref)).data()?.blockedUntil ?? 0);
      if (until > current) tx.set(ref, { blockedUntil: until }, { merge: true });
    });
  }

  async recordUpstreamFailure(): Promise<number> {
    const ref = this.db.collection(CONTROL).doc("main");
    return this.db.runTransaction(async (tx) => {
      const failures = Number((await tx.get(ref)).data()?.consecutiveFailures ?? 0) + 1;
      tx.set(ref, { consecutiveFailures: failures }, { merge: true });
      return failures;
    });
  }

  async recordUpstreamSuccess(): Promise<void> {
    await this.db.collection(CONTROL).doc("main").set({ consecutiveFailures: 0 }, { merge: true });
  }

  async count(counter: string, by = 1): Promise<void> {
    const day = windowIDs(Date.now()).day;
    await this.db.collection(COUNTERS).doc(day).set({ [counter]: FieldValue.increment(by) }, { merge: true });
  }
}
