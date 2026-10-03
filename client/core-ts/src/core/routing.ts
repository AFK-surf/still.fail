// Topic routing and derived subscription values (core/routing.rs): station topics go to the stations module, views to
// the views, the account topics are kept here, the core's own are computed when they go out.
import type { Inner } from "../core.ts";
import { isView, topicStation, type Topic } from "../protocol.ts";
import { RECHECKING } from "../station/words.ts";
import * as status from "../status.ts";
import type { Source, Value } from "../store.ts";
import * as accountState from "./account_state.ts";

/// The topics the core keeps itself and computes when they go out (status.rs, doing.rs, …).
const OWN = new Set(["status", "notices", "notify", "previewLoad", "doing", "adbShare", "slackTokens", "connectFlow", "decisionForm", "profileFlow"]);
/// Kept on the device (data.ts) and nowhere else.
const KEPT = new Set(["draft", "prefs"]);

/// What a module that owns topics of its own plugs in (pill.ts, choose.ts, jobs.ts, changelog.ts, the views…).
export interface Owner {
  owns(topic: Topic): boolean;
  start(topic: Topic): void;
  stop(topic: Topic): void;
  compute?(topic: Topic): Value | undefined;
}

export class Router implements Source {
  readonly #core: Inner;
  /// Later modules, in the order the Rust router asks them.
  readonly owners: Owner[] = [];
  /// The core's own topics' values, by topic name (notices, notify, adbShare, the flows…).
  readonly computers = new Map<string, (topic: Topic) => Value | undefined>();

  constructor(core: Inner) {
    this.#core = core;
  }

  start(topic: Topic): void {
    const core = this.#core;
    // Always kept: only computed while shown.
    if (OWN.has(topic.topic) || KEPT.has(topic.topic)) {
      core.store.invalidate(topic);
      return;
    }
    const owner = this.owners.find((o) => o.owns(topic));
    if (owner) return owner.start(topic);
    if (isView(topic) || topicStation(topic) !== null) {
      core.parts.stations?.start(topic);
      return;
    }
    accountState.startTopic(core, topic);
  }

  stop(topic: Topic): void {
    const core = this.#core;
    if (OWN.has(topic.topic) || KEPT.has(topic.topic)) return;
    const owner = this.owners.find((o) => o.owns(topic));
    if (owner) return owner.stop(topic);
    if (isView(topic) || topicStation(topic) !== null) {
      core.parts.stations?.stop(topic);
      return;
    }
    accountState.stopTopic(core, topic);
  }

  compute(topic: Topic): Value | undefined {
    const core = this.#core;
    switch (topic.topic) {
      case "status":
        return { ok: this.statusValue(typeof topic.workspace === "string" ? topic.workspace : null) };
      case "doing": {
        // A write on a station that went quiet is being asked again (station.ts): it says so.
        const rechecking = (params: Map<string, string>) => {
          const address = params.get("station");
          return address !== undefined && core.workspaces.ofStation(address).status.waits({ station: address }, RECHECKING());
        };
        return { ok: core.doing.value(rechecking) };
      }
      case "draft":
        return { ok: { text: "", quotes: [], files: [] } };
      case "prefs":
        return { ok: {} };
    }
    const own = this.computers.get(topic.topic);
    if (own) return own(topic);
    const owner = this.owners.find((o) => o.owns(topic));
    return owner?.compute?.(topic);
  }

  /// What is waited on: of a workspace, its own waits, its account's socket and the relay opened for no station; of
  /// none, every workspace's and all the device's.
  statusValue(workspace: string | null): unknown {
    const core = this.#core;
    if (workspace !== null) {
      const of = core.workspaces.of(workspace);
      const owner = of.owner !== null ? [of.owner] : [];
      return status.value([
        [of.status, "all"],
        [core.status, { for: owner }],
      ]);
    }
    const parts: [status.Status, status.Take][] = core.workspaces.all().map((w) => [w.status, "all"]);
    parts.push([core.status, "all"]);
    return status.value(parts);
  }
}
