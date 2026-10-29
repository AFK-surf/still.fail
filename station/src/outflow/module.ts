// Data outflow as a part of the station (parts.ts, docs/data-outflow.md): its socket for the programs of this machine
// (macOS, where still.fail Helper says who a program is; Linux, by its executable), its grants and the requests the
// workspace's admins answer, the routes the members list them with and the admins answer and revoke them with
// (GET /outflow/grants, POST /outflow/requests/:id, DELETE /outflow/grants/:id) and the event that tells them
// (`outflow-grants`, to the home workspace's members; how many on the overview, `outflowGrants`); and what the
// other stations of the workspace read of this one for a program granted the whole workspace there (`outflow.read`).
import { Effect, Layer } from "effect";
import { readlink } from "node:fs/promises";
import type { Socket } from "node:net";
import { routes } from "../api/routes/outflow.ts";
import type { HelperApp } from "../helper/app.ts";
import { bytesOf } from "../mesh/bus.ts";
import { managesStation } from "../mesh/credential.ts";
import { loadMesh } from "../mesh/native.ts";
import { platform } from "../platform/index.ts";
import { wall } from "../ops/fibers.ts";
import { stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { ControlPlane, Events, Helper, Parts, Paths, Peers, Previous, Readers } from "../services.ts";
import { type Identity, OutflowGrants } from "./grants.ts";
import { READ, peerRead, textOf } from "./peer.ts";
import { type Identify, OutflowServer, type StationEntry, fileHash, socketPath } from "./server.ts";

type Peer = (fd: number) => { pid: number; auditToken: string | null } | null;

const fdOf = (socket: Socket) => (socket as unknown as { _handle?: { fd?: number } })._handle?.fd;

/// Who the other end of `socket` is: its audit token, then its signature as still.fail Helper reads it. An unsigned
/// one by its executable's bytes too.
export function helperIdentify(helper: HelperApp, peer: Peer): Identify {
  return async (socket: Socket) => {
    const fd = fdOf(socket);
    const at = typeof fd === "number" && fd >= 0 ? peer(fd) : null;
    if (!at?.auditToken) return null;
    const got = await helper.request({ op: "outflow.identify", auditToken: at.auditToken }).catch(() => null);
    if (got === null || typeof got.path !== "string") return null;
    const text = (v: unknown) => (typeof v === "string" && v !== "" ? v : null);
    const identity: Identity = {
      path: got.path, valid: got.valid === true, teamId: text(got.teamId), identifier: text(got.identifier), signer: text(got.signer), app: text(got.app), sha256: null,
    };
    if (!identity.valid || identity.teamId === null) identity.sha256 = await fileHash(identity.path);
    return identity;
  };
}

/// Linux: the other end of `socket` by its executable (SO_PEERCRED's pid, /proc/<pid>/exe) and that file's bytes:
/// there are no code signatures to say more.
export function procIdentify(peer: Peer): Identify {
  return async (socket: Socket) => {
    const fd = fdOf(socket);
    const at = typeof fd === "number" && fd >= 0 ? peer(fd) : null;
    if (!at || at.pid <= 0) return null;
    const path = await readlink(`/proc/${at.pid}/exe`).catch(() => null);
    if (path === null) return null;
    const sha256 = await fileHash(path);
    if (sha256 === null) return null;
    return { path, valid: false, teamId: null, identifier: null, signer: null, app: null, sha256 };
  };
}

export const OutflowLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const readers = yield* Readers;
    const helper = yield* Helper;
    const events = yield* Events;
    const bus = yield* Peers;
    const cloud = (yield* ControlPlane).state;
    const previous = yield* Previous;
    const grants = new OutflowGrants(data, wall.now);
    const tell = () => {
      events.tell("outflow-grants", { grants: grants.list(), requests: grants.asking() }, "outflow-grants", { sees: { ws: null } });
      events.overviewChanged();
    };
    yield* Effect.acquireRelease(
      Effect.sync(() => grants.listen(tell)),
      (stop) => Effect.sync(stop),
    );
    const parts = yield* Parts;
    parts.routes(routes(grants));
    // How many there are, and requests waiting, on the station's overview: a page asks for them only when there are.
    parts.overview("outflowGrants", (viewer) => (viewer.home !== false ? grants.list().length + grants.asking().length : 0));
    // Whether the viewer answers requests: an admin of the home workspace.
    parts.overview("outflowAnswers", (viewer) => viewer.home !== false && managesStation(viewer));
    // Another station of the workspace reading this one's chats of it, for a program granted the workspace there.
    bus.on(READ, peerRead((op, args, lang) => readers.read(op, args, lang), () => cloud.home(), stationLang));
    const here = (): StationEntry => ({ id: cloud.state?.station ?? "", name: cloud.state?.name ?? "", here: true });
    const workspace = {
      here,
      stations: async (): Promise<StationEntry[]> => {
        const home = cloud.home();
        if (home === null) return [];
        const roster = await bus.ask("", { method: "peers", workspace: home });
        if (roster?.current !== true) throw new Error("the roster is not current");
        const id = here().id;
        return (Array.isArray(roster?.stations) ? roster.stations : [])
          .filter((e: any) => typeof e?.id === "string" && e.id !== "")
          .map((e: any) => ({ id: e.id, name: typeof e.name === "string" ? e.name : e.id, here: e.id === id }));
      },
      read: async (station: string, op: string, args: unknown) => {
        const got = await bus.ask(station, { method: READ, workspace: cloud.home(), op, args, whole: true });
        const bytes = bytesOf(got);
        if (bytes === null) throw new Error("that station answered without its data");
        return textOf(bytes);
      },
    };
    // Who a program is: still.fail Helper says it on macOS, the executable on Linux; both need the addon that says
    // the other end of a socket.
    const peer = loadMesh().peerProcess;
    const identify = peer === undefined ? null : helper !== null ? helperIdentify(helper, peer) : platform.os === "linux" ? procIdentify(peer) : null;
    if (identify === null) return;
    yield* Effect.acquireRelease(
      Effect.promise(async () => {
        const server = new OutflowServer({
          path: socketPath(data), grants, reads: (op, args, lang) => readers.read(op, args, lang), identify, workspace, lang: stationLang,
        });
        await server.listen().catch((e) => log.warn("outflow", "the outflow socket is not listened on", { error: (e as Error).message }));
        void previous.gone.then(() => server.previousGone());
        return server;
      }),
      (server) => Effect.promise(() => server.close()),
    );
  }),
);
