// A person's plugins (docs/client-plugins.md): what entries their apps grow and what a use of one does, as the
// workspace's stations keep them for this person (each its own, GET /plugins and the `plugin`/`plugin-gone` events).
// Their agent writes them; here they are put together, matched against what is shared, and run.
//
// Topic:
//   plugins {scope, source?}   this person's plugins in the workspace (by name), each with the title of the chat it
//                              sends to; with `source`, only those with a share entry that takes it
// Calls (plugins.<name> {scope, station, id, …}):
//   run {source}               what is shared sent into the plugin's chat as this person's message (`send: "auto"`),
//                              or put in that chat's composer (`"composer"`): {station, session, key, title, sent}
//   delete                     the plugin gone, from the station keeping it
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import type { Call } from "../core/calls.ts";
import { handlers } from "../core/execute.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { parseTopic, topicKey, type Topic } from "../protocol.ts";
import { splitShared } from "../share-in.ts";
import { StationAddr } from "../station/addr.ts";
import type { Value, Watch } from "../store.ts";
import { arr as arrU, get, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "plugins" }>;
const arr = (v: unknown): J[] => arrU(v) ?? [];

export type Entry = { kind: "share"; match?: string };
export type Plugin = { id: string; name: string; entries: Entry[]; action: { kind: "chat"; session: string; send: "auto" | "composer" }; at: number };
/// As held here: by `<station address>/<id>`, each with the address of the station keeping it.
type Held = Record<string, Plugin & { station: string }>;

const TABLE = "plugins";

function held(inner: Inner, ws: string): Held {
  const h = inner.data.record(TABLE, ws);
  return isObject(h) ? (h as Held) : {};
}

function change(inner: Inner, ws: string, f: (h: Held) => void): void {
  const h = structuredClone(held(inner, ws));
  f(h);
  inner.data.put(TABLE, ws, h);
  inner.store.invalidateAll((x) => x.topic === "plugins" && x.scope === ws);
}

/// Whether a plugin as a station said it is one this core can show (a newer station's kinds left out).
function usable(p: J): p is Plugin {
  return isObject(p) && typeof p.id === "string" && typeof p.name === "string" && Array.isArray(p.entries) && isObject(p.action) && p.action.kind === "chat" && typeof p.action.session === "string";
}

/// Whether one of a plugin's share entries takes what is shared: its expression found in it (any case), or none given.
export function takes(p: Plugin, source: string): boolean {
  return p.entries.some((e) => {
    if (e?.kind !== "share") return false;
    if (typeof e.match !== "string" || e.match === "") return true;
    try {
      return new RegExp(e.match, "i").test(source);
    } catch {
      return false;
    }
  });
}

/// A station's plugins for this person read again; one from before plugins (404) keeps none.
function readStation(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!inner.stations.link(address) || !inner.stations.reachable(address)) return;
    const r = yield* Effect.result(inner.stations.requests.call(StationAddr.parse(address), "GET", "/plugins", null, { quiet: true, ctx: null }));
    if (r._tag === "Failure" && r.failure.status !== 404) return;
    const list = r._tag === "Success" ? arr(get(r.success, "plugins")).filter(usable) : [];
    change(inner, ofAddress(address), (h) => {
      for (const [k, p] of Object.entries(h)) if (p.station === address) delete h[k];
      for (const p of list) h[`${address}/${p.id}`] = { ...p, station: address };
    });
  });
}

function heard(inner: Inner, address: string, name: string, data: unknown): void {
  if (name !== "plugin" && name !== "plugin-gone") return;
  const id = get(data, "id");
  if (typeof id !== "string") return;
  change(inner, ofAddress(address), (h) => {
    if (name === "plugin" && usable(data)) h[`${address}/${id}`] = { ...(data as Plugin), station: address };
    else delete h[`${address}/${id}`];
  });
}

export class Plugins implements Owner {
  readonly #inner: Inner;
  readonly #watches = new Map<string, Watch>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "plugins";
  }

  // The chats' titles come from the chats view.
  start(topic: Topic): void {
    const chats = parseTopic({ topic: "chats", scope: topic.scope as string });
    if (chats !== null) this.#watches.set(topicKey(topic), this.#inner.store.watch(chats, () => this.#inner.store.invalidate(topic)));
  }

  stop(topic: Topic): void {
    this.#watches.get(topicKey(topic))?.drop();
    this.#watches.delete(topicKey(topic));
  }

  /// The chat a plugin sends to, as the chats view has it; undefined when it is not there (yet).
  #chat(scope: string, p: Plugin & { station: string }): J {
    const v = this.#inner.store.value(parseTopic({ topic: "chats", scope })!);
    if (v === undefined || !("ok" in v)) return undefined;
    const rows = arr(get(v.ok, "days")).flatMap((d) => arr(get(d, "items")));
    return rows.find((r) => r.station === p.station && r.session === p.action.session);
  }

  /// The title of the chat a plugin sends to; null when the chats view has none for it.
  chatTitle(scope: string, p: Plugin & { station: string }): string | null {
    const row = this.#chat(scope, p);
    return typeof row?.title === "string" ? row.title : null;
  }

  compute(topic: Topic): Value | undefined {
    const scope = topic.scope as string;
    const source = typeof topic.source === "string" ? topic.source : null;
    const all = Object.values(held(this.#inner, scope))
      .filter((p) => source === null || takes(p, source))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.id < b.id ? -1 : 1));
    const items = all.map((p) => ({ station: p.station, id: p.id, name: p.name, entries: p.entries, action: p.action, chat: this.chatTitle(scope, p) }));
    return { ok: { items } };
  }

  plugin(scope: string, station: string, id: string): Plugin & { station: string } {
    const p = held(this.#inner, scope)[`${station}/${id}`];
    if (p === undefined) throw CoreError.invalid(t("core-misc.plugins.unknown"));
    return p;
  }
}

export function install(inner: Inner): void {
  const plugins = new Plugins(inner);
  inner.router.owners.push(plugins);
  inner.stations.also.push({ read: (address) => readStation(inner, address), event: (address, name, data) => heard(inner, address, name, data) });
  handlers.plugins = (_inner, call, progress, at, ctx) => {
    const c = call as Of;
    return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
      let p: Plugin & { station: string };
      try {
        p = plugins.plugin(c.scope, c.station, c.id);
      } catch (e) {
        return Effect.fail(e as CoreError);
      }
      if (c.name === "delete") {
        return Effect.map(inner.stations.requests.call(StationAddr.parse(p.station), "DELETE", `/plugins/${encodeURIComponent(p.id)}`, null, { ctx }), () => {
          change(inner, c.scope, (h) => void delete h[`${p.station}/${p.id}`]);
          return null;
        });
      }
      if (c.source.trim() === "") return Effect.fail(CoreError.invalid(t("core-logic.shareIn.error.empty")));
      const session = p.action.session;
      const key = `${p.station}:${session}`;
      const title = plugins.chatTitle(c.scope, p);
      const done = { station: p.station, session, key, title };
      if (p.action.send === "composer") {
        const shared = splitShared(c.source, null);
        if (shared.words !== "") inner.composers.offer(key, shared.words);
        if (shared.link !== null) inner.composers.link(key, shared.link);
        return Effect.succeed({ ...done, sent: false });
      }
      const send = handlers.chatSendTo!;
      return Effect.map(send(inner, { kind: "chatSendTo", station: p.station, session, text: c.source.trim(), attachments: [], quotes: [], client: null }, progress, at, ctx), () => ({ ...done, sent: true }));
    });
  };
}
