// Archives of plain files, as releases that are not a station's carry them: a module's package (docs/station-modules.md:
// written by scripts/module-bundle.ts, read by the station's modules/packages.ts). A gzipped tar of plain files, so
// neither side depends on a tar program and what is in it is only ever files under the directory it is opened into.
import { gunzipSync, gzipSync } from "node:zlib";

const BLOCK = 512;

/** A file of the archive: its path ("assets/index-….js", "/" between directories) and bytes. */
export interface ArchivedFile { path: string; bytes: Uint8Array }

/** A path the archive may hold: relative, "/" between parts, no part empty, "." or "..", nothing but what names files. */
export function safePath(path: string): boolean {
  return path.length > 0 && path.length <= 255 && !path.startsWith("/") && path.split("/").every((part) => part !== "" && part !== "." && part !== ".." && /^[\w@+=,.~-]+$/.test(part));
}

function field(header: Uint8Array, at: number, length: number, value: string): void {
  const bytes = Buffer.from(value, "utf8");
  if (bytes.length > length) throw new Error(`a tar field of ${length} bytes cannot hold ${JSON.stringify(value)}`);
  header.set(bytes, at);
}

const octal = (n: number, length: number) => `${n.toString(8).padStart(length - 1, "0")}\0`;

/** The files, sorted by path, as a gzipped ustar archive: the same files give the same bytes. */
export function writeArchive(files: ArchivedFile[]): Uint8Array {
  const blocks: Uint8Array[] = [];
  for (const file of [...files].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))) {
    if (!safePath(file.path)) throw new Error(`not a path the archive holds: ${file.path}`);
    const header = new Uint8Array(BLOCK);
    // ustar splits a long path into a prefix (155) and a name (100) at a "/".
    let name = file.path;
    let prefix = "";
    if (Buffer.byteLength(name) > 100) {
      const cut = name.lastIndexOf("/", 155);
      if (cut <= 0 || Buffer.byteLength(name.slice(cut + 1)) > 100) throw new Error(`too long a path for the archive: ${file.path}`);
      prefix = name.slice(0, cut);
      name = name.slice(cut + 1);
    }
    field(header, 0, 100, name);
    field(header, 100, 8, octal(0o644, 8));
    field(header, 108, 8, octal(0, 8));
    field(header, 116, 8, octal(0, 8));
    field(header, 124, 12, octal(file.bytes.length, 12));
    field(header, 136, 12, octal(0, 12));
    header.fill(0x20, 148, 156);
    header[156] = 0x30; // "0": a regular file
    field(header, 257, 6, "ustar\0");
    field(header, 263, 2, "00");
    field(header, 345, 155, prefix);
    field(header, 148, 8, octal(header.reduce((sum, b) => sum + b, 0), 7) + " ");
    blocks.push(header, file.bytes);
    const pad = (BLOCK - (file.bytes.length % BLOCK)) % BLOCK;
    if (pad) blocks.push(new Uint8Array(pad));
  }
  blocks.push(new Uint8Array(BLOCK * 2));
  return gzipSync(Buffer.concat(blocks), { level: 9 });
}

const text = (bytes: Uint8Array, at: number, length: number) => {
  const slice = bytes.subarray(at, at + length);
  const end = slice.indexOf(0);
  return Buffer.from(end < 0 ? slice : slice.subarray(0, end)).toString("utf8");
};

/**
 * The files of an archive writeArchive made (or any gzipped ustar of plain files). Anything else in it, a path that
 * would leave the directory (safePath), a header whose checksum is wrong or bytes cut short, and it throws.
 */
export function readArchive(gzipped: Uint8Array): ArchivedFile[] {
  const tar = gunzipSync(gzipped);
  const files: ArchivedFile[] = [];
  const seen = new Set<string>();
  for (let at = 0; ; ) {
    if (at + BLOCK > tar.length) throw new Error("the archive ends without its end");
    const header = tar.subarray(at, at + BLOCK);
    if (header.every((b) => b === 0)) return files;
    const sum = header.reduce((total, b, i) => total + (i >= 148 && i < 156 ? 0x20 : b), 0);
    if (Number.parseInt(text(header, 148, 8).trim(), 8) !== sum) throw new Error("an archive header's checksum is wrong");
    const type = String.fromCharCode(header[156] ?? 0);
    if (type !== "0" && type !== "\0") throw new Error(`the archive holds something not a plain file (type ${JSON.stringify(type)})`);
    const prefix = text(header, 345, 155);
    const path = prefix ? `${prefix}/${text(header, 0, 100)}` : text(header, 0, 100);
    if (!safePath(path) || seen.has(path)) throw new Error(`the archive holds a path it may not: ${JSON.stringify(path)}`);
    seen.add(path);
    const size = Number.parseInt(text(header, 124, 12).trim(), 8);
    if (!Number.isSafeInteger(size) || size < 0) throw new Error(`a size the archive cannot have: ${path}`);
    const start = at + BLOCK;
    if (start + size > tar.length) throw new Error(`the archive is cut short in ${path}`);
    files.push({ path, bytes: tar.subarray(start, start + size) });
    at = start + Math.ceil(size / BLOCK) * BLOCK;
  }
}
