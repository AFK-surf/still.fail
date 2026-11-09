// The MoonBit checker of the kept statistics' coverage (station/mb, src/usage) answers as the minute worker does: in
// the same states of the minutes, remote tasks, details and chat statistics, for the same viewers, the same answers.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Store } from "../src/store/store.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";

const binary = mbReaderBinary();

/// What each reader answers to every kind of ask, for every viewer: "ok" or its error.
async function answers(reader: MinuteReader): Promise<string[]> {
  const viewers = [null, { workspace: "A", home: false }, { workspace: "A", home: true }, { workspace: "B", home: false }];
  const out: string[] = [];
  const said = (p: Promise<void>) => p.then(() => "ok", (e: Error) => e.message);
  for (const v of viewers) out.push(await said(reader.ready(v)), await said(reader.readyDetail(v)), await said(reader.readyChats(v)));
  out.push(await said(reader.readyRemote()));
  return out;
}

/// The states: fresh (every statistic complete), then each made incomplete in turn, for a workspace or for all.
const states: [string, string][] = [
  ["fresh", ""],
  ["minutes not filled", "UPDATE usage_minute_all SET done = 0"],
  ["remote tasks not filled", "UPDATE remote_run_progress SET done = 0"],
  ["details not filled", "UPDATE usage_detail_all SET done = 0"],
  ["details ready for A", "UPDATE usage_detail_all SET done = 0; INSERT INTO usage_detail_ready(ws) VALUES ('A')"],
  ["chats not filled", "UPDATE usage_chat_progress SET done = 0"],
  // (with the minutes not filled too, so that the checker is asked rather than all being complete)
  ["a session of A moved", "UPDATE usage_minute_all SET done = 0; INSERT INTO usage_chat_dirty_scope(session, kind, ws) VALUES ('s', 2, 'A')"],
  ["a home session moved", "UPDATE usage_minute_all SET done = 0; INSERT INTO usage_chat_dirty_scope(session, kind, ws) VALUES ('s', 1, '')"],
  ["card outcomes incomplete", "CREATE TABLE card_outcomes_incomplete (x)"],
  ["usage retired", "CREATE TABLE usage_retired_detail (x)"],
];

for (const [name, sql] of states) {
  test(`the MoonBit checker answers as the minute worker: ${name}`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const dir = mkdtempSync(join(tmpdir(), "mb-usage-check-"));
    const path = join(dir, "stillfail.db");
    const store = Store.open(path, join(dir, "archive"));
    if (sql) store.db.exec(sql);
    const worker = new MinuteReader(path, {}, null), moonbit = new MinuteReader(path, {}, binary);
    try {
      const theirs = await answers(worker);
      assert.deepEqual(await answers(moonbit), theirs);
      // (each state is one a reader tells apart: fresh is all complete, the others are not)
      assert.equal(theirs.every((a) => a === "ok"), name === "fresh", JSON.stringify(theirs));
    } finally {
      await worker.close(); await moonbit.close();
      store.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
