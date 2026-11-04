import assert from "node:assert/strict";
import { test } from "node:test";
import { addSessionTurns } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("installing turn counts does not visit an old station's turns", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO turns(id,session_key,kind,started_at) VALUES (?,?,'user',?)");
    db.exec("BEGIN");
    for (let n = 0; n < 5_000; n++) put.run(`turn-${n}`, `session-${n % 5}`, n);
    db.exec("COMMIT");
    db.exec("DROP TRIGGER session_turns_add; DROP TRIGGER session_turns_drop; DROP TABLE session_turns");
    let visited = 0;
    db.function("visit_old_turn", (_id) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => target.exec(sql.replace(
          "SELECT session_key, COUNT(*) FROM turns GROUP BY session_key",
          "SELECT session_key, COUNT(visit_old_turn(id)) FROM turns GROUP BY session_key",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    addSessionTurns(instrumented);
    assert.equal(visited, 0, `opening an older station visited ${visited} old turns`);
  } finally { store.close(); }
});
