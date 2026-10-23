// A station's drive's files kept on the device once read (drive-kept.ts, `drive.read`'s `keep`), as Android's
// DriveCache.kt keeps them: read again, answered from what is kept without asking the station; read anew once it
// changed there; the least lately read let go past their bound; counted with what else the device keeps, and let go.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { DriveKept, keptId } from "../src/drive-kept.ts";
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
  // what was not played: from the station
  await read(t, ui, 5, "film.mp4", 30, 12, said, "played");
  assert.equal(reads(t.host), 3);
  call(t.core, ui, 6, "cache.usage", {});
  await t.host.settle();
  assert.equal((answers(t.host.takeEmitted(), 6)?.ok as { drive: number }).drive, 16 + 8 + 12);
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

test("past their bound the least lately read go, never the one just read nor one being written", async () => {
  const host = new FakeHost();
  const kept = new DriveKept(host, { file: 10, played: 100, chat: Number.POSITIVE_INFINITY, sent: 100 });
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

test("a chat's file opened is kept with its chat: read again from the device, listed with it, let go one at a time or with it", async () => {
  const t = await started();
  const pdf = bytesOf(40, 7);
  const film = bytesOf(64, 30);
  stationReplies(t.host, (req) => {
    const u = new URL(req.url);
    const name = u.searchParams.get("name");
    if (u.pathname.endsWith("/sessions/k1/files") && name === "plan.pdf") return new Raw({ status: 200, headers: [["content-type", "application/pdf"]], body: pdf });
    if (u.pathname.endsWith("/sessions/k1/parts") && name === "film.mp4") {
      const offset = Number(u.searchParams.get("offset"));
      const body = film.slice(offset, offset + Number(u.searchParams.get("length")));
      return new Raw({ status: 200, headers: [["content-type", "video/mp4"], ["stillfail-total", String(film.length)]], body });
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
