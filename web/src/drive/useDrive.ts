// What both the phone's and the desktop's drive pages know of a station's drive: its pinned folders (the overview's: none
// from a station from before the drive, which then is not offered), whether the viewer browses every folder of the
// machine from its home (`anywhere`: a member who may write), and who may change what is in them (anyone but a
// read-only member). The changes are the core's operations by name.
import { useMemo } from "react";
import { core, useTopicSelect } from "../core/react.ts";
import { useWorkspace } from "../cloud/api.ts";
import type { DriveEntry, DriveRoot, DriveRoots, StationView } from "../core/shapes.ts";
import { joinPath, type At } from "./model.ts";
import { t } from "../i18n.ts";

export interface DriveState {
  /** Still reading the station's overview. */
  loading: boolean;
  /** The station has a drive (one from before it has none: nothing is offered). */
  offered: boolean;
  roots: DriveRoot[];
  /** May name the folders it lends (the workspace's owners and admins). */
  manage: boolean;
  /** Browses every folder of the machine, and pins them (a member who may write, of a station that lets them). */
  anywhere: boolean;
  /** Where browsing starts, with `anywhere`: the home of the station's machine. */
  home: string | null;
  /** May change what is in them (not a read-only member). */
  write: boolean;
  /** What is deleted goes to the machine's trash (else it goes for good, asked first). */
  trash: boolean;
  /** A folder can be zipped to download. */
  zip: boolean;
  /** Files can be copied and moved into it from its own folders and other stations' (docs/drive.md "Copying between
   * stations"); a station from before does not. */
  transfers: boolean;
  error: string | null;
}

export function useDrive(station: string): DriveState {
  // From the workspace's stations as the pages already have them (each with its overview), only what this needs: the
  // same while its roots and the viewer's role are.
  const scope = station.split("/")[0] ?? "";
  const picked = useTopicSelect<StationView[], { listed: boolean; drive: DriveRoots | undefined; viewer: string | undefined; error: string | null }>({ topic: "stations", scope }, (s) => {
    const v = s.value?.find((x) => x.station === station);
    return { listed: !!v?.overview, drive: v?.overview?.drive, viewer: v?.overview?.viewer?.role, error: s.error?.message ?? null };
  }, (a, b) => a.listed === b.listed && a.viewer === b.viewer && a.error === b.error && JSON.stringify(a.drive) === JSON.stringify(b.drive));
  const role = useWorkspace(scope).value?.role;
  return useMemo(() => ({
    loading: !picked.listed && !picked.error,
    offered: !!picked.drive,
    roots: picked.drive?.roots ?? [],
    manage: role === "owner" || role === "admin",
    anywhere: picked.drive?.anywhere === true,
    home: picked.drive?.home ?? null,
    write: picked.viewer !== "viewer",
    trash: picked.drive?.trash === true,
    zip: picked.drive?.zip === true,
    transfers: picked.drive?.transfers === true,
    error: picked.error,
  }), [picked, role]);
}

/** A root's state as a line under its name (null while it can be browsed); in red where it shows. */
export function rootTrouble(root: DriveRoot): { text: string; hint: string } | null {
  switch (root.state) {
    case "ok": return null;
    case "missing": return { text: t("web-pages.drive.root.missing"), hint: t("web-pages.drive.root.missingHint") };
    case "not_a_directory": return { text: t("web-pages.drive.root.notFolder"), hint: t("web-pages.drive.root.notFolderHint") };
    default: return { text: t("web-pages.drive.root.unreadable"), hint: t("web-pages.drive.root.unreadableHint") };
  }
}

const call = (name: string, params: Record<string, unknown>) => core().call(name, params);

/** A folder to pick a root from: where it is, whether the station may list it, whether it is a disk. */
export type PickFolder = { name: string; path: string; unreadable: boolean; disk?: boolean };
/** The station's folders at one place (`drive.folders`): its folders, the way there, the places to start from. */
export type Folders = { path: string; parent: string | null; home: string; entries: PickFolder[]; unreadable: boolean; crumbs: { name: string; path: string }[]; places: PickFolder[] };

/** What the station answered, whole: one from before places and crumbs gave the names alone. */
function foldersOf(raw: unknown): Folders {
  const v = raw as { path: string; parent: string | null; home: string; folders?: string[]; entries?: PickFolder[]; unreadable?: boolean; crumbs?: Folders["crumbs"]; places?: PickFolder[] };
  return {
    path: v.path, parent: v.parent, home: v.home, unreadable: v.unreadable === true,
    entries: v.entries ?? (v.folders ?? []).map((name) => ({ name, path: childOf(v.path, name), unreadable: false })),
    crumbs: v.crumbs ?? [{ name: v.path, path: v.path }],
    places: v.places ?? [],
  };
}

/** The folders whose name has `filter` in it, case aside. */
export const filtered = (entries: readonly PickFolder[], filter: string) => {
  const f = filter.trim().toLowerCase();
  return f === "" ? entries : entries.filter((e) => e.name.toLowerCase().includes(f));
};

export const drive = {
  setRoots: (station: string, roots: string[]) => call("drive.setRoots", { station, roots }),
  /** `folder` (an absolute path on the station) pinned, or not, among `roots`. */
  pin: (station: string, roots: readonly DriveRoot[], folder: string, pinned: boolean) =>
    call("drive.setRoots", { station, roots: pinned ? [...roots.map((r) => r.path).filter((p) => p !== folder), folder] : roots.map((r) => r.path).filter((p) => p !== folder) }),
  folders: (station: string, path: string | null) => call("drive.folders", { station, ...(path ? { path } : {}) }).then(foldersOf),
  mkdir: (at: At, name: string) => call("drive.mkdir", { station: at.station, root: at.root, path: joinPath(at.path, name) }),
  rename: (at: At, entry: DriveEntry, to: string) => call("drive.rename", { station: at.station, root: at.root, from: joinPath(at.path, entry.name), to: joinPath(at.path, to) }),
  /** To the machine's trash, where there is one (`permanent`: for good). */
  remove: (at: At, entry: DriveEntry, permanent = false) => call("drive.remove", { station: at.station, root: at.root, path: joinPath(at.path, entry.name), ...(permanent ? { permanent: true } : {}) }),
};

/** A name a folder or file may have: not empty, no slash, not . or .. */
export function nameProblem(name: string): string | null {
  const n = name.trim();
  if (!n) return t("web-pages.drive.name.empty");
  if (n.includes("/") || n.includes("\\") || n === "." || n === "..") return t("web-pages.drive.name.bad");
  return null;
}

/** Where a page of the drive is: `files?root=…&path=…` under the station (`read`, `play`: a file opened). */
export function drivePath(base: string, root: string | null, path = "", what: "" | "read" | "play" = ""): string {
  const q = new URLSearchParams();
  if (root !== null) q.set("root", root);
  if (path) q.set("path", path);
  const s = q.toString();
  return `${base}/files${what ? `/${what}` : ""}${s ? `?${s}` : ""}`;
}

/** A child of a picked folder on the station (its own separator: Windows' backslash, else a slash). */
export function childOf(folder: string, name: string): string {
  const sep = folder.includes("\\") && !folder.includes("/") ? "\\" : "/";
  return folder.endsWith(sep) ? `${folder}${name}` : `${folder}${sep}${name}`;
}

/** Where a path under a root is on the station: its absolute path (the root's separator between). */
export function absoluteOf(root: string, path: string): string {
  return path.split("/").filter(Boolean).reduce((at, name) => childOf(at, name), root);
}

/** A folder's own name from its absolute path (the path itself for a top: `/`, `C:\`). */
export const folderName = (path: string) => path.split(/[/\\]/).filter(Boolean).at(-1) ?? path;

/**
 * The way to an absolute folder, each step a folder to go to: from the home (named) when it is under it, else from the
 * top of the disk.
 */
export function trailOf(abs: string, home: string | null, homeName: string): { name: string; path: string }[] {
  const sep = abs.includes("\\") && !abs.includes("/") ? "\\" : "/";
  const trim = (p: string) => (p.length > 1 && p.endsWith(sep) ? p.slice(0, -1) : p);
  const at = trim(abs);
  const h = home === null ? null : trim(home);
  if (h !== null && (at === h || at.startsWith(h + sep))) {
    const out = [{ name: homeName, path: h }];
    for (const part of at.slice(h.length).split(sep).filter(Boolean)) out.push({ name: part, path: childOf(out.at(-1)!.path, part) });
    return out;
  }
  const parts = at.split(sep).filter(Boolean);
  // A Windows path starts with its drive (`C:`), a POSIX one with `/`.
  const top = sep === "/" ? "/" : `${parts.shift() ?? ""}\\`;
  const out = [{ name: top, path: top }];
  for (const part of parts) out.push({ name: part, path: childOf(out.at(-1)!.path, part) });
  return out;
}
