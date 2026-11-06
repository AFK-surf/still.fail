import { createHash } from "node:crypto";

/// A sandbox's name for a station's key (a session's): what the front door takes (a lowercase letter, then lowercase
/// letters, digits and `-`, 31 at most), the same for the same key, apart for keys that clean up the same.
export function sandboxName(key: string): string {
  const clean = key.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 16).replace(/-+$/, "");
  const hash = createHash("sha256").update(key).digest("hex").slice(0, 10);
  return clean === "" ? `s-${hash}` : `s-${clean}-${hash}`;
}

/// A station's key (a session's) as a runner's id has it after its kind (agents/process.ts `runnerId`): safe as a file
/// name, a hash keeping two keys that clean up the same apart. A session's sandbox is named from it.
export function keyPart(key: string): string {
  const clean = key.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 24);
  return clean === key ? clean : `${clean}-${createHash("sha256").update(key).digest("hex").slice(0, 10)}`;
}
