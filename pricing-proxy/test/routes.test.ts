import assert from "node:assert/strict";
import { test } from "node:test";
import { defaultConfig } from "../src/config.ts";
import { classify, itemKey, requestKey } from "../src/routes.ts";

const config = defaultConfig("starter");

test("only the app's JustTCG request shapes are accepted", () => {
  assert.equal(classify("GET", "/v1/sets", [{ name: "game", value: "pokemon" }], undefined, config).ok, true);
  assert.equal(classify("GET", "v2/cards", [], undefined, config).ok, true);
  const other = classify("GET", "v1/games", [], undefined, config);
  assert.deepEqual(other.ok ? null : other.status, 404);
  const put = classify("PUT", "v1/cards", [], [], config);
  assert.deepEqual(put.ok ? null : put.status, 405);
  const postSets = classify("POST", "v1/sets", [], [], config);
  assert.deepEqual(postSets.ok ? null : postSets.status, 404);
});

test("batch validation enforces one identifier per item and the tier size", () => {
  const two = classify("POST", "v1/cards", [], [{ variantId: "a", cardId: "b" }], config);
  assert.equal(two.ok ? null : two.status, 400);
  const unknown = classify("POST", "v1/cards", [], [{ name: "Charizard" }], config);
  assert.equal(unknown.ok ? null : unknown.status, 400);
  const big = classify("POST", "v1/cards", [], Array.from({ length: 101 }, (_, i) => ({ variantId: `v${i}` })), config);
  assert.equal(big.ok ? null : big.status, 413);
  const badQuery = classify("POST", "v1/cards", [{ name: "game", value: "pokemon" }], [{ variantId: "a" }], config);
  assert.equal(badQuery.ok ? null : badQuery.status, 400);
});

test("batch items are de-duplicated and numeric identifiers normalized", () => {
  const result = classify(
    "POST",
    "v1/cards",
    [{ name: "include_price_history", value: "false" }, { name: "updated_after", value: "1764000000" }],
    [{ tcgplayerId: 42 }, { tcgplayerId: "42" }, { variantId: "v" }],
    config,
  );
  assert.ok(result.ok && result.route.kind === "batch");
  assert.deepEqual(result.route.items, [{ key: "tcgplayerId", value: "42" }, { key: "variantId", value: "v" }]);
  assert.equal(result.route.updatedAfter, 1_764_000_000);
});

test("history requests get the history TTL class", () => {
  const history = classify("GET", "v1/cards", [{ name: "tcgplayerId", value: "1" }, { name: "include_price_history", value: "true" }], undefined, config);
  assert.ok(history.ok && history.route.kind === "get" && history.route.ttl === "history");
  const graded = classify("GET", "v2/cards", [{ name: "include", value: "price_history.1y" }], undefined, config);
  assert.ok(graded.ok && graded.route.kind === "get" && graded.route.ttl === "history");
});

test("cache keys ignore query order but not history flags", () => {
  const a = classify("GET", "v1/cards", [{ name: "a", value: "1" }, { name: "b", value: "2" }], undefined, config);
  const b = classify("GET", "v1/cards", [{ name: "b", value: "2" }, { name: "a", value: "1" }], undefined, config);
  assert.ok(a.ok && b.ok && a.route.kind === "get" && b.route.kind === "get");
  assert.equal(requestKey(a.route), requestKey(b.route));
  const item = { key: "variantId", value: "v" };
  assert.notEqual(itemKey(item, true), itemKey(item, false));
});
