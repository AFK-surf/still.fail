import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("opening an old store bounds preparation of its per-chat people-time lookup", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "old-people-time-")), path = join(dir, "station.db");
    const initial = Store.open(path);
    const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(1,?,'message','person','p',?)");
    for (let n = 1; n <= size; n++) put.run(n,n);
    initial.db.exec("DROP INDEX entries_people_since");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    const prepareDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
    const prepare = prepareDescriptor.value as DatabaseSync["prepare"];
    const marker = "CREATE INDEX IF NOT EXISTS entries_people_since ON entries (thread, at) WHERE";
    const visited = new Set<string>();
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, sql: string) {
      if (sql.includes(marker)) {
        this.function("visit_people_time_build", { deterministic: true }, (n) => { visited.add(String(n)); return 1; });
        sql = sql.replace(marker, `${marker} visit_people_time_build(n) AND`);
      }
      return exec.call(this, sql);
    } });
    Object.defineProperty(DatabaseSync.prototype, "prepare", { ...prepareDescriptor, value(this: DatabaseSync, sql: string) {
      if (sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63") {
        this.function("visit_people_time_probe", (n) => { visited.add(String(n)); return 1; });
        sql = "SELECT 1 FROM entries WHERE visit_people_time_probe(n) LIMIT 1 OFFSET 63";
      }
      return prepare.call(this, sql);
    } });
    let reopened: Store | null = null;
    try { reopened = Store.open(path); counts.push(visited.size); }
    finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      Object.defineProperty(DatabaseSync.prototype, "prepare", prepareDescriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.ok(counts[0]! <= 64 && counts[1]! <= 64, `entries visited while opening: ${counts.join(" / ")}`);
});
