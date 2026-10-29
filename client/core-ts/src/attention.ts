// The core's part of attention (core.rs, routing.rs, execute.rs for attend.rs and notices.rs): the `notices` and
// `notify` topics, a chat's value as its UIs attend to it, the attention calls, push registration. The chat rows that
// change are looked at as the data says them (rule 2: pushed, never polled): what changed is noticed, and what a page
// is to show now goes out.
import { Effect } from "effect";
import { Attend } from "./attend.ts";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import type { Owner } from "./core/routing.ts";
import { Notices, type Changed } from "./notices.ts";
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

  constructor(core: Inner, attend: Attend) {
    this.#core = core;
    this.attend = attend;
    this.notices = new Notices({
      workspaces: core.workspaces,
      members: (workspace) => arr(get(core.data.shared({ topic: "workspace", workspace }), "members")),
      slackUsers: (station) => arr(get(core.data.shared({ topic: "overview", station }), "slackUsers")).filter((u): u is string => typeof u === "string"),
      emailOf: (workspace) => {
        const sub = core.workspaces.of(workspace).owner;
        return sub === null ? null : (core.accounts.list().find((a) => a.sub === sub)?.email ?? null);
      },
      now: () => core.host.nowMs(),
    });
    // Rows changed (an event, a read): what changed is looked at, as a write says it.
    core.data.onChats((station, rows, first) => this.look(station, rows, first));
    core.data.onChange((topic) => {
      if (topic.topic === "workspace") this.notices.keep(this.#stations());
    });
  }

  owns(topic: Topic): boolean {
    return topic.topic === "notices" || topic.topic === "notify";
  }

  compute(topic: Topic): Value | undefined {
    if (topic.topic === "notices") return { ok: this.notices.value(typeof topic.workspace === "string" ? topic.workspace : null) };
    return { ok: this.#notify() };
  }

  /// The `notify` topic (attend.ts `value`), with the workspaces the accounts are in, each heard of or not.
  #notify(): J {
    const all = this.#workspaces();
    const names = new Map(all.map((w) => [w.id as string, w.name as string]));
    return { ...this.attend.value((w) => names.get(w) ?? null), workspaces: all.map((w) => ({ ...w, on: this.attend.heard(w.id) })) };
  }

  /// The workspaces the signed-in accounts are in, as their `/v1/me` list them: id, name, and its mark.
  #workspaces(): J[] {
    const seen = new Set<string>();
    const out: J[] = [];
    for (const [, me] of this.#core.data.mes()) {
      for (const w of arr(get(me, "workspaces"))) {
        const id = get(w, "id");
        if (typeof id !== "string" || seen.has(id)) continue;
        seen.add(id);
        const name = get(w, "name");
        out.push({ id, name: typeof name === "string" && name !== "" ? name : id, ...(typeof get(w, "emoji") === "string" && w.emoji !== "" ? { emoji: w.emoji } : {}), ...(typeof get(w, "icon") === "string" && w.icon !== "" ? { icon: w.icon } : {}) });
      }
    }
    return out;
  }

  /// The stations kept in sync: those of every workspace an account reaches, as the workspace lists them.
  #stations(): string[] {
    const core = this.#core;
    return core.workspaces.owned().flatMap(([id]) =>
      arr(get(core.data.get({ topic: "workspace", workspace: id }), "stations")).flatMap((s) => (typeof get(s, "id") === "string" ? [`${id}/${s.id}`] : [])),
    );
  }

  /// Rows of a station that changed: what is new is noticed, and what a page is to show goes out.
  look(station: string, rows: Changed[], first: boolean): void {
    const store = this.#core.store;
    if (!this.#stations().includes(station)) return;
    const added = this.notices.changed(station, rows, first);
    if (added.length > 0) store.invalidateAll((t) => t.topic === "notices");
    const listened = store.liveTopics().some((t) => t.topic === "notify" && store.subscribed(t));
    if (this.attend.noticed(added, listened)) store.invalidateAll((t) => t.topic === "notify");
  }

  /// A chat as its UIs attend to it: its unread line; read, when due.
  attended(topic: Topic, value: Value | undefined): Value | undefined {
    if (topic.topic !== "chat" || value === undefined || !("ok" in value)) return value;
    const station = topic.station as string;
    const { due, value: attended } = this.attend.chat(station, typeof topic.session === "string" ? topic.session : null, value.ok);
    const core = this.#core;
    for (const d of due) {
      core.runner.fork(
        Effect.catch(core.stations.read(station, d.read.thread, d.read.seq, null), () => Effect.sync(() => this.attend.failed(station, d))),
      );
    }
    return { ok: attended };
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
    const self = this;
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
            if (c.focus.newChat !== null && c.focus.newChat !== "") prefs.newChatOpened(core.data, c.focus.newChat);
            attend.focus(at[0], c.focus);
            // (what was typed written now, not a moment after its last change: the app leaving a chat or the front may
            // be gone before that moment)
            core.data.flushSoon();
            store.invalidateAll((t) => t.topic === "chat");
            store.invalidateAll((t) => t.topic === "notify");
            return null;
          });
        case "set":
          return Effect.gen(function* () {
            yield* attend.set(c.on, c.asked, c.kinds, c.preview, c.workspaces);
            store.invalidateAll((t) => t.topic === "notify");
            // (a workspace turned off adds nothing to the app's badge)
            if (c.workspaces !== null) store.invalidateAll((t) => t.topic === "workspaceMarks");
            if (c.on === false && handlers.pushUnregister) yield* handlers.pushUnregister(core, { kind: "pushUnregister" }, progress, at, ctx);
            // what it shows changed: its registration given again (pushes made so), not waited on
            else if ((c.kinds !== null || c.preview !== null || c.workspaces !== null) && attend.on()) core.runner.fork(Effect.ignore(core.cloudSync.pushRegistered(), { log: "Unhandled", message: "push registration sent" }));
            return self.#notify();
          });
        case "permission":
          return Effect.sync(() => {
            if (attend.permit(c.state)) store.invalidateAll((t) => t.topic === "notify");
            return null;
          });
        case "claim":
          return Effect.sync(() => {
            const show = attend.claim(c.id);
            if (show) store.invalidateAll((t) => t.topic === "notify");
            return { show };
          });
        case "pushed": {
          // (the title as a notice of it shows: of a workspace the viewer is not in, its name first)
          const names = new Map(this.#workspaces().map((w) => [w.id as string, w.name as string]));
          const show = attend.pushed(c.workspace, c.notice);
          return Effect.succeed(c.title === null || c.workspace === null ? { show } : { show, title: attend.titled(c.workspace, c.title, (w) => names.get(w) ?? null) });
        }
        case "bring":
          return Effect.as(core.stations.bringPushed(c.station, c.session, c.seq), null);
      }
    };
    handlers.pushRegister = (_inner, call) => {
      const c = call as Extract<Call, { kind: "pushRegister" }>;
      return Effect.gen(function* () {
        if (!attend.on()) return null;
        yield* Effect.ignore(core.host.storageSet(PUSH_KEY, new TextEncoder().encode(JSON.stringify({ registration: c.registration, with: [], lang: null }))), { log: "Unhandled", message: "push registration kept" });
        const r = (yield* self.#registered()) as { _tag: string; failure?: J };
        if (r._tag === "Failure") return yield* Effect.fail(r.failure);
        return null;
      });
    };
    handlers.pushUnregister = () =>
      Effect.gen(function* () {
        attend.setPushing(false);
        const kept = parseJson(yield* Effect.orElseSucceed(core.host.storageGet(PUSH_KEY), () => null)) as J;
        yield* Effect.ignore(core.host.storageDelete(PUSH_KEY), { log: "Unhandled", message: "push registration removed" });
        if (isObject(kept) && isObject(kept.registration)) {
          const gone: J = {};
          for (const k of ["endpoint", "token"]) if ((kept.registration as J)[k] !== undefined) gone[k] = (kept.registration as J)[k];
          for (const account of core.accounts.list()) yield* Effect.ignore(core.provider.request(account.sub, "DELETE", "/v1/push", gone), { log: "Unhandled", message: "push registration deleted" });
        }
        return null;
      });
  }
}
