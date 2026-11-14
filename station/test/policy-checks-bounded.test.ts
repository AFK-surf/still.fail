// An archive policy's checks counted by a reader (read/policy-checks.ts): as the main thread counted them, and what
// the main thread is given back is as large whatever the number of chats checked.
import assert from "node:assert/strict";
import { test } from "node:test";
import { policyChecks, policySince } from "../src/sessions/archive-policy.ts";
import { policyChecksRead } from "../src/read/policy-checks.ts";
import { Store } from "../src/store/store.ts";

test("a reader counts a week's checks as the main thread did, and gives back the latest twenty chats of each option at most", () => {
  const sizes: number[] = [];
  for (const chats of [100, 1000]) {
    const store = Store.open(":memory:");
    try {
      const now = store.now();
      const insert = store.db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
      for (let i = 0; i < chats; i++) {
        const ws = i % 3 === 0 ? "elsewhere" : "mine";
        store.insertSession({ key: `s${i}`, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: `t${i}`, createdAt: 1, lastActiveAt: 1, ws });
        // An older check, the latest, and one from before the week.
        insert.run(`s${i}`, now - 3 * 86_400_000, JSON.stringify({ result: { selected: "agent_work" } }));
        insert.run(`s${i}`, now - 86_400_000 + i, JSON.stringify(i % 5 === 0 ? { error: "unreachable" } : { result: { selected: i % 2 === 0 ? "complete" : "human_needed" }, accepted: i % 4 === 0 }));
        insert.run(`s${i}`, now - 30 * 86_400_000, JSON.stringify({ result: { selected: "uncertain" } }));
      }
      for (const viewer of [{ workspace: "mine", home: false }, { workspace: "mine", home: true }]) {
        const read = policyChecksRead(store.db, policySince(now), viewer);
        const here = policyChecks(store.latestDecisionsSince(policySince(now), viewer), (session) => store.getSession(session)?.ws === "mine" || (viewer.home && store.getSession(session)?.ws == null));
        assert.deepEqual(read, here);
        for (const option of Object.values(read!.options)) assert.ok(option.chats.length <= 20);
      }
      sizes.push(JSON.stringify(policyChecksRead(store.db, policySince(now), { workspace: "mine", home: false })).length);
    } finally {
      store.close();
    }
  }
  // Ten times the chats: the counts grow a digit, the chats given back stay twenty an option.
  assert.ok(sizes[1]! - sizes[0]! < 400, sizes.join(" "));
});
