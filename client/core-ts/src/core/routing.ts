// Topic routing and the values the core computes as they go out. Subscriptions only read what is
// held (rule 6): nothing here asks the network for anything; a topic with nothing held yet shows nothing (or why it
// cannot have anything), and fills in as the sync brings it.
import type { Inner } from "../core.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { RECHECKING } from "../station/words.ts";
import { Loads } from "../preview-load.ts";
import * as status from "../status.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { computed, type Derived } from "../reactive.ts";
import type { Source, Value } from "../store.ts";
import { timed } from "../spent.ts";

/// What a module that owns topics of its own plugs in (the station topics, the views, …).
export interface Owner {
  owns(topic: Topic): boolean;
  start?(topic: Topic): void;
  resume?(topic: Topic): void;
  stop?(topic: Topic): void;
  compute?(topic: Topic): Value | undefined;
  waits?(topic: Topic): boolean;
  opened?(topic: Topic): void;
}

/// Whether two values `after` made of one are the same: each field the very same, a list's items each the very same
/// (what it puts in a chat: its unread line, the messages said and the agents started while it shows).
function sameSaid(a: Value | undefined, b: Value | undefined): boolean {
  if (a === undefined || b === undefined || !("ok" in a) || !("ok" in b)) return a === b;
  const [x, y] = [a.ok as Record<string, unknown>, b.ok as Record<string, unknown>];
  if (x === y) return true;
  if (typeof x !== "object" || typeof y !== "object" || x === null || y === null) return false;
  const keys = Object.keys(x);
  if (keys.length !== Object.keys(y).length) return false;
  return keys.every((k) => {
    const [u, w] = [x[k], y[k]];
    if (u === w) return true;
    return Array.isArray(u) && Array.isArray(w) && u.length === w.length && u.every((item, i) => item === w[i]);
  });
}

export class Router implements Source {
  readonly #core: Inner;
  readonly owners: Owner[] = [];
  /// What a topic's value goes through once computed (a chat as its UIs attend to it), and the topics it changes
  /// (`attends`): their value is made in a computed of their own (#made), apart from what `after` reads, so a UI's focus
  /// moving (`client.focus`, sent at every switch of workspace or chat, whatever it shows) puts the chat as it was made
  /// through `after` again, and does not make it again (3-6 ms in Hermes, twice as a switch of workspace committed onto
  /// a chat, 2026-11-11).
  after: (topic: Topic, value: Value | undefined) => Value | undefined = (_topic, value) => value;
  attends: (topic: Topic) => boolean = () => false;
  readonly #made = new Map<string, { value: Derived<Value | undefined>; said: { of: Value | undefined; out: Value | undefined } | undefined }>();

  constructor(core: Inner) {
    this.#core = core;
  }

  start(topic: Topic): void {
    const owner = this.owners.find((o) => o.owns(topic));
    if (owner?.start) timed(`${topic.topic}.start`, () => owner.start!(topic));
    // Computed when it goes out: its first value now.
    this.#core.store.invalidate(topic);
  }

  resume(topic: Topic): void {
    this.owners.find((o) => o.owns(topic))?.resume?.(topic);
  }

  opened(topic: Topic): void {
    this.owners.find((o) => o.owns(topic))?.opened?.(topic);
  }

  stop(topic: Topic): void {
    this.#made.delete(topicKey(topic));
    this.owners.find((o) => o.owns(topic))?.stop?.(topic);
  }

  waits(topic: Topic): boolean {
    return this.owners.find((o) => o.owns(topic))?.waits?.(topic) === true;
  }

  compute(topic: Topic): Value | undefined {
    const core = this.#core;
    switch (topic.topic) {
      case "accounts":
        return { ok: core.accounts.list() };
      case "workspaces":
        // What the accounts' `/v1/me` said, as held; nothing while no account's is.
        if (core.accounts.list().length > 0 && !core.accounts.list().some((a) => core.data.record("me", a.sub) !== undefined || core.cloudSync.mes.has(a.sub))) return undefined;
        return { ok: core.cloudSync.workspacesValue() };
      case "workspace": {
        const error = core.cloudSync.workspaceError(topic.workspace as string);
        return error ? { err: error } : undefined;
      }
      case "loginSessions":
      case "admin": {
        // An account signed out: nothing of it is shown any more.
        if (!core.accounts.list().some((a) => a.sub === topic.account)) return { err: CoreError.signedOut(t("core-logic.accounts.signed_out")) };
        const error = core.cloudSync.topicError(topic);
        return error ? { err: error } : undefined;
      }
      case "status":
        return { ok: this.statusValue(typeof topic.workspace === "string" ? topic.workspace : null) };
      case "doing": {
        // A write on a station that went quiet is being asked again: it says so.
        const rechecking = (params: Map<string, string>) => {
          const address = params.get("station");
          return address !== undefined && core.workspaces.ofStation(address).status.waits({ station: address }, RECHECKING());
        };
        return { ok: core.doing.value(rechecking) };
      }
      case "draft":
        return { ok: { text: "", quotes: [], files: [] } };
      case "composer":
        return { ok: core.composers.value(String(topic.key)) };
      case "adbShare":
        return { ok: core.adb.value() };
      case "adbCard":
        return { ok: core.adb.card(String(topic.station)) };
      case "rigs":
        return { ok: core.rigs.value(String(topic.workspace)) };
      case "devices":
        return { ok: core.devices.value(String(topic.workspace)) };
      case "previewLoad":
        return { ok: core.workspaces.ofStation(topic.station as string).part("previewLoad", () => new Loads()).value(topic) };
      case "prefs":
        return { ok: {} };
      case "drivePlace":
        return { ok: null };
    }
    const owner = this.owners.find((o) => o.owns(topic));
    if (!this.attends(topic)) return this.after(topic, owner?.compute?.(topic));
    // (made in a computed of its own: what `after` alone reads, a UI's focus, puts it through again as it was made)
    const key = topicKey(topic);
    let made = this.#made.get(key);
    if (made === undefined) this.#made.set(key, (made = { value: computed(() => owner?.compute?.(topic)), said: undefined }));
    const value = made.value.get();
    const said = this.after(topic, value);
    // (and as it went through before where that made the same of it: the very value, which goes out as it did)
    if (made.said !== undefined && made.said.of === value && sameSaid(made.said.out, said)) return made.said.out;
    made.said = { of: value, out: said };
    return said;
  }

  /// What is waited on: of a workspace, its own waits, its account's socket and the relay opened for no station; of
  /// none, every workspace's and all the device's, each station said with its workspace's name when there are several
  /// (one station may be in several workspaces).
  statusValue(workspace: string | null): unknown {
    const core = this.#core;
    if (workspace !== null) {
      const of = core.workspaces.of(workspace);
      return status.value([
        [of.status, "all"],
        [core.status, { for: of.owner !== null ? [of.owner] : [] }],
      ]);
    }
    const all = core.workspaces.all();
    const parts: [status.Status, status.Take, string | null][] = all.map((w) => [w.status, "all", all.length > 1 ? (core.cloudSync.workspaceName(w.id) ?? w.id) : null]);
    parts.push([core.status, "all", null]);
    return status.value(parts);
  }
}
