// The other stations of a workspace as places for a station's copies (replica/AGENTS.md): which of them keep a
// station's (rendezvous over the workspace's stations, the same answer on every station, nobody choosing), the place
// one of them is over the station transport (`replica.*`), and what a station answers of those it keeps.
import { createHash } from "node:crypto";
import { stat } from "node:fs/promises";
import { type Bytes, Refused, bytesOf, withBytes } from "../mesh/bus.ts";
import { fileBytes, oneBytes, readBytes, stopBytes } from "../mesh/files.ts";
import { BATCH, GEN, HASH, STATION, WORKSPACE } from "./format.ts";
import { type FolderPlace, type Held, type Place, nothingHeld } from "./places.ts";

type Json = any;

/// How many other stations keep a station's copies: two where there are, one where there is one other.
export const COPIES = 2;
/// A batch, a head or a listing at most, as a request's or an answer's bytes (a batch is folded long before).
export const MOST = 256 * 1024 * 1024;

/// The stations that keep `origin`'s copies in `ws`, of `stations` (the workspace's, as its roster says): the
/// min(COPIES, others) whose hash with it is highest. A station added or gone moves few others' copies.
export function keepers(ws: string, origin: string, stations: readonly string[]): string[] {
  return ranked(ws, origin, stations).slice(0, COPIES);
}

/// Every station of `stations` but `origin`, in the order they keep `origin`'s copies: the first COPIES do; while one
/// of them is not reached, the next after them does too (copies.ts `#targets`).
export function ranked(ws: string, origin: string, stations: readonly string[]): string[] {
  const others = [...new Set(stations)].filter((s) => s !== origin);
  const score = (s: string) => createHash("sha256").update(`${ws}\n${origin}\n${s}`).digest("hex");
  return others.map((s) => [score(s), s] as const).sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0)).map(([, s]) => s);
}

export type Ask = (station: string, request: Json) => Promise<Json>;

/// Another station of the workspace as a place for copies.
export class PeerPlace implements Place {
  readonly station: string;
  readonly ask: Ask;
  constructor(station: string, ask: Ask) {
    this.station = station;
    this.ask = ask;
  }

  async held(ws: string, origin: string): Promise<Held> {
    const got = await this.ask(this.station, { method: "replica.held", workspace: ws, origin, whole: true });
    const bytes = bytesOf(got);
    if (bytes === null) return nothingHeld();
    const held = JSON.parse((await readBytes(bytes, MOST)).toString("utf8")) as Held;
    return { gens: Array.isArray(held?.gens) ? held.gens : [], files: Array.isArray(held?.files) ? held.files : [] };
  }

  async put(ws: string, origin: string, gen: string, kind: "batch" | "head", name: string, bytes: Buffer): Promise<void> {
    await this.ask(this.station, withBytes({ method: "replica.put", workspace: ws, origin, gen, kind, name }, oneBytes(bytes)));
  }

  async putFile(ws: string, origin: string, hash: string, source: string | Buffer): Promise<void> {
    const bytes = Buffer.isBuffer(source) ? oneBytes(source) : fileBytes(source, 0, (await stat(source)).size);
    await this.ask(this.station, withBytes({ method: "replica.put", workspace: ws, origin, kind: "file", name: hash }, bytes));
  }

  async drop(ws: string, origin: string, gen: string, batches: string[], files: string[]): Promise<void> {
    await this.ask(this.station, { method: "replica.drop", workspace: ws, origin, gen, batches, files });
  }

  /// The stations whose copies it keeps in `ws`, each generation's head.
  async origins(ws: string): Promise<{ origin: string; heads: Json[] }[]> {
    const got = await this.ask(this.station, { method: "replica.list", workspace: ws, whole: true });
    const bytes = bytesOf(got);
    if (bytes === null) return [];
    const list = JSON.parse((await readBytes(bytes, MOST)).toString("utf8"));
    return Array.isArray(list) ? list : [];
  }

  /// A batch, a head (`gen` its generation) or a file (`gen` null) it keeps, whole.
  async read(ws: string, origin: string, gen: string | null, name: string): Promise<Bytes> {
    const got = await this.ask(this.station, { method: "replica.get", workspace: ws, origin, gen, name, whole: true });
    const bytes = bytesOf(got);
    if (bytes === null) throw new Error(`${this.station} sent nothing of ${name}`);
    return bytes;
  }
}

/// What a station answers of the copies it keeps, as `place` (<data>/replicas) holds them. `inWorkspace`: whether
/// `peer` and this station are of `ws` now (the transport said so as it took the request; asked again as an answer's
/// bytes go). `heard`: another station said what it once was (`formerly`); `hello`: another station is up and asks
/// for what it keeps of this one.
export type Serving = {
  place: FolderPlace;
  inWorkspace: (peer: string, ws: string) => boolean;
  hello: (peer: string, ws: string, formerly: string[]) => string[];
};

export function serve(s: Serving) {
  return async (peer: string, request: Json, workspace?: string): Promise<Json> => {
    const ws = typeof request?.workspace === "string" ? request.workspace : "";
    if (!WORKSPACE.test(ws) || (workspace !== undefined && workspace !== ws) || !s.inWorkspace(peer, ws)) throw new Refused("not a station of this workspace");
    const origin = typeof request?.origin === "string" ? request.origin : "";
    const bytes = bytesOf(request);
    try {
      switch (request?.method) {
        case "replica.hello":
          return { formerly: s.hello(peer, ws, Array.isArray(request.formerly) ? request.formerly.filter((f: unknown) => typeof f === "string" && STATION.test(f)) : []) };
        case "replica.list": {
          const text = Buffer.from(JSON.stringify(await s.place.origins(ws)));
          return withBytes({ size: text.length }, oneBytes(text));
        }
        case "replica.held": {
          if (!STATION.test(origin)) throw new Refused("not a station");
          const text = Buffer.from(JSON.stringify(await s.place.held(ws, origin)));
          return withBytes({ size: text.length }, oneBytes(text));
        }
        case "replica.get": {
          const gen = request.gen === null ? null : String(request.gen ?? "");
          const name = String(request.name ?? "");
          if (!STATION.test(origin) || (gen !== null && !GEN.test(gen))) throw new Refused("not a copy's name");
          const path = await s.place.pathOf(ws, origin, gen, name);
          if (path === null) throw new Refused(`${name} is not kept here`);
          const size = (await stat(path)).size;
          return withBytes({ size }, fileBytes(path, 0, size));
        }
        case "replica.put": {
          if (bytes === null) throw new Refused("nothing sent");
          const name = String(request.name ?? "");
          if (request.kind === "file") {
            if (!HASH.test(name)) throw new Refused("not a file's hash");
            await s.place.putFileFrom(ws, origin, name, bytes);
            return { ok: true };
          }
          const gen = String(request.gen ?? "");
          if (request.kind === "batch" && !BATCH.test(name)) throw new Refused("not a batch's name");
          if (request.kind !== "batch" && request.kind !== "head") throw new Refused("not a kind of copy");
          await s.place.put(ws, origin, gen, request.kind, name, await readBytes(bytes, MOST));
          return { ok: true };
        }
        case "replica.drop": {
          // Only the station a copy is of says what of it goes; the rest only add to it.
          if (peer !== origin) throw new Refused("only the station a copy is of folds it");
          const list = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
          await s.place.drop(ws, origin, String(request.gen ?? ""), list(request.batches), list(request.files));
          return { ok: true };
        }
      }
      throw new Refused("no such replica request");
    } finally {
      if (bytes !== null) await stopBytes(bytes).catch(() => {});
    }
  };
}
