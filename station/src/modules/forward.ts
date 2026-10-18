// A request of the admin API passed on to a module (modules/modules.ts), over its socket as HTTP/1.1: the method, the
// module's own path and the query, the caller's headers but those of the hop and any `stillfail-viewer` they sent, and
// who asks as the station verified them (`stillfail-viewer`); the body as it comes. Its answer comes back as it comes
// too: a part of a video, a thumbnail, an event stream that lasts. Let go of (the caller gone), the request to the module
// is ended with it.
import { request } from "node:http";
import { once } from "node:events";
import type { Answer } from "../api/request.ts";

/// Headers of one hop, not passed on. `accept-encoding` neither: the station compresses for the client that asks
/// (mesh/compress.ts), and a module's own encoding is one a client may not read.
const HOP = new Set(["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length", "accept-encoding"]);
const VIEWER = "stillfail-viewer";

export type Forwarded = { method: string; path: string; headers: Record<string, string>; body: Buffer | AsyncIterable<Buffer> };

/// `r` asked of what listens at `socket`, for the viewer `viewer` says (modules.ts viewerHeader; none: the station asks
/// for itself). Throws when it does not answer (not listening, gone before its answer's head).
export function forward(socket: string, r: Forwarded, viewer: string | null): Promise<Answer> {
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(r.headers)) {
    const lower = name.toLowerCase();
    if (!HOP.has(lower) && lower !== VIEWER) headers[lower] = value;
  }
  if (viewer !== null) headers[VIEWER] = viewer;
  const whole = Buffer.isBuffer(r.body) ? r.body : null;
  if (whole !== null) headers["content-length"] = String(whole.length);
  return new Promise<Answer>((resolve, reject) => {
    const req = request({ socketPath: socket, method: r.method, path: r.path, headers }, (res) => {
      const joined: Record<string, string> = {};
      for (const [name, value] of Object.entries(res.headers)) {
        if (value === undefined || HOP.has(name)) continue;
        joined[name] = Array.isArray(value) ? value.join(", ") : value;
      }
      // The body as it comes; let go of, the module's answer is ended (an event stream's too).
      resolve({ status: res.statusCode ?? 502, headers: joined, body: res as AsyncIterable<Buffer> });
    });
    req.on("error", reject);
    if (whole !== null) {
      req.end(whole);
      return;
    }
    void (async () => {
      try {
        for await (const chunk of r.body as AsyncIterable<Buffer>) if (!req.write(chunk)) await once(req, "drain");
        req.end();
      } catch (e) {
        req.destroy(e as Error);
      }
    })();
  });
}

/// A GET of the module's own (its manifest): status and body, whole.
export async function ask(socket: string, path: string): Promise<{ status: number; body: Buffer }> {
  const answer = await forward(socket, { method: "GET", path, headers: {}, body: Buffer.alloc(0) }, null);
  const parts: Buffer[] = [];
  for await (const chunk of answer.body as AsyncIterable<Buffer>) parts.push(chunk);
  return { status: answer.status, body: Buffer.concat(parts) };
}
