// The views' test rig (views.test.ts, topic-bytes.test.ts): a store whose topics the test sets, the views routed as
// core.ts does, what the stations hold in the account's database as in a core; the UI's messages read off the host.
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import type { Owner } from "../src/core/routing.ts";
import { Data, holds } from "../src/data.ts";
import { apply as applyOps, type Op } from "../src/delta.ts";
import { parseTopic, topicKey, type Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { Store, type Source, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Views, chatDerive, type ViewsEnv } from "../src/views/views.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The views this rig routes to `Views` unless asked for every one of theirs (`all`); the rest it only notes as started.
const VIEWS = new Set(["chats", "chatRow", "chatSearch", "stations", "stationNet", "connects", "connect", "connectCandidates", "chat", "history", "archive", "workspaceMarks", "chatJobs", "imageNear", "longJobs", "usage", "profiles", "profilesWhole", "profile"]);

export class Router implements Source {
  views!: Views;
  store!: Store;
  /// Whether every topic `Views` owns is routed to it, not only `VIEWS`.
  all = false;
  /// Other owners of topics, as a core plugs them in (choose.ts, changelog.ts).
  owners: Owner[] = [];
  started: Topic[] = [];
  stopped: Topic[] = [];
  computed = 0;
  /// What the station topics say of a held topic whose read failed while nothing is held (station/topics.ts).
  failed = new Map<string, CoreError>();
  #isView(topic: Topic): boolean {
    return VIEWS.has(topic.topic) || (this.all && this.views.owns(topic));
  }
  #owner(topic: Topic): Owner | undefined {
    return this.owners.find((o) => o.owns(topic));
  }
  start(topic: Topic): void {
    const owner = this.#owner(topic);
    if (this.#isView(topic)) this.views.start(topic);
    else if (owner) {
      owner.start?.(topic);
      this.store.invalidate(topic);
    } else this.started.push(topic);
  }
  opened(topic: Topic): void {
    if (this.#isView(topic)) this.views.opened(topic);
  }
  stop(topic: Topic): void {
    const owner = this.#owner(topic);
    if (this.#isView(topic)) this.views.stop(topic);
    else if (owner) owner.stop?.(topic);
    else this.stopped.push(topic);
  }
  compute(topic: Topic): Value | undefined {
    const failed = this.failed.get(topicKey(topic));
    if (failed) return { err: failed };
    if (this.#isView(topic)) {
      this.computed++;
      return this.views.compute(topic);
    }
    return this.#owner(topic)?.compute?.(topic);
  }
}

export type Ui = { value: J; error: J; messages: number };
export const ui = (): Ui => ({ value: undefined, error: undefined, messages: 0 });

/// What a rig is made with beyond the views: every view routed (`all`), owners of other topics made of its parts, and
/// what else the views are given as a core gives it them (`env`: the accounts' workspaces, their ways).
export type RigOptions = {
  all?: boolean;
  owners?: (parts: { host: FakeHost; store: Store; data: Data; views: Views }) => Owner[];
  env?: (parts: { host: FakeHost; store: Store; data: Data; runner: Runner }) => Partial<ViewsEnv>;
  /// The host whose databases it opens: another rig's, to read what that one wrote as a core started anew does.
  host?: FakeHost;
};

export function setup(options: RigOptions = {}) {
  const host = options.host ?? new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  store.setShaped();
  // What the stations hold is in the account's database (data.ts), as in a core: the test writes it there.
  const data = new Data(host, runner, { owner: () => "s1", derive: chatDerive });
  Effect.runSync(data.open(["s1"]));
  store.setHeld((topic) => data.shared(topic), (topic) => data.release(topic));
  data.onChange((topic) => store.changed(topic));
  const router = new Router();
  const views = new Views({
    host,
    runner,
    store,
    data,
    emailOf: (ws) => (ws === "ws" ? "Me@x.com" : null),
    betaOf: (ws) => ws === "ws" && (data.record("me", "s1") as J)?.user?.beta === true,
    subOf: (ws) => (ws === "ws" ? "s1" : null),
    relayName: () => null,
    // How much of a chat is on the device, as station/topics.ts `held` says it: its entries held of as far as it is
    // known to go (its summary's last, or what is held past it); all of it once none is missing.
    held: (station, thread) => {
      const span = data.logSpan("entry", station, String(thread));
      const last = (data.thread(station, thread) as J)?.last;
      const of = Math.max(typeof last === "number" ? last : 0, span?.max ?? 0);
      return { held: span?.count ?? 0, of, whole: (span?.count ?? 0) === of };
    },
    ...options.env?.({ host, store, data, runner }),
  });
  router.views = views;
  router.store = store;
  router.all = options.all === true;
  router.owners = options.owners?.({ host, store, data, views }) ?? [];
  store.setSource(router);
  const t = {
    host,
    data,
    store,
    router,
    views,
    subscribe: (id: number, topic: Topic) => store.subscribe(1, id, topic),
    /// Chat list `list` (`chats`' params) told its window, as `chats.window` tells it (views/calls.ts).
    window: (list: Topic, rows: number) => views.setChatsWindow(parseTopic(list)!, rows),
    async readAll(uis: [Ui, number][]) {
      await host.time.pass(100);
      for (const [, message] of host.takeEmitted()) {
        const m = message as J;
        if (m.error?.code === "shape") throw new Error(m.error.message);
        const found = uis.find(([, id]) => id === m.id);
        if (!found) continue;
        const [u] = found;
        if ("value" in m) [u.value, u.error] = [m.value, undefined];
        else if ("delta" in m) u.value = applyOps(u.value, m.delta as Op[]);
        else if ("error" in m) u.error = m.error;
        else continue;
        u.messages++;
      }
    },
    async read(u: Ui, id: number) {
      await t.readAll([[u, id]]);
    },
    set: (topic: Topic, value: unknown) => {
      router.failed.delete(topicKey(topic));
      if (holds(topic)) data.set(topic, value);
      else store.set(topic, { ok: value });
    },
    // A held topic's error shows while nothing is held of it (data.ts): what was held goes first, as the core has it
    // go (a workspace gone, a session removed, a station's rows no longer reached); the station topics say why.
    fail: (topic: Topic, error: CoreError) => {
      if (!holds(topic)) return store.set(topic, { err: error });
      if (topic.topic === "workspace") data.dropWorkspace(topic.workspace as string);
      else if (topic.topic === "session") {
        if (data.hasDetail(topic.station as string, topic.key as string)) data.dropSession(topic.station as string, topic.key as string);
      } else data.retain((s) => s !== topic.station, null);
      router.failed.set(topicKey(topic), error);
      store.invalidate(topic);
    },
    started: () => {
      const s = router.started;
      router.started = [];
      return s;
    },
    stopped: () => {
      const s = router.stopped;
      router.stopped = [];
      return sorted(s);
    },
    nowS: () => host.nowMs() / 1000,
  };
  return t;
}

export const workspace = (): Topic => ({ topic: "workspace", workspace: "ws" });
export const sessions = (st: string): Topic => ({ topic: "sessions", station: st });
export const overview = (st: string): Topic => ({ topic: "overview", station: st });
export const link = (st: string): Topic => ({ topic: "link", station: st });
export const threads = (st: string): Topic => ({ topic: "threads", station: st });
export const rows = (st: string): Topic => ({ topic: "chatRows", station: st });
export const hostOf = (st: string): Topic => ({ topic: "host", station: st });
export const prefs = (): Topic => ({ topic: "prefs" });
export const sorted = (topics: Topic[]) => [...topics].sort((a, b) => (topicKey(a) < topicKey(b) ? -1 : 1));
