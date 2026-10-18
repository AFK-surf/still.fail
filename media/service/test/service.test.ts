// The media service over its socket (src/server.ts, importer.ts, store.ts), with a fake station local API: importing
// through the station, the shelf, chapters and images, who may write what, places and notes per account, events, and
// workspaces kept apart.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { VIEWER_WRITES, viewerOf } from "../src/server.ts";
import { MEMBER, OTHER, OWNER, VIEWER, ascii, call, epub2, epub3, fakeStation, gb18030, header, listen, started, wait } from "./helpers.ts";

const NOVEL = "作者：王五\n第一章 风起\n　　第一段。\n第二章 云涌\n内容。\n";

test("import an EPUB through the station in parts; the shelf, the book's toc, a chapter, an image", async (t) => {
  const s = await started(4096);
  t.after(s.stop);
  const book = epub3();
  s.station.files.set("lib/test.epub", { bytes: book, mtime: 1000 });
  const imported = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "lib/test.epub" });
  assert.equal(imported.status, 200, JSON.stringify(imported.json));
  assert.equal(imported.json.ids.length, 1);
  const id = imported.json.ids[0];
  assert.equal(s.station.seen.reads, Math.ceil(book.length / 4096), "read in parts of what the station answers");
  assert.ok(s.station.seen.viewers.every((v) => v === header(OWNER)), "asked the station as the member, header as given");

  const shelf = await s.call("GET", "/books", VIEWER);
  assert.equal(shelf.status, 200);
  assert.equal(shelf.json.books.length, 1);
  const b = shelf.json.books[0];
  assert.deepEqual([b.id, b.title, b.author, b.format, b.cover, b.chapters], [id, "测试之书", "张三、李四", "epub", null, 3]);
  assert.equal(typeof b.added, "number");
  assert.equal(b.place, undefined);

  const toc = await s.call("GET", `/books/${id}`, VIEWER);
  assert.deepEqual(toc.json, {
    id,
    title: "测试之书",
    author: "张三、李四",
    toc: [
      { index: 0, title: "封面", level: 1, chars: 1 },
      { index: 1, title: "第一章 开始", level: 1, chars: 54 },
      { index: 2, title: "第二部", level: 1, chars: 8 },
    ],
  });

  const ch = await s.call("GET", `/books/${id}/chapters/1`, VIEWER);
  assert.equal(ch.status, 200);
  assert.equal(ch.json.chars, 54);
  assert.equal(ch.json.blocks.length, 9);
  assert.deepEqual(ch.json.blocks[3], { t: "p", runs: [{ text: "漢", ruby: "かん" }, { text: "字", ruby: "じ" }, { text: "を読む" }] });
  const img = ch.json.blocks[7];
  assert.deepEqual([img.t, img.w, img.h], ["img", 320, 240]);

  const bytes = await s.call("GET", `/books/${id}/images/${img.ref}`, VIEWER);
  assert.equal(bytes.status, 200);
  assert.equal(bytes.headers["content-type"], "image/png");
  assert.equal(bytes.bytes.readUInt32BE(16), 320);
  assert.equal(b.coverRef, (await s.call("GET", `/books/${id}/chapters/0`, VIEWER)).json.blocks[0].ref);

  assert.equal((await s.call("GET", `/books/${id}/chapters/3`, VIEWER)).status, 404);
  assert.equal((await s.call("GET", `/books/${id}/images/nope`, VIEWER)).status, 404);
  const missing = await s.call("GET", "/books/nope", VIEWER);
  assert.equal(missing.status, 404);
  assert.equal(missing.json.code, "not_found");
  assert.match(missing.json.error, /找不到/);
});

test("import a GB18030 TXT and an EPUB 2; re-importing keeps the id and reads again only when the file changed", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("novel.txt", { bytes: gb18030(NOVEL), mtime: 5 });
  const first = await s.call("POST", "/books/import", MEMBER, { root: "/books", path: "novel.txt" });
  assert.equal(first.status, 200, JSON.stringify(first.json));
  const id = first.json.ids[0];
  const toc = (await s.call("GET", `/books/${id}`, MEMBER)).json;
  assert.deepEqual(toc.toc.map((c: any) => [c.title, c.chars]), [["前言", 5], ["第一章 风起", 6 + 4], ["第二章 云涌", 6 + 3]]);
  assert.equal(toc.author, "王五");

  const reads = s.station.seen.reads;
  const again = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "novel.txt" });
  assert.deepEqual(again.json, { ids: [id] });
  assert.equal(s.station.seen.reads, reads, "unchanged: not read again");

  s.station.files.set("novel.txt", { bytes: Buffer.from(`﻿${NOVEL}第三章 新\n更多。\n`, "utf8"), mtime: 6 });
  const changed = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "novel.txt" });
  assert.deepEqual(changed.json, { ids: [id] });
  assert.equal((await s.call("GET", `/books/${id}`, MEMBER)).json.toc.length, 4);
  assert.equal((await s.call("GET", "/books", MEMBER)).json.books.length, 1);

  s.station.files.set("old.epub", { bytes: epub2(), mtime: 1 });
  const old = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "old.epub" });
  const oldToc = (await s.call("GET", `/books/${old.json.ids[0]}`, OWNER)).json.toc;
  assert.deepEqual(oldToc.map((c: any) => [c.title, c.level]), [["Part One", 1], ["Chapter 1", 2], ["Unnamed & found", 1]]);
});

test("import a folder: each EPUB and TXT in it, not its subfolders; MOBI refused with 415; drive errors", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("shelf/a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  s.station.files.set("shelf/b.epub", { bytes: epub3(), mtime: 1 });
  s.station.files.set("shelf/c.mobi", { bytes: Buffer.alloc(100), mtime: 1 });
  s.station.files.set("shelf/notes.md", { bytes: Buffer.from("# no"), mtime: 1 });
  s.station.files.set("shelf/deeper/d.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const folder = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "shelf" });
  assert.equal(folder.status, 200, JSON.stringify(folder.json));
  assert.equal(folder.json.ids.length, 2);
  assert.equal(folder.json.failed, undefined);
  assert.deepEqual((await s.call("GET", "/books", OWNER)).json.books.map((b: any) => b.format).sort(), ["epub", "txt"]);

  const mobi = Buffer.alloc(100);
  mobi.write("BOOKMOBI", 60, "latin1");
  s.station.files.set("k.azw3", { bytes: mobi, mtime: 1 });
  const refused = await s.call("POST", "/books/import", OWNER, { root: "/books", path: "k.azw3" });
  assert.equal(refused.status, 415);
  assert.equal(refused.json.code, "unsupported");
  assert.match(refused.json.error, /MOBI/);

  assert.equal((await s.call("POST", "/books/import", OWNER, { root: "/books", path: "none.epub" })).status, 404);
  assert.equal((await s.call("POST", "/books/import", OWNER, { root: "/elsewhere", path: "a.txt" })).status, 403);
  const bad = await s.call("POST", "/books/import", OWNER, { path: "a.txt" });
  assert.equal(bad.status, 400);
  assert.equal(bad.json.code, "bad_request");
});

test("a wrong station token: the import fails as the station's refusal, not a crash", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const { startService } = await import("../src/server.ts");
  const other = await startService({ dir: `${s.dir}/other`, socket: `${s.dir}/o.sock`, station: { socket: s.station.socket, token: "wrong" } });
  t.after(other.close);
  const { call } = await import("./helpers.ts");
  const r = await call(`${s.dir}/o.sock`, "POST", "/books/import", OWNER, { root: "/books", path: "a.txt" });
  assert.equal(r.status, 502);
  assert.equal(r.json.code, "station");
});

test("viewers read and keep their own place and notes; only writers import and remove; the manifest says so", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const ro = await s.call("POST", "/books/import", VIEWER, { root: "/books", path: "a.txt" });
  assert.equal(ro.status, 403);
  assert.equal(ro.json.code, "forbidden");
  const id = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  assert.equal((await s.call("DELETE", `/books/${id}`, VIEWER)).status, 403);
  assert.equal((await s.call("PUT", `/books/${id}/place`, VIEWER, { chapter: 1, offset: 3, at: 10 })).status, 200);
  assert.equal((await s.call("PUT", `/books/${id}/notes/n1`, VIEWER, { chapter: 1, start: 0, end: 2, text: "第一", color: "yellow", at: 10 })).status, 200);
  assert.equal((await s.call("DELETE", `/books/${id}/notes/n1`, VIEWER)).status, 200);

  const manifest = await s.call("GET", "/manifest", null);
  assert.deepEqual(manifest.json, { viewerWrites: VIEWER_WRITES });
  const allowed = (path: string) => manifest.json.viewerWrites.some((r: string) => new RegExp(r).test(path));
  assert.ok(allowed(`/books/${id}/place`));
  assert.ok(allowed(`/books/${id}/notes/n1`));
  assert.ok(!allowed("/books/import"));
  assert.ok(!allowed(`/books/${id}`));

  assert.equal((await s.call("GET", "/books", null)).status, 403, "no member, no answer");
  assert.equal((await s.call("GET", "/nothing", OWNER)).status, 404);
  assert.equal((await s.call("PATCH", "/books", OWNER)).status, 405);

  assert.equal((await s.call("DELETE", `/books/${id}`, MEMBER)).status, 200);
  assert.equal((await s.call("GET", "/books", OWNER)).json.books.length, 0);
  assert.equal((await s.call("GET", `/books/${id}/place`, VIEWER)).status, 404);
});

test("places: each account's own; the latest `at` wins; the shelf shows how far", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const id = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  // Chapters: 前言 5, 第一章 10, 第二章 9 (24 in all).
  assert.deepEqual((await s.call("GET", `/books/${id}/place`, OWNER)).json, { place: null });
  const put = await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 1, offset: 7, at: 2000 });
  assert.deepEqual(put.json, { place: { chapter: 1, offset: 7, at: 2000 } });
  const older = await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 0, offset: 0, at: 1000 });
  assert.deepEqual(older.json, { place: { chapter: 1, offset: 7, at: 2000 } }, "an older place is ignored");
  await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 2, offset: 3, at: 3000 });
  assert.deepEqual((await s.call("GET", `/books/${id}/place`, OWNER)).json, { place: { chapter: 2, offset: 3, at: 3000 } });
  assert.deepEqual((await s.call("GET", `/books/${id}/place`, VIEWER)).json, { place: null }, "another account's place is its own");

  const shelf = (await s.call("GET", "/books", OWNER)).json.books[0];
  assert.deepEqual(shelf.place, { chapter: 2, offset: 3, at: 3000 });
  assert.equal(shelf.read, (5 + 10 + 3) / 24);
  assert.equal((await s.call("GET", "/books", VIEWER)).json.books[0].place, undefined);

  assert.equal((await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 9, offset: 0, at: 4000 })).status, 400);
  assert.equal((await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 0, offset: -1, at: 4000 })).status, 400);
  assert.equal((await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 0, offset: 0 })).status, 400);
});

test("notes: each account sees and changes only its own; latest `at` wins", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const id = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  const note = { chapter: 1, start: 6, end: 10, text: "第一段。", note: "好", color: "yellow", at: 100 };
  const put = await s.call("PUT", `/books/${id}/notes/n-1`, OWNER, note);
  assert.equal(put.status, 200);
  assert.deepEqual(put.json, { note: { id: "n-1", ...note } });
  await s.call("PUT", `/books/${id}/notes/n-2`, OWNER, { chapter: 0, start: 0, end: 2, text: "作者", color: "blue", at: 100 });
  const listed = (await s.call("GET", `/books/${id}/notes`, OWNER)).json.notes;
  assert.deepEqual(listed.map((n: any) => n.id), ["n-2", "n-1"], "in reading order");
  assert.equal(listed[0].note, undefined);

  const stale = await s.call("PUT", `/books/${id}/notes/n-1`, OWNER, { ...note, note: "旧的", at: 50 });
  assert.equal(stale.json.note.note, "好", "an older edit is ignored");
  await s.call("PUT", `/books/${id}/notes/n-1`, OWNER, { ...note, note: "改了", at: 150 });
  assert.equal((await s.call("GET", `/books/${id}/notes`, OWNER)).json.notes[1].note, "改了");

  assert.deepEqual((await s.call("GET", `/books/${id}/notes`, VIEWER)).json, { notes: [] });
  const theirs = await s.call("PUT", `/books/${id}/notes/n-1`, VIEWER, { ...note, at: 999 });
  assert.equal(theirs.status, 403);
  assert.equal((await s.call("DELETE", `/books/${id}/notes/n-1`, VIEWER)).status, 403);
  assert.equal((await s.call("DELETE", `/books/${id}/notes/n-9`, OWNER)).status, 404);
  assert.equal((await s.call("PUT", `/books/${id}/notes/bad%20id`, OWNER, note)).status, 400);
  assert.equal((await s.call("PUT", `/books/${id}/notes/n-3`, OWNER, { ...note, start: 5, end: 2 })).status, 400);
  assert.equal((await s.call("PUT", `/books/${id}/notes/n-3`, OWNER, { ...note, color: undefined })).status, 400);

  assert.equal((await s.call("DELETE", `/books/${id}/notes/n-1`, OWNER)).status, 200);
  assert.deepEqual((await s.call("GET", `/books/${id}/notes`, OWNER)).json.notes.map((n: any) => n.id), ["n-2"]);
});

test("events: the shelf to the workspace, places and notes to the account only", async (t) => {
  const s = await started();
  t.after(s.stop);
  const owner = listen(s.socket, OWNER);
  const viewer = listen(s.socket, VIEWER);
  const other = listen(s.socket, OTHER);
  t.after(() => {
    owner.close();
    viewer.close();
    other.close();
  });
  await Promise.all([owner.ready, viewer.ready, other.ready]);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const id = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  await s.call("PUT", `/books/${id}/place`, VIEWER, { chapter: 1, offset: 1, at: 1 });
  await s.call("PUT", `/books/${id}/place`, VIEWER, { chapter: 1, offset: 1, at: 0 });
  await s.call("PUT", `/books/${id}/notes/x`, OWNER, { chapter: 1, start: 0, end: 1, text: "第", color: "red", at: 1 });
  await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" });
  await wait(100);
  assert.deepEqual(owner.events, [
    { event: "shelf", data: {} },
    { event: "notes", data: { book: id } },
  ]);
  assert.deepEqual(viewer.events, [
    { event: "shelf", data: {} },
    { event: "place", data: { book: id } },
  ], "one place event: the older place changed nothing; an unchanged re-import is no shelf change");
  assert.deepEqual(other.events, [], "another workspace hears nothing");
});

test("workspaces: books are the workspace's; the same file is a book of each workspace", async (t) => {
  const s = await started();
  t.after(s.stop);
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const mine = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  assert.deepEqual((await s.call("GET", "/books", OTHER)).json, { books: [] });
  assert.equal((await s.call("GET", `/books/${mine}`, OTHER)).status, 404);
  assert.equal((await s.call("GET", `/books/${mine}/chapters/0`, OTHER)).status, 404);
  assert.equal((await s.call("PUT", `/books/${mine}/place`, OTHER, { chapter: 0, offset: 0, at: 1 })).status, 404);
  assert.equal((await s.call("DELETE", `/books/${mine}`, OTHER)).status, 404);
  const theirs = (await s.call("POST", "/books/import", OTHER, { root: "/books", path: "a.txt" })).json.ids[0];
  assert.notEqual(theirs, mine);
  assert.equal((await s.call("GET", "/books", OWNER)).json.books.length, 1);
  assert.equal((await s.call("GET", "/books", OTHER)).json.books.length, 1);
});

test("the viewer header: ASCII JSON as the station escapes it; refused without sub or workspace", () => {
  const raw = ascii({ sub: "s", email: "e", name: "名字", role: "viewer", workspace: "w", home: false });
  assert.match(raw, /^[\x20-\x7e]+$/);
  assert.deepEqual(viewerOf(raw), { sub: "s", email: "e", name: "名字", role: "viewer", workspace: "w", home: false, raw });
  assert.equal(viewerOf(header(OWNER)).name, "主人");
  assert.equal(viewerOf(header(OWNER)).home, true);
  assert.throws(() => viewerOf(undefined), (e: any) => e.status === 403);
  assert.throws(() => viewerOf(JSON.stringify({ sub: "s" })), (e: any) => e.status === 403);
  assert.throws(() => viewerOf("garbage"), (e: any) => e.status === 403);
  assert.throws(() => viewerOf("[1]"), (e: any) => e.status === 403);
});

test("media.db: reopened with its data; stopping ends event streams", async (t) => {
  const s = await started();
  s.station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const id = (await s.call("POST", "/books/import", OWNER, { root: "/books", path: "a.txt" })).json.ids[0];
  await s.call("PUT", `/books/${id}/place`, OWNER, { chapter: 2, offset: 1, at: 5 });
  const events = listen(s.socket, OWNER);
  await events.ready;
  await s.service.close();
  await events.ended;
  const { startService } = await import("../src/server.ts");
  const again = await startService({ dir: `${s.dir}/data`, socket: s.socket, station: { socket: s.station.socket, token: "secret-token" } });
  t.after(async () => {
    await again.close();
    await s.station.close();
  });
  const shelf = (await s.call("GET", "/books", OWNER)).json.books;
  assert.deepEqual(shelf.map((b: any) => [b.id, b.place.chapter]), [[id, 2]]);
});

test("main.ts: started as the station starts a module (its environment), answers, and stops on SIGTERM", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "media-main-"));
  const station = await fakeStation(dir, "tok");
  t.after(station.close);
  station.files.set("a.txt", { bytes: Buffer.from(NOVEL), mtime: 1 });
  const socket = join(dir, "module.sock");
  const env = { ...process.env, STILLFAIL_MODULE_ID: "media", STILLFAIL_MODULE_DIR: join(dir, "data"), STILLFAIL_MODULE_SOCKET: socket, STILLFAIL_STATION_SOCKET: station.socket, STILLFAIL_STATION_TOKEN: "tok" };
  const child = spawn(process.execPath, [join(import.meta.dirname, "../src/main.ts")], { env, stdio: ["ignore", "ignore", "pipe"] });
  const exited = new Promise<number | null>((done) => child.on("exit", (code) => done(code)));
  t.after(() => child.kill("SIGKILL"));
  for (let i = 0; i < 100 && !existsSync(socket); i++) await wait(50);
  assert.deepEqual((await call(socket, "GET", "/manifest", null)).json, { viewerWrites: VIEWER_WRITES });
  const imported = await call(socket, "POST", "/books/import", OWNER, { root: "/books", path: "a.txt" });
  assert.equal(imported.status, 200);
  assert.ok(existsSync(join(dir, "data", "media.db")));
  child.kill("SIGTERM");
  assert.equal(await exited, 0);
});
