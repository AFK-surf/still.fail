// Whose workspace keeps a chat's file (`owner`, views.ts drawn): an agent's message's, its own session's, also while
// the chat's agents leave that agent out (its detail not had: refused here, or not answered on a phone's slow link).
import assert from "node:assert/strict";
import { test } from "node:test";
import { subscribe } from "./helpers.ts";
import { base, session, started, status, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const sent = { thread: 7, n: 1, kind: "message", target: null, ts: "1.0", authorKind: "agent", author: "k2", text: "图", at: 1, attachments: [{ name: "a.png", path: "/w2/uploads/a.png", size: 3 }] };

async function drawn(detail: "read" | "refused"): Promise<[string[], string | undefined]> {
  const k1 = { ...session("k1"), workspace: "/w1" };
  const k2 = { ...session("k2"), workspace: "/w2" };
  const thread = { ...threadView(7, 1), sessions: [{ thread: 7, session: "k1", connect: "ember", joinedAt: 1 }, { thread: 7, session: "k2", connect: "ember", joinedAt: 2 }] };
  const answers: J = {
    ...base(),
    "GET /sessions": [k1, k2],
    "GET /sessions/k1": { session: k1, threads: [], turns: [], jobs: [] },
    "GET /sessions/k2": detail === "refused" ? status(404, { error: "unknown session k2" }) : { session: k2, threads: [], turns: [], jobs: [] },
    "GET /threads": [thread],
    "GET /threads/7/entries?limit=50": { last: 1, entries: [sent] },
  };
  const { host, core } = await started(answers);
  const ui = core.connect();
  subscribe(core, ui, 2, { topic: "chat", station: "ws/st", thread: 7 });
  for (let i = 0; i < 10; i++) {
    await host.settle();
    await host.time.pass(5_000);
  }
  const value = host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === 2 && "value" in m).at(-1)?.value;
  core.close();
  return [(value?.agents ?? []).map((a: J) => a.session?.key), value?.messages?.find((m: J) => m.seq === 1)?.attachments?.[0]?.owner];
}

test("an_agents_files_are_kept_by_its_own_session_whether_or_not_the_chat_has_its_detail", async () => {
  assert.deepEqual(await drawn("read"), [["k1", "k2"], "k2"]);
  assert.deepEqual(await drawn("refused"), [["k1"], "k2"]);
});
