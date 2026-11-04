// A station down: what the person's other devices hold of it, read from them, face to face (iroh, CACHE_ALPN), with no
// cloud between them and nothing kept beyond what a device keeps anyway. Each device holds what it read of every station
// (docs/core-db.md); this is how one that was away, its station gone meanwhile, gets the chats and messages it missed.
//
// Only in a workspace with a lock (docs/workspace-lock.md), whose chain says which devices are whose, with no word of the
// cloud's. A device asked answers only: a device the lock names, live, as the same person's as this device's account in
// that workspace; with a member credential of that workspace for that very endpoint; whose login session still stands
// (the credential's `sid` among the account's sessions, as still.fail cloud told them last). Otherwise it says nothing.
//
// Read only, and what comes is the same rows as the station's: entries are numbered and never change, so the station
// coming back only goes on from them; its lists read then replace what a device said. Chats and messages alone: an agent's
// transcript and files stay on the station.
//
// The wire, a line of JSON each way at a time on one stream: `hello {ws, credential}` → `ok` | `no`; `list {station}` →
// `{rows, threads}`; `entries {station, thread, after, limit}` → `{entries, last}`.
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { hooks } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import type { Data } from "../data.ts";
import type { IrohConnection } from "../iroh.ts";
import { nOf } from "../entries.ts";
import { CACHE_ALPN } from "../pair.ts";
import { PAGE } from "../station/channel-kinds.ts";
import { get, isObject } from "../util.ts";
import { checkLock } from "../vault/lock-check.ts";
import { fold, held, live } from "./lock.ts";
import { type Duplex, credentialOf, streamDuplex } from "./pair.ts";
import { down } from "./views.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : null);

/// How long a device has to be reached and say it will answer, and to answer each question after that.
export const FILL_DIAL_MS = 15_000;
export const FILL_ANSWER_MS = 15_000;

/// The stations some of what is shown came from another device, while they stay down (the line over a chat's composer).
const filled = new WeakMap<Data, Set<string>>();
export const filledFromDevice = (data: Data, station: string): boolean => filled.get(data)?.has(station) === true;

// ── the device asked ──

/// Whether `peer` asks as this device's own person's, in `ws`.
export function allowed(inner: Inner, ws: string, token: string, peer: string): boolean {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  if (!inner.host.appKeys || sub === null || !h?.head) return false;
  const now = Math.floor(inner.host.nowMs() / 1000);
  let lock;
  try {
    lock = checkLock(h.entries, now);
  } catch {
    return false;
  }
  if (lock.disabled || live(lock.devices.get(peer), now)?.sub !== sub) return false;
  const c = credentialOf(token, lock.cloudKeys, ws, peer, now);
  if (c === null || c.sub !== sub || c.sid === null) return false;
  return arr(get(inner.data.shared({ topic: "loginSessions", account: sub }), "sessions")).some((s) => get(s, "id") === c.sid);
}

/// One device's questions on one stream, until it ends: nothing of a workspace but the one it proved itself in.
export function serveCache(inner: Inner, peer: string, d: Duplex): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const hello = yield* d.next();
    const ws = str(get(hello, "ws"));
    if (get(hello, "t") !== "hello" || ws === null || !allowed(inner, ws, str(get(hello, "credential")) ?? "", peer)) return yield* d.send({ t: "no" });
    yield* d.send({ t: "ok" });
    for (;;) {
      const asked = yield* d.next();
      if (asked === null) return;
      const station = str(get(asked, "station"));
      if (station === null || !station.startsWith(`${ws}/`)) return yield* d.send({ t: "no" });
      if (get(asked, "t") === "list") {
        yield* d.send({ rows: arr(inner.data.shared({ topic: "chatRows", station })), threads: arr(inner.data.shared({ topic: "threads", station })) });
      } else if (get(asked, "t") === "entries") {
        const thread = u64(get(asked, "thread"));
        const after = u64(get(asked, "after"));
        if (thread === null || after === null) return yield* d.send({ t: "no" });
        const limit = Math.min(u64(get(asked, "limit")) ?? PAGE, PAGE);
        const found = inner.data.logRange("entry", station, String(thread), after + 1, after + limit);
        yield* d.send({ entries: [...found.keys()].sort((a, b) => a - b).map((n) => found.get(n)), last: inner.data.threadLast(station, thread) });
      } else return yield* d.send({ t: "no" });
    }
  });
}

/// A device's connection, as the mesh's endpoint took it.
export function served(inner: Inner, connection: IrohConnection): void {
  inner.runner.fork(
    Effect.ignore(
      Effect.ensuring(
        Effect.gen(function* () {
          const stream = yield* connection.acceptBi();
          if (stream === null) return;
          yield* serveCache(inner, connection.remoteId(), streamDuplex(stream, () => connection.close(0, "done")));
          yield* stream.finish();
          yield* stream.stopped();
        }),
        Effect.sync(() => connection.close(0, "done")),
      ),
      { log: "Unhandled", message: "device cache served" },
    ),
  );
}

// ── the device that asks ──

/// Whether a station is taken for down here: its link found it so, or still.fail cloud says it is not online.
function isDown(inner: Inner, ws: string, station: string): boolean {
  const id = station.slice(ws.length + 1);
  const listed = arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")).find((s) => get(s, "id") === id);
  return get(listed, "online") === false || down(inner.stations.link(station)?.state);
}

/// What a device holds of a station, brought here over `d` (hello answered). Only what is newer or missing is written;
/// marked before it is, so a chat shown again for it says where it came from.
export function fillOver(inner: Inner, station: string, d: Duplex, going: () => boolean): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const data = inner.data;
    const answer = () => Effect.mapError(Effect.timeout(d.next(), FILL_ANSWER_MS), (e) => (e instanceof CoreError ? e : CoreError.plainly("device cache", "no answer")));
    yield* d.send({ t: "list", station });
    const list = yield* answer();
    const threads = arr(get(list, "threads")).filter((t) => u64(get(t, "id")) !== null && u64(get(t, "last")) !== null);
    const rows = arr(get(list, "rows")).filter(isObject);
    if (!data.listed(station, "threads")) {
      if (threads.length > 0) data.set({ topic: "threads", station }, threads);
    } else {
      for (const t of threads) if (data.thread(station, t.id) === undefined || t.last > data.threadLast(station, t.id)) data.putThread(station, t);
    }
    if (!data.listed(station, "chats")) {
      if (rows.length > 0) {
        markFilled(data, station);
        data.set({ topic: "chatRows", station }, rows);
      }
    } else {
      const heldRows = new Map(arr(data.shared({ topic: "chatRows", station })).map((r) => [String(get(r, "id")), r]));
      for (const r of rows) {
        const was = heldRows.get(String(get(r, "id")));
        if (was !== undefined && !((u64(get(r, "lastActiveAt")) ?? 0) > (u64(get(was, "lastActiveAt")) ?? 0))) continue;
        markFilled(data, station);
        data.putChat(station, r);
      }
    }
    for (const t of threads) {
      const id = String(t.id);
      const span = data.logSpan("entry", station, id);
      // What is before what is held, and after it; a hole between is the station's to fill, as its sync does.
      const stretches: [number, number][] = span === null ? [[0, t.last]] : [[0, span.min - 1], [span.max, t.last]];
      for (const [start, end] of stretches) {
        let after = start;
        while (after < end && going()) {
          yield* d.send({ t: "entries", station, thread: t.id, after, limit: PAGE });
          const items: [number, unknown][] = arr(get(yield* answer(), "entries")).flatMap((e) => {
            const n = nOf(e);
            return n !== null && n > after && n <= end ? [[n, e] as [number, unknown]] : [];
          });
          if (items.length === 0) break;
          markFilled(data, station);
          data.putItems("entry", station, id, items);
          after = Math.max(...items.map(([n]) => n));
        }
      }
    }
  });
}

/// A station's other holders asked, one after another: each may have more than the last.
function fill(inner: Inner, ws: string, sub: string, station: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const h = held(inner, ws);
    if (!h?.head) return;
    const now = Math.floor(inner.host.nowMs() / 1000);
    const mesh = yield* inner.mesh();
    const me = mesh.deviceId();
    const others = [...fold(h.entries).devices.values()].filter((o) => o.sub === sub && o.kind === "app" && o.id !== me && live(o, now) !== undefined);
    if (others.length === 0) return;
    const credential = (yield* inner.cloudSync.credential(ws, me, false, me, mesh.lockClaim(ws, me))).credential;
    const relays = [...new Set([...(inner.cloudSync.relays ?? []), ...inner.cloudSync.workspaceRelays(ws)])];
    for (const other of others) {
      if (!isDown(inner, ws, station)) return;
      yield* Effect.ignore(
        Effect.gen(function* () {
          const reached = yield* Effect.timeout(
            Effect.gen(function* () {
              const connection = yield* Effect.mapError(mesh.endpoint().connect({ id: other.id, relays }, CACHE_ALPN, []), (e) => CoreError.plainly("device cache", e));
              const stream = yield* Effect.mapError(connection.openBi(), (e) => CoreError.plainly("device cache", e));
              const d = streamDuplex(stream, () => connection.close(0, "done"));
              yield* d.send({ t: "hello", ws, credential });
              return { d, ok: get(yield* d.next(), "t") === "ok" };
            }),
            FILL_DIAL_MS,
          );
          yield* Effect.ensuring(reached.ok ? fillOver(inner, station, reached.d, () => isDown(inner, ws, station)) : Effect.void, Effect.sync(() => reached.d.close()));
        }),
      );
    }
  });
}

function markFilled(data: Data, station: string): void {
  let s = filled.get(data);
  if (!s) filled.set(data, (s = new Set()));
  s.add(station);
}

/// A station's other holders asked, once each time it goes down and each time the UI comes back while it is: nothing is
/// asked on a timer, and a device not reached is asked again only then.
class Asking {
  readonly #inner: Inner;
  /// The stations asked since they went down, or the UI last came back; those being asked now.
  readonly #asked = new Set<string>();
  readonly #going = new Set<string>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// How a station's link changed.
  linkChanged(station: string): void {
    const at = station.indexOf("/");
    if (at < 0) return;
    const ws = station.slice(0, at);
    if (!isDown(this.#inner, ws, station)) {
      filled.get(this.#inner.data)?.delete(station);
      this.#asked.delete(station);
      return;
    }
    this.#ask(ws, station);
  }

  /// The UI came back: what is down is asked for again, the other devices maybe there now.
  woken(): void {
    this.#asked.clear();
    for (const [ws] of this.#inner.workspaces.owned()) {
      for (const s of arr(get(this.#inner.data.shared({ topic: "workspace", workspace: ws }), "stations"))) {
        const id = str(get(s, "id"));
        if (id !== null && isDown(this.#inner, ws, `${ws}/${id}`)) this.#ask(ws, `${ws}/${id}`);
      }
    }
  }

  #ask(ws: string, station: string): void {
    const sub = this.#inner.workspaces.owner(ws);
    if (sub === null || !held(this.#inner, ws)?.head || this.#asked.has(station) || this.#going.has(station)) return;
    this.#asked.add(station);
    this.#going.add(station);
    this.#inner.runner.fork(Effect.ensuring(Effect.ignore(fill(this.#inner, ws, sub, station)), Effect.sync(() => this.#going.delete(station))));
  }
}

export function install(inner: Inner): void {
  hooks.deviceCache = served;
  const asking = new Asking(inner);
  inner.stations.linkChanged = (station) => asking.linkChanged(station);
  inner.runner.fork(Effect.forever(Effect.map(inner.wakes.next, () => asking.woken())));
}
