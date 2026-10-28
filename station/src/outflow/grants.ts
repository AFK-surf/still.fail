// The grants of data outflow (docs/data-outflow.md): which program on this machine may read which kinds of the
// station's data, given by a person at it, kept until revoked. Kept in <data>/outflow.json (0600): each grant with the
// SHA-256 of its token (never the token), the program as the system said it then, what it said of itself, its kinds,
// when and the latest reads.
import { createHash, randomBytes } from "node:crypto";
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";

/// The kinds of data a program may be granted.
export const SCOPES = ["usage", "chats", "messages"] as const;
export type Scope = (typeof SCOPES)[number];

/// A program as the system says it (the other end of the socket): its code signature where it has one, else its
/// executable and that file's SHA-256.
export type Identity = {
  path: string;
  /// Whether its signature holds now (macOS).
  valid: boolean;
  teamId: string | null;
  identifier: string | null;
  /// The signing certificate's name ("Developer ID Application: …").
  signer: string | null;
  /// The app it is in, as that app names itself.
  app: string | null;
  /// Of an unsigned program: its executable's SHA-256.
  sha256: string | null;
};

/// A program is the one granted when it is signed by the same team with the same identifier, or (unsigned) the same
/// executable, byte for byte.
export function identityKey(i: Identity): string {
  return i.valid && i.teamId !== null && i.identifier !== null ? `team:${i.teamId}:${i.identifier}` : `file:${i.path}:${i.sha256 ?? ""}`;
}

export type Read = { at: number; scope: Scope; rows: number };

export type Grant = {
  id: string;
  /// SHA-256 of its token, hex.
  token: string;
  identity: Identity;
  /// What the program said of itself when it asked (shown as its own words).
  said: { name: string; purpose: string };
  scopes: Scope[];
  grantedAt: number;
  /// The latest reads, the newest last (at most READS_KEPT).
  reads: Read[];
};

/// A grant as the pages are given it: without its token.
export type GrantView = Omit<Grant, "token"> & { lastReadAt: number | null };

const READS_KEPT = 100;
const TOKEN_PREFIX = "sfo_";

const digest = (token: string) => createHash("sha256").update(token).digest("hex");

export class OutflowGrants {
  readonly #file: string;
  readonly #now: () => number;
  #grants: Grant[];
  readonly #listeners = new Set<() => void>();

  constructor(data: string, now: () => number) {
    this.#file = join(data, "outflow.json");
    this.#now = now;
    this.#grants = this.#load();
  }

  list(): GrantView[] {
    return this.#grants.map(({ token: _, ...g }) => ({ ...g, lastReadAt: g.reads.at(-1)?.at ?? null }));
  }

  /// A new grant for `identity`, and its token (said once, never kept). Another grant of the same program goes: what
  /// it asked for now is what it has.
  add(identity: Identity, said: Grant["said"], scopes: Scope[]): { grant: GrantView; token: string } {
    const token = TOKEN_PREFIX + randomBytes(32).toString("base64url");
    const key = identityKey(identity);
    const grant: Grant = { id: randomBytes(8).toString("hex"), token: digest(token), identity, said, scopes: [...scopes], grantedAt: this.#now(), reads: [] };
    this.#grants = [...this.#grants.filter((g) => identityKey(g.identity) !== key), grant];
    this.#save();
    return { grant: this.list().find((g) => g.id === grant.id)!, token };
  }

  /// The grant `token` is of, if it is still there.
  byToken(token: string): Grant | null {
    if (!token.startsWith(TOKEN_PREFIX)) return null;
    const hash = digest(token);
    return this.#grants.find((g) => g.token === hash) ?? null;
  }

  /// Revokes grant `id`; whether there was one.
  revoke(id: string): boolean {
    const before = this.#grants.length;
    this.#grants = this.#grants.filter((g) => g.id !== id);
    if (this.#grants.length === before) return false;
    this.#save();
    return true;
  }

  /// A read made with grant `id`.
  read(id: string, scope: Scope, rows: number): void {
    const grant = this.#grants.find((g) => g.id === id);
    if (!grant) return;
    grant.reads = [...grant.reads, { at: this.#now(), scope, rows }].slice(-READS_KEPT);
    this.#save();
  }

  /// Told when the grants or their reads changed; the returned function stops it.
  listen(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  }

  #load(): Grant[] {
    try {
      const raw = JSON.parse(readFileSync(this.#file, "utf8"));
      return Array.isArray(raw?.grants) ? raw.grants : [];
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "ENOENT") log.warn("outflow", "the grants do not read; none are had", { error: (e as Error).message });
      return [];
    }
  }

  #save(): void {
    const tmp = `${this.#file}.tmp-${process.pid}`;
    writeFileSync(tmp, `${JSON.stringify({ grants: this.#grants })}\n`, { mode: 0o600 });
    renameSync(tmp, this.#file);
    for (const listener of this.#listeners) listener();
  }
}
