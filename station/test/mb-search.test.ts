// The search by the MoonBit program (station/mb, src/search; search/search.ts) finds what search/worker.ts finds: on
// the same station (its own chats and Slack threads named every way, messages with files, agents' identities with and
// without their runtime, archived and hidden chats, jobs of many sessions, memory and skills of the home workspace and a
// joined one, profiles), for each asker, kind, page and word (cased beyond ASCII too), before and after the candidate
// scopes and the session list are prepared, the same groups.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import type { Asker } from "../src/search/match.ts";
import { Search } from "../src/search/search.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

function station() {
  const data = mkdtempSync(join(tmpdir(), "mb-search-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const session = (key: string, ws: string | null, extra: Record<string, unknown> = {}) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, ws, ...extra } as Parameters<Store["insertSession"]>[0]);
  let ts = 0;
  const say = (thread: number, text: string, kind: "person" | "agent" = "person", author = "a@x", extra: Record<string, unknown> = {}) =>
    store.insertMessage({ ...newMessage(thread, String(++ts), kind, author, text), ...extra } as ReturnType<typeof newMessage>);
  // Own chats: named, auto-named, unnamed; Slack threads by their first line, mentions, a direct message.
  session("own", "W1"); session("auto", "W1"); session("plain", null); session("slack", "W2", { connect: "slack" });
  session("dm", "W2", { connect: "slack" }); session("gone", "W1"); session("old", "W1", { runtime: "codex" });
  const own = store.openThreadOf("ember", "ember", "own", null, "a@x", "own").id;
  store.joinThread(own, "own", "ember");
  store.db.prepare("UPDATE threads SET title = '  Σίσυφος  Plan ' WHERE id = ?").run(own);
  const auto = store.openThreadOf("ember", "ember", "auto", null, "a@x", "auto").id;
  store.joinThread(auto, "auto", "ember");
  store.setAutoTitle(auto, "İstanbul trip ΟΔΟΣ", true);
  const plain = store.openThreadOf("ember", "ember", "plain", null, "a@x", "plain").id;
  store.joinThread(plain, "plain", "ember");
  const slack = store.openThread("slack:T1", "C123", "1.1", null, "a@x").id;
  store.joinThread(slack, "slack", "slack");
  const dm = store.openThread("slack:T1", "D999", "2.2", null, "a@x").id;
  store.joinThread(dm, "dm", "slack");
  const orphan = store.openThread("slack:T1", "C777", "3.3", null, "a@x").id;
  for (const [thread, texts] of [[own, ["deploy the KelvinK build", "  ", "naïve café plan"]], [auto, ["İstanbul ΟΔΟΣ plan", "ΑΣ plan"]],
    [plain, ["plan with\ttabs and　spaces", "nothing"]], [slack, ["<@U12AB> plan the   release\nsecond", "plan again"]],
    [dm, ["<@x> plan dm"]], [orphan, ["plan orphan"]]] as const) for (const t of texts) say(thread as number, t);
  say(own, "", "person", "a@x", { attachments: [{ name: "plan.pdf", path: "/p", size: 1 }, { name: "", path: "/q", size: 2 }] });
  say(own, "agent plan reply", "agent", "own", { agentIdentity: { model: "opus", effort: null } });
  say(own, "agent plan with runtime", "agent", "own", { agentIdentity: { runtime: "codex", model: "gpt" } });
  say(own, "agent plan no identity", "agent", "old");
  say(auto, "agent plan of a gone session", "agent", "nobody");
  for (let i = 0; i < 300; i++) say(plain, i % 7 === 0 ? `plan batch ${i}` : `filler ${i}`);
  // Archived: a hidden chat and one whose sessions are archived.
  store.db.prepare("UPDATE threads SET hidden_at = 5 WHERE id = ?").run(dm);
  store.db.prepare("UPDATE sessions SET archived_at = 9 WHERE key = 'plain'").run();
  // Jobs of many sessions.
  for (let i = 0; i < 70; i++) {
    const key = i % 3 === 0 ? "own" : i % 3 === 1 ? "slack" : `s-${i}`;
    if (key.startsWith("s-")) session(key, i % 2 === 0 ? "W1" : null);
    store.insertJob({ id: `job-${i}`, sessionKey: key, name: i % 5 === 0 ? `plan job ${i}` : `job ${i}`, command: `run plan ${i}`, cwd: i % 4 === 0 ? "" : `/c/${i}`,
      port: i % 6 === 0 ? 3000 + i : null, token: `t-${i}`, state: "running", pgid: null, exitCode: null, startedAt: 1000 + (i % 9), endedAt: null,
      restarts: 0, log: "", watch: false });
  }
  // Memory and skills, the home workspace's and W1's; profiles.
  const agent = join(data, "agent");
  const skill = (home: string, name: string, text: string, files: Record<string, string> = {}) => {
    mkdirSync(join(home, "skills", name), { recursive: true });
    writeFileSync(join(home, "skills", name, "SKILL.md"), text);
    for (const [f, t] of Object.entries(files)) writeFileSync(join(home, "skills", name, f), t);
  };
  mkdirSync(agent, { recursive: true });
  writeFileSync(join(agent, "MEMORY.md"), "﻿- always plan ahead\n");
  skill(agent, "deploy", "---\ndescription: \"项目记忆：plan deploys\"\n---\nbody", { "b.md": "plan b", "a.md": "plan a", "SKILL.conflict-1.md": "plan x", "c.txt": "plan" });
  skill(agent, "stillfail-jobs", "---\ndescription: run jobs plan\n---\n");
  skill(agent, "zeta", "no front plan");
  skill(agent, "alpha", "---\r\ndescription: alpha\r\n---\r\nplan");
  writeFileSync(join(agent, "skills", "bad.md"), "plan");
  skill(join(agent, "workspaces", "W1"), "w1skill", "---\ndescription: W1 plan\n---\n");
  writeFileSync(join(agent, "workspaces", "W1", "MEMORY.md"), "W1 plan memory");
  mkdirSync(join(agent, "workspaces", "bad id"), { recursive: true });
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [
    { id: "cc", home: "homes/cc", runtime: "claude", name: "Plan Claude", access: { kind: "api", provider: "anthropic" } },
    { id: "cx", home: "/abs", runtime: "codex", model: "plan-model" }, { id: 3, home: "x" }, { id: "nohome" },
  ] }));
  return { data, store, close: () => { store.close(); rmSync(data, { recursive: true, force: true }); } };
}

const askers: Asker[] = [
  { workspace: "W1", home: true, scopes: ["write"] }, { workspace: "W2", home: false, scopes: [] }, { workspace: "*", home: false, scopes: [] },
];
const queries = ["plan", "PLAN agent", "σίσυφος", "i̇stanbul", "οδος", "ας", "kelvinK", "café", "batch", "job", "release", "nothing at all", "   ", "a b c d e f g h i j"];
const optionSets: { kinds?: string[]; limit?: number; offset?: number; archived?: boolean }[] = [
  {}, { kinds: ["message"], limit: 3, offset: 2 }, { kinds: ["chat"] }, { kinds: ["job"], limit: 5 }, { kinds: ["skill", "memory"] },
  { kinds: ["profile"] }, { archived: true }, { limit: 200, offset: 40 },
];

async function all(search: Search) {
  const out: unknown[] = [];
  for (const asker of askers) for (const q of queries) for (const o of optionSets) out.push(await search.query(q, asker, o).then((f) => f.groups, (e: Error) => e.message));
  return out;
}

test("the MoonBit search finds what the worker finds", { skip: binary === null ? "the MoonBit program is not built here" : false, timeout: 300_000 }, async () => {
  const f = station();
  const worker = new Search({ data: f.data, mb: null }), program = new Search({ data: f.data });
  worker.start(); program.start();
  try {
    // The candidate scopes and session list not prepared yet: the original walks.
    const before = await all(program);
    assert.deepEqual(before, await all(worker));
    // Prepared (each asked for by a search above): the scoped walks.
    for (let i = 0; i < 100; i++) {
      const ready = f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'search_scope_meta'").get() !== undefined
        && (f.store.db.prepare("SELECT threads_done AND members_done AS done FROM search_scope_meta").get() as { done: number }).done === 1;
      if (ready) break;
      await program.query("plan", askers[0]!);
    }
    const after = await all(program);
    assert.deepEqual(after, await all(worker));
    const counted = JSON.stringify(after);
    for (const kind of ["chat", "message", "job", "skill", "memory", "profile"]) assert.ok(counted.includes(`"kind":"${kind}"`), kind);
  } finally {
    await worker.stop(); await program.stop();
    f.close();
  }
});
