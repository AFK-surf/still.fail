// The vault as a part of the station (parts.ts, docs/vault.md): its store in the station's database, the agents'
// requests for its secrets and the grants they hold, its routes (the vaults, by the lock pinned in the asker's
// workspace; the requests and grants), its tools for the agents and its events (`vault-request`). A part of the agents'
// side: its requests are told in the agents' chats (the hub).
import { Effect, Layer } from "effect";
import { routes as vaultRoutes } from "../api/routes/vault.ts";
import { routes as requestRoutes } from "../api/routes/vault-requests.ts";
import { wall } from "../ops/fibers.ts";
import { Agents } from "../sessions/agents.ts";
import { sender } from "../sessions/messages.ts";
import { ControlPlane, Events, Parts, Paths, Store } from "../services.ts";
import { vaultTools } from "../tools/vault.ts";
import { plainStore } from "./plain.ts";
import { Secrets } from "./secrets.ts";
import { vaultStore } from "./store.ts";

export const VaultLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const events = yield* Events;
    const parts = yield* Parts;
    const cloud = (yield* ControlPlane).state;
    const { hub } = yield* Agents;
    // A workspace's lock: the home workspace's is the station's own (null), another's by its id.
    const lock = (ws: string | null) => cloud.locked(ws === null || ws === cloud.home() ? null : ws)?.state ?? null;
    const vaults = vaultStore(store.db);
    // The vault's secrets, asked for by agents and granted from the members' apps.
    const secrets = new Secrets({
      db: store.db, vaults, plain: plainStore(store.db), hub, data, home: () => cloud.home(), lock, now: () => wall.now(),
      title: (session) => sender(hub, session)[0] ?? null,
    });
    secrets.listen((r) => events.tell("vault-request", r, `vault-request\0${r.id}`, (viewer) => secrets.tells(r, viewer)));
    parts.routes([
      ...vaultRoutes({ vaults, lock: (ws) => lock(ws), events, boxed: (l, cert) => secrets.boxed(l, cert) }),
      ...requestRoutes({ secrets, plain: secrets.plain, lock: (ws) => lock(ws), events }),
    ]);
    parts.tools(vaultTools(secrets, (k) => store.getSession(k)?.workspace ?? null));
  }),
);
