// Data outflow as a part of the station (parts.ts, docs/data-outflow.md): its socket for the programs of this machine
// (macOS, where still.fail Helper says who a program is and asks the person), its grants, the routes the members
// list and revoke them with (GET /outflow/grants, DELETE /outflow/grants/:id) and the event that tells them
// (`outflow-grants`, to the home workspace's members).
import { Effect, Layer } from "effect";
import type { Socket } from "node:net";
import { routes } from "../api/routes/outflow.ts";
import type { HelperApp } from "../helper/app.ts";
import { loadMesh } from "../mesh/native.ts";
import { wall } from "../ops/fibers.ts";
import { stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { Events, Helper, Parts, Paths, Readers } from "../services.ts";
import { type Identity, OutflowGrants } from "./grants.ts";
import { type Ask, type Identify, OutflowServer, fileHash, socketPath } from "./server.ts";

/// Who the other end of `socket` is: its audit token, then its signature as still.fail Helper reads it. An unsigned
/// one by its executable's bytes too.
export function helperIdentify(helper: HelperApp, peer: (fd: number) => { pid: number; auditToken: string | null } | null): Identify {
  return async (socket: Socket) => {
    const fd = (socket as unknown as { _handle?: { fd?: number } })._handle?.fd;
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

export function helperAsk(helper: HelperApp): Ask {
  return async ({ words, identity, scopes, ms, left }) => {
    const cancel = () => void helper.request({ op: "outflow.cancel" }).catch(() => {});
    left.addEventListener("abort", cancel, { once: true });
    const got = await helper.request({ op: "outflow.ask", words, identity, scopes, ms }).finally(() => left.removeEventListener("abort", cancel));
    if (got?.busy === true) return "busy";
    return got?.answer === "allow" && Array.isArray(got.scopes) ? got.scopes : null;
  };
}

export const OutflowLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const readers = yield* Readers;
    const helper = yield* Helper;
    const events = yield* Events;
    const grants = new OutflowGrants(data, wall.now);
    const tell = () => events.tell("outflow-grants", { grants: grants.list() }, "outflow-grants", { sees: { ws: null } });
    yield* Effect.acquireRelease(
      Effect.sync(() => grants.listen(tell)),
      (stop) => Effect.sync(stop),
    );
    (yield* Parts).routes(routes(grants));
    // Who a program is needs the Helper (macOS) and an addon that says the other end of a socket.
    const peer = loadMesh().peerProcess;
    if (helper === null || peer === undefined) return;
    yield* Effect.acquireRelease(
      Effect.promise(async () => {
        const server = new OutflowServer({
          path: socketPath(data), grants, reads: (op, args, lang) => readers.read(op, args, lang), identify: helperIdentify(helper, peer), ask: helperAsk(helper), lang: stationLang,
        });
        await server.listen().catch((e) => log.warn("outflow", "the outflow socket is not listened on", { error: (e as Error).message }));
        return server;
      }),
      (server) => Effect.promise(() => server.close()),
    );
  }),
);
