import assert from "node:assert/strict";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { sessionChatReady, SessionChatPreparation } from "../src/store/session-chat-index.ts";
import { Store } from "../src/store/store.ts";

test("the overview prepares the names it needs together before reading them", async () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, title] of [["s1", "First"], ["s2", "Second"], ["elsewhere", "Other"]]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
      const thread = store.openThread("ember", "EMBER", key, title, null);
      store.joinThread(thread.id, key, "ember");
    }
    const requests: string[][] = [];
    const original = store.sessionChat.bind(store);
    store.sessionChat = (session) => {
      assert.ok(sessionChatReady(store.db, session), `the overview read ${session} before preparation`);
      return original(session);
    };
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }),
      prepareSessionChatNames: async (sessions: string[]) => {
        requests.push([...sessions]);
        const preparation = new SessionChatPreparation();
        for (const session of sessions) while (!preparation.step(store.db, session).done) {}
      } };
    let made = 0;
    const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
      decisionModels: () => [], automaticDecisionsView: (_viewer: unknown, options: any) => {
        made++;
        return { recent: ["s1", "s2", "s1"].map((session) => ({ session, title: options.title(session) })) };
      } };
    const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
      workspace: "mine", device: "d", home: false };
    const result: any = await overview({ store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) }, viewer, "en");
    assert.deepEqual(result.automaticDecisions.recent.map((row: any) => row.title), ["First", "Second", "First"]);
    assert.deepEqual(requests, [["s1", "s2"]], "the overview requests its names once, without unrelated sessions");
    assert.equal(made, 1, "building the view is not repeated to find its names");
  } finally { store.close(); }
});
