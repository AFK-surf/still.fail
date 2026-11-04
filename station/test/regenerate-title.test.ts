import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { newSession, say } from "../src/sessions/lifecycle.ts";
import { regenerateTitle, TitleError } from "../src/sessions/regenerate-title.ts";
import { completeTitle, titleCompletion } from "../src/sessions/title-completion.ts";
import { newMessage } from "../src/store/store.ts";
import { Rig, settle } from "./hub-fakes.ts";

test("a generated title replaces a manual name without changing the agent's state", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "codex", createdBy: "a@x" });
    r.store.insertMessage(newMessage(thread.id, "1.1", "person", "a@x", "帮我修登录页"));
    r.store.setThreadTitle(thread.id, "旧名称");
    r.store.startTurn("task", key, "input");
    r.store.endTurn("task", "completed", null, "need_human", null);
    const before = r.store.lastTurn(key);
    const result = regenerateTitle(r.hub, thread.id, [r.session(key)]);
    await settle();
    const helper = r.codex.last();
    assert.equal(helper.options.textOnly, true);
    assert.ok(helper.prompts[0]?.includes("帮我修登录页"));
    assert.equal(r.store.getThread(thread.id)?.title, "旧名称");
    helper.says("“登录页修复”\n");
    helper.complete();
    assert.equal(await result, "登录页修复");
    assert.equal(r.store.getThread(thread.id)?.title, null);
    assert.equal(r.store.getThread(thread.id)?.autoTitle, "登录页修复");
    assert.deepEqual(r.store.lastTurn(key), before);
    assert.equal(helper.disposed, true);
  } finally { await r.close(); }
});

test("a later rename or generation wins over an earlier pending result", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "a@x" });
    r.store.insertMessage(newMessage(thread.id, "1.1", "person", "a@x", "hello"));
    const row = r.session(key);
    r.store.setThreadTitle(thread.id, "manual");
    const first = regenerateTitle(r.hub, thread.id, [row]);
    await settle();
    const earlier = r.claude.last();
    // Even writing the same name again is an explicit later choice.
    r.store.setThreadTitle(thread.id, "manual");
    earlier.says("stale"); earlier.complete();
    await assert.rejects(first, (e: unknown) => e instanceof TitleError && e.problem === "changed");
    assert.equal(r.store.getThread(thread.id)?.title, "manual");
    const older = regenerateTitle(r.hub, thread.id, [row]);
    await settle();
    const a = r.claude.last();
    const newer = regenerateTitle(r.hub, thread.id, [row]);
    await settle();
    const b = r.claude.last();
    b.says("new"); b.complete();
    assert.equal(await newer, "new");
    a.says("old"); a.complete();
    await assert.rejects(older, (e: unknown) => e instanceof TitleError && e.problem === "changed");
    assert.equal(r.store.getThread(thread.id)?.autoTitle, "new");
  } finally { await r.close(); }
});

test("a failed generation leaves the old title alone", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "codex", createdBy: "a@x" });
    r.store.insertMessage(newMessage(thread.id, "1.1", "person", "a@x", "hello"));
    r.store.setThreadTitle(thread.id, "manual");
    const result = regenerateTitle(r.hub, thread.id, [r.session(key)]);
    await settle();
    const helper = r.codex.last();
    helper.end({ kind: "failed", reason: "network", message: "unavailable" });
    await assert.rejects(result, (e: unknown) => e instanceof TitleError && e.problem === "failed");
    assert.equal(r.store.getThread(thread.id)?.title, "manual");
    assert.equal(helper.disposed, true);
  } finally { await r.close(); }
});

test("a title can be generated while the chat's agent is working", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "codex", createdBy: "a@x" });
    say(r.hub, thread.id, "a@x", "fix the login");
    await settle();
    const task = r.codex.last();
    const turn = r.store.lastTurn(key);
    assert.equal(task.busy(), true);
    const result = regenerateTitle(r.hub, thread.id, [r.session(key)]);
    await settle();
    const helper = r.codex.last();
    assert.notEqual(helper, task);
    helper.says("Login fix"); helper.complete();
    assert.equal(await result, "Login fix");
    assert.equal(task.busy(), true);
    assert.equal(task.steers.length, 0);
    assert.deepEqual(r.store.lastTurn(key), turn);
  } finally { await r.close(); }
});

test("a keyed chat-completions provider receives a text-only title request", async () => {
  let seen: any;
  const server = createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(Buffer.from(chunk));
    seen = { path: req.url, authorization: req.headers.authorization, body: JSON.parse(Buffer.concat(chunks).toString()) };
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ choices: [{ message: { content: "登录修复" } }] }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const port = (server.address() as { port: number }).port;
    const profile = { id: "local", home: "/tmp", runtime: "dsh", runtimes: ["dsh"], model: "sample", spelling: () => null,
      access: { kind: "api-provider", provider: "ollama", endpoint: `http://127.0.0.1:${port}/v1` } } as any;
    const config = titleCompletion(profile, null, "session")!;
    const title = await completeTitle(config, "only a title", "conversation", AbortSignal.timeout(5000));
    assert.equal(title, "登录修复");
    assert.equal(seen.path, "/v1/chat/completions");
    assert.equal(seen.authorization, undefined);
    assert.equal(seen.body.model, "sample");
    assert.equal(seen.body.tools, undefined);
    assert.deepEqual(seen.body.messages, [{ role: "system", content: "only a title" }, { role: "user", content: "conversation" }]);
    const r = new Rig();
    try {
      r.edit((raw) => raw.profiles.push({ id: "local", runtime: "dsh", home: "homes/local", model: "sample",
        access: { kind: "api-provider", provider: "ollama", endpoint: `http://127.0.0.1:${port}/v1` } }));
      const [key, thread] = newSession(r.hub, { runtime: "dsh", profile: "local", createdBy: "a@x" });
      r.store.insertMessage(newMessage(thread.id, "1.1", "person", "a@x", "修复登录"));
      assert.equal(await regenerateTitle(r.hub, thread.id, [r.session(key)]), "登录修复");
      assert.equal(r.store.getThread(thread.id)?.autoTitle, "登录修复");
    } finally { await r.close(); }
  } finally { await new Promise<void>((resolve, reject) => server.close((e) => e ? reject(e) : resolve())); }
});
