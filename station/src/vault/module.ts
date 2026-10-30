// The vault as a part of the station (parts.ts, docs/vault.md): its store in the station's database, the agents'
// requests for its secrets and the grants they hold, its routes (the vaults, by the lock pinned in the asker's
// workspace; the requests and grants), its tools for the agents and its events (`vault-request`), and its requests of
// the other stations (`vault.`: a command run there with a secret, a secret read there). A part of the agents' side: its
// requests are told in the agents' chats (the hub), its commands run in the remote tasks' session directories.
import { Effect, Layer } from "effect";
import { nameOf, peerNamed } from "../mesh/peer-http.ts";
import { routes as vaultRoutes } from "../api/routes/vault.ts";
import { routes as requestRoutes } from "../api/routes/vault-requests.ts";
import { wall } from "../ops/fibers.ts";
import { Agents } from "../sessions/agents.ts";
import { sender } from "../sessions/messages.ts";
import { ControlPlane, Events, Parts, Paths, Previous, Store } from "../services.ts";
import { vaultTools } from "./tool.ts";
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
    const { hub, remote } = yield* Agents;
    // A workspace's lock: the home workspace's is the station's own (null), another's by its id.
    const lock = (ws: string | null) => cloud.locked(ws === null || ws === cloud.home() ? null : ws)?.state ?? null;
    const vaults = vaultStore(store.db);
    // What the process before held may come until it is gone (it gives it as it begins to hand over).
    let coming = true;
    void (yield* Previous).gone.then(() => (coming = false), () => (coming = false));
    // The vault's secrets, asked for by agents and granted from the members' apps.
    const secrets = new Secrets({
      db: store.db, vaults, plain: plainStore(store.db), hub, data, home: () => cloud.home(), lock, now: () => wall.now(),
      title: (session) => sender(hub, session)[0] ?? null,
      // Commands with a secret on another station of the workspace (docs/vault.md 在另一台 station 上用).
      peer: (given) => {
        if (given === cloud.state?.station || cloud.memberships().some((m) => m.name.toLowerCase() === given.toLowerCase())) return null;
        const { id } = peerNamed(cloud, given);
        return { id, name: nameOf(cloud, id) };
      },
      ask: (station, request) => remote.ask(station, request),
      workOf: (ws, peer, session) => remote.work(ws, peer, session),
      coming: () => coming,
    });
    // The grants, the boxes of requests waiting and the secrets to keep, only in memory: over to the next process at a
    // handover (an update), so no agent asks again.
    parts.carry("vault", () => secrets.carried(), (what) => {
      secrets.carry(what);
      coming = false;
    });
    remote.bus.on("vault.", (peer, request, workspace) => secrets.heard(peer, workspace ?? cloud.home() ?? "", request));
    secrets.listen((r) => {
      const to = secrets.tells(r);
      if (to !== null) events.tell("vault-request", r, `vault-request\0${r.id}`, to);
    });
    events.follow({ inVault: (viewer, vault) => secrets.inVault(viewer, vault) });
    parts.routes([
      ...vaultRoutes({ vaults, lock: (ws) => lock(ws), events, boxed: (l, cert) => secrets.boxed(l, cert) }),
      ...requestRoutes({ secrets, plain: secrets.plain, lock: (ws) => lock(ws), events }),
    ]);
    parts.tools(vaultTools(secrets, (k) => store.getSession(k)?.workspace ?? null));
  }),
);
