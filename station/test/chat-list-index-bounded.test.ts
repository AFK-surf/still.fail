import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { recentChatPage } from "../src/read/recent-chat.ts";
import { recentChatIds } from "../src/store/chat-list.ts";
import { RecentChatPreparation, type RecentChatScope } from "../src/store/chat-list-prepare.ts";
import { Store } from "../src/store/store.ts";

test("prepared recent pages read only their limited order rows as unrelated chats grow", () => {
  function visits(foreign: number) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      for (const [key, ws] of [["here", "here"], ["away", "away"]] as const)
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: 1, lastActiveAt: 1, ws });
      db.exec("BEGIN");
      for (let i = 0; i < 10; i++) {
        const id = store.openThread("ember", "CHAT", `here-${i}`, "Here", null).id;
        store.joinThread(id, "here", "ember");
        store.joinThread(id, "missing", "ember"); // Present in both the default and the explicit home.
      }
      for (let i = 0; i < foreign; i++) {
        const id = store.openThread("ember", "CHAT", `away-${i}`, "Away", null).id;
        db.prepare("UPDATE threads SET home = 'away' WHERE id = ?").run(id);
      }
      db.exec("COMMIT");
      const scopes: RecentChatScope[] = [{ ws: null, home: "here" }, { ws: "here", home: "elsewhere" }, { ws: "here", home: "here" }];
      const expected = scopes.map(({ ws, home }) => recentChatIds(db, ws, home, 5));
      const prep = new RecentChatPreparation(db);
      for (const scope of scopes) {
        let done = false;
        for (let i = 0; i < 10_000 && !done; i++) done = prep.step(scope).done;
        assert.ok(done, "all requested pages were prepared");
      }
      const visited = { global: 0, workspace: 0, home: 0 };
      db.function("visit_recent_global", (_thread) => { visited.global++; return 1; });
      db.function("visit_recent_workspace", (_thread) => { visited.workspace++; return 1; });
      db.function("visit_recent_home", (_thread) => { visited.home++; return 1; });
      const instrumented = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            for (const [source, fn] of [["recent_chat_rows INDEXED BY recent_chat_order", "visit_recent_global"],
              ["recent_scope_rows INDEXED BY recent_scope_order", "visit_recent_workspace"],
              ["recent_home_rows INDEXED BY recent_home_order", "visit_recent_home"]] as const) {
              if (sql.includes(source)) sql = sql.replace(/\s+ORDER BY/, `${sql.includes("WHERE ws = ?") ? " AND" : " WHERE"} ${fn}(thread) ORDER BY`);
            }
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      db.setAuthorizer((action, name) => action === constants.SQLITE_READ &&
        ["threads", "thread_state", "entries", "sessions", "thread_sessions"].includes(name ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try {
        assert.deepEqual(scopes.map(({ ws, home }) => recentChatPage(instrumented, ws, home, 5)), expected);
      } finally { db.setAuthorizer(null); }
      return visited;
    } finally { store.close(); }
  }
  const small = visits(50), large = visits(500);
  assert.deepEqual(large, small, "unrelated chats must not add order rows to a prepared page read");
  assert.deepEqual(large, { global: 5, workspace: 10, home: 5 }, "each source is read once per requested page");
});
