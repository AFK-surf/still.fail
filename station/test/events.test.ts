// GET /events: what is written told as it is written (each device makes its sidebar and a thread's summary itself),
// one `session` event per burst, the shared chat list by what changed, `read` only to its viewer, job logs as they grow; and each event with its id (the station's run, its number), what was told
// told again to a stream that takes over from another or comes back after its link went (`since`).
import type { Clock } from "effect";
import assert from "node:assert/strict";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Events, type EventsDeps } from "../src/api/events.ts";
import { KEPT_MS } from "../src/api/event-log.ts";
import type { StoreChange } from "../src/store/rows.ts";
import { settle, testClock } from "./hub-fakes.ts";

const viewer = (email: string) => ({ sub: email, email, name: email, role: "member", workspace: "w", device: "d" });

/// A station process's events. `handover`: what goes over to the next process; `db`: the rows and overview of another's
/// (the same station's, in the next process).
function setup(clock?: Clock.Clock, handover?: EventsDeps["handover"], db?: { rows: Record<string, any[]>; overview: { running: number } }) {
  let listener: (c: StoreChange) => void = () => {};
  const rows: Record<string, any[]> = db?.rows ?? { "a@x": [{ id: "1", title: "one" }], "b@x": [] };
  const overview = db?.overview ?? { running: 0 };
  const reads: string[] = [];
  const readers: any = {
    read: async (op: string, args: any) => {
      reads.push(op);
      if (op === "summary") return JSON.stringify({ key: args.key });
      // The shared chat list (read/views.ts sharedOf): here a@x's rows.
      if (op === "sharedOf") {
        const all = rows["a@x"] ?? [];
        return JSON.stringify({ rows: all, scope: args.sessions === null ? null : [...args.sessions, ...all.map((r) => r.id)] });
      }
      throw new Error(op);
    },
  };
  const dir = mkdtempSync(join(tmpdir(), "events-"));
  const events = new Events({
    readers,
    // What is said is told as the store wrote it, never read first (no `entries` read here).
    said: (_thread, entries) => entries.map((e) => ({ n: e.n, text: "hi" })),
    subscribe: (l) => ((listener = l), () => {}),
    host: async () => ({ cpu: 1 }),
    jobLog: (id) => (id === "j" ? join(dir, "j.log") : null),
    tail: (path) => require("node:fs").readFileSync(path, "utf8"),
    outputAt: () => 7,
    sessionExists: (key) => key !== "gone",
    clock,
    handover,
  });
  events.follow({ overview: async () => ({ ...overview }) });
  return { events, rows, reads, readers, overview, change: (c: StoreChange) => listener(c), dir };
}

/// Reads a stream's events as they come.
function reader(body: AsyncIterable<Buffer>) {
  const it = body[Symbol.asyncIterator]();
  const got: { id?: string; event?: string; data?: any; raw: string }[] = [];
  let pump: Promise<void> | null = null;
  const more = () =>
    (pump ??= (async () => {
      for (;;) {
        const next = await it.next();
        if (next.done) return;
        const raw = next.value.toString();
        const m = /^(?:id: ([0-9a-f]+\.\d+)\n)?event: (.+)\ndata: (.*)\n\n$/.exec(raw);
        // `made`, said first to every stream (it makes its rows itself), is kept as it came alone.
        got.push(m && m[2] !== "made" ? { id: m[1], event: m[2], data: JSON.parse(m[3]!), raw } : { raw });
      }
    })());
  more();
  return { got, close: () => it.return?.() };
}
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);

/// The process before, as the next one finds it (run/hub.json): the one that handed over (every one of a test is this
/// process), gone once `gone` is.
const previous = (gone: Promise<void> = Promise.resolve()) => ({ pid: process.pid, gone });

/// Opens a@x's stream from `since`: whether it was resumed, and what it is told.
async function opened(events: Events, since: string | null = null) {
  const answer = await events.open(viewer("a@x"), "zh", false, [], [], since);
  return { resumed: (answer.headers as Record<string, string>)["stillfail-resumed"] === "1", ...reader(answer.body as AsyncIterable<Buffer>) };
}

async function openedShared(events: Events, since: string | null = null) {
  const answer = await events.open(viewer("a@x"), "zh", false, [], [], since, false, [], false, true);
  return { resumed: (answer.headers as Record<string, string>)["stillfail-resumed"] === "1", ...reader(answer.body as AsyncIterable<Buffer>) };
}

test("the first change can remove a shared chat", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const stream = await openedShared(events);
  rows["a@x"] = [];
  change({ type: "threadRemoved", id: 1, ws: "w" });
  await settle();
  assert.ok(stream.got.some((e) => e.event === "chat-shared-removed" && e.data.id === "1"));
  await stream.close();
});

test("shared changes are kept while only an older stream follows", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const old = await opened(events);
  const shared = await openedShared(events);
  change({ type: "session", key: "1" });
  await settle();
  const heard = shared.got.findLast((e) => e.id)!.id!;
  await shared.close();
  rows["a@x"] = [...rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  change({ type: "session", key: "2" });
  await settle();
  const back = await openedShared(events, heard);
  await settle();
  assert.equal(back.resumed, true);
  assert.ok(back.got.some((e) => e.event === "chat-shared" && e.data.id === "2"));
  await back.close();
  await old.close();
});

test("a shared chat moving between workspaces is removed from the old one, including on replay", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const from = await openedShared(events);
  const answer = await events.open({ ...viewer("b@x"), workspace: "other", home: false }, "zh", false, [], [], null, false, [], false, true);
  const to = reader(answer.body as AsyncIterable<Buffer>);
  change({ type: "session", key: "1" });
  await settle();
  const heard = from.got.findLast((e) => e.id)!.id!;
  await from.close();
  rows["a@x"] = [{ id: "1", title: "one", ws: "other" }];
  change({ type: "session", key: "1" });
  await settle();
  const back = await openedShared(events, heard);
  await settle();
  assert.equal(back.resumed, true);
  assert.ok(back.got.some((e) => e.event === "chat-shared-removed" && e.data.id === "1"));
  assert.ok(to.got.some((e) => e.event === "chat-shared" && e.data.id === "1"));
  await back.close();
  await to.close();
});

test("changes while the first shared list is read are included in its baseline", async () => {
  const { events, rows, readers, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "old", ws: "w" }];
  const read = readers.read;
  let finish: (() => void) | undefined;
  readers.read = async (op: string, args: unknown) => {
    if (op !== "sharedOf" || finish) return read(op, args);
    const captured = await read(op, args);
    return new Promise<string>((resolve) => { finish = () => resolve(captured); });
  };
  const opening = openedShared(events);
  await settle();
  assert.ok(finish);
  rows["a@x"] = [{ id: "1", title: "new", ws: "w" }];
  change({ type: "session", key: "1" });
  await settle();
  finish();
  const stream = await opening;
  await settle();
  rows["a@x"] = [{ id: "1", title: "old", ws: "w" }];
  change({ type: "session", key: "1" });
  await settle();
  assert.ok(stream.got.some((e) => e.event === "chat-shared" && e.data.title === "old"));
  await stream.close();
});

test("an old handover without a shared baseline cannot resume a shared stream", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  const before = setup(time.clock, { file, previous: previous() });
  const lost = await openedShared(before.events);
  before.change({ type: "session", key: "1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await before.events.handOver();
  const handed = JSON.parse(readFileSync(file, "utf8"));
  delete handed.shared;
  writeFileSync(file, JSON.stringify(handed));
  const after = setup(time.clock, { file, previous: previous() }, before);
  const back = await openedShared(after.events, heard);
  await settle();
  assert.equal(back.resumed, false);
  assert.ok(back.got.some((e) => e.event === "missed"));
  await lost.close();
  await back.close();
});

test("a failed shared update ends its stream and prevents resuming across the missing change", async () => {
  const { events, rows, readers, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const stream = await openedShared(events);
  change({ type: "session", key: "1" });
  await settle();
  const heard = stream.got.findLast((e) => e.id)!.id!;
  const read = readers.read;
  let fail = true;
  readers.read = (op: string, args: unknown) => {
    if (op === "sharedOf" && fail) { fail = false; return Promise.reject(new Error("reader failed")); }
    return read(op, args);
  };
  rows["a@x"] = [...rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  change({ type: "session", key: "2" });
  await settle();
  assert.equal(events.inUse(), false);
  const back = await openedShared(events, heard);
  await settle();
  assert.equal(back.resumed, false);
  assert.ok(back.got.some((e) => e.event === "missed"));
  await back.close();
});

test("several shared streams read the initial list only once", async () => {
  const { events, reads } = setup(testClock().clock);
  const [first, second] = await Promise.all([openedShared(events), openedShared(events)]);
  assert.equal(reads.filter((op) => op === "sharedOf").length, 1);
  await first.close();
  await second.close();
});

test("the first change after a shared stream opens tells its chat", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const stream = await openedShared(events);
  await settle();
  rows["a@x"] = [...rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  change({ type: "session", key: "2" });
  await settle();
  assert.ok(stream.got.some((e) => e.event === "chat-shared" && e.data.id === "2"));
  await stream.close();
});

test("a shared stream coming back is told a chat created while nobody followed", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const lost = await openedShared(events);
  change({ type: "session", key: "1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  rows["a@x"] = [...rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  change({ type: "session", key: "2" });
  await settle();
  const back = await openedShared(events, heard);
  await settle();
  assert.equal(back.resumed, true);
  assert.ok(back.got.some((e) => e.event === "chat-shared" && e.data.id === "2"));
  await back.close();
});

test("a stream coming back says where the log was as it joined: what it tells up to there is told again, after it as it happens", async () => {
  const { events, rows, change } = setup(testClock().clock);
  rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const lost = await openedShared(events);
  change({ type: "session", key: "1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  rows["a@x"] = [...rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  change({ type: "session", key: "2" });
  await settle();
  const answer = await events.open(viewer("a@x"), "zh", false, [], [], heard, false, [], false, true);
  const back = reader(answer.body as AsyncIterable<Buffer>);
  const head = (answer.headers as Record<string, string>)["stillfail-head"]!;
  await settle();
  const n = (id: string) => Number(id.split(".")[1]);
  const told = (id: string) => back.got.find((e) => e.event === "chat-shared" && e.data.id === id && e.id);
  assert.ok(told("2") && n(told("2")!.id!) <= n(head), `${head} ${told("2")?.id}`);
  rows["a@x"] = [...rows["a@x"]!, { id: "3", title: "later", ws: "w" }];
  change({ type: "session", key: "3" });
  await settle();
  assert.ok(told("3") && n(told("3")!.id!) > n(head), `${head} ${told("3")?.id}`);
  // Not resumed: none said.
  const answered = await events.open(viewer("a@x"), "zh", false, [], [], null, false, [], false, true);
  assert.equal((answered.headers as Record<string, string>)["stillfail-head"], undefined);
  const fresh = reader(answered.body as AsyncIterable<Buffer>);
  await fresh.close();
  await back.close();
});

test("a shared stream coming back after station handover is told a chat created while away", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  const before = setup(time.clock, { file, previous: previous() });
  before.rows["a@x"] = [{ id: "1", title: "one", ws: "w" }];
  const lost = await openedShared(before.events);
  before.change({ type: "session", key: "1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  await before.events.handOver();
  const after = setup(time.clock, { file, previous: previous() }, before);
  await settle();
  after.rows["a@x"] = [...after.rows["a@x"]!, { id: "2", title: "new", ws: "w" }];
  after.change({ type: "session", key: "2" });
  await settle();
  const back = await openedShared(after.events, heard);
  await settle();
  assert.equal(back.resumed, true);
  assert.ok(back.got.some((e) => e.event === "chat-shared" && e.data.id === "2"));
  await back.close();
});

test("changes are told as events, read only to its viewer, no sidebar read", async () => {
  const { events, rows, change, reads } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const b = reader((await events.open(viewer("b@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  await settle();
  assert.equal(a.got[0]!.raw, "retry: 3000\n\n");
  assert.equal(a.got[1]!.raw, `event: made\ndata: ${JSON.stringify({ rows: true, marks: true })}\n\n`, "told first it makes its rows");
  rows["a@x"] = [{ id: "1", title: "one" }, { id: "2", title: "two" }];
  reads.length = 0;
  // A burst: one `session` event, and nothing of anyone's sidebar read.
  change({ type: "session", key: "s" });
  change({ type: "session", key: "s" });
  change({ type: "session", key: "gone" });
  change({ type: "read", viewer: "b@x", thread: 3, n: 9 });
  await settle();
  const ofA = a.got.filter((e) => e.event).map((e) => [e.event, e.data]);
  assert.deepEqual(ofA, [["session", { key: "s" }]]);
  const ofB = b.got.filter((e) => e.event).map((e) => [e.event, e.data]);
  assert.deepEqual(ofB, [["read", { viewer: "b@x", thread: 3, n: 9 }], ["session", { key: "s" }]]);
  assert.deepEqual(reads, ["summary"]);
  // Ids go up on each stream, of one run of the station; what is told to everyone has one id on all streams.
  const numbers = (got: { id?: string }[]) => got.filter((e) => e.id).map((e) => Number(e.id!.split(".")[1]));
  for (const got of [a.got, b.got]) assert.deepEqual(numbers(got), [...numbers(got)].sort((x, y) => x - y));
  assert.equal(new Set([...a.got, ...b.got].filter((e) => e.id).map((e) => e.id!.split(".")[0])).size, 1);
  const sessionIds = [a, b].map((s) => s.got.find((e) => e.event === "session")!.id);
  assert.equal(sessionIds[0], sessionIds[1]);
  rows["a@x"] = [{ id: "2", title: "two" }];
  change({ type: "threadRemoved", id: 1 });
  await settle();
  assert.deepEqual(a.got.slice(-1).map((e) => [e.event, e.data]), [["thread-removed", { id: 1 }]]);
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  await settle();
  assert.deepEqual(b.got.filter((e) => e.event === "thread").map((e) => e.data), [{ id: 4, entries: [{ n: 1, text: "hi" }] }]);
  await a.close();
  await b.close();
  assert.equal(events.inUse(), false);
});

test("what a viewer marks is told as written to their streams alone", async () => {
  const { events, change } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const b = reader((await events.open(viewer("b@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  await settle();
  change({ type: "pins", viewer: "a@x", session: "s", at: 5 });
  change({ type: "dismissed", viewer: "a@x", card: { thread: 3, n: 7 } });
  change({ type: "dismissed", viewer: "a@x", kept: { thread: 3, kept: false } });
  change({ type: "hidden", viewer: "a@x", thread: 3, hidden: true });
  change({ type: "muted", viewer: "a@x", thread: 3, muted: true });
  await settle();
  const told = (got: { event?: string; data?: any }[]) => got.filter((e) => e.event === "pin" || e.event === "dismiss" || e.event === "kept" || e.event === "hidden" || e.event === "muted").map((e) => [e.event, e.data]);
  assert.deepEqual(told(a.got), [["pin", { session: "s", at: 5 }], ["dismiss", { thread: 3, n: 7 }], ["kept", { thread: 3, kept: false }], ["hidden", { thread: 3, hidden: true }], ["muted", { thread: 3, muted: true }]]);
  assert.deepEqual(told(b.got), []);
  // What is written of a chat beside what is said in it, to those who see it.
  change({ type: "chatMark", thread: 3, session: "s", archive: { suggested: 4 } });
  await settle();
  assert.deepEqual(a.got.filter((e) => e.event === "chat-mark").map((e) => e.data), [{ thread: 3, session: "s", archive: { suggested: 4 } }]);
  await a.close();
  await b.close();
});

test("a stream that takes over is told first what was told to everyone after the last id its predecessor gave", async () => {
  const time = testClock();
  const { events, change } = setup(time.clock);
  const old = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  change({ type: "session", key: "s1" });
  await settle();
  const heard = old.got.find((e) => e.event === "session")!.id!;
  // Told while the new stream is asked for (it is not the station's yet): only the old one has them.
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  change({ type: "read", viewer: "b@x", thread: 3, n: 9 });
  change({ type: "read", viewer: "a@x", thread: 3, n: 9 });
  await settle();
  const fresh = reader((await events.open(viewer("a@x"), "zh", false, [], [], heard)).body as AsyncIterable<Buffer>);
  await settle();
  const told = (got: typeof old.got) => got.filter((e) => e.event === "thread" || e.event === "read").map((e) => [e.id, e.event]);
  // Again, with the ids they had, and only what is this viewer's (not b@x's read).
  assert.deepEqual(told(fresh.got), told(old.got));
  assert.deepEqual(told(fresh.got).map(([, event]) => event).sort(), ["read", "thread"]);
  // From then on, as to everyone.
  change({ type: "thread", id: 5, entries: [{ n: 1 } as any] });
  await settle();
  assert.deepEqual(fresh.got.filter((e) => e.event === "thread").map((e) => e.data.id), [4, 5]);
  await old.close();
  await fresh.close();
});

test("a stream that takes over from what is not kept any more, or another run's, is told it missed it", async () => {
  const time = testClock();
  const { events, change } = setup(time.clock);
  const old = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  change({ type: "thread", id: 3, entries: [{ n: 1 } as any] });
  await settle();
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  await settle();
  const [three] = old.got.filter((e) => e.event === "thread").map((e) => e.id!);
  // The last it heard (thread 4's summary to its viewer came after thread 4).
  const four = old.got.findLast((e) => e.id)!.id!;
  const told = async (since: string) => {
    const s = reader((await events.open(viewer("a@x"), "zh", false, [], [], since)).body as AsyncIterable<Buffer>);
    await settle();
    await s.close();
    return s.got.filter((e) => e.event === "thread" || e.event === "missed").map((e) => (e.event === "thread" ? e.data.id : e.event));
  };
  assert.deepEqual(await told(`${"0a0a0a0a"}.1`), ["missed"], "another run's");
  // An hour on, more told: 3 and 4 are let go.
  await time.adjust(3_601_000);
  change({ type: "thread", id: 5, entries: [{ n: 1 } as any] });
  await settle();
  change({ type: "thread", id: 6, entries: [{ n: 1 } as any] });
  await settle();
  assert.deepEqual(await told(three!), ["missed"], "4 came after it, and is not kept any more");
  // After the last let go, or later: all that came after is kept, told again.
  assert.deepEqual(await told(four!), [5, 6]);
  assert.deepEqual(await told(old.got.filter((e) => e.event === "thread").at(-2)!.id!), [6]);
  await old.close();
});

test("a stream that comes back after its link went is told what was told meanwhile and how its overview stands", async () => {
  const time = testClock();
  const { events, rows, overview, change } = setup(time.clock);
  const open = async (since?: string) => {
    const answer = await events.open(viewer("a@x"), "zh", false, [], [], since ?? null);
    return { resumed: (answer.headers as Record<string, string>)["stillfail-resumed"] === "1", ...reader(answer.body as AsyncIterable<Buffer>) };
  };
  const lost = await open();
  change({ type: "session", key: "s1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  assert.equal(events.inUse(), false);
  // Nobody follows: what is told is still made and kept a while, for one coming back.
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  change({ type: "processes" } as StoreChange);
  rows["a@x"] = [{ id: "1", title: "one, renamed" }, { id: "2", title: "two" }];
  overview.running = 1;
  change({ type: "session", key: "s2" });
  await settle();
  await time.adjust(60_000);
  const back = await open(heard);
  await settle();
  assert.equal(back.resumed, true);
  const told = back.got.filter((e) => e.event).map((e) => [e.event, e.event === "thread" ? e.data.id : e.event === "session" ? e.data.key : e.data]);
  assert.deepEqual(told, [
    ["thread", 4],
    ["session", "s2"],
    // Its overview, as it changed while none of its viewer's streams was there to be told.
    ["overview", { running: 1 }],
  ]);
  // Its overview again only as it changes.
  change({ type: "processes" } as StoreChange);
  await settle();
  assert.equal(back.got.filter((e) => e.event === "overview").length, 1);
  await back.close();
  // Past KEPT_MS with nobody: what was told is let go, and one coming back from before reads the station again.
  await time.adjust(3_601_000);
  const late = await open(back.got.findLast((e) => e.id)!.id!);
  await settle();
  assert.equal(late.resumed, false);
  assert.deepEqual(late.got.filter((e) => e.event).map((e) => e.event), ["missed"]);
  await late.close();
});

test("a stream read afresh is told where the log is, so the next goes on from there though nothing was told", async () => {
  const time = testClock();
  const { events, change } = setup(time.clock);
  const open = async (since?: string) => {
    const answer = await events.open(viewer("a@x"), "zh", false, [], [], since ?? null);
    return { resumed: (answer.headers as Record<string, string>)["stillfail-resumed"] === "1", ...reader(answer.body as AsyncIterable<Buffer>) };
  };
  // Something told before it, to a stream gone since: the new one is not told it, and goes on from after it.
  const before = await open();
  change({ type: "session", key: "s1" });
  await settle();
  await before.close();
  const first = await open();
  await settle();
  const at = first.got.map((e) => /^id: ([0-9a-f]+\.\d+)\n\n$/.exec(e.raw)?.[1]).find((id) => id !== undefined);
  assert.ok(at, JSON.stringify(first.got));
  assert.deepEqual(first.got.filter((e) => e.event).map((e) => e.event), []);
  // A quiet station: nothing else came on it before its link went.
  await first.close();
  change({ type: "session", key: "s2" });
  await settle();
  const back = await open(at);
  await settle();
  assert.equal(back.resumed, true);
  // What was told after it (s2), and not what was told before it (s1).
  assert.deepEqual(back.got.filter((e) => e.event === "session").map((e) => e.data.key), ["s2"]);
  // Resumed, it is told no position of its own: what comes on it says where it is.
  assert.equal(back.got.filter((e) => /^id: [^\n]+\n\n$/.test(e.raw)).length, 0);
  await back.close();
});

test("a job's log is told now and as it grows", async () => {
  const time = testClock();
  const { events, dir } = setup(time.clock);
  writeFileSync(join(dir, "j.log"), "one\n");
  const s = reader((await events.open(viewer("a@x"), "zh", false, [], [["j", 50], ["nothing", 5]])).body as AsyncIterable<Buffer>);
  await settle();
  appendFileSync(join(dir, "j.log"), "two\n");
  // Looked at again within 5 s, its watch or not (what the watch tells is side/events.test.ts's), once.
  await time.adjust(5_000);
  await settle();
  const logs = s.got.filter((e) => e.event === "job-log").map((e) => e.data);
  assert.deepEqual(logs, [
    { id: "j", lines: 50, text: "one\n", outputAt: 7 },
    { id: "j", lines: 50, text: "one\ntwo\n", outputAt: 7 },
  ]);
  await s.close();
});

test("what the agents spent is told at most once a minute: the first change at once, the last at the end of it", async () => {
  const time = testClock();
  const { events, change } = setup(time.clock);
  const s = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const told = () => s.got.filter((e) => e.event === "usage").length;
  change({ type: "usage", sessions: ["k"] });
  await settle();
  assert.equal(told(), 1);
  // A model call every 15 s: told again once, a minute after the first.
  for (let i = 0; i < 3; i++) {
    await time.adjust(15_000);
    change({ type: "usage", sessions: ["k"] });
    await settle();
  }
  assert.equal(told(), 1);
  await time.adjust(15_000);
  await settle();
  assert.equal(told(), 2);
  // Quiet a while: the next change is told at once.
  await time.adjust(120_000);
  change({ type: "usage", sessions: ["k"] });
  await settle();
  assert.equal(told(), 3);
  await s.close();
});

test("usage is told with when the earliest call recorded since was made, each telling kept for one who comes back", async () => {
  // A page holding the usage reads again only the days from then on (client/core-ts/src/station/usage-part.ts); read
  // whole at each telling, it was 2 to 23 s of the station's time a read on a station (2026-11-02).
  const time = testClock();
  const { events, change } = setup(time.clock);
  const s = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const told = (got: typeof s.got) => got.filter((e) => e.event === "usage").map((e) => e.data);
  change({ type: "usage", sessions: ["k"], from: 5_000 });
  await settle();
  // In the while, the earliest of the calls said: one made before those told already.
  await time.adjust(15_000);
  change({ type: "usage", sessions: ["k"], from: 9_000 });
  change({ type: "usage", sessions: ["j"], from: 2_000 });
  await settle();
  await time.adjust(45_000);
  await settle();
  // A change that does not say when: all of it.
  await time.adjust(60_000);
  change({ type: "usage", sessions: ["k"] });
  await settle();
  assert.deepEqual(told(s.got), [{ from: 5_000 }, { from: 2_000 }, {}]);
  // One that comes back from before them is told each, not the last alone; from after the first, the others.
  const ids = s.got.filter((e) => e.event === "usage").map((e) => e.id!);
  const run = ids[0]!.split(".")[0];
  for (const [since, want] of [[`${run}.0`, [{ from: 5_000 }, { from: 2_000 }, {}]], [ids[0]!, [{ from: 2_000 }, {}]]] as const) {
    const back = reader((await events.open(viewer("a@x"), "zh", false, [], [], since)).body as AsyncIterable<Buffer>);
    await settle();
    assert.deepEqual(told(back.got), want, since);
    await back.close();
  }
  await s.close();
});

// On a station (2026-11-02 15:41 UTC) what was told of two messages just said waited 50 s and 31 s: each was read back first,
// in line behind other reads. What is said is told as the store wrote it.
test("what is said in a thread is told at once, though no read is ever answered", async () => {
  const { events, change, readers } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  readers.read = () => new Promise(() => {});
  change({ type: "thread", id: 4, entries: [{ n: 7 } as any] });
  change({ type: "letters", id: 4, letters: [{ n: 2 } as any] });
  await settle();
  assert.deepEqual(a.got.filter((e) => e.event === "thread" || e.event === "letters").map((e) => [e.event, e.data]), [
    ["thread", { id: 4, entries: [{ n: 7, text: "hi" }] }],
    ["letters", { id: 4, letters: [{ n: 2, text: "hi" }] }],
  ]);
  await a.close();
});

test("only what is told again has an id: a stream's ids are the log from where it was asked, in order", async () => {
  // A client asks the next stream for what came after the last id it heard. A session's steps, numbered as the latest
  // and told before what was missed, left a client whose stream went in between with the latest id and nothing of
  // what it missed.
  const { events, change } = setup(testClock().clock);
  const first = reader((await events.open(viewer("a@x"), "zh", false, [], [], null)).body as AsyncIterable<Buffer>);
  change({ type: "session", key: "s1" });
  await settle();
  const heard = first.got.findLast((e) => e.id)!.id!;
  await first.close();
  for (const id of [4, 5, 6]) change({ type: "thread", id, entries: [{ n: 1 } as any] });
  await settle();
  // A session followed says its steps as the stream opens.
  events.follow({ live: (_key, _from, _last, send) => (send({ type: "steps", steps: [] }), () => {}) });
  const back = reader((await events.open(viewer("a@x"), "zh", false, [["k", 0, null]], [], heard)).body as AsyncIterable<Buffer>);
  await settle();
  // What is its own has no id, whenever it comes: nothing goes on from it.
  assert.equal(back.got.filter((e) => e.event === "live").length, 1);
  assert.equal(back.got.find((e) => e.event === "live")!.id, undefined);
  change({ type: "thread", id: 7, entries: [{ n: 1 } as any] });
  await settle();
  // With an id: what was told after `heard`, then what is told from now, each number above the one before.
  const logged = back.got.filter((e) => e.id);
  assert.deepEqual(logged.filter((e) => e.event === "thread").map((e) => e.data.id), [4, 5, 6, 7]);
  const ns = logged.map((e) => Number(e.id!.split(".")[1]));
  assert.ok(ns.every((n, i) => n > Number(heard.split(".")[1]) && (i === 0 || n > ns[i - 1]!)), `${heard}: ${ns}`);
  await back.close();
});

test("what says a thing whole is kept as it was last told only", async () => {
  const { events, overview, change } = setup(testClock().clock);
  const first = reader((await events.open(viewer("a@x"), "zh", false, [], [], null)).body as AsyncIterable<Buffer>);
  change({ type: "session", key: "s1" });
  await settle();
  const heard = first.got.findLast((e) => e.id)!.id!;
  // While it is away (another of its viewer's follows on): a session and the overview change again and again, a thread
  // is said in twice.
  const other = reader((await events.open(viewer("a@x"), "zh", false, [], [], null)).body as AsyncIterable<Buffer>);
  await first.close();
  for (let i = 1; i <= 5; i++) {
    overview.running = i;
    change({ type: "processes" } as StoreChange);
    change({ type: "session", key: "s2" });
    if (i % 2 === 1) change({ type: "thread", id: 4, entries: [{ n: i } as any] });
    await settle();
  }
  assert.equal(other.got.filter((e) => e.event === "overview").length, 5, "one following hears each as it is told");
  const back = reader((await events.open(viewer("a@x"), "zh", false, [], [], heard)).body as AsyncIterable<Buffer>);
  await settle();
  const count = (name: string) => back.got.filter((e) => e.event === name).length;
  // Every thing said in a thread (each adds to it); the session and the overview once, as they were last told.
  assert.deepEqual([count("thread"), count("session"), count("overview")], [3, 1, 1]);
  assert.deepEqual(back.got.find((e) => e.event === "overview")!.data, { running: 5 });
  await back.close();
  await other.close();
});

test("a stream that follows the sessions at work is told what each its viewer sees does, from where it stood, naming none", async () => {
  const { events } = setup(testClock().clock);
  const seen: Record<string, string> = { k: "a@x", other: "b@x" };
  const named: string[] = [];
  events.follow({
    held: () => ["k", "other"],
    heldNow: (key) => [{ type: "timeline", start: key === "k" ? 7 : 2, entries: [], usage: null }, { type: "steps", steps: [], phase: null }],
    // A client that does not know yet names the sessions too: they are not followed by name then.
    live: (key) => (named.push(key), () => {}),
  });
  // Only the viewer's sessions.
  (events as any).deps.seen = (v: any, of: any) => !("session" in of) || seen[of.session] === v.email;
  const answer = await events.open(viewer("a@x"), "zh", false, [["k", 0, 200]], [], null, true, [], true);
  assert.equal(answer.headers?.["stillfail-follows"], "running");
  const a = reader(answer.body as AsyncIterable<Buffer>);
  const old = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  await settle();
  assert.deepEqual(named, [], "nothing followed by name");
  const live = () => a.got.filter((e) => e.event === "live").map((e) => [e.data.key, e.data.type, e.data.start ?? null]);
  // As it is now: where its transcript ends, nothing of it; its steps.
  assert.deepEqual(live(), [["k", "timeline", 7], ["k", "steps", null]]);
  // From now on, what it does as it does it; the other viewer's not at all; a stream from before not at all.
  events.heldTold("k", { type: "timeline", start: 7, entries: [{ text: "new" }] });
  events.heldTold("other", { type: "timeline", start: 2, entries: [{ text: "theirs" }] });
  await settle();
  assert.deepEqual(live().slice(2), [["k", "timeline", 7]]);
  assert.equal(old.got.filter((e) => e.event === "live").length, 0);
  await a.close();
  await old.close();
});

test("a stream from before asked nothing new: the sessions it names, as before", async () => {
  const { events } = setup(testClock().clock);
  const named: [string, number][] = [];
  events.follow({ held: () => ["k"], heldNow: () => [], live: (key, from) => (named.push([key, from]), () => {}) });
  const answer = await events.open(viewer("a@x"), "zh", false, [["k", 3, 200]], []);
  assert.equal(answer.headers?.["stillfail-follows"], undefined);
  await settle();
  assert.deepEqual(named, [["k", 3]]);
  reader(answer.body as AsyncIterable<Buffer>).close();
});

test("a named live stream only receives a delayed result while its viewer can still see the session", async () => {
  const { events } = setup(testClock().clock);
  let visible = true;
  let exists = true;
  let send: (message: unknown) => void = () => {};
  (events as any).deps.seen = () => visible;
  (events as any).deps.sessionExists = () => exists;
  events.follow({ live: (_key, _from, _last, tell) => { send = tell; return () => {}; } });
  const stream = reader((await events.open(viewer("a@x"), "zh", false, [["k", 0, null]], [])).body as AsyncIterable<Buffer>);
  try {
    send({ type: "timeline", entries: [{ text: "visible" }] });
    visible = false;
    send({ type: "timeline", entries: [{ text: "hidden" }] });
    visible = true;
    send({ type: "timeline", entries: [{ text: "visible again" }] });
    exists = false;
    send({ type: "timeline", entries: [{ text: "deleted" }] });
    await settle();
    assert.deepEqual(stream.got.filter((e) => e.event === "live").map((e) => e.data.entries[0].text), ["visible", "visible again"]);
  } finally { await stream.close(); }
});

test("the sidebar's rows are the client's to make from what it is told: none read for what is said, a session's summary, a read, a pin", async () => {
  // Every change read every row it could touch again for every viewer: 3 to 5 s each on a station short of memory (2026-11-03).
  const { events, change, reads } = setup(testClock().clock);
  const theirs = reader((await events.open(viewer("a@x"), "zh", false, [], [], null)).body as AsyncIterable<Buffer>);
  await settle();
  assert.deepEqual(reads, [], "not read as it opens: it reads them itself");
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  change({ type: "session", key: "s1" });
  change({ type: "read", viewer: "a@x", thread: 4, n: 1 });
  change({ type: "pins", viewer: "a@x", session: "s1", at: 5 });
  change({ type: "dismissed", viewer: "a@x", card: { thread: 4, n: 1 } });
  await settle();
  assert.deepEqual(reads, ["summary"], "none read but the session's summary it is told");
  assert.deepEqual(theirs.got.filter((e) => e.event === "pin").map((e) => e.data), [{ session: "s1", at: 5 }], "what it makes them of, told");
  // Nor what changes which rows there are (a chat's sessions, a chat gone): told that, it reads what it needs itself.
  change({ type: "thread", id: 4, entries: [] });
  change({ type: "threadRemoved", id: 5 });
  await settle();
  assert.deepEqual(reads, ["summary"]);
  assert.deepEqual(theirs.got.filter((e) => e.event === "chat-changed" || e.event === "thread-removed").map((e) => [e.event, e.data]), [["chat-changed", { thread: 4 }], ["thread-removed", { id: 5 }]]);
  // Come back where it left off: resumed.
  const id = theirs.got.at(-1)!.id!;
  const back = await events.open(viewer("a@x"), "zh", false, [], [], id);
  assert.equal((back.headers as Record<string, string>)["stillfail-resumed"], "1");
  reader(back.body as AsyncIterable<Buffer>).close();
  await theirs.close();
});

test("a stream that comes back to the next station process is resumed there, as the one before would have resumed it", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  const before = setup(time.clock, { file, previous: previous() });
  const lost = await opened(before.events);
  before.change({ type: "processes" } as StoreChange);
  before.change({ type: "session", key: "s1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  // An update: the next process is up before this one stops, and waits for it to be gone.
  const gone = Promise.withResolvers<void>();
  const after = setup(time.clock, { file, previous: previous(gone.promise) }, before);
  // Its streams cut as it stops; what it tells until it hands over is kept all the same, whoever it is for.
  await lost.close();
  before.change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  await settle();
  before.change({ type: "read", viewer: "a@x", thread: 3, n: 9 });
  before.change({ type: "read", viewer: "b@x", thread: 3, n: 9 });
  before.rows["a@x"] = [{ id: "1", title: "one" }, { id: "2", title: "two" }];
  before.change({ type: "session", key: "s2" });
  await settle();
  await before.events.handOver();
  before.change({ type: "session", key: "s9" });
  await settle();
  assert.ok(existsSync(file));
  // Its client comes back to the next one before the old one is gone: answered once it is, from what it handed over.
  const asked = opened(after.events, heard);
  let answered = false;
  void asked.then(() => (answered = true));
  await settle();
  assert.equal(answered, false);
  gone.resolve();
  const back = await asked;
  await settle();
  assert.equal(back.resumed, true);
  assert.equal(existsSync(file), false);
  const told = back.got.filter((e) => e.event).map((e) => [e.event, e.event === "thread" ? e.data.id : e.event === "session" ? e.data.key : e.data]);
  // What came after `since` and is its viewer's (not b@x's read, nothing told once handed over); the overview as it
  // was: not told again.
  assert.deepEqual(told, [
    ["thread", 4],
    ["read", { viewer: "a@x", thread: 3, n: 9 }],
    ["session", "s2"],
  ]);
  // And on from there: the same run, numbered on.
  after.change({ type: "session", key: "s3" });
  await settle();
  const ids = back.got.filter((e) => e.id).map((e) => e.id!.split("."));
  assert.deepEqual(back.got.filter((e) => e.event === "session").map((e) => e.data.key), ["s2", "s3"]);
  assert.ok(ids.every(([run, n], i) => run === heard.split(".")[0] && Number(n) > Number(heard.split(".")[1]) && (i === 0 || Number(n) > Number(ids[i - 1]![1]))), JSON.stringify(ids));
  await back.close();
});

test("what the next process tells before its streams come back is kept for them, as while nobody follows", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  const before = setup(time.clock, { file, previous: previous() });
  const lost = await opened(before.events);
  before.change({ type: "session", key: "s1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  await before.events.handOver();
  // The next one takes up the sessions: what they do is told with nobody following yet, a thread's entries read as
  // the one who followed last has them.
  const after = setup(time.clock, { file, previous: previous() }, before);
  await settle();
  after.change({ type: "thread", id: 5, entries: [{ n: 1 } as any] });
  after.change({ type: "session", key: "s3" });
  await settle();
  await time.adjust(60_000);
  const back = await opened(after.events, heard);
  await settle();
  assert.equal(back.resumed, true);
  const told = back.got.filter((e) => e.event && e.event !== "overview").map((e) => [e.event, e.event === "thread" ? e.data.id : e.event === "session" ? e.data.key : e.data]);
  assert.deepEqual(told, [["thread", 5], ["session", "s3"]]);
  await back.close();
});

test("a stream that comes back to a process that took up nothing to go on from is told it missed it", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  /// A process whose stream was cut, stopped: handing over or not (a crash). The last id its stream heard.
  const stopped = async (hands: boolean) => {
    const before = setup(time.clock, { file, previous: previous() });
    const lost = await opened(before.events);
    before.change({ type: "processes" } as StoreChange);
    before.change({ type: "session", key: "s1" });
    await settle();
    await lost.close();
    if (hands) await before.events.handOver();
    return lost.got.findLast((e) => e.id)!.id!;
  };
  /// Its stream back at the next process: whether it was resumed, and the events it is told.
  const back = async (since: string) => {
    const after = setup(time.clock, { file, previous: previous() });
    const s = await opened(after.events, since);
    await settle();
    await s.close();
    return [s.resumed, s.got.filter((e) => e.event).map((e) => e.event)];
  };
  // Handed over: resumed, with nothing to tell.
  assert.deepEqual(await back(await stopped(true)), [true, []]);
  // A crash: nothing handed over.
  assert.deepEqual(await back(await stopped(false)), [false, ["missed"]]);
  // Handed over longer than KEPT_MS before the next process came: not taken up, and gone.
  const old = await stopped(true);
  await time.adjust(KEPT_MS + 1_000);
  assert.deepEqual(await back(old), [false, ["missed"]]);
  assert.equal(existsSync(file), false);
  // What does not read (cut short): not taken up, and gone.
  const cut = await stopped(true);
  writeFileSync(file, readFileSync(file, "utf8").slice(0, 100));
  assert.deepEqual(await back(cut), [false, ["missed"]]);
  assert.equal(existsSync(file), false);
  // Nobody followed for longer than KEPT_MS: nothing is handed over.
  const quiet = setup(time.clock, { file, previous: previous() });
  await (await opened(quiet.events)).close();
  await time.adjust(KEPT_MS + 1_000);
  await quiet.events.handOver();
  assert.equal(existsSync(file), false);
});

test("what the next process is to tell before it goes on from the one before is told after what that one told, numbered on", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  const before = setup(time.clock, { file, previous: previous() });
  const lost = await opened(before.events);
  before.change({ type: "session", key: "s1" });
  await settle();
  const heard = lost.got.findLast((e) => e.id)!.id!;
  await lost.close();
  // The next one is up while the one before stops (a device may reach it first): what it is to tell meanwhile waits.
  const gone = Promise.withResolvers<void>();
  const after = setup(time.clock, { file, previous: previous(gone.promise) }, before);
  after.change({ type: "read", viewer: "a@x", thread: 3, n: 9 });
  after.change({ type: "read", viewer: "b@x", thread: 3, n: 9 });
  after.events.tell("vault-plain", { id: "p1" }, "vault-plain\0p1", { workspace: "w", email: "a@x" });
  after.change({ type: "thread", id: 5, entries: [{ n: 1 } as any] });
  after.change({ type: "session", key: "s2" });
  await settle();
  before.change({ type: "session", key: "s3" });
  await settle();
  await before.events.handOver();
  gone.resolve();
  const back = await opened(after.events, heard);
  await settle();
  assert.equal(back.resumed, true);
  // All of it, the one before's first, and only what is a@x's (not b@x's read); a thread's entries read as a@x has them.
  const told = back.got.filter((e) => e.event && e.event !== "overview").map((e) => [e.event, e.event === "thread" ? e.data.id : e.event === "session" ? e.data.key : e.data]);
  assert.deepEqual(told, [
    ["session", "s3"],
    ["read", { viewer: "a@x", thread: 3, n: 9 }],
    ["vault-plain", { id: "p1" }],
    ["thread", 5],
    ["session", "s2"],
  ]);
  // The same run, numbered on from the last the one before told.
  const [run, n] = heard.split(".");
  const ids = back.got.filter((e) => e.id).map((e) => e.id!.split("."));
  assert.ok(ids.every(([r, m], i) => r === run && Number(m) > Number(n) && (i === 0 || Number(m) > Number(ids[i - 1]![1]))), JSON.stringify(ids));
  await back.close();
});

test("what is handed over is gone on from only by the process that waited for the one that handed it over", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  // Another process's pid (every one of a test is this process).
  const other = process.pid + 1;
  /// A process whose stream was cut, slow to stop: the last id its stream heard, and its handing over.
  const slow = async () => {
    const before = setup(time.clock, { file, previous: previous() });
    const lost = await opened(before.events);
    before.change({ type: "processes" } as StoreChange);
    before.change({ type: "session", key: "s1" });
    await settle();
    await lost.close();
    return { heard: lost.got.findLast((e) => e.id)!.id!, before };
  };
  /// The next process, waiting for `pid`: whether a@x's stream from `since` is resumed there, and the events it is told.
  const back = async (since: string, pid: number | null) => {
    const after = setup(time.clock, { file, previous: { pid, gone: Promise.resolve() } });
    const s = await opened(after.events, since);
    await settle();
    await s.close();
    return [s.resumed, s.got.filter((e) => e.event).map((e) => e.event)];
  };
  // The next one waited for it in vain (40 s), found nothing, and went on with a run of its own; then it hands over.
  let a = await slow();
  let b = setup(time.clock, { file, previous: previous() });
  await settle();
  await a.before.events.handOver();
  assert.ok(existsSync(file));
  // That one stops with nothing to hand over (nobody followed it): what is there goes with it.
  await b.events.handOver();
  assert.equal(existsSync(file), false);
  // Or it crashes: the one after it waits for it (run/hub.json names it), and does not go on from what is there.
  a = await slow();
  b = setup(time.clock, { file, previous: previous() });
  await settle();
  await a.before.events.handOver();
  assert.deepEqual(await back(a.heard, other), [false, ["missed"]]);
  assert.equal(existsSync(file), false);
  // Stopped before the next one started (none holds the station then): gone on from.
  a = await slow();
  await a.before.events.handOver();
  assert.deepEqual(await back(a.heard, null), [true, []]);
});

test("what is handed over that can be neither read nor removed fails no stream, waited on or not", async () => {
  const time = testClock();
  const file = join(mkdtempSync(join(tmpdir(), "events-")), "run", "events.json");
  mkdirSync(file, { recursive: true });
  const unhandled: unknown[] = [];
  const heard = (reason: unknown) => void unhandled.push(reason);
  process.on("unhandledRejection", heard);
  try {
    // Nobody waits on its taking up.
    setup(time.clock, { file, previous: previous() });
    await settle();
    // A stream does: answered, told it missed what was before.
    const after = setup(time.clock, { file, previous: previous() });
    const s = await opened(after.events, "1f2e3d4c.3");
    await settle();
    assert.equal(s.resumed, false);
    assert.deepEqual(s.got.filter((e) => e.event).map((e) => e.event), ["missed"]);
    await s.close();
  } finally {
    process.off("unhandledRejection", heard);
  }
  assert.deepEqual(unhandled, []);
});

test("a vault's records are told to its members as they are as each is told, again too", async () => {
  const time = testClock();
  const members = new Set(["a@x"]);
  const { events } = setup(time.clock);
  events.follow({ inVault: (viewer, vault) => vault === "v1" && members.has(viewer.sub) });
  /// a@x's and b@x's streams, each from its `since`.
  const streams = async (since: string[]) => {
    const both = await Promise.all(["a@x", "b@x"].map(async (who, i) => reader((await events.open(viewer(who), "zh", false, [], [], since[i] ?? null)).body as AsyncIterable<Buffer>)));
    await settle();
    return both;
  };
  const first = await streams([]);
  const at = first.map((s) => s.got.map((e) => /^id: ([0-9a-f]+\.\d+)\n\n$/.exec(e.raw)?.[1]).find((id) => id !== undefined)!);
  events.tell("vault-request", { id: "r1" }, "vault-request\0r1", { workspace: "w", vault: "v1" });
  await settle();
  const told = (s: (typeof first)[number]) => s.got.filter((e) => e.event === "vault-request").map((e) => e.data.id);
  assert.deepEqual(first.map(told), [["r1"], []]);
  for (const s of first) await s.close();
  // a@x left the vault and b@x came in: what their streams are told again is as the vault's members are now.
  members.delete("a@x");
  members.add("b@x");
  const again = await streams(at);
  assert.deepEqual(again.map(told), [[], ["r1"]]);
  for (const s of again) await s.close();
});

test("a session's summary read before its messages were taken is not told after the station told they were", async () => {
  // Its agent took a message (`session-pending`, told at once) while the summary a change before asked for was still
  // being read: told after it, that summary had the message waiting again and the turn before, and a device stood the
  // agent back in the queue, its activity in the chat gone until the next summary came (2026-11-09).
  const { events, readers, change } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  await settle();
  const read = readers.read;
  let pending = 1;
  let release: () => void = () => {};
  const held = new Promise<void>((r) => (release = r));
  let first = true;
  readers.read = async (op: string, args: any) => {
    if (op !== "summary") return read(op, args);
    const snapshot = pending;
    if (first) {
      first = false;
      await held;
    }
    return JSON.stringify({ key: args.key, pending: snapshot });
  };
  change({ type: "session", key: "s" });
  await settle();
  pending = 0;
  change({ type: "session", key: "s", pending: 0 });
  release();
  await settle();
  const told = a.got.filter((e) => e.event === "session" || e.event === "session-pending").map((e) => [e.event, e.data.pending]);
  assert.deepEqual(told, [["session-pending", 0], ["session", 0]]);
  await a.close();
});
