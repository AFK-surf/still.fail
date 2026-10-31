// A reader update must not make an already-kept chat parse its messages while opening.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Core } from "../src/core.ts";
import { ensureMdKept } from "../src/db/schema.ts";
import { MD_READING, mdKey, parse, readAfresh } from "../src/markdown.ts";
import { AHEAD_AFTER_MS } from "../src/md-ahead.ts";
import { HostWire } from "../src/station/wire.ts";
import { subscribe } from "./helpers.ts";
import { base, entry, started, stationLater } from "./station-fixture.ts";

test("an_existing_chat_opens_without_reading_its_markdown_after_a_reader_update", async () => {
  const answers = { ...base(), "GET /threads/7/entries?limit=50": { last: 1, entries: [entry(1, "old placeholder")] } };
  const { host, core } = await started(answers);
  await core.close();

  // Pretend another version had received and read this message. Its text has never been parsed in this process.
  const text = `**旧消息。**后面 ${Math.random()}`;
  const old = JSON.stringify([["p", [text]]]);
  const key = mdKey(text).replace(/^\d+\./, "1.");
  let written = false;
  for (const sql of host.sqls.values()) {
    if (sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'entry'").length === 0) continue;
    if (sql.all("SELECT 1 FROM entry WHERE station = ? AND thread = ? AND n = ?", ["ws/st", 7, 1]).length === 0) continue;
    sql.run("UPDATE entry SET json = ? WHERE station = ? AND thread = ? AND n = ?", [JSON.stringify({ ...entry(1, text), authorKind: "agent", author: "k1" }), "ws/st", 7, 1]);
    ensureMdKept(sql);
    sql.run("INSERT INTO md_kept (station, key, of, size, used, json) VALUES (?, ?, ?, ?, ?, ?)", ["ws/st", key, "t:7", old.length, 1, old]);
    written = true;
  }
  assert.ok(written, "a chat and its old reading are already on the device");
  stationLater(host, () => new Promise(() => {}));
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  try {
    const before = readAfresh.chars;
    let readAtFirstView: number | undefined;
    const emit = host.emit.bind(host);
    host.emit = (client, message) => {
      if ("id" in message && message.id === 1 && "value" in message && readAtFirstView === undefined) readAtFirstView = readAfresh.chars - before;
      emit(client, message);
    };
    const ui = again.connect();
    subscribe(again, ui, 1, { topic: "chat", station: "ws/st", thread: 7, session: null });
    await host.time.pass(100, 10);
    assert.equal(readAtFirstView, 0, "the chat goes out before its old messages are read again");
    const cached = [...host.sqls.values()].flatMap((sql) => {
      if (sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'md_kept'").length === 0) return [];
      return sql.all("SELECT json FROM md_kept WHERE station = ? AND key = ?", ["ws/st", mdKey(text)]);
    });
    assert.deepEqual(JSON.parse(String(cached[0]?.[0])), parse(text), "the current reading is kept in the background");
    const second = again.connect();
    subscribe(again, second, 2, { topic: "chat", station: "ws/st", thread: 7, session: null });
    await host.time.pass(100, 10);
    const value = host.takeEmitted().map(([, m]) => m as any).find((m) => m.id === 2 && "value" in m)?.value;
    assert.deepEqual(value?.messages?.find((m: any) => m.seq === 1)?.md, parse(text), "the open chat is updated after the reading changes");
  } finally {
    await again.close();
  }
});

test("older_cached_trees_are_read_ahead_even_for_old_entries_and_transcripts", async () => {
  const { host, core } = await started();
  await core.close();
  const texts = ["**很久以前。**后面", "**较新的消息。**后面", "**执行历史。**后面"];
  const suffix = String(Math.random());
  for (let i = 0; i < texts.length; i++) texts[i] += suffix;
  let written = false;
  for (const sql of host.sqls.values()) {
    if (sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'entry'").length === 0) continue;
    ensureMdKept(sql);
    for (let n = 1; n <= 52; n++) {
      const text = n === 1 ? texts[0]! : n === 52 ? texts[1]! : `未缓存的消息 ${n}`;
      sql.run("INSERT OR REPLACE INTO entry (station, thread, n, json) VALUES (?, ?, ?, ?)", ["ws/st", 7, n, JSON.stringify({ ...entry(n, text), authorKind: "agent", author: "k1" })]);
    }
    sql.run("INSERT OR REPLACE INTO transcript (station, session, i, json) VALUES (?, ?, ?, ?)", ["ws/st", "k1", 1, JSON.stringify({ kind: "thought", text: texts[2] })]);
    for (const [i, text] of texts.entries()) {
      const key = mdKey(text).replace(/^\d+\./, `${[1, 4, MD_READING - 1][i]}.`);
      const old = JSON.stringify([["p", [text]]]);
      sql.run("INSERT INTO md_kept (station, key, of, size, used, json) VALUES (?, ?, ?, ?, ?, ?)", ["ws/st", key, i === 2 ? "s:k1" : "t:7", old.length, 1, old]);
    }
    written = true;
  }
  assert.ok(written);
  stationLater(host, () => new Promise(() => {}));
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  try {
    await host.time.pass(AHEAD_AFTER_MS + 100, 10);
    for (const text of texts) {
      const rows = [...host.sqls.values()].flatMap((sql) => {
        if (sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'md_kept'").length === 0) return [];
        return sql.all("SELECT json FROM md_kept WHERE station = ? AND key = ?", ["ws/st", mdKey(text)]);
      });
      assert.deepEqual(JSON.parse(String(rows[0]?.[0])), parse(text), "a cached tree is updated without opening its chat or history");
    }
  } finally {
    await again.close();
  }
});
