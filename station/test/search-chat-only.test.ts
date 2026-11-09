import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { openStore } from "../src/read/store.ts";
import { type Asker, pickAsync, terms } from "../src/search/match.ts";
import { Search } from "../src/search/search.ts";
import { SEARCH_NEXT_MESSAGE_TIMES, stationDocSteps } from "../src/search/sources.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("a chat-only search does not read the messages of a chat whose title and session do not match", async () => {
  const data = mkdtempSync(join(tmpdir(), "search-chat-only-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const chat = (key: string, title: string) => {
    writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
      token: key, createdAt: 1, lastActiveAt: 1, ws: "W" });
    const thread = writer.openThreadOf("ember", "ember", key, null, "a@x", key);
    writer.joinThread(thread.id, key, "ember");
    writer.setAutoTitle(thread.id, title, true);
    return thread.id;
  };
  try {
    const other = chat("other", "Unrelated"), wanted = chat("wanted", "Needle report");
    for (let i = 0; i < 513; i++) writer.insertMessage(newMessage(other, String(i), "person", "a@x", `unrelated ${i}`));
    writer.insertMessage(newMessage(wanted, "1", "person", "a@x", "the report"));
    writer.setTitle("wanted", "details about the report");
    writer.setArchived("other", true, "a@x");
    writer.db.prepare("UPDATE sessions SET model='shared-claude' WHERE key IN ('other','wanted')").run();
    // Timestamps need not follow message numbers; letters count, but later edits do not.
    writer.db.prepare("UPDATE entries SET at = CASE WHEN n = 3 THEN 999999 ELSE n END, letter = CASE WHEN n = 3 THEN ? ELSE letter END WHERE thread = ?")
      .run(JSON.stringify({ way: "in", title: "old", link: null }), other);
    writer.editMessage("ember", "ember", "other", "0", "edited later");
    const read = openStore(data);
    const plan = (read.db.prepare(`EXPLAIN QUERY PLAN ${SEARCH_NEXT_MESSAGE_TIMES}`).all(other, 256, 513, 256) as { detail: string }[])
      .map((row) => row.detail).join(" | ");
    assert.match(plan, /SEARCH entries USING INDEX sqlite_autoindex_entries_1 \(thread=\? AND n=\?\)/);
    assert.match(plan, /SEARCH entries USING COVERING INDEX entries_said/);
    assert.match(plan, /SEARCH entries USING INDEX entries_letters/);
    assert.doesNotMatch(plan, /USE TEMP B-TREE FOR ORDER BY/);
    const pages: { thread: unknown; rows: number; bodies: boolean }[] = [];
    const db = new Proxy(read.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        return new Proxy(statement, { get(stmt, method) {
          const value = Reflect.get(stmt, method, stmt);
          if (typeof value !== "function") return value;
          if (method === "all") return (...args: unknown[]) => {
            const rows = Reflect.apply(value, stmt, args) as unknown[];
            if (/\bFROM\s+(?:merged|entries|legacy_said)\b/i.test(sql))
              pages.push({ thread: args[0], rows: rows.length, bodies: /SELECT\s+\*\s+FROM\s+merged/i.test(sql) });
            return rows;
          };
          return value.bind(stmt);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const asker: Asker = { workspace: "W", home: false, scopes: ["write"] };
      const documents = stationDocSteps({ ...read, db }, data, {}, new Set(["chat"]), asker, false, ["needle"]);
      const result = await pickAsync(documents, ["needle"], asker);
      assert.deepEqual(result.flatMap((group) => group.hits.map((hit) => hit.key)), [`c:${wanted}`]);
      assert.equal(pages.filter((page) => page.thread === other).reduce((sum, page) => sum + page.rows, 0), 0);
      assert.equal(pages.filter((page) => page.thread === wanted && page.bodies).reduce((sum, page) => sum + page.rows, 0), 0,
        "ranking the matching chat needs message times, not message bodies and edits");
      const fullChats = [...stationDocSteps(read, data, {}, null, asker)].filter((doc) => doc?.kind === "chat");
      const chatOnly = [...stationDocSteps(read, data, {}, new Set(["chat"]), asker)].filter((doc) => doc !== undefined);
      assert.deepEqual(chatOnly, fullChats, "timestamp-only pages preserve chat documents, including old letters and edits");
      assert.equal(chatOnly.find((doc) => doc?.key === `c:${other}`)?.at, 999999);
      // The normal source is the reference for ranking, title/body matches, archives, pagination, and mixed kinds.
      for (const query of ["Needle", "needle details", "claude", "unrelated", "absent"]) {
        const words = terms(query);
        for (const kinds of [new Set(["chat"]), new Set(["chat", "message"])]) {
          for (const archived of [false, true]) {
            for (const offset of [0, 1]) {
              const old = await pickAsync(stationDocSteps(read, data, {}, kinds, asker, archived), words, asker, { limit: 1, offset });
              const filtered = await pickAsync(stationDocSteps(read, data, {}, kinds, asker, archived, words), words, asker, { limit: 1, offset });
              assert.deepEqual(filtered, old, `${query}: ${[...kinds]} archived=${archived} offset=${offset}`);
            }
          }
        }
      }
      const search = new Search({ data });
      try {
        search.start();
        const found = await search.query("Needle details", asker, { kinds: ["chat"] });
        assert.deepEqual(found.groups.flatMap((group) => group.hits.map((hit) => hit.key)), [`c:${wanted}`]);
      } finally { await search.stop(); }
    } finally { read.db.close(); }
  } finally {
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a chat-only search yields while passing many nonmatching chats", () => {
  const data = mkdtempSync(join(tmpdir(), "search-chat-yield-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  try {
    for (let i = 0; i < 260; i++) writer.openThread("ember", "CHAT", `chat-${i}`, null, null);
    const read = openStore(data), visited = new Set<unknown>();
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
    try {
      const asker: Asker = { workspace: "home", home: true, scopes: ["write"] };
      const steps = stationDocSteps({ ...read, db }, data, {}, new Set(["chat"]), asker, false, ["needle"]);
      assert.deepEqual(steps.next(), { value: undefined, done: false });
      assert.ok(visited.size <= 128, `visited ${visited.size} chats before yielding`);
    } finally { read.db.close(); }
  } finally {
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});
