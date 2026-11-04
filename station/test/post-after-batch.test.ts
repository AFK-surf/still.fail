import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function setup() {
  const rig = new Rig();
  rig.store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = (name: string) => {
    const id = rig.store.openThread("ember", "EMBER", name, null, null).id;
    rig.store.joinThread(id, "s", "ember");
    return id;
  };
  const put = rig.store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, ts, text, at) VALUES (?, ?, 'message', ?, ?, ?, 'hello', ?)");
  const deliver = rig.store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, ?, 's')");
  const format = async () => {
    const actor = rig.hub.actor(rig.session("s"));
    return (await (actor as any).format(rig.store.pendingMessages("s")))[0] as string;
  };
  return { rig, thread, put, deliver, format };
}

test("a batch of messages with no later post does not repeatedly scan the same history", async () => {
  const { rig, thread, put, deliver, format } = setup();
  try {
    const id = thread("one");
    rig.store.db.exec("BEGIN");
    for (let n = 1; n <= 5_100; n++) {
      put.run(id, n, "person", "other", `m${n}`, n);
      if (n <= 100) deliver.run(id, n);
    }
    rig.store.db.exec("COMMIT");
    let searches = 0;
    const postAfter = rig.store.postAfter.bind(rig.store);
    rig.store.postAfter = (...args) => { searches++; return postAfter(...args); };
    const text = await format();
    assert.ok(text.includes('ts="m1">') && text.includes('ts="m100">'));
    assert.equal(searches, 1, "one search covers all messages in the same thread with no later post");
  } finally { await rig.close(); }
});

test("batched messages keep the first later post in each thread and their original delivery order", async () => {
  const { rig, thread, put, deliver, format } = setup();
  try {
    const a = thread("a"), b = thread("b");
    for (const [n, kind, author, ts] of [
      [1, "person", "other", "a1"], [2, "person", "other", "a2"], [3, "agent", "s", "p3"],
      [4, "person", "other", "a4"], [5, "agent", "s", null], [6, "person", "other", "a6"],
      [7, "agent", "s", "p7"], [8, "person", "other", "a8"],
    ] as const) put.run(a, n, kind, author, ts, n);
    put.run(b, 1, "person", "other", "b1", 1);
    put.run(b, 2, "agent", "s", "pb", 2);
    for (const [id, n] of [[a, 6], [b, 1], [a, 1], [a, 4], [a, 2], [a, 8]]) deliver.run(id!, n!);
    const text = await format();
    for (const part of ['ts="a6" before="p7">', 'ts="b1" before="pb">', 'ts="a1" before="p3">', 'ts="a4">', 'ts="a2" before="p3">', 'ts="a8">']) {
      assert.ok(text.includes(part), `${part} missing from ${text}`);
    }
    const order = ["a6", "b1", "a1", "a4", "a2", "a8"].map((ts) => text.indexOf(`ts="${ts}"`));
    assert.deepEqual(order, [...order].sort((x, y) => x - y));
  } finally { await rig.close(); }
});

test("a letter in its own log does not look for a later chat post", async () => {
  const { rig, thread, put, format } = setup();
  try {
    const id = thread("letters");
    put.run(id, 2, "agent", "s", "post", 2);
    rig.store.db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, at, letter) VALUES (?, 1, 'letter', 'agent', 'other', 'hello', 1, '{}')").run(id);
    rig.store.db.prepare("INSERT INTO letter_deliveries (thread, n, session) VALUES (?, 1, 's')").run(id);
    let searches = 0;
    const postAfter = rig.store.postAfter.bind(rig.store);
    rig.store.postAfter = (...args) => { searches++; return postAfter(...args); };
    assert.ok((await format()).includes('ts="letter">'));
    assert.equal(searches, 0);
  } finally { await rig.close(); }
});

test("a batch sees one snapshot while another station writes", () => {
  const dir = mkdtempSync(join(tmpdir(), "posts-after-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  const other = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "EMBER", "chat", null, null).id;
    store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, ts, at) VALUES (?, 2, 'message', 'agent', 's', 'p2', 2)").run(thread);
    const postAfter = store.postAfter.bind(store);
    let wrote = false;
    store.postAfter = (...args) => {
      const found = postAfter(...args);
      if (!wrote) {
        wrote = true;
        other.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, ts, at) VALUES (?, 4, 'message', 'agent', 's', 'p4', 4)").run(thread);
      }
      return found;
    };
    assert.deepEqual(store.postsAfter("s", [{ thread, n: 1 }, { thread, n: 3 }]), ["p2", null]);
    assert.deepEqual(store.postsAfter("s", [{ thread, n: 3 }]), ["p4"]);
    store.postAfter = () => { throw new Error("read failed"); };
    assert.throws(() => store.postsAfter("s", [{ thread, n: 1 }]), /read failed/);
    assert.doesNotThrow(() => store.db.exec("BEGIN; ROLLBACK"), "an error releases the read snapshot");
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
