// A station's drive's files kept on the device once read (drive-kept.ts, `drive.read`'s `keep`), as Android's
// DriveCache.kt keeps them: read again, answered from what is kept without asking the station; read anew once it
// changed there; the least lately read let go past their bound; counted with what else the device keeps, and let go.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import type { Inner } from "../src/core.ts";
import { DriveKept, chatKeptId, keptId, outboxKeptId, sentKeptId } from "../src/drive-kept.ts";
import { keptFirst } from "../src/station/calls.ts";
import { FakeHost } from "../src/testing.ts";
import { answers, call } from "./helpers.ts";
import { Raw, started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";
const ROOT = "/Users/a/Books";

type File = { bytes: Uint8Array; mtime: number };

/// The station's drive as `files` (by path): `/drive/read` answers a part of one with its whole size and time.
function drive(host: FakeHost, files: Map<string, File>): void {
  stationReplies(host, (req) => {
    if (!req.url.includes("/drive/read?")) return undefined;
    const q = new URL(req.url).searchParams;
    const f = files.get(q.get("path") ?? "");
    if (f === undefined) return status(404, { error: "文件或文件夹不存在", code: "not_found" });
    const offset = Number(q.get("offset"));
    const body = f.bytes.slice(offset, offset + Number(q.get("length")));
    return new Raw({ status: 200, headers: [["content-type", "text/plain"], ["stillfail-total", String(f.bytes.length)], ["stillfail-mtime", String(f.mtime)]], body });
  });
}

const reads = (host: FakeHost) => host.requests.filter((r) => r.url.includes("/drive/read?")).length;
const bytesOf = (n: number, from = 0) => Uint8Array.from({ length: n }, (_, i) => (from + i) % 251);

/// `drive.read` of `path` from `offset`, kept as `keep` with the file as its folder says it is; its answer, bytes and all.
async function read(t: Awaited<ReturnType<typeof started>>, ui: number, id: number, path: string, offset: number, length: number, file: { mtime: number; size: number } | null, keep = "file") {
  call(t.core, ui, id, "drive.read", { station: ST, root: ROOT, path, offset, length, ...(file ? { keep, mtime: file.mtime, size: file.size } : {}) });
  await t.host.settle();
  const a = answers(t.host.takeEmitted(), id) as { ok: { type: string; total: number; mtime: number }; bytes: Uint8Array } | undefined;
  assert.ok(a?.ok, `drive.read ${id} answered`);
  return a;
}

test("a file read whole is kept: read again, it is answered from the device; changed on the station, read anew", async () => {
  const t = await started();
  const files = new Map<string, File>([["notes.txt", { bytes: bytesOf(10), mtime: 1000 }]]);
  drive(t.host, files);
  const ui = t.core.connect();
  const said = { mtime: 1000, size: 10 };
  const first = await read(t, ui, 1, "notes.txt", 0, 6, said);
  const second = await read(t, ui, 2, "notes.txt", 6, 6, said);
  assert.equal(reads(t.host), 2);
  assert.deepEqual([...first.bytes, ...second.bytes], [...bytesOf(10)]);
  // Read again, from its start and from inside it: the station not asked
  const again = await read(t, ui, 3, "notes.txt", 0, 6, said);
  const inside = await read(t, ui, 4, "notes.txt", 4, 4, said);
  assert.equal(reads(t.host), 2);
  assert.deepEqual([...again.bytes], [...bytesOf(6)]);
  assert.deepEqual([...inside.bytes], [...bytesOf(4, 4)]);
  assert.deepEqual(again.ok, { type: "text/plain", total: 10, mtime: 1000 });
  // Not asked to keep it: the station asked, as before
  await read(t, ui, 5, "notes.txt", 0, 6, null);
  assert.equal(reads(t.host), 3);
  // Changed on the station: its folder says so, and it is read anew, as it is now
  files.set("notes.txt", { bytes: bytesOf(8, 100), mtime: 2000 });
  const now = await read(t, ui, 6, "notes.txt", 0, 6, { mtime: 2000, size: 8 });
  assert.equal(reads(t.host), 4);
  assert.deepEqual([...now.bytes], [...bytesOf(6, 100)]);
  await read(t, ui, 7, "notes.txt", 0, 6, { mtime: 2000, size: 8 });
  assert.equal(reads(t.host), 4, "as it is now, kept");
  t.core.close();
});

test("a file changed since its folder was read: what was kept goes, what is read is not kept", async () => {
  const t = await started();
  const files = new Map<string, File>([["a.txt", { bytes: bytesOf(10), mtime: 1000 }]]);
  drive(t.host, files);
  const ui = t.core.connect();
  const was = { mtime: 1000, size: 10 };
  await read(t, ui, 1, "a.txt", 0, 6, was);
  // Changed on the station, its folder not read again: what is kept of it as it was is what it is here (as Android's)
  files.set("a.txt", { bytes: bytesOf(12, 50), mtime: 3000 });
  await read(t, ui, 2, "a.txt", 0, 6, was);
  assert.equal(reads(t.host), 1);
  // until a part not kept is read, and the station says it is another now
  const changed = await read(t, ui, 3, "a.txt", 6, 4, was);
  assert.equal(reads(t.host), 2);
  assert.deepEqual(changed.ok, { type: "text/plain", total: 12, mtime: 3000 });
  assert.deepEqual([...changed.bytes], [...bytesOf(4, 56)]);
  await read(t, ui, 4, "a.txt", 0, 6, was);
  assert.equal(reads(t.host), 3, "what was kept of it gone");
  t.core.close();
});

test("a video's parts are kept as played, a stream's too; the page of what the device keeps counts them and lets them go", async () => {
  const t = await started();
  const files = new Map<string, File>([["film.mp4", { bytes: bytesOf(64), mtime: 7 }]]);
  drive(t.host, files);
  const ui = t.core.connect();
  const said = { mtime: 7, size: 64 };
  await read(t, ui, 1, "film.mp4", 16, 16, said, "played");
  call(t.core, ui, 2, "drive.read", { station: ST, root: ROOT, path: "film.mp4", offset: 40, length: 8, stream: true, keep: "played", ...said });
  await t.host.settle();
  const streamed = t.host.takeEmitted().map(([, m]) => m as { id?: number; bytes?: Uint8Array }).filter((m) => m.id === 2 && m.bytes !== undefined);
  assert.deepEqual(streamed.flatMap((m) => [...m.bytes!]), [...bytesOf(8, 40)]);
  assert.equal(reads(t.host), 2);
  // what was played, again (a stream's in one piece): from the device
  await read(t, ui, 3, "film.mp4", 20, 8, said, "played");
  call(t.core, ui, 4, "drive.read", { station: ST, root: ROOT, path: "film.mp4", offset: 40, length: 8, stream: true, keep: "played", ...said });
  await t.host.settle();
  const again = t.host.takeEmitted().map(([, m]) => m as { id?: number; bytes?: Uint8Array }).filter((m) => m.id === 4 && m.bytes !== undefined);
  assert.deepEqual(again.flatMap((m) => [...m.bytes!]), [...bytesOf(8, 40)]);
  assert.equal(reads(t.host), 2);
  // what was not played: from the station, only the stretch between what was played (32 to 40: 30 and 31 kept
  // before it, 40 and 41 after)
  const got = await read(t, ui, 5, "film.mp4", 30, 12, said, "played");
  assert.deepEqual([...got.bytes], [...bytesOf(12, 30)]);
  assert.equal(reads(t.host), 3);
  const asked = new URL(t.host.requests.filter((r) => r.url.includes("/drive/read")).at(-1)!.url).searchParams;
  assert.deepEqual([asked.get("offset"), asked.get("length")], ["32", "8"]);
  call(t.core, ui, 6, "cache.usage", {});
  await t.host.settle();
  assert.equal((answers(t.host.takeEmitted(), 6)?.ok as { drive: number }).drive, 16 + 8 + 8);
  call(t.core, ui, 7, "drive.kept.clear", {});
  await t.host.settle();
  assert.ok(answers(t.host.takeEmitted(), 7)?.ok === null);
  call(t.core, ui, 8, "cache.usage", {});
  await t.host.settle();
  assert.equal((answers(t.host.takeEmitted(), 8)?.ok as { drive: number }).drive, 0);
  assert.equal([...t.host.storage.keys()].filter((k) => k.startsWith("drive-kept-")).length, 0, "their bytes let go");
  await read(t, ui, 9, "film.mp4", 16, 16, said, "played");
  assert.equal(reads(t.host), 4);
  t.core.close();
});

test("a part partly kept: what is kept goes first, only the rest of it is asked of the station", async () => {
  const t = await started();
  drive(t.host, new Map<string, File>([["film.mp4", { bytes: bytesOf(64), mtime: 7 }]]));
  const ui = t.core.connect();
  const said = { mtime: 7, size: 64 };
  const asked = () =>
    t.host.requests.filter((r) => r.url.includes("/drive/read?")).map((r) => {
      const q = new URL(r.url).searchParams;
      return [Number(q.get("offset")), Number(q.get("length"))];
    });
  await read(t, ui, 1, "film.mp4", 16, 16, said, "played");
  // on from what was played: the station asked from where what is kept stops
  const on = await read(t, ui, 2, "film.mp4", 16, 32, said, "played");
  assert.deepEqual(asked(), [[16, 16], [32, 16]]);
  assert.deepEqual([...on.bytes], [...bytesOf(32, 16)]);
  assert.deepEqual(on.ok, { type: "text/plain", total: 64, mtime: 7 });
  // as it streams: what is kept handed on first, then what the station brings
  call(t.core, ui, 3, "drive.read", { station: ST, root: ROOT, path: "film.mp4", offset: 40, length: 16, stream: true, keep: "played", ...said });
  await t.host.settle();
  const streamed = t.host.takeEmitted().map(([, m]) => m as { id?: number; bytes?: Uint8Array }).filter((m) => m.id === 3 && m.bytes !== undefined);
  assert.deepEqual(streamed.flatMap((m) => [...m.bytes!]), [...bytesOf(16, 40)]);
  assert.deepEqual(asked().at(-1), [48, 8]);
  // all of it kept now: the station not asked again
  await read(t, ui, 4, "film.mp4", 16, 40, said, "played");
  assert.equal(asked().length, 3);
  t.core.close();
});

test("a part partly kept of a file changed on the station: read whole again from it, not put after what was kept", async () => {
  const t = await started();
  const files = new Map<string, File>([["a.txt", { bytes: bytesOf(10), mtime: 1000 }]]);
  drive(t.host, files);
  const ui = t.core.connect();
  const was = { mtime: 1000, size: 10 };
  await read(t, ui, 1, "a.txt", 0, 6, was);
  files.set("a.txt", { bytes: bytesOf(12, 50), mtime: 3000 });
  const got = await read(t, ui, 2, "a.txt", 0, 10, was);
  assert.deepEqual([...got.bytes], [...bytesOf(10, 50)]);
  assert.deepEqual(got.ok, { type: "text/plain", total: 12, mtime: 3000 });
  assert.equal(reads(t.host), 3, "the rest, then the part whole again");
  await read(t, ui, 3, "a.txt", 0, 6, was);
  assert.equal(reads(t.host), 4, "what was kept of it gone");
  t.core.close();
});

test("a part read stopped short (let go of, or broken off) keeps what came of it", async () => {
  const kept: [number, number[]][] = [];
  const taken: number[][] = [];
  const inner = { runner: { fork: (e: Effect.Effect<void>) => Effect.runFork(e) } } as unknown as Inner;
  const reading = keptFirst<{ type: string; total: number }, { type: string; total: number; bytes: Uint8Array }>(
    inner,
    { offset: 10, length: 20 },
    100,
    (at) => Effect.succeed(at === 10 ? { type: "video/mp4", bytes: bytesOf(4, 10) } : null),
    (_at, end) => Effect.succeed(end),
    undefined,
    (piece) => taken.push([...piece]),
    (at, _length, _before, take, said) =>
      Effect.gen(function* () {
        said({ type: "video/mp4", total: 100 });
        take(bytesOf(5, at));
        return yield* Effect.never;
      }),
    (_head, at, bytes) => Effect.sync(() => void kept.push([at, [...bytes]])),
    (head) => head.total === 100,
  );
  await Effect.runPromise(
    Effect.gen(function* () {
      const fiber = yield* Effect.forkChild(reading);
      yield* Effect.yieldNow;
      yield* Fiber.interrupt(fiber);
    }),
  );
  // what was kept went first, then the station's first piece; that piece kept where it is in the file
  assert.deepEqual(taken, [[...bytesOf(4, 10)], [...bytesOf(5, 14)]]);
  assert.deepEqual(kept, [[14, [...bytesOf(5, 14)]]]);
});

test("a part streamed to a player stops as the player lets go of it, or its page goes: nothing more of it comes", async () => {
  const t = await started();
  drive(t.host, new Map<string, File>([["film.mp4", { bytes: bytesOf(64), mtime: 7 }]]));
  const said = { mtime: 7, size: 64 };
  const part = (ui: number, id: number) => call(t.core, ui, id, "drive.read", { station: ST, root: ROOT, path: "film.mp4", offset: 0, length: 64, stream: true, keep: "played", ...said });
  const of = (id: number) => t.host.takeEmitted().map(([, m]) => m as { id: number; error?: { code: string }; bytes?: Uint8Array }).filter((m) => m.id === id);
  // The station slow to answer it, the player gone elsewhere meanwhile: it says so, and nothing of it comes after.
  const ui = t.core.connect();
  const release = t.host.hold("&length=64");
  part(ui, 1);
  await t.host.settle();
  t.core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await t.host.settle();
  release();
  await t.host.settle();
  assert.deepEqual(of(1).map((m) => m.error?.code ?? (m.bytes ? "bytes" : "answer")), ["cancelled"]);
  assert.equal(t.core.inner.calls.size, 0);
  // Its page gone: the same.
  const other = t.core.connect();
  const again = t.host.hold("&length=64");
  part(other, 2);
  await t.host.settle();
  t.core.disconnect(other);
  await t.host.settle();
  again();
  await t.host.settle();
  assert.deepEqual(of(2).map((m) => m.error?.code ?? (m.bytes ? "bytes" : "answer")), ["cancelled"]);
  assert.equal(t.core.inner.calls.size, 0);
  // One not let go of brings all of it.
  part(ui, 3);
  await t.host.settle();
  assert.deepEqual(of(3).flatMap((m) => [...(m.bytes ?? [])]), [...bytesOf(64)]);
  t.core.close();
});

test("past their bound the least lately read go, never the one just read nor one being written", async () => {
  const host = new FakeHost();
  const kept = new DriveKept(host, { file: 10, played: 100, chat: Number.POSITIVE_INFINITY, sent: 100, outbox: Number.POSITIVE_INFINITY });
  const run = <A>(e: Effect.Effect<A>) => Effect.runPromise(e);
  const ids = ["one", "two", "three"].map((n) => keptId(ST, ROOT, n));
  for (const id of ids) {
    await run(kept.keep(id, "file", 1, 4, "application/pdf", 0, bytesOf(4)));
    host.advance(61_000);
  }
  // 12 bytes of files past 10: the least lately read, the first, gone
  assert.equal(await run(kept.read(ids[0], 1, 4, 0, 4)), null);
  assert.deepEqual([...(await run(kept.read(ids[1], 1, 4, 0, 4)))!.bytes], [...bytesOf(4)]);
  assert.equal(await run(kept.usage()), 8);
  // the second read just now: a fourth lets the third go
  host.advance(61_000);
  await run(kept.keep(keptId(ST, ROOT, "four"), "file", 1, 4, "application/pdf", 0, bytesOf(4)));
  assert.equal(await run(kept.read(ids[2], 1, 4, 0, 4)), null);
  assert.notEqual(await run(kept.read(ids[1], 1, 4, 0, 4)), null);
  // one read past the bound alone is kept (never the one just read); what was played is counted apart
  await run(kept.keep(keptId(ST, ROOT, "five"), "file", 1, 12, "application/pdf", 0, bytesOf(12)));
  assert.notEqual(await run(kept.read(keptId(ST, ROOT, "five"), 1, 12, 0, 12)), null);
  await run(kept.keep(keptId(ST, ROOT, "film"), "played", 1, 400, "video/mp4", 0, bytesOf(50)));
  assert.notEqual(await run(kept.read(keptId(ST, ROOT, "film"), 1, 400, 0, 50)), null);
  assert.equal([...host.storage.keys()].filter((k) => k.startsWith("drive-kept-")).length, 2, "the bytes of those let go, gone");
});

test("a file kept whole is kept on under another name, its bytes where they are; one kept in part is not", async () => {
  const host = new FakeHost();
  const kept = new DriveKept(host, { file: 10, played: 100, chat: Number.POSITIVE_INFINITY, sent: 100, outbox: Number.POSITIVE_INFINITY });
  const run = <A>(e: Effect.Effect<A>) => Effect.runPromise(e);
  const [going, sent] = [outboxKeptId("clip"), sentKeptId(ST, "clip.mp4")];
  await run(kept.keep(going, "outbox", 0, 8, "video/mp4", 0, bytesOf(4)));
  assert.equal(await run(kept.rename(going, sent, "sent", 8)), false, "half of it kept");
  await run(kept.keep(going, "outbox", 0, 8, "video/mp4", 4, bytesOf(4, 4)));
  const before = [...host.storage.keys()].filter((k) => k.startsWith("drive-kept-")).sort();
  assert.equal(await run(kept.rename(going, sent, "sent", 8)), true);
  assert.equal(await run(kept.has(going)), false);
  assert.deepEqual(await run(kept.held(sent)), { type: "video/mp4", size: 8, bytes: bytesOf(8) });
  assert.deepEqual([...host.storage.keys()].filter((k) => k.startsWith("drive-kept-")).sort(), before, "nothing written again");
});

test("what is left of those kept in part: the first of each not kept, the most lately read first, but one whose rest its kind has no room for", async () => {
  const host = new FakeHost();
  const kept = new DriveKept(host, { file: 10, played: 100, chat: Number.POSITIVE_INFINITY, sent: 100, outbox: Number.POSITIVE_INFINITY });
  const run = <A>(e: Effect.Effect<A>) => Effect.runPromise(e);
  const [film, song, big, whole] = ["film", "song", "big", "whole"].map((n) => keptId(ST, ROOT, n));
  // its start and a part further on: what is between first
  await run(kept.keep(film, "played", 1, 40, "video/mp4", 0, bytesOf(10)));
  await run(kept.keep(film, "played", 1, 40, "video/mp4", 20, bytesOf(5)));
  host.advance(61_000);
  await run(kept.keep(song, "played", 1, 30, "audio/mp4", 0, bytesOf(10)));
  // all of it kept: nothing left of it
  await run(kept.keep(whole, "played", 1, 5, "audio/mp4", 0, bytesOf(5)));
  host.advance(61_000);
  // its rest past what videos keep beside the others
  await run(kept.keep(big, "played", 1, 90, "video/mp4", 0, bytesOf(10)));
  const left = await run(kept.unfinished(["played"]));
  assert.deepEqual(left.map((f) => [f.id, f.at, f.length]), [[song, 10, 20], [film, 10, 10]]);
  // a chat's not asked for: none of it
  await run(kept.keep(chatKeptId(ST, "k1", "a.mp4"), "chat", 0, 50, "video/mp4", 0, bytesOf(10)));
  assert.equal((await run(kept.unfinished(["played"]))).length, 2);
  assert.deepEqual((await run(kept.unfinished(["chat"]))).map((f) => [f.at, f.length]), [[10, 40]]);
  // only those read since a time: the song and the big one read after the film was
  assert.deepEqual((await run(kept.unfinished(["played"], host.nowMs() - 61_000))).map((f) => f.id), [song]);
});

test("a chat's file opened is kept with its chat: read again from the device, listed with it, let go one at a time or with it", async () => {
  const t = await started();
  const pdf = bytesOf(40, 7);
  const film = bytesOf(64, 30);
  stationReplies(t.host, (req) => {
    const u = new URL(req.url);
    const name = u.searchParams.get("name");
    // (one read whole is read a part at a time as any other, kept as each comes)
    const f = name === "plan.pdf" ? { bytes: pdf, type: "application/pdf" } : name === "film.mp4" ? { bytes: film, type: "video/mp4" } : null;
    if (u.pathname.endsWith("/sessions/k1/parts") && f !== null) {
      const offset = Number(u.searchParams.get("offset"));
      const body = f.bytes.slice(offset, offset + Number(u.searchParams.get("length")));
      return new Raw({ status: 200, headers: [["content-type", f.type], ["stillfail-total", String(f.bytes.length)]], body });
    }
    return undefined;
  });
  const asked = () => t.host.requests.filter((r) => r.url.includes("/sessions/k1/")).length;
  // the chat its session is in, with what is kept of its messages
  t.core.inner.data.putThread(ST, { id: 7, title: "季度计划", sessions: [{ session: "k1" }] });
  t.core.inner.data.putItems("entry", ST, "7", [[1, { text: "看一下附件" }]]);
  const ui = t.core.connect();
  const whole = async (id: number) => {
    call(t.core, ui, id, "station.file", { station: ST, key: "k1", name: "plan.pdf", keep: true, size: 40 });
    await t.host.settle();
    return answers(t.host.takeEmitted(), id) as { ok: { type: string }; bytes: Uint8Array };
  };
  assert.deepEqual([...(await whole(1)).bytes], [...pdf]);
  const again = await whole(2);
  assert.equal(asked(), 1, "read again from the device");
  assert.deepEqual([again.ok, [...again.bytes]], [{ type: "application/pdf" }, [...pdf]]);
  // a video's parts, as played
  const part = async (id: number, offset: number, length: number) => {
    call(t.core, ui, id, "station.file.part", { station: ST, key: "k1", name: "film.mp4", offset, length, keep: true, size: 64 });
    await t.host.settle();
    return answers(t.host.takeEmitted(), id) as { ok: { type: string; total: number }; bytes: Uint8Array };
  };
  await part(3, 0, 32);
  const played = await part(4, 8, 16);
  assert.equal(asked(), 2);
  assert.deepEqual([played.ok, [...played.bytes]], [{ type: "video/mp4", total: 64 }, [...bytesOf(16, 38)]]);
  // listed with its chat (the film a part of it), not counted with the drives'
  call(t.core, ui, 5, "cache.usage", {});
  await t.host.settle();
  const usage = answers(t.host.takeEmitted(), 5)?.ok as { chats: { thread: number; files: { name: string; size: number; bytes: number }[] }[]; drive: number; loose: unknown[] };
  const chat = usage.chats.find((c) => c.thread === 7)!;
  assert.deepEqual(chat.files.map((f) => [f.name, f.size, f.bytes]).sort(), [["film.mp4", 64, 32], ["plan.pdf", 40, 40]]);
  assert.deepEqual([usage.drive, usage.loose], [0, []]);
  // one let go: read from the station again
  call(t.core, ui, 6, "cache.file.clear", { station: ST, key: "k1", name: "plan.pdf" });
  await t.host.settle();
  await whole(7);
  assert.equal(asked(), 3);
  // the chat's let go: its files with it
  call(t.core, ui, 8, "cache.clear", { station: ST, thread: 7 });
  await t.host.settle();
  await part(9, 0, 32);
  await whole(10);
  assert.equal(asked(), 5);
  t.core.close();
});

test("the page of what the device keeps calls each chat as the chats' list does, the one keeping most first", async () => {
  const t = await started();
  const data = t.core.inner.data;
  // named by its agent; of still.fail's own, never named; a Slack thread, by its first line
  data.putThread(ST, { id: 1, surface: "ember", title: null, autoTitle: "ccvm 扩容", sessions: [{ session: "k1" }] });
  data.putThread(ST, { id: 2, surface: "ember", title: null, sessions: [{ session: "k2" }] });
  data.putThread(ST, { id: 3, surface: "slack:T1", channel: "C1", title: null, firstText: "<@U1> 看下构建", sessions: [{ session: "k3" }] });
  data.putItems("entry", ST, "1", [[1, { text: "a" }]]);
  data.putItems("entry", ST, "2", [[1, { text: "b".repeat(500) }]]);
  data.putItems("entry", ST, "3", [[1, { text: "c".repeat(50) }]]);
  const ui = t.core.connect();
  call(t.core, ui, 1, "cache.usage", {});
  await t.host.settle();
  const usage = answers(t.host.takeEmitted(), 1)?.ok as { chats: { thread: number; title: string | null }[] };
  assert.deepEqual(usage.chats.filter((c) => c.thread <= 3).map((c) => [c.thread, c.title]), [[2, "新对话"], [3, "看下构建"], [1, "ccvm 扩容"]]);
  t.core.close();
});
