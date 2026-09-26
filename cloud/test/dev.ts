// A local ember cloud for trying the whole path without Cloudflare: the
// Worker in miniflare (Google mocked) behind a small server on :8787 (PORT)
// that also serves the web app from dist/cloud-app. WebSockets (/v1/events,
// station presence) are piped to miniflare itself, listening on PORT + 1.
//   RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
// Development-only routes (never in the Worker):
//   /__dev/login?user=alice  signs that account into the browser and goes to /
//   /__dev/account?user=alice  that account as JSON, for the core's `migrate` (native apps)
//   /__dev/grant?device=hex  a grant for the first station of alice's first workspace
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { connect } from "node:net";
import { extname, join, normalize } from "node:path";
import { harness } from "./harness.ts";

const port = Number(process.env.PORT ?? 8787);
const origin = `http://127.0.0.1:${port}`;
const h = await harness({ origin, port: port + 1, relayUrl: process.env.RELAY ?? "http://127.0.0.1:3340" });
const app = join(import.meta.dirname, "..", "..", "dist", "cloud-app");
const alice = h.as(await h.login("alice"));
const workspace = await (await alice("POST", "/v1/workspaces", { name: "Dev" })).json() as { id: string };
for (const name of ["studio", "mac-mini"]) {
  const enrollment = await (await alice("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name })).json() as { command: string };
  console.log(`ENROLL ${enrollment.command}`);
}

const TYPES: Record<string, string> = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".wasm": "application/wasm", ".woff2": "font/woff2" };

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", origin);
  if (url.pathname === "/__dev/account") {
    const account = await signIn(url.searchParams.get("user") ?? "alice");
    return void res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(account));
  }
  if (url.pathname === "/__dev/login") {
    const account = await signIn(url.searchParams.get("user") ?? "alice");
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
});
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
server.listen(port, "127.0.0.1", () => console.log(`READY ember cloud (dev) on :${port}`));

/** An account as the web app kept it in localStorage (what `migrate` takes). */
async function signIn(user: string) {
  const tokens = await h.login(user);
  return { sub: tokens.subject, email: tokens.email, name: tokens.name, picture: "", access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at };
}
