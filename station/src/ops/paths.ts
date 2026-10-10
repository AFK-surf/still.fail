// Paths as the station checks them (the Rust station's Path, files.rs `clean`): absolute, worked out without following
// links, and compared component by component. On Unix exactly as before; on Windows as Windows has them: `\` and `/`
// both separate, a drive or a share starts an absolute path, and case does not tell two paths apart.
import { win32 } from "node:path";

const WINDOWS = process.platform === "win32";
const SEP = WINDOWS ? /[\\/]/ : "/";

/// A path's components (empty ones kept: callers drop what they do not want).
export const segments = (path: string): string[] => path.split(SEP);

/// files.rs `clean` on Unix: the path absolute (a leading `/`), `.` and `..` worked out lexically. What a relative path
/// from a Unix machine is made of, whatever this one is (`/` separates; on Windows `\` too).
export function cleanPosix(path: string): string {
  const out: string[] = [];
  for (const part of segments(path)) {
    if (part === "" || part === ".") continue;
    if (part === "..") out.pop();
    else out.push(part);
  }
  return `/${out.join("/")}`;
}

/// A path absolute, with `.` and `..` worked out (no link followed). On Windows, one with no drive is on the current
/// one, and nothing given is the drive's root (as nothing is `/` on Unix).
export function clean(path: string): string {
  if (!WINDOWS) return cleanPosix(path);
  return win32.resolve(path === "" ? "\\" : path);
}

const key = (path: string) => (WINDOWS ? path.toLowerCase() : path);

/// The same path (both cleaned, or both canonical).
export const samePath = (a: string, b: string) => key(a) === key(b);

/// Path::starts_with: `path` is `dir` or under it (both cleaned, or both canonical).
export function within(path: string, dir: string): boolean {
  if (!WINDOWS) return dir === "/" || path === dir || path.startsWith(`${dir}/`);
  const [p, d] = [key(path), key(dir)];
  return p === d || p.startsWith(/[\\/]$/.test(d) ? d : `${d}\\`);
}

/// Under `dir`, and not `dir` itself.
export const inside = (path: string, dir: string) => !samePath(path, dir) && within(path, dir);

/// Path::file_name: the last part; none for `..` or the root.
export function fileName(path: string): string | null {
  const parts = segments(path).filter((p) => p !== "" && p !== ".");
  const last = parts.at(-1);
  if (last === undefined || last === "..") return null;
  // A drive alone (`C:`) is a root, not a name.
  return WINDOWS && parts.length === 1 && /^[A-Za-z]:$/.test(last) ? null : last;
}

/// The last part of a path from any machine (another station's, Unix or Windows): what follows its last `/` or `\`.
export const anyBaseName = (path: string) => path.split(/[\\/]/).filter((p) => p !== "").at(-1) ?? "";
