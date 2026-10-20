// What the drive deletes goes where the machine's own file browser puts it (Finder's ~/.Trash, the freedesktop trash
// a Linux desktop empties), so a delete is undone there as one made on the machine is. A file on another disk goes to
// that disk's own trash (`.Trashes/<uid>` on macOS, `.Trash-<uid>` on Linux), as the system's do: it is moved, never
// copied. Where there is none to move it to (Windows, a disk that will not take one), the caller is told (null).
import { constants } from "node:fs";
import { mkdir, open, rename, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";

/// Moved to the trash `kind` (platform's `trash`): where it is there now. Null: no trash takes it here. `home`: whose
/// trash (the machine's own home, its XDG data folder followed, when none is given); `now`: when, for the freedesktop's
/// note of it.
export async function toTrash(entry: string, kind: "finder" | "freedesktop" | null, now: number, home?: string): Promise<string | null> {
  if (kind === null) return null;
  const uid = process.getuid?.() ?? 0;
  const dev = (await stat(dirname(entry))).dev;
  const data = (home === undefined ? process.env.XDG_DATA_HOME : undefined) || join(home ?? homedir(), ".local", "share");
  home ??= homedir();
  const homeTrash = kind === "finder" ? join(home, ".Trash") : join(data, "Trash");
  const onHomeDisk = await stat(home).then((s) => s.dev === dev, () => false);
  const trash = onHomeDisk ? homeTrash : join(await topOf(dirname(entry), dev), kind === "finder" ? join(".Trashes", String(uid)) : `.Trash-${uid}`);
  try {
    return kind === "finder" ? await intoMac(entry, trash) : await intoFreedesktop(entry, trash, now);
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    // A disk that will not take a trash (read-only, one the station may not write the top of), or one across disks.
    if (code === "EXDEV" || code === "EACCES" || code === "EPERM" || code === "EROFS") return null;
    throw e;
  }
}

/// The top of the disk `dir` is on: the last folder up from it on the same device.
async function topOf(dir: string, dev: number): Promise<string> {
  let at = dir;
  for (;;) {
    const up = dirname(at);
    if (up === at) return at;
    const s = await stat(up).catch(() => null);
    if (!s || s.dev !== dev) return at;
    at = up;
  }
}

/// Finder's: the trash folder itself, a name taken given ` 2`, ` 3`…, as Finder does.
async function intoMac(entry: string, trash: string): Promise<string> {
  await mkdir(trash, { recursive: true, mode: 0o700 });
  const name = basename(entry);
  for (let n = 1; ; n++) {
    const to = join(trash, n === 1 ? name : withNumber(name, n));
    if (await exists(to)) continue;
    await rename(entry, to);
    return to;
  }
}

/// The freedesktop trash: `files/` beside `info/`, where a `.trashinfo` (made first, which claims the name) says where
/// it was and when, for the desktop to put it back.
async function intoFreedesktop(entry: string, trash: string, now: number): Promise<string> {
  const files = join(trash, "files");
  const info = join(trash, "info");
  await mkdir(files, { recursive: true, mode: 0o700 });
  await mkdir(info, { recursive: true, mode: 0o700 });
  const name = basename(entry);
  for (let n = 1; ; n++) {
    const as = n === 1 ? name : withNumber(name, n);
    let claim;
    try {
      claim = await open(join(info, `${as}.trashinfo`), constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "EEXIST") continue;
      throw e;
    }
    try {
      const when = new Date(now);
      const pad = (v: number) => String(v).padStart(2, "0");
      const date = `${when.getFullYear()}-${pad(when.getMonth() + 1)}-${pad(when.getDate())}T${pad(when.getHours())}:${pad(when.getMinutes())}:${pad(when.getSeconds())}`;
      await claim.writeFile(`[Trash Info]\nPath=${encodeURI(entry)}\nDeletionDate=${date}\n`);
    } finally {
      await claim.close();
    }
    const to = join(files, as);
    if (await exists(to)) continue;
    await rename(entry, to);
    return to;
  }
}

/// `name` with a number before its extension (`report 2.pdf`; a folder or a name without one: at its end).
function withNumber(name: string, n: number): string {
  const dot = name.lastIndexOf(".");
  return dot > 0 ? `${name.slice(0, dot)} ${n}${name.slice(dot)}` : `${name} ${n}`;
}

const exists = (path: string) => stat(path).then(() => true, (e: NodeJS.ErrnoException) => e.code !== "ENOENT");
