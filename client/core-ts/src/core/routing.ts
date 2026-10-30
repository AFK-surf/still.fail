// Topic routing and the values the core computes as they go out (core/routing.rs). Subscriptions only read what is
// held (rule 6): nothing here asks the network for anything; a topic with nothing held yet shows nothing (or why it
// cannot have anything), and fills in as the sync brings it.
import type { Inner } from "../core.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { RECHECKING } from "../station/words.ts";
import { Loads } from "../preview-load.ts";
import * as status from "../status.ts";
import type { Topic } from "../protocol.ts";
import type { Source, Value } from "../store.ts";

/// What a module that owns topics of its own plugs in (the station topics, the views, …).
export interface Owner {
  owns(topic: Topic): boolean;
  start?(topic: Topic): void;
  resume?(topic: Topic): void;
  stop?(topic: Topic): void;
  compute?(topic: Topic): Value | undefined;
  waits?(topic: Topic): boolean;
}

export class Router implements Source {
  readonly #core: Inner;
  readonly owners: Owner[] = [];
  /// What a topic's value goes through once computed (a chat as its UIs attend to it).
  after: (topic: Topic, value: Value | undefined) => Value | undefined = (_topic, value) => value;

  constructor(core: Inner) {
    this.#core = core;
  }

  start(topic: Topic): void {
    const owner = this.owners.find((o) => o.owns(topic));
    if (owner?.start) owner.start(topic);
    // Computed when it goes out: its first value now.
    this.#core.store.invalidate(topic);
  }

  resume(topic: Topic): void {
    this.owners.find((o) => o.owns(topic))?.resume?.(topic);
  }

  stop(topic: Topic): void {
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
      case "previewLoad":
        return { ok: core.workspaces.ofStation(topic.station as string).part("previewLoad", () => new Loads()).value(topic) };
      case "prefs":
        return { ok: {} };
      case "drivePlace":
        return { ok: null };
    }
    return this.after(topic, this.owners.find((o) => o.owns(topic))?.compute?.(topic));
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
