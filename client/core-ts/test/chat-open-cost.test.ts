// What a chat's first answer costs a core started anew on the workspace of real size (real-size.ts), as a workspace
// switched to on 大屏 lands on it (apps/mbui/core/wsswitch.m, scripts/core.sh ws-switch): counted, not timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dbName, holds } from "../src/data.ts";
import { overviewPartOf, overviewRowOf } from "../src/db/schema.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import type { Sql } from "../src/host.ts";
import type { FakeHost } from "../src/testing.ts";
import { work, workSince } from "../src/work.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { held } from "./real-size-asked.ts";
import { CHAT, OPENS, fixture } from "./real-size.ts";
import { base as answersOf, entries, started, status, threadView } from "./station-fixture.ts";
import { Core } from "../src/core.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { HostWire } from "../src/station/wire.ts";
import { setup, ui } from "./views-rig.ts";

holdLanguage();

/// The chat as 大屏's pane asks it (sfbase core_topic_params: compact).
const CHAT_TOPIC: Topic = { topic: "chat", station: CHAT.station, thread: CHAT.thread, session: null, compact: true };

/// The real-size workspace written to a database as a core holds it, the core then stopped; its host, and when.
async function written(): Promise<{ host: FakeHost; base: number }> {
  const { t, base } = await held(false);
  t.store.runner.shutdown();
  return { host: t.host, base };
}

/// The chat's first answer of a core started anew on `host`'s database (what is not kept there given again, as its
/// station's topics give it), and what making it took.
async function chatAnew(host: FakeHost, base: number) {
  const before = { ...work };
  const t = setup({ all: true, host });
  const u = ui();
  t.subscribe(1, CHAT_TOPIC);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  const made = workSince(before);
  t.store.runner.shutdown();
  return { value: u.value, made };
}

test("a_core_started_anew_opens_a_chat_reading_and_decorating_no_overview", async () => {
  // Its agents' accounts and connects, who the viewer is in Slack, its station's updates and context were read of its
  // station's whole overview (25-27 KB), and of every other station's for a linked chat's `copies`: 5 overviews read
  // and parsed for its first answer (2.13 ms of its agents' 3.5 in Hermes, of the one not held yet). What it reads of
  // them is kept beside each as it is written (station_part.chat).
  const { host, base } = await written();
  const { value, made } = await chatAnew(host, base);
  assert.equal(made.overviewsRead, 0, "no overview read");
  assert.equal(made.overviews, 0, "no overview decorated");
  assert.equal(value.messages.length, OPENS);
});

/// What the chat reads of its own station's overview, in characters: its chat part and the profiles its agents run on.
function ownReads(sql: Sql): number {
  const chat = String(sql.all("SELECT chat FROM station_part WHERE address = ?", [CHAT.station])[0]![0]).length;
  const ids = new Set(CHAT.keys.flatMap((key) => {
    const r = sql.all("SELECT coalesce(json_extract(detail, '$.session.profile'), json_extract(summary, '$.profile')) FROM session WHERE station = ? AND key = ?", [CHAT.station, key])[0];
    return typeof r?.[0] === "string" ? [r[0]] : [];
  }));
  const profiles = [...ids].reduce((n, id) => n + String(sql.all("SELECT profiles -> ? FROM station_part WHERE address = ?", [`$.${JSON.stringify(id)}`, CHAT.station])[0]?.[0] ?? "").length, 0);
  return chat + profiles;
}

test("a_chats_agents_read_of_their_stations_profiles_those_they_run_on_alone", async () => {
  // A chat's part held its station's every profile (13 KB of its 17), read and parsed for its one or two agents' own:
  // what its page shows of an agent's account is the profile it runs on. Each is read alone, by its id.
  const { host, base } = await written();
  const sql = host.sqls.get(dbName("s1"))!;
  const chat = String(sql.all("SELECT chat FROM station_part WHERE address = ?", [CHAT.station])[0]![0]);
  assert.ok(!chat.includes('"profiles"'), "the chat's part holds no profile");
  const whole = String(sql.all("SELECT profiles FROM station_part WHERE address = ?", [CHAT.station])[0]![0]).length;
  const own = ownReads(sql);
  const { value, made } = await chatAnew(host, base);
  assert.ok(value.agents.length > 0 && value.agents.every((a: { profile?: { name?: string } }) => typeof a.profile?.name === "string"));
  assert.ok(own - chat.length < whole / 2, `its agents' profiles ${own - chat.length} of ${whole} characters`);
  assert.ok(made.overviewPartChars <= own + 5 * 16, `${made.overviewPartChars} characters read of parts, its own ${own}`);
});

test("a_chat_with_links_reads_of_each_other_station_what_a_link_is_taken_to_alone", async () => {
  // Where a link to a chat goes (views.ts stationNow) read each other station's `copies.formerly` out of its chat's
  // part: 4 parts of some 17 KB parsed for a few bytes (82.7 KB in Hermes with its own). They are kept apart
  // (station_part.formerly): its own station's chat part, and a few bytes of each other's.
  const { host, base } = await written();
  const sql = host.sqls.get(dbName("s1"))!;
  const own = ownReads(sql);
  const { value, made } = await chatAnew(host, base);
  assert.ok(value.messages.some((m: { text?: string }) => (m.text ?? "").includes("still.fail/o/")), "it has links to chats");
  assert.equal(made.overviewsRead, 0);
  assert.ok(made.overviewPartChars - own <= 5 * 16, `${made.overviewPartChars - own} characters of parts besides its own station's`);
});

test("a_chats_first_answer_waits_for_what_it_is_made_of_alone", async () => {
  // Its sources were worked out twice before its first value (as it started, then as it was made), each looking
  // through all its messages for the chats they link to, whose stations' lists it watches to keep them current:
  // 2.3-5.5 ms in Hermes before a chat switched to could go out. Those lists are watched once it has gone out.
  const { host, base } = await written();
  const t = setup({ all: true, host });
  let atFirst: typeof work | null = null;
  const before = { ...work };
  const told = t.router.opened.bind(t.router);
  t.router.opened = (topic) => {
    if (topic.topic === "chat" && atFirst === null) atFirst = workSince(before);
    told(topic);
  };
  const u = ui();
  t.subscribe(1, CHAT_TOPIC);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  assert.equal(u.value.messages.length, OPENS);
  assert.equal(atFirst!.linkScans, 0, "no message looked through for links before its first value");
  assert.equal(workSince(before).linkScans, 1, "once after it");
  t.store.runner.shutdown();
});

/// What a core before the chat's part keeps the parts by (schema.ts as #5619 left it): its triggers, made again in
/// place of these, and every part made again of the overviews with them, none with a chat's.
function olderTriggers(): string {
  const put = `INSERT INTO station_part (address, part, row) SELECT new.address, ${overviewPartOf("new.json")}, ${overviewRowOf("new.json")} WHERE json_valid(new.json);`;
  return `
    DROP TRIGGER station_part_put; DROP TRIGGER station_part_set;
    CREATE TRIGGER station_part_put AFTER INSERT ON station WHEN new.kind = 'overview'
      BEGIN
        DELETE FROM station_part WHERE address = new.address;
        ${put}
      END;
    CREATE TRIGGER station_part_set AFTER UPDATE OF json ON station WHEN new.kind = 'overview' AND old.json IS NOT new.json
      BEGIN
        DELETE FROM station_part WHERE address = new.address;
        ${put}
      END;
    DELETE FROM station_part;
    INSERT INTO station_part (address, part, row) SELECT st.address, ${overviewPartOf("st.json")}, ${overviewRowOf("st.json")} FROM station AS st WHERE st.kind = 'overview';
  `;
}

test("a_chat_opens_the_same_on_a_database_from_before_its_part_and_while_a_core_from_before_keeps_the_parts", async () => {
  const { host, base } = await written();
  const kept = await chatAnew(host, base);
  const sql = host.sqls.get(dbName("s1"))!;
  // As a core before the chat's part left it: its triggers, its table without the column (dropped once no trigger
  // reads it).
  sql.exec(olderTriggers());
  sql.exec("ALTER TABLE station_part DROP COLUMN chat");
  // Brought to it as it opens: the column added, the triggers and every part made again, by SQLite.
  const anew = await chatAnew(host, base);
  assert.deepEqual(sql.all("SELECT count(*), count(chat) FROM station_part")[0], [5, 5]);
  assert.ok(String(sql.all("SELECT sql FROM sqlite_master WHERE name = 'station_part_set'")[0]?.[0]).includes("(address, part, row, chat, formerly, profiles, profiled, software)"));
  assert.deepEqual([anew.made.overviewsRead, anew.made.overviews], [0, 0]);
  assert.deepEqual(anew.value, kept.value);
  // A core from before it opening the database meanwhile (a web page still open from before) keeps the parts by its
  // own triggers again, the column left empty: what a chat reads of an overview is made of it by SQLite as it is read.
  const t = setup({ all: true, host });
  sql.exec(olderTriggers());
  assert.deepEqual(sql.all("SELECT count(*), count(chat) FROM station_part")[0], [5, 0]);
  const from = { ...work };
  const u = ui();
  t.subscribe(1, CHAT_TOPIC);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  const made = workSince(from);
  t.store.runner.shutdown();
  assert.deepEqual([made.overviewsRead, made.overviews], [0, 0]);
  assert.deepEqual(u.value, kept.value);
});

test("a_chat_shown_is_not_made_again_as_a_switch_of_workspace_commits_onto_it", async () => {
  // As the app commits a switch of workspace that lands on a chat (apps/mbui/core/wsswitch.m `commit`), it writes the
  // workspace to the prefs and tells the core where its focus is, twice. The chat read the prefs whole, and its UIs'
  // focus with what it was made of: each made it again (3-6 ms in Hermes), the same.
  const { host, core } = await started();
  const client = core.connect();
  const values = new Map();
  const asked = (id: number, topic: Topic) => subscribe(core, client, id, parseTopic(topic)!);
  asked(1, { topic: "chat", station: "ws/st", session: "k1", compact: true });
  await host.settle();
  apply(host, values);
  const shown = JSON.stringify(v(values, 1));
  assert.equal(v(values, 1).messages.length, 3);
  const before = { ...work };
  call(core, client, 2, "prefs.set", { workspace: "w2" });
  call(core, client, 3, "client.focus", { visible: true, focused: true, workspace: "ws" });
  asked(4, { topic: "chatJobs", station: "ws/st", session: "k1", summary: true, compact: true });
  call(core, client, 5, "chat.place", { station: "ws/st", thread: 7 });
  call(core, client, 6, "client.focus", { chat: { station: "ws/st", session: "k1", thread: 7, end: true, seen: 3 } });
  await host.settle();
  assert.equal(workSince(before).chats, 0, "not made again");
  assert.ok(!host.takeEmitted().some(([, m]) => (m as { id?: number }).id === 1), "nothing sent of it");
  // What it is made of changed: made again.
  call(core, client, 7, "prefs.set", { chatTabs: { "ws/st:k1": { tabs: ["jobs"], active: "jobs" } } });
  await host.settle();
  apply(host, values);
  assert.equal(workSince(before).chats, 1);
  assert.notEqual(JSON.stringify(v(values, 1)), shown);
  core.close();
});

test("a_chat_let_go_of_keeping_it_and_asked_again_is_answered_by_what_changed_not_hashed_again", async () => {
  // Back to a workspace within seconds, the app asks its chat again with the version of what it kept (`have`, as it
  // let it go with `keep`: sfbase's topic_kept). The core hashed the chat whole to answer (digest.ts `version`, 4-5 ms
  // in Hermes for a chat of 46 KB, and as much again as it was let go of), though it remembered what the client holds:
  // what changed from that is worked out by its items, and none changed is the same version. Since, its version is a
  // token of the value object (digest.ts `token`): hashed neither as it is let go of nor as it is asked again.
  const { host, core } = await started();
  const client = core.connect();
  const values = new Map();
  const chat = parseTopic({ topic: "chat", station: "ws/st", session: "k1", compact: true })!;
  subscribe(core, client, 1, chat);
  await host.settle();
  apply(host, values);
  const before = { ...work };
  core.receive(client, { kind: "unsubscribe", id: 1, unsubscribe: true, keep: true });
  await host.settle();
  const said = host.takeEmitted().map(([, m]) => m as { id?: number; v?: string }).find((m) => m.id === 1 && typeof m.v === "string");
  assert.ok(said, "its version said as it is let go of");
  core.receive(client, { kind: "subscribe", id: 2, subscribe: chat, keyed: true, have: said!.v! });
  await host.settle();
  const again = host.takeEmitted().map(([, m]) => m as Record<string, unknown>).filter((m) => m.id === 2);
  assert.deepEqual(again[0], { id: 2, same: true });
  assert.equal(workSince(before).versions, 0, "nothing hashed: its token is the value object's (digest.ts token)");
  core.close();
});

test("a_chat_opens_on_as_many_of_its_last_messages_as_its_page_says_its_screen_shows_and_a_screen_more", async () => {
  // A chat opened at its end made and sent its latest page of entries whole, 50 messages (37 KB of its 46 KB on a
  // workspace of real size), of which 大屏 shows four. Its page says how many it opens on (`chat.window`: its screen by
  // the least height of a row it counts, by tens), no part of its topic; it grows by `chat.older` as many as its page
  // asks (a screen kept above what shows).
  const opened = async (rows: number | null, by: "thread" | "session") => {
    const answers = answersOf();
    answers["GET /threads"] = [threadView(7, 120)];
    answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
    answers["GET /threads/7/entries?from=21&to=70"] = { last: 120, entries: entries(21, 70) };
    answers["GET /threads/7/entries?from=1&to=20"] = { last: 120, entries: entries(1, 20) };
    const { host, core } = await started(answers);
    await host.time.pass(500);
    const client = core.connect();
    const values = new Map();
    const said = by === "thread" ? { thread: 7 } : { session: "k1" };
    if (rows !== null) call(core, client, 9, "chat.window", { station: "ws/st", ...said, rows });
    const before = { ...work };
    subscribe(core, client, 1, parseTopic({ topic: "chat", station: "ws/st", ...said, compact: true })!);
    await host.settle();
    const sent = host.takeEmitted().map(([, m]) => m as { id?: number; value?: { messages: unknown[] } }).find((m) => m.id === 1 && m.value !== undefined)!;
    const made = workSince(before);
    const bytes = JSON.stringify(sent.value!.messages).length;
    values.set(1, sent.value);
    const shown = v(values, 1).messages.length;
    call(core, client, 2, "chat.older", { station: "ws/st", thread: 7, ...(rows !== null ? { rows: 20 } : {}) });
    await host.time.pass(100);
    apply(host, values);
    const grown = v(values, 1).messages.length;
    core.close();
    return { shown, grown, bytes, made };
  };
  const untold = await opened(null, "thread");
  assert.deepEqual([untold.shown, untold.grown], [50, 100]);
  const told = await opened(30, "thread");
  assert.deepEqual([untold.made.messages, told.made.messages], [50, 30], "messages made for its first answer");
  assert.deepEqual([told.shown, told.grown], [30, 50], "30 messages, and 20 more as its page asks them, read back");
  assert.ok(told.bytes <= untold.bytes * 0.62, `its messages ${told.bytes} bytes of ${untold.bytes}`);
  // Told by its agent's session, as a chat is asked before its thread is known.
  assert.equal((await opened(30, "session")).shown, 30);
});

test("a_chat_told_its_window_opens_still_at_what_is_unread_and_where_it_was_left_as_wide_as_before", async () => {
  // Where the chat is to be read (its first unread, else where it was left) is the core's, and its window about it wins
  // over the count its page says: its unread line and the place it was left come with what they did before.
  const opened = async (rows: number | null, read: number, unread: number, place: number | null) => {
    const answers = answersOf();
    answers["GET /threads"] = [threadView(7, 120, read, unread)];
    answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
    answers["GET /threads/7/entries?from=21&to=70"] = { last: 120, entries: entries(21, 70) };
    answers["GET /threads/7/entries?from=1&to=20"] = { last: 120, entries: entries(1, 20) };
    const { host, core } = await started(answers);
    await host.time.pass(500);
    const client = core.connect();
    const values = new Map();
    if (place !== null) call(core, client, 8, "chat.place", { station: "ws/st", thread: 7, seq: place });
    if (rows !== null) call(core, client, 9, "chat.window", { station: "ws/st", thread: 7, rows });
    subscribe(core, client, 1, { topic: "thread", station: "ws/st", thread: 7 });
    await host.settle();
    apply(host, values);
    const w = v(values, 1);
    core.close();
    return [w.first, w.last, w.at ?? null];
  };
  assert.deepEqual(await opened(30, 100, 20, null), [51, 120, 101], "at the first unread");
  assert.deepEqual(await opened(30, 100, 20, null), await opened(null, 100, 20, null));
  assert.deepEqual(await opened(30, 120, 0, 40), [1, 89, 40], "where it was left");
  assert.deepEqual(await opened(30, 120, 0, 40), await opened(null, 120, 0, 40));
  assert.deepEqual(await opened(30, 120, 0, null), [91, 120, null], "at its end, the count");
});

test("a_chats_opening_reads_of_its_log_what_its_window_shows_and_a_page_told_grows_by_what_it_is_asked", async () => {
  // Its window found as many of its messages as it was told by reading back 60 entries of its log (max(rows*2, PAGE)),
  // more than the untold page read (50): it reads back a step of `rows` at a time, a further one only while fewer
  // messages were found, and a window grown by `rows` reads those alone, where the device holds them.
  const answers = answersOf();
  answers["GET /threads"] = [threadView(7, 300)];
  answers["GET /threads/7/entries?limit=50"] = { last: 300, entries: entries(251, 300) };
  for (let from = 1; from <= 201; from += 50) answers[`GET /threads/7/entries?from=${from}&to=${from + 49}`] = { last: 300, entries: entries(from, from + 49) };
  const first = await started(answers);
  await first.host.time.pass(500);
  assert.equal(first.core.inner.data.logSpan("entry", "ws/st", "7")?.count, 300);
  await first.core.close();
  // (a core started again on what the device holds, its station not reached: its log read from the database)
  const opened = async (rows: number | null, outline = false) => {
    const core = await Core.create(first.host, { clock: first.host.time.clock, sample: 0, wire: () => new HostWire(first.host) });
    await first.host.time.pass(500);
    const client = core.connect();
    const values = new Map();
    // (its outline, of all the device holds of the chat, not of its window: asked first where it is looked at)
    if (outline) {
      subscribe(core, client, 3, { topic: "chatOutline", station: "ws/st", thread: 7 });
      await first.host.settle();
    }
    const before = { ...work };
    if (rows !== null) call(core, client, 9, "chat.window", { station: "ws/st", thread: 7, rows });
    subscribe(core, client, 1, parseTopic({ topic: "chat", station: "ws/st", thread: 7, compact: true })!);
    await first.host.settle();
    apply(first.host, values);
    const read = workSince(before).logRows;
    const shown = v(values, 1).messages.length;
    const grow = { ...work };
    call(core, client, 2, "chat.older", { station: "ws/st", thread: 7, ...(rows !== null ? { rows: 20 } : {}) });
    await first.host.time.pass(100);
    const outlined = first.host.emitted.filter(([, m]) => (m as { id?: number }).id === 3).length;
    apply(first.host, values);
    const grown = [v(values, 1).messages.length, workSince(grow).logRows];
    await core.close();
    const said = outline ? v(values, 3).count : null;
    return { shown, read, grown, outlined, said };
  };
  for (const k of Object.keys(answers)) if (k.startsWith("GET /threads/7/entries")) answers[k] = status(502, { error: "busy" });
  const untold = await opened(null);
  const told = await opened(30);
  assert.deepEqual([untold.shown, untold.read, untold.grown], [50, 50, [100, 50]]);
  assert.deepEqual([told.shown, told.read, told.grown], [30, 30, [50, 20]], "its log read for what it shows, and for the 20 it grows by");
  // Its outline sent nothing as it grew: what the device holds did not change (views.ts #chatOutline).
  const outlined = await opened(30, true);
  assert.deepEqual([outlined.said, outlined.outlined], [300, 0]);
});

test("a_chat_let_go_of_and_asked_again_untold_opens_on_its_untold_page", async () => {
  // What a chat's page told of its first window is let go of with it (views.ts Views `stop`): asked again with nothing
  // told, it opens as untold.
  const answers = answersOf();
  answers["GET /threads"] = [threadView(7, 120)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  answers["GET /threads/7/entries?from=21&to=70"] = { last: 120, entries: entries(21, 70) };
  answers["GET /threads/7/entries?from=1&to=20"] = { last: 120, entries: entries(1, 20) };
  const { host, core } = await started(answers);
  await host.time.pass(500);
  const client = core.connect();
  const values = new Map();
  const topic = parseTopic({ topic: "chat", station: "ws/st", session: "k1", compact: true })!;
  call(core, client, 9, "chat.window", { station: "ws/st", session: "k1", rows: 30 });
  subscribe(core, client, 1, topic);
  await host.settle();
  apply(host, values);
  const told = v(values, 1).messages.length;
  core.receive(client, { kind: "unsubscribe", id: 1, unsubscribe: true });
  // (let go of by the core once nothing has asked it a while, the chat and then the thread it watched: within it,
  // asked again, it is the same)
  await host.time.pass(3 * EVICT_AFTER_MS, 1000);
  subscribe(core, client, 2, topic);
  await host.settle();
  apply(host, values);
  assert.deepEqual([told, v(values, 2).messages.length], [30, 50]);
  core.close();
});
