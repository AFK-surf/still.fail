// A station down: the chats and messages the person's other devices hold of it, read from them face to face (iroh,
// CACHE_ALPN), nothing kept beyond what a device keeps anyway, nothing through the cloud. Only in a workspace with a lock:
// whose devices are whose is the person's own lock where they bound it there, else the workspace lock's list, never the
// cloud (`ownDevices`; `allowed`: who is answered, and why each condition).
//
// Read only; what comes is the station's own rows, and entries never change, so the station back goes on from them and
// its lists then replace what a device said. An agent's transcript and files stay on the station.
//
// The wire, a line of JSON each way at a time on one stream: `hello {ws, credential}` → `ok` | `no`; `list {station}` →
// `{rows, threads}`; `entries {station, thread, after, limit}` → `{entries, last}`, the next `limit` held above `after`.
import { Deferred, Effect, Semaphore } from "effect";
import type { Inner } from "../core.ts";
import { hooks } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import type { Data } from "../data.ts";
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import type { IrohConnection } from "../iroh.ts";
import type { Entry } from "../lock.ts";
import { nOf } from "../entries.ts";
import { CACHE_ALPN } from "../pair.ts";
import { PAGE } from "../station/channel-kinds.ts";
import { get, isObject } from "../util.ts";
import { checkLock } from "../vault/lock-check.ts";
import { type Folded, fold, held, live, onBoundPerson } from "./lock.ts";
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

/// A chat opened asks again only this long after its station was last asked: opening several in a row is one question.
export const FILL_OPENED_AGAIN_MS = 30_000;

/// What came of asking, kept with what came (`deviceFill`, by the station's address) until the station is back: `filled`,
/// from which device and as far as when; `none`, those reached have nothing newer; `unreached`, none was reached.
export type FillStatus = { state: "filled"; from: string; upTo: number | null } | { state: "none" } | { state: "unreached" };
/// Those being asked now, by station: the device being read from, or null while none has answered yet (once one has,
/// what came is said meanwhile). Not kept.
const asking = new WeakMap<Data, Map<string, string | null>>();

/// What the line over a chat's composer adds while its station is down.
export function fillNote(data: Data, station: string, now: number, offsetMin: number): string | null {
  const being = asking.get(data);
  if (being?.has(station)) {
    const device = being.get(station);
    return device == null ? t("core-logic.looks.offline.fill.dialing") : t("core-logic.looks.offline.fill.asking", { device });
  }
  const status = data.record("deviceFill", station) as FillStatus | undefined;
  switch (status?.state) {
    case "filled":
      return status.upTo === null ? t("core-logic.looks.offline.fill.from", { device: status.from }) : t("core-logic.looks.offline.fill.upTo", { device: status.from, time: format.relativeTime(status.upTo, now, offsetMin) });
    case "none":
      return t("core-logic.looks.offline.fill.none");
    case "unreached":
      return t("core-logic.looks.offline.fill.unreached");
    default:
      return null;
  }
}

// ── whose devices ──

/// The workspace lock's devices of `sub`'s, as they stand at `now`.
const listed = (f: Folded, sub: string, now: number): Map<string, J> => new Map([...f.devices.values()].filter((d) => d.sub === sub && live(d, now) !== undefined).map((d) => [d.id, d]));

/// `sub`'s devices in `ws` as this device can tell, by id. Where they bound a lock of their own there, as the stations
/// go (station/src/mesh/serve.ts `inLock`): an app device by that lock alone, so one taken off it is not theirs though
/// the workspace's lock still names it, and one put on it is before that lock names it; a web page, which holds no key
/// of it, by its entry. Null where they bound one and this device is not on it: it cannot tell.
function ownDevices(inner: Inner, ws: string, sub: string, entries: Entry[], now: number): Map<string, J> | null {
  const f = fold(entries);
  const named = listed(f, sub, now);
  if (!f.persons.has(sub)) return named;
  if (!onBoundPerson(inner, ws)) return null;
  const out = new Map([...named].filter(([, d]) => d.kind === "web"));
  for (const d of inner.adb.personal().chain(sub)?.devices.values() ?? []) out.set(d.id, { id: d.id, sub, kind: "app", label: str(named.get(d.id)?.label) || d.label });
  return out;
}

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
  // (an app off the lock its person bound here answers no one)
  if (lock.disabled || !ownDevices(inner, ws, sub, h.entries, now)?.has(peer)) return false;
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
        // The next `limit` it holds above `after`, whatever their numbers: a hole in what it holds ends no page.
        const held = inner.data.logNumbers("entry", station, String(thread));
        let i = 0;
        while (i < held.length && held[i]! <= after) i++;
        const next = held.slice(i, i + limit);
        const found = next.length === 0 ? new Map<number, unknown>() : inner.data.logRange("entry", station, String(thread), next[0]!, next[next.length - 1]!);
        yield* d.send({ entries: next.flatMap((n) => (found.has(n) ? [found.get(n)] : [])), last: inner.data.threadLast(station, thread) });
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

/// Whether a station is taken for down here: its link found it so, or still.fail cloud says it is not online and this
/// device's link is not up (one up, as on the station's LAN while its internet is gone, is believed over the cloud).
function isDown(inner: Inner, ws: string, station: string): boolean {
  const link = inner.stations.link(station)?.state;
  if (down(link)) return true;
  if (get(link, "state") === "online") return false;
  const id = station.slice(ws.length + 1);
  const listed = arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")).find((s) => get(s, "id") === id);
  return get(listed, "online") === false;
}

/// What a device holds of a station, brought here over `d` (hello answered), all of it: page after page until it has no
/// more. Only what is newer or missing is written. Whether anything came, and the latest message that did.
export function fillOver(inner: Inner, station: string, d: Duplex, going: () => boolean): Effect.Effect<{ brought: boolean; upTo: number | null }, CoreError> {
  return Effect.gen(function* () {
    const data = inner.data;
    let brought = false;
    let upTo: number | null = null;
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
        brought = true;
        data.set({ topic: "chatRows", station }, rows);
      }
    } else {
      const heldRows = new Map(arr(data.shared({ topic: "chatRows", station })).map((r) => [String(get(r, "id")), r]));
      for (const r of rows) {
        const was = heldRows.get(String(get(r, "id")));
        if (was !== undefined && !((u64(get(r, "lastActiveAt")) ?? 0) > (u64(get(was, "lastActiveAt")) ?? 0))) continue;
        brought = true;
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
          brought = true;
          data.putItems("entry", station, id, items);
          for (const [, e] of items) {
            const at = u64(get(e, "at"));
            if (at !== null && (upTo === null || at > upTo)) upTo = at;
          }
          after = Math.max(...items.map(([n]) => n));
        }
      }
    }
    return { brought, upTo };
  });
}

/// A station's other holders dialled together, each given FILL_DIAL_MS to say it answers; those that do read from one at a
/// time (`fillOver` compares with what is held), in the order they answered, each for all it has: each may have more
/// than the last. What came of it kept, a later try that found nothing newer leaving what an earlier one brought said.
function fill(inner: Inner, ws: string, sub: string, station: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const h = held(inner, ws);
    if (!h?.head || !isDown(inner, ws, station)) return;
    const now = Math.floor(inner.host.nowMs() / 1000);
    const mesh = yield* inner.mesh();
    const me = mesh.deviceId();
    // (where this device cannot tell, a web page or an app off its person's own lock, the workspace lock's: the one
    // dialled decides)
    const mine = ownDevices(inner, ws, sub, h.entries, now) ?? listed(fold(h.entries), sub, now);
    const others = [...mine.values()].filter((o) => o.kind === "app" && o.id !== me);
    if (others.length === 0) return;
    const credential = (yield* inner.cloudSync.credential(ws, me, false, me, mesh.lockClaim(ws, me))).credential;
    const relays = [...new Set([...(inner.cloudSync.relays ?? []), ...inner.cloudSync.workspaceRelays(ws)])];
    const nameOf = (o: { label?: unknown }) => str(o.label) || t("core-logic.looks.offline.fill.another");
    const told = () => inner.store.invalidateAll((topic) => topic.topic === "chat" && topic.station === station);
    let shown = asking.get(inner.data);
    if (!shown) asking.set(inner.data, (shown = new Map()));
    const turn = Semaphore.makeUnsafe(1);
    let answered = false;
    let from: string | null = null;
    let upTo: number | null = null;
    // One device: reached and its `ok` heard within FILL_DIAL_MS, then read from in its turn. Its connection closed
    // however it ends, one the host hands over after this has ended included.
    const one = (other: { id: string; label?: unknown }) =>
      Effect.suspend(() => {
        let ended = false;
        let connection: IrohConnection | null = null;
        const close = () => {
          ended = true;
          connection?.close(0, "done");
          connection = null;
        };
        const reach = Effect.gen(function* () {
          const dialled = Deferred.makeUnsafe<IrohConnection, CoreError>();
          inner.runner.fork(
            Effect.gen(function* () {
              const r = yield* Effect.result(mesh.endpoint().connect({ id: other.id, relays }, CACHE_ALPN, []));
              if (r._tag === "Success") {
                if (ended) return r.success.close(0, "done");
                connection = r.success;
              }
              Deferred.doneUnsafe(dialled, r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(CoreError.plainly("device cache", r.failure)));
            }),
          );
          const c = yield* Deferred.await(dialled);
          const stream = yield* Effect.mapError(c.openBi(), (e) => CoreError.plainly("device cache", e));
          const d = streamDuplex(stream, close);
          yield* d.send({ t: "hello", ws, credential });
          return get(yield* d.next(), "t") === "ok" ? d : null;
        });
        return Effect.ensuring(
          Effect.gen(function* () {
            const d = yield* Effect.timeout(reach, FILL_DIAL_MS);
            if (d === null) return;
            answered = true;
            yield* turn.withPermits(1)(
              Effect.gen(function* () {
                if (!isDown(inner, ws, station)) return;
                shown.set(station, nameOf(other));
                told();
                const came = yield* Effect.ensuring(
                  fillOver(inner, station, d, () => isDown(inner, ws, station)),
                  Effect.sync(() => {
                    shown.delete(station);
                    told();
                  }),
                );
                if (came.brought) {
                  from = nameOf(other);
                  if (came.upTo !== null && (upTo === null || came.upTo > upTo)) upTo = came.upTo;
                  // Said at once, not once those not reached yet are given up on.
                  keep();
                  told();
                }
              }),
            );
          }),
          Effect.sync(close),
        );
      });
    const keep = () => {
      const was = inner.data.record("deviceFill", station) as FillStatus | undefined;
      if (from !== null) inner.data.put("deviceFill", station, { state: "filled", from, upTo: upTo ?? (was?.state === "filled" ? was.upTo : null) } satisfies FillStatus);
      else if (was?.state !== "filled" && isDown(inner, ws, station)) inner.data.put("deviceFill", station, { state: answered ? "none" : "unreached" } satisfies FillStatus);
    };
    shown.set(station, null);
    told();
    yield* Effect.ensuring(
      Effect.forEach(others, (other) => Effect.ignore(one(other)), { concurrency: "unbounded", discard: true }),
      Effect.sync(() => {
        shown.delete(station);
        keep();
        told();
      }),
    );
  });
}

/// A station's other holders asked as it goes down, as the UI comes back while it is, and as one of its chats is opened:
/// nothing is asked on a timer, and a device not reached is asked again only then.
class Asking {
  readonly #inner: Inner;
  /// The stations asked since they went down, or the UI last came back; those being asked now.
  readonly #asked = new Set<string>();
  readonly #going = new Set<string>();
  readonly #ended = new Map<string, number>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// How a station's link changed.
  linkChanged(station: string): void {
    const at = station.indexOf("/");
    if (at < 0) return;
    const ws = station.slice(0, at);
    if (!isDown(this.#inner, ws, station)) {
      if (this.#inner.data.record("deviceFill", station) !== undefined) this.#inner.data.forgetRecord("deviceFill", station);
      this.#asked.delete(station);
      return;
    }
    this.#ask(ws, station);
  }

  /// One of its chats opened.
  chatOpened(station: string): void {
    const at = station.indexOf("/");
    if (at < 0 || !isDown(this.#inner, station.slice(0, at), station)) return;
    if (this.#inner.host.nowMs() - (this.#ended.get(station) ?? -FILL_OPENED_AGAIN_MS) < FILL_OPENED_AGAIN_MS) return;
    this.#asked.delete(station);
    this.#ask(station.slice(0, at), station);
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
    this.#inner.runner.fork(Effect.ensuring(Effect.ignore(fill(this.#inner, ws, sub, station)), Effect.sync(() => {
      this.#going.delete(station);
      this.#ended.set(station, this.#inner.host.nowMs());
    })));
  }
}

export function install(inner: Inner): void {
  hooks.deviceCache = served;
  const questions = new Asking(inner);
  inner.stations.linkChanged = (station) => questions.linkChanged(station);
  inner.stations.chatOpened = (station) => questions.chatOpened(station);
  inner.runner.fork(
    Effect.gen(function* () {
      for (;;) {
        yield* inner.wakes.next;
        questions.woken();
      }
    }),
  );
}
