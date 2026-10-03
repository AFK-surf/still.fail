// The core's part of attention (core.rs, routing.rs, execute.rs for attend.rs and notices.rs): the `notices` and
// `notify` topics, a chat's value as its UIs attend to it, the attention calls, push registration. The chat rows are
// looked at as the data center changes them (rule 2: pushed, never polled): what changed is noticed, and what a page
// is to show now goes out.
import { Effect } from "effect";
import { Attend } from "./attend.ts";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import type { Owner } from "./core/routing.ts";
import { Notices } from "./notices.ts";
import * as prefs from "./prefs.ts";
import type { Topic } from "./protocol.ts";
import type { Value } from "./store.ts";
import { arr as arrU, get as getU, isObject, parseJson } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// Where this device's push registration is kept.
export const PUSH_KEY = "push";

export class Attention implements Owner {
  readonly #core: Inner;
  readonly attend: Attend;
  readonly notices: Notices;
  #looking = false;

  constructor(core: Inner, attend: Attend) {
    this.#core = core;
    this.attend = attend;
    this.notices = new Notices({
      workspaces: core.workspaces,
      rows: (station) => {
        const rows = core.data.get({ topic: "chatRows", station });
        return Array.isArray(rows) ? rows : undefined;
      },
      members: (workspace) => arr(get(core.data.get({ topic: "workspace", workspace }), "members")),
      slackUsers: (station) => arr(get(core.data.get({ topic: "overview", station }), "slackUsers")).filter((u): u is string => typeof u === "string"),
      emailOf: (workspace) => {
        const sub = core.workspaces.of(workspace).owner;
        return sub === null ? null : (core.accounts.list().find((a) => a.sub === sub)?.email ?? null);
      },
      now: () => core.host.nowMs(),
    });
    // The rows changed (an event, a read): looked at once what changed together has settled.
    core.data.onChange((topic) => {
      if (topic.topic === "chatRows" || topic.topic === "workspace" || topic.topic === "workspaces") this.#lookSoon();
    });
  }

  owns(topic: Topic): boolean {
    return topic.topic === "notices" || topic.topic === "notify";
  }

  compute(topic: Topic): Value | undefined {
    const workspace = typeof topic.workspace === "string" ? topic.workspace : null;
    return { ok: topic.topic === "notices" ? this.notices.value(workspace) : this.attend.value(workspace) };
  }

  /// The stations kept in sync: those of every workspace an account reaches, as the workspace lists them.
  #stations(): string[] {
    const core = this.#core;
    return core.workspaces.owned().flatMap(([id]) =>
      arr(get(core.data.get({ topic: "workspace", workspace: id }), "stations")).flatMap((s) => (typeof get(s, "id") === "string" ? [`${id}/${s.id}`] : [])),
    );
  }

  #lookSoon(): void {
    if (this.#looking) return;
    this.#looking = true;
    this.#core.runner.fork(
      Effect.sync(() => {
        this.#looking = false;
        this.look();
      }),
    );
  }

  /// Looks at the rows: what is new is noticed, and what a page is to show goes out.
  look(): void {
    const store = this.#core.store;
    const added = this.notices.look(this.#stations());
    if (added.length > 0) store.invalidateAll((t) => t.topic === "notices");
    const listened = store.liveTopics().some((t) => t.topic === "notify" && store.subscribed(t));
    if (this.attend.noticed(added, listened)) store.invalidateAll((t) => t.topic === "notify");
  }

  /// A chat as its UIs attend to it: its unread line; read, when due.
  attended(topic: Topic, value: Value | undefined): Value | undefined {
    if (topic.topic !== "chat" || value === undefined || !("ok" in value)) return value;
    const station = topic.station as string;
    const due = this.attend.chat(station, typeof topic.session === "string" ? topic.session : null, value.ok);
    const core = this.#core;
    for (const d of due) {
      core.runner.fork(
        Effect.catch(core.stations.read(station, d.read.thread, d.read.seq, null), () => Effect.sync(() => this.attend.failed(station, d))),
      );
    }
    return value;
  }

  /// This device's push registration, given to the accounts that do not have it yet.
  #registered(): Effect.Effect<unknown, never> {
    return Effect.map(Effect.result(this.#core.cloudSync.pushRegistered()), (r) => {
      this.attend.setPushing(r._tag === "Success");
      return r;
    });
  }

  install(): void {
    const core = this.#core;
    const attend = this.attend;
    const store = core.store;
    // A registration kept: this device has pushes.
    core.runner.fork(
      Effect.map(Effect.orElseSucceed(core.host.storageGet(PUSH_KEY), () => null), (bytes) => {
        const kept = parseJson(bytes) as J;
        attend.setPushing(isObject(kept) && Array.isArray(kept.with) && kept.with.length > 0);
      }),
    );
    handlers.attend = (_inner, call, progress, at, ctx) => {
      const c = (call as Extract<Call, { kind: "attend" }>).call;
      switch (c.kind) {
        case "focus":
          return Effect.sync(() => {
            const chat = c.focus.chat;
            if (chat && chat.session !== null && chat.session !== "" && !chat.session.startsWith("new:")) prefs.chatOpened(core.data, chat.station, chat.session);
            attend.focus(at[0], c.focus);
            store.invalidateAll((t) => t.topic === "chat");
            store.invalidateAll((t) => t.topic === "notify");
            return null;
          });
        case "set":
          return Effect.gen(function* () {
            yield* attend.set(c.on, c.asked);
            store.invalidateAll((t) => t.topic === "notify");
            if (c.on === false && handlers.pushUnregister) yield* handlers.pushUnregister(core, { kind: "pushUnregister" }, progress, at, ctx);
            return attend.value(null);
          });
        case "claim":
          return Effect.sync(() => {
            const show = attend.claim(c.id);
            if (show) store.invalidateAll((t) => t.topic === "notify");
            return { show };
          });
        case "pushed":
          return Effect.succeed({ show: attend.pushed(c.workspace) });
      }
    };
    handlers.pushRegister = (_inner, call) => {
      const c = call as Extract<Call, { kind: "pushRegister" }>;
      const self = this;
      return Effect.gen(function* () {
        if (!attend.on()) return null;
        yield* Effect.ignore(core.host.storageSet(PUSH_KEY, new TextEncoder().encode(JSON.stringify({ registration: c.registration, with: [], lang: null }))));
        const r = (yield* self.#registered()) as { _tag: string; failure?: J };
        if (r._tag === "Failure") return yield* Effect.fail(r.failure);
        return null;
      });
    };
    handlers.pushUnregister = () =>
      Effect.gen(function* () {
        attend.setPushing(false);
        const kept = parseJson(yield* Effect.orElseSucceed(core.host.storageGet(PUSH_KEY), () => null)) as J;
        yield* Effect.ignore(core.host.storageDelete(PUSH_KEY));
        if (isObject(kept) && isObject(kept.registration)) {
          const gone: J = {};
          for (const k of ["endpoint", "token"]) if ((kept.registration as J)[k] !== undefined) gone[k] = (kept.registration as J)[k];
          for (const account of core.accounts.list()) yield* Effect.ignore(core.cloud.request(account.sub, "DELETE", "/v1/push", gone));
        }
        return null;
      });
  }
}
