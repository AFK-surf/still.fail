// The core's data center (data.rs; docs/core-db.md): the one place what the cloud and the stations said is held, as
// records by table and key, in memory and written through to the host's database (the same tables, keys and JSON as
// the Rust core: either core opens the other's). A topic of this data has no value of its own in the store: its value
// is read from here when asked for, and a change here tells the store.
import type { Host, DbOp } from "./host.ts";
import type { Topic } from "./protocol.ts";
import type { Runner } from "./runtime.ts";
import { compareKeys, equal, isObject, parseJson, toJsonBytes } from "./util.ts";

/// Between the parts of a key: sorts before every character a part can hold.
export const SEP = "\u0001";

/// Every table, to load them all at start.
const TABLES = ["me", "workspace", "overview", "session", "row", "session_summary", "thread", "list", "draft", "chat_ref", "choice", "prefs", "changelog"];

type Shape = { one: { table: string; key: string } } | { list: { table: string; scope: string; idField: string } };

function join(parts: string[]): string {
  return parts.join(SEP);
}

function shape(topic: Topic): Shape | null {
  const s = (k: string) => topic[k] as string;
  switch (topic.topic) {
    case "workspace":
      return { one: { table: "workspace", key: s("workspace") } };
    case "overview":
      return { one: { table: "overview", key: s("station") } };
    case "session":
      return { one: { table: "session", key: join([s("station"), s("key")]) } };
    case "chatRows":
      return { list: { table: "row", scope: s("station"), idField: "id" } };
    case "sessions":
      return { list: { table: "session_summary", scope: s("station"), idField: "key" } };
    case "threads":
      return { list: { table: "thread", scope: s("station"), idField: "id" } };
    case "draft":
      return { one: { table: "draft", key: join([s("station"), s("chat")]) } };
    case "prefs":
      return { one: { table: "prefs", key: "device" } };
    default:
      return null;
  }
}

/// Whether a topic's value is held here (rather than by the store).
export function holds(topic: Topic): boolean {
  return shape(topic) !== null;
}

/// How long a record changing as it is typed waits before it is written.
export const SOON_MS = 300;

function idText(id: unknown): string | null {
  if (typeof id === "string") return id;
  if (typeof id === "number") return String(id);
  return null;
}

export class Data {
  readonly #host: Host;
  readonly #runner: Runner;
  /// table → key → value.
  readonly #records = new Map<string, Map<string, unknown>>();
  #changed: ((topic: Topic) => void) | null = null;
  #tail: Promise<void> = Promise.resolve();
  readonly #soon = new Map<string, [string, string, Uint8Array]>();
  #flushing = false;
  /// Model selections awaiting their station: never persisted as confirmed data.
  readonly #modelEdits = new Map<string, [unknown, unknown]>();

  constructor(host: Host, runner: Runner) {
    this.#host = host;
    this.#runner = runner;
  }

  onChange(listener: (topic: Topic) => void): void {
    this.#changed = listener;
  }

  #table(table: string): Map<string, unknown> {
    let t = this.#records.get(table);
    if (!t) {
      t = new Map();
      this.#records.set(table, t);
    }
    return t;
  }

  /// Reads every record from the host's database. What arrived meanwhile is newer and stays.
  async load(): Promise<void> {
    const found: [string, string, unknown][] = [];
    for (const table of TABLES) {
      let rows: [string, Uint8Array][] = [];
      try {
        rows = await this.#host.dbRead({ table, from: "", to: "\u{10ffff}" });
      } catch {}
      for (const [key, bytes] of rows) {
        const value = parseJson(bytes);
        if (value !== undefined) found.push([table, key, value]);
      }
    }
    for (const [table, key, value] of found) {
      const t = this.#table(table);
      if (!t.has(key)) t.set(key, value);
    }
    this.#tellAll();
  }

  /// A held topic's value; undefined while nothing is known of it.
  get(topic: Topic): unknown {
    const s = shape(topic);
    if (!s) return undefined;
    if ("one" in s) return structuredCloneOrSelf(this.#records.get(s.one.table)?.get(s.one.key));
    const { table, scope } = s.list;
    const ids = this.#records.get("list")?.get(join([table, scope]));
    if (!Array.isArray(ids)) return undefined;
    const items = this.#records.get(table);
    const out: unknown[] = [];
    for (const id of ids) {
      if (typeof id !== "string") continue;
      const item = items?.get(join([scope, id]));
      if (item !== undefined) out.push(structuredCloneOrSelf(item));
    }
    return out;
  }

  /// The visible selection over confirmed data.
  shown(topic: Topic): unknown {
    const value = this.get(topic);
    if (value === undefined) return undefined;
    if (topic.topic === "overview" && isObject(value) && Array.isArray(value.profiles)) {
      for (const p of value.profiles) {
        if (!isObject(p)) continue;
        const id = typeof p.id === "string" ? p.id : "";
        const edit = this.#modelEdits.get(`${topic.station as string}${SEP}${id}`);
        if (edit) {
          p.modelsSaving = edit[1] as never;
          p.models = edit[0] as never;
        }
      }
    }
    return value;
  }

  /// One write at a time per profile; all screens read the same optimistic selection.
  beginModels(station: string, id: string, models: unknown): boolean {
    const key = `${station}${SEP}${id}`;
    const overview = this.get({ topic: "overview", station });
    const profile = isObject(overview) && Array.isArray(overview.profiles) ? overview.profiles.find((p) => isObject(p) && p.id === id) : undefined;
    const before: unknown[] = isObject(profile) && Array.isArray(profile.models) ? profile.models : [];
    const after: unknown[] = Array.isArray(models) ? models : [];
    const has = (list: unknown[], m: unknown) => list.some((x) => equal(x, m));
    const changed = [...before, ...after].filter((m) => has(before, m) !== has(after, m));
    if (this.#modelEdits.has(key)) return false;
    this.#modelEdits.set(key, [models, changed]);
    this.#tell({ topic: "overview", station });
    return true;
  }

  endModels(station: string, id: string): void {
    this.#modelEdits.delete(`${station}${SEP}${id}`);
    this.#tell({ topic: "overview", station });
  }

  /// A held topic's new value: its records that differ are written, those of items no longer in a list removed.
  set(topic: Topic, value: unknown): void {
    const s = shape(topic);
    if (!s) return;
    const ops: DbOp[] = [];
    const put = (table: string, key: string, v: unknown) => {
      const t = this.#table(table);
      if (t.has(key) && equal(t.get(key), v)) return;
      ops.push({ put: { table, key, value: toJsonBytes(v) } });
      t.set(key, structuredCloneOrSelf(v));
    };
    if ("one" in s) put(s.one.table, s.one.key, value);
    else {
      const { table, scope, idField } = s.list;
      const items = Array.isArray(value) ? value : [];
      const ids: string[] = [];
      for (const item of items) {
        const id = idText(isObject(item) ? item[idField] : undefined);
        if (id === null) continue;
        ids.push(id);
        put(table, join([scope, id]), item);
      }
      const kept = new Set(ids.map((id) => join([scope, id])));
      const prefix = scope + SEP;
      const t = this.#table(table);
      for (const key of [...t.keys()].sort(compareKeys)) {
        if (key.startsWith(prefix) && !kept.has(key)) {
          t.delete(key);
          ops.push({ delete: { table, key } });
        }
      }
      put("list", join([table, scope]), ids);
    }
    if (ops.length > 0) {
      this.#write(ops);
      this.#tell(topic);
    }
  }

  /// A held topic's new value, as it is typed (a draft): there at once, written a moment after its last change.
  setSoon(topic: Topic, value: unknown): void {
    const s = shape(topic);
    if (!s || !("one" in s)) return this.set(topic, value);
    const { table, key } = s.one;
    const t = this.#table(table);
    if (t.has(key) && equal(t.get(key), value)) return;
    this.#soon.set(`${table}${SEP}${key}`, [table, key, toJsonBytes(value)]);
    t.set(key, structuredCloneOrSelf(value));
    this.#tell(topic);
    if (this.#flushing) return;
    this.#flushing = true;
    this.#runner.spawn(async () => {
      await this.#runner.sleep(SOON_MS);
      this.#flushing = false;
      const ops: DbOp[] = [...this.#soon.values()].map(([table, key, value]) => ({ put: { table, key, value } }));
      this.#soon.clear();
      if (ops.length > 0) this.#write(ops);
    });
  }

  /// Changes a held topic's value in place; does nothing while nothing is known of it.
  update(topic: Topic, change: (value: unknown) => unknown): void {
    const value = this.get(topic);
    if (value === undefined) return;
    const next = change(value);
    this.set(topic, next === undefined ? value : next);
  }

  /// A record the core keeps itself, by table and key (an account's `/v1/me`).
  record(table: string, key: string): unknown {
    return structuredCloneOrSelf(this.#records.get(table)?.get(key));
  }

  put(table: string, key: string, value: unknown): void {
    const t = this.#table(table);
    if (t.has(key) && equal(t.get(key), value)) return;
    t.set(key, structuredCloneOrSelf(value));
    this.#write([{ put: { table, key, value: toJsonBytes(value) } }]);
  }

  /// Every record of a table, by key, in key order.
  records(table: string): [string, unknown][] {
    const t = this.#records.get(table);
    if (!t) return [];
    return [...t.keys()].sort(compareKeys).map((k) => [k, structuredCloneOrSelf(t.get(k))]);
  }

  /// Keeps only the stations `keep` picks and, where given, the `workspaces`.
  retain(keep: (station: string) => boolean, workspaces: Set<string> | null): void {
    const stationOf = (table: string, key: string): string | null => {
      const at = key.indexOf(SEP);
      switch (table) {
        case "overview":
          return key;
        case "list":
          return at >= 0 ? key.slice(at + 1) : null;
        case "session":
        case "row":
        case "session_summary":
        case "thread":
          return at >= 0 ? key.slice(0, at) : null;
        default:
          return null;
      }
    };
    this.#forget((table, key) => {
      if (table === "workspace") return workspaces !== null && !workspaces.has(key);
      const station = stationOf(table, key);
      return station !== null && !keep(station);
    });
  }

  /// A held topic known no more (a draft sent or emptied).
  forgetTopic(topic: Topic): void {
    const s = shape(topic);
    if (!s || !("one" in s)) return;
    const { table, key } = s.one;
    this.#soon.delete(`${table}${SEP}${key}`);
    const t = this.#records.get(table);
    if (t?.delete(key)) {
      this.#write([{ delete: { table, key } }]);
      this.#tell(topic);
    }
  }

  forgetRecord(table: string, key: string): void {
    this.#forget((t, k) => t === table && k === key);
  }

  #forget(doomed: (table: string, key: string) => boolean): void {
    const gone: [string, string][] = [];
    for (const table of [...this.#records.keys()].sort(compareKeys)) {
      for (const key of [...this.#records.get(table)!.keys()].sort(compareKeys)) if (doomed(table, key)) gone.push([table, key]);
    }
    if (gone.length === 0) return;
    for (const [table, key] of gone) this.#records.get(table)!.delete(key);
    this.#write(gone.map(([table, key]) => ({ delete: { table, key } })));
    this.#tellAll();
  }

  #tell(topic: Topic): void {
    this.#changed?.(topic);
  }

  /// Every topic the records may be of changed (loaded, or forgotten in bulk).
  #tellAll(): void {
    const topics = new Map<string, Topic>();
    for (const [table, rows] of this.#records) {
      for (const key of rows.keys()) {
        const topic = topicOf(table, key);
        if (topic) topics.set(JSON.stringify(topic), topic);
      }
    }
    for (const topic of topics.values()) this.#tell(topic);
  }

  /// Queues a batch after those before it.
  #write(ops: DbOp[]): void {
    const previous = this.#tail;
    this.#tail = previous.then(() => this.#host.dbWrite(ops)).catch(() => undefined);
  }

  /// Resolves once every write asked for so far is done.
  written(): Promise<void> {
    return this.#tail;
  }
}

/// The topic a record is (part) of.
function topicOf(table: string, key: string): Topic | null {
  const at = key.indexOf(SEP);
  const station = at >= 0 ? key.slice(0, at) : null;
  switch (table) {
    case "workspace":
      return { topic: "workspace", workspace: key };
    case "overview":
      return { topic: "overview", station: key };
    case "session":
      return at >= 0 ? { topic: "session", station: key.slice(0, at), key: key.slice(at + 1) } : null;
    case "row":
      return station !== null ? { topic: "chatRows", station } : null;
    case "session_summary":
      return station !== null ? { topic: "sessions", station } : null;
    case "thread":
      return station !== null ? { topic: "threads", station } : null;
    case "list": {
      if (at < 0) return null;
      const t = key.slice(0, at);
      const scope = key.slice(at + 1);
      if (t === "row") return { topic: "chatRows", station: scope };
      if (t === "session_summary") return { topic: "sessions", station: scope };
      if (t === "thread") return { topic: "threads", station: scope };
      return null;
    }
    default:
      return null;
  }
}

function structuredCloneOrSelf<T>(v: T): T {
  return v === undefined || v === null || typeof v !== "object" ? v : structuredClone(v);
}
