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
