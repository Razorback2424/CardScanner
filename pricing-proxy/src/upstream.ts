// The only code that talks to JustTCG. The key comes from Secret Manager at
// call time and never appears in a response, log line or cache entry.

export interface UpstreamRequest {
  readonly method: "GET" | "POST";
  readonly path: string;
  readonly query: ReadonlyArray<{ readonly name: string; readonly value: string }>;
  readonly body?: unknown;
}

export type UpstreamResult =
  | { readonly kind: "response"; readonly status: number; readonly body: string; readonly link: string | null; readonly retryAfter: string | null }
  | { readonly kind: "network-error"; readonly message: string };

export interface Upstream {
  send(request: UpstreamRequest): Promise<UpstreamResult>;
}

export class JustTCGUpstream implements Upstream {
  private readonly baseURL: string;
  private readonly apiKey: () => string;
  private readonly timeoutMs: number;

  constructor(baseURL: string, apiKey: () => string, timeoutMs: number) {
    this.baseURL = baseURL;
    this.apiKey = apiKey;
    this.timeoutMs = timeoutMs;
  }

  async send(request: UpstreamRequest): Promise<UpstreamResult> {
    const url = new URL(request.path, this.baseURL.endsWith("/") ? this.baseURL : this.baseURL + "/");
    for (const { name, value } of request.query) url.searchParams.append(name, value);
    const headers: Record<string, string> = {
      "x-api-key": this.apiKey(),
      // JustTCG sits behind Cloudflare, which rejects default client agents (error 1010).
      "User-Agent": "ScanStashPricingProxy/1.0",
      Accept: "application/json",
    };
    let body: string | undefined;
    if (request.body !== undefined) {
      body = JSON.stringify(request.body);
      headers["Content-Type"] = "application/json";
    }
    try {
      const response = await fetch(url, {
        method: request.method,
        headers,
        body,
        redirect: "error",
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      return {
        kind: "response",
        status: response.status,
        body: await response.text(),
        link: response.headers.get("link"),
        retryAfter: response.headers.get("retry-after"),
      };
    } catch (error) {
      return { kind: "network-error", message: error instanceof Error ? error.name : "unknown" };
    }
  }
}

/** Retry-After as seconds or an HTTP date; falls back when absent or unparseable. */
export function retryAfterMs(value: string | null, now: number, fallbackMs: number): number {
  if (value) {
    const trimmed = value.trim();
    if (/^\d+$/.test(trimmed)) return now + Number(trimmed) * 1000;
    const date = Date.parse(trimmed);
    if (!Number.isNaN(date)) return Math.max(date, now);
  }
  return now + fallbackMs;
}
