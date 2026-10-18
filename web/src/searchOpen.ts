// Where something a search found opens that the wide screen and the phone open the same way (docs/search.md).
import type { DriveKind, SearchItem } from "./core/shapes.ts";
import { openerOf } from "./drive/model.ts";
import { drivePath } from "./drive/useDrive.ts";

/**
 * Where a file found opens in the drive (drive/useDrive.ts `drivePath`): a folder entered, a text read, a video or song
 * played, anything else shown in its folder. Under the folder a read-only member's workspace pinned (`root`) when found
 * there, else from its own folder (a member who may write reaches any).
 */
export function fileOpen(base: string, item: SearchItem): string {
  const path = item.path ?? "";
  const cut = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"));
  const [folder, name] = cut > 0 ? [path.slice(0, cut), path.slice(cut + 1)] : [path, ""];
  const root = item.root ?? (item.dir ? path : folder);
  const rel = item.root ? (item.rel ?? "") : item.dir ? "" : name;
  const parent = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "";
  const how = item.dir ? "folder" : openerOf((item.fileKind ?? "other") as DriveKind);
  if (how === "folder") return drivePath(base, root, rel);
  if (how === "read" || how === "play") return drivePath(base, root, rel, how);
  return drivePath(base, root, parent);
}
