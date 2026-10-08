// A local still.fail cloud for trying the whole path without Cloudflare: its Workers
// in miniflare (Google mocked; see harness.ts) behind a small server on :8787
// (PORT), on :8789 (ADMIN_PORT) as the admin console's host, :8790 as the
// preview host and :8791 (PORT + 4) as the test channel's (app.youdid.wtf's: the
// web app's files, with what ember-web-beta adds; alice is let in, bob is not). The static sites come from dist/cloud-web, dist/cloud-admin and
// dist/cloud-preview (`pnpm run build:cloud`) as on Cloudflare. WebSockets
// (/v1/events, the relay) are piped to miniflare itself, listening on PORT + 1.
//   RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
// The console's admin is alice (ADMIN_EMAIL=bob@example.test makes it bob). SEED=600 fills it with made-up people.
// Development-only routes (never in the Worker), on either port:
//   /__dev/login?user=alice  signs that account into the browser (on that origin) and goes to /
//   /__dev/account?user=alice  that account as JSON, for the core's `migrate` (native apps)
//   /__dev/credential?device=hex  a mstill.fail's credential for alice's first workspace
// With PUSH_LOG=<file>, pushes work with a VAPID key made at start, and what the cloud pushes (to browsers, to FCM)
// is written there, a JSON line each (its body base64), instead of reaching a push service.
import { appendFileSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { connect } from "node:net";
import { extname, join, normalize } from "node:path";
import { Response as MFResponse } from "miniflare";
import { releaseType } from "../src/install.ts";
import { harness } from "./harness.ts";

const port = Number(process.env.PORT ?? 8787);
const adminPort = Number(process.env.ADMIN_PORT ?? port + 2);
const origin = `http://127.0.0.1:${port}`;
const adminOrigin = `http://127.0.0.1:${adminPort}`;
// The preview host: another port, so another origin (see src/preview.ts).
const previewPort = port + 3;
const previewOrigin = `http://127.0.0.1:${previewPort}`;
// The test channel's host: another origin again.
const betaPort = port + 4;
const betaOrigin = `http://127.0.0.1:${betaPort}`;
const dist = join(import.meta.dirname, "..", "..", "dist");
const TYPES: Record<string, string> = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".wasm": "application/wasm", ".woff2": "font/woff2" };

/** The static sites' files as the stand-in static Worker asks for them (/web/…, /admin/…, /preview/…); 404 for anything else. */
async function assets(request: Request): Promise<Response> {
  const [, site, ...rest] = normalize(decodeURIComponent(new URL(request.url).pathname)).split("/");
  const file = rest.join("/");
  try {
    const body = await readFile(join(dist, `cloud-${site}`, file));
    return new MFResponse(body, { headers: { "content-type": TYPES[extname(file)] ?? "application/octet-stream" } }) as unknown as Response;
  } catch {
    return new MFResponse("Not found", { status: 404 }) as unknown as Response;
  }
}

/** A VAPID key made now: its public point and private scalar, base64url. */
async function vapidKey(): Promise<{ publicKey: string; privateKey: string }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey) as JsonWebKey;
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey) as ArrayBuffer);
  return { publicKey: Buffer.from(raw).toString("base64url"), privateKey: jwk.d! };
}
const pushLog = process.env.PUSH_LOG;
const pushes = pushLog ? {
  vapid: await vapidKey(),
  push: (r: { url: string; method: string; headers: Record<string, string>; body: Uint8Array }) => {
    appendFileSync(pushLog, JSON.stringify({ ...r, body: Buffer.from(r.body).toString("base64") }) + "\n");
    return { status: 201 };
  },
} : {};

// With AXIOM_TOKEN (and AXIOM_DATASET) in the environment, traces go to Axiom as they would from Cloudflare.
const h = await harness({ clock: "real", ...pushes, origin, adminOrigin, previewOrigin, betaOrigin, assets, port: port + 1, relayUrl: process.env.RELAY ?? "http://127.0.0.1:3340", adminEmail: process.env.ADMIN_EMAIL ?? "alice@example.test", ...(process.env.AXIOM_TOKEN ? { axiom: "real" as const } : {}), ...(process.env.REVIEW_ACCOUNTS ? { reviewAccounts: process.env.REVIEW_ACCOUNTS } : {}) });
const aliceTokens = await h.login("alice");
const alice = h.as(aliceTokens);
// alice may use the test channel (the console's switch does the same).
await h.as(aliceTokens, "admin")("POST", `/v1/admin/users/${aliceTokens.subject}/beta`, { on: true });
const workspace = await (await alice("POST", "/v1/workspaces", { name: "Dev" })).json() as { id: string };
// SEED=600: that many made-up people, workspaces and stations, to see the admin's console as it is with many.
if (Number(process.env.SEED) > 0) {
  const directories: any = await h.mf.getDurableObjectNamespace("DIRECTORY", "api");
  await directories.get(directories.idFromName("primary")).seedPeople(Number(process.env.SEED));
}
// What dist/releases holds goes into the Worker's bucket too, for what the API reads of it: the changelog
// (changelog.json, `node scripts/changelog.ts`) and what each part has out (station.json, android/latest.json, web.json…).
try {
  const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: Uint8Array): Promise<unknown> };
  for (const file of await readdir(join(dist, "releases"), { recursive: true })) {
    const body = await readFile(join(dist, "releases", file)).catch(() => null);
    if (body) await bucket.put(file, body);
  }
} catch {
  // No dist/releases: nothing to put.
}
for (const name of ["studio", "mac-mini"]) {
  const enrollment = await (await alice("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name })).json() as { command: string };
  console.log(`ENROLL ${enrollment.command}`);
}

async function serve(base: string, req: IncomingMessage, res: ServerResponse) {
  const url = new URL(req.url ?? "/", base);
  // Releases as scripts/release.sh leaves them with RELEASE_DIR=dist/releases (the Worker's bucket is not here).
  const release = /^\/releases\/(.+)$/.exec(url.pathname)?.[1];
  const type = release ? releaseType(release) : null;
  if (release && type) {
    try {
      return void res.writeHead(200, { "content-type": type }).end(await readFile(join(dist, "releases", release)));
    } catch {
      return void res.writeHead(404).end("no such release in dist/releases");
    }
  }
  if (url.pathname === "/__dev/account") {
    const account = await signIn(url.searchParams.get("user") ?? "alice");
    return void res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(account));
  }
  if (url.pathname === "/__dev/login") {
    const account = await signIn(url.searchParams.get("user") ?? "alice");
    // Under the web app's key, and its key from before the rename (for a build of the web app from then).
    res.writeHead(200, { "content-type": "text/html" }).end(`<script>
      for (const key of ["stillfail.accounts", "ember.accounts"]) {
        const list = JSON.parse(localStorage.getItem(key) || "[]").filter((a) => a.sub !== ${JSON.stringify(account.sub)});
        localStorage.setItem(key, JSON.stringify([...list, ${JSON.stringify(account)}]));
      }
      location.replace("/");</script>`);
    return;
  }
  if (url.pathname === "/__dev/credential") {
    const headers = { "access-control-allow-origin": "*", "content-type": "application/json" };
    const issued = await alice("POST", `/v1/workspaces/${workspace.id}/credential`, { device: url.searchParams.get("device") });
    return void res.writeHead(issued.status, headers).end(await issued.text());
  }
  // Everything else is the Worker's, on the host it was asked on.
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const headers = Object.fromEntries(Object.entries(req.headers).filter(([k, v]) => typeof v === "string" && !["host", "connection"].includes(k))) as Record<string, string>;
  const response = await (base === origin ? h.fetch : base === previewOrigin ? h.fetchPreview : base === betaOrigin ? h.fetchBeta : h.fetchAdmin)(url.pathname + url.search, {
    method: req.method, headers, redirect: "manual",
    ...(chunks.length ? { body: Buffer.concat(chunks) } : {}),
  });
  res.writeHead(response.status, Object.fromEntries(response.headers)).end(Buffer.from(await response.arrayBuffer()));
}

/** A request that fails (the Worker's sign-in rate limit, say) answers 500 rather than ending the dev cloud. */
function handle(base: string) {
  return (req: IncomingMessage, res: ServerResponse) => void serve(base, req, res).catch((error: unknown) => {
    console.error(`${req.method} ${req.url}: ${String(error)}`);
    if (!res.headersSent) res.writeHead(500, { "content-type": "text/plain" });
    res.end(String(error));
  });
}

const server = createServer(handle(origin));
// The upgrade goes to miniflare byte for byte, Host included, so the Worker sees this origin.
server.on("upgrade", (req, socket, head) => {
  const upstream = connect(port + 1, "127.0.0.1", () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) lines.push(`${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`);
    upstream.write(lines.join("\r\n") + "\r\n\r\n");
    upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
});
server.listen(port, "127.0.0.1", () => console.log(`READY still.fail cloud (dev) on :${port}`));
createServer(handle(adminOrigin)).listen(adminPort, "127.0.0.1", () => console.log(`READY admin console (dev) on :${adminPort}`));
createServer(handle(previewOrigin)).listen(previewPort, "127.0.0.1", () => console.log(`READY preview host (dev) on :${previewPort}`));
// The test channel's events socket goes to miniflare as the main one's does.
const betaServer = createServer(handle(betaOrigin));
betaServer.on("upgrade", (req, socket, head) => server.emit("upgrade", req, socket, head));
betaServer.listen(betaPort, "127.0.0.1", () => console.log(`READY beta (dev) on :${betaPort}`));

/** An account as the web app kept it in localStorage (what `migrate` takes). */
async function signIn(user: string) {
  const tokens = await h.login(user);
  return { sub: tokens.subject, email: tokens.email, name: tokens.name, picture: "", access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at };
}
