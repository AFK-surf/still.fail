import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import * as reads from "../src/read/store.ts";
import * as compact from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { Store } from "../src/store/store.ts";

test("a repeated usage summary rereads only hours whose statistics changed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-cache-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let db: DatabaseSync | null = null;
  try {
    for (const [key, ws] of [["a", "A"], ["b", "A"], ["other", "B"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, output = 1) => ({ id, at, model: "m", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    for (const key of ["a", "b", "other"]) {
      const calls = Array.from({ length: 120 }, (_, n) => [call(`${key}-${n}`, n * 60_000), owner] as [ReturnType<typeof call>, typeof owner]);
      writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", calls);
    }
    const install = (compact as any).installUsageSummaryChanges;
    assert.equal(typeof install, "function", "a reader can tell which hours changed, including writes by an older station");
    install(writer.db);
    db = new DatabaseSync(path, { readOnly: true });
    const store = reads.makeStore(db, dir);
    const make = (reads as any).UsageSummaryCache;
    assert.equal(typeof make, "function");
    const cache = new make();
    const viewer = { workspace: "A", home: false };
    const read = async () => {
      db!.exec("BEGIN");
      try { return await (reads.usageGroupsBatched as any)(store, 0n, 120n * 60_000n, 0n, viewer, async () => {}, cache); }
      finally { db!.exec("COMMIT"); }
    };
    const first = await read();
    assert.deepEqual(first.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual((await read()).groups, first.groups, "an unchanged summary does not read the minute buckets again"); }
    finally { db.setAuthorizer(null); }
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call("a-1", 60_000, 7), owner]]);
    const next = await read();
    assert.deepEqual(next.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    assert.equal(next.diagnostics.parts, 60, "only the changed session's hour is read again");
  } finally {
    db?.close();
    writer.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
