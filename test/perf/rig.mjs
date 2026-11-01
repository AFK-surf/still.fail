// What the perf scripts share: Playwright and its Chromium, and a build's web app served against a cloud.
import { createServer, request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { extname, join, normalize } from "node:path";
import { connect } from "node:net";
import { connect as tlsConnect } from "node:tls";

export async function playwright() {
  for (const name of [process.env.PLAYWRIGHT_MODULE, "playwright-core", "playwright"].filter(Boolean)) {
    try { return await import(name); } catch {}
  }
  throw new Error("no Playwright: `npm i playwright-core` somewhere Node finds it, or set PLAYWRIGHT_MODULE");
}

export function chromium() {
  if (process.env.CHROMIUM_EXECUTABLE) return process.env.CHROMIUM_EXECUTABLE;
  const cache = join(homedir(), "Library/Caches/ms-playwright");
  const found = existsSync(cache) && readdirSync(cache).filter((d) => /^chromium-\d+$/.test(d)).sort().at(-1);
  const app = found && join(cache, found, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
  return app && existsSync(app) ? app : undefined;
}

/**
 * Serves the build's web app (`root`, a dist/cloud-web) at /: its files, and the web's own React pages (web.html) for
 * its pages; the rest (the API, /auth, /__dev, the core's sockets) goes on to the cloud as if asked there (Host and Origin its own).
 */
export function proxy(root, cloud) {
  const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".wasm": "application/wasm", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json" };
  const tls = cloud.protocol === "https:";
  const port = Number(cloud.port || (tls ? 443 : 80));
  const theirs = (headers) => ({ ...headers, host: cloud.host, ...(headers.origin ? { origin: cloud.origin } : {}) });
  const pass = (req, res) => {
    const up = (tls ? httpsRequest : httpRequest)({ host: cloud.hostname, port, path: req.url, method: req.method, headers: theirs(req.headers) }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
    up.on("error", () => res.destroy());
    req.pipe(up);
  };
  const SERVERS = /^\/(v1|auth|__dev|releases)(\/|$)/;
  const s = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (req.method !== "GET" || SERVERS.test(path)) return pass(req, res);
    const file = normalize(join(root, path));
    const hit = file.startsWith(root) && existsSync(file) && statSync(file).isFile() ? file : !extname(path) ? join(root, "web.html") : null;
    if (!hit) return pass(req, res);
    res.writeHead(200, { "content-type": types[extname(hit)] ?? "application/octet-stream" });
    res.end(readFileSync(hit));
  });
  s.on("upgrade", (req, socket, head) => {
    const opened = () => {
      up.write(`${req.method} ${req.url} HTTP/1.1\r\n${Object.entries(theirs(req.headers)).map(([k, v]) => `${k}: ${v}`).join("\r\n")}\r\n\r\n`);
      up.write(head);
      up.pipe(socket);
      socket.pipe(up);
    };
    const up = tls ? tlsConnect({ host: cloud.hostname, port, servername: cloud.hostname }, opened) : connect(port, cloud.hostname, opened);
    up.on("error", () => socket.destroy());
    socket.on("error", () => up.destroy());
  });
  return new Promise((resolve) => s.listen(0, "127.0.0.1", () => resolve(s)));
}
