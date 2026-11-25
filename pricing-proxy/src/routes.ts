import { createHash } from "node:crypto";
import type { ProxyConfig } from "./config.ts";

// The proxy forwards exactly the request shapes the app's JustTCG clients use
// (JustTCGV1Client, JustTCGV2GradedClient, CardMarketHistoryService). Anything
// else is refused so the endpoint cannot become a general JustTCG mirror.

export type TTLClass = "sets" | "quote" | "history";

export interface QueryPair {
  readonly name: string;
  readonly value: string;
}

export interface BatchItem {
  /** Wire key, e.g. "variantId". */
  readonly key: string;
  readonly value: string;
}

export type Route =
  | { readonly kind: "get"; readonly path: string; readonly query: QueryPair[]; readonly ttl: TTLClass }
  | {
      readonly kind: "batch";
      readonly path: "v1/cards";
      readonly items: BatchItem[];
      readonly includePriceHistory: boolean;
      /** Unix seconds; applied to cached data the way the provider applies it. */
      readonly updatedAfter: number | null;
    };

export type RouteResult = { readonly ok: true; readonly route: Route } | { readonly ok: false; readonly status: number; readonly reason: string };

/** Vendor precedence order (JustTCGBatchLookup). */
export const BATCH_KEYS = ["variantId", "tcgplayerSkuId", "tcgplayerId", "mtgjsonId", "scryfallId", "cardId"] as const;

/** Matches JustTCGQuota.batchSize in proxy builds of the app. */
export const CLIENT_BATCH_LIMIT = 100;

const GET_PATHS = new Set(["v1/sets", "v1/cards", "v2/cards"]);
const NAME = /^[A-Za-z_][A-Za-z0-9_.]{0,39}$/;
const MAX_QUERY_PAIRS = 24;
const MAX_VALUE_LENGTH = 256;

function fail(status: number, reason: string): RouteResult {
  return { ok: false, status, reason };
}

function normalizePath(raw: string): string {
  return raw.replace(/^\/+/, "").replace(/\/+$/, "");
}

function validQuery(pairs: QueryPair[]): string | null {
  if (pairs.length > MAX_QUERY_PAIRS) return "too many query parameters";
  for (const { name, value } of pairs) {
    if (!NAME.test(name)) return `invalid query parameter name`;
    if (value.length > MAX_VALUE_LENGTH) return `query value too long`;
  }
  return null;
}

function ttlFor(path: string, query: QueryPair[]): TTLClass {
  if (path === "v1/sets") return "sets";
  const wantsHistory = query.some(
    ({ name, value }) =>
      (name === "include_price_history" && value === "true") ||
      (name === "include" && value.includes("price_history")),
  );
  return wantsHistory ? "history" : "quote";
}

export function classify(
  method: string,
  rawPath: string,
  query: QueryPair[],
  body: unknown,
  config: ProxyConfig,
): RouteResult {
  const path = normalizePath(rawPath);
  const queryError = validQuery(query);
  if (queryError) return fail(400, queryError);

  if (method === "GET") {
    if (!GET_PATHS.has(path)) return fail(404, "unsupported path");
    return { ok: true, route: { kind: "get", path, query, ttl: ttlFor(path, query) } };
  }

  if (method === "POST" && path === "v1/cards") {
    for (const { name } of query) {
      if (name !== "include_price_history" && name !== "updated_after") return fail(400, "unsupported batch parameter");
    }
    if (!Array.isArray(body)) return fail(400, "batch body must be an array");
    if (body.length === 0) return fail(400, "empty batch");
    // The app sends up to CLIENT_BATCH_LIMIT items; the proxy splits upstream
    // calls to the plan's own batch size.
    if (body.length > Math.max(CLIENT_BATCH_LIMIT, config.tier.batchSize)) return fail(413, "batch too large");
    const items: BatchItem[] = [];
    const seen = new Set<string>();
    for (const raw of body) {
      if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return fail(400, "batch item must be an object");
      const entries = Object.entries(raw as Record<string, unknown>);
      if (entries.length !== 1) return fail(400, "batch item needs exactly one identifier");
      const [key, value] = entries[0]!;
      if (!(BATCH_KEYS as readonly string[]).includes(key)) return fail(400, "unsupported batch identifier");
      if ((typeof value !== "string" && typeof value !== "number") || String(value).length === 0 || String(value).length > MAX_VALUE_LENGTH) {
        return fail(400, "invalid batch identifier value");
      }
      const item = { key, value: String(value) };
      const id = `${item.key}=${item.value}`;
      if (!seen.has(id)) {
        seen.add(id);
        items.push(item);
      }
    }
    const history = query.find((p) => p.name === "include_price_history")?.value === "true";
    const updatedRaw = query.find((p) => p.name === "updated_after")?.value;
    let updatedAfter: number | null = null;
    if (updatedRaw !== undefined) {
      if (!/^\d{1,12}$/.test(updatedRaw)) return fail(400, "invalid updated_after");
      updatedAfter = Number(updatedRaw);
    }
    return { ok: true, route: { kind: "batch", path: "v1/cards", items, includePriceHistory: history, updatedAfter } };
  }

  return fail(method === "GET" || method === "POST" ? 404 : 405, "unsupported request");
}

function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

/** Cache key for a GET: method, path and query in a canonical order. */
export function requestKey(route: Extract<Route, { kind: "get" }>): string {
  const sorted = [...route.query].sort((a, b) => (a.name === b.name ? (a.value < b.value ? -1 : 1) : a.name < b.name ? -1 : 1));
  return "r_" + sha256(`GET|${route.path}|` + sorted.map((p) => `${p.name}=${p.value}`).join("&"));
}

/** Cache key for one batch item; history-bearing and lean results are cached separately. */
export function itemKey(item: BatchItem, includePriceHistory: boolean): string {
  return "i_" + sha256(`POST|v1/cards|${item.key}=${item.value}|h=${includePriceHistory ? 1 : 0}`);
}

export function hashInstall(installID: string, salt: string): string {
  return sha256(`install|${salt}|${installID}`).slice(0, 32);
}
