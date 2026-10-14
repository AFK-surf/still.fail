// Chats published as snapshots (docs/public-share.md): what looks like a secret hidden, the preview, the snapshot written
// out frozen with the attachments ticked, its chat's view, visitors over the guest ALPN, and taking it down.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import type { Connection, Stream } from "../src/mesh/native.ts";
import { tr } from "../src/ops/i18n.ts";
import { Guests, LIMITS } from "../src/publish/guest.ts";
import { redact } from "../src/publish/redact.ts";
import { Readers } from "../src/read/pool.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Hub } from "../src/sessions/hub.ts";
import { InternalChat } from "../src/sessions/internal.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { FakeDriver } from "./hub-fakes.ts";

const alice = { sub: "a", email: "alice@acme.dev", name: "Alice", role: "member", workspace: "w", device: "d" };
const bob = { ...alice, sub: "b", email: "bob@acme.dev", name: "Bob" };
const owner = { ...alice, sub: "o", email: "owner@acme.dev", name: "Olga", role: "owner" };
const reader = { ...alice, sub: "v", email: "viv@acme.dev", name: "Viv", role: "viewer" };

test("secrets by their shape are hidden, counted; plain words are not", () => {
  const mark = "[hidden]";
  const cases: [string, number][] = [
    ["key sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123", 1],
    ["export OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwx", 1],
    ["ghp_abcdefghijklmnopqrstuvwxyz0123456789 and xoxb-123456789012-abcdefghijkl", 2],
    ["AKIAABCDEFGHIJKLMNOP", 1],
    ["https://deploy:hunter2secret@example.com/repo.git", 1],
    ["Authorization: Bearer abcdefghijklmnop.qrstuvwxyz", 1],
    ['{"password": "correct-horse-9"}', 1],
    ["-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----", 1],
    ["eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", 1],
    // Not secrets: numbers called tokens, an author, a task's name, words.
    ["tokens: 12000 used, max_tokens = 4096", 0],
    ["author: zuozijian, password reset page is broken", 0],
    ["task-scheduler-for-the-nightly-build and risk-assessment-document", 0],
  ];
  for (const [text, count] of cases) {
    const hidden = redact(text, mark);
    assert.equal(hidden.count, count, `${text} → ${hidden.text}`);
    if (count > 0) assert.ok(hidden.text.includes(mark), hidden.text);
    else assert.equal(hidden.text, text);
  }
  // Hidden once, not again.
  assert.deepEqual(redact("token: [hidden]", mark), { text: "token: [hidden]", count: 0 });
});

/// A visitor's connection: the streams it opens (each a request line), what each was answered.
function visitor(requests: unknown[]) {
  const answers: Buffer[][] = requests.map(() => []);
  const streams = requests.map((request, i): Stream => {
    let sent = false;
    return {
      read: async () => {
        if (sent) return null;
        sent = true;
        return Buffer.from(JSON.stringify(request) + "\n");
      },
      write: async (bytes: Buffer) => void answers[i]!.push(Buffer.from(bytes)),
      finish: async () => {},
      stopped: async () => null,
      reset: () => {},
    } as unknown as Stream;
  });
  let next = 0;
  const closed: string[] = [];
  const conn = {
    remoteId: () => "visitor",
    acceptBi: async () => (next < streams.length ? streams[next++]! : null),
    close: (_code: number, reason: string) => void closed.push(reason),
  } as unknown as Connection;
  /// What stream i was answered: its head line and the bytes after it.
  const answer = (i: number) => {
    const all = Buffer.concat(answers[i]!);
    const at = all.indexOf(10);
    return { head: JSON.parse(all.subarray(0, at).toString()), body: all.subarray(at + 1) };
  };
  return { conn, answer, closed };
}

/// A clock the test moves: timers fire as it passes them.
function clock(start = 1_000_000) {
  let now = start;
  const timers: { at: number; f: () => void; off: boolean }[] = [];
  return {
    now: () => now,
    after: (ms: number, f: () => void) => {
      const t = { at: now + ms, f, off: false };
      timers.push(t);
      return () => void (t.off = true);
    },
    pass: (ms: number) => {
      now += ms;
      for (const t of timers.filter((t) => !t.off && t.at <= now)) {
        t.off = true;
        t.f();
      }
    },
  };
}

test("a chat published: previewed, written out frozen with the attachments ticked, read by a visitor, taken down", async () => {
  const data = mkdtempSync(join(tmpdir(), "publish-"));
  const config = hubConfig({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc", models: ["opus"] }] }, data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const hub = new Hub({ config: () => config, store, chats: () => undefined, drivers: [new FakeDriver("claude")], mcpUrl: "http://127.0.0.1:1/mcp", internal: new InternalChat(), runners: () => [] });
  const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
  hub.setJobs(jobs);
  const readers = new Readers(data, 1);
  const admin = new Admin(readers, { store, agents: { hub, jobs, place: () => ({ origin: "o", workspace: "w", station: "s", name: "Studio" }) } as any });
  const ask = async (viewer: typeof alice, method: string, path: string, body?: unknown) => {
    const r: Request = { method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "en" };
    const a = await admin.handle(r);
    return { status: a.status, body: JSON.parse(String(a.body)) };
  };
  try {
    const made = (await ask(alice, "POST", "/sessions", { runtime: "claude" })).body;
    const thread: number = made.thread.id;
    const workspace = store.getSession(made.key)!.workspace;
    mkdirSync(join(workspace, "uploads"), { recursive: true });
    writeFileSync(join(workspace, "uploads/shot.png"), "png bytes");
    writeFileSync(join(workspace, "uploads/notes.txt"), "plain notes");
    store.insertMessage(newMessage(thread, "1.1", "person", "alice@acme.dev", "deploy with token: abc123def456ghi"));
    store.insertMessage({ ...newMessage(thread, "1.2", "agent", made.key, "done ![](shot.png)"), attachments: [
      { name: "shot.png", path: join(workspace, "uploads/shot.png"), size: 9, width: 4, height: 3 },
      { name: "notes.txt", path: join(workspace, "uploads/notes.txt"), size: 11 },
    ] });
    store.insertMessage(newMessage(thread, "1.3", "person", "carol@elsewhere.org", "looks good"));

    // A read-only member previews nothing, publishes nothing.
    assert.equal((await ask(reader, "POST", `/threads/${thread}/publish/preview`, {})).status, 403);

    const preview = await ask(alice, "POST", `/threads/${thread}/publish/preview`, { names: { "alice@acme.dev": "Alice Liddell" } });
    assert.equal(preview.status, 200, JSON.stringify(preview.body));
    const p = preview.body;
    assert.deepEqual(p.entries.map((e: any) => e.author), ["Alice Liddell", p.entries[1].author, "carol"], "people by name, never by address");
    assert.ok(!JSON.stringify(p).includes("@acme.dev") && !JSON.stringify(p).includes("@elsewhere.org"), "no address in the snapshot");
    assert.equal(p.entries[0].text, "deploy with token: [hidden]");
    assert.equal(p.title, "deploy with token: [hidden]", "its name, the first thing said, hidden alike");
    assert.deepEqual(p.redacted, [{ n: p.entries[0].n, count: 1 }]);
    assert.deepEqual(p.files.map((f: any) => [f.k, f.name, f.type]), [["f0", "shot.png", "image/png"], ["f1", "notes.txt", "text/plain; charset=utf-8"]]);
    assert.ok(p.files.every((f: any) => f.path === undefined), "where a file is stays on the station");
    const upto: number = p.upto;

    // Said after the preview: not in what is published.
    store.insertMessage(newMessage(thread, "1.4", "person", "alice@acme.dev", "a later word"));
    const done = await ask(alice, "POST", `/threads/${thread}/publish`, { upto, files: ["f0"], names: {} });
    assert.equal(done.status, 200, JSON.stringify(done.body));
    const published = done.body.published;
    assert.match(published.id, /^[A-Za-z0-9_-]{16}$/);
    assert.match(published.key, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(published.byName, "Alice");
    const dir = join(data, "published", published.id);
    const snapshot = JSON.parse(readFileSync(join(dir, "snapshot.json"), "utf8"));
    assert.equal(snapshot.v, 1);
    assert.equal(snapshot.station, "Studio");
    assert.equal(snapshot.by, "Alice");
    assert.deepEqual(snapshot.entries.map((e: any) => e.text), ["deploy with token: [hidden]", "done ![](shot.png)", "looks good"]);
    assert.deepEqual(snapshot.entries[1].files.map((f: any) => f.k), ["f0"], "only what was ticked");
    assert.equal(readFileSync(join(dir, "f", "f0"), "utf8"), "png bytes");
    assert.ok(!existsSync(join(dir, "f", "f1")));

    // The chat's view says it is published; the original changing does not change the snapshot.
    const view = JSON.parse(await readers.read("thread", { id: String(thread), viewer: alice, lang: "en" }, "en"));
    assert.deepEqual(view.published.map((x: any) => x.id), [published.id]);
    writeFileSync(join(workspace, "uploads/shot.png"), "changed");
    assert.equal(readFileSync(join(dir, "f", "f0"), "utf8"), "png bytes");

    // A visitor reads the snapshot and its attachment; a wrong key, an unknown id and a file not in it are all "gone".
    const guests = new Guests(store, clock(), { ...LIMITS, streams: 8 });
    const v = visitor([
      { get: published.id, key: published.key },
      { get: published.id, key: published.key, file: "f0" },
      { get: published.id, key: "x".repeat(43) },
      { get: "AAAAAAAAAAAAAAAA", key: published.key },
      { get: published.id, key: published.key, file: "f1" },
      { get: published.id, key: published.key, file: "../snapshot.json" },
    ]);
    await guests.serve(v.conn);
    const first = v.answer(0);
    assert.equal(first.head.ok, true);
    assert.equal(first.head.size, first.body.length);
    assert.deepEqual(JSON.parse(first.body.toString()), snapshot);
    assert.deepEqual([v.answer(1).head, v.answer(1).body.toString()], [{ ok: true, size: 9, type: "image/png" }, "png bytes"]);
    for (const i of [2, 3, 4, 5]) assert.equal(v.answer(i).head.code, "gone", `request ${i}`);

    // Taken down: not by another member, by its publisher; then gone for visitors too.
    assert.equal((await ask(bob, "DELETE", `/published/${published.id}`)).status, 403);
    assert.deepEqual((await ask(alice, "DELETE", `/published/${published.id}`)).body, { ok: true });
    assert.ok(!existsSync(dir));
    assert.equal((await ask(alice, "DELETE", `/published/${published.id}`)).status, 404);
    const after = visitor([{ get: published.id, key: published.key }]);
    await guests.serve(after.conn);
    assert.equal(after.answer(0).head.code, "gone");
    const view2 = JSON.parse(await readers.read("thread", { id: String(thread), viewer: alice, lang: "en" }, "en"));
    assert.equal(view2.published, undefined, "left out when none");

    // An owner takes down another's; too big a snapshot, an empty chat, a chat that is not there are refused.
    const again = (await ask(bob, "POST", `/threads/${thread}/publish`, { upto, files: [] })).body.published;
    assert.deepEqual((await ask(owner, "DELETE", `/published/${again.id}`)).body, { ok: true });
    writeFileSync(join(workspace, "uploads/huge.bin"), Buffer.alloc(11 * 1024 * 1024));
    const [hugeN] = store.insertMessage({ ...newMessage(thread, "1.5", "agent", made.key, "big"), attachments: [{ name: "huge.bin", path: join(workspace, "uploads/huge.bin"), size: 11 * 1024 * 1024 }] });
    const big = (await ask(alice, "POST", `/threads/${thread}/publish/preview`, {})).body;
    const k = big.files.find((f: any) => f.name === "huge.bin").k;
    const refused = await ask(alice, "POST", `/threads/${thread}/publish`, { upto: hugeN, files: [k] });
    assert.deepEqual(refused, { status: 413, body: { error: tr("en", "station.publish.tooLarge", { mb: "20" }) } });
    const empty = (await ask(alice, "POST", "/sessions", { runtime: "claude" })).body;
    assert.deepEqual(await ask(alice, "POST", `/threads/${empty.thread.id}/publish/preview`, {}), { status: 400, body: { error: tr("en", "station.publish.empty") } });
    assert.equal((await ask(alice, "POST", "/threads/99999/publish/preview", {})).status, 404);

    // A chat that goes takes its snapshots with it.
    const last = (await ask(alice, "POST", `/threads/${thread}/publish`, { upto, files: ["f0"] })).body.published;
    assert.ok(existsSync(join(data, "published", last.id)));
    store.deleteSession(made.key);
    assert.equal(store.published(last.id), null);
    assert.ok(!existsSync(join(data, "published", last.id)));
  } finally {
    await hub.shutdown();
    await jobs.shutdown();
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("visitors: few at once, few requests a minute, an idle one dropped", async () => {
  const store = Store.open(":memory:", null);
  try {
    const time = clock();
    const guests = new Guests(store, time, { ...LIMITS, perMinute: 2, streams: 4, connections: 16, idleMs: 30_000 });
    const ask = { get: "AAAAAAAAAAAAAAAA", key: "k".repeat(43) };
    const v = visitor([ask, ask, ask]);
    await guests.serve(v.conn);
    assert.deepEqual([0, 1, 2].map((i) => v.answer(i).head.code), ["gone", "gone", "busy"], "the third of the minute is refused");
    time.pass(60_000);
    const w = visitor([ask]);
    await guests.serve(w.conn);
    assert.equal(w.answer(0).head.code, "gone", "a new minute");

    // A connection that asks nothing is closed once it has idled.
    let release!: () => void;
    const held = new Promise<null>((r) => (release = () => r(null)));
    const closed: string[] = [];
    const idle = { remoteId: () => "v", acceptBi: () => held, close: (_: number, why: string) => (closed.push(why), release()) } as unknown as Connection;
    const serving = guests.serve(idle);
    time.pass(29_999);
    assert.deepEqual(closed, []);
    time.pass(1);
    assert.deepEqual(closed, ["idle"]);
    await serving;
  } finally {
    store.close();
  }
});
