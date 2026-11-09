import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { Store } from "../src/store/store.ts";

test("a new station's overview reads session counts without recounting its sessions", async () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("BEGIN");
    for (let i = 0; i < 1536; i++) {
      const key = `session-${i}`;
      store.insertSession({ key, connect: i % 2 ? "a" : "b", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: i, lastActiveAt: i, ws: i < 512 ? "mine" : i < 768 ? null : "elsewhere" });
    }
    db.exec("COMMIT");
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }) };
    const cloud: any = { state: null };
    const config = () => ({ connects: ["a", "b"].map((id) => ({ id, workspace: "mine" })) });
    const viewer = { sub: "s", email: "person@example.test", name: "P", role: "member" as const,
      workspace: "mine", device: "d", home: false };
    // No process needs a session row in this fixture. A ready count must come from its maintained totals.
    db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "sessions"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    const joined: any = await overview({ store, hub, cloud, config }, viewer, "en");
    assert.equal(joined.counts.sessions, 512);
    assert.deepEqual(joined.connects.map((connect: any) => connect.sessions), [256, 256]);
    const home: any = await overview({ store, hub, cloud, config }, { ...viewer, home: true }, "en");
    assert.equal(home.counts.sessions, 768);
    assert.deepEqual(home.connects.map((connect: any) => connect.sessions), [384, 384]);
    assert.equal(store.sessionCounts().reduce((n, row) => n + row.n, 0), 1536);
  } finally { db.setAuthorizer(null); store.close(); }
});
