// The grants of data outflow (docs/data-outflow.md): which program on this machine may read which kinds of the
// station's data (or of every station of its workspace), given by an admin of the workspace in still.fail, kept until
// revoked; and the requests the admins have not answered yet, or whose program has not come for its token yet. Kept
// in <data>/outflow.json (0600): each grant with the SHA-256 of its token (never the token), the program as the system
// said it then, what it said of itself, its kinds, how far it reaches, who allowed it, when and the latest reads.
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

/// What a grant reaches: this station's chats, or those of every station of its home workspace.
export type Reach = "station" | "workspace";

/// `station`: the station read, when not this one.
/// Whose a request or grant is: its program, and the key that program gave it (one program can ask for several
/// grants under keys of its own, each its own; a grant from before has none).
const whose = (i: Identity, key: string | undefined) => `${identityKey(i)}\u0000${key ?? ""}`;

export type Read = { at: number; scope: Scope; rows: number; station?: string };

export type Grant = {
  id: string;
  /// SHA-256 of its token, hex; empty while its program has not come for it yet (allowed, the token not made).
  token: string;
  /// SHA-256 of the tokens it was given again since (its program asking for what it already holds), the newest last
  /// (at most TOKENS_KEPT); absent while it has none.
  again?: string[];
  identity: Identity;
  /// What the program said of itself when it asked (shown as its own words).
  said: { name: string; purpose: string };
  /// The key the program asked under (absent: none).
  key?: string;
  scopes: Scope[];
  /// Absent on a grant from before: this station.
  reach?: Reach;
  /// The admin who allowed it (their email); absent on a grant from before, allowed at this machine.
  allowedBy?: string;
  grantedAt: number;
  /// The latest reads, the newest last (at most READS_KEPT).
  reads: Read[];
};

/// A grant as the pages are given it: without its token.
export type GrantView = Omit<Grant, "token" | "again" | "reach"> & { reach: Reach; lastReadAt: number | null; taken: boolean };

/// A program's request, until its program takes what was answered: asking while no admin answered; then allowed
/// (with what the admin left of it) or refused.
export type Request = {
  id: string;
  identity: Identity;
  said: { name: string; purpose: string };
  key: string;
  scopes: Scope[];
  reach: Reach;
  askedAt: number;
  /// Allowed: the grant made of it at once (shown and revocable), its token given when the program comes for it.
  answer: null | { at: number; by: string; allow: false } | { at: number; by: string; allow: true; grant: string };
};

/// What a program asking is answered, once there is an answer: its grant and token, or refused.
export type Taken = { grant: GrantView; token: string } | "refused";

const READS_KEPT = 100;
/// Tokens a grant was given again, kept at most: the program's copies still running keep reading with theirs.
const TOKENS_KEPT = 8;
/// A request is kept this long after it was asked or answered, unless its program takes the answer before: one no
/// admin answers in a week goes, as does an allowed one its program never came back for.
export const REQUEST_KEPT_MS = 7 * 24 * 60 * 60_000;
const TOKEN_PREFIX = "sfo_";

const digest = (token: string) => createHash("sha256").update(token).digest("hex");

export class OutflowGrants {
  readonly #file: string;
  readonly #now: () => number;
  #grants: Grant[];
  #requests: Request[];
  readonly #listeners = new Set<() => void>();

  constructor(data: string, now: () => number) {
    this.#file = join(data, "outflow.json");
    this.#now = now;
    const kept = this.#load();
    this.#grants = kept.grants;
    this.#requests = kept.requests;
    // Allowed before a grant was made at once (it waited for its program): made now, so it shows and can be revoked.
    let made = false;
    for (const request of this.#requests) {
      const answer = request.answer as { allow?: boolean; grant?: string; scopes?: Scope[]; reach?: Reach; by: string; at: number } | null;
      if (answer?.allow !== true || answer.grant !== undefined) continue;
      const grant: Grant = { id: randomBytes(8).toString("hex"), token: "", identity: request.identity, said: request.said, ...(request.key ? { key: request.key } : {}), scopes: answer.scopes ?? [], reach: answer.reach ?? "station", allowedBy: answer.by, grantedAt: answer.at, reads: [] };
      this.#grants.push(grant);
      request.answer = { at: answer.at, by: answer.by, allow: true, grant: grant.id };
      made = true;
    }
    if (made) this.#save();
  }

  list(): GrantView[] {
    return this.#grants.map(({ token, again: _, ...g }) => ({ ...g, reach: g.reach ?? "station", lastReadAt: g.reads.at(-1)?.at ?? null, taken: token !== "" }));
  }

  /// The requests no admin has answered yet, the oldest first.
  asking(): Request[] {
    this.#expire();
    return this.#requests.filter((r) => r.answer === null);
  }

  /// A program asks under `key`: its request, a new one, or the one it already has under that key that it has not
  /// taken (asked again while no admin answered, it says now what it asks for). One a request of it refused before is
  /// asked anew.
  ask(identity: Identity, said: Request["said"], scopes: Scope[], reach: Reach, key = ""): Request {
    this.#expire();
    const it = whose(identity, key);
    const had = this.#requests.find((r) => whose(r.identity, r.key) === it && r.answer?.allow !== false);
    if (had?.answer === null) {
      Object.assign(had, { identity, said, scopes: [...scopes], reach });
      this.#save();
      return had;
    }
    if (had) return had;
    const request: Request = { id: randomBytes(8).toString("hex"), identity, said, key, scopes: [...scopes], reach, askedAt: this.#now(), answer: null };
    this.#requests = [...this.#requests.filter((r) => whose(r.identity, r.key) !== it), request];
    this.#save();
    return request;
  }

  /// A program asking for what one of its grants already gives it (those kinds, as far or less, under any key of its):
  /// that grant again, with a token of its own, at once, no admin asked. Null when none gives it all.
  held(identity: Identity, scopes: Scope[], reach: Reach): { grant: GrantView; token: string } | null {
    const it = identityKey(identity);
    const grant = this.#grants
      // One allowed but not taken yet is its program's to take through its request.
      .filter((g) => g.token !== "" && identityKey(g.identity) === it && scopes.every((s) => g.scopes.includes(s)) && (reach === "station" || g.reach === "workspace"))
      .at(-1);
    if (!grant) return null;
    const token = TOKEN_PREFIX + randomBytes(32).toString("base64url");
    grant.again = [...(grant.again ?? []), digest(token)].slice(-TOKENS_KEPT);
    this.#save();
    return { grant: this.list().find((g) => g.id === grant.id)!, token };
  }

  /// An admin's answer to request `id` (`by`: their email): allowed with the kinds and reach they left of it (no more
  /// than it asked), or refused. False when there is no such request waiting for one.
  answer(id: string, by: string, answer: { allow: false } | { allow: true; scopes: Scope[]; reach: Reach }): boolean {
    this.#expire();
    const request = this.#requests.find((r) => r.id === id && r.answer === null);
    if (!request) return false;
    const at = this.#now();
    if (answer.allow) {
      const scopes = request.scopes.filter((s) => answer.scopes.includes(s));
      if (scopes.length === 0) return this.answer(id, by, { allow: false });
      const reach: Reach = request.reach === "workspace" && answer.reach === "workspace" ? "workspace" : "station";
      // The grant stands from now on: in the list, revocable; another of the same program under the same key goes.
      const it = whose(request.identity, request.key);
      const grant: Grant = { id: randomBytes(8).toString("hex"), token: "", identity: request.identity, said: request.said, ...(request.key === "" ? {} : { key: request.key }), scopes, reach, allowedBy: by, grantedAt: at, reads: [] };
      this.#grants = [...this.#grants.filter((g) => whose(g.identity, g.key) !== it), grant];
      request.answer = { at, by, allow: true, grant: grant.id };
    } else request.answer = { at, by, allow: false };
    this.#save();
    return true;
  }

  /// What request `id`'s program is given, once answered (null while asking, or when there is no such request): the
  /// grant made of it and its token (made now, said once, never kept), or refused (also when the grant was revoked
  /// before its program came for it). Either way the request goes.
  take(id: string): Taken | null {
    this.#expire();
    const request = this.#requests.find((r) => r.id === id);
    if (!request || request.answer === null) return null;
    this.#requests = this.#requests.filter((r) => r !== request);
    if (!request.answer.allow) {
      this.#save();
      return "refused";
    }
    const grant = this.#grants.find((g) => g.id === (request.answer as { grant: string }).grant);
    if (!grant) {
      this.#save();
      return "refused";
    }
    const token = TOKEN_PREFIX + randomBytes(32).toString("base64url");
    grant.token = digest(token);
    this.#save();
    return { grant: this.list().find((g) => g.id === grant.id)!, token };
  }

  /// The grant `token` is of, if it is still there.
  byToken(token: string): Grant | null {
    if (!token.startsWith(TOKEN_PREFIX)) return null;
    const hash = digest(token);
    return this.#grants.find((g) => g.token === hash || g.again?.includes(hash)) ?? null;
  }

  /// Revokes grant `id` (one its program has not come for yet too); whether there was one.
  revoke(id: string): boolean {
    const before = this.#grants.length;
    this.#grants = this.#grants.filter((g) => g.id !== id);
    if (this.#grants.length === before) return false;
    this.#requests = this.#requests.filter((r) => !(r.answer?.allow === true && r.answer.grant === id));
    this.#save();
    return true;
  }

  /// A read made with grant `id`.
  read(id: string, scope: Scope, rows: number, station?: string): void {
    const grant = this.#grants.find((g) => g.id === id);
    if (!grant) return;
    grant.reads = [...grant.reads, { at: this.#now(), scope, rows, ...(station === undefined ? {} : { station }) }].slice(-READS_KEPT);
    this.#save();
  }

  /// Told when the grants or their reads changed; the returned function stops it.
  listen(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  }

  /// Requests asked or answered longer ago than REQUEST_KEPT_MS go.
  #expire(): void {
    const since = this.#now() - REQUEST_KEPT_MS;
    const kept = this.#requests.filter((r) => (r.answer?.at ?? r.askedAt) >= since);
    if (kept.length === this.#requests.length) return;
    this.#requests = kept;
    this.#save();
  }

  #load(): { grants: Grant[]; requests: Request[] } {
    try {
      const raw = JSON.parse(readFileSync(this.#file, "utf8"));
      return { grants: Array.isArray(raw?.grants) ? raw.grants : [], requests: Array.isArray(raw?.requests) ? raw.requests : [] };
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "ENOENT") log.warn("outflow", "the grants do not read; none are had", { error: (e as Error).message });
      return { grants: [], requests: [] };
    }
  }

  #save(): void {
    const tmp = `${this.#file}.tmp-${process.pid}`;
    writeFileSync(tmp, `${JSON.stringify({ grants: this.#grants, requests: this.#requests })}\n`, { mode: 0o600 });
    renameSync(tmp, this.#file);
    for (const listener of this.#listeners) listener();
  }
}
