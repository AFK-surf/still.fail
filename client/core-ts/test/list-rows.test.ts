// A chat list's rows kept beside their records (db/account.ts `chat_row`, views.ts listRowKey): what the list's first
// answer costs a core started anew on the workspace of real size (real-size.ts), as a workspace switched to answers it
// (apps/mbui/core/wsswitch.m, scripts/core.sh ws-switch): counted, not timed. Its 30 rows were made of their records as
// it was asked (2.75 ms of its 7.5 in Hermes on a Mac Studio, their records read and parsed 1.0 ms more, shaped as they
// went out 0.5 ms, and a young collection 0.45 ms for the 1 MB it allocated, 2026-11-12); a row is made as its record
// is written, and kept beside it under the key of what else it was made with.
import assert from "node:assert/strict";
import { test } from "node:test";
import { textKey } from "../src/conform.ts";
import { dbName, holds } from "../src/data.ts";
import { holdLanguage, setCurrent } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import type { FakeHost } from "../src/testing.ts";
import { LIST_ROW_MAKING } from "../src/views/views.ts";
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
/// digest (conform.ts textKey): another whenever a row is made otherwise, when LIST_ROW_MAKING is to be raised with it.
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

test("a_core_started_anew_answers_its_list_of_rows_kept_beside_their_records", async () => {
  const { host, base } = await written();
  // (the rows not kept as they were written are kept as the list first made them)
  const warm = await listAnew(host, base);
  const kept = await listAnew(host, base);
  assert.equal(rowsOf(kept.value).length, WINDOW);
  assert.equal(kept.first.rowJson, 0, "no record's JSON read");
  assert.equal(kept.first.rows, 0, "no row made");
  assert.equal(kept.first.rowsKept, WINDOW + 1, "its window's rows and one more, as they were kept");
  assert.equal(kept.first.conformed, kept.value.days.length, "no row shaped as it went out: its days alone");
  assert.equal(kept.text, warm.text);
});

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

test("a_record_written_keeps_its_row_made_as_it_is_written_and_the_list_makes_none", async () => {
  const { host, base } = await written();
  await listAnew(host, base);
  const station = UP[0];
  const rows = fixture(base, OPENS).find(([topic]) => topic.topic === "chatRows" && topic.station === station)![1] as J[];
  const changed = rows.map((r, i) => (i === 0 ? { ...r, unread: !r.unread, last: { ...r.last, text: "已经合并，CI 全绿。" } } : r));
  const t = setup({ all: true, host });
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.host.time.pass(100);
  const before = { ...work };
  t.set({ topic: "chatRows", station }, changed);
  await t.host.time.pass(100);
  const wrote = workSince(before);
  t.store.runner.shutdown();
  assert.equal(wrote.rowsWritten, 1, "its row alone, as its record was written");
  const anew = await listAnew(host, base);
  assert.deepEqual([anew.first.rows, anew.first.rowJson], [0, 0]);
  assert.ok(rowsOf(anew.value).some((r: J) => r.last?.preview === "已经合并，CI 全绿。"), "the list says it");
});

test("a_record_no_list_read_is_written_with_no_row_made_and_a_whole_station_written_makes_none", async () => {
  const { host, base } = await written();
  const station = UP[0];
  const sql = sqlOf(host);
  const rows = fixture(base, OPENS).find(([topic]) => topic.topic === "chatRows" && topic.station === station)![1] as J[];
  const flipped = rows.map((r) => ({ ...r, unread: !r.unread }));
  // (as a device that has synced the workspace and shown no list of it yet: what `written` asked, every way the app
  // asks, kept every chat's row, the whole lists' too)
  sql.exec("DELETE FROM chat_row");
  // A station's records all written again before any list read one (as its first sync writes them): no row is made.
  {
    const t = setup({ all: true, host });
    for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
    await t.host.time.pass(100);
    const before = { ...work };
    t.set({ topic: "chatRows", station }, flipped);
    await t.host.time.pass(100);
    const wrote = workSince(before);
    t.store.runner.shutdown();
    assert.deepEqual([wrote.rowsWritten, wrote.rows, wrote.listed], [0, 0, 0], "no list read them: none made as they were written");
    assert.equal(sql.all("SELECT count(*) FROM chat_row")[0]![0], 0);
  }
  // A list read its window: those are kept, and a record outside it written makes no row still.
  const warm = await listAnew(host, base);
  const shown = new Set(rowsOf(warm.value).filter((r: J) => r.station === station).map((r: J) => r.id));
  const kept = new Set(sql.all("SELECT id FROM chat_row WHERE station = ?", [station]).map((r) => String(r[0])));
  const out = flipped.find((r) => !kept.has(String(r.id)))!;
  const inside = flipped.find((r) => shown.has(String(r.id)))!;
  assert.ok(out !== undefined && inside !== undefined, "the station has a chat the list showed and one it did not");
  const t = setup({ all: true, host });
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.host.time.pass(100);
  const before = { ...work };
  t.set({ topic: "chatRows", station }, flipped.map((r) => (r === out || r === inside ? { ...r, unread: !r.unread } : r)));
  await t.host.time.pass(100);
  const wrote = workSince(before);
  t.store.runner.shutdown();
  assert.equal(wrote.rowsWritten, 1, "the one the list showed, not the one it did not");
  assert.equal(sql.all("SELECT count(*) FROM chat_row WHERE station = ? AND id = ?", [station, String(out.id)])[0]![0], 0);
  assert.equal(sql.all("SELECT count(*) FROM chat_row WHERE station = ? AND id = ?", [station, String(inside.id)])[0]![0], 1);
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
  assert.deepEqual([anew.first.rows, anew.first.rowJson, anew.first.rowsKept], [1, 1, WINDOW]);
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
    const maker = db.listRows!;
    keys.set(station, maker.key(station));
    for (const [, record] of db.chatHead([station], 10_000)) {
      const made = maker.make(station, record);
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
  // LIST_ROW_MAKING with it, so that no row a core made before is taken as kept by this one, and write the digest here.
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
  assert.equal(digest, MADE[LIST_ROW_MAKING], `rows are made otherwise than LIST_ROW_MAKING ${LIST_ROW_MAKING} says (${digest}): raise it and write the digest`);
});
