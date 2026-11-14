// The station's driver plugin in DeepSeek Harness (src/agents/dsh-bridge.mjs) on its own lines, in a made-up dsh: a
// loader that has settled when the test says, with the plugin for the station's tools as the test leaves it, and agents
// that record what they are given. It holds that no session is made, so no prompt reaches an agent, before that plugin
// is up, and that `open` is refused, saying why, where it failed, was not loaded or did not start.
//
// What it cannot hold is dsh's side of it: that a real dsh's MCP client has the station's tools registered once its
// plugin is up, and that its loader says so this way. test/dsh.test.ts does not either (its fake dsh stands for dsh
// and this plugin both); only a real dsh shows it, which no test here runs.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { driver } from "../src/agents/dsh-bridge.mjs";

type Json = any;
/// A plugin as dsh's loader keeps it: its state (Cordis's FiberState) and what waiting for it gives.
type Fiber = { state: number; await(): Promise<unknown> };

const TOOLS = "stillfail-tools";

function dsh() {
  /// What was asked of dsh, in order.
  const asked: string[] = [];
  /// What the driver wrote, in order.
  const said: Json[] = [];
  let settle!: () => void;
  const settled = new Promise<void>((done) => (settle = done));
  const tools: { options: { id: string }; fiber?: Fiber } = { options: { id: TOOLS } };
  const handle = (id: string) => ({
    agent: { id: `agent-${id}`, session: { id }, followup: (m: Json) => void asked.push(`prompt ${m.content[0].text}`) },
    dispose: async () => {},
  });
  const ctx = {
    on() {},
    loader: {
      // Until everything is imported and started (or has failed to).
      await: () => {
        asked.push("loader settled?");
        return settled;
      },
      *entries() {
        yield { options: { id: "acp", disabled: true } };
        yield tools;
      },
    },
    agents: {
      create: async (o: Json) => (asked.push("create"), handle(o.sessionId)),
      resume: async (o: Json) => (asked.push(`resume ${o.resumeSessionId}`), handle(o.resumeSessionId)),
    },
  };
  const d = driver(ctx, { tools: TOOLS }, (message) => void said.push(message));
  return {
    asked,
    /// What the driver wrote so far.
    said: (): Json[] => [...said],
    line: (message: Json) => d.line(JSON.stringify(message)),
    /// dsh's loader has settled, the plugin for the station's tools left as `fiber` (none: never loaded).
    settled(fiber?: Fiber) {
      if (fiber) tools.fiber = fiber;
      settle();
    },
  };
}

/// The plugin for the station's tools up (its `apply` returned: the tools are registered), failed, or never started.
const up = (asked: string[]): Fiber => ({ state: 2, await: async () => void asked.push("tools up?") });
const failed = (error: Error): Fiber => ({ state: 3, await: () => Promise.reject(error) });
const pending = (): Fiber => ({ state: 0, await: async () => {} });

describe("the station's driver in DeepSeek Harness", () => {
  test("no session is made, and no prompt taken, before the station's tools are up", async () => {
    const d = dsh();
    const opening = d.line({ id: "open", op: "open", cwd: "/w", provider: "stillfail", model: "m1" });
    // It waits on dsh's loader: nothing made, nothing answered.
    assert.deepEqual(d.asked, ["loader settled?"]);
    assert.deepEqual(d.said(), []);
    // A prompt meanwhile reaches no agent.
    await d.line({ id: "p0", op: "prompt", text: "early" });
    assert.deepEqual(d.said(), [{ id: "p0", error: "no session is open" }]);
    assert.deepEqual(d.asked, ["loader settled?"]);

    d.settled(up(d.asked));
    await opening;
    assert.deepEqual(d.asked, ["loader settled?", "tools up?", "create"]);
    assert.equal(d.said().length, 2);
    assert.equal(d.said()[1].id, "open");
    assert.match(d.said()[1].session, /^[0-9a-f-]{36}$/);

    await d.line({ id: "p1", op: "prompt", text: "hi" });
    assert.deepEqual(d.asked.slice(3), ["prompt hi"]);
    assert.deepEqual(d.said()[2], { id: "p1" });
  });

  test("a session resumed waits for them the same", async () => {
    const d = dsh();
    const opening = d.line({ id: "open", op: "open", cwd: "/w", resume: "s1" });
    assert.deepEqual(d.asked, ["loader settled?"]);
    d.settled(up(d.asked));
    await opening;
    assert.deepEqual(d.asked, ["loader settled?", "tools up?", "resume s1"]);
    assert.deepEqual(d.said(), [{ id: "open", session: "s1" }]);
  });

  test("open is refused, saying why, where the station's tools did not come up", async () => {
    // dsh's MCP client with failOnStartupError: the reason is in the causes.
    const unreachable = new Error("mcp-client(stillfail): initial connection or tool synchronization failed", {
      cause: new Error("fetch failed", { cause: new Error("connect ECONNREFUSED 127.0.0.1:4750") }),
    });
    const cases: [Fiber | undefined, string][] = [
      [failed(unreachable), "the station's tools could not be mounted (mcp-client(stillfail): initial connection or tool synchronization failed: fetch failed: connect ECONNREFUSED 127.0.0.1:4750)"],
      // Its module not imported, or the entry disabled: dsh's loader keeps no plugin for it.
      [undefined, "dsh did not load its plugin stillfail-tools (the station's tools)"],
      // Waiting for a service nobody provides.
      [pending(), "dsh did not start its plugin stillfail-tools (the station's tools)"],
    ];
    for (const [fiber, error] of cases) {
      const d = dsh();
      const opening = d.line({ id: "open", op: "open", cwd: "/w" });
      d.settled(fiber);
      await opening;
      assert.deepEqual(d.said(), [{ id: "open", error }]);
      // No session: a prompt reaches no agent.
      await d.line({ id: "p1", op: "prompt", text: "hi" });
      assert.deepEqual(d.said()[1], { id: "p1", error: "no session is open" });
      assert.deepEqual(d.asked, ["loader settled?"]);
    }
  });
});
