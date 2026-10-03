// The choose calls (core/execute.rs `Call::Choose`) and the profiles checked once a run as their station's overview
// comes in (choose.rs did it as a new chat's page was computed; here the sync does it, whatever is shown: rule 6).
import { Effect } from "effect";
import { Choose } from "./choose.ts";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import * as ops from "./ops.ts";
import { Priority } from "./sync/scheduler.ts";
import { asCoreError } from "./error.ts";
import { arr as arrU, get as getU } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

export function installChoose(inner: Inner): Choose {
  const choose = new Choose({ store: inner.store, data: inner.data, now: () => inner.host.nowMs(), agent: (station, key) => inner.views.agent(station, key) });
  inner.router.owners.push(choose);
  // A profile its station has not checked since it started is checked, once a run.
  const checked = new Set<string>();
  inner.data.onChange((topic) => {
    if (topic.topic !== "overview") return;
    const station = topic.station as string;
    for (const p of arr(get(inner.data.get(topic), "profiles"))) {
      const id = typeof get(p, "id") === "string" ? p.id : "";
      if (id === "" || (get(p, "check") !== undefined && p.check !== null)) continue;
      const key = `${station}\u0001${id}`;
      if (checked.has(key)) continue;
      checked.add(key);
      const op = ops.request("profile.check", { station, id });
      if (op === null) continue;
      inner.scheduler.enqueue(station, `${station} profile.check/${id}`, Priority.background, Effect.asVoid(inner.stations.perform(op, null)));
    }
  });
  handlers.choose = (_inner, call, progress, at, ctx) => {
    const c = call as Extract<Call, { kind: "choose" }>;
    const params = c.params;
    const field = (f: string) => (typeof params[f] === "string" ? (params[f] as string) : "");
    return Effect.suspend((): Effect.Effect<unknown, import("./error.ts").CoreError> => {
      const attempt = <A>(f: () => A) => Effect.try({ try: f, catch: asCoreError });
      switch (c.name) {
        case "newChat.pick":
          return Effect.as(attempt(() => choose.pickNew(field("scope"), params)), null);
        case "newChat.migrate":
          return Effect.as(attempt(() => choose.migrate(params)), null);
        case "newChat.create":
          return Effect.gen(function* () {
            const ask = yield* attempt(() => choose.create(field("station")));
            const made = yield* handlers.chatCreate!(inner, { kind: "chatCreate", station: field("station"), ask }, progress, at, ctx);
            choose.used(field("station"), ask);
            return { key: get(made, "key") ?? null, runtime: ask.runtime ?? null, model: ask.model ?? null, effort: ask.effort ?? null };
          });
        case "pick.set":
          return Effect.as(attempt(() => choose.set(field("station"), field("of"), params)), null);
        default:
          return Effect.gen(function* () {
            const saved = yield* attempt(() => choose.save(field("station"), field("of")));
            if ("done" in saved) return saved.done;
            yield* handlers.op!(inner, { kind: "op", op: saved.op }, progress, at, ctx);
            return { saved: true };
          });
      }
    });
  };
  return choose;
}
