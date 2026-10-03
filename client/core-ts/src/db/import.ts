// What a device kept before the databases per account (docs/core-db.md, Import), brought into an account's database
// once, when it is first opened: the former records store (the KV `records` table of `core.db`, IndexedDB `records` on
// the web; data.ts before) and what the Rust core kept of threads and transcripts in storage chunks (`kept`). Each
// account takes what is its own and what is of the workspaces it reaches (the first account in sign-in order whose
// `/v1/me` lists one, as Workspaces has it); the device's values (preferences, the changelog) go to the device's
// storage once. Nothing is taken away: an older core still finds what it kept. No size cap: all of it comes over;
// threads' entries and transcripts in the background, after the first view (what the sync brings meanwhile is newer
// and stays).
import { Effect } from "effect";
import type { Data } from "../data.ts";
import type { Host } from "../host.ts";
import type { Runner } from "../runtime.ts";
import { isObject, parseJson } from "../util.ts";
import type { AccountDb } from "./account.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const SEP = "\u0001";
const END = "\u{10ffff}";
/// The Rust core's chunks of a log (kept.rs).
export const CHUNK = 256;
const DEVICE_DONE = "device-imported";

type Rows = [string, J][];

/// Reads one table of the former store whole (or a key range of it).
function read(host: Host, table: string, from = "", to = END): Effect.Effect<Rows> {
  if (!host.legacyRead) return Effect.succeed([]);
  return Effect.map(Effect.orElseSucceed(host.legacyRead({ table, from, to }), () => [] as [string, Uint8Array][]), (rows) =>
    rows.flatMap(([key, bytes]) => {
      const v = parseJson(bytes);
      return v === undefined ? [] : [[key, v] as [string, J]];
    }),
  );
}

const split = (key: string): [string, string] => {
  const at = key.indexOf(SEP);
  return at < 0 ? [key, ""] : [key.slice(0, at), key.slice(at + 1)];
};

const workspaceOf = (station: string) => (station.includes("/") ? station.slice(0, station.indexOf("/")) : station);

/// Brings what the device kept into `db`, once (its `imported` mark); `subs`: the accounts in sign-in order.
export function importFormer(host: Host, runner: Runner, data: Data, subs: string[], db: AccountDb): Effect.Effect<void> {
  return Effect.gen(function* () {
    yield* importDevice(host, data);
    if (db.readOnly || db.meta("imported") !== null) return;
    if (!host.legacyRead) {
      db.setMeta("imported", "none");
      return;
    }
    const mes = yield* read(host, "me");
    // Which account reaches each workspace, as it did then.
    const owners = new Map<string, string>();
    for (const sub of subs) {
      const me = mes.find(([k]) => k === sub)?.[1];
      for (const w of Array.isArray(me?.workspaces) ? me.workspaces : []) if (typeof w?.id === "string" && !owners.has(w.id)) owners.set(w.id, sub);
    }
    const ours = (workspace: string) => owners.get(workspace) === db.sub;
    const station = (s: string) => ours(workspaceOf(s));
    const confirmed = new Map((yield* read(host, "confirmed")).map(([k, v]) => [k, typeof v === "number" ? v : null]));
    const at = (table: string, key: string) => confirmed.get(`${table}${SEP}${key}`) ?? null;
    const tables = new Map<string, Rows>();
    for (const t of ["workspace", "overview", "footprint", "usage", "slack_app", "row", "archived_row", "session_summary", "session", "thread", "job_open", "job", "list", "draft", "outbox", "pending", "first", "changing", "login_sessions", "admin", "choice", "chat_ref"]) tables.set(t, yield* read(host, t));
    const of = (t: string) => tables.get(t) ?? [];
    const byKey = (t: string) => new Map(of(t));
    db.batch(() => {
      const me = mes.find(([k]) => k === db.sub)?.[1];
      if (me !== undefined) db.putAccountDoc("me", me, at("me", db.sub), null);
      for (const [k, v] of of("login_sessions")) if (k === db.sub) db.putAccountDoc("login_sessions", v, at("login_sessions", k), null);
      for (const [k, v] of of("admin")) {
        const [sub, list] = split(k);
        if (sub === db.sub) db.putAccountDoc(`admin/${list}`, v, at("admin", k), null);
      }
      for (const [id, v] of of("workspace")) if (ours(id)) db.putWorkspace(id, v, at("workspace", id));
      for (const [t, topic] of [["overview", "overview"], ["footprint", "footprint"], ["usage", "stationUsage"]] as const) {
        for (const [s, v] of of(t)) if (station(s)) db.putStationDoc(s, t, v, at(t, s), { topic, station: s });
      }
      for (const [k, v] of of("slack_app")) {
        const [s, connect] = split(k);
        if (station(s)) db.putSlackApp(s, connect, v, at("slack_app", k));
      }
      // Lists: the ids in order, each item its own record.
      const items = new Map<string, Map<string, J>>();
      for (const t of ["row", "archived_row", "session_summary", "thread", "job_open"]) items.set(t, byKey(t));
      for (const [k, ids] of of("list")) {
        const [t, s] = split(k);
        if (!station(s) || !Array.isArray(ids)) continue;
        const its = items.get(t);
        if (!its) continue;
        const list = ids.flatMap((id: unknown) => {
          const v = typeof id === "string" || typeof id === "number" ? its.get(`${s}${SEP}${id}`) : undefined;
          return v === undefined ? [] : [v];
        });
        const when = at("list", k);
        if (t === "row") db.setChats(s, false, list, when);
        else if (t === "archived_row") db.setChats(s, true, list, when);
        else if (t === "session_summary") db.setSessions(s, list, when);
        else if (t === "thread") db.setThreads(s, list, when);
        else if (t === "job_open") db.setJobs(s, list, when);
      }
      for (const [k, v] of of("session")) {
        const [s, key] = split(k);
        if (station(s) && isObject(v)) db.setDetail(s, key, v);
      }
      for (const [k, v] of of("job")) {
        const [s] = split(k);
        if (station(s)) db.putJob(s, v, false);
      }
      for (const [k, v] of of("draft")) {
        const [s, chat] = split(k);
        if (station(s)) db.putDraft(s, chat, v);
      }
      for (const [k, v] of of("outbox")) {
        const [s, thread] = split(k);
        if (station(s)) db.putLocal("outbox", s, thread, v);
      }
      for (const [k, v] of of("pending")) {
        const [s, key] = split(k);
        if (station(s)) db.putLocal("pending", s, key, v);
      }
      for (const [k, v] of of("first")) {
        const [s, key] = split(k);
        if (station(s)) db.putLocal("first", s, key, v);
      }
      for (const [k, v] of of("changing")) {
        const [s, id] = split(k);
        // A change done waited on the rows as they were then: it is let go once the rows change.
        if (station(s) && isObject(v)) db.putLocal("changing", s, id, isObject(v.done) ? { ...v, done: { rev: -1 } } : v);
      }
      for (const [k, v] of of("choice")) {
        if (!k.startsWith("ws:")) continue;
        const cut = k.indexOf(":", 3);
        const ws = cut < 0 ? k.slice(3) : k.slice(3, cut);
        if (ours(ws)) db.putWorkspacePref(ws, `choice:${cut < 0 ? "" : k.slice(cut + 1)}`, v);
      }
      for (const [k, v] of of("chat_ref")) if (k.startsWith("links:") && ours(k.slice(6))) db.putWorkspacePref(k.slice(6), "links", v);
      db.setMeta("imported", String(host.nowMs()));
    });
    // Threads' entries and transcripts, in the background, a station at a time.
    const stations = new Set<string>();
    for (const [k] of of("overview")) stations.add(k);
    for (const [k] of of("list")) stations.add(split(k)[1]);
    for (const t of ["thread", "session", "row", "session_summary", "draft", "outbox"]) for (const [k] of of(t)) stations.add(split(k)[0]);
    for (const s of [...stations]) if (!station(s)) stations.delete(s);
    const kept = yield* Effect.orElseSucceed(host.storageGet("kept-read"), () => null);
    runner.fork(
      Effect.gen(function* () {
        for (const s of [...stations].sort()) {
          for (const table of ["entry", "transcript"] as const) {
            const rows = yield* read(host, table, `${s}${SEP}`, `${s}\u0002`);
            const logs = new Map<string, [number, J][]>();
            for (const [k, v] of rows) {
              const parts = k.split(SEP);
              const n = Number(parts[2]);
              if (parts.length !== 3 || !Number.isInteger(n)) continue;
              let list = logs.get(parts[1]);
              if (!list) logs.set(parts[1], (list = []));
              list.push([n, v]);
            }
            for (const [id, list] of logs) {
              db.putLog(table, s, id, list, null, true);
              yield* Effect.yieldNow;
            }
          }
        }
        // The Rust core's chunks, if no core in TypeScript read them before (it left them in its records then).
        if (kept === null) yield* importKept(host, db, station);
      }),
    );
  });
}

/// The device's values, once per device: its preferences, the changelog seen, the picks and links not a workspace's.
function importDevice(host: Host, data: Data): Effect.Effect<void> {
  return Effect.gen(function* () {
    if (!host.legacyRead) return;
    if ((yield* Effect.orElseSucceed(host.storageGet(DEVICE_DONE), () => null)) !== null) return;
    for (const [k, v] of yield* read(host, "prefs")) if (k === "device" && data.device.get("prefs", "device") === undefined) data.device.put("prefs", "device", v);
    for (const [k, v] of yield* read(host, "changelog")) if (data.device.get("changelog", k) === undefined) data.device.put("changelog", k, v);
    for (const [k, v] of yield* read(host, "choice")) if (!k.startsWith("ws:") && data.device.get("choice", k) === undefined) data.device.put("choice", k, v);
    for (const [k, v] of yield* read(host, "chat_ref")) if (!k.startsWith("links:") && data.device.get("chat_ref", k) === undefined) data.device.put("chat_ref", k, v);
    yield* Effect.ignore(host.storageSet(DEVICE_DONE, new TextEncoder().encode("1")));
  });
}

const getJson = (host: Host, key: string): Effect.Effect<J> =>
  Effect.map(Effect.orElseSucceed(host.storageGet(key), () => null), (b) => (b ? parseJson(b) : undefined));

/// The Rust core's chunks of 256 (kept.rs): `thread/<station>/<thread>/<chunk>` (entries numbered from 1),
/// `transcript/<station>/<session>/<chunk>` (items from 0), `<log>/meta` the run `{first, last}` held, `kept` the index.
export function importKept(host: Host, db: AccountDb, ours: (station: string) => boolean): Effect.Effect<void> {
  return Effect.gen(function* () {
    const index = (yield* getJson(host, "kept")) as J;
    if (!index || typeof index !== "object") return;
    for (const [name, item] of Object.entries(index as Record<string, J>)) {
      const station = typeof item?.station === "string" ? item.station : null;
      if (!station || !ours(station)) continue;
      const table = name.startsWith(`thread/${station}/`) ? "entry" : name.startsWith(`transcript/${station}/`) ? "transcript" : null;
      if (!table) continue;
      const id = name.slice((table === "entry" ? "thread/" : "transcript/").length + station.length + 1);
      const base = table === "entry" ? 1 : 0;
      const held = (yield* getJson(host, `${name}/meta`)) as J;
      const first = Number(held?.first);
      const last = Number(held?.last);
      if (!Number.isInteger(first) || !Number.isInteger(last) || last < first) continue;
      const items: [number, unknown][] = [];
      let whole = true;
      for (let chunk = Math.floor((first - base) / CHUNK); chunk <= Math.floor((last - base) / CHUNK); chunk++) {
        const start = Math.max(chunk * CHUNK + base, first);
        const end = Math.min(chunk * CHUNK + base + CHUNK - 1, last);
        const entries = (yield* getJson(host, `${name}/${chunk}`)) as J;
        // As kept.rs reads a chunk: all of it there, and a thread's entries each where its `n` says.
        if (!Array.isArray(entries) || entries.length !== end + 1 - start || (table === "entry" && entries.some((e: J, i: number) => e?.n !== start + i))) {
          whole = false;
          break;
        }
        entries.forEach((e: unknown, i: number) => items.push([start + i, e]));
      }
      if (whole) db.putLog(table, station, id, items, null, true);
      yield* Effect.yieldNow;
    }
  });
}
