// A person's plugins kept on this station (docs/client-plugins.md): what entries their apps grow (a share entry, by
// what is shared) and what is done when one is used (what was shared sent into a chat of this station). Data, not
// code: their agent writes them (tools/plugins.ts), their apps read them (GET /plugins, the `plugin` events), and
// nobody else sees them.
import type { DatabaseSync } from "node:sqlite";

export type Entry = { kind: "share"; match?: string };
export type Action = { kind: "chat"; session: string; send: "auto" | "composer" };
export type Plugin = { id: string; name: string; entries: Entry[]; action: Action; at: number };

/// A plugin's id: what its person calls it by, unique among theirs on this station.
export const ID = /^[a-z][a-z0-9-]{0,31}$/;
/// The most plugins a person keeps on one station.
export const MOST = 50;
const NAME_MAX = 40;
const MATCH_MAX = 500;
const ENTRIES_MAX = 8;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS plugins (
  ws TEXT NOT NULL,
  owner TEXT NOT NULL,
  id TEXT NOT NULL,
  body TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (ws, owner, id)
);
`;

const isObj = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/// What `given` says as a plugin, its action's chat being `session` (already checked by the caller), at `at` (unix
/// seconds); or why it is none.
export function pluginOf(given: unknown, session: string, at: number): Plugin | string {
  if (!isObj(given)) return "a plugin is {id, name, entries, action?}";
  const id = typeof given.id === "string" ? given.id.trim() : "";
  if (!ID.test(id)) return "id is lowercase letters, digits and -, starting with a letter, at most 32 (e.g. douyin)";
  const name = typeof given.name === "string" ? given.name.trim() : "";
  if (name === "" || [...name].length > NAME_MAX) return `name is what the person sees, 1 to ${NAME_MAX} characters`;
  if (!Array.isArray(given.entries) || given.entries.length === 0 || given.entries.length > ENTRIES_MAX) return `entries are 1 to ${ENTRIES_MAX} of {kind: "share", match?}`;
  const entries: Entry[] = [];
  for (const e of given.entries) {
    if (!isObj(e) || e.kind !== "share") return 'an entry is {kind: "share", match?}: the only kind so far';
    if (e.match === undefined || e.match === null || e.match === "") {
      entries.push({ kind: "share" });
      continue;
    }
    if (typeof e.match !== "string" || e.match.length > MATCH_MAX) return `match is a regular expression, at most ${MATCH_MAX} characters`;
    try {
      new RegExp(e.match, "i");
    } catch (error) {
      return `match is no regular expression: ${(error as Error).message}`;
    }
    entries.push({ kind: "share", match: e.match });
  }
  const a = given.action;
  if (a !== undefined && a !== null && !isObj(a)) return 'action is {kind: "chat", session?, send?}';
  if (isObj(a) && a.kind !== undefined && a.kind !== "chat") return 'action\'s kind is "chat": the only kind so far';
  const send = isObj(a) && a.send !== undefined ? a.send : "auto";
  if (send !== "auto" && send !== "composer") return 'send is "auto" (sent at once) or "composer" (put in the chat\'s composer)';
  return { id, name, entries, action: { kind: "chat", session, send }, at };
}

export class PluginStore {
  readonly #db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.#db = db;
    db.exec(SCHEMA);
  }

  /// `owner`'s plugins in workspace `ws`, by id.
  list(ws: string, owner: string): Plugin[] {
    return (this.#db.prepare("SELECT body FROM plugins WHERE ws = ? AND owner = ? ORDER BY id").all(ws, owner) as { body: string }[]).map((r) => JSON.parse(r.body));
  }

  get(ws: string, owner: string, id: string): Plugin | null {
    const row = this.#db.prepare("SELECT body FROM plugins WHERE ws = ? AND owner = ? AND id = ?").get(ws, owner, id) as { body: string } | undefined;
    return row ? JSON.parse(row.body) : null;
  }

  /// A plugin kept, in place of one of the same id; false when `owner` has MOST others already.
  put(ws: string, owner: string, p: Plugin): boolean {
    if (this.get(ws, owner, p.id) === null && this.list(ws, owner).length >= MOST) return false;
    this.#db
      .prepare("INSERT INTO plugins (ws, owner, id, body, at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (ws, owner, id) DO UPDATE SET body = excluded.body, at = excluded.at")
      .run(ws, owner, p.id, JSON.stringify(p), p.at);
    return true;
  }

  /// Whether there was one to delete.
  delete(ws: string, owner: string, id: string): boolean {
    return Number(this.#db.prepare("DELETE FROM plugins WHERE ws = ? AND owner = ? AND id = ?").run(ws, owner, id).changes) > 0;
  }
}
