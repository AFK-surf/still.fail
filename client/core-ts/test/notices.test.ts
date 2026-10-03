// The Rust core's notices.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { BODY, Notices, body } from "../src/notices.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { Workspaces } from "../src/workspace.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

function row(state: string | null, seq: number, unread: boolean, by: [string, string]): J {
  const [process, declared, outcome] =
    state === "run" ? ["running", null, "completed"] : state === "block" ? ["warm", "block", "completed"] : state === "failed" ? ["warm", null, "failed"] : ["warm", "final", "completed"];
  return {
    id: "ds:C1:1.2", session: "ds:C1:1.2", thread: 7, title: "部署挂了", mine: true, unread, connect: null,
    agents: [{ key: "ds:C1:1.2", model: "gpt-6-astra", runtime: "codex", process, pending: 0, lastTurn: { declared, outcome } }],
    last: { agentIdentity: { model: "claude-opus-5-5" }, seq, authorKind: by[0], author: by[1], authorName: null, text: "修好了\n  再看看" },
  };
}

/// Notices as the core feeds them: each look tells the rows that changed since the one before (as a write of the
/// station's rows says them, db/account.ts), a station's first rows where it starts from.
class Looked {
  readonly #notices: Notices;
  readonly #rows: Map<string, J[]>;
  readonly #was = new Map<string, Map<string, J>>();
  constructor(notices: Notices, rows: Map<string, J[]>) {
    this.#notices = notices;
    this.#rows = rows;
  }
  look(stations: string[]): J[] {
    this.#notices.keep(stations);
    // What is no longer reached goes from the device (Data.retain): when it is again, its rows are its first.
    for (const station of [...this.#was.keys()]) if (!stations.includes(station)) this.#was.delete(station);
    const added: J[] = [];
    for (const station of stations) {
      const now = new Map((this.#rows.get(station) ?? []).map((r) => [r.id as string, r]));
      const was = this.#was.get(station);
      const changes = [...now].filter(([id, r]) => JSON.stringify(was?.get(id)) !== JSON.stringify(r)).map(([id, r]) => ({ id, before: was?.get(id), after: r }));
      for (const [id, r] of was ?? []) if (!now.has(id)) changes.push({ id, before: r, after: undefined });
      this.#was.set(station, now);
      if (changes.length > 0) added.push(...this.#notices.changed(station, changes, was === undefined));
    }
    return added;
  }
  value(workspace: string | null): J {
    return this.#notices.value(workspace);
  }
}

function setup() {
  const host = new FakeHost();
  const rows = new Map<string, J[]>();
  const notices = new Looked(
    new Notices({
      workspaces: new Workspaces(host, new Runner(host.time.clock)),
      members: () => [],
      slackUsers: () => [],
      emailOf: () => "me@x.y",
      now: () => host.nowMs(),
    }),
    rows,
  );
  return { rows, notices };
}

const kinds = (n: Looked) => n.value(null).items.map((i: J) => i.kind);
const agent: [string, string] = ["agent", "ds:C1:1.2"];

test("a_reply_seen_while_running_is_noticed_once_when_the_turn_settles", () => {
  const { rows, notices } = setup();
  const stations = ["ws/st"];
  rows.set("ws/st", [row(null, 3, true, agent)]);
  notices.look(stations);
  for (const state of ["run", null]) {
    rows.set("ws/st", [row(state, 3, true, agent)]);
    notices.look(stations);
  }
  assert.deepEqual(kinds(notices), []);
  rows.set("ws/st", [row("run", 4, true, agent)]);
  notices.look(stations);
  notices.look(stations);
  assert.deepEqual(kinds(notices), []);
  rows.set("ws/st", [row(null, 4, true, agent)]);
  notices.look(stations);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done"]);
  rows.set("ws/st", [row("run", 5, true, agent)]);
  notices.look(stations);
  rows.set("ws/st", [row(null, 5, false, agent)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done"]);
});

test("a_chat_of_mine_is_noticed_as_it_changes_and_not_for_how_it_was_at_first", () => {
  const { rows, notices } = setup();
  const stations = ["ws/st"];
  rows.set("ws/st", [row("block", 3, true, agent)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), []);
  rows.set("ws/st", [row("run", 4, true, agent)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), []);
  rows.set("ws/st", [row(null, 5, true, agent)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done"]);
  const n = notices.value(null).items[0];
  assert.equal(n.body, "Opus 5.5: 修好了 再看看");
  assert.equal(n.tag, "ws/st/ds:C1:1.2");
  assert.equal(n.url, "/o/ws/st/ds%3AC1%3A1.2");
  assert.equal(n.title, "部署挂了");
  notices.look(stations);
  assert.equal(kinds(notices).length, 1);
  rows.set("ws/st", [row(null, 6, false, ["person", "me@x.y"])]);
  notices.look(stations);
  rows.set("ws/st", [row("block", 7, true, agent)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done", "block"]);
  assert.ok(notices.value(null).items[1].body.startsWith("要你帮忙 · 修好了"));
  rows.set("ws/st", [row(null, 8, true, ["person", "you@x.y"])]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done", "block", "message"]);
  const failed = row("failed", 9, true, ["ember", "ember"]);
  failed.last.text = "⚠️ 无法启动 agent：没有 claude";
  rows.set("ws/st", [failed]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["done", "block", "message", "failed"]);
  assert.equal(notices.value(null).items[3].body, "出错了 · 无法启动 agent：没有 claude");
});

test("chats_not_mine_and_slack_threads_are_not_noticed", () => {
  const { rows, notices } = setup();
  const stations = ["ws/st"];
  rows.set("ws/st", []);
  notices.look(stations);
  const theirs = { ...row("block", 2, true, agent), mine: false };
  const slack = { ...row("block", 2, true, agent), id: "other", connect: "ds" };
  rows.set("ws/st", [theirs, slack]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), []);
});

test("a_workspace_hears_of_its_own_chats_only", () => {
  const { rows, notices } = setup();
  const stations = ["w1/st", "w2/st"];
  rows.set("w1/st", [row("run", 3, true, agent)]);
  rows.set("w2/st", [row("run", 3, true, agent)]);
  notices.look(stations);
  rows.set("w1/st", [row(null, 4, true, agent)]);
  const added = notices.look(stations);
  assert.equal(added.length, 1);
  assert.equal(notices.value("w1").items[0].workspace, "w1");
  assert.deepEqual(notices.value("w2").items, []);
  rows.set("w2/st", [row("block", 5, true, agent)]);
  notices.look(stations.slice(0, 1));
  notices.look(stations);
  assert.deepEqual(notices.value("w2").items, []);
  assert.deepEqual(kinds(notices), ["done"]);
});

test("a_decision_newly_waiting_for_me_is_noticed_once", () => {
  const { rows, notices } = setup();
  const stations = ["ws/st"];
  const w = (decision: J, seq: number) => ({ ...row("block", seq, false, agent), decision });
  const asked = (seq: number, text: string): J => ({ seq, options: [{ label: "A" }], message: { seq, text } });
  rows.set("ws/st", [w(asked(3, "旧的？"), 3)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), []);
  rows.set("ws/st", [w(asked(5, "**合吗？**\n细节"), 5)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["wait"]);
  assert.equal(notices.value(null).items[0].body, "等你决定 · 合吗？");
  notices.look(stations);
  assert.equal(kinds(notices).length, 1);
  const dismissed = { ...asked(6, "这个？"), dismissed: true };
  rows.set("ws/st", [w(dismissed, 6)]);
  notices.look(stations);
  assert.equal(kinds(notices).length, 1);
  rows.set("ws/st", [w(asked(7, "那这个？"), 7)]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["wait", "wait"]);
  const typed = { ...row("run", 8, false, agent), card: { seq: 8, card: { type: "text" }, message: { seq: 8, text: "域名填哪个？" } } };
  rows.set("ws/st", [typed]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["wait", "wait", "wait"]);
  assert.equal(notices.value(null).items[2].body, "等你决定 · 域名填哪个？");
});

test("needing_help_is_told_by_what_it_needs", () => {
  const { rows, notices } = setup();
  const stations = ["ws/st"];
  rows.set("ws/st", [row("run", 3, false, agent)]);
  notices.look(stations);
  const needs = row("block", 4, true, agent);
  needs.agents[0].lastTurn.need = "要 Stripe 的测试 key";
  rows.set("ws/st", [needs]);
  notices.look(stations);
  assert.deepEqual(kinds(notices), ["block"]);
  assert.equal(notices.value(null).items[0].body, "要你帮忙 · 要 Stripe 的测试 key");
});

test("bodies_are_one_short_line", () => {
  assert.equal(body("done", "Claude", "a\n\n b"), "Claude: a b");
  assert.equal(body("failed", "Claude", ""), "出错了");
  assert.equal(body("wait", "", "设置页间距"), "等你决定 · 设置页间距");
  const long = body("message", "x", "字".repeat(300));
  assert.equal(Array.from(long).length, BODY);
  assert.ok(long.endsWith("…"));
});
