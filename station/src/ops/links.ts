// Symbolic links where Windows may refuse them: making one there takes a privilege most users have not (Developer Mode
// gives it, an administrator has it). Refused, a directory is linked as a junction (no privilege needed; its target
// made absolute) and a file is copied. On Unix, and on Windows with the privilege, links are links.
import { copyFileSync, statSync, symlinkSync } from "node:fs";
import { copyFile, stat, symlink } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { platform } from "../platform/index.ts";

type MakeSync = (target: string, path: string, type?: "dir" | "file" | "junction") => void;
type Make = (target: string, path: string, type?: "dir" | "file" | "junction") => Promise<void>;

const refused = (error: unknown) => platform.linkRefused(error);

/// `path` linked to `target` (relative to `path`'s directory, as a link's is), or what stands in for a link. False when
/// the link was refused and its target is not there to stand in for (yet).
export function linkSync(target: string, path: string, make: MakeSync = symlinkSync): boolean {
  try {
    make(target, path);
    return true;
  } catch (error) {
    if (!refused(error)) throw error;
  }
  const absolute = resolve(dirname(path), target);
  const st = statSync(absolute, { throwIfNoEntry: false });
  if (st === undefined) return false;
  if (st.isDirectory()) make(absolute, path, "junction");
  else copyFileSync(absolute, path);
  return true;
}

export async function link(target: string, path: string, make: Make = symlink): Promise<boolean> {
  try {
    await make(target, path);
    return true;
  } catch (error) {
    if (!refused(error)) throw error;
  }
  const absolute = resolve(dirname(path), target);
  const st = await stat(absolute).catch(() => undefined);
  if (st === undefined) return false;
  if (st.isDirectory()) await make(absolute, path, "junction");
  else await copyFile(absolute, path);
  return true;
}
