// A fake module for test/modules.test.ts (docs/station-modules.md): HTTP/1.1 on STILLFAIL_MODULE_SOCKET. Each start is
// a JSON line in <STILLFAIL_MODULE_DIR>/starts (its pid and what it was told), so a test knows its token. It answers:
//   GET /manifest        {viewerWrites: ["/progress/[^/]+"]}
//   * /echo              what it was asked: method, path, the viewer it was told, the headers, the body's size and sha256
//   PUT /progress/:id    {saved: id}
//   GET /big?n=          n bytes, in parts
//   GET /events          an event stream, an event every 20 ms; let go of, it writes <dir>/closed
//   GET /crash           ends the process (exit 3)
// It ends when its stdin closes (the station gone), as a module does.
import { createHash } from "node:crypto";
import { appendFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";

const dir = process.env.STILLFAIL_MODULE_DIR;
appendFileSync(
  join(dir, "starts"),
  JSON.stringify({ pid: process.pid, id: process.env.STILLFAIL_MODULE_ID, socket: process.env.STILLFAIL_MODULE_SOCKET, station: process.env.STILLFAIL_STATION_SOCKET, token: process.env.STILLFAIL_STATION_TOKEN, extra: process.env.FAKE_EXTRA ?? null }) + "\n",
);
process.stdin.on("end", () => process.exit(0));
process.stdin.resume();

const json = (res, status, value) => res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(value));

createServer(async (req, res) => {
  const url = new URL(req.url, "http://module");
  if (url.pathname === "/manifest") return json(res, 200, { viewerWrites: ["/progress/[^/]+"] });
  if (url.pathname === "/echo") {
    const hash = createHash("sha256");
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      hash.update(chunk);
    }
    return json(res, 200, { method: req.method, path: req.url, viewer: req.headers["stillfail-viewer"] ?? null, headers: req.headers, size, sha256: hash.digest("hex") });
  }
  if (req.method === "PUT" && url.pathname.startsWith("/progress/")) return json(res, 200, { saved: url.pathname.slice("/progress/".length) });
  if (url.pathname === "/big") {
    const n = Number(url.searchParams.get("n"));
    res.writeHead(200, { "content-type": "application/octet-stream", "content-length": String(n) });
    const part = Buffer.alloc(1 << 20, 7);
    for (let sent = 0; sent < n; sent += part.length) {
      if (!res.write(part.subarray(0, Math.min(part.length, n - sent)))) await new Promise((r) => res.once("drain", r));
    }
    return res.end();
  }
  if (url.pathname === "/events") {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store" });
    let n = 0;
    const timer = setInterval(() => res.write(`data: ${n++}\n\n`), 20);
    res.on("close", () => {
      clearInterval(timer);
      writeFileSync(join(dir, "closed"), "1");
    });
    return;
  }
  if (url.pathname === "/crash") process.exit(3);
  json(res, 404, { error: "no such thing" });
}).listen(process.env.STILLFAIL_MODULE_SOCKET);
