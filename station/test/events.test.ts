// GET /events as admin/events.rs has it: sidebar rows told by what changed, one `session` event per burst, `read`
// only to its viewer, job logs as they grow; and each event with its id (the station's run, its number), what was told
// told again to a stream that takes over from another or comes back after its link went (`since`).
import type { Clock } from "effect";
import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Events } from "../src/api/events.ts";
import type { StoreChange } from "../src/store/rows.ts";
import { settle, testClock } from "./hub-fakes.ts";

const viewer = (email: string) => ({ sub: email, email, name: email, role: "member", workspace: "w", device: "d" });

function setup(clock?: Clock.Clock) {
  let listener: (c: StoreChange) => void = () => {};
  const rows: Record<string, any[]> = { "a@x": [{ id: "1", title: "one" }], "b@x": [] };
  const overview = { running: 0 };
  const reads: string[] = [];
  const readers: any = {
    read: async (op: string, args: any) => {
      reads.push(op);
      if (op === "chats") return JSON.stringify(rows[args.viewer.email] ?? []);
      if (op === "summary") return JSON.stringify({ key: args.key });
      if (op === "entries") return JSON.stringify({ entries: [{ n: 1, text: "hi" }] });
      if (op === "thread") return JSON.stringify({ id: args.id, last: 1, unread: 1, for: args.viewer.email });
      throw new Error(op);
    },
  };
  const dir = mkdtempSync(join(tmpdir(), "events-"));
  const events = new Events({
    readers,
    subscribe: (l) => ((listener = l), () => {}),
    host: async () => ({ cpu: 1 }),
    jobLog: (id) => (id === "j" ? join(dir, "j.log") : null),
    tail: (path) => require("node:fs").readFileSync(path, "utf8"),
    outputAt: () => 7,
    sessionExists: (key) => key !== "gone",
    clock,
  });
  events.follow({ overview: async () => ({ ...overview }) });
  return { events, rows, reads, overview, change: (c: StoreChange) => listener(c), dir };
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
        got.push(m ? { id: m[1], event: m[2], data: JSON.parse(m[3]!), raw } : { raw });
      }
    })());
  more();
  return { got, close: () => it.return?.() };
}
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);

test("changes are told as events, rows by what changed, read only to its viewer", async () => {
  const { events, rows, change, reads } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const b = reader((await events.open(viewer("b@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  await settle();
  assert.equal(a.got[0]!.raw, "retry: 3000\n\n");
  rows["a@x"] = [{ id: "1", title: "one" }, { id: "2", title: "two" }];
  reads.length = 0;
  // A burst: one `session` event, one round of rows.
  change({ type: "session", key: "s" });
  change({ type: "session", key: "s" });
  change({ type: "session", key: "gone" });
  change({ type: "read", viewer: "b@x", thread: 3, n: 9 });
  await settle();
  const ofA = a.got.filter((e) => e.event).map((e) => [e.event, e.data]);
  assert.deepEqual(ofA, [["session", { key: "s" }], ["chat", { id: "2", title: "two" }]]);
  const ofB = b.got.filter((e) => e.event).map((e) => [e.event, e.data]);
  assert.deepEqual(ofB, [["read", { viewer: "b@x", thread: 3, n: 9 }], ["session", { key: "s" }]]);
  assert.equal(reads.filter((r) => r === "summary").length, 1);
  // Ids go up on each stream, of one run of the station; what is told to everyone has one id on all streams.
  const numbers = (got: { id?: string }[]) => got.filter((e) => e.id).map((e) => Number(e.id!.split(".")[1]));
  for (const got of [a.got, b.got]) assert.deepEqual(numbers(got), [...numbers(got)].sort((x, y) => x - y));
  assert.equal(new Set([...a.got, ...b.got].filter((e) => e.id).map((e) => e.id!.split(".")[0])).size, 1);
  const sessionIds = [a, b].map((s) => s.got.find((e) => e.event === "session")!.id);
  assert.equal(sessionIds[0], sessionIds[1]);
  rows["a@x"] = [{ id: "2", title: "two" }];
  change({ type: "threadRemoved", id: 1 });
  await settle();
  assert.deepEqual(a.got.slice(-2).map((e) => [e.event, e.data]), [["thread-removed", { id: 1 }], ["chat-removed", { id: "1" }]]);
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  await settle();
  assert.deepEqual(b.got.filter((e) => e.event === "thread").map((e) => e.data), [{ id: 4, entries: [{ n: 1, text: "hi" }] }]);
  await a.close();
  await b.close();
  assert.equal(events.inUse(), false);
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

test("a stream that comes back after its link went is told what was told meanwhile and how its sidebar stands", async () => {
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
    ["thread-view", { id: 4, last: 1, unread: 1, for: "a@x" }],
    ["session", "s2"],
    // Its sidebar and overview, as they changed while none of its viewer's streams was there to be told.
    ["overview", { running: 1 }],
    ["chat", { id: "1", title: "one, renamed" }],
    ["chat", { id: "2", title: "two" }],
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
  change({ type: "usage" });
  await settle();
  assert.equal(told(), 1);
  // A model call every 15 s: told again once, a minute after the first.
  for (let i = 0; i < 3; i++) {
    await time.adjust(15_000);
    change({ type: "usage" });
    await settle();
  }
  assert.equal(told(), 1);
  await time.adjust(15_000);
  await settle();
  assert.equal(told(), 2);
  // Quiet a while: the next change is told at once.
  await time.adjust(120_000);
  change({ type: "usage" });
  await settle();
  assert.equal(told(), 3);
  await s.close();
});

test("after something is said in a thread, each viewer is told it as GET /threads/:id has it for them", async () => {
  const { events, change } = setup(testClock().clock);
  const a = reader((await events.open(viewer("a@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  const b = reader((await events.open(viewer("b@x"), "zh", false, [], [])).body as AsyncIterable<Buffer>);
  change({ type: "thread", id: 4, entries: [{ n: 1 } as any] });
  await settle();
  const views = (s: typeof a) => s.got.filter((e) => e.event === "thread-view").map((e) => [e.data.id, e.data.for]);
  assert.deepEqual(views(a), [[4, "a@x"]]);
  assert.deepEqual(views(b), [[4, "b@x"]]);
  assert.ok(a.got.some((e) => e.event === "thread"));
  await a.close();
  await b.close();
});
