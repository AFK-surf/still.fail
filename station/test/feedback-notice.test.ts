// A failure notice reported from the chat (src/feedback/notice.ts): the report made of what the station knows of it
// (the notice, the failed turn, the agent, versions, the names of the agents' variables, the session's log lines),
// sent once per notice, and refused for what is not a failure notice.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { REPORT_PATH, logLines, reportRoutes } from "../src/feedback/notice.ts";
import { StationParts } from "../src/parts.ts";
import { Store, newMessage } from "../src/store/store.ts";

const member = { sub: "u", email: "ada@x.com", name: "Ada", role: "member", workspace: "w", device: "d" };
const viewer = { ...member, sub: "v", role: "viewer" };
const readers: any = { names: new Map(), read: async () => "{}" };

function ask(admin: Admin, who: typeof member, path: string, body: unknown) {
  const r: Request = { method: "POST", path, query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer: who, lang: "en" };
  return admin.handle(r).then((a) => [a.status, JSON.parse(String(a.body))] as const);
}

test("a failure notice reported: the turn, the agent, versions, variables' names and the session's log lines go", async () => {
  const store = Store.open(":memory:", null);
  try {
    store.insertSession({ key: "ember:c-aaa111", connect: "ember", runtime: "codex", profile: "pro", model: "gpt-6", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" } as any);
    store.setRuntimeSessionId("ember:c-aaa111", "019a-codex-thread");
    store.insertSession({ key: "other", connect: "ember", runtime: "claude", profile: "cc", workspace: "/o", token: "t2", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" } as any);
    const chat = store.openThread("ember", "EMBER", "1.1", null, "ada@x.com");
    store.joinThread(chat.id, "ember:c-aaa111", "ember");
    store.insertMessage(newMessage(chat.id, "1.2", "person", "ada@x.com", "fix it"));
    store.startTurn("t1", "ember:c-aaa111", "message");
    store.endTurn("t1", "failed", "other: workspace routing discovery timed out", null, null);
    store.insertMessage(newMessage(chat.id, "1.3", "ember", "ember", "⚠️ 本轮出错：workspace routing discovery timed out\nmore"));
    const notice = store.lastEntry(chat.id);
    store.insertMessage(newMessage(chat.id, "1.4", "ember", "ember", "已停止当前任务"));
    const calm = store.lastEntry(chat.id);

    const at = (ms: number) => new Date(Date.now() + ms).toISOString();
    const log = [
      `${at(-3_600_000)}  WARN agents::codex: codex turn error thread=019a-codex-thread error=old`,
      `${at(-1000)}  INFO session: turn started session=ember:c-aaa111`,
      `${at(-900)}  WARN agents::codex: codex turn error thread=019a-codex-thread error={"message":"workspace routing discovery timed out"} cwd=/Users/ada/work`,
      `${at(-800)}  WARN agents::codex: a codex app-server not replaced profile=pro error=busy`,
      `${at(-700)}  INFO session: turn started session=other`,
      `${at(-600)}  INFO mesh: not held`,
    ].join("\n");
    const sent: any[] = [];
    const parts = new StationParts();
    const deps = { logTail: () => log, versions: () => ({ station: "0.1.3600", codex: "0.160.0" }), envNames: () => ["HTTPS_PROXY", "HTTP_PROXY"], link: (k: string) => `https://app/o/${k}`, home: "/Users/ada" };
    parts.routes(reportRoutes(store, deps, async (report) => (sent.push(report), sent.length === 1 ? { number: 12 } : { number: 12, duplicate: true })));
    parts.viewerMay((r) => r.method === "POST" && REPORT_PATH.test(r.path));
    const admin = new Admin(readers, { parts, store });

    assert.deepEqual(await ask(admin, member, `/threads/${chat.id}/report`, { n: notice }), [200, { number: 12 }]);
    const report = sent[0];
    assert.equal(report.title, "本轮出错：workspace routing discovery timed out");
    assert.equal(report.area, "station");
    assert.equal(report.reporter, "Ada (ada@x.com), from the chat");
    assert.match(report.body, /> 本轮出错：workspace routing discovery timed out\n> more/);
    assert.match(report.body, /\*\*Failure\*\*: other: workspace routing discovery timed out/);
    assert.match(report.body, /\*\*Agent\*\*: codex, profile pro, model gpt-6/);
    assert.match(report.body, /station 0\.1\.3600, codex 0\.160\.0/);
    assert.match(report.body, /names only\): HTTPS_PROXY, HTTP_PROXY/);
    assert.deepEqual(
      { ...report.context, notice: undefined },
      { notice: undefined, os: report.context.os, arch: report.context.arch, software: { station: "0.1.3600", codex: "0.160.0" }, agentEnv: ["HTTPS_PROXY", "HTTP_PROXY"], session: "ember:c-aaa111", connect: "ember", runtime: "codex", profile: "pro", model: "gpt-6", link: "https://app/o/ember:c-aaa111", thread: "EMBER/1.1" },
    );
    // The session's lines of the turn's time: not an hour before, not another session's, not the mesh's; homes scrubbed.
    const lines = report.logs.split("\n");
    assert.equal(lines.length, 3, report.logs);
    assert.match(lines[0], /turn started session=ember:c-aaa111$/);
    assert.match(lines[1], /discovery timed out.*cwd=~\/work$/);
    assert.match(lines[2], /app-server not replaced profile=pro/);

    // The same notice again: the same report (its key), which still.fail cloud keeps once.
    assert.deepEqual(await ask(admin, viewer, `/threads/${chat.id}/report`, { n: notice }), [200, { number: 12, duplicate: true }]);
    assert.equal(sent[1].key, report.key);

    // Not a failure notice, or no such entry.
    assert.equal((await ask(admin, member, `/threads/${chat.id}/report`, { n: calm }))[0], 404);
    assert.equal((await ask(admin, member, `/threads/${chat.id}/report`, { n: 1 }))[0], 404);
    assert.equal((await ask(admin, member, `/threads/${chat.id}/report`, {}))[0], 400);
    assert.equal((await ask(admin, member, `/threads/999/report`, { n: notice }))[0], 404);
    assert.equal(sent.length, 2);
  } finally {
    store.close();
  }
});

test("a report not taken by still.fail cloud is said so", async () => {
  const store = Store.open(":memory:", null);
  try {
    const chat = store.openThread("ember", "EMBER", "2.1", null, "ada@x.com");
    store.insertMessage(newMessage(chat.id, "2.2", "ember", "ember", "⚠️ 本轮出错：boom"));
    const parts = new StationParts();
    const deps = { logTail: () => null, versions: () => ({}), envNames: () => [], link: () => null, home: "/h" };
    parts.routes(reportRoutes(store, deps, async () => { throw new Error("still.fail cloud answered 429: rate_limited"); }));
    const admin = new Admin(readers, { parts, store });
    const [status, answer] = await ask(admin, member, `/threads/${chat.id}/report`, { n: store.lastEntry(chat.id) });
    assert.equal(status, 502);
    assert.match(answer.error, /Couldn't send it to still\.fail: still\.fail cloud answered 429/);
  } finally {
    store.close();
  }
});

test("log lines: the newest kept, under the size the cloud takes", () => {
  const t = Date.parse("2026-10-19T12:00:00Z");
  const many = Array.from({ length: 1000 }, (_, i) => `${new Date(t + i).toISOString()}  INFO session: step ${i} session=k ${"x".repeat(200)}`).join("\n");
  const kept = logLines(many, t, t + 10_000, ["session=k"], "codex", "/h").split("\n");
  assert.ok(kept.length <= 300);
  assert.ok(Buffer.byteLength(kept.join("\n")) <= 48 * 1024);
  assert.match(kept.at(-1)!, /step 999 /);
});
