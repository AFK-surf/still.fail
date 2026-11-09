import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { type Asker, pick } from "../src/search/match.ts";
import { stationDocs } from "../src/search/sources.ts";
import { SearchScopePreparation } from "../src/search/scope-prepare.ts";
import { Store } from "../src/store/store.ts";

test("search visits the chats visible to its workspace, including public and default chats", () => {
  const writer = Store.open(":memory:");
  try {
    for (const [key, ws] of [["away", "away"], ["mine", "mine"], ["old", null], ["public", "*"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const chat = (key: string, home: string | null, member: string | null) => {
      const thread = writer.openThreadOf("ember", "CHAT", key, "needle", null, home);
      if (member !== null) writer.joinThread(thread.id, member, "ember");
      return thread.id;
    };
    const own = chat("own", "away", "mine");
    const publicChat = chat("public-chat", "public", "public");
    const old = chat("old-chat", "away", "old");
    const orphan = chat("orphan", "away", null);
    const unknown = chat("unknown", "away", "unknown-session");
    for (let i = 0; i < 400; i++) chat(`away-${i}`, "away", "away");
    const preparation = new SearchScopePreparation(writer.db);
    let prepared = false;
    for (let i = 0; i < 100 && !prepared; i++) prepared = preparation.step().done;
    assert.ok(prepared);
    const read = makeStore(writer.db, "."), visited = new Set<unknown>();
    const db = new Proxy(read.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        return new Proxy(statement, { get(stmt, method) {
          const value = Reflect.get(stmt, method, stmt);
          if (typeof value !== "function") return value;
          if (method === "get" && sql === "SELECT * FROM threads WHERE id = ?") return (...args: unknown[]) => {
            visited.add(args[0]);
            return Reflect.apply(value, stmt, args);
          };
          return value.bind(stmt);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    for (const home of [false, true]) {
      visited.clear();
      const asker: Asker = { workspace: "mine", home, scopes: [] };
      const found = pick(stationDocs({ ...read, db }, ".", {}, new Set(["chat"]), asker), ["needle"], asker, { limit: 10 });
      const hits = found.flatMap((group) => group.hits.map((hit) => hit.thread)).sort((a, b) => Number(a) - Number(b));
      const expected = (home ? [own, publicChat, old, orphan, unknown] : [own, publicChat]).sort((a, b) => a - b);
      assert.deepEqual(hits, expected);
      assert.equal(visited.size, expected.length, `visited ${visited.size} chats for ${expected.length} visible chats`);
    }
  } finally { writer.close(); }
});
