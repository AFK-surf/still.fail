// The requests the MoonBit program answers itself (station/src/mesh/served.ts, station/mb's reader `--serve`): a
// device's stream asking a route given to the front (front.ts `route`, client/shell `conn.hand`) goes to the program,
// which answers it as the admin API does; every other stream comes to Node as before, in the order the device opened
// them, the one taken by the program not waited for. Real processes and sockets: the side run's.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { createZstdDecompress, zstdDecompressSync } from "node:zlib";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { withFront } from "../src/mesh/front.ts";
import { SERVED_ROUTES, Served } from "../src/mesh/served.ts";
import { RUNTIME_KINDS } from "../src/agents/runtime.ts";
import { tr } from "../src/ops/i18n.ts";
import { type Endpoint, type Stream, loadMesh } from "../src/mesh/native.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();
const skip = binary === null ? "the MoonBit program is not built here (station/mb/build.sh)" : false;
const ALPN = Buffer.from("stillfail/test/served");
const OTHER = Buffer.from("stillfail/test/other");

async function front(dir: string): Promise<{ socket: string; stop: () => Promise<number> }> {
  const socket = join(dir, "front.sock");
  const p = new MbProcess(binary!, ["--builder", "mesh", "--socket", socket, "--shell-dir", join(dir, "shell")]);
  await new Promise<void>((resolve, reject) => {
    p.once("message", (m: { listening?: string }) => (m.listening === socket ? resolve() : reject(new Error(JSON.stringify(m)))));
    p.once("exit", (code: number) => reject(new Error(`ended (${code})`)));
  });
  return { socket, stop: () => p.terminate() };
}

async function readAll(s: Stream): Promise<Buffer> {
  const parts: Buffer[] = [];
  for (let b = await s.read(); b !== null; b = await s.read()) parts.push(b);
  return Buffer.concat(parts);
}

/// A request on a stream of its own: its head line, then its answer's head and body.
async function ask(conn: { openBi(): Promise<Stream> }, head: object): Promise<{ head: any; body: Buffer }> {
  const s = await conn.openBi();
  await s.write(Buffer.from(`${JSON.stringify(head)}\n`));
  await s.finish();
  const all = await readAll(s);
  const at = all.indexOf(10);
  return { head: JSON.parse(all.subarray(0, at).toString()), body: all.subarray(at + 1) };
}

function diffAt(a: unknown, b: unknown, at = ""): string | null {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (a && b && typeof a === "object" && typeof b === "object") {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = diffAt((a as any)[k], (b as any)[k], `${at}.${k}`);
      if (d !== null) return d;
    }
  }
  return `${at}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`;
}

const addrOf = (e: Endpoint) => ({ id: e.id(), ips: e.sockets().filter((s) => /^\d/.test(s)).map((s) => s.replace(/^0\.0\.0\.0/, "127.0.0.1")) });

test("a routed request is answered by the MoonBit program as the admin API answers it; the rest come to Node in order", { skip, timeout: 60_000 }, async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "mbsv-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const data = join(dir, "data");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  // (chats of sessions, so the list has rows to compress)
  for (let k = 0; k < 6; k++) {
    store.insertSession({ key: `s${k}`, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: `s${k}`, createdAt: 1, lastActiveAt: 1000 + k } as Parameters<Store["insertSession"]>[0]);
    const t = store.openThread("ember", "CHAT", `c${k}`, `Served ${k}`, null).id;
    store.joinThread(t, `s${k}`, "ember");
    store.insertMessage({ ...newMessage(t, "1", "person", "p@x", `hello ${k} ${"words ".repeat(30)}`), at: 100 + k } as ReturnType<typeof newMessage>);
  }
  // (one of another workspace: none for this member)
  store.insertSession({ key: "elsewhere", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "e", createdAt: 1, lastActiveAt: 1, ws: "other" } as Parameters<Store["insertSession"]>[0]);
  const hidden = store.openThread("ember", "CHAT", "ce", "Elsewhere", null).id;
  store.joinThread(hidden, "elsewhere", "ember");
  const thread = store.openThread("ember", "CHAT", "c", "Served", null).id;
  for (let i = 0; i < 40; i++) store.insertMessage({ ...newMessage(thread, String(i + 1), "person", "p@x", `message ${i} ${"words ".repeat(20)}`), at: (i + 1) * 10 } as ReturnType<typeof newMessage>);
  t.after(() => store.close());

  const f = await front(dir);
  t.after(() => f.stop());
  const mesh = withFront(loadMesh(), f.socket);
  const station = await mesh.bind({ secretKey: Buffer.alloc(32, 7), alpns: [ALPN, OTHER], relayUrls: [], discovery: false });
  t.after(() => station.close());
  const device = await loadMesh().bind({ secretKey: Buffer.alloc(32, 9), alpns: [ALPN, OTHER], relayUrls: [], discovery: false });
  t.after(() => device.close());

  const viewer = { email: "p@x", name: "P", workspace: "ws", role: "owner", home: true };
  const given: { head: any; body: string }[] = [];
  const builds: (number | null)[] = [];
  const served = new Served(binary!, data, async (v, head, body) => {
    given.push({ head, body: body.toString() });
    assert.deepEqual(v, viewer);
    return { status: 200, headers: { "content-type": "application/json" }, body: Buffer.from('{"from":"node"}') };
  }, (_, build) => builds.push(build), async (v, head) => {
    // an event stream as Node's events make one (api/events.ts `relay`): two pieces, then one more told every stream
    // each time `more` is called (the one text, as `emit` tells it), till let go
    assert.deepEqual(v, viewer);
    assert.equal(head.path, "/admin/api/events?shared=1");
    const pieces = ["retry: 3000\n\n", "event: made\ndata: {}\n\n"];
    const body: AsyncIterableIterator<Buffer> & { relay?: unknown } = {
      [Symbol.asyncIterator]: () => body,
      next: async () => ({ done: true, value: undefined }),
      return: async () => {
        events.sinks = events.sinks.filter((k) => k !== sink);
        if (events.sinks.length === 0) events.letGo();
        return { done: true, value: undefined };
      },
    };
    let sink: { send: (text: string) => void; ended: () => void } | null = null;
    body.relay = (send: (text: string) => void, ended: () => void) => {
      for (const p of pieces) send(p);
      sink = { send, ended };
      events.sinks.push(sink);
    };
    return { status: 200, headers: { "content-type": "text/event-stream" }, body };
  });
  const events = {
    sinks: [] as { send: (text: string) => void; ended: () => void }[],
    told: 0,
    more: () => { const text = `event: x\ndata: ${events.told++}\n\n`; for (const k of events.sinks) k.send(text); },
    letGo: () => {},
    wentAway: null as Promise<void> | null,
  };
  events.wentAway = new Promise<void>((r) => (events.letGo = r));
  t.after(() => served.close());
  const paths = await served.start();
  assert.equal(await station.route!(ALPN, paths, SERVED_ROUTES), true);

  const accepted = station.accept();
  const theirs = await device.connect(addrOf(station), ALPN);
  const conn = (await accepted)!;
  assert.equal(typeof conn.handed, "number");

  // first a stream as a credential's (Node's), then a routed request, then one of Node's: Node takes the first and the
  // third, in that order, the second never waited for
  const first = await theirs.openBi();
  await first.write(Buffer.from('{"hello":1}\n'));
  const routedHead = { method: "GET", path: "/admin/api/chats?shared=1", headers: { "stillfail-build": "0.1.9200", "stillfail-runtimes": RUNTIME_KINDS.join(","), "accept-encoding": "zstd", "stillfail-lang": "en" } };
  const routed = ask(theirs, routedHead);
  const third = await theirs.openBi();
  await third.write(Buffer.from('{"method":"GET","path":"/admin/api/host"}\n'));
  const a = (await conn.acceptBi())!;
  const c = (await conn.acceptBi())!;
  const lineOf = async (s: Stream) => (await s.read())!.toString();
  assert.equal(await lineOf(a), '{"hello":1}\n');
  assert.equal(await lineOf(c), '{"method":"GET","path":"/admin/api/host"}\n');

  // the member said once the connection is let in: the request waits for it
  served.viewer(conn.handed!, viewer);
  const answer = await routed;
  const said = `${JSON.stringify(answer.head)}, ${answer.body.length} bytes: ${answer.body.subarray(0, 200).toString()}`;
  assert.equal(answer.head.status, 200, said);
  assert.equal(answer.head.headers["content-encoding"], "zstd", said);
  assert.equal(answer.head.headers["stillfail-idempotent"], "1");
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  // (as the admin API learns people's names from who asks)
  worker.names.set(viewer.email, viewer.name);
  t.after(() => worker.close());
  const theirsText = await worker.read("sharedChats", { viewer, sessions: null, threads: null }, "en");
  const ours = JSON.parse(zstdDecompressSync(answer.body).toString());
  assert.ok(Array.isArray(ours) ? ours.length > 0 : Object.keys(ours).length > 0, said);
  assert.deepEqual(ours, JSON.parse(theirsText), diffAt(ours, JSON.parse(theirsText)) ?? "");
  assert.deepEqual(builds, [9200]);

  // each route answered there, as the worker reads it (sessions.ts, chats.ts)
  const read = async (path: string) => {
    const got = await ask(theirs, { ...routedHead, path: `/admin/api${path}` });
    const text = got.head.headers["content-encoding"] === "zstd" ? zstdDecompressSync(got.body).toString() : got.body.toString();
    return { status: got.head.status, body: JSON.parse(text) };
  };
  const routes = [
    ["/sessions", "sessions", { connect: null, archived: false, lang: "en", viewer }],
    ["/sessions?archived=1", "sessions", { connect: null, archived: true, lang: "en", viewer }],
    ["/sessions/s0", "session", { key: "s0", viewer, lang: "en" }],
    ["/sessions/s0?turns=2", "session", { key: "s0", viewer, lang: "en", turns: "2" }],
    ["/sessions/s0/timeline?limit=5", "timeline", { key: "s0", lang: "en", limit: "5" }],
    ["/threads", "threads", { viewer, session: null, lang: "en" }],
    ["/threads?session=s1", "threads", { viewer, session: "s1", lang: "en" }],
    [`/threads/${thread}`, "thread", { id: String(thread), viewer, lang: "en" }],
    [`/threads/${thread}/entries`, "entries", { viewer, thread, params: [] }],
    [`/threads/${thread}/entries?before=20&limit=5`, "entries", { viewer, thread, params: [["before", "20"], ["limit", "5"]] }],
    [`/threads/${thread}/entries?before=x`, "entries", { viewer, thread, params: [["before", "x"]] }],
    [`/threads/${thread}/letters`, "letters", { viewer, thread, params: [] }],
    ["/jobs", "openJobs", { viewer, lang: "en", chats: true }],
    ["/jobs?chats=0", "openJobs", { viewer, lang: "en", chats: false }],
    ["/jobs/none", "job", { id: "none" }],
    ["/jobs/none/log?lines=5", "jobLog", { id: "none", lines: "5" }],
  ] as const;
  // What a read needs prepared first (a station's pool prepares it as a read is refused for it, and the program gives such
  // a request to Node meanwhile), prepared as the station's own readers do: then the program answers each itself.
  const pool = new Readers(data, 1);
  pool.mbReader = binary!;
  t.after(() => pool.close());
  for (const [, op, args] of routes) await pool.read(op, args, "en").catch(() => {});
  const givenBefore = given.length;
  for (const [path, op, args] of routes) {
    const ours = await read(path);
    let theirs: { status: number; body: unknown };
    try { theirs = { status: 200, body: JSON.parse(await worker.read(op, args, "en")) }; }
    catch (e) { theirs = { status: (e as { status: number }).status, body: { error: (e as Error).message } }; }
    assert.deepEqual(ours, theirs, `${path}: ${diffAt(ours, theirs)}`);
  }
  // several in one (admin.ts `batch`): each as its own GET, one it does not read in a batch refused there
  const gets = [`/threads/${thread}/entries?limit=5`, "/sessions/s0", "/sessions/s0/timeline?limit=3", `/threads/${thread}`, "/nope"];
  const bs = await theirs.openBi();
  await bs.write(Buffer.from(`${JSON.stringify({ ...routedHead, method: "POST", path: "/admin/api/batch" })}\n${JSON.stringify({ gets })}`));
  await bs.finish();
  const all = await readAll(bs);
  const at = all.indexOf(10);
  const bh = JSON.parse(all.subarray(0, at).toString());
  const bb = all.subarray(at + 1);
  const batched = JSON.parse((bh.headers["content-encoding"] === "zstd" ? zstdDecompressSync(bb) : bb).toString());
  const expected = { answers: [
    { status: 200, body: JSON.parse(await worker.read("entries", { viewer, thread, params: [["limit", "5"]] }, "en")) },
    { status: 200, body: JSON.parse(await worker.read("session", { key: "s0", viewer, lang: "en" }, "en")) },
    { status: 200, body: JSON.parse(await worker.read("timeline", { key: "s0", lang: "en", limit: "3" }, "en")) },
    { status: 200, body: JSON.parse(await worker.read("thread", { id: String(thread), viewer, lang: "en" }, "en")) },
    { status: 400, body: { error: "not read in a batch: /nope" } },
  ] };
  assert.equal(bh.status, 200, JSON.stringify(bh));
  assert.deepEqual(batched, expected, diffAt(batched, expected) ?? "");
  // the event stream: Node's, carried and compressed by the program as it comes, let go once the device is gone
  {
    // (a connection of its own: the device goes by closing it)
    const acceptedEvents = station.accept();
    const own = await device.connect(addrOf(station), ALPN);
    const ownConn = (await acceptedEvents)!;
    served.viewer(ownConn.handed!, viewer);
    await (await own.openBi()).write(Buffer.from('{"hello":1}\n'));
    void ownConn.acceptBi();
    // two streams of it: what is told both is given the program once (served.ts `#piece`), and arrives on each
    const open = async () => {
      const es = await own.openBi();
      await es.write(Buffer.from(`${JSON.stringify({ ...routedHead, path: "/admin/api/events?shared=1" })}\n`));
      await es.finish();
      const z = createZstdDecompress();
      const got = { seen: "", head: null as any };
      z.on("data", (b: Buffer) => (got.seen += b.toString()));
      let carry = Buffer.alloc(0);
      const until = async (want: string) => {
        while (!got.seen.includes(want)) {
          const b = await es.read();
          assert.ok(b !== null, `the stream ended before ${want}: ${got.seen}`);
          if (got.head === null) {
            carry = Buffer.concat([carry, b]);
            const at = carry.indexOf(10);
            if (at < 0) continue;
            got.head = JSON.parse(carry.subarray(0, at).toString());
            await new Promise<void>((r) => z.write(carry.subarray(at + 1), () => r()));
          } else await new Promise<void>((r) => z.write(b, () => r()));
          // (what it decompressed is told before its write's callback; a turn more for its 'data')
          await new Promise((r) => setImmediate(r));
        }
      };
      return { got, until };
    };
    const one = await open();
    const two = await open();
    await one.until("event: made");
    await two.until("event: made");
    assert.equal(one.got.head.status, 200);
    assert.equal(one.got.head.headers["content-encoding"], "zstd");
    events.more();
    await one.until("data: 0");
    await two.until("data: 0");
    // gone: the next piece cannot be written, and Node's streams are let go
    own.close(0, "gone");
    for (let i = 0; i < 5 && events.sinks.length > 0; i++) {
      events.more();
      await new Promise((r) => setTimeout(r, 50));
    }
    await events.wentAway;
  }
  // a member's own marks (routes/marks.ts): written there, what changed told the store's followers, answered as there
  {
    const told: any[] = [];
    served.changed = (changes) => told.push(...changes);
    const put = async (method: string, path: string, body?: unknown) => {
      const ms = await theirs.openBi();
      await ms.write(Buffer.from(`${JSON.stringify({ ...routedHead, method, path: `/admin/api${path}` })}\n${body === undefined ? "" : JSON.stringify(body)}`));
      await ms.finish();
      const got = await readAll(ms);
      const at3 = got.indexOf(10);
      const head = JSON.parse(got.subarray(0, at3).toString());
      const bytes = got.subarray(at3 + 1);
      return { status: head.status, body: JSON.parse((head.headers?.["content-encoding"] === "zstd" ? zstdDecompressSync(bytes) : bytes).toString()) };
    };
    assert.deepEqual(await put("PUT", `/threads/${thread}/read`, { n: 7 }), { status: 200, body: { viewer: "p@x", thread, n: 7 } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/read`, { n: 3 }), { status: 200, body: { viewer: "p@x", thread, n: 7 } });
    assert.equal(store.readPosition("p@x", thread), 7);
    assert.deepEqual(await put("PUT", `/threads/${thread}/read`, { n: -1 }), { status: 400, body: { error: tr("en", "station.admin.badN") } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/hidden`, { hidden: true }), { status: 200, body: { hidden: true } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/muted`, { muted: true }), { status: 200, body: { muted: true } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/muted`, { muted: "x" }), { status: 400, body: { error: "muted must be a boolean" } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/keep`), { status: 200, body: { kept: true } });
    assert.deepEqual([...store.keptChats("p@x")], [thread]);
    assert.deepEqual(await put("DELETE", `/threads/${thread}/keep`), { status: 200, body: { kept: false } });
    assert.deepEqual(await put("PUT", "/sessions/s0/pin"), { status: 200, body: { session: "s0", pinned: true } });
    assert.ok(store.pins("p@x").has("s0"));
    assert.deepEqual(await put("DELETE", "/sessions/s0/pin"), { status: 200, body: { session: "s0", pinned: false } });
    assert.deepEqual(await put("PUT", "/sessions/none/pin"), { status: 404, body: { error: "unknown session none" } });
    assert.deepEqual(await put("PUT", `/threads/${hidden}/read`, { n: 1 }), { status: 404, body: { error: `unknown thread ${hidden}` } });
    assert.deepEqual(told.map((c) => c.type), ["read", "read", "hidden", "muted", "dismissed", "dismissed", "pins", "pins"]);
    assert.deepEqual(told[3], { type: "muted", viewer: "p@x", thread, muted: true });
    // names given by hand: a session's with its own chat, a chat's answered as it is read; the chats told named
    told.length = 0;
    const titled: number[] = [];
    served.changed = (changes, named) => (told.push(...changes), titled.push(...named));
    const home = store.openThreadOf("ember", "CHAT", "ch", "Home", null, "s1").id;
    assert.deepEqual(await put("POST", "/sessions/s1/title", { title: `  ${"名".repeat(85)} ` }), { status: 200, body: { ok: true } });
    assert.equal(store.getSession("s1")!.title, "名".repeat(80));
    assert.equal(store.getThread(home)!.title, "名".repeat(80));
    assert.deepEqual(await put("POST", "/sessions/s2/title", { title: "  " }), { status: 200, body: { ok: true } });
    assert.equal(store.getSession("s2")!.title, null);
    assert.deepEqual(await put("POST", "/sessions/none/title", { title: "x" }), { status: 404, body: { error: "unknown session none" } });
    const renamed = await put("PUT", `/threads/${thread}/title`, { title: " Renamed " });
    assert.equal(store.getThread(thread)!.title, "Renamed");
    assert.deepEqual(renamed, await put("GET", `/threads/${thread}`));
    assert.equal(renamed.body.title, "Renamed");
    const slack = store.openThread("slack", "C1", "1.0", "Slack", null).id;
    assert.deepEqual(await put("PUT", `/threads/${slack}/title`, { title: "x" }), { status: 400, body: { error: tr("en", "station.admin.renameOnlyStillfail") } });
    assert.deepEqual(titled, [home, thread]);
    // a card the member will not take up: an agent's post, or one with a card; a person's is nothing waiting
    const [asks] = store.insertMessage({ ...newMessage(thread, "100", "agent", "s0", "asks"), at: 1000 } as ReturnType<typeof newMessage>);
    const agent = { n: asks };
    assert.deepEqual(await put("PUT", `/threads/${thread}/dismissed`, { n: agent.n }), { status: 200, body: { dismissed: { thread, n: agent.n } } });
    assert.ok(store.dismissed("p@x").has(`${thread}:${agent.n}`));
    assert.deepEqual(await put("PUT", `/threads/${thread}/dismissed`, { n: 1 }), { status: 404, body: { error: tr("en", "station.admin.nothingWaiting") } });
    assert.deepEqual(await put("PUT", `/threads/${thread}/dismissed`, { n: 0 }), { status: 400, body: { error: tr("en", "station.admin.badN") } });
    assert.deepEqual(told.map((c) => c.type), ["session", "thread", "session", "thread", "dismissed"]);
    assert.deepEqual(told.at(-1), { type: "dismissed", viewer: "p@x", card: { thread, n: agent.n } });
  }
  // a person's message in words alone (routes/hub.ts, sessions/lifecycle.ts `say`): claimed of Node, written there as
  // store.ts writes one, told Node; a keyed one asked again given its first answer; one with more, Node's
  {
    const said: any[] = [];
    const kept = new Map<string, any>();
    let ts = 1_700_000_000_000_000;
    served.says = {
      claim: async (_v, path, key) => {
        if (key !== null && kept.has(`${path}|${key}`)) return { kept: kept.get(`${path}|${key}`) };
        const t = ++ts;
        return { ts: `${Math.floor(t / 1e6)}.${String(t % 1e6).padStart(6, "0")}`, settle: (a) => { if (key !== null && a !== null) kept.set(`${path}|${key}`, a); } };
      },
      said: (thread, n, text, row) => said.push({ thread, n, text, row }),
    };
    const post = async (body: unknown, key?: string) => {
      const ms = await theirs.openBi();
      const h = { ...routedHead, method: "POST", path: `/admin/api/threads/${thread}/messages`, headers: { ...routedHead.headers, ...(key ? { "idempotency-key": key } : {}) } };
      await ms.write(Buffer.from(`${JSON.stringify(h)}\n${JSON.stringify(body)}`));
      await ms.finish();
      const got = await readAll(ms);
      const at4 = got.indexOf(10);
      return { status: JSON.parse(got.subarray(0, at4).toString()).status, body: JSON.parse(got.subarray(at4 + 1).toString()) };
    };
    const before = given.length;
    const first = await post({ text: "  hello there  ", client: "android 0.1.9300\u0007" }, "k1");
    assert.equal(first.status, 200);
    assert.equal(typeof first.body.n, "number");
    // (told Node on the program's own line, which may come after the answer reached the device)
    for (let i = 0; i < 100 && said.length === 0; i++) await new Promise((r) => setTimeout(r, 10));
    assert.equal(said.length, 1);
    // the row as the store wrote a message of the same words: every column but where and when
    const row = said[0].row;
    const [n2] = store.insertMessage({ ...newMessage(thread, "x.1", "person", "p@x", "hello there"), client: "android 0.1.9300", at: row.at } as ReturnType<typeof newMessage>);
    const theirsRow = (store as any).db.prepare("SELECT thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, client, profile, runtime, options, card, at, agent_identity, letter, change FROM entries WHERE thread = ? AND n = ?").get(thread, n2);
    assert.deepEqual({ ...row, n: 0, ts: "" }, { ...theirsRow, n: 0, ts: "" });
    assert.equal(row.n, first.body.n);
    // asked again with its key: its first answer, nothing written
    assert.deepEqual(await post({ text: "hello there" }, "k1"), first);
    assert.equal(said.length, 1);
    assert.deepEqual(await post({ text: "   " }), { status: 400, body: { error: tr("en", "station.admin.emptyMessage") } });
    assert.equal(given.length, before);
    // with files: Node's
    await post({ text: "a file", attachments: [{ path: "x" }] });
    assert.equal(given.length, before + 1);
    assert.equal(given.pop()!.head.path, `/admin/api/threads/${thread}/messages`);
  }
  // a list read again as what changed of it (routes/changed.ts): what the device holds of it, by digest
  for (const [list, args, id] of [
    ["sessions", { connect: null, archived: false, lang: "en", viewer }, "key"],
    ["threads", { viewer, session: null, lang: "en" }, "id"],
    ["chats", { viewer, archived: false }, "id"],
  ] as const) {
    const cs = await theirs.openBi();
    await cs.write(Buffer.from(`${JSON.stringify({ ...routedHead, method: "POST", path: `/admin/api/changed/${list}` })}\n${JSON.stringify({ held: { s1: "x" } })}`));
    await cs.finish();
    const got = await readAll(cs);
    const at2 = got.indexOf(10);
    const h = JSON.parse(got.subarray(0, at2).toString());
    const b = got.subarray(at2 + 1);
    const ours = JSON.parse((h.headers["content-encoding"] === "zstd" ? zstdDecompressSync(b) : b).toString());
    const want = JSON.parse(await worker.read("changed", { op: list, args, id, held: { s1: "x" }, runtimes: [...RUNTIME_KINDS] }, "en"));
    assert.equal(h.status, 200, JSON.stringify(h));
    assert.deepEqual(ours, want, `changed/${list}: ${diffAt(ours, want)}`);
  }
  assert.equal(given.length, givenBefore, `given to Node: ${given.slice(givenBefore).map((g) => g.head.path).join(", ")}`);
  // what is of another workspace, and a thread that is no number: not there, as the admin API says
  assert.deepEqual(await read("/sessions/elsewhere"), { status: 404, body: { error: "unknown session elsewhere" } });
  assert.deepEqual(await read(`/threads/${hidden}/entries`), { status: 404, body: { error: `unknown thread ${hidden}` } });
  assert.deepEqual(await read("/threads/abc/entries"), { status: 404, body: { error: "unknown thread abc" } });

  // a core that does not take every runtime: given to Node, its answer said as Node made it
  const old = await ask(theirs, { ...routedHead, headers: { ...routedHead.headers, "stillfail-runtimes": "claude" } });
  assert.equal(old.head.status, 200);
  assert.equal(old.body.toString(), '{"from":"node"}');
  assert.equal(given.length, 1);
  assert.equal(given[0]!.head.path, "/admin/api/chats?shared=1");

  // a core under the floor: told to update, by the program
  const tooOld = await ask(theirs, { ...routedHead, headers: { ...routedHead.headers, "stillfail-build": "0.1.1001" } });
  assert.equal(tooOld.head.status, 426);
  assert.equal(JSON.parse(tooOld.body.toString()).update, true);

  // another protocol's connections are not routed: its request comes to Node
  const acceptedOther = station.accept();
  const other = await device.connect(addrOf(station), OTHER);
  const otherConn = (await acceptedOther)!;
  const s = await other.openBi();
  await s.write(Buffer.from('{"x":0}\n'));
  const o = await other.openBi();
  await o.write(Buffer.from(`${JSON.stringify(routedHead)}\n`));
  const o1 = (await otherConn.acceptBi())!;
  const o2 = (await otherConn.acceptBi())!;
  assert.equal(await lineOf(o1), '{"x":0}\n');
  assert.equal(JSON.parse(await lineOf(o2)).path, "/admin/api/chats?shared=1");
});
