// A station's file or folder dragged out of a list of its drive (the files' page, the chat's 文件 tab): what it is, in
// a type of its own, for a composer to take it, named by its path on its station (switched to a file, it is sent:
// copied by the chat's station when it is the one that has it, else read from the other and sent up); and its path as
// plain text, for anywhere else (a text field, a terminal).
import { useSyncExternalStore } from "react";
import type { DriveEntry } from "../core/shapes.ts";
import type { Dropped } from "../draft.ts";
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

/** What this page is dragging now (its rows), for what it goes over to show it: a drag's data is unread until a drop. */
let dragging: Dragged[] | null = null;
export const draggedNow = () => dragging;
export const endDrag = () => { dragging = null; };

/** Puts what is dragged on the drag. */
export function startDrag(e: { dataTransfer: DataTransfer }, items: Dragged[]): void {
  dragging = items;
  // Copied or moved where it is dropped (a folder: drive/browse.ts effectOf), copied into a message.
  e.dataTransfer.effectAllowed = "copyMove";
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

/** What is being dragged over a chat's page now (ChatPage.tsx), for its composer to show where it goes: a station's files
 * or Finder's on a machine that is a station (`path`), other files (`file`), or nothing. */
let over: "path" | "file" | null = null;
const listeners = new Set<() => void>();
export function setDropOver(next: "path" | "file" | null): void {
  if (over === next) return;
  over = next;
  for (const l of listeners) l();
}
export function useDropOver(): "path" | "file" | null {
  return useSyncExternalStore((l) => { listeners.add(l); return () => { listeners.delete(l); }; }, () => over, () => null);
}

/** What a file is by its type (a drag from Finder says its files' types, not their names, until it is dropped): a name
 * with the extension that type usually has, for its mark. */
export function nameByType(type: string): string {
  const known: Record<string, string> = {
    "application/pdf": "pdf", "application/zip": "zip", "application/json": "json", "text/plain": "txt", "text/markdown": "md", "text/csv": "csv",
    "text/html": "html", "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp", "image/svg+xml": "svg", "image/heic": "heic",
    "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm", "audio/mpeg": "mp3", "audio/wav": "wav", "audio/mp4": "m4a",
  };
  const ext = known[type] ?? (/^(image|video|audio)\/([a-z0-9]{2,4})$/.exec(type)?.[2] ?? "");
  return ext ? `file.${ext}` : "file";
}
