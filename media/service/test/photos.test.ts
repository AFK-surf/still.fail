// The photo library over the service's socket (src/photos.ts), with a fake station serving a folder of the disk:
// folders set by an owner and read as them, metadata, albums, the timeline's windows, items, thumbnails (one, the
// batch and its index, kept by time and size, HEIC and posters through a sips of the test's own), drive/watch's
// changes, phones' uploads (resumed, checked, put by account and month, a name taken given a number), who may.
process.env.TZ = "Asia/Shanghai";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import { photoId } from "../src/photos.ts";
import { MEMBER, OWNER, ascii, PHONE_EXIF, POSTER, VIEWER, bmp, callBytes, exifJpeg, gif, header, heic, jpeg, listen, mp4, png, started, tiff, wait } from "./helpers.ts";

const at = (y: number, m: number, d: number) => new Date(y, m - 1, d, 12, 0, 0).getTime();
const write = (file: string, bytes: Buffer, mtime?: number) => {
  mkdirSync(join(file, ".."), { recursive: true });
  writeFileSync(file, bytes);
  if (mtime !== undefined) utimesSync(file, mtime / 1000, mtime / 1000);
};
const sha = (b: Buffer) => createHash("sha256").update(b).digest("hex");

/// Waits until `f` holds (the disk's watch takes its time).
async function until(f: () => Promise<boolean> | boolean, what: string, ms = 15_000) {
  const end = Date.now() + ms;
  while (!(await f())) {
    if (Date.now() > end) throw new Error(`timed out waiting: ${what}`);
    await wait(100);
  }
}

/// A sips that makes FIX.jpg of anything asked as a JPEG and FIX.bmp as a BMP (as `-s format F -Z N IN --out OUT`).
function fakeSips(dir: string) {
  const jpg = jpeg(720, 540);
  writeFileSync(join(dir, "fix.jpg"), jpg);
  writeFileSync(join(dir, "fix.bmp"), bmp(10, 8, [200, 120, 40]));
  const script = join(dir, "sips.sh");
  writeFileSync(script, `#!/bin/sh\nif [ "$3" = bmp ]; then cp "${dir}/fix.bmp" "$8"; else cp "${dir}/fix.jpg" "$8"; fi\n`);
  chmodSync(script, 0o755);
  return { script, jpg };
}

/// A library at `<dir>/lib`: a phone's JPEG, a HEIC, a video, a PNG and a GIF (by their times), and what is not kept.
function library(dir: string) {
  const lib = join(dir, "lib");
  write(join(lib, "2024", "a.jpg"), exifJpeg(4032, 3024, PHONE_EXIF()), at(2025, 1, 1));
  // Taken at 8 in the morning, the station's time (no offset given).
  write(join(lib, "2024", "b.HEIC"), heic(4032, 3024, tiff([[0x0112, 3, [6]]], [[0x9003, 2, "2024:01:01 08:00:00"]])), at(2025, 1, 1));
  write(join(lib, "clips", "c.mp4"), mp4(Date.UTC(2022, 5, 15, 8), 12.5, 1920, 1080), at(2025, 1, 1));
  write(join(lib, "p.png"), png(10, 20), at(2021, 3, 4));
  write(join(lib, "g.gif"), gif(3, 5), at(2021, 3, 4));
  write(join(lib, ".hidden.jpg"), jpeg(1, 1));
  write(join(lib, "@eaDir", "x.jpg"), jpeg(1, 1));
  write(join(lib, "Old.photoslibrary", "y.jpg"), jpeg(1, 1));
  write(join(lib, "notes.txt"), Buffer.from("no"));
  return lib;
}

test("folders: set by an owner or admin, read as them; metadata, albums, items, the timeline's windows", async (t) => {
  const s = await started(1 << 20);
  t.after(s.stop);
  library(s.dir);

  const none = await s.call("GET", "/photos/folders", MEMBER);
  assert.equal(none.status, 200);
  assert.deepEqual(none.json, { folders: [], backup: { root: s.backup, path: "" } });
  await s.service.photos.settled();
  assert.ok(existsSync(s.backup), "the backup folder made");

  for (const [who, method, path] of [[VIEWER, "GET", "/photos/timeline"], [VIEWER, "GET", "/photos/albums"], [VIEWER, "GET", "/photos/folders"], [VIEWER, "PUT", "/photos/folders"], [MEMBER, "PUT", "/photos/folders"]] as const) {
    const r = await s.call(method, path, who, method === "PUT" ? { folders: [] } : undefined);
    assert.equal(r.status, 403, `${who.role} ${method} ${path}`);
    assert.equal(r.json.code, "forbidden");
  }
  assert.equal((await s.call("PUT", "/photos/folders", OWNER, { folders: [{ root: s.dir, path: "lib/p.png" }] })).status, 400, "a file is no folder");
  assert.equal((await s.call("PUT", "/photos/folders", OWNER, { folders: [{ root: s.dir, path: "../x" }] })).status, 400);

  const set = await s.call("PUT", "/photos/folders", OWNER, { folders: [{ root: s.dir, path: "/lib/" }, { root: s.dir, path: "lib" }] });
  assert.equal(set.status, 200, JSON.stringify(set.json));
  assert.deepEqual(set.json, { folders: [{ root: s.dir, path: "lib" }], backup: { root: s.backup, path: "" } });
  await s.service.photos.settled();
  const libReads = s.station.seen.asked.filter((a) => a.root === s.dir && a.path.startsWith("lib") && a.route !== "/drive/stat");
  assert.ok(libReads.length > 0);
  assert.ok(libReads.every((a) => a.viewer === header(OWNER)), "the library read as the owner who set it");

  const album = photoId(s.dir, "lib");
  const ids = { a: photoId(s.dir, "lib/2024/a.jpg"), b: photoId(s.dir, "lib/2024/b.HEIC"), c: photoId(s.dir, "lib/clips/c.mp4"), p: photoId(s.dir, "lib/p.png"), g: photoId(s.dir, "lib/g.gif") };
  const albums = (await s.call("GET", "/photos/albums", MEMBER)).json;
  assert.deepEqual(albums, { albums: [{ id: "backup", title: "手机备份", cover: null, count: 0 }, { id: album, title: "lib", cover: ids.a, count: 5 }] });

  const a = (await s.call("GET", `/photos/items/${ids.a}`, MEMBER)).json;
  assert.deepEqual(a, { id: ids.a, kind: "photo", taken: Date.UTC(2024, 4, 1, 1, 20, 30), w: 3024, h: 4032, size: statSync(join(s.dir, "lib/2024/a.jpg")).size, root: s.dir, path: "lib/2024/a.jpg", camera: "Apple iPhone 15 Pro", lens: "iPhone 15 Pro back camera 6.86mm f/1.78", gps: { lat: 35.6582, lon: 139.741733 } });
  const c = (await s.call("GET", `/photos/items/${ids.c}`, MEMBER)).json;
  assert.deepEqual([c.kind, c.taken, c.duration, c.w, c.h], ["video", Date.UTC(2022, 5, 15, 8), 12.5, 1080, 1920]);
  const p = (await s.call("GET", `/photos/items/${ids.p}`, OWNER)).json;
  assert.deepEqual([p.taken, p.w, p.h, p.camera], [at(2021, 3, 4), 10, 20, undefined], "no EXIF: the file's time");
  assert.equal((await s.call("GET", "/photos/items/nope", MEMBER)).status, 404);

  // From the newest day back: four days, newest first, each day's newest first.
  const all = (await s.call("GET", "/photos/timeline", MEMBER)).json;
  assert.deepEqual(all.days.map((d: any) => [d.day, d.items.map((i: any) => i.id)]), [
    ["2024-05-01", [ids.a]],
    ["2024-01-01", [ids.b]],
    ["2022-06-15", [ids.c]],
    ["2021-03-04", [ids.g, ids.p].sort()],
  ]);
  assert.deepEqual(all.more, { before: false, after: false });
  assert.deepEqual([all.days[1].items[0].taken, all.days[1].items[0].w, all.days[1].items[0].h], [new Date(2024, 0, 1, 8).getTime(), 3024, 4032], "the HEIC turned by irot");
  const v = all.days[2].items[0];
  assert.deepEqual(v, { id: ids.c, kind: "video", taken: Date.UTC(2022, 5, 15, 8), w: 1080, h: 1920, thumbhash: v.thumbhash, duration: 12.5 });

  const days = async (q: string) => {
    const r = (await s.call("GET", `/photos/timeline${q}`, MEMBER)).json;
    return [r.days.map((d: any) => d.day), r.more];
  };
  const order = all.days.map((d: any) => d.day) as string[];
  assert.deepEqual(await days("?before=1"), [order.slice(0, 2), { before: true, after: false }]);
  assert.deepEqual(await days(`?around=${order[1]}&before=1&after=1`), [order.slice(0, 3), { before: true, after: false }]);
  assert.deepEqual(await days(`?around=${order[2]}&before=0&after=0`), [[order[2]], { before: true, after: true }]);
  assert.deepEqual(await days("?around=2023-01-01&before=1&after=1"), [[order[1], order[2]], { before: true, after: true }], "a day without items: the days on either side");
  assert.deepEqual(await days("?around=1999-01-01&before=5&after=2"), [[order[2], order[3]], { before: false, after: true }]);
  assert.equal((await s.call("GET", "/photos/timeline?around=yesterday", MEMBER)).status, 400);
  assert.equal((await s.call("GET", "/photos/timeline?before=-1", MEMBER)).status, 400);

  // Folders taken out of the library: their album goes.
  await s.call("PUT", "/photos/folders", OWNER, { folders: [] });
  await s.service.photos.settled();
  assert.deepEqual((await s.call("GET", "/photos/albums", MEMBER)).json, { albums: [{ id: "backup", title: "手机备份", cover: null, count: 0 }] });
  assert.deepEqual((await s.call("GET", "/photos/timeline", MEMBER)).json, { days: [], more: { before: false, after: false } });
});

test("thumbnails: one with its size, the batch with its index, kept until the file changes; HEIC and posters by sips", async (t) => {
  const fixtures = mkdtempish();
  t.after(() => rmSync(fixtures, { recursive: true, force: true }));
  const sips = fakeSips(fixtures);
  const s = await started(1 << 20, sips.script);
  t.after(s.stop);
  const lib = library(s.dir);
  await s.call("PUT", "/photos/folders", OWNER, { folders: [{ root: s.dir, path: "lib" }] });
  await s.service.photos.settled();
  const ids = { a: photoId(s.dir, "lib/2024/a.jpg"), b: photoId(s.dir, "lib/2024/b.HEIC"), c: photoId(s.dir, "lib/clips/c.mp4"), p: photoId(s.dir, "lib/p.png"), g: photoId(s.dir, "lib/g.gif") };

  // Made in the background: every item has its ThumbHash.
  const timeline = (await s.call("GET", "/photos/timeline", MEMBER)).json;
  const hashes = new Map(timeline.days.flatMap((d: any) => d.items.map((i: any) => [i.id, i.thumbhash])));
  assert.equal(hashes.get(ids.a), Buffer.from("th:a.jpg").toString("base64"), "the station's");
  for (const id of [ids.b, ids.c, ids.g]) assert.match(String(hashes.get(id)), /^[A-Za-z0-9+/]+=*$/, "by sips' BMP");
  const thumbs = s.station.seen.thumbs;
  const posters = s.station.seen.posters;

  const one = await s.call("GET", `/photos/thumbs/${ids.a}?size=large`, MEMBER);
  assert.equal(one.status, 200);
  assert.deepEqual(one.bytes, readFileSync(join(lib, "2024/a.jpg")));
  assert.deepEqual([one.headers["content-type"], one.headers["stillfail-width"], one.headers["stillfail-height"]], ["image/jpeg", "4032", "3024"]);
  assert.equal(s.station.seen.thumbs, thumbs, "kept from the background's");
  const heif = await s.call("GET", `/photos/thumbs/${ids.b}?size=grid`, MEMBER);
  assert.deepEqual([heif.bytes.equals(sips.jpg), heif.headers["stillfail-width"], heif.headers["stillfail-height"]], [true, "720", "540"]);
  assert.equal((await s.call("GET", `/photos/thumbs/${ids.a}?size=huge`, MEMBER)).status, 400);
  assert.equal((await s.call("GET", "/photos/thumbs/nope", MEMBER)).status, 404);
  assert.equal((await s.call("GET", `/photos/thumbs/${ids.a}`, VIEWER)).status, 403);

  const batch = await s.call("GET", `/photos/thumbs?ids=${[ids.a, "nope", ids.c, ids.b].join(",")}&size=grid`, MEMBER);
  assert.equal(batch.status, 200);
  const index = JSON.parse(String(batch.headers["stillfail-index"]));
  assert.deepEqual(index.map((x: any) => x.id), [ids.a, ids.c, ids.b], "what is not there left out");
  const slice = (i: number) => batch.bytes.subarray(index[i].offset, index[i].offset + index[i].length);
  assert.deepEqual(slice(0), readFileSync(join(lib, "2024/a.jpg")));
  assert.deepEqual(slice(1), POSTER());
  assert.deepEqual([index[1].w, index[1].h], [640, 360]);
  assert.deepEqual(slice(2), sips.jpg);
  assert.equal(index[2].offset + index[2].length, batch.bytes.length);
  assert.equal(s.station.seen.posters, posters, "kept");
  const many = Array.from({ length: 65 }, (_, i) => `x${i}`).join(",");
  assert.equal((await s.call("GET", `/photos/thumbs?ids=${many}`, MEMBER)).status, 400);

  // The file changed: made again.
  write(join(lib, "2024/a.jpg"), exifJpeg(4032, 3024, PHONE_EXIF(), Buffer.alloc(10)), at(2025, 2, 2));
  await s.service.photos.pass();
  await s.service.photos.settled();
  assert.equal(s.station.seen.thumbs, thumbs + 1);
  const again = await s.call("GET", `/photos/thumbs/${ids.a}`, MEMBER);
  assert.deepEqual(again.bytes, readFileSync(join(lib, "2024/a.jpg")));
  assert.equal(s.station.seen.thumbs, thumbs + 1);
});

/// A short folder of the test's own.
function mkdtempish() {
  const d = join("/tmp", `mp-${process.pid}-${Math.random().toString(36).slice(2, 8)}`);
  mkdirSync(d, { recursive: true });
  return d;
}

test("changes followed through drive/watch: a file added, a folder moved in, files and folders gone; members told", async (t) => {
  const s = await started(1 << 20);
  t.after(s.stop);
  const lib = library(s.dir);
  await s.call("PUT", "/photos/folders", OWNER, { folders: [{ root: s.dir, path: "lib" }] });
  await s.service.photos.settled();
  const member = listen(s.socket, MEMBER);
  const viewer = listen(s.socket, VIEWER);
  await Promise.all([member.ready, viewer.ready]);
  t.after(() => {
    member.close();
    viewer.close();
  });
  const has = async (id: string) => (await s.call("GET", `/photos/items/${id}`, MEMBER)).status === 200;
  // The watches asked for (each folder the library knows).
  await until(() => ["lib", "lib/2024"].every((p) => s.station.seen.asked.some((a) => a.route === "/drive/watch" && a.path === p)), "watching");

  write(join(lib, "new.png"), png(4, 4), at(2023, 7, 7));
  s.station.changed(lib);
  const added = photoId(s.dir, "lib/new.png");
  await until(() => has(added), "the new file");
  await until(() => member.events.some((e) => e.event === "photos"), "the event");
  assert.deepEqual(member.events.find((e) => e.event === "photos")!.data, {});

  const staging = join(s.dir, "staging");
  write(join(staging, "trip", "day1", "x.png"), png(2, 2), at(2023, 8, 8));
  renameSync(join(staging, "trip"), join(lib, "trip"));
  s.station.changed(lib);
  const deep = photoId(s.dir, "lib/trip/day1/x.png");
  await until(() => has(deep), "the folder moved in, walked");

  rmSync(join(lib, "new.png"));
  s.station.changed(lib);
  await until(async () => !(await has(added)), "the file gone");
  rmSync(join(lib, "trip"), { recursive: true });
  s.station.changed(lib);
  await until(async () => !(await has(deep)), "the folder gone");
  rmSync(join(lib, "2024", "a.jpg"));
  s.station.changed(join(lib, "2024"));
  await until(async () => !(await has(photoId(s.dir, "lib/2024/a.jpg"))), "a file in a folder below gone");
  assert.ok(await has(photoId(s.dir, "lib/2024/b.HEIC")));
  await wait(1200);
  assert.equal(viewer.events.filter((e) => e.event === "photos").length, 0, "a viewer is not told");
});

test("upload: resumed, checked, put in the member's backup folder by month, a name taken given a number; has", async (t) => {
  const s = await started(1 << 20);
  t.after(s.stop);
  // Before any folders are set: the backup folder only, read as the last member who may write who asked.
  write(join(s.backup, "someone@example.com", "2020", "01", "old.png"), png(3, 3), at(2020, 1, 5));
  const listener = listen(s.socket, MEMBER);
  await listener.ready;
  t.after(() => listener.close());

  const photo = exifJpeg(4032, 3024, PHONE_EXIF(), Buffer.alloc(30_000, 7));
  const hash = sha(photo);
  const taken = Date.UTC(2024, 1, 10, 4);
  const q = (offset: number, h = hash, size = photo.length, name = "IMG_1.jpg") => `/photos/upload?name=${encodeURIComponent(name)}&size=${size}&hash=${h}&taken=${taken}&offset=${offset}`;
  const up = (who: typeof MEMBER, offset: number, body: Buffer, h?: string, name?: string, size?: number) => callBytes(s.socket, "POST", q(offset, h, size, name), who, body);

  assert.deepEqual((await s.call("GET", `/photos/has?hash=${hash}`, MEMBER)).json, { id: null });
  await s.service.photos.settled();
  const old = photoId(s.backup, "someone@example.com/2020/01/old.png");
  assert.equal((await s.call("GET", `/photos/items/${old}`, MEMBER)).status, 200, "the backup folder indexed");
  assert.ok(s.station.seen.asked.filter((a) => a.root === s.backup).every((a) => a.viewer === header(MEMBER)));
  assert.equal((await s.call("GET", "/photos/has?hash=nope", MEMBER)).status, 400);

  assert.equal((await up(VIEWER, 0, photo.subarray(0, 100))).status, 403);
  assert.deepEqual((await up(MEMBER, 0, photo.subarray(0, 10_000))).json, { have: 10_000 });
  const ahead = await up(MEMBER, 20_000, photo.subarray(20_000, 21_000));
  assert.equal(ahead.status, 409);
  assert.deepEqual([ahead.json.code, ahead.json.have], ["conflict", 10_000]);
  assert.deepEqual((await up(MEMBER, 0, Buffer.alloc(0))).json, { have: 10_000 }, "asked where it is");
  assert.deepEqual((await up(MEMBER, 5_000, photo.subarray(5_000, 10_000))).json, { have: 10_000 }, "a part sent again");
  assert.equal((await up(MEMBER, 10_000, Buffer.alloc(photo.length))).status, 400, "past its size");
  const done = await up(MEMBER, 10_000, photo.subarray(10_000));
  assert.equal(done.status, 200, JSON.stringify(done.json));
  const path = "u-member@example.com/2024/02/IMG_1.jpg";
  assert.deepEqual(done.json, { have: photo.length, id: photoId(s.backup, path) });
  const file = join(s.backup, ...path.split("/"));
  assert.deepEqual(readFileSync(file), photo);
  assert.equal(Math.round(statSync(file).mtimeMs), taken, "its time the one it was taken at");
  assert.deepEqual((await s.call("GET", `/photos/has?hash=${hash}`, OWNER)).json, { id: done.json.id });
  const item = (await s.call("GET", `/photos/items/${done.json.id}`, MEMBER)).json;
  assert.deepEqual([item.taken, item.w, item.h, item.root, item.path], [Date.UTC(2024, 4, 1, 1, 20, 30), 3024, 4032, s.backup, path], "the EXIF's time over the phone's");
  await until(() => listener.events.some((e) => e.event === "photos"), "told");

  // Already there: answered at once.
  assert.deepEqual((await up(OWNER, 0, photo.subarray(0, 10))).json, { have: photo.length, id: done.json.id });

  // Another photo by the same name in the same month: a number given.
  const other = exifJpeg(100, 100, PHONE_EXIF(), Buffer.alloc(100, 1));
  const second = await up(MEMBER, 0, other, sha(other), "IMG_1.jpg", other.length);
  assert.deepEqual(second.json, { have: other.length, id: photoId(s.backup, "u-member@example.com/2024/02/IMG_1 (1).jpg") });

  // Not what its hash says: refused, started over.
  const wrong = await up(MEMBER, 0, other, "0".repeat(64), "bad.jpg", other.length);
  assert.equal(wrong.status, 409);
  assert.equal(wrong.json.code, "conflict");

  // Not a photo, a part too large.
  assert.equal((await up(MEMBER, 0, Buffer.from("x"), hash, "notes.txt", 1)).status, 415);
  assert.equal((await up(MEMBER, 0, Buffer.from("x"), hash, "../x.jpg", 1)).status, 400);
  const big = Buffer.alloc(8 * 1024 * 1024 + 1);
  assert.equal((await up(MEMBER, 0, big, sha(big), "big.mp4", big.length)).status, 413);

  // A full pass keeps what was uploaded as it was (its hash too).
  await s.service.photos.pass();
  await s.service.photos.settled();
  assert.deepEqual((await s.call("GET", `/photos/has?hash=${hash}`, MEMBER)).json, { id: done.json.id });
  const albums = (await s.call("GET", "/photos/albums", MEMBER)).json.albums;
  assert.deepEqual(albums.map((a: any) => [a.id, a.count]), [["backup", 3]]);
});

test("photos are the home workspace's: a member of another workspace the station joined is refused", async () => {
  const s = await started();
  const away = ascii({ sub: "u-away", email: "away@example.com", name: "外", role: "member", workspace: "w9", home: false });
  const got = await new Promise<{ status: number }>((resolve, reject) => {
    request({ socketPath: s.socket, path: "/photos/albums", headers: { "stillfail-viewer": away } }, (res) => {
      res.resume();
      resolve({ status: res.statusCode! });
    }).on("error", reject).end();
  });
  assert.equal(got.status, 403);
  await s.stop();
});
