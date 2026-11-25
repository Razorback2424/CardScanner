import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { defaultConfig } from "./config.ts";
import { FirestoreStore } from "./firestoreStore.ts";
import { handle } from "./proxy.ts";
import { hashInstall } from "./routes.ts";
import type { QueryPair } from "./routes.ts";
import { JustTCGUpstream } from "./upstream.ts";

// Deployed at launch preparation only (Blaze plan + paid JustTCG plan).
// Until then this runs in the Firebase Emulator Suite.

initializeApp();

const JUSTTCG_API_KEY = defineSecret("JUSTTCG_API_KEY");
const INSTALL_SALT = defineSecret("PRICING_INSTALL_SALT");
const JUSTTCG_TIER = defineString("JUSTTCG_TIER", { default: "starter" });

const PREFIX = "/v1/justtcg/";
const INSTALL_ID = /^[A-Za-z0-9-]{16,64}$/;

function isEmulator(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

export const justtcgProxy = onRequest(
  {
    region: "us-central1",
    secrets: [JUSTTCG_API_KEY, INSTALL_SALT],
    concurrency: 40,
    maxInstances: 10,
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
  },
  async (req, res) => {
    // App Check proves the caller is the genuine app on a real device
    // (App Attest). Without it this would be a free public JustTCG mirror,
    // which the provider's terms forbid.
    const token = req.header("X-Firebase-AppCheck");
    if (!isEmulator() || token) {
      try {
        if (!token) throw new Error("missing");
        await getAppCheck().verifyToken(token);
      } catch {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
    }

    const installID = req.header("X-ScanStash-Install") ?? "";
    if (!INSTALL_ID.test(installID)) {
      res.status(400).json({ error: "missing install identifier" });
      return;
    }

    if (!req.path.startsWith(PREFIX)) {
      res.status(404).json({ error: "unsupported path" });
      return;
    }

    const query: QueryPair[] = [];
    const url = new URL(req.originalUrl, "https://proxy.invalid");
    for (const [name, value] of url.searchParams) query.push({ name, value });

    const config = defaultConfig(JUSTTCG_TIER.value());
    const response = await handle(
      {
        method: req.method,
        path: req.path.slice(PREFIX.length),
        query,
        body: req.method === "POST" ? req.body : undefined,
        installHash: hashInstall(installID, INSTALL_SALT.value()),
        lane: req.header("X-ScanStash-Lane") === "background" ? "background" : "interactive",
      },
      {
        config,
        store: new FirestoreStore(getFirestore()),
        upstream: new JustTCGUpstream(config.upstreamBaseURL, () => JUSTTCG_API_KEY.value(), config.upstreamTimeoutMs),
        now: () => Date.now(),
        sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
        newOwner: () => randomUUID(),
      },
    );

    res.status(response.status);
    for (const [name, value] of Object.entries(response.headers)) res.setHeader(name, value);
    res.send(response.body);
  },
);
