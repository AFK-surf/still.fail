// Prototype: a still.fail station in TypeScript, on Node 22.18+ as is (types stripped, no build). Its iroh is the
// prebuilt addon in ../native; the rest is here: the mesh's wire format and member credentials as
// mesh/station/src/main.rs has them (`serve`, `relay_request`), and the admin API's reads (./admin, ported from
// mesh/app/src/admin) over the station's own database.
//
// node src/main.ts --data <dir> [--no-discovery]: <dir> as a station's (mesh/cloud.json, mesh/secret.key,
// stillfail.db). Where it listens goes to <dir>/ts-station.json.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Admitted, revoked, verifyMember } from "./credential.ts";
import { HttpError, chats, entries } from "./admin/views.ts";
import { openStore } from "./admin/store.ts";

const ALPN = Buffer.from("stillfail/admin/1");
const FORMER_ALPN = Buffer.from("ember/admin/1");
const MIN_CLIENT_PROTOCOL = 1;
const MAX_HEAD = 16 * 1024;
const MAX_BODY = 64 * 1024 * 1024;

type Native = {
  bind(options: { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; discovery?: boolean }): Promise<Endpoint>;
};
type Endpoint = { id(): string; sockets(): string[]; accept(): Promise<Connection | null> };
type Connection = { remoteId(): string; acceptBi(): Promise<Stream | null>; close(code: number, reason: string): void };
type Stream = { read(): Promise<Buffer | null>; write(bytes: Buffer): Promise<void>; finish(): Promise<void> };

const args = process.argv.slice(2);
const data = args[args.indexOf("--data") + 1];
const native: Native = loadNative(process.env.STILLFAIL_MESH_NATIVE ?? new URL("../native/target/release/libstillfail_mesh_native.dylib", import.meta.url).pathname);
const state = JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8"));
const store = openStore(data);

function loadNative(path: string): Native {
  const module = { exports: {} as Native };
  process.dlopen(module, path);
  return module.exports;
}

const endpoint = await native.bind({
  secretKey: readFileSync(join(data, "mesh", "secret.key")),
  alpns: [ALPN, FORMER_ALPN],
  relayUrls: [state.relay_url, ...(state.relay_urls ?? [])].filter((u, i, all) => u && all.indexOf(u) === i),
  discovery: !args.includes("--no-discovery"),
});
writeFileSync(join(data, "ts-station.json"), JSON.stringify({ id: endpoint.id(), sockets: endpoint.sockets(), pid: process.pid }));
console.error(`ts-station: ${endpoint.id()} on ${endpoint.sockets().join(", ")}`);

for (let conn = await endpoint.accept(); conn; conn = await endpoint.accept()) {
  serve(conn).catch((error) => console.error(`ts-station: connection ended: ${error.message}`));
}

// ---- the wire: one JSON line, then bytes (mesh/station/src/main.rs `read_line`, `write_line`) ----

class Reader {
  carry = Buffer.alloc(0);
  constructor(readonly stream: Stream) {}

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

const writeLine = (stream: Stream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));
const now = () => Math.floor(Date.now() / 1000);

// ---- a connection: its credential first, then a request a stream (`serve`) ----

async function serve(conn: Connection) {
  const device = conn.remoteId();
  const first = await conn.acceptBi();
  if (!first) return;
  const credentials = new Reader(first);
  const check = (line: any) => verifyMember(typeof line?.credential === "string" ? line.credential : "", state.grant_keys, state.workspace, device, state.revocations ?? []);
  const hello = await credentials.line();
  if (hello === null) throw new Error("no credential");
  let current: Admitted;
  try {
    current = check(hello);
  } catch (error) {
    await writeLine(first, { error: (error as Error).message }).catch(() => {});
    await first.finish().catch(() => {});
    setTimeout(() => conn.close(1, "credential_refused"), 200);
    throw error;
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
  await writeLine(first, { ok: true, station: state.name, expires_at: current.exp });
  console.error(`ts-station: client connected: ${current.viewer.email} ${device.slice(0, 12)}`);

  // Renewals on the credential stream; the connection closes when the credential runs out or is revoked.
  (async () => {
    for (let line = await credentials.line().catch(() => null); line !== null; line = await credentials.line().catch(() => null)) {
      let reply;
      try {
        current = check(line);
        reply = { ok: true, expires_at: current.exp };
      } catch (error) {
        reply = { error: (error as Error).message };
      }
      await writeLine(first, reply);
    }
  })();
  const watch = setInterval(() => {
    if (current.exp <= now() || revoked(current, state.revocations ?? [])) {
      conn.close(3, revoked(current, state.revocations ?? []) ? "credential_revoked" : "credential_expired");
      clearInterval(watch);
    }
  }, 5000);

  try {
    for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
      if (current.exp <= now() || revoked(current, state.revocations ?? [])) {
        conn.close(3, "credential_expired");
        return;
      }
      const viewer = current.viewer;
      request(stream, viewer).catch((error) => console.error(`ts-station: request failed: ${error.message}`));
    }
  } finally {
    clearInterval(watch);
  }
}

// ---- a request (`relay_request`, with the admin API in this process) ----

async function request(stream: Stream, viewer: Admitted["viewer"]) {
  const reader = new Reader(stream);
  const head = await reader.line();
  if (head === null) return;
  const method: string = head.method ?? "GET";
  const path: string = head.path ?? "";
  const answer = async (status: number, body: unknown) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(JSON.stringify(body)));
    await stream.finish();
  };
  if (!path.startsWith("/admin/api/") || path.includes("..")) {
    return answer(404, { error: "only the admin API is reachable over the mesh" });
  }
  await reader.rest();
  const url = new URL(path.slice("/admin/api".length), "http://stillfail");
  // The first of a name counts, as admin/mod.rs `query_pairs` has it.
  const pairs = [...url.searchParams.entries()];
  try {
    if (method === "GET" && url.pathname === "/chats") return await answer(200, chats(store, viewer, url.searchParams.get("archived") === "1"));
    const thread = url.pathname.match(/^\/threads\/(\d+)\/entries$/);
    if (method === "GET" && thread) return await answer(200, entries(store, viewer, Number(thread[1]), pairs));
    return await answer(404, { error: "not in this prototype" });
  } catch (error) {
    return answer(error instanceof HttpError ? error.status : 500, { error: (error as Error).message });
  }
}
