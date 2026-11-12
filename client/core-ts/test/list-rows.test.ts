// A chat list's rows kept beside their records (db/kept.ts KEPT.listRow, views.ts listRowKey): what is the list's own of
// them, on the workspace of real size (real-size.ts), as a workspace switched to answers it (apps/mbui/core/wsswitch.m,
// scripts/core.sh ws-switch), counted, not timed: what it sends of them, the surroundings their key says, their digest.
// What every value kept beside its record is held to (a hit reads no record, a write costs by what was read, the same
// as made now) is test/kept.test.ts's. Its 30 rows were made of their records as
// it was asked (2.75 ms of its 7.5 in Hermes on a Mac Studio, their records read and parsed 1.0 ms more, shaped as they
// went out 0.5 ms, and a young collection 0.45 ms for the 1 MB it allocated, 2026-11-12); a row is made as its record
// is written, and kept beside it under the key of what else it was made with.
import assert from "node:assert/strict";
import { test } from "node:test";
import { textKey } from "../src/conform.ts";
import { dbName, holds } from "../src/data.ts";
import { holdLanguage, setCurrent, t as words } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import type { FakeHost } from "../src/testing.ts";
import { CHAT_READS } from "../src/db/chat-reads.ts";
import { KEPT } from "../src/db/kept.ts";
import { work, workSince, type Work } from "../src/work.ts";
import { held } from "./real-size-asked.ts";
import { OPENS, UP, fixture } from "./real-size.ts";
import { prefs, setup, ui, workspace, type RigOptions } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

/// The list as 小屏's Home and 大屏's sidebar ask it, its window as they tell it (sfbase first_window).
const LIST: Topic = { topic: "chats", scope: "ws", mine: false };
const WINDOW = 30;

/// The rows of every station of the workspace made as a list makes them (#listRow) in each language, and their
/// digest (conform.ts textKey): another whenever a row is made otherwise, when KEPT.listRow.making is to be raised with it.
const MADE: Record<number, string> = { 1: "1594267.1cilsvl.1jt1vru" };

/// The real-size workspace written to a database as a core holds it, the core then stopped; its host, and when.
async function written(): Promise<{ host: FakeHost; base: number }> {
  const { t, base } = await held(false);
  t.store.runner.shutdown();
  return { host: t.host, base };
}

/// The list's first answer of a core started anew on `host`'s database (what is not kept there given again, as its
/// stations' topics give it): its value as it went out, what its first answer took (`first`) and all it took till it
/// was quiet (`made`, its rows kept after it too).
async function listAnew(host: FakeHost, base: number, options: RigOptions = {}) {
  const before = { ...work };
  const t = setup({ all: true, host, ...options });
  let first: Work | null = null;
  const told = t.router.opened.bind(t.router);
  t.router.opened = (topic) => {
    if (topic.topic === "chats" && first === null) first = workSince(before);
    told(topic);
  };
  const u = ui();
  t.window(LIST, WINDOW);
  t.subscribe(1, LIST);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  const made = workSince(before);
  t.store.runner.shutdown();
  assert.ok(first !== null, "the list answered");
  return { value: u.value, text: JSON.stringify(u.value), first: first as Work, made };
}

const rowsOf = (value: J): J[] => value.days.flatMap((d: J) => d.items);
const sqlOf = (host: FakeHost) => host.sqls.get(dbName("s1"))!;

test("a_list_of_kept_rows_goes_out_as_it_is_made_byte_for_byte_in_each_language", async () => {
  for (const lang of ["zh", "en"] as const) {
    setCurrent(lang);
    try {
      const { host, base } = await written();
      const warm = await listAnew(host, base);
      const kept = await listAnew(host, base);
      assert.equal(kept.first.rows, 0, `${lang}: no row made`);
      sqlOf(host).exec("DELETE FROM chat_row");
      const made = await listAnew(host, base);
      assert.equal(made.first.rows, WINDOW, `${lang}: its window's rows made, none kept`);
      assert.equal(kept.text, made.text, `${lang}: as made`);
      assert.equal(warm.text, made.text);
    } finally {
      setCurrent("zh");
    }
  }
});

test("a_record_a_core_from_before_writes_takes_its_row_with_it_and_the_list_makes_that_one_alone", async () => {
  const { host, base } = await written();
  const warm = await listAnew(host, base);
  const sql = sqlOf(host);
  const top = rowsOf(warm.value)[0];
  // (as a core that knows nothing of `chat_row` writes a record: its statement, the triggers on it)
  sql.run("UPDATE chat SET json = json_set(json, '$.last.text', 'CI 挂了，在看。') WHERE station = ? AND archived = 0 AND id = ?", [top.station, top.id]);
  assert.equal(sql.all("SELECT count(*) FROM chat_row WHERE station = ? AND id = ?", [top.station, top.id])[0]![0], 0, "its row went with it");
  const anew = await listAnew(host, base);
  assert.deepEqual([anew.first.rows, anew.first.rowJson, anew.first.listRowKept], [1, 1, WINDOW - 1]);
  assert.equal(rowsOf(anew.value)[0].last.preview, "CI 挂了，在看。");
  const again = await listAnew(host, base);
  assert.deepEqual([again.first.rows, again.first.rowJson], [0, 0], "kept again after it");
});

test("what_else_a_row_is_made_with_changed_its_rows_are_made_again_and_kept_again", async () => {
  const { host, base } = await written();
  await listAnew(host, base);
  // A member renamed: every row's key another.
  const ws = fixture(base, OPENS).find(([topic]) => topic.topic === "workspace")![1] as J;
  const renamed = { ...ws, members: ws.members.map((m: J, i: number) => (i === 0 ? { ...m, name: `${m.name} 2` } : m)) };
  const t = setup({ all: true, host });
  t.set(workspace(), renamed);
  await t.host.time.pass(100);
  t.store.runner.shutdown();
  const anew = await listAnew(host, base);
  assert.equal(anew.first.rows, WINDOW, "made again");
  const again = await listAnew(host, base);
  assert.equal(again.first.rows, 0, "kept again");
  assert.equal(again.text, anew.text);
  // The viewer's archiveHint: the same.
  const p = setup({ all: true, host });
  p.set(prefs(), { archiveHint: "off" });
  await p.host.time.pass(100);
  p.store.runner.shutdown();
  const hinted = await listAnew(host, base);
  assert.equal(hinted.first.rows, WINDOW);
});

test("a_database_from_before_kept_rows_and_one_whose_triggers_a_core_from_before_dropped", async () => {
  const { host, base } = await written();
  const warm = await listAnew(host, base);
  const sql = sqlOf(host);
  // From before: no table, no triggers.
  sql.exec("DROP TRIGGER chat_row_put; DROP TRIGGER chat_row_set; DROP TRIGGER chat_row_drop; DROP TABLE chat_row;");
  const anew = await listAnew(host, base);
  assert.equal(anew.first.rows, WINDOW, "made as it is read");
  assert.equal(anew.text, warm.text);
  const again = await listAnew(host, base);
  assert.deepEqual([again.first.rows, again.first.rowJson], [0, 0], "kept after it, the one read and not made too");
  // Its triggers gone (a core from before made the table `chat` again) and a record written meanwhile: nothing kept is
  // taken, every row made again.
  sql.exec("DROP TRIGGER chat_row_put; DROP TRIGGER chat_row_set; DROP TRIGGER chat_row_drop;");
  const top = rowsOf(warm.value)[0];
  sql.run("UPDATE chat SET json = json_set(json, '$.last.text', '回滚了。') WHERE station = ? AND archived = 0 AND id = ?", [top.station, top.id]);
  const after = await listAnew(host, base);
  assert.equal(after.first.rows, WINDOW);
  assert.equal(rowsOf(after.value)[0].last.preview, "回滚了。");
});

/// Each station's records, as its list reads them; and what the database's maker makes of each (`key`, `rows`).
function madeOf(t: ReturnType<typeof setup>): { keys: Map<string, string | null>; rows: Map<string, string> } {
  const keys = new Map<string, string | null>();
  const rows = new Map<string, string>();
  for (const station of UP) {
    const db = t.data.of(station)!;
    const maker = db.kept.maker(KEPT.listRow)!;
    keys.set(station, maker.key([station]));
    for (const [, record] of db.chatHead([station], 10_000)) {
      const made = maker.make([station, String(record.id)], record);
      rows.set(`${station} ${record.id}`, JSON.stringify(made === null ? null : [made.state, made.whole, made.sent]));
    }
  }
  return { keys, rows };
}

test("a_row_made_otherwise_under_another_of_what_else_it_reads_has_another_key", async () => {
  // Every surrounding a row reads besides its record, each given another value: wherever a row comes out otherwise,
  // its station's key is another (listRowKey): a row taken as kept is the row made now. A surrounding the maker comes
  // to read that the key does not say fails here.
  const { base } = await written();
  const all = fixture(base, OPENS);
  const ws = all.find(([topic]) => topic.topic === "workspace")![1] as J;
  const overviewOf = (st: string) => all.find(([topic]) => topic.topic === "overview" && topic.station === st)![1] as J;
  // (the Slack people its chats name, none of them the viewer: taken as the viewer there)
  const slackPeople = all.filter(([topic]) => topic.topic === "chatRows").flatMap(([, rows]) => (rows as J[]).map((r) => r.creator?.id)).filter((id): id is string => typeof id === "string" && id.startsWith("slack:"));
  type Change = { name: string; options?: RigOptions; apply?: (t: ReturnType<typeof setup>) => void };
  const changes: Change[] = [
    { name: "language", apply: () => setCurrent("en") },
    { name: "viewer", options: { env: () => ({ emailOf: (w: string) => (w === "ws" ? "dana@x.com" : null) }) } },
    { name: "member renamed", apply: (t) => t.set(workspace(), { ...ws, members: ws.members.map((m: J) => ({ ...m, name: `${m.name}·` })) }) },
    { name: "member's picture", apply: (t) => t.set(workspace(), { ...ws, members: ws.members.map((m: J) => ({ ...m, picture: `${m.picture ?? ""}?2` })) }) },
    { name: "station renamed", apply: (t) => t.set(workspace(), { ...ws, stations: ws.stations.map((s: J) => ({ ...s, name: `${s.name}·` })) }) },
    { name: "station's emoji", apply: (t) => t.set(workspace(), { ...ws, stations: ws.stations.map((s: J) => ({ ...s, emoji: "🦊" })) }) },
    { name: "one station", apply: (t) => t.set(workspace(), { ...ws, stations: ws.stations.slice(0, 1) }) },
    { name: "who the viewer is in Slack", apply: (t) => { for (const st of UP) t.set({ topic: "overview", station: st }, { ...overviewOf(st), slackUsers: [...overviewOf(st).slackUsers, ...slackPeople] }); } },
    // (`reviewed` makes these as `done` does: every station of them reviews its chats for archiving)
    { name: "archiveHint off", apply: (t) => t.set(prefs(), { archiveHint: "off" }) },
  ];
  for (const change of changes) {
    // (each on a database of its own, what it changes written there)
    const { host } = await written();
    const base0 = setup({ all: true, host });
    await base0.host.time.pass(100);
    const was = madeOf(base0);
    base0.store.runner.shutdown();
    const t = setup({ all: true, host, ...change.options });
    try {
      change.apply?.(t);
      await t.host.time.pass(100);
      const now = madeOf(t);
      let differ = 0;
      for (const [k, row] of now.rows) {
        if (row === was.rows.get(k)) continue;
        differ++;
        const station = k.split(" ")[0];
        assert.notEqual(now.keys.get(station), was.keys.get(station), `${change.name}: ${k} is made otherwise under the same key`);
      }
      // (a surrounding that changes no row of these would hold nothing: each changes some, not all)
      assert.ok(differ > 0, `${change.name}: some row is made otherwise`);
    } finally {
      setCurrent("zh");
      t.store.runner.shutdown();
    }
  }
});

test("rows_are_made_as_list_row_making_says", async () => {
  // A change to how a row is made (its maker, a word of its, a shape it goes out as) changes this digest: raise
  // KEPT.listRow.making with it, so that no row a core made before is taken as kept by this one, and write the digest here.
  const { host } = await written();
  const out: string[] = [];
  for (const lang of ["zh", "en"] as const) {
    setCurrent(lang);
    const t = setup({ all: true, host });
    try {
      await t.host.time.pass(100);
      out.push(...[...madeOf(t).rows].sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) => `${lang} ${k} ${v}`));
    } finally {
      setCurrent("zh");
      t.store.runner.shutdown();
    }
  }
  const digest = textKey(out.join("\n"));
  assert.equal(digest, MADE[KEPT.listRow.making], `rows are made otherwise than KEPT.listRow.making ${KEPT.listRow.making} says (${digest}): raise it and write the digest`);
});

test("a_pinned_chat_whose_row_was_kept_stays_with_the_pinned_as_the_list_is_made_again", async () => {
  // A row read as kept beside its record is made of its JSON (one the list's first answer did not read, #chats
  // `keptRow`): as the list was made again of rows it made before (a chat pinned or archived here: not quiet), a pinned
  // one's row was taken as it was read, no longer known pinned, and went down among its day's (2026-11-12).
  const { host, base } = await written();
  await listAnew(host, base);
  const t = setup({ all: true, host });
  // The viewer's own first (小屏's 我参与的): the rows of the others, pinned or not, read of the database as the whole
  // list is shown after it, not by its first answer.
  const MINE: Topic = { ...LIST, mine: true };
  const m = ui();
  t.window(MINE, WINDOW);
  t.subscribe(2, MINE);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(m, 2);
  const u = ui();
  t.window(LIST, WINDOW);
  t.subscribe(1, LIST);
  await t.read(u, 1);
  // (the pinned above the days, as their label says: a day's `pinned` goes no further than the core)
  const PINNED = words("core-views.pinned");
  const pinnedOf = (value: J): string[] => (value.days.find((d: J) => d.label === PINNED)?.items ?? []).map((r: J) => `${r.station} ${r.id}`);
  const pinned = pinnedOf(u.value);
  assert.ok(pinned.length > 1, "some pinned");
  // Another pinned here (as `chat.pin` does, views/calls.ts): its station's rows no longer quiet, the list is made again.
  const other = rowsOf(u.value).find((r: J) => !pinned.includes(`${r.station} ${r.id}`) && typeof r.session === "string")!;
  t.views.local.changing(other.station, typeof other.thread === "number" ? other.thread : null, other.session, { pinned: t.host.nowMs() }, null);
  await t.read(u, 1);
  t.store.runner.shutdown();
  assert.deepEqual(pinnedOf(u.value), [`${other.station} ${other.id}`, ...pinned], "the one pinned here first, the pinned before it after it");
  for (const d of u.value.days) if (d.label !== PINNED) assert.ok(d.items.every((r: J) => r.pinned !== true), `no pinned row in ${d.label}`);
});

/// What a list's window of `rows` rows is of the whole list (views.ts firstRows).
function firstOf(whole: J, rows: number): J {
  let left = rows;
  let more = 0;
  const days: J[] = [];
  for (const d of whole.days) {
    if (left <= 0) more += d.items.length;
    else if (d.items.length <= left) days.push(d);
    else {
      days.push({ ...d, items: d.items.slice(0, left) });
      more += d.items.length - left;
    }
    left -= Math.min(left, d.items.length);
  }
  return more === 0 ? whole : { ...whole, days, more };
}

/// The list shown on a core started anew on `host`, its rows kept already: the rig, its page, and the text of what
/// the chat table's statements give back from now on (`texts`: each one longer than a key or a number, by statement).
async function shown(host: FakeHost, base: number) {
  const t = setup({ all: true, host });
  const u = ui();
  t.window(LIST, WINDOW);
  t.subscribe(1, LIST);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  await t.host.time.pass(100);
  const sql = sqlOf(host);
  const all = sql.all.bind(sql);
  const texts: string[] = [];
  sql.all = (q: string, p?: readonly unknown[]) => {
    const r = all(q, p as never);
    if (/\bchat(_row)?\b/.test(q)) for (const row of r) for (const v of row) if (typeof v === "string" && v.length > 120) texts.push(q);
    return r;
  };
  return { t, u, texts, done: () => (delete (sql as J).all, t.store.runner.shutdown()) };
}

test("a_change_of_one_chat_with_the_list_shown_reads_no_rows_text_but_that_chats_own_and_that_from_its_writer", async () => {
  const { host, base } = await written();
  await listAnew(host, base);
  const { t, u, texts, done } = await shown(host, base);
  try {
    const items = rowsOf(u.value);
    // One in the window renamed by its station: its row made as its record is written (db/kept.ts `wrote`), the
    // window's keys read again, no record's JSON nor any row kept beside one read (those held are taken from the cache).
    // (its record as its station's stream gives it: read as the sync reads it, before)
    const top = items[2];
    const record = t.data.chat(top.station, top.id) as J;
    texts.length = 0;
    let before = { ...work };
    t.data.putChat(top.station, { ...record, title: "改了名" });
    await t.read(u, 1);
    assert.equal(rowsOf(u.value)[2].title, "改了名");
    // (its own JSON read by its writer alone, to see whether what it is given is what it holds: account.ts putChat)
    const own = ["SELECT ord, json, unread FROM chat WHERE station = ? AND archived = 0 AND id = ?"];
    assert.deepEqual([workSince(before).rowJson, workSince(before).listRowKept], [1, 0], "no other record's JSON, no kept row read");
    assert.deepEqual(texts, own, "nothing but keys read of the chat table");
    // One far below the window, as its station's stream gives it (its record read as the sync reads it, before): nothing
    // of it shown, nothing read but the window's keys.
    const last = String(sqlOf(host).all("SELECT id FROM chat WHERE station = ? AND archived = 0 ORDER BY last_active LIMIT 1", [UP[1]])[0]![0]);
    const far = t.data.chat(UP[1], last) as J;
    texts.length = 0;
    before = { ...work };
    const was = u.value;
    t.data.putChat(UP[1], { ...far, title: "远处改了名" });
    await t.read(u, 1);
    assert.deepEqual([workSince(before).rowJson, workSince(before).listRowKept, workSince(before).rows], [1, 0, 0]);
    assert.deepEqual(texts, own);
    assert.deepEqual(rowsOf(u.value).map((r: J) => r.id), rowsOf(was).map((r: J) => r.id));
  } finally {
    done();
  }
});

/// The statements of the chat list's database a change ran, by kind: a declared read by its name (db/chat-reads.ts),
/// any other by its first words.
function statementsOf(host: FakeHost): { kinds: () => Record<string, number>; done: () => void } {
  const sql = sqlOf(host) as J;
  const names = new Map(Object.entries(CHAT_READS).map(([name, read]) => [read.sql, name]));
  let kinds: Record<string, number> = {};
  const count = (q: string) => {
    const kind = names.get(q) ?? q.replace(/\s+/g, " ").slice(0, 60);
    kinds[kind] = (kinds[kind] ?? 0) + 1;
  };
  const was = { all: sql.all, run: sql.run, exec: sql.exec };
  for (const m of ["all", "run", "exec"] as const) {
    const f = was[m].bind(sql);
    sql[m] = (q: string, p?: unknown) => (count(q), f(q, p));
  }
  return {
    kinds: () => {
      const out = kinds;
      kinds = {};
      return out;
    },
    done: () => {
      for (const m of ["all", "run", "exec"] as const) delete sql[m];
    },
  };
}

/// What the statements of each of three changes with the list shown are, by kind (statementsOf): a declared read runs
/// only where what it reads of the row changed (chat-reads.ts `by`), the row itself reaching the list by its own key.
const CHANGES: Record<string, Record<string, number>> = {
  "an agent's state": {
    "BEGIN IMMEDIATE": 1,
    "SELECT ord, json, unread FROM chat WHERE station = ? AND arc": 1,
    "SELECT id FROM chat_row WHERE station = ?": 1,
    "INSERT OR REPLACE INTO chat (station, id, archived, ord, thr": 1,
    "INSERT OR REPLACE INTO chat_row (station, id, key, state, wh": 1,
    "INSERT INTO list (station, list, confirmed, rev) VALUES (?, ": 1,
    "COMMIT": 1,
    "counts": 1,
    "SELECT rev FROM list WHERE station = ? AND list = 'chats'": 5
  },
  "a new message on the first chat": {
    "BEGIN IMMEDIATE": 1,
    "SELECT ord, json, unread FROM chat WHERE station = ? AND arc": 1,
    "INSERT OR REPLACE INTO chat (station, id, archived, ord, thr": 1,
    "INSERT OR REPLACE INTO chat_row (station, id, key, state, wh": 1,
    "INSERT INTO list (station, list, confirmed, rev) VALUES (?, ": 1,
    "COMMIT": 1,
    "window": 1,
    "SELECT rev FROM list WHERE station = ? AND list = 'chats'": 5
  },
  "a new message on a chat outside the window": {
    "BEGIN IMMEDIATE": 1,
    "SELECT ord, json, unread FROM chat WHERE station = ? AND arc": 1,
    "SELECT id FROM chat_row WHERE station = ?": 1,
    "INSERT OR REPLACE INTO chat (station, id, archived, ord, thr": 1,
    "INSERT OR REPLACE INTO chat_row (station, id, key, state, wh": 1,
    "INSERT INTO list (station, list, confirmed, rev) VALUES (?, ": 1,
    "COMMIT": 1,
    "window": 1,
    "SELECT rev FROM list WHERE station = ? AND list = 'chats'": 5
  }
};

test("one_chat_changing_with_the_list_shown_runs_the_window_only_where_what_it_reads_of_the_row_changed", async () => {
  const { host, base } = await written();
  await listAnew(host, base);
  const { t, u, done } = await shown(host, base);
  const counted = statementsOf(host);
  const seen: Record<string, Record<string, number>> = {};
  try {
    const items = rowsOf(u.value);
    const change = async (name: string, station: string, id: string, f: (r: J) => J) => {
      const record = t.data.chat(station, id) as J;
      counted.kinds();
      t.data.putChat(station, f(record));
      await t.read(u, 1);
      seen[name] = counted.kinds();
    };
    // An agent's state (its process): the row's place and the list's rows as they were. (The first not pinned: the
    // pinned keep their own order.)
    const top = items.find((r: J) => r.pinned !== true)!;
    const at = items.indexOf(top);
    const ids = items.map((r: J) => r.id);
    await change("an agent's state", top.station, top.id, (r) => ({ ...r, agents: r.agents.map((a: J, i: number) => (i === 0 ? { ...a, process: a.process === "running" ? "cold" : "running" } : a)) }));
    assert.deepEqual(rowsOf(u.value).map((r: J) => r.id), ids);
    // A new message on the chat first already: active later, its place the same.
    await change("a new message on the first chat", top.station, top.id, (r) => ({ ...r, lastActiveAt: t.host.nowMs() + 1000, last: { ...r.last, text: "又一条" } }));
    assert.deepEqual(rowsOf(u.value).map((r: J) => r.id), ids);
    assert.equal(rowsOf(u.value)[at].id, top.id);
    // A new message on a chat outside the window: it comes in first, the last of the window goes.
    const last = String(sqlOf(host).all("SELECT id FROM chat WHERE station = ? AND archived = 0 ORDER BY last_active LIMIT 1", [UP[1]])[0]![0]);
    await change("a new message on a chat outside the window", UP[1], last, (r) => ({ ...r, lastActiveAt: t.host.nowMs() + 2000, last: { ...r.last, text: "新来的" } }));
    assert.equal(rowsOf(u.value)[at].id, last, "it came in first of those not pinned");
    assert.equal(rowsOf(u.value).length, ids.length, "and the last of the window went");
    if (process.env.LIST_ROWS_PRINT) console.log(`const CHANGES: Record<string, Record<string, number>> = ${JSON.stringify(seen, null, 2)};`);
    assert.equal(seen["an agent's state"].window ?? 0, 0, "an agent's state changing ran no window");
    assert.deepEqual(seen, CHANGES);
  } finally {
    counted.done();
    done();
  }
});

test("rows_an_older_core_put_are_derived_again_at_the_next_open_and_every_read_of_them_is_right", async () => {
  const { host, base } = await written();
  const sql = sqlOf(host);
  const station = UP[0];
  const now = base + 3_600_000;
  // As an older core puts a record (its statement: the columns it knows; `made`, `state` and what SQLite derives for
  // this core left as they fall): a chat new on top, one at work taking part as another session; one of the window
  // hidden by its station; one archived now.
  const older = (archived: number, record: J, ord: number) =>
    sql.run(
      "INSERT OR REPLACE INTO chat (station, id, archived, ord, thread, session, client_key, last_active, pinned_at, unread, mine, running, tone, asks, json) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, NULL, 0, 1, 0, NULL, 0, ?)",
      [station, record.id, archived, ord, record.thread ?? null, record.session ?? null, record.lastActiveAt ?? 0, JSON.stringify(record)],
    );
  const records = sql.all("SELECT id, json FROM chat WHERE station = ? AND archived = 0 ORDER BY last_active DESC LIMIT 3", [station]);
  const like = JSON.parse(String(records[0]![1]));
  const one = like.agents[0];
  older(0, { ...like, id: "zz-new", session: "k-zz-new", thread: null, pinned: undefined, hidden: undefined, title: "旧的核心写的", agents: [{ ...one, key: "k-zz-new", process: "cold" }, { ...one, key: "k-zz-agent", process: "running" }], lastActiveAt: now }, -1);
  const hidden = JSON.parse(String(records[1]![1]));
  older(0, { ...hidden, hidden: true }, 0);
  const gone = JSON.parse(String(records[2]![1]));
  sql.run("DELETE FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, gone.id]);
  older(1, { ...gone, archived: { at: now, by: "auto" } }, 0);
  assert.equal(sql.all("SELECT count(*) FROM chat WHERE made IS NULL")[0]![0], 3, "three rows to derive");
  // Opened: those three alone derived again, their JSON read for `state` alone.
  const t = setup({ all: true, host });
  try {
    assert.deepEqual((t.data as J).db("s1").chatColumnsMade, { rows: 3, read: 3, bytes: (t.data as J).db("s1").chatColumnsMade.bytes });
    assert.equal(sql.all("SELECT count(*) FROM chat WHERE made IS NULL")[0]![0], 0);
    const u = ui();
    t.window(LIST, WINDOW);
    t.subscribe(1, LIST);
    for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
    await t.read(u, 1);
    // The window: the new one on top of those not pinned, the hidden one not there; as the list read whole has it, byte
    // for byte.
    const ids = rowsOf(u.value).filter((r: J) => r.pinned !== true).map((r: J) => r.id);
    assert.equal(ids[0], "zz-new");
    const every = rowsOf(u.value).map((r: J) => r.id);
    assert.ok(!every.includes(hidden.id) && !every.includes(gone.id));
    const windowed = t.store.value(LIST) as J;
    // (the list whole, its stations' rows loaded behind its first screen: views.ts #head)
    t.views.chatsWhole("ws");
    await t.host.time.pass(100);
    const whole = t.views.chatsWhole("ws") as J;
    const { days: d1, ...rest1 } = JSON.parse(JSON.stringify(windowed.ok));
    const { days: d2, ...rest2 } = JSON.parse(JSON.stringify(firstOf(whole.ok, WINDOW)));
    assert.deepEqual(rest1, rest2);
    assert.deepEqual(d1, d2);
    assert.equal(JSON.stringify(windowed.ok), JSON.stringify(firstOf(whole.ok, WINDOW)));
    // Its agents' sessions (`chat_agent`, its trigger), its state (the glyph's), its archive.
    assert.equal((t.data.chatOfAgent(station, "k-zz-agent") as J)?.id, "zz-new");
    assert.equal(sql.all("SELECT state FROM chat WHERE station = ? AND id = 'zz-new'", [station])[0]![0], "run");
    const archive = ui();
    t.subscribe(2, { topic: "archive", scope: "ws", limit: 60 });
    await t.read(archive, 2);
    assert.equal(archive.value.days[0].items[0].id, gone.id);
  } finally {
    t.store.runner.shutdown();
  }
});

test("the_columns_sqlite_makes_of_a_record_are_what_the_js_that_read_the_record_says", async () => {
  // schema.ts CHAT_COLUMNS, as the writer puts a record (its statement) and as a row another core put is derived again
  // at the next open: each against the rule the JS that read the record keeps (the list's for `hidden` and the title,
  // archive.ts's for the moment it was archived), for every chat of the workspace of real size, listed and archived,
  // and the odd ones.
  const { host, base } = await written();
  const odd: J[] = [
    { id: "o1" },
    { id: "o2", title: 3, hidden: false },
    { id: "o3", title: "", hidden: 1, archived: "yes" },
    { id: "o4", archived: { at: null }, lastActiveAt: 5 },
    { id: "o5", archived: {}, lastActiveAt: 6.5 },
    { id: "o6", archived: { at: "x" }, lastActiveAt: 7 },
    { id: "o7", archived: { at: 8 }, hidden: true, title: "标题" },
    { id: "o8", archived: { at: null } },
    { id: "o9", archived: [1], hidden: "true" },
    { id: "o10", archived: null, title: null },
  ];
  const sql = sqlOf(host);
  // (as an older core puts them: no column but its own, every one derived at the next open)
  for (const [i, r] of odd.entries()) {
    for (const archived of [0, 1]) sql.run("INSERT OR REPLACE INTO chat (station, id, archived, ord, json) VALUES ('ws/zz-older', ?, ?, ?, ?)", [r.id, archived, i, JSON.stringify(r)]);
  }
  const t = setup({ all: true, host });
  try {
    // (as this core's writer puts them)
    t.set({ topic: "chatRows", station: "ws/zz-written" }, odd);
    t.set({ topic: "archivedRows", station: "ws/zz-written" }, odd);
    await t.host.time.pass(100);
    const rows = sql.all("SELECT station, archived, id, json, hidden, title, archived_mark, archived_at FROM chat");
    assert.ok(rows.length >= 720 + 4 * odd.length, `${rows.length} rows`);
    for (const [station, archived, id, json, hidden, title, mark, at] of rows) {
      const record = JSON.parse(String(json));
      const archivedMark = record.archived !== null && typeof record.archived === "object" && !Array.isArray(record.archived);
      const moment = archivedMark ? (record.archived.at ?? record.lastActiveAt) : undefined;
      assert.deepEqual(
        [hidden, title, mark, at],
        [record.hidden === true ? 1 : 0, typeof record.title === "string" ? record.title : null, archivedMark ? 1 : 0, archivedMark && typeof moment === "number" ? moment : null],
        `${station} ${archived} ${id}: ${json}`,
      );
    }
  } finally {
    t.store.runner.shutdown();
  }
});
