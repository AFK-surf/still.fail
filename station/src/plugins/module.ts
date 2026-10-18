// The plugins as a part of the station (parts.ts, docs/client-plugins.md): a person's plugins kept in the station's
// database, read and deleted by their apps (routes/plugins.ts), written by their agents (tools/plugins.ts), and told
// to their apps alone as they change (`plugin`, `plugin-gone`).
import { Effect, Layer } from "effect";
import { PLUGIN_PATH, routes } from "../api/routes/plugins.ts";
import { wall } from "../ops/fibers.ts";
import { Agents } from "../sessions/agents.ts";
import { starterOf } from "../sessions/opened.ts";
import { ControlPlane, Events, Parts, Store } from "../services.ts";
import { pluginTools } from "../tools/plugins.ts";
import { PluginStore } from "./store.ts";

export const PluginsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const store = yield* Store;
    const events = yield* Events;
    const parts = yield* Parts;
    const cloud = (yield* ControlPlane).state;
    const { hub } = yield* Agents;
    const plugins = new PluginStore(store.db);
    const to = (ws: string, owner: string) => (v: { workspace: string; email: string }) => v.workspace === ws && v.email.toLowerCase() === owner;
    const of = (ws: string, owner: string, id: string) => `plugin\0${ws}\0${owner}\0${id}`;
    parts.routes(routes({ plugins, gone: (ws, owner, id) => events.tell("plugin-gone", { id }, of(ws, owner, id), to(ws, owner)) }));
    // A person deletes their own, read-only member or not.
    parts.viewerMay((r) => r.method === "DELETE" && PLUGIN_PATH.test(r.path));
    parts.tools(
      pluginTools({
        plugins,
        starter: (key) => {
          const row = store.getSession(key);
          if (row === null) return null;
          const email = starterOf(hub, key);
          const ws = row.ws ?? cloud.home();
          return email.includes("@") && ws !== null ? { owner: email.toLowerCase(), ws } : null;
        },
        exists: (key) => store.getSession(key) !== null,
        told: (ws, owner, p) => ("gone" in p ? events.tell("plugin-gone", { id: p.id }, of(ws, owner, p.id), to(ws, owner)) : events.tell("plugin", p, of(ws, owner, p.id), to(ws, owner))),
        now: () => wall.now(),
      }),
    );
  }),
);
