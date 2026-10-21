// Copying into the station's drive (./transfers.ts, docs/drive.md "Copying between stations") as a part of the station
// (parts.ts): the transfers into it, run here and kept in its data directory, told to the asker's streams as they
// change (`drive-transfers`); its routes (api/routes/transfers.ts); and what another station of the workspace reads of
// this one's drive with a grant of its own (`drive.walk`, `drive.part`, `drive.release` on the bus).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/transfers.ts";
import { Refused } from "../mesh/bus.ts";
import { nameOf } from "../mesh/peer-http.ts";
import { wall } from "../ops/fibers.ts";
import { ControlPlane, Events, Parts, Paths, Peers, StationDrive } from "../services.ts";
import { CHUNK } from "../jobs/remote.ts";
import { type Drive, DriveError } from "./drive.ts";
import { covers, grantKey, verify, type Granted } from "./grants.ts";
import { type Source, type Transfer, Transfers, removeOrTrash, shown, walkDrive } from "./transfers.ts";

type Json = any;

/// The drive as a workspace has it: the station's own, or one it joined (its own pinned folders; routes/drive.ts driveOf).
const scoped = (drive: Drive, g: { workspace: string; home: boolean }) => (g.home ? drive : drive.scoped(g.workspace));
const join2 = (a: string, b: string) => (a === "" ? b : `${a}/${b}`);

/// What another station reads of this one's drive with a grant of this one's: its names walked, a part of a file under
/// them, the originals let go once moved.
export async function driveForPeer(drive: Drive, key: Buffer, request: Json, workspace: string | null, now: number): Promise<Json> {
  try {
    const g: Granted = verify(key, request?.grant, workspace, now);
    const d = scoped(drive, g);
    switch (request?.method) {
      case "drive.walk": {
        const names = Array.isArray(request.names) ? request.names.filter((n: unknown) => typeof n === "string" && g.names.includes(n)) : g.names;
        return { items: await walkDrive(d, g.root, g.path, names, g.anywhere) };
      }
      case "drive.part": {
        const path = typeof request.path === "string" ? request.path : "";
        const offset = typeof request.offset === "number" && Number.isSafeInteger(request.offset) && request.offset >= 0 ? request.offset : -1;
        if (!covers(g, path) || offset < 0) throw new DriveError("permission", "that is not what was granted");
        const got = await d.read(g.root, join2(g.path, path), offset, CHUNK, g.anywhere);
        return { data: got.bytes.toString("base64"), size: got.total, mtime: got.mtime };
      }
      case "drive.release": {
        if (!g.move) throw new DriveError("permission", "that grant copies, and does not move");
        const names = Array.isArray(request.names) ? request.names.filter((n: unknown) => typeof n === "string" && g.names.includes(n)) : [];
        for (const name of names) await removeOrTrash(d, g.root, join2(g.path, name), g.anywhere);
        return {};
      }
      default:
        throw new DriveError("invalid_request", `unknown method ${String(request?.method)}`);
    }
  } catch (e) {
    // The other station is told why, as a refusal (not a request that did not get through), with the drive's code.
    throw new Refused(e instanceof DriveError ? `${e.code}: ${e.message}` : (e as Error).message);
  }
}

/// Another station's drive as a transfer's source: read over the station transport with its grant.
export function peerSource(ask: (station: string, request: Json) => Promise<Json>, t: Transfer): Source {
  const station = t.from.station!;
  const base = { workspace: t.workspace, grant: t.from.grant };
  return {
    station,
    part: CHUNK,
    walk: async (names) => {
      const got = await ask(station, { ...base, method: "drive.walk", names });
      return { items: Array.isArray(got?.items) ? got.items : [] };
    },
    read: async (path, offset) => {
      const got = await ask(station, { ...base, method: "drive.part", path, offset });
      if (typeof got?.data !== "string" || typeof got.size !== "number") throw new Error(`${station} answered no part of ${path}`);
      return { bytes: Buffer.from(got.data, "base64"), size: got.size, mtime: typeof got.mtime === "number" ? got.mtime : 0 };
    },
    release: async (names) => void (await ask(station, { ...base, method: "drive.release", names })),
  };
}

/// This station's id (mesh/cloud.json, as the remote tasks read it); null when it has none.
function ownId(data: string): string | null {
  try {
    const id = JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8"))?.station;
    return typeof id === "string" && id !== "" ? id : null;
  } catch {
    return null;
  }
}

export const DriveTransfersLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const drive = yield* StationDrive;
    const bus = yield* Peers;
    const events = yield* Events;
    const parts = yield* Parts;
    const cloud = (yield* ControlPlane).state;
    const key = grantKey(data);
    const now = () => wall.now();
    const transfers = yield* Effect.acquireRelease(
      Effect.sync(
        () =>
          new Transfers({
            dir: join(data, "drive-transfers"),
            driveFor: (t) => scoped(drive, t),
            remote: (t) => peerSource((station, request) => bus.ask(station, request), t),
            now,
            // Told to the asker's own streams, the latest kept for one coming back.
            changed: (t) => events.tell("drive-transfers", { transfer: shown(t) }, `drive-transfer\0${t.id}`, (viewer) => viewer.email === t.by),
          }),
      ),
      (t) => Effect.sync(() => t.close()),
    );
    bus.on("drive.", (_peer, request, workspace) => driveForPeer(drive, key, request, workspace ?? null, now()));
    parts.routes(routes({ drive, transfers, key, self: () => ownId(data), nameOf: (station) => nameOf(cloud, station), now }));
  }),
);
