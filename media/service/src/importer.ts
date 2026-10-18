// Importing books from the drive (POST /books/import): a file (EPUB, TXT) or every such file of a folder, read through
// the station for the member who asked. A file imported before in the workspace keeps its id: read again only when its
// size or time changed.
import { randomBytes } from "node:crypto";
import { basename, extname, posix } from "node:path";
import type { Parsed } from "./blocks.ts";
import { isEpub, parseEpub } from "./epub.ts";
import { MediaError } from "./errors.ts";
import { type StationLink, list, readAll, stat } from "./station.ts";
import type { Store } from "./store.ts";
import { decodeText, looksLikeText, parseTxt } from "./txt.ts";

/// The largest book file imported.
export const MOST = 512 * 1024 * 1024;

const BOOKS = new Set([".epub", ".txt"]);
const KINDLE = new Set([".mobi", ".azw", ".azw3", ".prc", ".kfx"]);

const kindle = () => new MediaError("unsupported", "暂不支持 MOBI / AZW3 格式（第一期只导入 EPUB 和 TXT），请先转换成 EPUB");

/// The book in `bytes` by its content, then its name.
export function parseBook(bytes: Buffer, name: string): Parsed {
  const ext = extname(name).toLowerCase();
  if (isEpub(bytes)) return parseEpub(bytes, name);
  const magic = bytes.toString("latin1", 60, 68);
  if (KINDLE.has(ext) || magic === "BOOKMOBI" || magic === "TEXtREAd") throw kindle();
  if (ext === ".epub") throw new MediaError("bad_request", "这个文件不是有效的 EPUB");
  if (ext === ".txt" || looksLikeText(bytes)) return parseTxt(decodeText(bytes), name);
  throw new MediaError("unsupported", "不支持这种文件格式（第一期只导入 EPUB 和 TXT）");
}

export const newId = () => randomBytes(9).toString("base64url");

/// What an import needs: the store, the station, and what to do once the workspace's shelf changed.
export type ImportDeps = { store: Store; link: StationLink; changed: (workspace: string) => void };

/// One import per file at a time: a second asks the same file again, it waits for the first.
const running = new Map<string, Promise<string>>();

/// Imports the file at `root`/`path` (its drive entry `size`, `mtime`) into `workspace`; answers the book's id.
async function importFile(deps: ImportDeps, viewer: string, workspace: string, root: string, path: string, size: number, mtime: number): Promise<string> {
  const key = JSON.stringify([workspace, root, path]);
  while (running.has(key)) await running.get(key)!.catch(() => {});
  const work = (async () => {
    const had = deps.store.bookAt(workspace, root, path);
    if (had && had.size === size && had.mtime === mtime) return had.id;
    const name = basename(path) || path;
    const read = await readAll(deps.link, viewer, root, path, MOST, (head) => {
      const magic = head.toString("latin1", 60, 68);
      if (KINDLE.has(extname(name).toLowerCase()) || magic === "BOOKMOBI" || magic === "TEXtREAd") throw kindle();
    });
    const parsed = parseBook(read.bytes, name);
    const id = had?.id ?? newId();
    deps.store.saveBook({ id, workspace, root, path, size, mtime, added: Date.now(), parsed }, had !== undefined);
    deps.changed(workspace);
    return id;
  })();
  running.set(key, work);
  try {
    return await work;
  } finally {
    running.delete(key);
  }
}

export type ImportResult = { ids: string[]; failed?: { path: string; error: string }[] };

/// Imports `path` under `root`: a file, or each EPUB and TXT right in a folder (not in its subfolders; one that fails
/// is reported in `failed`, the others go on).
export async function importPath(deps: ImportDeps, viewer: string, workspace: string, root: string, path: string): Promise<ImportResult> {
  const entry = await stat(deps.link, viewer, root, path);
  if (!entry.dir) return { ids: [await importFile(deps, viewer, workspace, root, path, entry.size, entry.mtime)] };
  const listing = await list(deps.link, viewer, root, path);
  const ids: string[] = [];
  const failed: { path: string; error: string }[] = [];
  const files = listing.entries.filter((e) => !e.dir && BOOKS.has(extname(e.name).toLowerCase())).sort((a, b) => a.name.localeCompare(b.name, "zh"));
  for (const e of files) {
    const at = path ? posix.join(path, e.name) : e.name;
    try {
      ids.push(await importFile(deps, viewer, workspace, root, at, e.size, e.mtime));
    } catch (err) {
      if (!(err instanceof MediaError)) throw err;
      failed.push({ path: at, error: err.message });
    }
  }
  if (ids.length === 0 && failed.length === 0) throw new MediaError("not_found", "这个文件夹里没有 EPUB 或 TXT 文件");
  return failed.length > 0 ? { ids, failed } : { ids };
}
