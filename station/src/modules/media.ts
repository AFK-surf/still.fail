// Thumbnails and posters of the drive's files, for the modules (modules/local.ts): made by the same code as a chat's
// (sessions/thumbs.ts: the native image codecs; sessions/posters.ts: QuickLook or ffmpeg), kept in <data>/thumbs/drive by
// the file's path and made again once the file is newer. A file reached through still.fail Helper (a folder macOS
// protects) is never opened by the station itself: the helper copies it into a folder of the station's own first, and
// the copy goes once what was made of it is kept.
import { mkdir, mkdtemp, readFile, rename, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { type Drive, MAX_READ, typeOf } from "../drive/drive.ts";
import { type Codecs, type Thumbnail, hashOf, idOf, kept, thumbnail, wanted as wantedThumb } from "../sessions/thumbs.ts";
import { poster, posterPath, wanted as wantedPoster } from "../sessions/posters.ts";

/// Where the drive's thumbnails and posters are kept.
export const driveThumbs = (thumbs: string) => join(thumbs, "drive");

/// What a thumbnail is answered with: its bytes and type, and the ThumbHash of what is shown (with its size), when the
/// codecs read it.
export type Shown = { bytes: Buffer; type: string; hash: { hash: string; width: number; height: number } | null };

type File = Awaited<ReturnType<Drive["file"]>>;

/// `use` given a copy of a file reached through still.fail Helper, in a folder of its own under `dir` (removed after).
async function withCopy<T>(file: File, dir: string, use: (copy: string, scratch: string) => Promise<T>): Promise<T> {
  await mkdir(dir, { recursive: true });
  const scratch = await mkdtemp(join(dir, ".copy-"));
  try {
    const copy = join(scratch, file.name);
    await file.copy!(copy);
    return await use(copy, scratch);
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
}

const shown = async (path: string, type: string, codecs: Codecs | null | undefined): Promise<Shown> => ({ bytes: await readFile(path), type, hash: await hashOf(path, codecs) });

/// An image's thumbnail (the image itself when it is small already, or no smaller one is made); null for a file that is
/// not an image a thumbnail is made of (by its name), or one not readable as an image. Refusals are the drive's.
export async function thumbOf(drive: Drive, at: { root: string; path: string; anywhere: boolean }, thumbs: string, codecs?: Codecs | null): Promise<Shown | null> {
  const file = await drive.file(at.root, at.path, at.anywhere);
  if (!wantedThumb(file.name)) return null;
  const dir = driveThumbs(thumbs);
  const itself = file.size <= MAX_READ ? typeOf(file.name) : null;
  if (file.copy === null) {
    const made = await thumbnail(file.found, dir, codecs, file.mtime);
    if (made !== null) return shown(made.path, made.type, codecs);
    return itself === null ? null : shown(file.found, itself, codecs);
  }
  const had = kept(dir, idOf(file.found), file.mtime);
  if (had !== null) return shown(had.path, had.type, codecs);
  return withCopy(file, dir, async (copy, scratch) => {
    const made: Thumbnail | null = await thumbnail(copy, scratch, codecs);
    if (made === null) return itself === null ? null : shown(copy, itself, codecs);
    // Kept by the file's own path, as one read directly is.
    const to = join(dir, `${idOf(file.found)}.${made.type === "image/png" ? "png" : "jpg"}`);
    await rename(made.path, to);
    return shown(to, made.type, codecs);
  });
}

/// A video's poster, a JPEG's path; null for a file that is not a video (by its name), or one none can be made of.
export async function posterOf(drive: Drive, at: { root: string; path: string; anywhere: boolean }, thumbs: string): Promise<string | null> {
  const file = await drive.file(at.root, at.path, at.anywhere);
  if (!wantedPoster(file.name)) return null;
  const dir = driveThumbs(thumbs);
  if (file.copy === null) return poster(file.found, dir, file.mtime);
  const to = posterPath(file.found, dir);
  if (((await stat(to).catch(() => null))?.mtimeMs ?? -1) >= file.mtime) return to;
  return withCopy(file, dir, async (copy, scratch) => {
    const made = await poster(copy, scratch);
    if (made === null) return null;
    await rename(made, to);
    return to;
  });
}
