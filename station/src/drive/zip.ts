// A folder put into a zip, for a member to send it in a chat as one file (drive.ts `stage`): every file under it,
// deflated, named by its path in the folder (under the folder's own name), with its time. Links are not followed, and
// what `skip` names (the station's own data, uploads not finished) is left out. No zip64: at most `most` bytes read in
// all, which the caller keeps well under 4 GB.
import { crc32, deflateRawSync } from "node:zlib";
import { lstat, open, readdir, readFile } from "node:fs/promises";
import { basename, join } from "node:path";

export class TooBig extends Error {}

type Entry = { name: Buffer; crc: number; size: number; packed: number; method: number; at: number; time: number; date: number };

/// A time as DOS has it (2-second steps, local time, from 1980).
function dos(ms: number): { time: number; date: number } {
  const d = new Date(Math.max(ms, Date.UTC(1980, 0, 1)));
  return {
    time: (d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2),
    date: ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(),
  };
}

/// Writes `dir` as a zip at `to` (made new; it must not be there). Answers the zip's size.
export async function zipFolder(dir: string, to: string, most: number, skip: (path: string, name: string) => Promise<boolean>): Promise<number> {
  const out = await open(to, "wx");
  let at = 0;
  let read = 0;
  const entries: Entry[] = [];
  const write = async (b: Buffer) => {
    let done = 0;
    while (done < b.length) done += (await out.write(b, done, b.length - done, at + done)).bytesWritten;
    at += b.length;
  };
  const add = async (name: string, data: Buffer | null, mtime: number) => {
    const isDir = data === null;
    const body = data ?? Buffer.alloc(0);
    const packed = isDir || body.length === 0 ? body : deflateRawSync(body);
    const method = isDir || packed.length >= body.length ? 0 : 8;
    const stored = method === 8 ? packed : body;
    const e: Entry = { name: Buffer.from(name, "utf8"), crc: isDir ? 0 : crc32(body) >>> 0, size: body.length, packed: stored.length, method, at, ...dos(mtime) };
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0);
    h.writeUInt16LE(20, 4);
    h.writeUInt16LE(0x0800, 6); // names in UTF-8
    h.writeUInt16LE(method, 8);
    h.writeUInt16LE(e.time, 10);
    h.writeUInt16LE(e.date, 12);
    h.writeUInt32LE(e.crc, 14);
    h.writeUInt32LE(e.packed, 18);
    h.writeUInt32LE(e.size, 22);
    h.writeUInt16LE(e.name.length, 26);
    h.writeUInt16LE(0, 28);
    await write(h);
    await write(e.name);
    await write(stored);
    entries.push(e);
  };
  const walk = async (path: string, name: string) => {
    const names = (await readdir(path)).sort();
    for (const child of names) {
      const full = join(path, child);
      if (await skip(full, child)) continue;
      const s = await lstat(full).catch(() => null);
      if (s === null || s.isSymbolicLink()) continue;
      const inZip = `${name}/${child}`;
      if (s.isDirectory()) {
        await add(`${inZip}/`, null, s.mtimeMs);
        await walk(full, inZip);
      } else if (s.isFile()) {
        read += s.size;
        if (read > most) throw new TooBig();
        await add(inZip, await readFile(full), s.mtimeMs);
      }
    }
  };
  try {
    const top = basename(dir) || "folder";
    const s = await lstat(dir);
    await add(`${top}/`, null, s.mtimeMs);
    await walk(dir, top);
    const start = at;
    for (const e of entries) {
      const c = Buffer.alloc(46);
      c.writeUInt32LE(0x02014b50, 0);
      c.writeUInt16LE(0x031e, 4); // made by Unix, 3.0
      c.writeUInt16LE(20, 6);
      c.writeUInt16LE(0x0800, 8);
      c.writeUInt16LE(e.method, 10);
      c.writeUInt16LE(e.time, 12);
      c.writeUInt16LE(e.date, 14);
      c.writeUInt32LE(e.crc, 16);
      c.writeUInt32LE(e.packed, 20);
      c.writeUInt32LE(e.size, 24);
      c.writeUInt16LE(e.name.length, 28);
      const folder = e.name[e.name.length - 1] === 0x2f;
      c.writeUInt32LE((((folder ? 0o40755 : 0o100644) << 16) | (folder ? 0x10 : 0)) >>> 0, 38);
      c.writeUInt32LE(e.at, 42);
      await write(c);
      await write(e.name);
    }
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(at - start, 12);
    end.writeUInt32LE(start, 16);
    await write(end);
    await out.sync();
    return at;
  } finally {
    await out.close();
  }
}
