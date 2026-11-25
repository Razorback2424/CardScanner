import assert from "node:assert/strict";
import { test } from "node:test";
import { harness, ok, parse, status } from "./helpers.ts";

const SETS = { method: "GET", path: "v1/sets", query: [{ name: "game", value: "pokemon" }] };
const HOUR = 3_600_000;

test("a fresh hit never calls JustTCG, and account metadata is removed", async () => {
  const h = harness(() => ok({ data: [{ id: "base" }], _metadata: { apiDailyRequestsUsed: 900 } }));
  const first = await h.call(SETS);
  assert.equal(first.headers["X-ScanStash-Cache"], "miss");
  assert.deepEqual(parse(first), { data: [{ id: "base" }] });
  const second = await h.call(SETS);
  assert.equal(second.headers["X-ScanStash-Cache"], "hit");
  assert.equal(h.upstream.calls.length, 1);
});

test("an expired entry is refreshed", async () => {
  const h = harness(() => ok({ data: [{ id: "base" }] }));
  await h.call(SETS);
  h.clock.advance(25 * HOUR);
  const again = await h.call(SETS);
  assert.equal(again.headers["X-ScanStash-Cache"], "miss");
  assert.equal(h.upstream.calls.length, 2);
});

test("a 404 is cached briefly as a genuine absence with its status", async () => {
  const h = harness(() => status(404));
  const query = { method: "GET", path: "v2/cards", query: [{ name: "variant_id", value: "x" }] };
  assert.equal((await h.call(query)).status, 404);
  assert.equal((await h.call(query)).status, 404);
  assert.equal(h.upstream.calls.length, 1);
  h.clock.advance(16 * 60_000);
  await h.call(query);
  assert.equal(h.upstream.calls.length, 2);
});

test("a provider failure never overwrites a good value; the old value is served as stale", async () => {
  let fail = false;
  const h = harness(() => (fail ? status(500) : ok({ data: [{ id: "base" }] })));
  const first = await h.call(SETS);
  fail = true;
  h.clock.advance(25 * HOUR);
  const stale = await h.call(SETS);
  assert.equal(stale.status, 200);
  assert.equal(stale.headers["X-ScanStash-Cache"], "stale");
  assert.equal(stale.headers["X-ScanStash-Data-As-Of"], first.headers["X-ScanStash-Data-As-Of"]);
  assert.deepEqual(parse(stale), { data: [{ id: "base" }] });
});

test("without a cached value a provider failure is an honest 503", async () => {
  const h = harness(() => ({ kind: "network-error", message: "TimeoutError" }));
  const response = await h.call(SETS);
  assert.equal(response.status, 503);
  assert.equal(response.headers["X-ScanStash-Unavailable"], "provider");
});

test("an expired or revoked operator key is never shown as the user's problem", async () => {
  const h = harness(() => status(401));
  const response = await h.call(SETS);
  assert.equal(response.status, 503);
  assert.equal(response.headers["X-ScanStash-Unavailable"], "provider-auth");
});

test("a provider 429 opens the circuit until Retry-After", async () => {
  const h = harness(() => status(429, "120"));
  const limited = await h.call(SETS);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers["Retry-After"], "120");
  await h.call({ ...SETS, query: [{ name: "game", value: "magic-the-gathering" }] });
  assert.equal(h.upstream.calls.length, 1, "circuit must hold further upstream calls");
  h.clock.advance(121_000);
  h.upstream.responder = () => ok({ data: [] });
  await h.call(SETS);
  assert.equal(h.upstream.calls.length, 2);
});

test("repeated provider failures open the circuit", async () => {
  const h = harness(() => status(502));
  for (let i = 0; i < 3; i++) await h.call({ ...SETS, query: [{ name: "game", value: `g${i}` }] });
  await h.call({ ...SETS, query: [{ name: "game", value: "g9" }] });
  assert.equal(h.upstream.calls.length, 3);
});

test("with the subscription off nothing is served, not even a fresh cache entry", async () => {
  const h = harness(() => ok({ data: [{ id: "base" }] }));
  await h.call(SETS);
  h.store.control = { ...h.store.control, subscriptionActive: false };
  const response = await h.call(SETS);
  assert.equal(response.status, 503);
  assert.equal(response.headers["X-ScanStash-Unavailable"], "subscription");
  assert.equal(h.upstream.calls.length, 1);
});

test("stored data stops being served once it passes the retention window", async () => {
  let fail = false;
  const h = harness(() => (fail ? status(500) : ok({ data: [{ id: "base" }] })));
  await h.call(SETS);
  fail = true;
  h.clock.advance(32 * 24 * HOUR);
  assert.equal((await h.call(SETS)).status, 503);
});

test("the global per-minute budget holds at 80% of the tier", async () => {
  const h = harness(() => ok({ data: [{ id: "x" }] }));
  const responses = [];
  for (let i = 0; i < 41; i++) responses.push(await h.call({ ...SETS, query: [{ name: "game", value: `g${i}` }] }));
  assert.equal(h.upstream.calls.length, 40);
  const last = responses.at(-1)!;
  assert.equal(last.status, 429);
  assert.equal(last.headers["X-ScanStash-Unavailable"], "quota");
});

test("background work cannot spend the interactive reserve", async () => {
  const h = harness(() => ok({ data: [{ id: "x" }] }));
  for (let i = 0; i < 30; i++) await h.call({ ...SETS, lane: "background", query: [{ name: "game", value: `b${i}` }] });
  assert.equal(h.upstream.calls.length, 24, "background capped at 60% of 40");
  const tap = await h.call({ ...SETS, lane: "interactive", query: [{ name: "game", value: "tap" }] });
  assert.equal(tap.status, 200);
});

test("one install cannot exceed its own per-minute limit", async () => {
  const h = harness(() => ok({ data: [] }));
  let last;
  for (let i = 0; i < 31; i++) last = await h.call({ ...SETS, installHash: "abc" });
  assert.equal(last!.status, 429);
  assert.equal(last!.headers["X-ScanStash-Unavailable"], "install-limit");
  assert.equal((await h.call({ ...SETS, installHash: "other" })).status, 200);
});

test("fifty simultaneous misses on one key produce one upstream call", async () => {
  const h = harness(async () => {
    for (let i = 0; i < 3; i++) await new Promise((resolve) => setImmediate(resolve));
    return ok({ data: [{ id: "base" }] });
  });
  const responses = await Promise.all(Array.from({ length: 50 }, () => h.call(SETS)));
  assert.equal(h.upstream.calls.length, 1);
  assert.ok(responses.every((r) => r.status === 200));
});

test("a provider validation error passes through and is not cached", async () => {
  const h = harness(() => status(400));
  assert.equal((await h.call(SETS)).status, 400);
  assert.equal((await h.call(SETS)).status, 400);
  assert.equal(h.upstream.calls.length, 2);
});

test("pagination Link headers pass through unchanged", async () => {
  const link = '<https://api.justtcg.com/v2/cards?cursor=abc>; rel="next"';
  const h = harness(() => ok({ data: [{ id: "c" }] }, { link }));
  const response = await h.call({ method: "GET", path: "v2/cards", query: [{ name: "graded", value: "only" }] });
  assert.equal(response.headers.Link, link);
  assert.equal((await h.call({ method: "GET", path: "v2/cards", query: [{ name: "graded", value: "only" }] })).headers.Link, link);
});

test("a crashed refresh owner blocks the key only until its lease expires", async () => {
  const h = harness(() => ok({ data: [{ id: "base" }] }));
  const { requestKey } = await import("../src/routes.ts");
  const key = requestKey({ kind: "get", path: "v1/sets", query: SETS.query, ttl: "sets" });
  await h.store.acquireLease(key, "crashed", h.clock.now, h.config.leaseMs);
  const busy = await h.call(SETS);
  assert.equal(busy.status, 503);
  assert.equal(busy.headers["X-ScanStash-Unavailable"], "busy");
  h.clock.advance(h.config.leaseMs + 1);
  assert.equal((await h.call(SETS)).status, 200);
  assert.equal(h.upstream.calls.length, 1);
});
