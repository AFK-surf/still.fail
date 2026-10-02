// Members' connections over the mesh (mesh/station/src/main.rs `serve`, `relay_request`). Wire format, on ALPN
// `stillfail/admin/1` (and `ember/admin/1`, as clients from before the rename ask): the first bidirectional stream
// carries credentials, one JSON line each, answered with one JSON line (a later line renews); every other stream is
// one request: a JSON head line `{method, path, headers}`, then the body until the stream finishes, answered by a
// JSON head line `{status, headers}` and the response body.
import type { Admin } from "../api/admin.ts";
import { langOfCore, queryPairs } from "../api/request.ts";
import type { Cloud } from "../cloud/state.ts";
import { log } from "../ops/log.ts";
import { nowSecs } from "../ops/files.ts";
import { type Admitted, revoked, verifyMember } from "./credential.ts";
import type { Connection, Stream } from "./native.ts";

export const ALPN = Buffer.from("stillfail/admin/1");
export const FORMER_ALPN = Buffer.from("ember/admin/1");
// Keep old clients admitted until protocol-2 clients have reached the stable channel.
const MIN_CLIENT_PROTOCOL = 1;
const MAX_HEAD = 16 * 1024;
// Files sent to a session go through here; the station caps them at 50 MB.
const MAX_BODY = 64 * 1024 * 1024;
/// Headers of one hop, not of what is relayed.
const HOP = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length"];

/// One JSON line at a time from a stream, then the rest of it.
export class Reader {
  carry: Buffer = Buffer.alloc(0);
  stream: Stream;
  constructor(stream: Stream) {
    this.stream = stream;
  }

  async line(): Promise<any | null> {
    for (;;) {
      const at = this.carry.indexOf(10);
      if (at >= 0) {
        const line = this.carry.subarray(0, at);
        this.carry = this.carry.subarray(at + 1);
        return JSON.parse(line.toString());
      }
      if (this.carry.length > MAX_HEAD) throw new Error("head too large");
      const more = await this.stream.read();
      if (more === null) {
        if (this.carry.length === 0) return null;
        throw new Error("stream ended mid-line");
      }
      this.carry = Buffer.concat([this.carry, more]);
    }
  }

  async rest(): Promise<Buffer> {
    const parts = [this.carry];
    let size = this.carry.length;
    for (let more = await this.stream.read(); more; more = await this.stream.read()) {
      parts.push(more);
      size += more.length;
      if (size > MAX_BODY) throw new Error("request body too large");
    }
    return Buffer.concat(parts);
  }
}

export const writeLine = (stream: Stream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));

export type Members = {
  cloud: Cloud;
  admin: Admin;
  /// Whether the station answers now (its parts started; not handing over).
  up(): boolean;
};

/// One member's connection: the credential first, nothing served before it checks out; then a request a stream.
export async function serve(m: Members, conn: Connection) {
  if (m.cloud.removed()) {
    conn.close(2, "station_removed");
    throw new Error("station removed");
  }
  const device = conn.remoteId();
  const first = await conn.acceptBi();
  if (!first) return;
  const credentials = new Reader(first);
  const state = () => m.cloud.state!;
  const check = (line: any) => verifyMember(typeof line?.credential === "string" ? line.credential : "", state().grant_keys, state().workspace, device, state().revocations);
  const hello = await credentials.line();
  if (hello === null) throw new Error("no credential");
  let current: Admitted;
  try {
    current = check(hello);
  } catch (e) {
    await writeLine(first, { error: (e as Error).message }).catch(() => {});
    await first.finish().catch(() => {});
    setTimeout(() => conn.close(1, "credential_refused"), 200);
    throw e;
  }
  const protocol = Number.isInteger(hello.protocol) && hello.protocol >= 0 ? hello.protocol : 1;
  if (protocol < MIN_CLIENT_PROTOCOL) {
    await writeLine(first, {
      code: "client_upgrade_required",
      error: "Please update still.fail to the latest version, or reload the web page, before connecting to this station.",
      required_protocol: MIN_CLIENT_PROTOCOL,
      update_url: "https://still.fail",
    });
    await first.finish().catch(() => {});
    setTimeout(() => conn.close(4, "client_upgrade_required"), 200);
    throw new Error("client upgrade required");
  }
  await writeLine(first, { ok: true, station: state().name, expires_at: current.exp });
  log.info("mesh", "client connected", { email: current.viewer.email, device: device.slice(0, 12) });

  // The connection ends when its credential runs out or is revoked, or the station leaves its workspace: checked on
  // every change of the cloud's state, and when the credential runs out.
  const gone = () => {
    if (m.cloud.removed()) conn.close(2, "station_removed");
    else if (revoked(current, state().revocations)) conn.close(3, "credential_revoked");
    else if (current.exp <= nowSecs()) conn.close(3, "credential_expired");
    else return false;
    return true;
  };
  let expiry: ReturnType<typeof setTimeout> | undefined;
  const watchExpiry = () => {
    clearTimeout(expiry);
    expiry = setTimeout(gone, Math.max(0, current.exp * 1000 - Date.now()) + 50);
  };
  watchExpiry();
  const unlisten = m.cloud.listen(gone);
  // Renewals on the credential stream.
  (async () => {
    for (let line = await credentials.line().catch(() => null); line !== null; line = await credentials.line().catch(() => null)) {
      let reply;
      try {
        current = check(line);
        watchExpiry();
        reply = { ok: true, expires_at: current.exp };
      } catch (e) {
        reply = { error: (e as Error).message };
      }
      await writeLine(first, reply).catch(() => {});
    }
  })();

  try {
    for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
      if (gone()) return;
      const viewer = current.viewer;
      request(m, stream, viewer, conn).catch((e) => log.info("mesh", "request failed", { error: (e as Error).message }));
    }
  } finally {
    clearTimeout(expiry);
    unlisten();
  }
}

/// One request: to the admin API in this process.
async function request(m: Members, stream: Stream, viewer: Admitted["viewer"], _conn: Connection) {
  const reader = new Reader(stream);
  const head = await reader.line();
  if (head === null) return;
  const method: string = typeof head.method === "string" ? head.method : "GET";
  const path: string = typeof head.path === "string" ? head.path : "";
  const answer = async (status: number, body: unknown) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(typeof body === "string" ? body : JSON.stringify(body)));
    await stream.finish();
  };
  if (!path.startsWith("/admin/api/") || path.includes("..")) {
    return answer(404, '{"error":"only the admin API is reachable over the mesh"}');
  }
  const body = await reader.rest();
  // The caller's headers go on, but not those of the hop, nor any of the station's own: who is asking is only what
  // the credential says.
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(head.headers ?? {})) {
    const lower = name.toLowerCase();
    if (HOP.includes(lower) || lower.startsWith("x-stillfail-") || lower.startsWith("x-ember-") || lower === "traceparent" || lower === "tracestate") continue;
    if (typeof value === "string") headers[name] = value;
  }
  if (!m.up()) return answer(502, { error: "station unreachable: not started" });
  const rest = path.slice("/admin/api".length);
  const at = rest.indexOf("?");
  const response = await m.admin.handle({
    method,
    path: at < 0 ? rest : rest.slice(0, at),
    query: at < 0 ? [] : queryPairs(rest.slice(at + 1)),
    headers,
    body,
    viewer,
    lang: langOfCore(headers),
  });
  await writeLine(stream, { status: response.status, headers: response.headers });
  if (Buffer.isBuffer(response.body)) await stream.write(response.body);
  else for await (const chunk of response.body) await stream.write(chunk);
  await stream.finish();
}
