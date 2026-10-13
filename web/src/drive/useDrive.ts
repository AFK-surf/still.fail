// What both the phone's and the desktop's drive pages know of a station's drive: its roots (the overview's: none from a
// station from before the drive, which then is not offered), who may name them (the workspace's owners and admins) and
// who may change what is in them (anyone but a read-only member). The changes are the core's operations by name.
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
  /** May change what is in them (not a read-only member). */
  write: boolean;
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
    write: picked.viewer !== "viewer",
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

export const drive = {
  setRoots: (station: string, roots: string[]) => call("drive.setRoots", { station, roots }),
  folders: (station: string, path: string | null) => call("drive.folders", { station, ...(path ? { path } : {}) }) as Promise<{ path: string; parent: string | null; home: string; folders: string[] }>,
  mkdir: (at: At, name: string) => call("drive.mkdir", { station: at.station, root: at.root, path: joinPath(at.path, name) }),
  rename: (at: At, entry: DriveEntry, to: string) => call("drive.rename", { station: at.station, root: at.root, from: joinPath(at.path, entry.name), to: joinPath(at.path, to) }),
  remove: (at: At, entry: DriveEntry) => call("drive.remove", { station: at.station, root: at.root, path: joinPath(at.path, entry.name) }),
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
