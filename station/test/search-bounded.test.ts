import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Store, newMessage } from "../src/store/store.ts";
import { openStore } from "../src/read/store.ts";
import { type Asker, type Doc, pick, pickAsync } from "../src/search/match.ts";
import { SEARCH_NEXT_MESSAGES, stationDocs } from "../src/search/sources.ts";

const asker: Asker = { workspace: "W2", home: false, scopes: ["write"] };

test("a result page does not repeatedly compare every matching document", () => {
  let datesRead = 0;
  const count = 2_003;
  const docs: Doc[] = Array.from({ length: count }, (_, i) => ({
    key: `${i}`, kind: "message", ws: "W2", title: "", body: "needle", ref: {},
    get at() { datesRead++; return (i * 593) % count; },
  }));
  const expected = Array.from({ length: count }, (_, i) => i)
    .sort((a, b) => ((b * 593) % count) - ((a * 593) % count))
    .slice(3, 8).map(String);
  const result = pick(docs, ["needle"], asker, { limit: 5, offset: 3 });
  assert.deepEqual(result[0]?.hits.map((h) => h.key), expected);
  assert.equal(result[0]?.more, true);
  assert.ok(datesRead <= count + 8, `each match's date is read once; got ${datesRead} reads for ${count} matches`);
});

test("the page keeps its own excerpts instead of retaining every matching body", () => {
  let current = 0;
  function* documents(): Generator<Doc> {
    for (let i = 0; i < 1_000; i++) {
      yield {
        key: `${i}`, kind: "message", ws: "W2", title: "", at: i, ref: {},
        get body() {
          assert.equal(current, i, "a body is used only while its document is being read");
          return `needle ${i}`;
        },
      };
      current++;
    }
  }
  const result = pick(documents(), ["needle"], asker, { limit: 2 });
  assert.deepEqual(result[0]?.hits.map((h) => [h.key, h.text]), [["999", "needle 999"], ["998", "needle 998"]]);
});

test("a bounded page preserves title priority, timestamps, and input order for ties", () => {
  const docs: Doc[] = Array.from({ length: 100 }, (_, i) => ({
    key: `${i}`, kind: "message", ws: "W2", title: i % 13 === 0 ? "needle title" : "",
    body: "needle", at: i % 7 === 0 ? null : i % 5, ref: {},
  }));
  const expected = docs.map((d, i) => ({ d, i }))
    .sort((a, b) => Number(b.d.title !== "") - Number(a.d.title !== "")
      || Number(a.d.at === null) - Number(b.d.at === null)
      || (b.d.at ?? 0) - (a.d.at ?? 0) || a.i - b.i)
    .slice(8, 15).map(({ d }) => d.key);
  assert.deepEqual(pick(docs, ["needle"], asker, { limit: 7, offset: 8 })[0]?.hits.map((h) => h.key), expected);
});

test("a cancelled search stops between batches and lets another request run", async () => {
  let stopped = false;
  let read = 0;
  function* documents(): Generator<Doc> {
    for (let i = 0; i < 2_000; i++) {
      read++;
      yield { key: `${i}`, kind: "message", ws: "W2", title: "", body: "needle", at: i, ref: {} };
    }
  }
  const pending = pickAsync(documents(), ["needle"], asker, {}, () => stopped);
  await new Promise<void>((resolve) => setImmediate(resolve));
  stopped = true;
  await assert.rejects(pending, /search took too long/);
  assert.ok(read <= 257, `cancelled after ${read} documents`);
});

test("search reads messages in bounded batches and skips other workspaces before reading their bodies", () => {
  const data = mkdtempSync(join(tmpdir(), "search-bounded-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const chat = (key: string, ws: string) => {
    writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, ws });
    const thread = writer.openThreadOf("ember", "ember", key, null, "a@x", key);
    writer.joinThread(thread.id, key, "ember");
    return thread.id;
  };
  try {
    const other = chat("other", "W1");
    const own = chat("own", "W2");
    writer.insertMessage(newMessage(other, "1", "person", "a@x", "needle hidden"));
    for (let i = 0; i < 1_024; i++) writer.insertMessage(newMessage(own, String(i), "person", "a@x", `needle ${i}`));
    const read = openStore(data);
    const plan = (read.db.prepare(`EXPLAIN QUERY PLAN ${SEARCH_NEXT_MESSAGES}`)
      .all(own, 512, 1_024, 256) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH entries USING COVERING INDEX entries_said \(thread=\? AND n>\? AND n<\?\)/, "later batches seek ordinary messages");
    assert.match(plan, /SEARCH entries USING INDEX entries_letters \(thread=\? AND n>\? AND n<\?\)/, "later batches seek legacy letters");
    assert.match(plan, /SEARCH m USING INDEX \S+ \(thread=\? AND n=\?\)/, "only those messages are fetched");
    assert.doesNotMatch(plan, /USE TEMP B-TREE FOR ORDER BY/);
    const queries: { thread: unknown; rows: number }[] = [];
    const db = new Proxy(read.db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(stmt, method) {
              const value = Reflect.get(stmt, method, stmt);
              if (typeof value !== "function") return value;
              if (method === "all" || method === "get") return (...args: unknown[]) => {
                const rows = Reflect.apply(value, stmt, args);
                if (/\bmerged\b/i.test(sql)) queries.push({ thread: args[0], rows: Array.isArray(rows) ? rows.length : Number(rows !== undefined) });
                return rows;
              };
              return value.bind(stmt);
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    try {
      const traced = { ...read, db };
      // The fifth argument is the viewer for whom the source is read.
      const documents = (stationDocs as any)(traced, data, {}, new Set(["message"]), asker) as Generator<Doc>;
      const first = documents.next().value as Doc;
      assert.equal(first.ref.thread, own);
      assert.ok(!queries.some((q) => q.thread === other), "another workspace's message bodies are never read");
      assert.ok(queries.reduce((n, q) => n + q.rows, 0) <= 257, "reading the first hit does not load the whole chat");
      writer.insertMessage(newMessage(own, "later", "person", "a@x", "needle arrived later"));
      assert.ok(![...documents].some((d) => d.body === "needle arrived later"), "a growing chat does not extend this search forever");
    } finally {
      read.db.close();
    }
  } finally {
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});
