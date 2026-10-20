// One bounded, read-only synchronization for WidgetKit. No application Core,
// database, event subscriptions, message histories or foreground attention.
import { Effect } from "effect";
import { Accounts } from "./accounts.ts";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import type { Iroh, IrohConnection, IrohStream } from "./iroh.ts";
import { lockClaim } from "./lock.ts";
import { fromUtf8, toJsonBytes, utf8 } from "./util.ts";
import { presentRow } from "./decisions.ts";
import { rowState, rowStateLine, session } from "./present.ts";

type J = any;
export type WidgetScope = { account: string; workspace: string };
export type WidgetReading = { name: string; chats: J; archivedAt: number[] };
const fail = (code: string) => new CoreError(code, code);

// Heads are capped separately from list bodies. A malicious/oversized reply
// fails the refresh, retaining the old snapshot instead of exhausting the extension.
class StreamReader {
  private carry: Uint8Array = new Uint8Array(0);
  private readonly stream: IrohStream;
  constructor(stream: IrohStream) { this.stream = stream; }
  line(): Effect.Effect<J, unknown> {
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        const at = this.carry.indexOf(10);
        if (at >= 0) {
          const line = fromUtf8(this.carry.subarray(0, at));
          this.carry = this.carry.slice(at + 1);
          return yield* Effect.try(() => JSON.parse(line));
        }
        if (this.carry.length > 65536) return yield* Effect.fail(fail("widget_reply_too_large"));
        const part = yield* this.stream.read();
        if (part === null) return yield* Effect.fail(fail("widget_incomplete_reply"));
        const joined = new Uint8Array(this.carry.length + part.length);
        joined.set(this.carry); joined.set(part, this.carry.length); this.carry = joined;
      }
    });
  }
  json(): Effect.Effect<J, unknown> {
    return Effect.gen({ self: this }, function* () {
      const parts: Uint8Array[] = [this.carry]; let size = this.carry.length;
      for (;;) {
        const part = yield* this.stream.read();
        if (part === null) break;
        size += part.length;
        if (size > 4 * 1024 * 1024) return yield* Effect.fail(fail("widget_reply_too_large"));
        parts.push(part);
      }
      const joined = new Uint8Array(size); let offset = 0;
      for (const part of parts) { joined.set(part, offset); offset += part.length; }
      return yield* Effect.try(() => JSON.parse(fromUtf8(joined)));
    });
  }
}

function readList(conn: IrohConnection, path: string): Effect.Effect<J[], unknown> {
  return Effect.acquireUseRelease(conn.openBi(), (stream) => Effect.gen(function* () {
    yield* stream.write(utf8(`${JSON.stringify({ method: "GET", path, headers: {} })}\n`));
    yield* stream.finish();
    const reader = new StreamReader(stream);
    const head = yield* reader.line();
    if (head?.status !== 200) return yield* Effect.fail(fail("widget_station_refused"));
    const rows = yield* reader.json();
    if (!Array.isArray(rows)) return yield* Effect.fail(fail("widget_bad_rows"));
    return rows;
  }), (stream) => Effect.sync(() => stream.reset(0)));
}

export function readWidget(host: Host, iroh: Iroh, scope: WidgetScope): Effect.Effect<WidgetReading, unknown> {
  return Effect.gen(function* () {
    const accounts = yield* Accounts.load(host);
    if (!accounts.list().some((a) => a.sub === scope.account)) return yield* Effect.fail(fail("widget_signed_out"));
    const request = (method: string, path: string, body?: J): Effect.Effect<J, unknown> => Effect.gen(function* () {
      const token = yield* accounts.accessToken(scope.account);
      const response = yield* host.fetch({ method, url: host.cloudOrigin() + path,
        headers: [["authorization", `Bearer ${token}`], ["content-type", "application/json"]], body: body === undefined ? null : toJsonBytes(body) });
      if (response.status < 200 || response.status >= 300) return yield* Effect.fail(fail(response.status === 401 ? "widget_signed_out" : response.status === 403 || response.status === 404 ? "widget_scope_removed" : "widget_cloud_failed"));
      return yield* Effect.try(() => JSON.parse(fromUtf8(response.body)));
    });
    const workspace = yield* request("GET", `/v1/workspaces/${encodeURIComponent(scope.workspace)}`);
    if (!Array.isArray(workspace?.stations)) return yield* Effect.fail(fail("widget_bad_workspace"));
    const base = yield* host.storageGet("device");
    if (!base || base.length !== 32) return yield* Effect.fail(fail("widget_not_configured"));
    // A separate ephemeral endpoint avoids competing with the foreground app's
    // endpoint. The existing, confirmed device signs it for locked workspaces.
    const seed = new Uint8Array(32); host.randomBytes(seed);
    const me = yield* request("GET", "/v1/me");
    const own = Array.isArray(me.relay_urls) ? me.relay_urls : [me.relay_url];
    const relays: string[] = [...new Set([...own, ...(Array.isArray(workspace.relays) ? workspace.relays : [])])].filter((v): v is string => typeof v === "string" && /^https?:\/\//.test(v));
    return yield* Effect.acquireUseRelease(iroh.bind({ secretKey: seed, relayUrls: relays, lookup: true, relayOnly: false }), (endpoint) => Effect.gen(function* () {
      const claim = lockClaim(base, scope.workspace, endpoint.id());
      if (workspace.locked) {
        const lock = yield* request("GET", `/v1/workspaces/${encodeURIComponent(scope.workspace)}/lock`);
        if (Array.isArray(lock?.entries)) claim.entries = lock.entries;
      }
      const grant = yield* request("POST", `/v1/workspaces/${encodeURIComponent(scope.workspace)}/credential`, {
        device: endpoint.id(), base: claim.device, proof: claim.proof, kind: "app", label: "still.fail widgets",
      });
      if (typeof grant?.credential !== "string") return yield* Effect.fail(fail("widget_bad_credential"));
      const rows: J[] = [], archivedAt: number[] = [];
      // Bound peak memory: process one station and one list at a time, keeping
      // only task metadata and calendar timestamps, never histories or messages.
      for (const station of workspace.stations) {
        if (typeof station?.id !== "string" || !/^[0-9a-f]{64}$/.test(station.id)) return yield* Effect.fail(fail("widget_bad_station"));
        yield* Effect.acquireUseRelease(endpoint.connect({ id: station.id, relays }, utf8("stillfail/admin/1"), [utf8("ember/admin/1")]), (conn) => Effect.gen(function* () {
          const control = yield* conn.openBi();
          yield* control.write(utf8(`${JSON.stringify({ credential: grant.credential, protocol: 2, lock: claim })}\n`));
          const hello = yield* new StreamReader(control).line();
          if (hello?.error !== undefined) return yield* Effect.fail(fail("widget_credential_refused"));
          const active = yield* readList(conn, "/chats");
          for (const raw of active) {
            if (!raw || typeof raw !== "object") return yield* Effect.fail(fail("widget_bad_rows"));
            const row = presentRow({ ...raw, state: rowState(raw.agents ?? []), agents: (raw.agents ?? []).map(session) });
            const line = rowStateLine(row);
            rows.push({ id: raw.id, station: `${scope.workspace}/${station.id}`, session: raw.session ?? raw.id, thread: raw.thread,
              title: raw.title, last: raw.last, stateText: line?.[0], decision: row.decision, tone: row.tone, unread: raw.unread,
              lastActiveAt: raw.lastActiveAt, time: { createdAt: { at: raw.createdAt }, lastActiveAt: { at: raw.lastActiveAt } } });
          }
          const archived = yield* readList(conn, "/chats?archived=1");
          for (const raw of archived) {
            // Match the existing archive's day basis, not a second notion of task count.
            const at = raw?.archived?.at ?? raw?.lastActiveAt;
            if (typeof at === "number" && Number.isFinite(at) && at > 0) archivedAt.push(at);
          }
        }), (conn) => Effect.sync(() => conn.close(0, "widget refresh finished")));
      }
      return { name: typeof workspace.name === "string" ? workspace.name : "", chats: { loading: false, stations: [], days: [{ items: rows }] }, archivedAt };
    }), (endpoint) => endpoint.close());
  });
}
