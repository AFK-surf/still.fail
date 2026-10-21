// Copying into the station's drive (drive/transfers.ts, docs/drive.md "Copying between stations"), as members ask it:
// POST /drive/grant lets another station read names of a folder here for the asker (a read-only member: of a folder
// pinned, and only to copy); POST /drive/transfers copies (or moves) names of a folder here or of another station's
// (with what it granted) into a folder here, which only a member who may write asks; GET /drive/transfers says the
// asker's own, and POST /drive/transfers/<id>/cancel or /retry stops one or takes one that failed up again.
import { type Request, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { readOnly } from "../../mesh/credential.ts";
import { type Drive, DriveError } from "../../drive/drive.ts";
import { type Conflict, type Transfers, shown, walkDrive } from "../../drive/transfers.ts";
import { GRANT_MS, type Granted, sign } from "../../drive/grants.ts";
import { driveOf, refused } from "./drive.ts";

export type TransferRouteDeps = {
  drive: Drive;
  transfers: Transfers;
  /// The station's key for its grants (drive/grants.ts).
  key: Buffer;
  /// This station's id: a transfer from it is from its own drive.
  self: () => string | null;
  /// A station of the workspace by its id, as its name.
  nameOf: (station: string) => string;
  now: () => number;
};

const anywhere = (r: Request) => !readOnly(r.viewer);

function body(r: Request): Record<string, any> {
  try {
    const v = JSON.parse(r.body.toString("utf8") || "{}");
    if (v !== null && typeof v === "object" && !Array.isArray(v)) return v;
  } catch {}
  throw new DriveError("invalid_request", "a JSON object");
}

const text = (v: unknown, name: string): string => {
  if (typeof v !== "string") throw new DriveError("invalid_request", `${name} is required`);
  return v;
};

/// Names of a folder: at least one, each a name and not a path.
const namesOf = (v: unknown): string[] => {
  if (!Array.isArray(v) || v.length === 0 || v.length > 1000 || v.some((n) => typeof n !== "string" || n === "" || n === "." || n === ".." || n.includes("/") || n.includes("\0"))) {
    throw new DriveError("invalid_request", "names: 1 to 1000 names of the folder");
  }
  return [...new Set(v as string[])];
};

const conflictsOf = (v: unknown): Record<string, Conflict> => {
  const out: Record<string, Conflict> = {};
  if (v === undefined || v === null) return out;
  if (typeof v !== "object" || Array.isArray(v)) throw new DriveError("invalid_request", "conflicts: name → replace | keep | skip");
  for (const [name, answer] of Object.entries(v)) {
    if (answer !== "replace" && answer !== "keep" && answer !== "skip") throw new DriveError("invalid_request", "conflicts: name → replace | keep | skip");
    out[name] = answer;
  }
  return out;
};

export function routes({ drive, transfers, key, self, nameOf, now }: TransferRouteDeps): Route[] {
  const answer = (f: (r: Request, groups: string[]) => Promise<unknown>) => async (r: Request, groups: string[] = []) => {
    try {
      return json(200, JSON.stringify(await f(r, groups)));
    } catch (e) {
      return refused(e, r.lang);
    }
  };
  return [
    {
      method: "POST",
      pattern: /^\/drive\/grant$/,
      handle: answer(async (r) => {
        const b = body(r);
        const root = text(b.root, "root");
        const path = typeof b.path === "string" ? b.path : "";
        const names = namesOf(b.names);
        const move = b.move === true;
        // Moving lets the originals go: a member who may write here.
        if (move && !anywhere(r)) throw new DriveError("permission", "a read-only member copies, and does not move");
        // Each name read as this member reads it, so what they may not read is refused here and now.
        await walkDrive(driveOf(drive, r), root, path, names, anywhere(r));
        const expires = now() + GRANT_MS;
        const g: Granted = { v: 1, workspace: r.viewer.workspace, home: r.viewer.home !== false, by: r.viewer.email, anywhere: anywhere(r), root, path, names, move, expires };
        return { grant: sign(key, g), expires };
      }),
    },
    {
      method: "POST",
      pattern: /^\/drive\/transfers$/,
      handle: answer(async (r) => {
        // Writing here: a member who may write.
        if (!anywhere(r)) throw new DriveError("permission", "a read-only member does not copy into a station");
        const b = body(r);
        const from = b.from !== null && typeof b.from === "object" ? b.from : {};
        const to = b.to !== null && typeof b.to === "object" ? b.to : {};
        const names = namesOf(from.names);
        const station = typeof from.station === "string" && from.station !== "" && from.station !== self() ? from.station : null;
        if (station !== null && typeof from.grant !== "string") throw new DriveError("invalid_request", "from.grant is required for another station's files");
        const into = { root: text(to.root, "to.root"), path: typeof to.path === "string" ? to.path : "" };
        // Where they go must be a folder this member may write in.
        const listed = await driveOf(drive, r).stat(into.root, into.path, true);
        if (!listed.dir) throw new DriveError("not_a_directory", "that is not a folder");
        const t = transfers.start({
          by: r.viewer.email,
          workspace: r.viewer.workspace,
          home: r.viewer.home !== false,
          anywhere: true,
          move: b.move === true,
          from: {
            station,
            ...(station !== null ? { stationName: nameOf(station), grant: from.grant as string } : {}),
            root: text(from.root, "from.root"),
            path: typeof from.path === "string" ? from.path : "",
            names,
          },
          to: into,
          conflicts: conflictsOf(b.conflicts),
        });
        return { transfer: shown(t) };
      }),
    },
    { method: "GET", pattern: /^\/drive\/transfers$/, handle: answer(async (r) => ({ transfers: transfers.list(r.viewer.email).map(shown) })) },
    {
      method: "POST",
      pattern: /^\/drive\/transfers\/([A-Za-z0-9]{1,64})\/(cancel|retry)$/,
      handle: answer(async (r, [id, what]) => {
        const t = what === "cancel" ? transfers.cancel(r.viewer.email, id!) : transfers.retry(r.viewer.email, id!);
        return { transfer: shown(t) };
      }),
    },
  ];
}
