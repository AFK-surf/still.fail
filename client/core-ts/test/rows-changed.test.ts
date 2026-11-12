// A station's chat list is made again only where what it is made of changed, written only where it changed, and
// nothing is read back to find out (rows-made.ts RowsMemo, db/account.ts `setChats`): what is stored is what a core
// started anew makes of the same sessions, threads and marks, whatever came before; and what one change makes the core
// do follows that change, not how many chats the station has.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { worded } from "../src/chat-row.ts";
import { rowWords } from "../src/station/rows-made.ts";
import type { Topic } from "../src/protocol.ts";
import { CAUSES, held } from "./real-size-asked.ts";
import { type Did, GROWING, PROBES, Station, anyChange, anySharedChange, differences, madeAnew, seeded, startedOn, stored } from "./rows-changed-run.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// How many changes of every kind are told, and their seed.
const CHANGES = 300;
const SHARED_CHANGES = 150;
const SEED = 46;

/// The first place what is stored differs from what is made anew, after `what`.
const differ = (s: Parameters<typeof stored>[0], what: string) => differences(stored(s), madeAnew(s)).slice(0, 8).map((d) => `after ${what}: ${d}`);

test("a chat list made of what changed is what a core started anew makes of what is held, change after change", async () => {
  const station = new Station();
  const s = await startedOn(station);
  try {
    assert.ok(stored(s).length >= station.threads.size / 2, `the list was made: ${stored(s).length} rows`);
    assert.deepEqual(differ(s, "everything was read"), []);
    const r = seeded(SEED);
    const told = new Map<string, number>();
    for (let i = 0; i < CHANGES; i++) {
      const kind = anyChange(station, s, r);
      told.set(kind, (told.get(kind) ?? 0) + 1);
      await s.host.time.pass(1500, 100);
      assert.deepEqual(differ(s, `change ${i} (${kind})`), []);
    }
    // (every kind told, more than once)
    assert.ok([...told.values()].every((n) => n > 1) && told.size === 17, JSON.stringify(Object.fromEntries(told)));
  } finally {
    s.core.close();
  }
});

test("a chat list made of the one its station makes for everyone is what a core started anew makes of it, change after change", async () => {
  const station = new Station();
  const s = await startedOn(station, true);
  try {
    assert.ok(s.core.inner.stations.link("ws/st")!.shared, "made of the station's list");
    assert.equal(stored(s).length, station.shared.size);
    assert.deepEqual(differ(s, "everything was read"), []);
    const r = seeded(SEED + 1);
    for (let i = 0; i < SHARED_CHANGES; i++) {
      const kind = anySharedChange(station, s, r);
      await s.host.time.pass(1500, 100);
      assert.deepEqual(differ(s, `change ${i} (${kind})`), []);
    }
  } finally {
    s.core.close();
  }
});

test("a chat list written as given is what was given, after each change of the real-size workspace", async () => {
  const h = await held();
  try {
    const words = rowWords();
    // What each station's lists were last given (its rows in this device's words, each id once), as a core started anew
    // with nothing held would write them.
    const given = new Map<string, J[]>();
    const asGiven = (rows: J[]) => {
      const seen = new Set<string>();
      return rows.flatMap((r) => {
        if (seen.has(r.id)) return [];
        seen.add(r.id);
        const { unread, ...rest } = worded(r, words);
        return [{ id: r.id, json: JSON.stringify(rest), unread: typeof unread === "boolean" ? (unread ? 1 : 0) : null }];
      });
    };
    const set = h.t.set;
    h.t.set = (topic: Topic, value: unknown) => {
      if (topic.topic === "chatRows" || topic.topic === "archivedRows") given.set(`${topic.station} ${topic.topic === "archivedRows" ? 1 : 0}`, asGiven(value as J[]));
      set(topic, value);
    };
    // (as the rig was made: the fixture's)
    const { fixture } = await import("./real-size.ts");
    for (const [topic, value] of fixture(h.base, h.chat)) if (topic.topic === "chatRows" || topic.topic === "archivedRows") given.set(`${topic.station} ${topic.topic === "archivedRows" ? 1 : 0}`, asGiven(value as J[]));
    const check = (what: string) => {
      for (const [key, rows] of given) {
        const [station, archived] = key.split(" ");
        const now = h.t.data.of(station!)!.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = ? ORDER BY ord", [station!, Number(archived)])
          .map((r) => ({ id: String(r[0]), json: String(r[1]), unread: r[2] as number | null }));
        assert.deepEqual(differences(now, rows).slice(0, 8), [], `${station}'s ${archived === "1" ? "archived" : "listed"} chats after ${what}`);
      }
    };
    check("the workspace was set");
    for (const [cause, c] of Object.entries(CAUSES)) {
      c.run(h);
      await h.t.host.time.pass(c.ms ?? 1000, 100);
      check(cause);
    }
  } finally {
    h.t.store.runner.shutdown();
  }
});

/// Each probe measured at a size, in a worker of its own (real-size.ts reads its size as it loads).
function probedAt(realSize: Record<string, number>): Promise<{ chats: number; did: Record<string, Did>; differ: string[] }> {
  return new Promise((resolve, reject) => {
    const w = new Worker(new URL("./rows-changed-run.ts", import.meta.url), { workerData: { rowsChanged: true, realSize } });
    w.once("message", (m) => {
      void w.terminate();
      if ((m as { error?: string }).error !== undefined) reject(new Error((m as { error: string }).error));
      else resolve(m);
    });
    w.once("error", reject);
  });
}

/// The most rows one change of one chat makes again: its own row, once for each step of the change that changes it, two
/// at most (a message: the review's verdict of the chat let go as it is said in, then its thread's summary put; a
/// summary or a rename: it put, then the chat's marks read again). Each of the fixture's agents is in one chat, so no
/// row shares a member with it, and none other is made.
const MOST_MADE = 2;
/// The rows a change writes itself besides those made again: a read finds its chat's row by its thread and writes it
/// read (account.ts #readRows). What is read of the chats' JSON is at most what is serialised: a row given that is not
/// the one written before is read by its key to be compared, the others not at all.
const WRITTEN_ALSO: Record<string, number> = { read: 1 };

test("what one change of one chat makes the core do follows that change, not how many chats there are", async () => {
  const [one, three] = await Promise.all([probedAt({}), probedAt({ chats: 3 })]);
  assert.ok(three.chats >= 2.5 * one.chats, `three times the chats: ${one.chats} → ${three.chats}`);
  console.log(`What each change made the core do (rows made, serialised, taken as written; chat JSON read), at ${one.chats} and ${three.chats} chats:\n${Object.keys(PROBES).map((n) => `  ${n.padEnd(14)} ${JSON.stringify(one.did[n])}  ${JSON.stringify(three.did[n])}`).join("\n")}`);
  assert.deepEqual(one.differ, []);
  assert.deepEqual(three.differ, []);
  for (const name of Object.keys(PROBES)) {
    const [a, b] = [one.did[name]!, three.did[name]!];
    // (what was only looked at follows the list: each row of it taken as written but those made again)
    assert.ok(a.same + a.serialised >= one.chats - 1, `${name}: every other row taken as written (${JSON.stringify(a)})`);
    if (GROWING.has(name)) continue;
    assert.ok(a.made >= 1 && a.made <= MOST_MADE, `${name}: made ${a.made} rows`);
    assert.ok(a.serialised <= a.made + (WRITTEN_ALSO[name] ?? 0), `${name}: serialised ${a.serialised}, more than the ${a.made} made`);
    assert.ok(a.chatJson <= a.serialised, `${name}: read ${a.chatJson} chats' JSON, more than the ${a.serialised} serialised`);
    assert.deepEqual({ made: b.made, serialised: b.serialised, chatJson: b.chatJson }, { made: a.made, serialised: a.serialised, chatJson: a.chatJson }, `${name} with three times the chats`);
  }
});
