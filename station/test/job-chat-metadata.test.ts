import assert from "node:assert/strict";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { makeStore } from "../src/read/store.ts";
import { chats } from "../src/read/views.ts";
import { MANUAL, Store, newMessage } from "../src/store/store.ts";

const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member", workspace: "A", device: "dev", home: true } as const;

for (const children of [4, 400]) test(`naming a job does not read ${children} children or sidebar marks`, () => {
  const station = Store.open(":memory:");
  try {
    station.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
    const chat = station.openThread("ember", "CHAT", "own", "Given title", "ann@x");
    station.joinThread(chat.id, "a", "ember");
    station.insertMessage({ ...newMessage(chat.id, "1", "person", "ann@x", "hello"), at: 1 });
    station.insertJob({ id: "j", sessionKey: "a", name: "watching", command: "true", cwd: "/", port: null, token: "j",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: true });
    const db = station.db;
    db.prepare("INSERT INTO job_notices (job_id, at, text) VALUES ('j', 3, 'notice')").run();
    const reader = makeStore(db, ".");
    const expected = openJobs(reader, viewer, "en");
    assert.deepEqual(expected.map((j) => [j.id, j.chat?.id, j.chat?.title, j.notices]),
      [["j", "a", "Given title", [{ at: 3, text: "notice" }]]]);

    const put = db.prepare("INSERT INTO opened_chats (child_station, child, parent_station, parent, key, title, created_at) VALUES ('remote', ?, '', 'a', ?, ?, ?)");
    for (let i = 0; i < children; i++) put.run(`child-${i}`, `key-${i}`, `Child ${i}`, i);
    db.prepare("INSERT INTO chat_shares (session, shared, write, by, at) VALUES ('a', ?, 0, 'ann@x', ?)")
      .run(JSON.stringify([{ workspace: "B", name: "B", used: Date.now() }]), Date.now());
    db.prepare("INSERT INTO reads VALUES ('ann@x', ?, 1, 1)").run(chat.id);
    db.prepare("INSERT INTO dismissed VALUES ('ann@x', ?, 1, 1)").run(chat.id);
    db.prepare("INSERT INTO kept_chats VALUES ('ann@x', ?)").run(chat.id);
    db.prepare("INSERT INTO hidden_chats VALUES ('ann@x', ?)").run(chat.id);
    db.prepare("INSERT INTO muted_chats VALUES ('ann@x', ?)").run(chat.id);
    db.prepare("INSERT INTO pins VALUES ('ann@x', 'a', 2)").run();

    const full = chats(reader, viewer, false)[0];
    assert.equal(full.opened.length, children);
    assert.deepEqual(full.xshare.to, ["B"]);
    assert.equal(full.hidden, true);
    assert.equal(full.muted, true);
    assert.equal(full.pinned, 2);
    assert.deepEqual(full.agents[0].watch.names, ["watching"]);

    const looked: string[] = [];
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const table = /\bFROM\s+(opened_chats|chat_shares|active_watch_jobs|reads|dismissed|kept_chats|hidden_chats|muted_chats|pins)\b/i.exec(sql)?.[1];
        if (table) looked.push(table);
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer, "en"), expected);
    assert.deepEqual(looked, [], "job names do not need the sidebar's children, shares, watches or viewer marks");
  } finally { station.close(); }
});

test("an archived job is named without reading its chat's children", () => {
  const station = Store.open(":memory:");
  try {
    station.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
    const chat = station.openThreadOf("ember", "CHAT", "own", "Archived title", "ann@x", "a");
    station.joinThread(chat.id, "a", "ember");
    station.insertJob({ id: "j", sessionKey: "a", name: "job", command: "true", cwd: "/", port: null, token: "j",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    station.setArchived("a", true, MANUAL);
    const db = station.db, reader = makeStore(db, ".");
    const expected = openJobs(reader, viewer, "en");
    assert.deepEqual(expected.map((j) => [j.id, j.chat?.title, j.chat?.archived]), [["j", "Archived title", true]]);
    const put = db.prepare("INSERT INTO opened_chats (child_station, child, parent_station, parent, key, title, created_at) VALUES ('remote', ?, '', 'a', ?, ?, ?)");
    for (let i = 0; i < 4; i++) put.run(`child-${i}`, `key-${i}`, `Child ${i}`, i);
    assert.equal(chats(reader, viewer, true)[0].opened.length, 4);
    let opened = 0;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (/\bFROM\s+opened_chats\b/i.test(sql)) opened++;
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer, "en"), expected);
    assert.equal(opened, 0);
  } finally { station.close(); }
});
