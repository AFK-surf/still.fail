// A station's file as @stillfail/ui's viewers open it (viewer/file.ts): read a part at a time, streamed where the page
// can (stream.ts), a file beside it read (a subtitle), where it was left kept on this device (`drive.place`), saved.
import { useMemo } from "react";
import type { ViewerFile } from "@stillfail/ui/viewer/file.ts";
import type { DriveEntry } from "../core/shapes.ts";
import { download, joinPath, parentOf, placeAt, readKept, readWhole, usePlace, type At } from "./model.ts";
import { streaming, streamUrl } from "./stream.ts";

export function driveFile(at: At, entry: Pick<DriveEntry, "name" | "size" | "mtime" | "type" | "kind">): ViewerFile {
  return {
    name: entry.name, size: entry.size, mtime: entry.mtime, type: entry.type, kind: entry.kind, title: at.path,
    key: `${at.station}\n${at.root}\n${at.path}\n${entry.size}\n${entry.mtime}`,
    read: (opts) => readWhole(at, entry.size, opts),
    stream: async (type, ahead) => ((await streaming()) ? streamUrl(at, entry.size, type, ahead) : null),
    beside: (side, type) => readKept({ ...at, path: joinPath(parentOf(at.path), side.name) }, side, type),
    usePlace: () => usePlace(at),
    keepPlace: (where, of) => placeAt(at, where, of),
    save: () => { void download(at, entry); },
  };
}

/** The same while it is the same file, unchanged: what the viewers read of it is kept for as long. */
export function useDriveFile(at: At, entry: Pick<DriveEntry, "name" | "size" | "mtime" | "type" | "kind"> | null): ViewerFile | null {
  return useMemo(() => (entry ? driveFile(at, entry) : null), // eslint-disable-line react-hooks/exhaustive-deps
    [at.station, at.root, at.path, entry?.name, entry?.size, entry?.mtime, entry?.type, entry?.kind]);
}
