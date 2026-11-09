import assert from "node:assert/strict";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { PENDING_COUNT } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

test("a Comma Task's status counts only readable pending messages and letters, without reading their bodies", async () => {
  const rig = new Rig();
  const tasks = new CommaTasks(join(rig.dir, "comma-tasks.json"));
  const task = tasks.invited("cm", "task1", { requester: "u", title: null, runtime: null, model: null }, 0);
  const key = `cm:TASK:${task.threadTs}`;
  const surface = new CommaSurface({ connect: "cm", server: "http://127.0.0.1", token: "token", name: "cm", tasks, store: rig.store, models: () => [] });
  try {
    rig.store.insertSession({ key, connect: "cm", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 } as never);
    const thread = rig.store.openThread("comma:cm", "TASK", task.threadTs, null, null);
    rig.store.joinThread(thread.id, key, "cm");
    const [message] = rig.store.insertMessage({ thread: thread.id, ts: "1.1", authorKind: "person", author: "u", text: "message" });
    rig.store.editMessage("comma:cm", "TASK", task.threadTs, "1.1", "edited message");
    const edit = rig.store.lastEntry(thread.id);
    const [read] = rig.store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "u", text: "read already" });
    rig.store.deliver(thread.id, message, [key, "another"]);
    rig.store.deliver(thread.id, edit, [key]); // An edit is not a message, even if an old delivery points at it.
    rig.store.deliver(thread.id, read, [key]);
    rig.store.deliver(thread.id, 99999, [key]); // An orphan delivery is not readable.
    rig.store.markDelivered(key, [{ thread: thread.id, n: read, apart: false }]);
    const letter = rig.store.insertLetter({ thread: thread.id, ts: "2.1", authorKind: "person", author: "u", text: "letter", letter: { way: "in", title: "another", link: null } });
    rig.store.deliverLetter(thread.id, letter, [key]);
    rig.store.deliverLetter(thread.id, 99999, [key]);
    const elsewhere = rig.store.openThread("comma:cm", "TASK", "elsewhere", null, null);
    const [unjoined] = rig.store.insertMessage({ thread: elsewhere.id, ts: "3.1", authorKind: "person", author: "u", text: "not a member" });
    rig.store.deliver(elsewhere.id, unjoined, [key]);

    assert.equal(rig.store.pendingMessages(key).length, 2);
    const plan = rig.store.db.prepare(`EXPLAIN QUERY PLAN ${PENDING_COUNT}`).all(key) as { detail: string }[];
    assert.match(plan.map((p) => p.detail).join(" | "), /deliveries_pending \(session=\?\)/);
    assert.match(plan.map((p) => p.detail).join(" | "), /letter_deliveries_pending \(session=\?\)/);
    rig.store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ &&
      ((table === "entries" && ["text", "attachments", "quotes", "agent_identity", "target"].includes(column ?? "")) ||
       (table === "letters" && ["text", "attachments", "letter"].includes(column ?? ""))) ? constants.SQLITE_DENY : constants.SQLITE_OK);
    const handle = surface as unknown as { handle(method: string, params: unknown): Promise<{ pending: number }> };
    assert.equal((await handle.handle("task.status", { task: "task1" })).pending, 2);
    rig.store.db.setAuthorizer(null);
    rig.store.markDelivered(key, [{ thread: thread.id, n: message, apart: false }, { thread: thread.id, n: letter, apart: true }]);
    assert.equal((await handle.handle("task.status", { task: "task1" })).pending, 0);
  } finally { rig.store.db.setAuthorizer(null); await rig.close(); }
});
