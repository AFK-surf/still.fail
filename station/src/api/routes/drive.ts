// The station's drive (src/drive/drive.ts) as members ask it. GET /drive says its pinned folders, and what the viewer
// may do; PUT /drive/roots pins them (any member but a read-only one, kept in config.json `drive.roots`), GET
// /drive/folders lists the folders of a place. The rest is a path under a root (`root`, `path` relative to it, `/`
// between components; `root` any absolute path for a member who may write, one pinned for a read-only one): GET
// /drive/list, /drive/stat and /drive/read (a part of a file: `offset`, `length`); PUT /drive/upload (a part of a file
// written: `id`, `offset`, `total`, `replace`; its bytes the body), POST /drive/mkdir, /drive/rename, /drive/remove
// and /drive/stage (a file copied among the uploads, or a folder zipped there, for a message to send; a JSON body). Read-only members only read
// (the admin API refuses their writes). A refusal is `{error, code}` with the code's status (CODES).
import { homedir } from "node:os";
import { type Answer, type Request, json, param } from "../request.ts";
import type { Route } from "../admin.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import { readOnly } from "../../mesh/credential.ts";
import { CODES, Drive, DriveError, MAX_READ, MOST_ROOTS, TOO_BIG, rootsOf } from "../../drive/drive.ts";
import { FolderWatches } from "../../drive/watch.ts";

export type DriveRouteDeps = {
  drive: Drive; config: ConfigFile; home?: string; changed?: () => void;
  /// Where a file sent in a chat waits for its message (the uploads), with a name of its own: none, no /drive/stage.
  stage?: (name: string) => { safe: string; path: string };
};

const manages = (r: { viewer: { role: string } }) => r.viewer.role === "owner" || r.viewer.role === "admin";
/// Whether the asker reaches every folder of the machine: a member who may write, whose agents could reach them anyway.
const anywhere = (r: { viewer: Request["viewer"] }) => !readOnly(r.viewer);
/// The drive as the asker's workspace has it: the folders that workspace pinned (docs/multi-workspace.md).
const driveOf = (drive: Drive, r: { viewer: Request["viewer"] }) => (r.viewer.home === false ? drive.scoped(r.viewer.workspace) : drive);

/// A refusal in the asker's words (`station.drive.<code>`, after the path it is about, if any).
const refused = (e: unknown, lang: Lang): Answer => {
  const d = e instanceof DriveError ? e : new DriveError("io", (e as Error).message);
  const words = tr(lang, d.code === "permission" && d.message === MANAGE ? "station.drive.manage" : d.code === "too_large" && d.message === TOO_BIG ? "station.drive.tooBigToSend" : `station.drive.${d.code}`);
  return json(CODES[d.code], JSON.stringify({ error: d.about ? `${d.about}: ${words}` : words, code: d.code, ...(d.have !== undefined ? { have: d.have } : {}) }));
};

const MANAGE = "a read-only member does not pin folders";

/// A number from the query: its fallback when not there, -1 when not one.
const num = (r: Request, name: string, fallback: number) => {
  const v = param(r, name);
  return v === undefined ? fallback : /^[0-9]+$/.test(v) ? Number(v) : -1;
};

function body(r: Request): Record<string, unknown> {
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

/// What GET /drive and the overview say: the folders pinned, what the viewer may do, and, for one who reaches every
/// folder (`anywhere`), the home to start from.
export const driveView = (drive: Drive, r: { viewer: Request["viewer"] }, home = homedir()) => ({
  roots: driveOf(drive, r).roots(), manage: manages(r), write: !readOnly(r.viewer), ...(anywhere(r) ? { anywhere: true, home } : {}),
  // What is deleted goes to the machine's trash (macOS, Linux); folders are watched for what changes in them, and zipped
  // to download.
  ...(process.platform === "darwin" || process.platform === "linux" ? { trash: true } : {}), watch: true, ...(anywhere(r) ? { zip: true } : {}),
});

/// The most a file sent in a chat from the drive is (as an upload in parts).
const MOST_STAGED = 1024 * 1024 * 1024;

export function routes({ drive: whole, config, home = homedir(), changed, stage }: DriveRouteDeps): Route[] {
  const watches = new FolderWatches();
  const at = (r: Request) => ({ root: param(r, "root") ?? "", path: param(r, "path") ?? "" });
  // Every route below goes through the asker's workspace's drive.
  const view = (r: Request) => driveView(whole, r, home);
  const answer = (f: (r: Request) => Promise<unknown>) => async (r: Request): Promise<Answer> => {
    try {
      return json(200, JSON.stringify(await f(r)));
    } catch (e) {
      return refused(e, r.lang);
    }
  };
  return [
    { method: "GET", pattern: /^\/drive$/, handle: answer(async (r) => view(r)) },
    {
      method: "PUT",
      pattern: /^\/drive\/roots$/,
      handle: answer(async (r) => {
        if (!anywhere(r)) throw new DriveError("permission", MANAGE);
        const asked = body(r).roots;
        if (!Array.isArray(asked) || asked.length > MOST_ROOTS || asked.some((p) => typeof p !== "string")) throw new DriveError("invalid_request", `roots: at most ${MOST_ROOTS} paths`);
        // The asker's workspace's own list: one the station joined keeps its own (`drive.workspaces`).
        const ws = r.viewer.home === false ? r.viewer.workspace : null;
        const drive = whole;
        const before = rootsOf(config.raw(), ws);
        const roots: string[] = [];
        for (const p of asked as string[]) {
          // One named before stays even while it is not there (a disk not mounted): it is only checked when new.
          const clean = before.find((b) => b === p) ?? (await drive.checkRoot(p));
          if (!roots.includes(clean)) roots.push(clean);
        }
        config.update((raw) => {
          const was = raw.drive !== null && typeof raw.drive === "object" ? raw.drive : {};
          raw.drive = ws === null ? { ...was, roots } : { ...was, workspaces: { ...(was.workspaces ?? {}), [ws]: roots } };
        });
        changed?.();
        return view(r);
      }),
    },
    {
      method: "GET",
      pattern: /^\/drive\/folders$/,
      handle: answer(async (r) => {
        if (!anywhere(r)) throw new DriveError("permission", MANAGE);
        return whole.folders(param(r, "path") ?? "", home, r.lang);
      }),
    },
    { method: "GET", pattern: /^\/drive\/list$/, handle: answer(async (r) => driveOf(whole, r).list(at(r).root, at(r).path, anywhere(r))) },
    { method: "GET", pattern: /^\/drive\/stat$/, handle: answer(async (r) => driveOf(whole, r).stat(at(r).root, at(r).path, anywhere(r))) },
    {
      method: "GET",
      pattern: /^\/drive\/read$/,
      handle: async (r) => {
        try {
          const read = await driveOf(whole, r).read(at(r).root, at(r).path, num(r, "offset", 0), num(r, "length", MAX_READ), anywhere(r));
          return {
            status: 200,
            headers: { "content-type": read.type, "cache-control": "no-store", "stillfail-total": String(read.total), "stillfail-mtime": String(read.mtime) },
            body: read.bytes,
          };
        } catch (e) {
          return refused(e, r.lang);
        }
      },
    },
    {
      method: "PUT",
      pattern: /^\/drive\/upload$/,
      handle: answer(async (r) =>
        driveOf(whole, r).upload(at(r).root, at(r).path, param(r, "id") ?? "", num(r, "offset", 0), num(r, "total", -1), r.body, param(r, "replace") === "1", anywhere(r)),
      ),
    },
    {
      method: "POST",
      pattern: /^\/drive\/mkdir$/,
      handle: answer(async (r) => {
        const b = body(r);
        return driveOf(whole, r).mkdir(text(b.root, "root"), text(b.path, "path"), anywhere(r));
      }),
    },
    {
      method: "POST",
      pattern: /^\/drive\/rename$/,
      handle: answer(async (r) => {
        const b = body(r);
        return driveOf(whole, r).rename(text(b.root, "root"), text(b.from, "from"), text(b.to, "to"), anywhere(r));
      }),
    },
    {
      method: "POST",
      pattern: /^\/drive\/remove$/,
      handle: answer(async (r) => {
        const b = body(r);
        await driveOf(whole, r).remove(text(b.root, "root"), text(b.path, "path"), anywhere(r), b.permanent === true);
        return {};
      }),
    },
    {
      // A folder zipped to download: where the zip is (a root of its own, read as any file of the drive is), for a member
      // who reaches every folder.
      method: "POST",
      pattern: /^\/drive\/zip$/,
      handle: answer(async (r) => {
        if (!anywhere(r)) throw new DriveError("permission", "a read-only member does not download folders");
        const b = body(r);
        return driveOf(whole, r).zip(text(b.root, "root"), text(b.path, "path"), MOST_STAGED, true);
      }),
    },
    {
      // Answered once something in the folder changes (`{changed: true}`), else after a while (`false`), for the client to
      // read it again (./drive/watch.ts). `id`: the client's own asking, kept between its askings.
      method: "GET",
      pattern: /^\/drive\/watch$/,
      handle: answer(async (r) => {
        const dir = await driveOf(whole, r).folderToWatch(at(r).root, at(r).path, anywhere(r));
        return { changed: await watches.changed(dir, param(r, "id") ?? "") };
      }),
    },
    ...(stage
      ? [{
          method: "POST",
          pattern: /^\/drive\/stage$/,
          handle: answer(async (r) => {
            // Sending is writing (a read-only member sends nothing; the admin API refuses it first).
            if (readOnly(r.viewer)) throw new DriveError("permission", "a read-only member sends nothing");
            const b = body(r);
            return driveOf(whole, r).stage(text(b.root, "root"), text(b.path, "path"), stage, MOST_STAGED, anywhere(r), b.zip === true);
          }),
        } as Route]
      : []),
  ];
}
