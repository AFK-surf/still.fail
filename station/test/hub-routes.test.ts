// What the pages ask of the hub, the jobs and the files, as admin/mod.rs and admin/files.rs answer it (routes/hub.ts):
// new chats, uploads, messages, archiving, deleting, stopping, a session's settings, jobs. A real store in a temporary
// data directory, the real readers over it, a hub with runtimes scripted in-process (test/hub-fakes.ts).
import assert from "node:assert/strict";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, basename } from "node:path";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { tr } from "../src/ops/i18n.ts";
import { Readers } from "../src/read/pool.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Hub } from "../src/sessions/hub.ts";
import { InternalChat } from "../src/sessions/internal.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { digest } from "../src/read/digest.ts";
import { openStore } from "../src/read/store.ts";
import { chatRows, chats } from "../src/read/views.ts";
import { isDeepStrictEqual } from "node:util";
import { fileAway } from "./archived-before.ts";
import { FakeDriver, settle } from "./hub-fakes.ts";
import { UsageCounter, claudeProject } from "../src/usage/counter.ts";
import { keepCounted } from "../src/usage/module.ts";

const viewer = { sub: "u", email: "a@x", name: "A", role: "member", workspace: "w", device: "d" };
const en = (key: string, args: Record<string, unknown> = {}) => tr("en", key, args);

/// Looks every 25 ms until `f` holds (no deadline: it comes, however slow the machine, or the test hangs).
async function until(_what: string, f: () => boolean) {
  while (!f()) await new Promise((r) => setTimeout(r, 25));
}

function rig(withAgents = true) {
  const data = mkdtempSync(join(tmpdir(), "hr-"));
  const raw = { profiles: [{ id: "cc", runtime: "claude", home: "homes/cc", models: ["opus"] }, { id: "cx", runtime: "codex", home: "homes/cx" }] };
  const config = hubConfig(raw, data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const claude = new FakeDriver("claude");
  const codex = new FakeDriver("codex");
  const hub = new Hub({
    config: () => config,
    store,
    chats: () => undefined,
    drivers: [claude, codex],
    mcpUrl: "http://127.0.0.1:1/mcp",
    internal: new InternalChat(),
    runners: () => [],
  });
  const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
  hub.setJobs(jobs);
  const readers = new Readers(data, 1);
  readers.processes = () => hub.processes();
  const admin = new Admin(readers, { store, agents: withAgents ? ({ hub, jobs } as any) : undefined });
  const ask = async (method: string, path: string, body?: unknown, query: [string, string][] = []) => {
    const raw = Buffer.isBuffer(body) ? body : Buffer.from(body === undefined ? "" : typeof body === "string" ? body : JSON.stringify(body));
    const r: Request = { method, path, query, headers: {}, body: raw, viewer, lang: "en" };
    const a = await admin.handle(r);
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  const close = async () => {
    await hub.shutdown();
    await jobs.shutdown();
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  };
  return { data, store, hub, jobs, readers, claude, codex, ask, close };
}

test("a new chat: its session and its thread, refused without a runtime or with an unknown profile", async () => {
  const r = rig();
  try {
    assert.deepEqual(await r.ask("POST", "/sessions", { runtime: "gemini" }), [400, { error: en("station.admin.badRuntime") }]);
    assert.deepEqual(await r.ask("POST", "/sessions", "{"), [400, { error: "invalid JSON" }]);
    assert.deepEqual(await r.ask("POST", "/sessions", { runtime: "claude", profile: "nope" }), [400, { error: "no claude profile nope" }]);
    const [status, made] = await r.ask("POST", "/sessions", { runtime: "codex", title: "plans", fast: true, clientKey: "k1", profile: "" });
    assert.equal(status, 200);
    assert.deepEqual(Object.keys(made), ["key", "thread"]);
    const row = r.store.getSession(made.key)!;
    assert.deepEqual([row.runtime, row.profile, row.title, row.createdBy, row.fast], ["codex", "cx", "plans", "a@x", true]);
    assert.equal(made.thread.home, made.key);
    assert.equal(made.thread.title, "plans");
    assert.deepEqual(made.thread.sessions.map((m: any) => m.session), [made.key]);
    assert.equal(r.hub.clientKey(made.key), "k1");
  } finally {
    await r.close();
  }
});

test("retrying a new chat after the station restarts returns the same chat", async () => {
  const r = rig();
  try {
    const ask = { runtime: "codex", clientKey: "new:restart-test" };
    const [, first] = await r.ask("POST", "/sessions", ask);
    // The process-local keys are lost when the station restarts.
    r.hub.clientKeysMade.clear();
    const [, retry] = await r.ask("POST", "/sessions", ask);
    assert.equal(retry.key, first.key);
    assert.equal(retry.thread.id, first.thread.id);
    // A stop between the thread and its membership must also be repaired.
    r.store.db.prepare("DELETE FROM thread_sessions WHERE thread = ?").run(first.thread.id);
    const [, repaired] = await r.ask("POST", "/sessions", ask);
    assert.equal(repaired.thread.id, first.thread.id);
    assert.deepEqual(repaired.thread.sessions.map((m: any) => m.session), [first.key]);
    // A stop after the session but before the thread leaves the same session to finish.
    r.store.db.prepare("DELETE FROM thread_sessions WHERE thread = ?").run(first.thread.id);
    r.store.db.prepare("DELETE FROM threads WHERE id = ?").run(first.thread.id);
    const [, finished] = await r.ask("POST", "/sessions", ask);
    assert.equal(finished.key, first.key);
    assert.deepEqual(finished.thread.sessions.map((m: any) => m.session), [first.key]);
  } finally {
    await r.close();
  }
});

test("a chat's relaying through the routes (docs/relay.md): where to, read past the thread's other actions; to where, checked", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const id = made.thread.id;
    // No connect can take it here: none listed, none relayed through.
    assert.deepEqual(await r.ask("GET", `/threads/${id}/relay`), [200, { connects: [] }]);
    assert.deepEqual(await r.ask("POST", `/threads/${id}/relay`, {}), [400, { error: en("station.relay.pick") }]);
    assert.deepEqual(await r.ask("POST", `/threads/${id}/relay`, { connect: "cl", channel: "C1" }), [400, { error: "connect cl cannot take this chat" }]);
    // Who its note can mention there: asked where, checked as relaying is.
    assert.deepEqual(await r.ask("GET", `/threads/${id}/relay/people`), [400, { error: en("station.relay.pick") }]);
    assert.deepEqual(await r.ask("GET", `/threads/${id}/relay/people`, undefined, [["connect", "cl"], ["channel", "C1"]]), [400, { error: "connect cl cannot take this chat" }]);
    // Another action of a thread is still none.
    assert.deepEqual(await r.ask("GET", `/threads/${id}/nope`), [404, { error: `no route GET /threads/${id}/nope` }]);
  } finally {
    await r.close();
  }
});

test("another chat with a session, and a session brought into a chat", async () => {
  const r = rig();
  try {
    const [, a] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const [, b] = await r.ask("POST", "/sessions", { runtime: "claude" });
    assert.deepEqual(await r.ask("POST", "/threads", { session: "nope" }), [404, { error: "unknown session nope" }]);
    const [status, chat] = await r.ask("POST", "/threads", { session: a.key, title: "  side  " });
    assert.equal(status, 200);
    assert.equal(chat.title, "side");
    assert.equal(chat.home, undefined, "a chat of its own");
    assert.deepEqual(await r.ask("POST", `/threads/${chat.id}/sessions`, { session: "nope" }), [404, { error: "unknown session nope" }]);
    assert.deepEqual(await r.ask("POST", "/threads/999/sessions", { session: b.key }), [404, { error: "unknown thread 999" }]);
    const [joined, view] = await r.ask("POST", `/threads/${chat.id}/sessions`, { session: b.key });
    assert.equal(joined, 200);
    assert.deepEqual(view.sessions.map((m: any) => m.session), [a.key, b.key]);
    const slack = r.store.openThread("slack:T1", "C1", "1.1", null, null);
    assert.deepEqual(await r.ask("POST", `/threads/${slack.id}/sessions`, { session: b.key }), [400, { error: `no still.fail chat ${slack.id}` }]);
    // chat_list's threads, as the readers read them: what the store lists.
    assert.deepEqual(JSON.parse(await r.readers.read("threadList", {}, "en")), JSON.parse(JSON.stringify(r.store.listThreads("", null, null))));
    // The archive review's messages, as the readers read them: what the store has.
    assert.deepEqual(JSON.parse(await r.readers.read("latestMessages", { thread: chat.id, limit: 2 }, "en")), JSON.parse(JSON.stringify(r.store.messagesBefore(chat.id, null, 2))));
  } finally {
    await r.close();
  }
});

test("uploads wait in the station's uploads, a message takes them into its chat and its agent hears it", async () => {
  const r = rig();
  try {
    const staged = join(r.data, "uploads");
    mkdirSync(staged, { recursive: true });
    writeFileSync(join(staged, "old"), "x");
    utimesSync(join(staged, "old"), new Date(Date.now() - 25 * 3600_000), new Date(Date.now() - 25 * 3600_000));
    const [status, up] = await r.ask("POST", "/uploads", Buffer.from("png"), [["name", "dir/..\\.a\u0001.png"]]);
    assert.equal(status, 200);
    assert.deepEqual(Object.keys(up), ["name", "path", "size"]);
    assert.equal(up.name, "a_.png");
    assert.equal(up.size, 3);
    assert.match(up.path, /[\\/]uploads[\\/]\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-[0-9a-f]{6}-a_\.png$/);
    assert.ok(!existsSync(join(staged, "old")), "a day-old upload is swept");
    const [, unnamed] = await r.ask("POST", "/uploads", Buffer.from(""));
    assert.match(unnamed.name, /^file$/);

    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const id = made.thread.id;
    const workspace = r.store.getSession(made.key)!.workspace;
    assert.deepEqual(await r.ask("POST", `/threads/${id}/messages`, { text: "  " }), [400, { error: en("station.admin.emptyMessage") }]);
    assert.deepEqual(await r.ask("POST", `/threads/${id}/messages`, { attachments: [{ path: "/etc/passwd" }] }), [400, { error: en("station.files.notUploaded") }]);
    const send = {
      text: " look ",
      attachments: [{ path: up.path, name: "a_.png", width: 10, height: 20, size: 3 }],
      quotes: [{ text: "earlier", ts: "1.2", role: "agent", file: "a_.png" }, { text: "  " }],
      client: " web\u0007 1.0 ",
    };
    const [sent, said] = await r.ask("POST", `/threads/${id}/messages`, send);
    assert.equal(sent, 200);
    const moved = join(workspace, "uploads", basename(up.path));
    assert.ok(existsSync(moved) && !existsSync(up.path), "moved into the session's uploads");
    assert.equal(readFileSync(moved, "utf8"), "png");
    const message = r.store.messagesBefore(id, null, 10).find((m) => m.n === said.n)!;
    assert.equal(message.text, "look");
    assert.deepEqual(message.attachments, [{ name: "a_.png", path: moved, size: 3, width: 10, height: 20 }]);
    assert.deepEqual(message.quotes, [{ author: "消息", text: "earlier", comment: "", ts: "1.2", role: "agent", file: "a_.png" }]);
    assert.equal(message.client, "web 1.0");
    await settle();
    await until("its turn starts", () => r.claude.count() === 1 && r.claude.last().prompts.length === 1);
    assert.match(r.claude.last().prompts[0]!, /look/);
    // Sent again (a retry): the file has moved already, and is found where it went.
    const [again] = await r.ask("POST", `/threads/${id}/messages`, send);
    assert.equal(again, 200);
    // Named by its place in the uploads when the page gives no name.
    const [, named] = await r.ask("POST", `/threads/${id}/messages`, { attachments: [{ path: moved, width: 5 }] });
    assert.deepEqual(r.store.messagesBefore(id, null, 10).find((m) => m.n === named.n)!.attachments, [{ name: basename(moved), path: moved, size: 0 }]);

    // A PNG sent without its size (the desktop's page could not read it): its header says it.
    const head = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x05, 0xb4, 0, 0, 0, 0x66]);
    const [, strip] = await r.ask("POST", "/uploads", head, [["name", "strip.png"]]);
    const [, unsized] = await r.ask("POST", `/threads/${id}/messages`, { attachments: [{ path: strip.path, name: "strip.png", size: head.length }] });
    const [kept] = r.store.messagesBefore(id, null, 10).find((m) => m.n === unsized.n)!.attachments;
    assert.deepEqual([kept!.width, kept!.height], [1460, 102]);

    const slack = r.store.openThread("slack:T1", "C1", "1.1", null, null);
    assert.deepEqual(await r.ask("POST", `/threads/${slack.id}/messages`, { text: "hi" }), [400, { error: en("station.admin.postOnlyStillfail") }]);
    assert.deepEqual(await r.ask("POST", "/threads/x/messages", { text: "hi" }), [404, { error: "unknown thread x" }]);
    assert.equal((await r.ask("POST", "/uploads", Buffer.alloc(50 * 1024 * 1024 + 1)))[0], 413);
  } finally {
    await r.close();
  }
});

test("a file in parts: each added where the file ends, asked again or out of place it adds nothing, whole it is an upload", async () => {
  const r = rig();
  try {
    const part = (offset: number, body: string, size = 10, id = "abcdefgh12") =>
      r.ask("POST", "/uploads/parts", Buffer.from(body), [["id", id], ["name", "big.bin"], ["size", String(size)], ["offset", String(offset)]]);
    assert.deepEqual(await part(0, "0123"), [200, { have: 4 }]);
    // Its answer lost, asked again: nothing added.
    assert.deepEqual(await part(0, "0123"), [200, { have: 4 }]);
    // Ahead of the file's end: nothing added, the caller goes on from where it is.
    assert.deepEqual(await part(8, "89"), [200, { have: 4 }]);
    // Overlapping the end: only the rest of it added.
    assert.deepEqual(await part(2, "234567"), [200, { have: 8 }]);
    const staged = join(r.data, "uploads");
    assert.equal(readFileSync(join(staged, ".part-abcdefgh12"), "utf8"), "01234567");
    const [status, done] = await part(8, "89");
    assert.equal(status, 200);
    assert.equal(done.have, 10);
    assert.deepEqual([done.file.name, done.file.size], ["big.bin", 10]);
    assert.match(done.file.path, /[\\/]uploads[\\/]\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-[0-9a-f]{6}-big\.bin$/);
    assert.equal(readFileSync(done.file.path, "utf8"), "0123456789");
    assert.ok(!existsSync(join(staged, ".part-abcdefgh12")));
    // The last part asked again after it was put together: the same file.
    assert.deepEqual(await part(8, "89"), [200, done]);
    // A part file is never sent with a message.
    await part(0, "01", 10, "otherid123");
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    assert.deepEqual(await r.ask("POST", `/threads/${made.thread.id}/messages`, { attachments: [{ path: join(staged, ".part-otherid123") }] }), [400, { error: en("station.files.notUploaded") }]);
    // Bounds: the whole file, a part, the id.
    assert.deepEqual(await part(0, "x", 1024 * 1024 * 1024 + 1, "toolarge12"), [413, { error: en("station.files.tooLargeParts") }]);
    assert.equal((await part(0, "x", 10, "../../etc"))[0], 400);
    assert.equal((await part(0, "x".repeat(11), 10, "pastsize12"))[0], 413);
    assert.equal((await r.ask("POST", "/uploads/parts", Buffer.from("x"), [["id", "noquery123"]]))[0], 400);
  } finally {
    await r.close();
  }
});

test("a file sent again is copied from where the station keeps it, and none of it comes again", async () => {
  const r = rig();
  try {
    const sha = (text: string) => createHash("sha256").update(text).digest("hex");
    const ask = (id: string, offset: number, body: string, extra: [string, string][] = []) =>
      r.ask("POST", "/uploads/parts", Buffer.from(body), [["id", id], ["name", "shot.png"], ["size", "10"], ["offset", String(offset)], ...extra]);
    // Not here yet: nothing, and it comes in parts as before.
    assert.deepEqual(await ask("firstone12", 0, "", [["sha256", sha("0123456789")]]), [200, { have: 0 }]);
    await ask("firstone12", 0, "01234");
    const [, first] = await ask("firstone12", 5, "56789");
    // Sent with a message: it moves into the chat's uploads, and is known there.
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    assert.equal((await r.ask("POST", `/threads/${made.thread.id}/messages`, { text: "a", attachments: [first.file] }))[0], 200);
    assert.ok(!existsSync(first.file.path));
    // Sent again: a copy of its own, at once.
    const [status, again] = await ask("secondone1", 0, "", [["sha256", sha("0123456789")]]);
    assert.equal(status, 200);
    assert.equal(again.have, 10);
    assert.notEqual(again.file.path, first.file.path);
    assert.equal(readFileSync(again.file.path, "utf8"), "0123456789");
    // Another content, or a size that is not its: not taken for it.
    assert.deepEqual(await ask("thirdone12", 0, "", [["sha256", sha("x")]]), [200, { have: 0 }]);
    assert.deepEqual(await r.ask("POST", "/uploads/parts", Buffer.alloc(0), [["id", "fourthone1"], ["name", "a"], ["size", "9"], ["offset", "0"], ["sha256", sha("0123456789")]]), [200, { have: 0 }]);
    assert.equal((await ask("fifthone12", 0, "", [["sha256", "nothex"]]))[0], 400);
  } finally {
    await r.close();
  }
});

test("a pending card: an option chosen by an old client is refused; an answer quoting it marks it read", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const id = made.thread.id;
    const [n] = r.store.insertMessage({
      ...newMessage(id, "1700000000.000100", "agent", made.key, "deploy?"),
      card: { type: "options", options: [{ label: "no", action: "close" }, { label: "yes", action: "reply" }] },
    });
    r.store.insertMessage(newMessage(id, "1700000000.000200", "agent", made.key, "later"));
    const quote = [{ text: "deploy?", ts: "1700000000.000100" }];
    assert.deepEqual(await r.ask("POST", `/threads/${id}/messages`, { text: "no", quotes: quote }), [409, { error: en("station.admin.updateClientForOption") }]);
    const [status] = await r.ask("POST", `/threads/${id}/messages`, { text: "yes", quotes: quote });
    assert.equal(status, 200);
    assert.equal(r.store.readPosition("a@x", id), n, "read up to the card, not past it");
  } finally {
    await r.close();
  }
});

test("archiving a session and a chat, and deleting a session", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const [status, summary] = await r.ask("POST", `/sessions/${made.key}/archive`);
    assert.equal(status, 200);
    assert.equal(summary.key, made.key);
    assert.equal(typeof summary.archivedAt, "number");
    assert.equal((await r.ask("DELETE", `/sessions/${made.key}/archive`))[1].archivedAt, null);
    assert.deepEqual(await r.ask("POST", "/sessions/nope/archive"), [404, { error: "unknown session nope" }]);

    const [, own] = await r.ask("POST", "/threads", { session: made.key });
    const [hidden, view] = await r.ask("POST", `/threads/${own.id}/archive`);
    assert.equal(hidden, 200);
    assert.equal(typeof view.hiddenAt, "number");
    assert.equal(r.store.getSession(made.key)!.archivedAt, null, "a chat of its own goes alone");
    assert.equal((await r.ask("DELETE", `/threads/${own.id}/archive`))[1].hiddenAt, undefined);
    const [, home] = await r.ask("POST", `/threads/${made.thread.id}/archive`);
    assert.equal(home.id, made.thread.id);
    assert.notEqual(r.store.getSession(made.key)!.archivedAt, null, "a session's own chat goes with it");
    const slack = r.store.openThread("slack:T1", "C1", "1.1", null, null);
    assert.deepEqual(await r.ask("POST", `/threads/${slack.id}/archive`), [400, { error: `no still.fail chat ${slack.id}` }]);

    const workspace = r.store.getSession(made.key)!.workspace;
    assert.deepEqual(await r.ask("DELETE", `/sessions/${encodeURIComponent(made.key)}`), [200, { ok: true }]);
    assert.equal(r.store.getSession(made.key), null);
    assert.ok(!existsSync(workspace));
    assert.deepEqual(await r.ask("DELETE", "/sessions/nope"), [404, { error: "unknown session nope" }]);
  } finally {
    await r.close();
  }
});

test("stopping, evicting, warming and changing a session", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    assert.deepEqual(await r.ask("POST", "/sessions/nope/stop"), [500, { error: "unknown session nope" }]);
    assert.deepEqual(await r.ask("POST", "/sessions/nope/evict"), [200, { ok: true }]);
    assert.deepEqual(await r.ask("POST", "/sessions/nope/warm"), [404, { error: "unknown session nope" }]);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/warm`), [202, { ok: true }]);
    await until("it warms", () => r.claude.count() === 1);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/evict`), [200, { ok: true }]);
    await until("it is evicted", () => r.claude.last().disposed);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/stop`), [200, { ok: true }]);
    // Its context by hand: refused, saying why, before there is one; what its runtime can do is in its summary.
    assert.deepEqual(await r.ask("POST", "/sessions/nope/compact"), [404, { error: "unknown session nope" }]);
    r.store.setRuntimeSessionId(made.key, null);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/clear`), [409, { error: "暂无上下文" }]);
    assert.deepEqual((await r.ask("GET", `/sessions/${made.key}`))[1].session.contextActions, ["compact", "clear"]);

    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/settings`, { fast: "yes" }), [400, { error: en("station.admin.badFast") }]);
    assert.equal((await r.ask("POST", "/sessions/nope/settings", { model: "opus" }))[0], 400);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/settings`, { model: "opus", profile: "cc" }), [200, { ok: true, profile: "cc" }]);
    const row = r.store.getSession(made.key)!;
    assert.deepEqual([row.model, row.profile, row.profilePinned], ["opus", "cc", true]);
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/settings`, { profile: null }), [200, { ok: true, profile: "cc" }]);
    assert.equal(r.store.getSession(made.key)!.profilePinned, false);
    // Kept to it again, then given back to the station to pick again.
    await r.ask("POST", `/sessions/${made.key}/settings`, { profile: "cc" });
    assert.deepEqual(await r.ask("POST", `/sessions/${made.key}/settings`, { repick: true }), [200, { ok: true, profile: "cc" }]);
    assert.deepEqual([r.store.getSession(made.key)!.profile, r.store.getSession(made.key)!.profilePinned], ["cc", false]);
  } finally {
    await r.close();
  }
});

test("a chat's ended jobs cleared, a job stopped from the pages", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const work = r.store.getSession(made.key)!.workspace;
    const done = r.jobs.start(made.key, "done", "true", work, null, false);
    // Never ends by itself: still running when it is stopped, however slow the machine.
    const live = r.jobs.start(made.key, "watch", "tail -f /dev/null", work, null, false);
    await until("it ends", () => r.store.getJob(done.id)!.state === "exited");
    assert.deepEqual(await r.ask("DELETE", "/sessions/nope/jobs"), [404, { error: "unknown session nope" }]);
    assert.deepEqual(await r.ask("DELETE", `/sessions/${made.key}/jobs`), [200, { removed: [done.id] }]);
    const [status, stopped] = await r.ask("POST", `/jobs/${live.id}/stop`);
    assert.equal(status, 200);
    assert.deepEqual([stopped.id, stopped.state, stopped.session], [live.id, "stopped", made.key]);
    assert.ok(Array.isArray(stopped.notices) && "outputAt" in stopped);
    assert.deepEqual(await r.ask("POST", "/jobs/nope/stop"), [500, { error: "no job nope" }]);
  } finally {
    await r.close();
  }
});

test("open jobs name their chats: the session's own, listed or archived", async () => {
  const r = rig();
  try {
    const [, listed] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const [, gone] = await r.ask("POST", "/sessions", { runtime: "claude" });
    await r.ask("POST", `/sessions/${gone.key}/archive`);
    // Never end by themselves: still running as they are listed, however slow the machine.
    const a = r.jobs.start(listed.key, "watch", "tail -f /dev/null", r.store.getSession(listed.key)!.workspace, null, false);
    const b = r.jobs.start(gone.key, "watch", "tail -f /dev/null", r.store.getSession(gone.key)!.workspace, null, false);
    const [status, open] = await r.ask("GET", "/jobs");
    assert.equal(status, 200);
    const chatOf = (id: string) => open.find((j: any) => j.id === id)?.chat;
    assert.deepEqual([chatOf(a.id)?.id, chatOf(a.id)?.archived], [listed.key, false]);
    assert.deepEqual([chatOf(b.id)?.id, chatOf(b.id)?.archived], [gone.key, true]);
    await r.ask("POST", `/jobs/${a.id}/stop`);
    await r.ask("POST", `/jobs/${b.id}/stop`);
  } finally {
    await r.close();
  }
});

test("where a session's transcript is: none before its runtime writes it, then the file in its profile's home", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const url = `/sessions/${encodeURIComponent(made.key)}/transcript`;
    assert.deepEqual(await r.ask("GET", url), [200, { path: null }]);
    const id = "11111111-aaaa-bbbb-cccc-000000000002";
    r.store.setRuntimeSessionId(made.key, id);
    assert.deepEqual(await r.ask("GET", url), [200, { path: null }], "begun, but nothing written yet");
    // Its profile's home as the reads find it: in the station's config.json.
    writeFileSync(join(r.data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }] }));
    const dir = join(r.data, "homes", "cc", "projects", "-project");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `${id}.jsonl`), "");
    assert.deepEqual(await r.ask("GET", url), [200, { path: join(dir, `${id}.jsonl`) }]);
  } finally {
    await r.close();
  }
});

test("going on with one of the machine's own sessions", async () => {
  const r = rig();
  const home = process.env.HOME;
  try {
    process.env.HOME = join(r.data, "home");
    const project = join(r.data, "project");
    const dir = join(r.data, "home", ".claude", "projects", "-project");
    mkdirSync(project, { recursive: true });
    mkdirSync(dir, { recursive: true });
    const id = "11111111-aaaa-bbbb-cccc-000000000001";
    const records = [
      { type: "user", cwd: project, timestamp: "2026-09-01T00:00:02.000Z", message: { content: "fix the build" } },
      { type: "assistant", cwd: project, timestamp: "2026-09-01T00:00:06.000Z", message: { model: "claude-opus-5-5", content: [{ type: "text", text: "Fixed." }] } },
    ];
    writeFileSync(join(dir, `${id}.jsonl`), records.map((x) => JSON.stringify(x)).join("\n") + "\n");
    assert.deepEqual(await r.ask("POST", "/machine-sessions", { runtime: "x", id }), [400, { error: en("station.admin.badRuntime") }]);
    assert.deepEqual(await r.ask("POST", "/machine-sessions", { runtime: "claude", id: "nope" }), [404, { error: en("station.admin.noLocalSession", { id: "nope" }) }]);
    const [status, made] = await r.ask("POST", "/machine-sessions", { runtime: "claude", id });
    assert.equal(status, 200);
    assert.deepEqual(Object.keys(made), ["key", "thread"]);
    const row = r.store.getSession(made.key)!;
    assert.deepEqual([row.runtimeSessionId, row.cwd, row.title], [id, project, "fix the build"]);
    // Asked again: the session already going on with it.
    assert.equal((await r.ask("POST", "/machine-sessions", { runtime: "claude", id }))[1].key, made.key);
  } finally {
    process.env.HOME = home;
    await r.close();
  }
});

test("without the agents' side: the hub's routes answer that the station is starting", async () => {
  const r = rig(false);
  try {
    assert.deepEqual(await r.ask("POST", "/sessions", { runtime: "claude" }), [503, { error: "station starting" }]);
    assert.deepEqual(await r.ask("POST", "/jobs/x/stop"), [503, { error: "station starting" }]);
  } finally {
    await r.close();
  }
});

test("a file a message names by its path: its peek and the file whole, only within the session's own directories", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const key = encodeURIComponent(made.key);
    const workspace = r.store.getSession(made.key)!.workspace;
    mkdirSync(join(workspace, "src"), { recursive: true });
    writeFileSync(join(workspace, "src", "a.ts"), Array.from({ length: 40 }, (_, i) => `line ${i + 1}`).join("\n"));
    writeFileSync(join(workspace, "bin.dat"), Buffer.from([1, 0, 2]));
    const peek = (path: string, line?: string) => r.ask("GET", `/sessions/${key}/peek`, undefined, [["path", path], ...(line ? [["line", line] as [string, string]] : [])]);
    // Relative to its working directory, and absolute; lines around the one named.
    const [status, a] = await peek("src/a.ts", "20");
    assert.equal(status, 200);
    assert.deepEqual([a.kind, a.name, a.lines.start, a.lines.at, a.lines.text[0], a.lines.text.length], ["text", "a.ts", 17, 20, "line 17", 12]);
    assert.equal((await peek(join(workspace, "src", "a.ts")))[1].lines.start, 1);
    assert.deepEqual((await peek("src"))[1].entries, ["a.ts"]);
    assert.equal((await peek("bin.dat"))[1].kind, "binary");
    // The agents' home too: their skills and memory.
    const skill = join(r.data, "agent", "skills", "x", "SKILL.md");
    mkdirSync(dirname(skill), { recursive: true });
    writeFileSync(skill, "---\nname: x\n---\n");
    assert.deepEqual((await peek(skill))[1].lines.text[1], "name: x");
    // A path from inside a repository of its workspace, as agents write one: the file whose path ends with it.
    const repo = join(workspace, "cue");
    mkdirSync(join(repo, "apps", "x", "lib", "ifc"), { recursive: true });
    writeFileSync(join(repo, "apps", "x", "lib", "ifc", "destination.ex"), "defmodule D do\nend\n");
    execFileSync("git", ["init", "-q", repo]);
    execFileSync("git", ["-C", repo, "add", "."]);
    const [found, d] = await peek("x/lib/ifc/destination.ex");
    assert.deepEqual([found, d.lines?.text[0]], [200, "defmodule D do"]);
    assert.equal((await peek("y/ifc/destination.ex"))[0], 404);
    // A directory of it, as the file's is named; a path shortened in the middle (`...`, `…`), any directories there.
    for (const dir of ["x/lib/ifc", "apps/x/lib/ifc/", "lib"]) assert.deepEqual((await peek(dir))[1].entries, dir === "lib" ? ["ifc/"] : ["destination.ex"], dir);
    for (const short of ["apps/.../ifc/destination.ex", "apps/…/destination.ex", ".../lib/ifc"]) assert.equal((await peek(short))[0], 200, short);
    assert.equal((await peek("apps/.../y/destination.ex"))[0], 404);
    // Else one of the station's clones (<data>/repos), as agents read them without a worktree: the one fetched last.
    for (const [name, age] of [["old", 3600], ["new", 0]] as const) {
      const clone = join(r.data, "repos", name);
      mkdirSync(join(clone, "web", "src"), { recursive: true });
      writeFileSync(join(clone, "web", "src", "Peeks.tsx"), `// ${name}\n`);
      execFileSync("git", ["init", "-q", clone]);
      execFileSync("git", ["-C", clone, "add", "."]);
      writeFileSync(join(clone, ".git", "FETCH_HEAD"), "");
      for (const f of ["FETCH_HEAD", "HEAD", "index"]) utimesSync(join(clone, ".git", f), new Date(Date.now() - age * 1000), new Date(Date.now() - age * 1000));
    }
    const [cloned, c] = await peek("web/src/Peeks.tsx");
    assert.deepEqual([cloned, c.path, c.lines?.text[0]], [200, realpathSync(join(r.data, "repos", "new", "web", "src", "Peeks.tsx")), "// new"]);
    // Nothing outside, however named; nothing that is not there.
    assert.deepEqual(await peek("../../../../stillfail.db"), [403, { error: en("station.files.outside") }]);
    // A file there is, outside: Windows has its own.
    const outside = process.platform === "win32" ? join(process.env.SystemRoot ?? "C:\\Windows", "win.ini") : "/etc/hosts";
    assert.deepEqual(await peek(outside), [403, { error: en("station.files.outside") }]);
    assert.deepEqual(await peek("src/nope.ts"), [404, { error: en("station.files.notFound") }]);
    const [, whole] = await r.ask("GET", `/sessions/${key}/open`, undefined, [["path", "src/a.ts"]]);
    assert.equal(Buffer.from(whole.bytes, "base64").toString("utf8").split("\n").length, 40);
    assert.equal(whole.name, "a.ts");
  } finally {
    await r.close();
  }
});

test("a row's digest is the core's, whatever the order of its fields", () => {
  // The values client/core-ts/test/station-flows.test.ts takes: the core makes the same digests.
  const v = { b: [1, "x", null, true, { z: 2, y: [] }], a: { d: 1.5, c: '中文 \u2028 "q"' }, e: -0 };
  const w = { e: 0, a: { c: '中文 \u2028 "q"', d: 1.5 }, b: [1, "x", null, true, { y: [], z: 2 }] };
  assert.deepEqual([digest(v), digest(w), digest({ k: 1 }), digest({ k: 2 })], ["txw0i07ix8", "txw0i07ix8", "1x451bsuzqf", "1jui8glvs7p"]);
});

test("a list read as what changed of it: its order, and the rows the client does not hold as they are", async () => {
  const r = rig();
  try {
    const made: any[] = [];
    for (const title of ["a", "b", "c"]) made.push((await r.ask("POST", "/sessions", { runtime: "claude", title }))[1]);
    const lists: [string, string, [string, string][]][] = [["chats", "id", []], ["chats", "id", [["archived", "1"]]], ["threads", "id", []], ["sessions", "key", []]];
    const read = async () => Promise.all(lists.map(async ([list, , query]) => (await r.ask("GET", `/${list}`, undefined, query))[1] as any[]));
    // Held as read, each row's fields in another order.
    const heldOf = (rows: any[], id: string) => Object.fromEntries(rows.map((x) => [String(x[id]), digest(Object.fromEntries(Object.entries(x).reverse()))]));
    const before = await read();
    for (const [i, [list, id, query]] of lists.entries()) {
      assert.deepEqual(await r.ask("POST", `/changed/${list}`, { held: heldOf(before[i]!, id) }, query), [200, { order: before[i]!.map((x) => x[id]), rows: [] }], list);
      assert.deepEqual(await r.ask("POST", `/changed/${list}`, { held: {} }, query), [200, { order: before[i]!.map((x) => x[id]), rows: before[i] }], list);
    }
    // a renamed, b archived, c as it was.
    assert.equal((await r.ask("PUT", `/threads/${made[0].thread.id}/title`, { title: "renamed" }))[0], 200);
    assert.equal((await r.ask("POST", `/sessions/${made[1].key}/archive`))[0], 200);
    const now = await read();
    for (const [i, [list, id, query]] of lists.entries()) {
      const was = new Map(before[i]!.map((x) => [String(x[id]), x]));
      const [status, changed] = await r.ask("POST", `/changed/${list}`, { held: heldOf(before[i]!, id) }, query);
      assert.equal(status, 200);
      assert.deepEqual(changed.order, now[i]!.map((x) => x[id]), list);
      assert.deepEqual(changed.rows, now[i]!.filter((x) => !isDeepStrictEqual(was.get(String(x[id])), x)), list);
    }
    const [, chats] = await r.ask("POST", "/changed/chats", { held: heldOf(before[0]!, "id") });
    assert.deepEqual([[...chats.order].sort(), chats.rows.map((x: any) => x.id)], [[made[0].key, made[2].key].sort(), [made[0].key]], "c held as it is: not sent");
    assert.deepEqual(await r.ask("POST", "/changed/chats", { held: [] }), [400, { error: "held: each held row's digest by its id" }]);
    assert.deepEqual(await r.ask("POST", "/changed/chats", "{"), [400, { error: "held: each held row's digest by its id" }]);
  } finally {
    await r.close();
  }
});

test("several reads in one: each answered as its GET is, in their order, only the reads of a history", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const id = made.thread.id;
    r.store.insertMessage(newMessage(id, "1.2", "person", "a@x", "hi"));
    const key = encodeURIComponent(made.key);
    const gets = [`/threads/${id}/entries?limit=50`, `/threads/${id}`, `/sessions/${key}`, `/sessions/${key}/timeline?before=1000000000000000&limit=200&brief=1`, "/threads/999/entries?after=0", "/usage?from=0", "/events", `/sessions/${key}/files?name=x`];
    const [status, batch] = await r.ask("POST", "/batch", { gets });
    assert.equal(status, 200);
    assert.equal(batch.answers.length, gets.length);
    for (const [i, get] of gets.slice(0, 5).entries()) {
      const [path, query] = get.split("?");
      const [s, body] = await r.ask("GET", path!, undefined, [...new URLSearchParams(query ?? "")]);
      assert.deepEqual(batch.answers[i], { status: s, body }, get);
    }
    assert.equal(batch.answers[4].status, 404);
    for (const [i, get] of gets.slice(5).entries()) assert.deepEqual(batch.answers[5 + i], { status: 400, body: { error: `not read in a batch: ${get.split("?")[0]}` } });
    assert.deepEqual(await r.ask("POST", "/batch", { gets: Array.from({ length: 65 }, () => `/threads/${id}`) }), [400, { error: "gets: at most 64 paths to read" }]);
    assert.deepEqual(await r.ask("POST", "/batch", "{"), [400, { error: "gets: at most 64 paths to read" }]);
  } finally {
    await r.close();
  }
});

test("a session at work: the station follows it, its summary says how long its transcript is, and what comes after a point is read in brief", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const key = made.key;
    const dir = join(r.data, "homes", "cc", "projects", "p");
    mkdirSync(dir, { recursive: true });
    const said = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-24T00:00:00Z", message: { id, content: [{ type: "text", text }] } })}\n`;
    writeFileSync(join(dir, "rs1.jsonl"), ["one", "two", "three", "four", "five"].map((t, i) => said(t, `m${i}`)).join(""));
    r.store.ranIn(key, "rs1", "cc");
    r.store.setRuntimeSessionId(key, "rs1");
    // Where the reads find its profile's home.
    writeFileSync(join(r.data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: join(r.data, "homes", "cc") }] }));
    const summary = async () => (await r.ask("GET", `/sessions/${encodeURIComponent(key)}`))[1].session;
    assert.equal((await summary()).transcriptLength, undefined, "not read at work yet: not said");
    // At work: followed, read, its length kept where its summary reads it.
    r.store.setRunning(key, true);
    assert.deepEqual(r.hub.live.held(), [key]);
    assert.equal((await summary()).transcriptLength, 5);
    const timeline = async (query: [string, string][]) => (await r.ask("GET", `/sessions/${encodeURIComponent(key)}/timeline`, undefined, query))[1];
    const texts = (t: any) => [t.start, t.entries.map((e: any) => e.text), t.end];
    assert.deepEqual(texts(await timeline([["after", "1"], ["limit", "2"], ["brief", "1"]])), [2, ["three", "four"], 5]);
    assert.deepEqual(texts(await timeline([["after", "4"], ["brief", "1"]])), [5, [], 5]);
    assert.deepEqual(texts(await timeline([["before", "1000000000000000"], ["limit", "2"], ["brief", "1"]])), [3, ["four", "five"], 5]);
    assert.deepEqual(texts(await timeline([["from", "0"], ["to", "1"], ["brief", "1"]])), [0, ["one", "two"], 5]);
  } finally {
    await r.close();
  }
});

test("a session's summary says what its calls used as the usage counter recorded them, so a device knows it of one at rest", async () => {
  const r = rig();
  const counter = new UsageCounter({ store: r.store, config: () => ({ dataDir: r.data, profiles: [{ home: join(r.data, "homes", "cc") }] }) });
  const stop = keepCounted(r.store, r.hub.live, counter);
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const key = made.key;
    const dir = join(r.data, "homes", "cc", "projects", claudeProject(r.store.getSession(key)!.workspace));
    mkdirSync(dir, { recursive: true });
    const said = (id: string, input: number) =>
      `${JSON.stringify({ type: "assistant", timestamp: new Date(r.store.now() + 1000).toISOString(), message: { id, model: "claude-opus-5-5", content: [{ type: "text", text: id }], usage: { input_tokens: input, cache_read_input_tokens: 100, output_tokens: 7 } } })}\n`;
    writeFileSync(join(dir, "rs1.jsonl"), said("m1", 1) + said("m2", 2));
    r.store.ranIn(key, "rs1", "cc");
    r.store.setRuntimeSessionId(key, "rs1");
    const summary = async () => (await r.ask("GET", `/sessions/${encodeURIComponent(key)}`))[1].session;
    assert.equal((await summary()).usage, undefined, "no call read yet: not said");
    await counter.read();
    const usage = (await summary()).usage;
    assert.deepEqual([usage.modelCalls, usage.inputTokens, usage.cachedTokens, usage.outputTokens, usage.contextTokens, usage.model], [2, 203, 200, 14, 102, "claude-opus-5-5"]);
    assert.ok(usage.cost > 0, "and what it would cost, as the usage page has it");
    // At work: what it writes is read for it alone, and its summary says it.
    r.store.setRunning(key, true);
    appendFileSync(join(dir, "rs1.jsonl"), said("m3", 3));
    await counter.read(new Set([key]));
    const working = (await summary()).usage;
    assert.deepEqual([working.modelCalls, working.contextTokens], [3, 103]);
    r.store.setRunning(key, false);
    const listed = (await r.ask("GET", "/sessions"))[1].find((s: any) => s.key === key);
    assert.deepEqual(listed.usage, working, "the list says it as the session does");
  } finally {
    stop();
    await counter.stop();
    await r.close();
  }
});

test("as the station starts, a summary a station from before kept is kept as it says it now, and devices are told", async () => {
  const r = rig();
  const counter = new UsageCounter({ store: r.store, config: () => ({ dataDir: r.data, profiles: [{ home: join(r.data, "homes", "cc") }] }) });
  let stop = keepCounted(r.store, r.hub.live, counter);
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const key = made.key;
    const dir = join(r.data, "homes", "cc", "projects", claudeProject(r.store.getSession(key)!.workspace));
    mkdirSync(dir, { recursive: true });
    const usage = { input_tokens: 1, cache_read_input_tokens: 100, cache_creation_input_tokens: 80_000, cache_creation: { ephemeral_1h_input_tokens: 80_000 }, output_tokens: 7 };
    writeFileSync(join(dir, "rs1.jsonl"), `${JSON.stringify({ type: "assistant", timestamp: new Date(r.store.now() + 1000).toISOString(), message: { id: "m1", model: "claude-opus-5-5", content: [], usage } })}\n`);
    r.store.ranIn(key, "rs1", "cc");
    r.store.setRuntimeSessionId(key, "rs1");
    await counter.read();
    const now = r.store.sessionUsage(key);
    assert.equal(now.cacheMs, 3_600_000);
    // As a station from before kept it: without when its cache is over.
    const { cacheMs: _, lastCallAt: __, rereadCost: ___, ...before } = now;
    r.store.setSessionUsage(key, before, true);
    stop();
    const told: string[] = [];
    const unsubscribe = r.store.subscribe((c) => {
      if (c.type === "session") told.push(c.key);
    });
    stop = keepCounted(r.store, r.hub.live, counter);
    unsubscribe();
    assert.deepEqual(r.store.sessionUsage(key), now, "kept as this station says it");
    assert.deepEqual(told, [key], "told, as a device holds the summary from before");
    told.length = 0;
    stop();
    const again = r.store.subscribe((c) => {
      if (c.type === "session") told.push(c.key);
    });
    stop = keepCounted(r.store, r.hub.live, counter);
    again();
    assert.deepEqual(told, [], "the same again: nothing told");
  } finally {
    stop();
    await counter.stop();
    await r.close();
  }
});

test("the sidebar items a change can touch are read as the whole sidebar has them, and only they", async () => {
  const r = rig();
  try {
    const made: any[] = [];
    for (const title of ["a", "b", "c"]) made.push((await r.ask("POST", "/sessions", { runtime: "claude", title }))[1]);
    // b brought into a's chat: a's item has both; c alone.
    assert.equal((await r.ask("POST", `/threads/${made[0].thread.id}/sessions`, { session: made[1].key }))[0], 200);
    r.store.insertMessage(newMessage(made[0].thread.id, "1.2", "person", "a@x", "hi"));
    const store = openStore(r.data);
    const whole = chats(store, viewer, false);
    const byId = new Map(whole.map((row: any) => [String(row.id), row]));
    for (const [sessions, threads] of [[[made[1].key], []], [[], [made[0].thread.id]], [[made[2].key], []]] as [string[], number[]][]) {
      const some = chatRows(store, viewer, sessions, threads);
      assert.ok(some.rows.length > 0 && some.rows.length < whole.length, JSON.stringify(some.scope));
      for (const row of some.rows) assert.deepEqual(row, byId.get(String(row.id)));
      for (const row of some.rows) assert.ok(some.scope.includes(String(row.id)));
    }
    store.db.close();
  } finally {
    await r.close();
  }
});

test("writing in an agent's Slack thread makes its item the viewer's (我参与的), chat or no chat", async () => {
  const r = rig();
  try {
    // Someone else's agents, each with a Slack thread: one with no chat, one in a chat of its own.
    r.store.insertSession({ key: "alone", connect: "slack:T1", runtime: "claude", profile: "cc", workspace: join(r.data, "alone"), token: "t1", createdAt: 1, lastActiveAt: 1, createdBy: "z@x" });
    const [, chatted] = await r.ask("POST", "/sessions", { runtime: "claude" });
    const thread = (ts: string, session: string) => {
      const t = r.store.openThread("slack:T1", "C1", ts, null, null);
      r.store.joinThread(t.id, session, "slack:T1");
      return t.id;
    };
    const quiet = thread("1.1", "alone");
    const busy = thread("2.1", chatted.key);
    r.store.insertMessage(newMessage(quiet, "1.1", "person", "UZ", "explain rdp"));
    r.store.insertMessage(newMessage(busy, "2.1", "person", "UZ", "and this"));
    const other = { ...viewer, sub: "b", email: "b@x", name: "B" };
    r.store.setSlackIdentity("b@x", "UB", true);
    const mine = () => {
      const store = openStore(r.data);
      const rows = chats(store, other, false);
      store.db.close();
      return Object.fromEntries(rows.map((row: any) => [row.session, row.mine]));
    };
    assert.deepEqual(mine(), { alone: false, [chatted.key]: false }, "not written in yet");
    r.store.insertMessage(newMessage(quiet, "1.2", "person", "UB", "can our windows join?"));
    r.store.insertMessage(newMessage(busy, "2.2", "person", "UB", "me too"));
    assert.deepEqual(mine(), { alone: true, [chatted.key]: true });
  } finally {
    await r.close();
  }
});

test("an archived chat is listed as it was, from the database or from the file a station before wrote it out to", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "claude", title: "a" });
    const id = made.thread.id;
    r.store.insertMessage(newMessage(id, "1.2", "person", "a@x", "first"));
    const listed = async () => ((await r.ask("GET", "/threads"))[1] as any[]).find((t) => t.id === id);
    const before = await listed();
    // Archived: its entries stay in the database, and the lists read it as before.
    const file = join(r.data, "archive", "threads", `${id}.jsonl.zst`);
    assert.equal((await r.ask("POST", `/sessions/${made.key}/archive`))[0], 200);
    assert.ok(!existsSync(file));
    const archived = await listed();
    assert.deepEqual([archived.last, archived.lastMessage.text, archived.unread, archived.people], [before.last, "first", before.unread, before.people]);
    // Written out to its file by a station before: read from there the same (once: a second list is the same).
    fileAway(r.store, id);
    assert.deepEqual(await listed(), archived);
    assert.deepEqual(await listed(), archived);
    // Brought back by what is said in it and archived again: listed as it is now.
    r.store.insertMessage(newMessage(id, "1.3", "person", "b@x", "second"));
    assert.ok(!existsSync(file));
    assert.equal((await r.ask("POST", `/sessions/${made.key}/archive`))[0], 200);
    const again = await listed();
    assert.deepEqual([again.last, again.lastMessage.text, again.people.map((p: any) => p.email)], [archived.last + 1, "second", ["a@x", "b@x"]]);
  } finally {
    await r.close();
  }
});

test("an agent's message comes with its session's model and runtime, for its mark before the session is read", async () => {
  const r = rig();
  try {
    const [, made] = await r.ask("POST", "/sessions", { runtime: "codex", title: "a" });
    r.store.setSessionModel(made.key, "gpt-5.5", null);
    const id = made.thread.id;
    r.store.insertMessage(newMessage(id, "1.2", "person", "a@x", "hi"));
    r.store.insertMessage(newMessage(id, "1.3", "agent", made.key, "done"));
    const [, page] = await r.ask("GET", `/threads/${id}/entries`);
    const by = (kind: string) => page.entries.find((e: any) => e.authorKind === kind);
    assert.deepEqual([by("agent").authorModel, by("agent").authorRuntime], ["gpt-5.5", "codex"]);
    assert.deepEqual([by("person").authorModel, by("person").authorRuntime], [undefined, undefined]);
  } finally {
    await r.close();
  }
});
