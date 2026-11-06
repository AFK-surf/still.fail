import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("opening an old store can use its time index without rebuilding it over all checks", () => {
  const visits: number[] = [];
  const probes: number[] = [];
  for (const size of [80, 800]) {
    const dir = mkdtempSync(join(tmpdir(), "old-decision-time-"));
    const path = join(dir, "station.db");
    let store: Store | null = Store.open(path);
    let old: DatabaseSync | null = null;
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const prepareDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    const prepare = prepareDescriptor.value as DatabaseSync["prepare"];
    let visited = 0, probed = 0;
    try {
      store.db.exec("BEGIN");
      const put = store.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('a',?, '{}')");
      for (let n = 1; n <= size; n++) put.run(n);
      store.db.exec("COMMIT");
      store.db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
      store.db.exec("DROP INDEX decision_checks_lately");
      store.close();
      store = null;
      old = new DatabaseSync(path);
      old.function("visit_decision_time_build", { deterministic: true }, (id) => id === null ? 0 : 1);
      const oldRead = old.prepare("SELECT id FROM decision_checks INDEXED BY decision_checks_at WHERE created_at>=? ORDER BY created_at,id");
      const oldWrite = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('b',?, '{}')");
      const create = "CREATE INDEX IF NOT EXISTS decision_checks_lately ON decision_checks (created_at, session)";
      Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, source: string) {
        if (source.includes(create)) {
          this.function("visit_decision_time_build", { deterministic: true }, (id) => { visited++; return id === null ? 0 : 1; });
          source = source.replace(create, `${create} WHERE visit_decision_time_build(id)`);
        }
        return exec.call(this, source);
      } });
      Object.defineProperty(DatabaseSync.prototype, "prepare", { ...prepareDescriptor, value(this: DatabaseSync, source: string) {
        if (source === "SELECT 1 FROM decision_checks LIMIT 1 OFFSET 63") {
          this.function("visit_decision_time_probe", (id) => { probed++; return id === null ? 0 : 1; });
          source = "SELECT 1 FROM decision_checks WHERE visit_decision_time_probe(id) LIMIT 1 OFFSET 63";
        }
        return prepare.call(this, source);
      } });
      store = Store.open(path);
      visits.push(visited);
      probes.push(probed);
      oldWrite.run(size + 1);
      assert.deepEqual(oldRead.all(size).map((row) => row.id), [size, size + 1]);
      assert.deepEqual(store.latestDecisionsSince(size).map((row) => row.session), ["a", "b"]);
    } finally {
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      Object.defineProperty(DatabaseSync.prototype, "prepare", prepareDescriptor);
      old?.close();
      store?.close();
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(visits, [0, 0], `opening rebuilt the time index over ${visits.join(" / ")} old checks`);
  assert.deepEqual(probes, [64, 64], `opening probed ${probes.join(" / ")} checks`);
});
