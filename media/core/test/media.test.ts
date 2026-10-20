// The media module in a whole core (media/core/media.ts): the shelf and a book's place read from the station's media
// service as they are shown, kept, and read again when its events say they changed; a place set shown at once; a
// chapter kept once read; pictures with their bytes beside the answer.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Queue } from "effect";
import { apply, answers, call, subscribe, v } from "../../../client/core-ts/test/helpers.ts";
import { Raw, started, stationReplies } from "../../../client/core-ts/test/station-fixture.ts";
import { EVICT_AFTER_MS } from "../../../client/core-ts/src/store.ts";
import { media } from "../media.ts";

const ST = "ws/st";
const M = "/admin/api/m/media";

test("the shelf is read as it is shown, kept, and read again when the service says it changed", async () => {
  let books = [{ id: "b1", title: "三体", chapters: 30 }];
  const s = await started(undefined, 0, undefined, undefined, [media]);
  const { host, core } = s;
  stationReplies(host, (req) => (req.url.endsWith(`${M}/books`) && req.method === "GET" ? { books } : undefined));
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "media.shelf", station: ST });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).books.map((b: { title: string }) => b.title), ["三体"]);
  const events = s.streams.find((x) => x.path === "/m/media/events" && !x.closed);
  assert.ok(events, "its events are followed while it is shown");
  books = [...books, { id: "b2", title: "活着", chapters: 12 }];
  Queue.offerUnsafe(events.queue, new TextEncoder().encode(`event: shelf\ndata: {}\n\n`));
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).books.map((b: { title: string }) => b.title), ["三体", "活着"]);
  // Shown no more (and let go of, a while after): its events are too.
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  assert.ok(events.closed);
  core.close();
});

test("a place set is shown at once and sent; an older one does not replace a newer", async () => {
  const s = await started(undefined, 0, undefined, undefined, [media]);
  const { host, core } = s;
  const put: unknown[] = [];
  stationReplies(host, (req) => {
    if (req.url.endsWith(`${M}/books/b1/place`) && req.method === "GET") return { place: null };
    if (req.url.endsWith(`${M}/books/b1/place`) && req.method === "PUT") {
      put.push(JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array())));
      return { ok: true };
    }
    return undefined;
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "media.place", station: ST, book: "b1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1), { place: null });
  call(core, ui, 2, "media.place.set", { station: ST, book: "b1", place: { chapter: 3, offset: 1200, at: 2000 } });
  call(core, ui, 3, "media.place.set", { station: ST, book: "b1", place: { chapter: 1, offset: 5, at: 1000 } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { place: { chapter: 3, offset: 1200, at: 2000 } });
  assert.equal(put.length, 2, "both go to the service, which keeps the latest");
  core.close();
});

test("a chapter is kept once read; a picture comes with its bytes", async () => {
  const s = await started(undefined, 0, undefined, undefined, [media]);
  const { host, core } = s;
  const png = new Uint8Array([137, 80, 78, 71]);
  stationReplies(host, (req) => {
    if (req.url.endsWith(`${M}/books/b1/chapters/0`)) return { chars: 5, blocks: [{ t: "p", text: "第一章开头" }] };
    if (req.url.endsWith(`${M}/books/b1/images/i1`)) return new Raw({ status: 200, headers: [["content-type", "image/png"]], body: png });
    return undefined;
  });
  const ui = core.connect();
  call(core, ui, 1, "media.chapter", { station: ST, book: "b1", index: 0 });
  await host.settle();
  call(core, ui, 2, "media.chapter", { station: ST, book: "b1", index: 0 });
  call(core, ui, 3, "media.image", { station: ST, book: "b1", ref: "i1" });
  call(core, ui, 4, "media.chapter", { station: ST, book: "b1" });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.deepEqual(answers(emitted, 1)?.ok, { chars: 5, blocks: [{ t: "p", text: "第一章开头" }] });
  assert.deepEqual(answers(emitted, 2)?.ok, answers(emitted, 1)?.ok);
  assert.equal(host.requests.filter((r) => r.url.endsWith(`${M}/books/b1/chapters/0`)).length, 1, "read once");
  const image = answers(emitted, 3) as { ok: { type: string }; bytes: Uint8Array };
  assert.equal(image.ok.type, "image/png");
  assert.deepEqual([...image.bytes], [...png]);
  assert.equal((answers(emitted, 4)?.error as { code: string }).code, "invalid_params");
  core.close();
});

test("the photos' timeline, a window of it read as it is shown and again when the photos change; thumbnails many at once", async () => {
  let days = [{ day: "2026-10-18", items: [{ id: "a1", kind: "photo", taken: 1, w: 4, h: 3, thumbhash: "x" }] }];
  const s = await started(undefined, 0, undefined, undefined, [media]);
  const { host, core } = s;
  const jpeg = new Uint8Array([255, 216, 1, 2, 255, 217, 255, 216, 3, 255, 217]);
  stationReplies(host, (req) => {
    if (req.url.includes(`${M}/photos/timeline?`)) return { days, more: { before: false, after: false } };
    if (req.url.includes(`${M}/photos/thumbs?ids=a1,b2&size=grid`))
      return new Raw({ status: 200, headers: [["content-type", "application/octet-stream"], ["stillfail-index", JSON.stringify([{ id: "a1", offset: 0, length: 6, w: 4, h: 3 }, { id: "b2", offset: 6, length: 5, w: 3, h: 4 }])]], body: jpeg });
    return undefined;
  });
  const ui = core.connect();
  core.receiveJson(ui, JSON.stringify({ id: 1, subscribe: { topic: "media.timeline", station: ST, before: 30 } }));
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).days.map((d: { day: string }) => d.day), ["2026-10-18"]);
  assert.ok(host.requests.some((r) => r.url.endsWith(`${M}/photos/timeline?before=30&after=0`)));
  const events = s.streams.find((x) => x.path === "/m/media/events" && !x.closed)!;
  days = [{ day: "2026-10-19", items: [{ id: "b2", kind: "video", taken: 2, w: 3, h: 4, thumbhash: "y" }] }, ...days];
  Queue.offerUnsafe(events.queue, new TextEncoder().encode("event: photos\ndata: {}\n\n"));
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).days.map((d: { day: string }) => d.day), ["2026-10-19", "2026-10-18"]);
  call(core, ui, 2, "media.thumbs", { station: ST, ids: ["a1", "b2"] });
  call(core, ui, 3, "media.thumbs", { station: ST, ids: [] });
  await host.settle();
  const emitted = host.takeEmitted();
  const thumbs = answers(emitted, 2) as { ok: { index: { id: string; offset: number; length: number }[] }; bytes: Uint8Array };
  assert.deepEqual(thumbs.ok.index.map((i) => [i.id, i.offset, i.length]), [["a1", 0, 6], ["b2", 6, 5]]);
  assert.equal(thumbs.bytes.length, 11);
  assert.equal((answers(emitted, 3)?.error as { code: string }).code, "invalid_params");
  core.close();
});

test("films and shows: the library and a place in one read as shown and as the service says they changed; a player's parts fetched", async () => {
  let progress: unknown = null;
  const s = await started(undefined, 0, undefined, undefined, [media]);
  const { host, core } = s;
  const segment = new Uint8Array([71, 1, 2, 3]);
  stationReplies(host, (req) => {
    if (req.url.endsWith(`${M}/videos/library`)) return { movies: [{ id: "m1", title: "活着", year: 1994 }], shows: [], recent: progress ? [{ id: "m1" }] : [] };
    if (req.url.endsWith(`${M}/videos/m1/progress`) && req.method === "GET") return { progress };
    if (req.url.endsWith(`${M}/videos/m1/progress`) && req.method === "PUT") return { ok: true };
    if (req.url.endsWith(`${M}/videos/m1/hls/0.ts`)) return new Raw({ status: 200, headers: [["content-type", "video/mp2t"]], body: segment });
    return undefined;
  });
  const ui = core.connect();
  core.receiveJson(ui, JSON.stringify({ id: 1, subscribe: { topic: "media.videos", station: ST } }));
  core.receiveJson(ui, JSON.stringify({ id: 2, subscribe: { topic: "media.progress", station: ST, id: "m1" } }));
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).movies.map((m: { title: string }) => m.title), ["活着"]);
  assert.deepEqual(v(values, 2), { progress: null });
  // Watched here: shown at once.
  call(core, ui, 3, "media.video.progress.set", { station: ST, id: "m1", position: 600, at: 1000 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2), { progress: { position: 600, at: 1000 } });
  // Watched on another device: the service says so.
  progress = { position: 1200, at: 2000 };
  const events = s.streams.find((x) => x.path === "/m/media/events" && !x.closed)!;
  Queue.offerUnsafe(events.queue, new TextEncoder().encode('event: progress\ndata: {"id":"m1"}\n\n'));
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2), { progress: { position: 1200, at: 2000 } });
  assert.deepEqual(v(values, 1).recent, [{ id: "m1" }]);
  call(core, ui, 4, "media.video.fetch", { station: ST, path: "/videos/m1/hls/0.ts" });
  call(core, ui, 5, "media.video.fetch", { station: ST, path: "/books/b1" });
  await host.settle();
  const emitted = host.takeEmitted();
  const got = answers(emitted, 4) as { ok: { type: string }; bytes: Uint8Array };
  assert.equal(got.ok.type, "video/mp2t");
  assert.deepEqual([...got.bytes], [...segment]);
  assert.equal((answers(emitted, 5)?.error as { code: string }).code, "invalid_params");
  core.close();
});
