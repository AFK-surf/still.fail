// A change to one chat must not read the viewer's marks and answers, nor any chat's shares, openers or snapshots, for
// every other chat.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { ops } from "../src/read/ops.ts";
import { answersSince, dismissed, keptChats, makeStore, openStore } from "../src/read/store.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("a scoped chat update reads marks and answers only for those chats", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE dismissed (viewer TEXT, thread INTEGER, n INTEGER, at INTEGER, PRIMARY KEY (viewer, thread, n));
    CREATE TABLE kept_chats (viewer TEXT, thread INTEGER, PRIMARY KEY (viewer, thread));
    CREATE TABLE closed_cards (thread INTEGER, n INTEGER, viewer TEXT, at INTEGER, PRIMARY KEY (thread, n));
    CREATE TABLE entries (thread INTEGER, n INTEGER, kind TEXT, author_kind TEXT, at INTEGER);`);
  const mark = db.prepare("INSERT INTO dismissed VALUES ('person', ?, 1, 100)");
  const keep = db.prepare("INSERT INTO kept_chats VALUES ('person', ?)");
  const close = db.prepare("INSERT INTO closed_cards VALUES (?, 1, 'person', 100)");
  for (let i = 1; i <= 2000; i++) { mark.run(i); keep.run(i); close.run(i); }
  const counts: Record<string, number> = {};
  const observed = {
    prepare(sql: string) {
      const statement = db.prepare(sql);
      const table = /\bFROM (dismissed|kept_chats|closed_cards)\b/i.exec(sql)?.[1];
      return {
        all: (...params: any[]) => {
          const rows = statement.all(...params);
          if (table) counts[table] = (counts[table] ?? 0) + rows.length;
          return rows;
        },
        get: (...params: any[]) => statement.get(...params),
      };
    },
  } as unknown as DatabaseSync;
  try {
    const s = makeStore(observed, ".");
    assert.deepEqual([...dismissed(s, "person", [1])], ["1:1"]);
    assert.deepEqual([...keptChats(s, "person", [1])], [1]);
    // The closed card for thread 1 is before the time window; the other 1,999 cannot be relevant.
    db.prepare("UPDATE closed_cards SET at = 0 WHERE thread = 1").run();
    assert.deepEqual(answersSince(s, 50, [1]), []);
    assert.deepEqual(counts, { dismissed: 1, kept_chats: 1, closed_cards: 0 });
  } finally {
    db.close();
  }
});

test("a change's sidebar items and a chat's view read their own shares, openers and snapshots, not every chat's", () => {
  // Each read every chat ever shared, opened by an agent or published: at every sidebar change, and every chat told.
  const dir = mkdtempSync(join(tmpdir(), "chat-row-scope-"));
  const store = Store.open(join(dir, "stillfail.db"), join(dir, "archive"));
  try {
    store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" } as any);
    const chat = store.openThread("ember", "EMBER", "1.1", null, "ada@x.com");
    store.joinThread(chat.id, "k", "ember");
    store.insertMessage(newMessage(chat.id, "1.2", "person", "ada@x.com", "看一下"));
    const shared = JSON.stringify([{ workspace: "w2", name: "W2", used: Date.now() }]);
    const share = store.db.prepare("INSERT INTO chat_shares (session, shared, write, by, at) VALUES (?, ?, 0, 'ada@x.com', ?)");
    const open = store.db.prepare("INSERT INTO opened_chats (child_station, child, parent_station, parent, key, created_at) VALUES ('', ?, '', ?, ?, 1)");
    const publish = store.db.prepare("INSERT INTO published (id, thread, key, title, created_by, by_name, created_at, upto, size) VALUES (?, ?, 'k', 't', 'ada@x.com', 'Ada', 1, 1, 1)");
    share.run("k", shared, Date.now());
    open.run("k", "p", "o");
    publish.run("mine", chat.id);
    for (let i = 0; i < 500; i++) {
      share.run(`s${i}`, shared, Date.now());
      open.run(`c${i}`, `p${i}`, `o${i}`);
      open.run(`d${i}`, "k2", `q${i}`);
      publish.run(`x${i}`, 1000 + i);
    }
    const reader = openStore(dir);
    const counts: Record<string, number> = {};
    const db = reader.db;
    (reader as any).db = new Proxy(db, {
      get: (target, property) => {
        if (property !== "prepare") {
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        }
        return (sql: string) => {
          const statement = target.prepare(sql);
          const table = /\bFROM (chat_shares|opened_chats|published)\b/i.exec(sql)?.[1];
          return new Proxy(statement, {
            get: (s, p) => {
              const v = Reflect.get(s, p, s);
              if (p !== "all" && p !== "get") return typeof v === "function" ? v.bind(s) : v;
              return (...args: any[]) => {
                const rows = v.apply(s, args);
                if (table) counts[table] = (counts[table] ?? 0) + (Array.isArray(rows) ? rows.length : rows ? 1 : 0);
                return rows;
              };
            },
          });
        };
      },
    });
    try {
      const viewer = { sub: "ada@x.com", email: "ada@x.com", name: "Ada", role: "member", workspace: "w", device: "d" };
      const rows = (ops.chatRows!(reader, { viewer, sessions: ["k"], threads: [chat.id] }) as any).rows;
      assert.deepEqual(rows.map((r: any) => [r.id, r.opener?.session, r.xshare?.to]), [["k", "p", ["w2"]]]);
      const view = ops.thread!(reader, { viewer, id: String(chat.id), lang: "zh" }) as any;
      assert.deepEqual([view.xshare?.to.map((t: any) => t.workspace), view.published?.map((p: any) => p.id)], [["w2"], ["mine"]]);
      assert.deepEqual(counts, { chat_shares: 2, opened_chats: 1, published: 1 });
    } finally {
      db.close();
    }
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
