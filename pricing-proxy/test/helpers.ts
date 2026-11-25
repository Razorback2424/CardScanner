import { defaultConfig } from "../src/config.ts";
import type { ProxyConfig } from "../src/config.ts";
import { MemoryStore } from "../src/memoryStore.ts";
import { handle } from "../src/proxy.ts";
import type { ProxyDeps, ProxyRequest, ProxyResponse } from "../src/proxy.ts";
import type { Upstream, UpstreamRequest, UpstreamResult } from "../src/upstream.ts";

export const T0 = Date.UTC(2026, 10, 24, 12, 0, 0);

export class Clock {
  now = T0;
  advance(ms: number): void {
    this.now += ms;
  }
}

type Responder = (request: UpstreamRequest) => UpstreamResult | Promise<UpstreamResult>;

export class StubUpstream implements Upstream {
  readonly calls: UpstreamRequest[] = [];
  responder: Responder;
  constructor(responder: Responder) {
    this.responder = responder;
  }
  async send(request: UpstreamRequest): Promise<UpstreamResult> {
    this.calls.push(request);
    return this.responder(request);
  }
}

export function ok(body: unknown, extra: Partial<{ status: number; link: string; retryAfter: string }> = {}): UpstreamResult {
  return { kind: "response", status: extra.status ?? 200, body: JSON.stringify(body), link: extra.link ?? null, retryAfter: extra.retryAfter ?? null };
}

export function status(code: number, retryAfter: string | null = null): UpstreamResult {
  return { kind: "response", status: code, body: JSON.stringify({ error: "x" }), link: null, retryAfter };
}

export function card(uuid: string, tcgplayerId: string, variantUUIDs: string[], lastUpdated = 1_764_000_000): Record<string, unknown> {
  return {
    id: `slug-${uuid}`,
    uuid,
    name: `Card ${uuid}`,
    tcgplayerId,
    variants: variantUUIDs.map((v) => ({ id: `slug-${v}`, uuid: v, price: 1.5, lastUpdated })),
  };
}

/** Batch responder that answers each requested item from a fixed catalog, like JustTCG. */
export function catalogResponder(catalog: Record<string, unknown>[]): Responder {
  return (request) => {
    const items = (request.body as Record<string, string>[]) ?? [];
    const data = catalog.filter((c) =>
      items.some((item) => {
        const [key, value] = Object.entries(item)[0]!;
        if (key === "tcgplayerId") return c.tcgplayerId === value;
        if (key === "variantId") return (c.variants as { uuid: string }[]).some((v) => v.uuid === value);
        if (key === "cardId") return c.uuid === value;
        return false;
      }),
    );
    return ok({ data, _metadata: { apiDailyRequestsUsed: 999 } });
  };
}

export interface Harness {
  readonly clock: Clock;
  readonly store: MemoryStore;
  readonly upstream: StubUpstream;
  readonly config: ProxyConfig;
  call(request: Partial<ProxyRequest>): Promise<ProxyResponse>;
}

export function harness(responder: Responder, overrides: Partial<ProxyConfig> = {}): Harness {
  const clock = new Clock();
  const store = new MemoryStore();
  const upstream = new StubUpstream(responder);
  const config: ProxyConfig = { ...defaultConfig("starter"), ...overrides };
  let owners = 0;
  const deps: ProxyDeps = {
    config,
    store,
    upstream,
    now: () => clock.now,
    // Many concurrent waiters share one fake clock, so a sleep only yields and
    // nudges time forward; the lease-wait deadline still terminates every loop.
    sleep: async () => {
      clock.advance(1);
      await new Promise((resolve) => setImmediate(resolve));
    },
    newOwner: () => `owner-${++owners}`,
  };
  return {
    clock,
    store,
    upstream,
    config,
    call: (request) =>
      handle(
        {
          method: "GET",
          path: "v1/sets",
          query: [],
          body: undefined,
          installHash: null,
          lane: "interactive",
          ...request,
        },
        deps,
      ),
  };
}

export function parse(response: ProxyResponse): any {
  return JSON.parse(response.body);
}
