import assert from "node:assert/strict";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { sessionChatReady, SessionChatPreparation } from "../src/store/session-chat-index.ts";
import { Store } from "../src/store/store.ts";

test("the overview names a single chat without preparing an index", async () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const thread = store.openThread("ember", "CHAT", "s", "Only chat", null);
    store.joinThread(thread.id, "s", "ember");
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }),
      prepareSessionChatNames: async () => { throw new Error("a single chat should not need preparation"); } };
    const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
      decisionModels: () => [], automaticDecisionsView: (_viewer: unknown, options: any) => ({
        recent: [{ session: "s", title: options.title("s") }],
      }) };
    const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
      workspace: "mine", device: "d", home: false };
    const result: any = await overview({ store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) }, viewer, "en");
    assert.deepEqual(result.automaticDecisions.recent, [{ session: "s", title: "Only chat" }]);
  } finally { store.close(); }
});

test("the overview prepares the names it needs together before reading them", async () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, title] of [["s1", "First"], ["s2", "Second"], ["elsewhere", "Other"]]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
      const older = store.openThread("slack", "C", `${key}-older`, null, null);
      store.joinThread(older.id, key, "slack");
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

test("a session moved to another workspace while names are prepared is not shown", async () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const older = store.openThread("slack", "C", "older", null, null);
    store.joinThread(older.id, "s", "slack");
    const thread = store.openThread("ember", "EMBER", "s", "Private title", null);
    store.joinThread(thread.id, "s", "ember");
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }),
      prepareSessionChatNames: async (sessions: string[]) => {
        const preparation = new SessionChatPreparation();
        for (const session of sessions) while (!preparation.step(store.db, session).done) {}
        // Moved as the station moves a session to another workspace (the one way it is: `setSessionsWs`).
        store.setSessionsWs("mine", "elsewhere");
      } };
    const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
      decisionModels: () => [], automaticDecisionsView: (_viewer: unknown, options: any) => ({
        recent: options.visible("s") ? [{ session: "s", title: options.title("s") }] : [],
      }) };
    const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
      workspace: "mine", device: "d", home: false };
    const result: any = await overview({ store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) }, viewer, "en");
    assert.deepEqual(result.automaticDecisions.recent, []);
  } finally { store.close(); }
});

test("a home-workspace session deleted during name preparation does not keep the overview waiting", async () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1 });
    const older = store.openThread("slack", "C", "older", null, null);
    store.joinThread(older.id, "s", "slack");
    const thread = store.openThread("ember", "CHAT", "s", "Old title", null);
    store.joinThread(thread.id, "s", "ember");
    let requests = 0;
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }),
      prepareSessionChatNames: async () => {
        assert.equal(++requests, 1, "a removed session cannot be prepared again");
        store.deleteSession("s");
      } };
    const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
      decisionModels: () => [], automaticDecisionsView: (_viewer: unknown, options: any) => ({
        recent: options.visible("s") ? [{ session: "s", title: options.title("s") }] : [],
      }) };
    const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
      workspace: "mine", device: "d", home: true };
    const result: any = await overview({ store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) }, viewer, "en");
    assert.deepEqual(result.automaticDecisions.recent, [{ session: "s", title: "s" }]);
    assert.equal(requests, 1);
  } finally { store.close(); }
});
