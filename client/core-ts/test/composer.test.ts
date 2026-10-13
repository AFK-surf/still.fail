// What is being written in a chat, kept by the core (composer.ts): words, quotes, files going up, taken to send and put
// back, carried on into the chat a new one made, and kept on the device as the chat's draft.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { dbName, SOON_MS } from "../src/data.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

type J = any;

async function setup() {
  const s = await started();
  const ui = s.core.connect();
  let id = 100;
  const values = new Map<number, unknown>();
  const settle = async () => {
    await s.host.settle();
    await s.host.time.pass(60);
    await s.host.settle();
    apply(s.host, values);
  };
  const ask = async (name: string, params: J): Promise<J> => {
    const at = ++id;
    call(s.core, ui, at, `composer.${name}`, params);
    await settle();
    return null;
  };
  const watch = async (sub: number, key: string) => {
    subscribe(s.core, ui, sub, { topic: "composer", key });
    await settle();
  };
  return { ...s, ui, values, settle, ask, watch };
}

test("what_is_written_shows_with_what_it_can_do_and_is_kept_as_the_chats_draft", async () => {
  const t = await setup();
  await t.watch(1, "ws/st:k");
  assert.deepEqual([v(t.values, 1).text, v(t.values, 1).ready, v(t.values, 1).quotes], ["", false, []]);
  await t.ask("text", { key: "ws/st:k", text: "修一下" });
  // The words are the page's: they come back as written, with no new `rev` (the page has them already), and it can be
  // sent now.
  assert.deepEqual([v(t.values, 1).text, v(t.values, 1).rev, v(t.values, 1).ready], ["修一下", 0, true]);
  await t.ask("quote", { key: "ws/st:k", id: "q1", quote: { author: "agent", text: "这段", ts: "1.0", role: "agent" }, focus: true });
  assert.deepEqual(v(t.values, 1).quotes.map((q: J) => [q.id, q.text, q.comment]), [["q1", "这段", ""]]);
  assert.equal(v(t.values, 1).focus, "q1");
  await t.ask("comment", { key: "ws/st:k", id: "q1", comment: "为什么" });
  await t.ask("focused", { key: "ws/st:k" });
  assert.deepEqual([v(t.values, 1).quotes[0].comment, v(t.values, 1).focus], ["为什么", undefined]);
  // On the device a moment after the last change, as the chat's draft.
  await t.host.time.pass(SOON_MS + 50);
  await t.host.settle();
  const kept = t.host.rows(dbName("s1"), "SELECT json FROM draft ORDER BY station, chat").map(([json]) => JSON.parse(json as string));
  assert.deepEqual(kept.map((d: J) => [d.text, d.quotes.map((q: J) => [q.text, q.comment])]), [["修一下", [["这段", "为什么"]]]]);
  t.core.close();
});

test("taken_to_send_it_empties_and_comes_back_when_it_could_not_go_unless_something_new_was_written", async () => {
  const t = await setup();
  await t.watch(1, "ws/st:k");
  await t.ask("text", { key: "ws/st:k", text: "  发出去  " });
  await t.ask("quote", { key: "ws/st:k", id: "q1", quote: { author: "agent", text: "这段" } });
  const at = 900;
  call(t.core, t.ui, at, "composer.take", { key: "ws/st:k" });
  await t.settle();
  const before = v(t.values, 1);
  assert.deepEqual([before.text, before.quotes, before.ready], ["", [], false]);
  const rev = before.rev;
  await t.ask("restore", { key: "ws/st:k", error: "发不出去" });
  const back = v(t.values, 1);
  assert.deepEqual([back.text, back.quotes.length, back.error, back.rev > rev], ["  发出去  ", 1, "发不出去", true]);
  // Taken again, something new written meanwhile: not put back over it.
  call(t.core, t.ui, 901, "composer.take", { key: "ws/st:k" });
  await t.settle();
  await t.ask("text", { key: "ws/st:k", text: "新的" });
  await t.ask("restore", { key: "ws/st:k", error: "发不出去", unlessWritten: true });
  assert.deepEqual([v(t.values, 1).quotes.length, v(t.values, 1).error], [0, undefined]);
  t.core.close();
});

test("a_new_chats_words_go_on_into_the_chat_it_made_and_a_new_chat_moved_takes_its_words_not_its_files", async () => {
  const t = await setup();
  await t.watch(1, "new:ws/st");
  await t.ask("text", { key: "new:ws/st", text: "第一句" });
  await t.ask("carry", { key: "new:ws/st", to: "ws/st:made" });
  await t.watch(2, "ws/st:made");
  assert.deepEqual([v(t.values, 2).text, v(t.values, 2).ready], ["第一句", true]);
  assert.deepEqual([v(t.values, 1).text, v(t.values, 1).ready], ["", false]);
  await t.ask("text", { key: "new:ws/st", text: "换个 station" });
  await t.ask("move", { key: "new:ws/st", to: "new:ws/other" });
  await t.watch(3, "new:ws/other");
  assert.equal(v(t.values, 3).text, "换个 station");
  t.core.close();
});

test("files_go_up_by_their_station_and_say_how_far_and_a_failed_one_says_why", async () => {
  const t = await setup();
  const parts: J[] = [];
  const requests = t.core.inner.stations.requests as J;
  requests.uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => {
    parts.push({ name: q.name, offset: q.offset, length: bytes.length });
    if (q.name === "bad.bin") return Effect.succeed({ have: q.offset });
    const have = q.offset + bytes.length;
    return Effect.succeed(have >= q.size ? { have, file: { name: q.name, path: `/u/${q.name}`, size: q.size } } : { have });
  };
  await t.watch(1, "ws/st:k");
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [{ id: "f1", name: "a.bin", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])]) }, { id: "f2", name: "bad.bin", size: 2, blob: new Blob([new Uint8Array([1, 2])]) }] });
  await t.settle();
  const files = v(t.values, 1).files;
  assert.deepEqual(files.map((f: J) => [f.id, f.done?.path ?? null, f.error ?? null]), [["f1", "/u/a.bin", null], ["f2", null, "上传失败"]]);
  assert.deepEqual(parts.map((p) => [p.name, p.offset, p.length]), [["a.bin", 0, 3], ["bad.bin", 0, 2]]);
  assert.equal(v(t.values, 1).uploading, false);
  t.core.close();
});

test("what_the_core_kept_frozen_is_read_back_and_written_on_copies", async () => {
  const t = await setup();
  // Kept on the device as a page before the composer wrote it (`draft.put`): held frozen by the core.
  call(t.core, t.ui, 50, "draft.put", { key: "ws/st:old", text: "旧的草稿", quotes: [{ author: "agent", text: "那段", comment: "嗯" }], files: [{ name: "a.png", path: "/u/a.png", size: 3 }] });
  await t.settle();
  await t.host.time.pass(SOON_MS + 50);
  await t.host.settle();
  await t.watch(1, "ws/st:old");
  const v1 = v(t.values, 1);
  assert.deepEqual([v1.text, v1.rev, v1.quotes.map((q: J) => [q.text, q.comment]), v1.files.map((f: J) => f.done.path), v1.ready], ["旧的草稿", 1, [["那段", "嗯"]], ["/u/a.png"], true]);
  // Every change on what it read: none throws (frozen), each on copies.
  const quote = v1.quotes[0].id;
  const file = v1.files[0].id;
  await t.ask("comment", { key: "ws/st:old", id: quote, comment: "改了" });
  await t.ask("text", { key: "ws/st:old", text: "旧的草稿，接着写" });
  await t.ask("quote", { key: "ws/st:old", id: "q2", quote: { author: "agent", text: "另一段" }, focus: true });
  await t.ask("unquote", { key: "ws/st:old", id: "q2" });
  call(t.core, t.ui, 60, "composer.take", { key: "ws/st:old" });
  await t.settle();
  await t.ask("restore", { key: "ws/st:old", error: null });
  await t.ask("carry", { key: "ws/st:old", to: "ws/st:new" });
  await t.watch(2, "ws/st:new");
  await t.ask("remove", { key: "ws/st:new", id: file });
  const v2 = v(t.values, 2);
  assert.deepEqual([v2.text, v2.quotes.map((q: J) => [q.text, q.comment]), v2.files], ["旧的草稿，接着写", [["那段", "改了"]], []]);
  t.core.close();
});
