// A local ember cloud for trying the whole path without Cloudflare: the
// Worker in miniflare (Google mocked) behind a small server on :8787 that
// also serves the web app from dist/cloud-app.
//   RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
// Development-only routes (never in the Worker):
//   /__dev/login?user=alice  signs that account into the browser and goes to /
//   /__dev/grant?device=hex  a grant for the first station of alice's first workspace
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { harness } from "./harness.ts";

const origin = "http://127.0.0.1:8787";
const h = await harness({ origin, relayUrl: process.env.RELAY ?? "http://127.0.0.1:3340" });
const app = join(import.meta.dirname, "..", "..", "dist", "cloud-app");
const alice = h.as(await h.login("alice"));
const workspace = await (await alice("POST", "/v1/workspaces", { name: "Dev" })).json() as { id: string };
const enrollment = await (await alice("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name: "dev-station" })).json() as { command: string };
console.log(`ENROLL ${enrollment.command}`);

const TYPES: Record<string, string> = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".wasm": "application/wasm", ".woff2": "font/woff2" };

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", origin);
  if (url.pathname === "/__dev/login") {
    const tokens = await h.login(url.searchParams.get("user") ?? "alice");
    const account = { sub: tokens.subject, email: tokens.email, name: tokens.name, picture: "", access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at };
    res.writeHead(200, { "content-type": "text/html" }).end(`<script>
      const list = JSON.parse(localStorage.getItem("ember.accounts") || "[]").filter((a) => a.sub !== ${JSON.stringify(account.sub)});
      localStorage.setItem("ember.accounts", JSON.stringify([...list, ${JSON.stringify(account)}]));
      location.replace("/");</script>`);
    return;
  }
  if (url.pathname === "/__dev/grant") {
    const view = await (await alice("GET", `/v1/workspaces/${workspace.id}`)).json() as { stations: { id: string }[] };
    const headers = { "access-control-allow-origin": "*", "content-type": "application/json" };
    if (!view.stations[0]) return void res.writeHead(409, headers).end(JSON.stringify({ error: "no station enrolled yet" }));
    const granted = await alice("POST", `/v1/workspaces/${workspace.id}/stations/${view.stations[0].id}/grant`, { device: url.searchParams.get("device") });
    return void res.writeHead(granted.status, headers).end(await granted.text());
  }
  if (/^\/(v1|\.well-known|pkarr)\/|^\/healthz$/.test(url.pathname)) {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const headers = Object.fromEntries(Object.entries(req.headers).filter(([k, v]) => typeof v === "string" && !["host", "connection"].includes(k))) as Record<string, string>;
    const response = await h.fetch(url.pathname + url.search, {
      method: req.method, headers, redirect: "manual",
      ...(chunks.length ? { body: Buffer.concat(chunks) } : {}),
    });
    res.writeHead(response.status, Object.fromEntries(response.headers)).end(Buffer.from(await response.arrayBuffer()));
    return;
  }
  // The web app, with client routes falling back to index.html.
  const file = normalize(url.pathname).replace(/^\/+/, "");
  for (const candidate of extname(file) ? [file, "index.html"] : ["index.html"]) {
    try {
      const body = await readFile(join(app, candidate));
      return void res.writeHead(200, { "content-type": TYPES[extname(candidate)] ?? "application/octet-stream" }).end(body);
    } catch { /* next */ }
  }
  res.writeHead(404).end();
}).listen(8787, "127.0.0.1", () => console.log("READY ember cloud (dev) on :8787"));
