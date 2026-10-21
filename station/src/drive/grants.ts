// What a station lets another one read of its drive for a member (docs/drive.md "Copying between stations"): a grant
// it signs when the member asks (POST /drive/grant, checked as any of their reads is: they may read those names there,
// and, for a move, may write there too), which the member hands to the station the files go to. That station reads the
// files with it over the station transport (`drive.walk`, `drive.part`, `drive.release`), and this one checks its own
// signature, the workspace it was granted in, and that what is read is under the names granted, before it reads
// anything as that member would. The transport says which station asks and that it is of the workspace; the grant is
// what says a member asked for it: no station reads another's files on its own say.
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DriveError } from "./drive.ts";

/// What a grant says.
export type Granted = {
  v: 1;
  /// The workspace it was asked in, and whether that is the station's own (whose pinned folders a read-only member reads).
  workspace: string;
  home: boolean;
  by: string;
  /// Whether the member reaches every folder here (and so may move what they copy).
  anywhere: boolean;
  root: string;
  path: string;
  names: string[];
  move: boolean;
  expires: number;
};

/// A grant is good for this long: a transfer that waited (its station away) is taken up again within it.
export const GRANT_MS = 7 * 24 * 3600 * 1000;

const b64 = (b: Buffer) => b.toString("base64url");

/// The station's key for its grants, made the first time (its data directory's own, never sent anywhere).
export function grantKey(data: string): Buffer {
  const path = join(data, "drive-grant.key");
  try {
    const key = readFileSync(path);
    if (key.length >= 32) return key;
  } catch {}
  const key = randomBytes(32);
  writeFileSync(path, key, { mode: 0o600 });
  return key;
}

export function sign(key: Buffer, g: Granted): string {
  const body = b64(Buffer.from(JSON.stringify(g)));
  return `${body}.${b64(createHmac("sha256", key).update(body).digest())}`;
}

/// What `grant` says, when this station signed it, it has not expired, and it was granted in `workspace`.
export function verify(key: Buffer, grant: unknown, workspace: string | null, now: number): Granted {
  const refuse = () => new DriveError("permission", "that is not a grant of this station's");
  if (typeof grant !== "string") throw refuse();
  const [body, sig] = grant.split(".");
  if (!body || !sig) throw refuse();
  const want = createHmac("sha256", key).update(body).digest();
  const got = Buffer.from(sig, "base64url");
  if (got.length !== want.length || !timingSafeEqual(got, want)) throw refuse();
  let g: Granted;
  try {
    g = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    throw refuse();
  }
  if (g?.v !== 1 || !Array.isArray(g.names)) throw refuse();
  if (g.expires < now) throw new DriveError("permission", "that grant has expired");
  if (workspace !== null && g.workspace !== workspace) throw refuse();
  return g;
}

/// Whether `path` (relative to the folder the names are in) is one of the names granted or under one.
export function covers(g: Granted, path: string): boolean {
  const parts = path.split("/");
  return parts.length > 0 && g.names.includes(parts[0]!) && !parts.some((p) => p === "" || p === "." || p === "..");
}
