// A web service on this machine, reached through the admin API: GET
// /admin/api/preview/<port>/<path> is <path> of http://localhost:<port>,
// passed through as it is. It is how a client shows a page an agent serves
// here (a dev server, a report) — its requests come over the mesh like any
// other admin call, so they need no port open to anyone.
import { request as httpRequest, type IncomingHttpHeaders, type IncomingMessage, type ServerResponse } from "node:http";

/** Headers that belong to the hop to here (and the admin call's own), not to the service. */
const HOP = new Set(["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "authorization", "traceparent", "tracestate"]);
/** Answers the service gives that would stop its page from being shown framed on another origin. */
const FRAMING = new Set(["x-frame-options", "content-security-policy", "content-security-policy-report-only"]);

export function previewTarget(path: string): { port: number; path: string } | null {
  const match = /^\/preview\/(\d{1,5})(\/.*)?$/.exec(path);
  if (!match) return null;
  const port = Number(match[1]);
  return port >= 1 && port <= 65535 ? { port, path: match[2] ?? "/" } : null;
}

export function proxyPreview(req: IncomingMessage, res: ServerResponse, port: number, path: string): Promise<void> {
  const headers: IncomingHttpHeaders = {};
  for (const [name, value] of Object.entries(req.headers)) {
    if (!HOP.has(name) && !name.startsWith("x-ember-")) headers[name] = value;
  }
  headers.host = `localhost:${port}`;
  // The body goes back as it is: a client that cannot undo an encoding (a service worker's Response does not) gets
  // it plain.
  headers["accept-encoding"] = "identity";
  return new Promise((done) => {
    const upstream = httpRequest({ host: "localhost", port, method: req.method, path, headers }, (answer) => {
      const out: Record<string, string | string[]> = {};
      for (const [name, value] of Object.entries(answer.headers)) {
        if (value === undefined || HOP.has(name) || FRAMING.has(name)) continue;
        // A redirect to the service itself stays on the preview's path.
        out[name] = name === "location" && typeof value === "string" ? value.replace(new RegExp(`^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):${port}`), "") : value;
      }
      res.writeHead(answer.statusCode ?? 502, out);
      answer.pipe(res);
      answer.on("end", done);
      answer.on("error", () => { res.destroy(); done(); });
    });
    upstream.on("error", (error) => {
      if (!res.headersSent) {
        res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
        res.end(`这台机器上的 localhost:${port} 没有回应：${error.message}`);
      } else res.destroy();
      done();
    });
    req.pipe(upstream);
  });
}
