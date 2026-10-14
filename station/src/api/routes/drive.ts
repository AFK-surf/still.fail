// The station's drive (src/drive/drive.ts) as members ask it. GET /drive says its roots, and what the viewer may do;
// PUT /drive/roots names them (the workspace's owners and admins, kept in config.json `drive.roots`), GET
// /drive/folders lets them pick one. The rest is a path under a root (`root`, `path` relative to it, `/` between
// components): GET /drive/list, /drive/stat and /drive/read (a part of a file: `offset`, `length`); PUT /drive/upload
// (a part of a file written: `id`, `offset`, `total`, `replace`; its bytes the body), POST /drive/mkdir, /drive/rename
// and /drive/remove (a JSON body). Read-only members only read (the admin API refuses their writes). A refusal is
// `{error, code}` with the code's status (CODES).
import { homedir } from "node:os";
import { type Answer, type Request, json, param } from "../request.ts";
import type { Route } from "../admin.ts";
import type { ConfigFile } from "../../ops/config.ts";
import { type Lang, tr } from "../../ops/i18n.ts";
import { readOnly } from "../../mesh/credential.ts";
import { CODES, Drive, DriveError, MAX_READ, MOST_ROOTS, rootsOf } from "../../drive/drive.ts";

export type DriveRouteDeps = { drive: Drive; config: ConfigFile; home?: string; changed?: () => void };

const manages = (r: { viewer: { role: string } }) => r.viewer.role === "owner" || r.viewer.role === "admin";

/// A refusal in the asker's words (`station.drive.<code>`, after the path it is about, if any).
const refused = (e: unknown, lang: Lang): Answer => {
  const d = e instanceof DriveError ? e : new DriveError("io", (e as Error).message);
  const words = tr(lang, d.code === "permission" && d.message === MANAGE ? "station.drive.manage" : `station.drive.${d.code}`);
  return json(CODES[d.code], JSON.stringify({ error: d.about ? `${d.about}: ${words}` : words, code: d.code, ...(d.have !== undefined ? { have: d.have } : {}) }));
};

const MANAGE = "only the workspace's owners and admins name the drive's folders";

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

/// What GET /drive and the overview say: the roots, and what the viewer may do with them.
export const driveView = (drive: Drive, r: { viewer: Request["viewer"] }) => ({ roots: drive.roots(), manage: manages(r), write: !readOnly(r.viewer) });

export function routes({ drive, config, home = homedir(), changed }: DriveRouteDeps): Route[] {
  const at = (r: Request) => ({ root: param(r, "root") ?? "", path: param(r, "path") ?? "" });
  const answer = (f: (r: Request) => Promise<unknown>) => async (r: Request): Promise<Answer> => {
    try {
      return json(200, JSON.stringify(await f(r)));
    } catch (e) {
      return refused(e, r.lang);
    }
  };
  return [
    { method: "GET", pattern: /^\/drive$/, handle: answer(async (r) => driveView(drive, r)) },
    {
      method: "PUT",
      pattern: /^\/drive\/roots$/,
      handle: answer(async (r) => {
        if (!manages(r)) throw new DriveError("permission", MANAGE);
        const asked = body(r).roots;
        if (!Array.isArray(asked) || asked.length > MOST_ROOTS || asked.some((p) => typeof p !== "string")) throw new DriveError("invalid_request", `roots: at most ${MOST_ROOTS} paths`);
        const before = rootsOf(config.raw());
        const roots: string[] = [];
        for (const p of asked as string[]) {
          // One named before stays even while it is not there (a disk not mounted): it is only checked when new.
          const clean = before.find((b) => b === p) ?? (await drive.checkRoot(p));
          if (!roots.includes(clean)) roots.push(clean);
        }
        config.update((raw) => {
          raw.drive = { ...(raw.drive !== null && typeof raw.drive === "object" ? raw.drive : {}), roots };
        });
        changed?.();
        return driveView(drive, r);
      }),
    },
    {
      method: "GET",
      pattern: /^\/drive\/folders$/,
      handle: answer(async (r) => {
        if (!manages(r)) throw new DriveError("permission", MANAGE);
        return drive.folders(param(r, "path") ?? "", home, r.lang);
      }),
    },
    { method: "GET", pattern: /^\/drive\/list$/, handle: answer(async (r) => drive.list(at(r).root, at(r).path)) },
    { method: "GET", pattern: /^\/drive\/stat$/, handle: answer(async (r) => drive.stat(at(r).root, at(r).path)) },
    {
      method: "GET",
      pattern: /^\/drive\/read$/,
      handle: async (r) => {
        try {
          const read = await drive.read(at(r).root, at(r).path, num(r, "offset", 0), num(r, "length", MAX_READ));
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
        drive.upload(at(r).root, at(r).path, param(r, "id") ?? "", num(r, "offset", 0), num(r, "total", -1), r.body, param(r, "replace") === "1"),
      ),
    },
    {
      method: "POST",
      pattern: /^\/drive\/mkdir$/,
      handle: answer(async (r) => {
        const b = body(r);
        return drive.mkdir(text(b.root, "root"), text(b.path, "path"));
      }),
    },
    {
      method: "POST",
      pattern: /^\/drive\/rename$/,
      handle: answer(async (r) => {
        const b = body(r);
        return drive.rename(text(b.root, "root"), text(b.from, "from"), text(b.to, "to"));
      }),
    },
    {
      method: "POST",
      pattern: /^\/drive\/remove$/,
      handle: answer(async (r) => {
        const b = body(r);
        await drive.remove(text(b.root, "root"), text(b.path, "path"));
        return {};
      }),
    },
  ];
}
