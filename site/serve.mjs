// Serves the built site (dist/site, `pnpm build:site`) and forwards /_llm/opencode/* to OpenCode Go, which lets no
// page call it across origins: the demo's agent reaches its model through here with the visitor's own key, which is
// passed on and kept nowhere. `PORT=… node site/serve.mjs`. The site's host has to forward the same path.
import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../dist/site/", import.meta.url));
const UPSTREAM = "https://opencode.ai/zen/go";
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webp": "image/webp", ".woff2": "font/woff2", ".json": "application/json", ".webmanifest": "application/manifest+json" };
const FORWARDED = ["content-type", "x-api-key", "authorization", "anthropic-version", "anthropic-beta", "x-opencode-session"];

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://site");
  if (url.pathname.startsWith("/_llm/opencode/")) {
    if (req.method !== "POST" && req.method !== "GET") { res.writeHead(405).end(); return; }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const headers = Object.fromEntries(FORWARDED.flatMap((h) => (req.headers[h] ? [[h, String(req.headers[h])]] : [])));
    try {
      const up = await fetch(UPSTREAM + url.pathname.slice("/_llm/opencode".length) + url.search, { method: req.method, headers, ...(req.method === "POST" ? { body: Buffer.concat(chunks) } : {}) });
      res.writeHead(up.status, { "content-type": up.headers.get("content-type") ?? "application/json", "cache-control": "no-store" });
      res.end(Buffer.from(await up.arrayBuffer()));
    } catch (e) {
      res.writeHead(502, { "content-type": "application/json" }).end(JSON.stringify({ error: { message: `转发失败：${e.message}` } }));
    }
    return;
  }
  let file = normalize(join(ROOT, decodeURIComponent(url.pathname)));
  if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(file, "index.html");
  if (!existsSync(file)) { res.writeHead(404).end("Not found"); return; }
  res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" });
  createReadStream(file).pipe(res);
}).listen(Number(process.env.PORT ?? 4173), "127.0.0.1");
