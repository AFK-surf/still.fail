// The media app end to end, but for its UI: a real station's module layer (station/src/modules) starts the real media
// service (media/service) beside a drive with a book in it, and cores with the media module (media/core) on two devices
// of one account, and a read-only member's, ask it as the app would. A book put on the shelf on one device is read on
// the other where the first left it; a read-only member keeps their own place but puts nothing on the shelf.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
// The station's side.
import { Admin } from "../../station/src/api/admin.ts";
import type { Answer } from "../../station/src/api/request.ts";
import { stationDrive } from "../../station/src/drive/drive.ts";
import type { Viewer } from "../../station/src/mesh/credential.ts";
import { follow } from "../../station/src/modules/live.ts";
import { ModuleSet } from "../../station/src/modules/modules.ts";
import { ConfigFile } from "../../station/src/ops/config.ts";
// The devices' side.
import type { Core } from "../../client/core-ts/src/core.ts";
import type { HttpRequest, HttpResponse } from "../../client/core-ts/src/host.ts";
import type { FakeHost } from "../../client/core-ts/src/testing.ts";
import { apply, call, subscribe } from "../../client/core-ts/test/helpers.ts";
import { started, stationLater } from "../../client/core-ts/test/station-fixture.ts";
import { media } from "../core/media.ts";
import { epub3 } from "../service/test/helpers.ts";

const SERVICE = fileURLToPath(new URL("../service/src/main.ts", import.meta.url));
const ST = "ws/st";
const owner: Viewer = { sub: "usr_o", email: "o@x", name: "主人", role: "owner", workspace: "ws", device: "d", home: true };
const reader: Viewer = { sub: "usr_v", email: "v@x", name: "只读", role: "viewer", workspace: "ws", device: "d", home: true };

const real = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// A station whose config names the media service, its drive pinning a folder with a book in it.
async function station(t: { after: (f: () => unknown) => void }) {
  // Short: a unix socket's path is at most 104 bytes on macOS (the module's are under the data folder).
  const base = realpathSync(mkdtempSync(join(process.platform === "darwin" ? "/tmp" : tmpdir(), "me-")));
  const data = join(base, "data");
  const books = join(base, "books");
  mkdirSync(data, { recursive: true });
  mkdirSync(books, { recursive: true });
  writeFileSync(join(books, "三体.epub"), epub3());
  writeFileSync(join(data, "config.json"), JSON.stringify({ drive: { roots: [books] }, modules: [{ id: "media", command: process.execPath, args: [SERVICE] }] }));
  const config = new ConfigFile(data);
  const modules = new ModuleSet(data);
  const fiber = Effect.runFork(
    Effect.scoped(Effect.gen(function* () {
      yield* yield* follow({ data, modules, drive: stationDrive(config, () => [], null), config, previousGone: Promise.resolve() });
      yield* Effect.never;
    })),
  );
  t.after(async () => {
    await Effect.runPromise(Fiber.interrupt(fiber));
    rmSync(base, { recursive: true, force: true });
  });
  for (let i = 0; modules.get("media")?.running !== true; i++) {
    if (i > 500) throw new Error("the media service did not start");
    await real(20);
  }
  return { admin: new Admin({ names: new Map() } as any, { modules }), books };
}

async function whole(answer: Answer): Promise<Uint8Array> {
  if (Buffer.isBuffer(answer.body)) return new Uint8Array(answer.body);
  const parts: Buffer[] = [];
  for await (const chunk of answer.body) parts.push(chunk);
  return new Uint8Array(Buffer.concat(parts));
}

/// A device: a core with the media module whose `/admin/api/m/…` requests reach the station as `who`.
async function device(admin: Admin, who: Viewer): Promise<{ host: FakeHost; core: Core; ui: number }> {
  const { host, core } = await started(undefined, 0, undefined, undefined, [media]);
  stationLater(host, (req: HttpRequest) => {
    const url = new URL(req.url);
    if (!url.pathname.startsWith("/admin/api/m/")) return undefined;
    const headers: Record<string, string> = {};
    for (const [k, v] of req.headers) headers[k.toLowerCase()] = v;
    return admin
      .handle({ method: req.method, path: url.pathname.slice("/admin/api".length), query: [...url.searchParams], search: url.search, headers, body: Buffer.from(req.body ?? new Uint8Array()), viewer: who, lang: "zh" } as any)
      .then(async (answer): Promise<HttpResponse> => ({ status: answer.status, headers: Object.entries(answer.headers ?? {}), body: await whole(answer) }));
  });
  return { host, core, ui: core.connect() };
}

/// Lets the core and the station (a real process: real time) go on until `done` says the values are there.
async function until<T>(d: { host: FakeHost }, values: Map<number, unknown>, done: () => T | undefined): Promise<T> {
  for (let i = 0; i < 300; i++) {
    await d.host.settle();
    apply(d.host, values);
    const got = done();
    if (got !== undefined) return got;
    await real(20);
  }
  throw new Error("nothing came");
}

/// A call's answer, waited for as `until` does.
async function answered(d: { host: FakeHost; core: Core; ui: number }, id: number, name: string, params: unknown): Promise<any> {
  call(d.core, d.ui, id, name, params);
  const seen: unknown[] = [];
  for (let i = 0; i < 300; i++) {
    await d.host.settle();
    for (const [, m] of d.host.takeEmitted()) {
      const msg = m as any;
      if (msg.id === id && ("ok" in msg || "error" in msg)) return msg;
      seen.push(msg);
    }
    await real(20);
  }
  throw new Error(`no answer to ${name}`);
}

test("a book put on the shelf on one device is read on another where the first left it", async (t) => {
  const { admin, books } = await station(t);
  const a = await device(admin, owner);
  const b = await device(admin, owner);

  // Device A: the book file put on the shelf, opened, read to a place.
  const imported = await answered(a, 1, "media.import", { station: ST, root: books, path: "三体.epub" });
  assert.ok(imported.ok, JSON.stringify(imported.error));
  const [book] = imported.ok.ids as string[];
  const aValues = new Map<number, unknown>();
  subscribe(a.core, a.ui, 2, { topic: "media.book", station: ST, book });
  const toc = await until(a, aValues, () => (aValues.get(2) as any)?.toc);
  assert.ok(toc.length >= 2, "its chapters");
  const chapter = await answered(a, 3, "media.chapter", { station: ST, book, index: 1 });
  assert.ok(chapter.ok.chars > 0 && chapter.ok.blocks.length > 0, "a chapter's text");
  const place = { chapter: 1, offset: Math.min(10, chapter.ok.chars - 1), at: Date.now() };
  assert.ok((await answered(a, 4, "media.place.set", { station: ST, book, place })).ok !== undefined);

  // Device B: the same book on its shelf, how far it was read, and where.
  const bValues = new Map<number, unknown>();
  subscribe(b.core, b.ui, 1, { topic: "media.shelf", station: ST });
  const shelf = await until(b, bValues, () => (bValues.get(1) as any)?.books);
  assert.deepEqual(shelf.map((x: any) => x.id), [book]);
  assert.ok(shelf[0].title, "its title");
  assert.deepEqual(shelf[0].place, place);
  subscribe(b.core, b.ui, 2, { topic: "media.place", station: ST, book });
  assert.deepEqual(await until(b, bValues, () => (bValues.get(2) as any)?.place ?? undefined), place);
  const same = await answered(b, 3, "media.chapter", { station: ST, book, index: 1 });
  assert.deepEqual(same.ok, chapter.ok, "the same text where it left off");

  // A read-only member: reads the shelf and keeps their own place; puts nothing on it.
  const v = await device(admin, reader);
  const refused = await answered(v, 1, "media.import", { station: ST, root: books, path: "三体.epub" });
  assert.equal(refused.error?.code !== undefined, true, "a read-only member cannot import");
  const theirs = { chapter: 0, offset: 0, at: Date.now() };
  assert.ok((await answered(v, 2, "media.place.set", { station: ST, book, place: theirs })).ok !== undefined);
  const vValues = new Map<number, unknown>();
  subscribe(v.core, v.ui, 3, { topic: "media.place", station: ST, book });
  assert.deepEqual(await until(v, vValues, () => (vValues.get(3) as any)?.place ?? undefined), theirs);
  // The owner's place is still theirs.
  const again = await answered(b, 4, "media.import", { station: ST, root: books, path: "三体.epub" });
  assert.deepEqual(again.ok.ids, [book], "the same file is the same book");
  for (const d of [a, b, v]) d.core.close();
});
