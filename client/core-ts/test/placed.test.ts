import assert from "node:assert/strict";
import { test } from "node:test";
import { near } from "../src/placed.ts";

test("the same image in a message and two quotes has a distinct place in the gallery", () => {
  const photo = { name: "photo.png", path: "/w/uploads/photo.png", owner: "s1", size: 1 };
  const next = { name: "next.png", path: "/w/uploads/next.png", owner: "s1", size: 1 };
  const chat = { messages: [
    { ts: "1", attachments: [photo] },
    { ts: "2", attachments: [photo], quotes: [{ file: "photo.png" }, { file: "photo.png" }] },
    { ts: "3", attachments: [next] },
  ] };
  const at = near;
  assert.deepEqual(at(chat, photo.path, "m:1/f"), {
    after: photo, afterAt: "m:2/q:0", index: 0, count: 4,
  });
  assert.deepEqual(at(chat, photo.path, "m:2/q:0"), {
    before: photo, beforeAt: "m:1/f", after: photo, afterAt: "m:2/q:1", index: 1, count: 4,
  });
  assert.deepEqual(at(chat, photo.path, "m:2/q:1"), {
    before: photo, beforeAt: "m:2/q:0", after: next, afterAt: "m:3/f", index: 2, count: 4,
  });
});

test("a quote is ordered before placed and remaining files and retains its place as an outbox message is delivered", () => {
  const photo = { name: "photo.png", path: "/w/photo.png", owner: "s1", size: 1 };
  const first = { name: "first.png", path: "/w/first.png", owner: "s1", size: 1 };
  const last = { name: "last.png", path: "/w/last.png", owner: "s1", size: 1 };
  const content = { attachments: [last, photo, first], quotes: [{ file: "photo.png" }], placed: ["first.png"] };
  const sending = { outbox: [{ ...content, id: "sent-1" }] };
  const delivered = { messages: [{ ...content, ts: "42", outgoing: "sent-1" }] };
  for (const chat of [sending, delivered]) {
    assert.deepEqual(near(chat, photo.path, "o:sent-1/q:0"), {
      after: first, afterAt: "o:sent-1/f", index: 0, count: 3,
    });
    assert.deepEqual(near(chat, first.path, "o:sent-1/f"), {
      before: photo, beforeAt: "o:sent-1/q:0", after: last, afterAt: "o:sent-1/f", index: 1, count: 3,
    });
    assert.deepEqual(near(chat, photo.path, "m:elsewhere/q:0"), { count: 3 });
  }
  // An older client without an occurrence still gets the first match and the original response shape.
  assert.deepEqual(near(delivered, photo.path), { after: first, index: 0, count: 3 });
});
