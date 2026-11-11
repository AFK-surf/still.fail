// What a chat's first answer costs a core started anew on the workspace of real size (real-size.ts), as a workspace
// switched to on 大屏 lands on it (apps/mbui/core/wsswitch.m, scripts/core.sh ws-switch): counted, not timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dbName, holds } from "../src/data.ts";
import { overviewPartOf, overviewRowOf } from "../src/db/schema.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import type { FakeHost } from "../src/testing.ts";
import { work, workSince } from "../src/work.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { held } from "./real-size-asked.ts";
import { CHAT, OPENS, fixture } from "./real-size.ts";
import { started } from "./station-fixture.ts";
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

test("a_chat_with_links_reads_of_each_other_station_what_a_link_is_taken_to_alone", async () => {
  // Where a link to a chat goes (views.ts stationNow) read each other station's `copies.formerly` out of its chat's
  // part: 4 parts of some 17 KB parsed for a few bytes (82.7 KB in Hermes with its own). They are kept apart
  // (station_part.formerly): its own station's chat part, and a few bytes of each other's.
  const { host, base } = await written();
  const sql = host.sqls.get(dbName("s1"))!;
  const own = String(sql.all("SELECT chat FROM station_part WHERE address = ?", [CHAT.station])[0]![0]).length;
  const { value, made } = await chatAnew(host, base);
  assert.ok(value.messages.some((m: { text?: string }) => (m.text ?? "").includes("still.fail/o/")), "it has links to chats");
  assert.equal(made.overviewsRead, 0);
  assert.ok(made.overviewPartChars - own <= 5 * 16, `${made.overviewPartChars - own} characters of parts besides its own station's chat part`);
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
  // As a core before the chat's part left it: its table without the column, its triggers.
  sql.exec("ALTER TABLE station_part DROP COLUMN chat");
  sql.exec(olderTriggers());
  // Brought to it as it opens: the column added, the triggers and every part made again, by SQLite.
  const anew = await chatAnew(host, base);
  assert.deepEqual(sql.all("SELECT count(*), count(chat) FROM station_part")[0], [5, 5]);
  assert.ok(String(sql.all("SELECT sql FROM sqlite_master WHERE name = 'station_part_set'")[0]?.[0]).includes("(address, part, row, chat, formerly)"));
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
  // what changed from that is worked out by its items, and none changed is the same version.
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
  assert.equal(workSince(before).versions, 1, "hashed once, as it was let go of");
  core.close();
});
