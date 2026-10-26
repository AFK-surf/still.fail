// What a search finds on this station (docs/search.md) as a part of the station (parts.ts): its index of the station's
// data and the machine's files as they are asked for, kept current while the station runs; GET /search and its
// settings, the agents' `search` tool, and what other stations of the workspace ask of it (`search.query` on the bus).
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/search.ts";
import { rootsOf } from "../drive/drive.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Events, HelperFolders, Own, Parts, Paths, Peers, StationConfig, Store } from "../services.ts";
import { SEARCH, searchForPeer, searchTools } from "./tool.ts";
import { FileSearch } from "./files.ts";
import { Search } from "./search.ts";

export const SearchLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const config = yield* StationConfig;
    const own = yield* Own;
    const helperFiles = yield* HelperFolders;
    const store = yield* Store;
    const bus = yield* Peers;
    const events = yield* Events;
    const cloud = (yield* ControlPlane).state;
    const parts = yield* Parts;
    const { hub, place } = yield* Agents;
    // The machine's files too, never what is the station's own (ops/own.ts).
    const search = new Search({
      data,
      files: new FileSearch({
        protect: () => own.paths(),
        roots: (ws) => rootsOf(config.raw(), ws),
        personal: () => config.raw()?.search?.personal === true,
        // Documents, Desktop and Downloads through still.fail Helper, where it holds their grant (looked at in the
        // background where not known yet; nothing asks for one on a search's behalf).
        helper: helperFiles
          ? {
              granted: (tops) => {
                const unknown = tops.filter((t) => helperFiles.known(t) === undefined);
                if (unknown.length > 0) helperFiles.check(unknown);
                return tops.filter((t) => helperFiles.known(t)?.state === "granted");
              },
              search: (top, query, most, protect) => helperFiles.search(top, query, most, protect),
            }
          : null,
      }),
    });
    yield* Effect.acquireRelease(Effect.sync(() => search.start()), () => Effect.promise(() => search.stop()));
    const link = (session: string) => hub.link(session);
    // Another station of the workspace searching this one (the agents' `search` tool there).
    bus.on(SEARCH, (_peer, request, workspace) => searchForPeer({ search, link }, request, workspace ?? null, cloud.home()));
    parts.routes(routes({ search, config, events }));
    parts.tools(
      searchTools({
        search,
        workspaceOf: (session) => {
          const row = store.getSession(session);
          if (!row) return null;
          const home = cloud.home();
          return { workspace: row.ws ?? home ?? "", home: row.ws === null || row.ws === home };
        },
        link,
        stations: async (workspace) => {
          const roster = await bus.ask("", { method: "peers", workspace });
          const station = place()?.station ?? "";
          return (Array.isArray(roster?.stations) ? roster.stations : [])
            .filter((e: any) => typeof e?.id === "string" && e.id !== "")
            .map((e: any) => ({ id: e.id, name: typeof e.name === "string" ? e.name : e.id, here: e.id === station }));
        },
        ask: (station, request) => bus.ask(station, request),
      }),
    );
  }),
);
