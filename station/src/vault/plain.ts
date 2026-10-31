// The library not locked (docs/vault.md 不加锁的库): in a workspace without security mode, a person's secrets kept on
// this station as they are, in plain text, beside the profiles' keys in config.json. Nothing here is encrypted: who
// may read an item is only who it is (its owner, by the email the cloud's credential says), and the agents of the
// station could read the database. What it gives is the same way of using them as the vault's (a request, its card,
// the owner's decision, the proxy), and that their values stay out of the files agents read. Once security mode is on,
// nothing is written here but deletions: the owner's app moves each item into their encrypted vault (`vault.migrate`).
import type { DatabaseSync } from "node:sqlite";
import { type Kind, type Listing, type Mode, type Scope, SCOPES, browserListingOk } from "./crypto.ts";

/// The id a plain library goes by where a vault's would (requests, the core's topics).
export const PLAIN = "plain";

export type PlainItem = {
  ws: string; id: string; owner: string; version: number; kind: Kind; name: string; fields: Record<string, string>; notes: string;
  listing?: Listing; at: number; deleted?: true;
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_plain (
  ws TEXT NOT NULL,
  id TEXT NOT NULL,
  owner TEXT NOT NULL,
  version INTEGER NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, id)
);
CREATE TABLE IF NOT EXISTS vault_plain_lasts (
  ws TEXT NOT NULL,
  owner TEXT NOT NULL,
  lasts TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (ws, owner)
);
`;

export const KINDS: Kind[] = ["token", "ssh_key", "login", "file", "browser"];
export const MODES: Mode[] = ["proxy", "ssh", "env", "file", "browser"];
/// The fields each kind of item holds: a file's `content` is its bytes in base64, `filename` what it is called; a
/// sign-in's `cookies` the cookies of its sites, as JSON (browser/signins.ts).
export const FIELDS: Record<Kind, string[]> = { token: ["value"], ssh_key: ["private_key", "public_key"], login: ["username", "password", "totp"], file: ["content", "filename"], browser: ["cookies"] };
/// The most a file kept in the vault may be (its bytes): one credential's file (a kubeconfig, a service account's key,
/// a certificate), not a store of files.
export const FILE_MOST = 64 * 1024;
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

/// Why a file's fields are not one (its content base64, at most FILE_MOST, its name a file's), or null.
export function fileOk(fields: Record<string, string>): string | null {
  const content = fields.content ?? "";
  if (content.length % 4 !== 0 || !BASE64.test(content)) return "a file's content is its bytes in base64";
  if (Buffer.byteLength(content, "base64") > FILE_MOST) return `a file is at most ${FILE_MOST / 1024} KB`;
  const name = fields.filename;
  if (name !== undefined && (name.length > 200 || /[/\\\0]/.test(name) || name === "." || name === "..")) return "a file's name is a name, not a path";
  return null;
}
const isStr = (v: unknown, max = 100_000): v is string => typeof v === "string" && v.length <= max;

/// An item as the pages are told it: all but its fields.
export function shown(i: PlainItem): Omit<PlainItem, "fields"> {
  const { fields: _, ...rest } = i;
  return rest;
}

/// Whether `next` may follow `prev` (none: a new one) for `owner`; why not, or null.
export function plainOk(prev: PlainItem | null, next: PlainItem, owner: string): string | null {
  if (next === null || typeof next !== "object" || !isStr(next.id, 64) || !/^i_[0-9A-Z]{26}$/.test(next.id)) return "an item is {id: i_<ULID>, …}";
  if (next.owner !== owner) return "an item is its owner's own";
  if (prev !== null && prev.owner !== owner) return "no such item here, or not yours";
  if (prev?.deleted) return "the item is deleted";
  if (!Number.isSafeInteger(next.at)) return "at is unix seconds";
  if (next.deleted === true) return null;
  if (!KINDS.includes(next.kind)) return "kind is token, ssh_key, login, file or browser";
  if (!isStr(next.name, 200) || next.name.trim() === "") return "an item has a name";
  if (!isStr(next.notes, 10_000)) return "notes are text";
  const fields = next.fields;
  if (fields === null || typeof fields !== "object" || Object.entries(fields).some(([k, v]) => !FIELDS[next.kind].includes(k) || !isStr(v))) return `a ${next.kind}'s fields are ${FIELDS[next.kind].join(", ")}`;
  if (next.kind === "file") {
    const why = fileOk(fields);
    if (why !== null) return why;
  }
  const l = next.listing;
  if (l !== undefined) {
    if (l === null || typeof l !== "object" || !isStr(l.name, 200) || l.kind !== next.kind) return "a listing names the item and its kind";
    if (!Array.isArray(l.modes) || l.modes.length === 0 || !l.modes.every((m) => MODES.includes(m))) return "a listing's modes are proxy, ssh, env, file or browser";
    if (l.modes.includes("file") !== (next.kind === "file") || (next.kind === "file" && l.modes.length > 1)) return "a file is given as a file, and only a file is";
    if (!Array.isArray(l.hosts) || !l.hosts.every((h) => isStr(h, 253) && /^(\*\.)?[a-z0-9.-]+$/.test(h))) return "a listing's hosts are host names";
    if (l.modes.includes("proxy") && l.hosts.length === 0) return "given through the proxy, it names its hosts";
    const sign = browserListingOk(l);
    if (sign !== null) return sign;
    if (l.env !== undefined && !(isStr(l.env, 100) && /^[A-Za-z_][A-Za-z0-9_]*$/.test(l.env))) return "env is a variable's name";
    if (l.lasts !== undefined && !SCOPES.includes(l.lasts)) return "lasts is once, hour or chat";
  }
  return null;
}

export class PlainStore {
  readonly #db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.#db = db;
    db.exec(SCHEMA);
  }

  /// `owner`'s items in a workspace (deleted ones too: a version saying so).
  items(ws: string, owner: string): PlainItem[] {
    return (this.#db.prepare("SELECT body FROM vault_plain WHERE ws = ? AND owner = ? ORDER BY id").all(ws, owner) as { body: string }[]).map((r) => JSON.parse(r.body));
  }

  item(ws: string, id: string): PlainItem | null {
    const row = this.#db.prepare("SELECT body FROM vault_plain WHERE ws = ? AND id = ?").get(ws, id) as { body: string } | undefined;
    return row ? JSON.parse(row.body) : null;
  }

  /// The longest grant `owner`'s items are given for where an item says none, and when they said so (none: any).
  lasts(ws: string, owner: string): { lasts: Scope; at: number } | null {
    const row = this.#db.prepare("SELECT lasts, at FROM vault_plain_lasts WHERE ws = ? AND owner = ?").get(ws, owner) as { lasts: Scope; at: number } | undefined;
    return row ? { lasts: row.lasts, at: row.at } : null;
  }

  /// `owner`'s longest grant, said at `at` (unix seconds): kept unless what is kept was said later (each station of
  /// the workspace is told it; the latest word wins wherever it arrives first). Why not, or null.
  setLasts(ws: string, owner: string, lasts: unknown, at: unknown): string | null {
    if (!SCOPES.includes(lasts as Scope)) return "lasts is once, hour or chat";
    if (!Number.isSafeInteger(at)) return "at is unix seconds";
    this.#db
      .prepare("INSERT INTO vault_plain_lasts (ws, owner, lasts, at) VALUES (?, ?, ?, ?) ON CONFLICT (ws, owner) DO UPDATE SET lasts = excluded.lasts, at = excluded.at WHERE excluded.at >= vault_plain_lasts.at")
      .run(ws, owner, lasts as Scope, at as number);
    return null;
  }

  /// A new version, in place of the one before; a deleted one keeps nothing of what it held.
  put(i: PlainItem): void {
    const kept: PlainItem = i.deleted ? { ws: i.ws, id: i.id, owner: i.owner, version: i.version, kind: i.kind, name: "", fields: {}, notes: "", at: i.at, deleted: true } : i;
    this.#db.prepare("INSERT INTO vault_plain (ws, id, owner, version, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET version = excluded.version, body = excluded.body").run(i.ws, i.id, i.owner, i.version, JSON.stringify(kept));
  }
}

const made = new WeakMap<DatabaseSync, PlainStore>();

/// The plain store of a database: one per database, whoever asks.
export function plainStore(db: DatabaseSync): PlainStore {
  let s = made.get(db);
  if (!s) made.set(db, (s = new PlainStore(db)));
  return s;
}
