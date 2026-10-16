// A station's file or folder dragged out of a list of its drive (the files' page, the chat's 文件 tab): what it is, in
// a type of its own, for a composer to take it, named by its path on its station (switched to a file, it is sent:
// copied by the chat's station when it is the one that has it, else read from the other and sent up); and its path as
// plain text, for anywhere else (a text field, a terminal).
import type { DriveEntry } from "../core/shapes.ts";
import { absoluteOf } from "./useDrive.ts";
import { joinPath, type At } from "./model.ts";

export const DRIVE_DRAG = "application/x-stillfail-drive";

/** One dragged: where it is (its station and that station's name, its root, its path under it), its absolute path,
 * its name and size. */
export interface Dragged { station: string; stationName: string; root: string; path: string; abs: string; name: string; size: number; dir: boolean }

export function draggedOf(at: At, entry: DriveEntry, stationName: string): Dragged {
  const path = joinPath(at.path, entry.name);
  return { station: at.station, stationName, root: at.root, path, abs: absoluteOf(at.root, path), name: entry.name, size: entry.size, dir: entry.dir };
}

/** What a composer takes of one dragged (draft.ts `addDropped`): named by its path, sent from its drive if switched. */
export function droppedFrom(i: Dragged) {
  return {
    name: i.name, size: i.size, ref: { station: i.station, stationName: i.stationName, path: i.abs, dir: i.dir },
    ...(i.dir ? {} : { drive: { station: i.station, root: i.root, path: i.path } }),
  };
}

/** Puts what is dragged on the drag. */
export function startDrag(e: { dataTransfer: DataTransfer }, items: Dragged[]): void {
  e.dataTransfer.effectAllowed = "copy";
  e.dataTransfer.setData(DRIVE_DRAG, JSON.stringify(items));
  e.dataTransfer.setData("text/plain", items.map((i) => i.abs).join("\n"));
}

/** Whether a drag (as it goes over) carries a station's files. */
export const carriesDrive = (dt: DataTransfer) => dt.types.includes(DRIVE_DRAG);

/** What a drop carries of a station's files (none: not such a drop). */
export function droppedOf(dt: DataTransfer): Dragged[] {
  try {
    const v = JSON.parse(dt.getData(DRIVE_DRAG) || "[]") as unknown;
    return Array.isArray(v) ? v.filter((x): x is Dragged => typeof x === "object" && x !== null && typeof (x as Dragged).abs === "string") : [];
  } catch {
    return [];
  }
}
