import assert from "node:assert/strict";
import { test } from "node:test";
import { card, catalogResponder, harness, ok, parse, status } from "./helpers.ts";

const A = card("ua", "1", ["va"]);
const B = card("ub", "2", ["vb"]);
const C = card("uc", "3", ["vc"]);
const CATALOG = [A, B, C];

function batch(items: Record<string, string>[], query = [{ name: "include_price_history", value: "false" }]) {
  return { method: "POST", path: "v1/cards", query, body: items, lane: "background" as const };
}

test("items are cached individually so different batches share results", async () => {
  const h = harness(catalogResponder(CATALOG));
  const first = await h.call(batch([{ tcgplayerId: "1" }, { tcgplayerId: "2" }]));
  assert.deepEqual(parse(first).data.map((c: any) => c.uuid), ["ua", "ub"]);
  const second = await h.call(batch([{ tcgplayerId: "2" }, { tcgplayerId: "3" }]));
  assert.deepEqual(parse(second).data.map((c: any) => c.uuid), ["ub", "uc"]);
  assert.equal(h.upstream.calls.length, 2);
  assert.deepEqual(h.upstream.calls[1]!.body, [{ tcgplayerId: "3" }], "only the miss goes upstream");
  assert.equal(second.headers["X-ScanStash-Cache"], "miss");
  const third = await h.call(batch([{ tcgplayerId: "3" }, { tcgplayerId: "1" }]));
  assert.equal(third.headers["X-ScanStash-Cache"], "hit");
  assert.equal(h.upstream.calls.length, 2);
});

test("account metadata never reaches the app", async () => {
  const h = harness(catalogResponder(CATALOG));
  const body = parse(await h.call(batch([{ variantId: "va" }])));
  assert.equal(body._metadata, undefined);
});

test("a genuinely missing item is negative-cached briefly", async () => {
  const h = harness(catalogResponder(CATALOG));
  const response = await h.call(batch([{ tcgplayerId: "999" }]));
  assert.deepEqual(parse(response).data, []);
  await h.call(batch([{ tcgplayerId: "999" }]));
  assert.equal(h.upstream.calls.length, 1);
  h.clock.advance(16 * 60_000);
  await h.call(batch([{ tcgplayerId: "999" }]));
  assert.equal(h.upstream.calls.length, 2);
});

test("an uncorrelated card forbids negative caching and is still passed through", async () => {
  const orphan = { uuid: "orphan", name: "No identifiers", variants: [] };
  const h = harness(() => ok({ data: [orphan] }));
  const response = await h.call(batch([{ tcgplayerId: "77" }]));
  assert.deepEqual(parse(response).data, [orphan]);
  await h.call(batch([{ tcgplayerId: "77" }]));
  assert.equal(h.upstream.calls.length, 2, "nothing was cached as 'not found'");
});

test("updated_after is applied to cached data, never forwarded upstream", async () => {
  const old = card("uo", "10", ["vo"], 1_700_000_000);
  const recent = card("ur", "11", ["vr"], 1_764_000_000);
  const h = harness(catalogResponder([old, recent]));
  const response = await h.call(
    batch([{ tcgplayerId: "10" }, { tcgplayerId: "11" }], [
      { name: "include_price_history", value: "false" },
      { name: "updated_after", value: "1750000000" },
    ]),
  );
  assert.deepEqual(parse(response).data.map((c: any) => c.uuid), ["ur"]);
  assert.ok(!h.upstream.calls[0]!.query.some((p) => p.name === "updated_after"));
});

test("history and lean results are cached separately", async () => {
  const h = harness(catalogResponder(CATALOG));
  await h.call(batch([{ variantId: "va" }]));
  await h.call(batch([{ variantId: "va" }], [{ name: "include_price_history", value: "true" }]));
  assert.equal(h.upstream.calls.length, 2);
});

test("a provider failure serves expired items as stale with their real age", async () => {
  const h = harness(catalogResponder(CATALOG));
  const first = await h.call(batch([{ tcgplayerId: "1" }]));
  h.clock.advance(2 * 3_600_000);
  h.upstream.responder = () => status(503);
  const stale = await h.call(batch([{ tcgplayerId: "1" }]));
  assert.equal(stale.status, 200);
  assert.equal(stale.headers["X-ScanStash-Cache"], "stale");
  assert.equal(stale.headers["X-ScanStash-Data-As-Of"], first.headers["X-ScanStash-Data-As-Of"]);
});

test("a batch that cannot be answered completely fails instead of omitting items", async () => {
  const h = harness(catalogResponder(CATALOG));
  await h.call(batch([{ tcgplayerId: "1" }]));
  h.upstream.responder = () => status(500);
  const response = await h.call(batch([{ tcgplayerId: "1" }, { tcgplayerId: "2" }]));
  assert.equal(response.status, 503);
});

test("quota exhaustion without stale data returns 429 with Retry-After", async () => {
  const h = harness(catalogResponder(CATALOG));
  for (let i = 0; i < 24; i++) await h.call(batch([{ tcgplayerId: `x${i}` }]));
  const limited = await h.call(batch([{ tcgplayerId: "1" }]));
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers["Retry-After"]) >= 1);
});

test("the same card reached by two identifiers appears once", async () => {
  const h = harness(catalogResponder(CATALOG));
  const response = await h.call(batch([{ tcgplayerId: "1" }, { variantId: "va" }]));
  assert.deepEqual(parse(response).data.map((c: any) => c.uuid), ["ua"]);
});

test("the Data-As-Of header is the oldest item in a mixed response", async () => {
  const h = harness(catalogResponder(CATALOG));
  const first = await h.call(batch([{ tcgplayerId: "1" }]));
  h.clock.advance(10 * 60_000);
  const mixed = await h.call(batch([{ tcgplayerId: "1" }, { tcgplayerId: "2" }]));
  assert.equal(mixed.headers["X-ScanStash-Data-As-Of"], first.headers["X-ScanStash-Data-As-Of"]);
});

test("fifty simultaneous identical batches make one upstream call", async () => {
  const responder = catalogResponder(CATALOG);
  const h = harness(async (request) => {
    for (let i = 0; i < 3; i++) await new Promise((resolve) => setImmediate(resolve));
    return responder(request);
  });
  const responses = await Promise.all(Array.from({ length: 50 }, () => h.call(batch([{ tcgplayerId: "1" }, { tcgplayerId: "2" }]))));
  assert.equal(h.upstream.calls.length, 1);
  assert.ok(responses.every((r) => r.status === 200 && parse(r).data.length === 2));
});

test("a 100-item app batch is split into plan-sized upstream calls", async () => {
  const catalog = Array.from({ length: 45 }, (_, i) => card(`u${i}`, `${1000 + i}`, [`v${i}`]));
  const h = harness(catalogResponder(catalog), { tier: { perMinute: 10, perDay: 100, perMonth: 1_000, batchSize: 20 } });
  const response = await h.call(batch(catalog.map((c) => ({ tcgplayerId: String(c.tcgplayerId) }))));
  assert.equal(response.status, 200);
  assert.equal(parse(response).data.length, 45);
  assert.deepEqual(h.upstream.calls.map((c) => (c.body as unknown[]).length), [20, 20, 5]);
});
