// A local ember cloud for trying the whole path without Cloudflare: the
// Worker in miniflare (Google mocked) behind a small server on :8787 (PORT),
// and on :8789 (ADMIN_PORT) as the admin console's host. The Worker serves
// both web apps from dist/cloud-app (`pnpm run build:cloud`) as it does on
// Cloudflare. WebSockets (/v1/events, station presence) are piped to
// miniflare itself, listening on PORT + 1.
//   RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
// The console's admin is alice (ADMIN_EMAIL=bob@example.test makes it bob).
// Development-only routes (never in the Worker), on either port:
//   /__dev/login?user=alice  signs that account into the browser (on that origin) and goes to /
//   /__dev/account?user=alice  that account as JSON, for the core's `migrate` (native apps)
//   /__dev/credential?device=hex  a member's credential for alice's first workspace
import { readFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { connect } from "node:net";
import { extname, join, normalize } from "node:path";
import { Response as MFResponse } from "miniflare";
import { harness } from "./harness.ts";

const port = Number(process.env.PORT ?? 8787);
const adminPort = Number(process.env.ADMIN_PORT ?? port + 2);
const origin = `http://127.0.0.1:${port}`;
const adminOrigin = `http://127.0.0.1:${adminPort}`;
// The preview host: another port, so another origin (see src/preview.ts).
const previewPort = port + 3;
const previewOrigin = `http://127.0.0.1:${previewPort}`;
const app = join(import.meta.dirname, "..", "..", "dist", "cloud-app");
const TYPES: Record<string, string> = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".wasm": "application/wasm", ".woff2": "font/woff2" };

/** The assets binding over dist/cloud-app: a directory's index.html for its path with a slash, 404 for anything else. */
async function assets(request: Request): Promise<Response> {
  const path = normalize(decodeURIComponent(new URL(request.url).pathname));
  const file = path.endsWith("/") ? `${path}index.html` : path;
  try {
    const body = await readFile(join(app, file));
    return new MFResponse(body, { headers: { "content-type": TYPES[extname(file)] ?? "application/octet-stream" } }) as unknown as Response;
  } catch {
    return new MFResponse("Not found", { status: 404 }) as unknown as Response;
  }
}

// With AXIOM_TOKEN (and AXIOM_DATASET) in the environment, traces go to Axiom as they would from Cloudflare.
const h = await harness({ origin, adminOrigin, previewOrigin, assets, port: port + 1, relayUrl: process.env.RELAY ?? "http://127.0.0.1:3340", adminEmail: process.env.ADMIN_EMAIL ?? "alice@example.test", ...(process.env.AXIOM_TOKEN ? { axiom: "real" as const } : {}) });
const alice = h.as(await h.login("alice"));
const workspace = await (await alice("POST", "/v1/workspaces", { name: "Dev" })).json() as { id: string };
for (const name of ["studio", "mac-mini"]) {
  const enrollment = await (await alice("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name })).json() as { command: string };
  console.log(`ENROLL ${enrollment.command}`);
}

async function serve(base: string, req: IncomingMessage, res: ServerResponse) {
  const url = new URL(req.url ?? "/", base);
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
  if (url.pathname === "/__dev/credential") {
    const headers = { "access-control-allow-origin": "*", "content-type": "application/json" };
    const issued = await alice("POST", `/v1/workspaces/${workspace.id}/credential`, { device: url.searchParams.get("device") });
    return void res.writeHead(issued.status, headers).end(await issued.text());
  }
  // Everything else is the Worker's, on the host it was asked on.
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const headers = Object.fromEntries(Object.entries(req.headers).filter(([k, v]) => typeof v === "string" && !["host", "connection"].includes(k))) as Record<string, string>;
  const response = await (base === origin ? h.fetch : base === previewOrigin ? h.fetchPreview : h.fetchAdmin)(url.pathname + url.search, {
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
server.listen(port, "127.0.0.1", () => console.log(`READY ember cloud (dev) on :${port}`));
createServer(handle(adminOrigin)).listen(adminPort, "127.0.0.1", () => console.log(`READY admin console (dev) on :${adminPort}`));
createServer(handle(previewOrigin)).listen(previewPort, "127.0.0.1", () => console.log(`READY preview host (dev) on :${previewPort}`));

/** An account as the web app kept it in localStorage (what `migrate` takes). */
async function signIn(user: string) {
  const tokens = await h.login(user);
  return { sub: tokens.subject, email: tokens.email, name: tokens.name, picture: "", access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at };
}
