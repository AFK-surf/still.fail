// The MoonBit builder of the sessions' turn counts (station/mb, src/turns) counts as `turnCountStep` does, asking for
// the backfill permit only when it writes: the same turns, slice by slice, give the same answers and counts, also when
// the session's turns change in the middle of a count, and when the pool refuses it the permit.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { TurnBuilder } from "../src/read/turn-builder.ts";
import { addSessionTurns } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { turnCountStep, type TurnCountScan } from "../src/store/turn-state.ts";

const binary = mbReaderBinary();

function forgetCounts(db: DatabaseSync) {
  db.exec(`DROP TRIGGER IF EXISTS session_turns_add; DROP TRIGGER IF EXISTS session_turns_drop;
    DROP TRIGGER IF EXISTS session_turns_before_insert; DROP TRIGGER IF EXISTS session_turns_move;
    DROP TABLE IF EXISTS session_turns_guard; DROP TABLE session_turns`);
}

/// A station's database whose turns are from before their counts: a long session (300 turns, many at one moment and
/// with negative rowids), a short one, one with none.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-turn-counts-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  for (const key of ["long", "short", "none"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
    workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
  const put = store.db.prepare("INSERT INTO turns(rowid,id,session_key,kind,started_at) VALUES (?, ?, ?, 'input', ?)");
  store.db.exec("BEGIN");
  for (let n = 0; n < 300; n++) put.run(n - 150, `old-${n}`, "long", n < 200 ? 1 : n);
  for (let n = 0; n < 5; n++) put.run(n + 1000, `short-${n}`, "short", n);
  store.db.exec("COMMIT");
  forgetCounts(store.db);
  addSessionTurns(store.db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const counts = (store: Store) => JSON.stringify(store.db.prepare("SELECT session, n FROM session_turns ORDER BY session").all());

/// The MoonBit builder asked as the pool asks it, the permit given or refused as `permit` says.
function asker(builder: MbProcess, permit: () => boolean) {
  return (message: Record<string, unknown>) => new Promise<{ done: boolean; error?: string }>((resolve) => {
    const on = (line: { done?: boolean; error?: string; take?: boolean; give?: boolean }) => {
      if (line.take) return void builder.postMessage({ permit: permit() });
      if (line.give) return;
      builder.off("message", on);
      resolve(line as { done: boolean; error?: string });
    };
    builder.on("message", on);
    builder.postMessage(message);
  });
}

test("the MoonBit builder counts a session's turns slice by slice as turnCountStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "turn-counts", "--db", mb.path]);
  const ask = asker(builder, () => true);
  try {
    const steps: { session: string; ts: boolean; mb: boolean }[] = [];
    for (const session of ["short", "long", "none"]) {
      let scan: TurnCountScan | null = null;
      for (let i = 0; i < 30; i++) {
        const ours = await ask({ session });
        assert.equal(ours.error, undefined);
        const theirs = turnCountStep(ts.store.db, session, scan);
        scan = theirs.scan;
        steps.push({ session, ts: theirs.done, mb: ours.done });
        // a turn added to the long session in the middle of its count, in both
        if (session === "long" && i === 2) for (const f of [ts, mb])
          f.store.db.prepare("INSERT INTO turns(id,session_key,kind,started_at) VALUES ('late','long','input',9999)").run();
        if (ours.done) break;
      }
    }
    assert.ok(steps.filter((s) => s.session === "long").length >= 5, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(counts(mb.store), counts(ts.store));
    assert.equal(counts(mb.store), JSON.stringify([{ session: "long", n: 301 }, { session: "short", n: 5 }]));
    assert.equal((mb.store.db.prepare("SELECT count(*) AS n FROM session_turns_guard").get() as { n: number }).n, 0);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("without the permit it reads but writes nothing; a count let go leaves no guard", async () => {
  assert.notEqual(binary, null);
  const f = old();
  let allowed = false;
  const builder = new MbProcess(binary!, ["--builder", "turn-counts", "--db", f.path]);
  const ask = asker(builder, () => allowed);
  try {
    assert.deepEqual(await ask({ session: "long" }), { done: false });
    assert.equal((f.store.db.prepare("SELECT count(*) AS n FROM session_turns_guard").get() as { n: number }).n, 0);
    allowed = true;
    assert.deepEqual(await ask({ session: "long" }), { done: false });
    assert.equal((f.store.db.prepare("SELECT count(*) AS n FROM session_turns_guard").get() as { n: number }).n, 1);
    // let go: its guard removed under the permit, no answer
    const taken = new Promise<void>((resolve) => builder.once("message", (line: { take?: boolean }) => {
      assert.equal(line.take, true);
      builder.postMessage({ permit: true });
      resolve();
    }));
    builder.postMessage({ session: "long", cancel: true });
    await taken;
    const given = await new Promise((resolve) => builder.once("message", resolve));
    assert.deepEqual(given, { give: true });
    assert.equal((f.store.db.prepare("SELECT count(*) AS n FROM session_turns_guard").get() as { n: number }).n, 0);
  } finally {
    await builder.terminate();
    f.close();
  }
});

test("the station's turn builder counts what it is asked, the pool giving the permit", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const priority = new SharedArrayBuffer(8);
  const builder = new TurnBuilder(f.path, { priority });
  try {
    await builder.ready(["long", "short", "none"]);
    assert.equal(counts(f.store), JSON.stringify([{ session: "long", n: 300 }, { session: "short", n: 5 }]));
    assert.equal(Atomics.load(new Int32Array(priority), 1), 0, "the permit given back");
  } finally {
    await builder.close();
    f.close();
  }
});
