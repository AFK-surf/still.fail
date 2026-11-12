// The workspace's accounts' rows kept beside each station's overview part (db/kept.ts KEPT.profileRow, views.ts
// profileRowKey), as a chat list's rows are beside their records (list-rows.test.ts; what every value kept so is held
// to is test/kept.test.ts's): what `profiles`' first answer
// costs a core started anew on the workspace of real size (real-size.ts), as a workspace switched to answers it,
// counted, not timed. Each station's profiles were decorated as the list was asked (10.7 ms of its 14.6 after a switch
// on 小屏 in Hermes on a Mac Studio, 2026-11-12); its rows are made as its part is written, kept under the key of what
// else they are made with, and the list merges them across stations as it reads them, its windows' refills said then.
import assert from "node:assert/strict";
import { test } from "node:test";
import { textKey } from "../src/conform.ts";
import { dbName, holds } from "../src/data.ts";
import { holdLanguage, setCurrent } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import type { FakeHost } from "../src/testing.ts";
import { KEPT } from "../src/db/kept.ts";
import { work, workSince, type Work } from "../src/work.ts";
import { held } from "./real-size-asked.ts";
import { OPENS, UP, fixture, quotaChanged } from "./real-size.ts";
import { link, setup, ui, workspace } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

/// The list as 小屏's Profile place and 大屏's sidebar ask it.
const LIST: Topic = { topic: "profiles", scope: "ws" };

/// The rows of every station of the workspace as the list makes them in each language, and their digest (conform.ts
/// textKey): another whenever rows are made otherwise, when KEPT.profileRow.making is to be raised with it.
const MADE: Record<number, string> = { 1: "59171.hbc9kt.12hrkze" };

/// The real-size workspace written to a database as a core holds it, the core then stopped; its host, and when.
async function written(): Promise<{ host: FakeHost; base: number }> {
  const { t, base } = await held(false);
  t.store.runner.shutdown();
  return { host: t.host, base };
}

/// The list's first answer of a core started anew on `host`'s database (as a workspace switched to asks it): its value
/// as it went out, what its first answer took (`first`) and all it took till it was quiet (`made`).
async function listAnew(host: FakeHost, base: number, also: Topic[] = []) {
  const before = { ...work };
  const t = setup({ all: true, host });
  let first = null as Work | null;
  const told = t.router.opened.bind(t.router);
  t.router.opened = (topic) => {
    if (topic.topic === "profiles" && first === null) first = workSince(before);
    told(topic);
  };
  const u = ui();
  t.subscribe(1, LIST);
  for (const [topic, value] of fixture(base, OPENS)) if (!holds(topic)) t.set(topic, value);
  await t.read(u, 1);
  // (what it made as its stations' parts came, kept beside them before the core stops)
  await t.host.time.pass(100);
  await t.read(u, 1);
  const made = workSince(before);
  const others: J[] = [];
  for (const [i, topic] of also.entries()) {
    const o = ui();
    t.subscribe(10 + i, topic);
    await t.read(o, 10 + i);
    others.push(o.value);
  }
  return { t, value: u.value, text: JSON.stringify(u.value), first: first!, made, others };
}

const sqlOf = (host: FakeHost) => host.sqls.get(dbName("s1"))!;
const stationsOf = (t: ReturnType<typeof setup>) => (t.views.stations("ws") as J[]).map((s) => s.address as string);

test("a_switched_to_workspace_answers_its_accounts_of_rows_kept_beside_their_parts_decorating_none", async () => {
  const { host, base } = await written();
  // (rows not kept as their parts were written are kept as the list first made them)
  const warm = await listAnew(host, base);
  warm.t.store.runner.shutdown();
  const kept = await listAnew(host, base);
  const n = stationsOf(kept.t).length;
  kept.t.store.runner.shutdown();
  assert.ok(kept.value.items.length > 0);
  assert.equal(kept.made.profiledParts, 0, "no station's part decorated for the list");
  assert.equal(kept.made.profileRows, 0, "no rows made");
  assert.equal(kept.made.overviewsRead, 0, "no station's whole overview read");
  assert.equal(kept.made.profileRowKept, n, "each station's rows taken as kept");
  assert.equal(kept.made.wholeShaped, 0, "nothing copied, decorated or shaped whole as it went out");
  assert.equal(kept.text, warm.text);
});

test("rows_made_otherwise_are_kept_by_another_key_and_a_station_renamed_or_down_changes_only_the_merge", async () => {
  const { host, base } = await written();
  const all = fixture(base, OPENS);
  const ws = all.find(([topic]) => topic.topic === "workspace")![1] as J;
  const rowsOf = (t: ReturnType<typeof setup>) => new Map(stationsOf(t).map((s) => [s, t.views.profileRowsNow(s)]));
  const was = await listAnew(host, base);
  const before = rowsOf(was.t);
  was.t.store.runner.shutdown();
  // What the rows are made with: each made otherwise, its rows come out otherwise under another key.
  {
    setCurrent("en");
    const t = setup({ all: true, host });
    try {
      await t.host.time.pass(100);
      for (const [s, now] of rowsOf(t)) {
        if (now === null) continue;
        assert.notEqual(JSON.stringify(now.rows), JSON.stringify(before.get(s)!.rows), `language: ${s}'s rows the same`);
        assert.notEqual(now.key, before.get(s)!.key, `language: ${s}'s rows made otherwise under the same key`);
      }
    } finally {
      setCurrent("zh");
      t.store.runner.shutdown();
    }
  }
  // What is the merge's: a station renamed, one gone down. No row made, none other; what the list sends, otherwise.
  const changes: { name: string; apply: (t: ReturnType<typeof setup>) => void }[] = [
    { name: "station renamed", apply: (t) => t.set(workspace(), { ...ws, stations: ws.stations.map((s: J) => ({ ...s, name: `${s.name}·` })) }) },
    { name: "station down", apply: (t) => t.set(link(UP[0]), { state: "offline", message: "连不上", last: "offline" }) },
  ];
  for (const change of changes) {
    const { host: h, base: b } = await written();
    const first = await listAnew(h, b);
    first.t.store.runner.shutdown();
    const t = setup({ all: true, host: h });
    try {
      const u = ui();
      t.subscribe(1, LIST);
      for (const [topic, value] of fixture(b, OPENS)) if (!holds(topic)) t.set(topic, value);
      await t.read(u, 1);
      const sentBefore = JSON.stringify(u.value);
      const rowsBefore = rowsOf(t);
      const w = { ...work };
      change.apply(t);
      await t.read(u, 1);
      const spent = workSince(w);
      assert.deepEqual([spent.profileRows, spent.profileRowWritten, spent.profiledParts], [0, 0, 0], `${change.name}: no row made`);
      for (const [s, now] of rowsOf(t)) assert.deepEqual(now, rowsBefore.get(s), `${change.name}: ${s}'s rows otherwise`);
      assert.notEqual(JSON.stringify(u.value), sentBefore, `${change.name}: the list says it`);
    } finally {
      t.store.runner.shutdown();
    }
  }
});

test("accounts_of_kept_rows_go_out_as_made_at_read_byte_for_byte_in_each_language_and_as_the_clock_moves", async () => {
  for (const lang of ["zh", "en"] as const) {
    setCurrent(lang);
    try {
      const { host, base } = await written();
      const warm = await listAnew(host, base);
      warm.t.store.runner.shutdown();
      const kept = await listAnew(host, base);
      kept.t.store.runner.shutdown();
      assert.equal(kept.made.profileRows, 0, `${lang}: no rows made`);
      // made at read, no row kept: the same as from kept rows
      sqlOf(host).exec("DELETE FROM profile_row");
      const made = await listAnew(host, base);
      made.t.store.runner.shutdown();
      assert.ok(made.made.profileRows > 0, `${lang}: its rows made, none kept`);
      assert.equal(kept.text, made.text, `${lang}: as made`);
      assert.equal(warm.text, made.text);
      // the clock a minute on: its windows' refills said again, nothing else, no row made
      const again = await listAnew(host, base);
      assert.equal(again.made.profileRows, 0, `${lang}: the rows made at read were kept`);
      // (the minute clock, as the core runs it: times in words fresh each minute while shown)
      again.t.store.setClock();
      const u = ui();
      again.t.subscribe(2, LIST);
      await again.t.read(u, 2);
      // (the rows: what the machines' logins offered beside say of their allowances' times as it is shown)
      const at = JSON.stringify(u.value.items);
      const w = { ...work };
      await again.t.host.time.pass(61_000);
      await again.t.read(u, 2);
      const moved = workSince(w);
      const later = JSON.stringify(u.value.items);
      again.t.store.runner.shutdown();
      assert.deepEqual([moved.profileRows, moved.profileRowWritten, moved.profiledParts], [0, 0, 0], `${lang}: no row made as the clock moved`);
      const refills = (v: string) => v.replace(/"refills":(null|"[^"]*")/g, '"refills":_');
      assert.notEqual(later, at, `${lang}: a refill said otherwise a minute on`);
      assert.equal(refills(later), refills(at), `${lang}: nothing but refills changed`);
    } finally {
      setCurrent("zh");
    }
  }
});

test("an_accounts_page_usage_and_fleet_answer_after_a_switch_where_only_rows_were_read", async () => {
  const { host, base } = await written();
  const warm = await listAnew(host, base);
  const entry = warm.value.items.find((e: J) => e.several === true) ?? warm.value.items[0];
  warm.t.store.runner.shutdown();
  const asked: Topic[] = [
    { topic: "profile", scope: "ws", key: entry.key },
    { topic: "usage", scope: "ws", days: 7 },
    { topic: "fleet", scope: "ws" },
  ];
  const after = await listAnew(host, base, asked);
  after.t.store.runner.shutdown();
  assert.equal(after.first.profiledParts, 0, "the list's first answer decorated no part");
  const [profile, usage, fleet] = after.others;
  assert.equal(profile.key, entry.key, "the account whole, by its key");
  assert.ok(Array.isArray(profile.members) && profile.members.length > 0, "with its members");
  assert.ok(Array.isArray(usage.lists), "usage answers");
  assert.ok(fleet !== undefined, "fleet answers");
});

test("rows_are_made_as_profile_row_making_says", async () => {
  // A change to how rows are made (its maker, a word of theirs, a shape they are made through) changes this digest:
  // raise KEPT.profileRow.making with it, so that no rows a core made before are taken as kept by this one.
  const { host } = await written();
  const out: string[] = [];
  for (const lang of ["zh", "en"] as const) {
    setCurrent(lang);
    const t = setup({ all: true, host });
    try {
      await t.host.time.pass(100);
      for (const s of stationsOf(t).sort()) out.push(`${lang} ${s} ${JSON.stringify(t.views.profileRowsNow(s)?.rows ?? null)}`);
    } finally {
      setCurrent("zh");
      t.store.runner.shutdown();
    }
  }
  const digest = textKey(out.join("\n"));
  assert.equal(digest, MADE[KEPT.profileRow.making], `rows made otherwise (${digest}): raise KEPT.profileRow.making and write the digest in MADE`);
});
