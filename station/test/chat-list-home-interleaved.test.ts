import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep, settleRecentHomeOrderStep, settleRecentHomeSessionStep } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome, scanRecentHomeOverlapStep, settleRecentHomeOverlapStep } from "../src/store/chat-list-home-overlap.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep, settleRecentWorkspaceSessionStep } from "../src/store/chat-list-scope-build.ts";
import { trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { dispatchRecentScopeOrderStep, settleRecentWorkspaceOrderStep } from "../src/store/chat-list-scope-order.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "../src/store/chat-list-scope-visibility.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`home and workspace pages match the original across interleaved changes (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "A"], ["two", "B"], ["default", null]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    let seed = 0x845ab613, name = 0;
    const pick = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    const add = () => {
      const id = store.openThread("ember", "EMBER", `chat-${name++}`, "Chat", null).id;
      db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(pick(20), id);
      return id;
    };
    for (let i = 0; i < 10; i++) {
      const id = add();
      if (i % 3 === 0) db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(i % 2 === 0 ? "one" : "missing", id);
      else store.joinThread(id, i % 2 === 0 ? "one" : "two", "ember");
    }
    installRecentHomeIndex(db);
    for (const ws of ["A", "B"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 3).sourceDone) { /* Prepare each workspace. */ }
    }
    while (!scanRecentHomeChatsStep(db, 3).scanDone) { /* Enqueue old default chats. */ }
    while (!settleRecentHomeChatStep(db, 3).chatsDone) { /* Prepare default rows. */ }
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 3).scanDone) { /* Enqueue existing default rows. */ }
    while (!settleRecentHomeOverlapStep(db, 3).overlapsDone) { /* Prepare overlap counts. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const check = (step: number) => {
      for (const ws of ["A", "B"]) for (const limit of [1, 3, 20]) {
        const scoped = readPreparedRecentWorkspace(db, ws, limit);
        if (scoped !== null) assert.deepEqual(scoped, recentChatIds(db, ws, "fallback", limit), `workspace ${ws}, write ${step}`);
        const home = readPreparedRecentHome(db, ws, limit);
        if (home !== null) assert.deepEqual(home, recentChatIds(db, ws, ws, limit), `home ${ws}, write ${step}`);
      }
    };
    const drain = () => {
      for (let pass = 0; pass < 200; pass++) {
        settleRecentScopeVisibilityStep(db, 3);
        for (const ws of ["A", "B"]) {
          settleRecentWorkspaceSessionStep(db, ws, 3);
          settleRecentWorkspaceMemberStep(db, ws, 3);
        }
        dispatchRecentScopeOrderStep(db, 3);
        for (const ws of ["A", "B"]) settleRecentWorkspaceOrderStep(db, ws, 3);
        settleRecentHomeSessionStep(db, 3);
        settleRecentHomeChatStep(db, 3);
        settleRecentHomeOrderStep(db, 3);
        settleRecentHomeOverlapStep(db, 3);
        if (["A", "B"].every((ws) => readPreparedRecentHome(db, ws, 3) !== null)) return;
      }
      assert.fail("all changed pages should eventually settle");
    };
    const insert = db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','p','hello',?)");
    const sessions = ["one", "two", "default", "missing"];
    for (let step = 0; step < 100; step++) {
      const threads = db.prepare("SELECT id FROM threads ORDER BY id").all() as { id: number }[];
      const id = threads.length ? threads[pick(threads.length)]!.id : add();
      switch (pick(7)) {
        case 0: db.prepare("UPDATE threads SET home = ? WHERE id = ?").run([null, "one", "two", "missing"][pick(4)], id); break;
        case 1: store.joinThread(id, sessions[pick(sessions.length)]!, "ember"); break;
        case 2: db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = ?").run(id, sessions[pick(sessions.length)]); break;
        case 3: insert.run(id, 1 + pick(4), pick(100)); break;
        case 4: db.prepare("UPDATE entries SET at = ? WHERE thread = ? AND n = ?").run(pick(100), id, 1 + pick(4)); break;
        case 5: db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run([null, "A", "B"][pick(3)], sessions[pick(3)]); break;
        case 6: if (threads.length > 3) db.prepare("DELETE FROM threads WHERE id = ?").run(id); else add(); break;
      }
      check(step);
      drain();
      check(step);
    }
  } finally { store.close(); }
});
