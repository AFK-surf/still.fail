// What is being written in a chat, kept by the core (composer.ts): words, quotes, files going up, taken to send and put
// back, carried on into the chat a new one made, and kept on the device as the chat's draft.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { Core } from "../src/core.ts";
import { dbName, SOON_MS } from "../src/data.ts";
import { answers, apply, call, subscribe, v } from "./helpers.ts";
import { CoreFiles, PageFiles } from "../src/hosts/file-port.ts";
import { FileSource } from "../src/file-source.ts";
import { CoreError } from "../src/error.ts";
import { Raw, stationReplies, started } from "./station-fixture.ts";
import { HostWire } from "../src/station/wire.ts";

/// A draft as written, without the name the core gives it (its own test: draft-id.test.ts).
const noId = ({ id: _, ...d }: any) => d;

type J = any;

test("desktop_upload_retry_keeps_its_source_after_a_station_failure", async () => {
  const t = await setup();
  const released: number[] = [];
  const received: number[][] = [];
  const page = new PageFiles((m) => bridge.receive(structuredClone(m)));
  const bridge = new CoreFiles((m) => {
    if ((m as J).filePort === "release") released.push((m as J).file);
    page.receive(structuredClone(m));
  });
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => {
    received.push([...bytes]);
    return received.length === 1
      ? Effect.fail(new CoreError("upload", "try again"))
      : Effect.succeed({ have: bytes.length, file: { name: q.name, path: "/u/retried.png", size: bytes.length } });
  };
  await t.watch(1, "ws/st:k");
  const params = { key: "ws/st:k", station: "ws/st", files: [{ id: "f1", name: "image.png", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])]) }] };
  t.core.receiveRaw(t.ui, bridge.prepare(structuredClone(page.prepare({ id: 101, call: "composer.add", params }))));
  await t.settle();
  assert.equal(v(t.values, 1).files[0].error, "try again");
  assert.deepEqual(released, []);
  const retry = Effect.runPromise(t.core.inner.composers.uploaded("ws/st", [{ id: "f1", name: "image.png" }], true));
  await t.settle();
  assert.equal((await retry)[0].path, "/u/retried.png");
  assert.deepEqual(received, [[1, 2, 3], [1, 2, 3]]);
  assert.deepEqual(released, [1]);
  bridge.close(); t.core.close();
});

test("an_image_sent_up_from_here_is_shown_and_opened_from_the_device_not_read_back_from_its_station", async () => {
  const t = await setup();
  const png = Uint8Array.from({ length: 40 }, (_, i) => i);
  // The station keeps each under a name of its own, kept as it moves it into the chat's uploads.
  const stored = (name: string) => `2026-10-24T08-00-00-0a1b2c-${name}`;
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) =>
    Effect.succeed({ have: bytes.length, file: { name: q.name, path: `/data/uploads/${stored(q.name)}`, size: bytes.length } });
  const asked: string[] = [];
  stationReplies(t.host, (req) => {
    const u = new URL(req.url);
    if (!u.pathname.includes("/sessions/k1/")) return undefined;
    asked.push(`${u.pathname.split("/").at(-1)} ${u.searchParams.get("name")}`);
    return new Raw({ status: 200, headers: [["content-type", "text/plain"]], body: new Uint8Array([9]) });
  });
  await t.watch(1, "ws/st:k");
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [
    { id: "shot", name: "shot.png", size: png.length, blob: new Blob([png], { type: "image/png" }) },
    { id: "notes", name: "notes.txt", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])], { type: "text/plain" }) },
  ] });
  await t.settle();
  assert.deepEqual(v(t.values, 1).files.map((f: J) => f.done?.path), [`/data/uploads/${stored("shot.png")}`, `/data/uploads/${stored("notes.txt")}`]);
  // In whichever chat its message is, as its station names it there.
  const file = async (id: number, op: string, name: string, params: J = {}) => {
    call(t.core, t.ui, id, op, { station: "ws/st", key: "k1", name, ...params });
    await t.host.settle();
    return answers(t.host.takeEmitted(), id) as { ok: { type: string; total?: number }; bytes: Uint8Array };
  };
  const thumb = await file(201, "station.file", stored("shot.png"), { thumb: true });
  assert.deepEqual([thumb.ok, [...thumb.bytes]], [{ type: "image/png" }, [...png]]);
  const whole = await file(202, "station.file", stored("shot.png"));
  assert.deepEqual([...whole.bytes], [...png]);
  const part = await file(203, "station.file.part", stored("shot.png"), { offset: 10, length: 8 });
  assert.deepEqual([part.ok, [...part.bytes]], [{ type: "image/png", total: 40 }, [...png.slice(10, 18)]]);
  assert.deepEqual(asked, [], "its station not asked");
  // What is not an image is read from its station as before.
  await file(204, "station.file", stored("notes.txt"));
  assert.deepEqual(asked, [`files ${stored("notes.txt")}`]);
  // Counted and let go with the drives' files: then read from its station.
  call(t.core, t.ui, 205, "cache.usage", {});
  await t.host.settle();
  assert.equal((answers(t.host.takeEmitted(), 205)?.ok as { drive: number }).drive, png.length);
  call(t.core, t.ui, 206, "drive.kept.clear", {});
  await t.host.settle();
  await file(207, "station.file", stored("shot.png"), { thumb: true });
  assert.deepEqual(asked, [`files ${stored("notes.txt")}`, `files ${stored("shot.png")}`]);
  t.core.close();
});

test("a_failed_upload_goes_up_again_from_the_composer", async () => {
  const t = await setup();
  const received: number[][] = [];
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => {
    received.push([...bytes]);
    return received.length === 1
      ? Effect.fail(new CoreError("upload", "connection closed"))
      : Effect.succeed({ have: bytes.length, file: { name: q.name, path: "/u/again.png", size: bytes.length } });
  };
  await t.watch(1, "ws/st:k");
  call(t.core, t.ui, 101, "composer.add", { key: "ws/st:k", station: "ws/st", files: [{ id: "f1", name: "image.png", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])]) }] });
  await t.settle();
  assert.equal(v(t.values, 1).files[0].error, "connection closed");
  call(t.core, t.ui, 102, "composer.retry", { key: "ws/st:k", id: "f1" });
  await t.settle();
  const f = v(t.values, 1).files[0];
  assert.equal(f.error, undefined);
  assert.equal(f.done.path, "/u/again.png");
  assert.deepEqual(received, [[1, 2, 3], [1, 2, 3]]);
  // Retried once it is up: nothing goes again.
  call(t.core, t.ui, 103, "composer.retry", { key: "ws/st:k", id: "f1" });
  await t.settle();
  assert.equal(received.length, 2);
  t.core.close();
});

test("a_file_the_station_has_already_is_not_sent_again", async () => {
  const t = await setup();
  const asked: J[] = [];
  let parts = 0;
  const requests = t.core.inner.stations.requests as J;
  // the content named as the core names it (the blob read, WebCrypto's digest: done off the host's clock, so its end is
  // waited for here, not guessed by settling: run 39917135209 settled before it and found nothing up yet)
  let done = () => {};
  const named = new Promise<void>((resolve) => { done = resolve; });
  const name = Object.getPrototypeOf(requests).uploadName;
  requests.uploadName = async (...a: unknown[]) => { try { return await name.apply(requests, a); } finally { done(); } };
  (t.core.inner.stations.requests as J).uploadHave = (_addr: unknown, q: J) => { asked.push(q); return Effect.succeed({ name: q.name, path: "/u/kept.png", size: q.size }); };
  (t.core.inner.stations.requests as J).uploadPart = () => { parts++; return Effect.fail(new CoreError("upload", "not asked")); };
  await t.watch(1, "ws/st:k");
  call(t.core, t.ui, 101, "composer.add", { key: "ws/st:k", station: "ws/st", files: [{ id: "f1", name: "image.png", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])]) }] });
  await named;
  await t.settle();
  assert.equal(v(t.values, 1).files[0].done.path, "/u/kept.png");
  assert.equal(parts, 0);
  // Named by its content, as the station names what it has.
  assert.equal(asked[0].sha256, "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81");
  assert.equal(asked[0].size, 3);
  t.core.close();
});

test("desktop_files_reach_upload_and_release_on_success_or_removal_after_failure", async () => {
  const t = await setup();
  const received: number[][] = [];
  const released: number[] = [];
  const page = new PageFiles((m) => bridge.receive(structuredClone(m)));
  const bridge = new CoreFiles((m) => {
    if ((m as J).filePort === "release") released.push((m as J).file);
    page.receive(structuredClone(m));
  });
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => {
    received.push([...bytes]);
    return Effect.succeed({ have: bytes.length, file: { name: q.name, path: "/u/image.png", size: bytes.length } });
  };
  await t.watch(1, "ws/st:k");
  const send = (id: number) => {
    const message = { id, call: "composer.add", params: { key: "ws/st:k", station: "ws/st", files: [{ id: `f${id}`, name: "image.png", size: 3, blob: new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" }) }] } };
    t.core.receiveRaw(t.ui, bridge.prepare(structuredClone(page.prepare(message))));
  };
  send(101);
  await t.settle();
  assert.deepEqual(received, [[1, 2, 3]]);
  assert.equal(v(t.values, 1).files[0].done.path, "/u/image.png");
  assert.equal(v(t.values, 1).uploading, false);
  send(102);
  page.close();
  await t.settle();
  assert.match(v(t.values, 1).files[1].error, /no longer available/);
  assert.equal(v(t.values, 1).uploading, false);
  assert.deepEqual(released, [1]);
  await t.ask("remove", { key: "ws/st:k", id: "f102" });
  assert.deepEqual(released, [1, 2]);
  bridge.close(); t.core.close();
});

async function setup() {
  const t = await setupBare();
  // No station here has a file before it goes up (one that has: its own test).
  (t.core.inner.stations.requests as J).uploadName = () => Promise.resolve(null);
  return t;
}

async function setupBare() {
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

test("an_image_of_a_message_quoted_goes_again_with_the_message_as_it_is_on_the_station_nothing_going_up", async () => {
  const t = await setup();
  await t.watch(1, "ws/st:k");
  const image = { name: "shot.png", path: "/w/uploads/shot.png", size: 120, width: 40, height: 30, owner: "s1" };
  const quote = { author: "agent", text: "shot.png", ts: "1.0", role: "agent", file: "shot.png" };
  await t.ask("quote", { key: "ws/st:k", id: "q1", quote, focus: true, attachment: image, fileId: "f1" });
  // Quoted twice: the file goes once.
  await t.ask("quote", { key: "ws/st:k", id: "q2", quote, attachment: image });
  const shown = v(t.values, 1);
  assert.deepEqual([shown.quotes.map((q: J) => q.file), shown.files.map((f: J) => f.done), shown.uploading, shown.ready], [["shot.png", "shot.png"], [image], false, true]);
  assert.equal(shown.files[0].id, "f1");
  // Without the quote naming it, an attachment offered is not taken.
  await t.ask("quote", { key: "ws/st:k", id: "q3", quote: { author: "agent", text: "这段" }, attachment: { ...image, path: "/w/uploads/other.png" } });
  assert.equal(v(t.values, 1).files.length, 1);
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

test("a_made_chats_pending_draft_survives_restart_and_stays_cleared_after_sending", async () => {
  const t = await setup();
  const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
  t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
  const key = "ws/st:ember:made";
  const quote = { author: "agent", text: "那段", comment: "为什么", ts: "1.0", role: "agent" };
  const file = { name: "a.png", path: "/u/a.png", size: 3 };
  // Older clients kept writing under the temporary key after the station made the chat.
  t.core.inner.data.set({ topic: "draft", station: "ws/st", chat: pending }, { text: "还没发送", quotes: [quote], files: [file] });
  const restart = async (core: Core) => {
    await t.host.time.pass(SOON_MS + 50);
    await t.host.settle();
    await Effect.runPromise(core.inner.data.written);
    core.close();
    t.host.takeEmitted();
    return Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  };
  const again = await restart(t.core);
  try {
    const restored = again.inner.composers.value(key) as J;
    assert.deepEqual([restored.text, restored.quotes.map(({ id: _, ...q }: J) => q), restored.files.map((f: J) => f.done)], ["还没发送", [quote], [file]]);
    const sent = again.inner.composers.take(key);
    assert.deepEqual([sent.text, sent.quotes, sent.attachments], ["还没发送", [quote], [file]]);
    const third = await restart(again);
    try {
      for (const draft of [key, `ws/st:${pending}`]) {
        const cleared = third.inner.composers.value(draft) as J;
        assert.deepEqual([cleared.text, cleared.quotes, cleared.files, cleared.ready], ["", [], [], false]);
      }
    } finally { third.close(); }
  } finally { again.close(); }
});

test("a_canonical_draft_wins_over_its_old_pending_draft_without_crossing_stations", async () => {
  const t = await setup();
  const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
  t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
  const keep = (station: string, chat: string, text: string) => t.core.inner.data.set({ topic: "draft", station, chat }, { text, quotes: [], files: [] });
  keep("ws/st", pending, "旧的草稿");
  keep("ws/st", "ember:made", "接着写的草稿");
  keep("ws/other", "ember:made", "另一台 station 的草稿");
  await t.host.time.pass(SOON_MS + 50);
  await t.host.settle();
  await Effect.runPromise(t.core.inner.data.written);
  t.core.close();
  t.host.takeEmitted();
  const again = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  try {
    const text = (key: string) => (again.inner.composers.value(key) as J).text;
    assert.equal(text(`ws/st:${pending}`), "接着写的草稿");
    assert.equal(text("ws/st:ember:made"), "接着写的草稿");
    assert.equal(text("ws/other:ember:made"), "另一台 station 的草稿");
    assert.equal(text(`ws/other:${pending}`), "");
  } finally { again.close(); }
});

test("a_pending_and_made_composer_share_live_edits_upload_completion_and_a_draft_after_restart", async () => {
  const t = await setup();
  const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
  const old = `ws/st:${pending}`;
  const key = "ws/st:ember:made";
  const gate = Deferred.makeUnsafe<J, CoreError>();
  let uploads = 0;
  (t.core.inner.stations.requests as J).uploadPart = () => { uploads++; return Deferred.await(gate); };
  try {
    await t.watch(1, old);
    await t.ask("text", { key: old, text: "创建时写的" });
    await t.ask("add", { key: old, station: "ws/st", files: [{ id: "slow", name: "slow.txt", size: 3, blob: new Blob(["abc"]) }] });
    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    await t.watch(2, key);
    assert.equal(v(t.values, 2).text, "创建时写的");
    assert.equal(v(t.values, 2).uploading, true);
    await t.ask("text", { key, text: "接着写" });
    assert.equal(v(t.values, 1).text, "接着写");
    const saved = { name: "slow.txt", path: "/u/slow.txt", size: 3 };
    Deferred.doneUnsafe(gate, Effect.succeed({ have: 3, file: saved }));
    await t.settle();
    assert.equal(uploads, 1);
    for (const sub of [1, 2]) {
      assert.deepEqual(v(t.values, sub).files.map((f: J) => f.done), [saved]);
      assert.equal(v(t.values, sub).uploading, false);
    }
    assert.equal(v(t.values, 1).version, v(t.values, 2).version);
    // The current page keeps the pending key even after creation; reopening uses the station's key.
    await t.ask("text", { key: old, text: "创建完成后继续写" });
    for (const [from, to] of [[old, key], [key, old]]) {
      await t.ask("carry", { key: from, to });
      for (const sub of [1, 2]) {
        assert.equal(v(t.values, sub).text, "创建完成后继续写");
        assert.deepEqual(v(t.values, sub).files.map((f: J) => f.done), [saved]);
      }
    }
    await t.host.time.pass(SOON_MS + 50);
    await t.host.settle();
    await Effect.runPromise(t.core.inner.data.written);
    t.core.close();
    t.host.takeEmitted();
    const again = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
    try {
      const restored = again.inner.composers.value(key) as J;
      assert.deepEqual([restored.text, restored.files.map((f: J) => f.done)], ["创建完成后继续写", [saved]]);
    } finally { again.close(); }
  } finally { t.core.close(); }
});

test("draft_subscriptions_follow_both_chat_keys_when_joined_edited_and_taken", async () => {
  const t = await setup();
  const pending = t.core.inner.views.local.pendingNew("ws/st", { runtime: "claude" });
  const draft = { text: "还没发", quotes: [{ author: "agent", text: "那段", comment: "为什么", role: "agent" }], files: [{ name: "a.png", path: "/u/a.png", size: 3 }], links: [] };
  try {
    subscribe(t.core, t.ui, 1, { topic: "draft", station: "ws/st", chat: pending });
    subscribe(t.core, t.ui, 2, { topic: "draft", station: "ws/st", chat: "ember:made" });
    await t.settle();
    call(t.core, t.ui, 901, "draft.put", { key: `ws/st:${pending}`, ...draft });
    await t.settle();
    assert.deepEqual(noId(v(t.values, 1)), draft);
    assert.deepEqual(noId(v(t.values, 2)), { text: "", quotes: [], files: [], links: [] });

    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    await t.settle();
    for (const sub of [1, 2]) assert.deepEqual(noId(v(t.values, sub)), draft);
    const edited = { ...draft, text: "继续写" };
    call(t.core, t.ui, 902, "draft.put", { key: "ws/st:ember:made", ...edited });
    await t.settle();
    for (const sub of [1, 2]) assert.deepEqual(noId(v(t.values, sub)), edited);

    await t.ask("take", { key: "ws/st:ember:made" });
    for (const sub of [1, 2]) assert.deepEqual(noId(v(t.values, sub)), { text: "", quotes: [], files: [], links: [] });
  } finally { t.core.close(); }
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


// Hold the station's upload response until the test releases it: no timers or real network.
async function queuedUpload() {
  const t = await setup();
  const gate = Deferred.makeUnsafe<J, CoreError>();
  let tries = 0;
  (t.core.inner.stations.requests as J).uploadPart = () => { tries++; return Deferred.await(gate); };
  const posted: J[] = [];
  (t.core.inner.stations as J).post = (_station: string, thread: number, message: J) => Effect.sync(() => { posted.push({ thread, ...message }); return posted.length; });
  await t.watch(1, "ws/st:k");
  const file = { id: "slow", name: "slow.txt", size: 3, blob: new Blob(["abc"]) };
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [file] });
  const uploads = [{ id: file.id, name: file.name, size: file.size }];
  const saved = { name: file.name, size: file.size, path: "/u/slow.txt" };
  const send = (id: number, extra: J = {}) => call(t.core, t.ui, id, "chat.send", { station: "ws/st", thread: 7, text: "with file", uploads, ...extra });
  const finish = () => Deferred.doneUnsafe(gate, Effect.succeed({ have: 3, file: saved }));
  return { ...t, gate, posted, send, finish, saved, uploads, tries: () => tries, local: t.core.inner.views.local };
}

test("uploading_attachment_can_be_submitted_and_survives_leaving_the_composer_without_early_delivery", async () => {
  const t = await queuedUpload();
  assert.equal(v(t.values, 1).uploading, true);
  assert.equal(v(t.values, 1).ready, true); // attachment alone is enough
  await t.ask("take", { key: "ws/st:k" });
  t.send(501, { text: "", quotes: [{ author: "agent", text: "quote", comment: "" }] });
  await t.settle();
  assert.equal(v(t.values, 1).ready, false);
  assert.equal(t.posted.length, 0);
  assert.equal(t.local.outbox("ws/st", 7)[0].uploads[0].name, "slow.txt");
  t.core.disconnect(t.ui);
  t.finish();
  await t.settle();
  assert.equal(t.posted.length, 1);
  assert.deepEqual(t.posted[0].attachments, [t.saved]);
  assert.equal(t.posted[0].quotes[0].text, "quote");
  assert.equal(t.posted[0].uploads, undefined);
  t.core.close();
});

test("an_image_sent_while_going_up_keeps_its_shape_and_its_message_says_which_upload_it_was", async () => {
  const t = await queuedUpload();
  t.send(501, { uploads: [{ ...t.uploads[0], width: 1200, height: 800 }] });
  await t.settle();
  assert.deepEqual([t.local.outbox("ws/st", 7)[0].uploads[0].width, t.local.outbox("ws/st", 7)[0].uploads[0].height], [1200, 800]);
  assert.equal(t.local.uploadOf("ws/st", "/u/slow.txt"), undefined);
  t.finish();
  await t.settle();
  // The station is given the file as it keeps it, nothing of this device's; this device knows it by its name there,
  // wherever the station moves it.
  assert.deepEqual(t.posted[0].attachments, [t.saved]);
  assert.equal(t.local.uploadOf("ws/st", "/sessions/x/uploads/slow.txt"), "slow");
  assert.equal(t.local.uploadOf("ws/other", "/u/slow.txt"), undefined);
  // A size that is no size is refused: nothing joins the outbox.
  const queued = t.local.outbox("ws/st", 7).length;
  call(t.core, t.ui, 502, "chat.send", { station: "ws/st", thread: 7, text: "x", uploads: [{ ...t.uploads[0], width: 0 }] });
  await t.settle();
  assert.equal(t.local.outbox("ws/st", 7).length, queued);
  t.core.close();
});

test("an_image_sent_before_the_page_heard_its_size_goes_with_its_size_all_the_same", async () => {
  const t = await queuedUpload();
  // A PNG: its size is read from its header as it is added.
  const head = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x0b, 0x40, 0, 0, 0x07, 0x08]);
  const png = { id: "png", name: "shot.png", size: head.length, blob: new Blob([head], { type: "image/png" }) };
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [png] });
  await t.settle();
  assert.deepEqual(v(t.values, 1).files.find((f: J) => f.id === "png").width, 2880);
  // The page sent it as it knew it, without its size: the outbox has it.
  t.send(501, { uploads: [{ id: png.id, name: png.name, size: png.size }] });
  await t.settle();
  const [up] = t.local.outbox("ws/st", 7)[0].uploads;
  assert.deepEqual([up.id, up.width, up.height], ["png", 2880, 1800]);
  // Read after it was sent: the waiting message takes it there.
  t.send(502);
  await t.settle();
  assert.equal(t.local.outbox("ws/st", 7)[1].uploads[0].width, undefined);
  t.local.uploadChanged("slow", { width: 640, height: 480 });
  assert.deepEqual([t.local.outbox("ws/st", 7)[1].uploads[0].width, t.local.outbox("ws/st", 7)[1].uploads[0].height], [640, 480]);
  t.core.close();
});

test("an_image_the_desktop_core_reads_from_its_page_has_its_size_read_too", async () => {
  const t = await queuedUpload();
  // The desktop's core has the page's file as a FileSource (file-port.ts), not a Blob.
  const head = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x05, 0xb4, 0, 0, 0, 0x66]);
  const blob = new FileSource(head.length, "image/png", async (start, end) => head.slice(start, end).buffer, () => {});
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [{ id: "strip", name: "strip.png", size: head.length, blob }] });
  await t.settle();
  const strip = v(t.values, 1).files.find((f: J) => f.id === "strip");
  assert.deepEqual([strip.width, strip.height], [1460, 102]);
  t.core.close();
});

test("a_message_sent_before_its_file_is_up_says_how_far_the_file_has_gone", async () => {
  const t = await setup();
  const PART = 4 * 1024 * 1024;
  const parts = [Deferred.makeUnsafe<J, CoreError>(), Deferred.makeUnsafe<J, CoreError>(), Deferred.makeUnsafe<J, CoreError>()];
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J) => Deferred.await(parts[q.offset / PART]!);
  (t.core.inner.stations as J).post = () => Effect.succeed(1);
  await t.watch(1, "ws/st:k");
  const size = 2 * PART + 3;
  const file = (id: string) => ({ id, name: `${id}.bin`, size, blob: new Blob([new Uint8Array(size)]) });
  const sent = (n: number) => t.core.inner.views.local.outbox("ws/st", 7)[n].uploads[0].sent;
  const send = (id: number, f: { id: string; name: string }) => call(t.core, t.ui, id, "chat.send", { station: "ws/st", thread: 7, text: "", uploads: [{ id: f.id, name: f.name, size }] });
  // Sent before any of it is up: its row says so as each part goes.
  const a = file("a");
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [a] });
  send(501, a);
  await t.settle();
  assert.equal(sent(0), 0);
  Deferred.doneUnsafe(parts[0]!, Effect.succeed({ have: PART }));
  await t.settle();
  assert.equal(sent(0), PART);
  // Sent part way through (another file of the same parts): it starts from there.
  const b = file("b");
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [b] });
  await t.settle();
  Deferred.doneUnsafe(parts[1]!, Effect.succeed({ have: 2 * PART }));
  await t.settle();
  send(502, b);
  await t.settle();
  assert.deepEqual([sent(0), sent(1)], [2 * PART, 2 * PART]);
  Deferred.doneUnsafe(parts[2]!, Effect.succeed({ have: size, file: { name: "x.bin", size, path: "/u/x.bin" } }));
  await t.settle();
  t.core.close();
});

test("a_file_says_how_far_it_has_gone_as_a_part_goes_not_only_when_the_part_is_in", async () => {
  const t = await setup();
  const part = Deferred.makeUnsafe<J, CoreError>();
  let wrote: (n: number) => void = () => {};
  (t.core.inner.stations.requests as J).uploadPart = (_addr: unknown, _q: J, _bytes: Uint8Array, _ctx: unknown, w: (n: number) => void) => { wrote = w; return Deferred.await(part); };
  (t.core.inner.stations as J).post = () => Effect.succeed(1);
  await t.watch(1, "ws/st:k");
  // Under one part: nothing yet, said at once, then as it goes, a step (64 KB) at a time.
  const size = 1024 * 1024;
  const file = { id: "small", name: "small.bin", size, blob: new Blob([new Uint8Array(size)]) };
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [file] });
  await t.settle();
  const shown = () => v(t.values, 1).files.find((f: J) => f.id === "small").sent;
  assert.equal(shown(), 0);
  call(t.core, t.ui, 501, "chat.send", { station: "ws/st", thread: 7, text: "", uploads: [{ id: file.id, name: file.name, size }] });
  await t.settle();
  wrote(1000);
  wrote(300 * 1024);
  wrote(300 * 1024 + 1000);
  await t.settle();
  // The composer's file and the waiting message's, alike; what is under a step from what was said waits.
  assert.equal(t.core.inner.views.local.outbox("ws/st", 7)[0].uploads[0].sent, 300 * 1024);
  wrote(size);
  await t.settle();
  assert.equal(t.core.inner.views.local.outbox("ws/st", 7)[0].uploads[0].sent, size);
  Deferred.doneUnsafe(part, Effect.succeed({ have: size, file: { name: file.name, size, path: "/u/small.bin" } }));
  await t.settle();
  t.core.close();
});

test("later_messages_wait_behind_uploads_but_other_chats_are_free", async () => {
  const t = await queuedUpload();
  t.send(501);
  t.send(502, { text: "next", uploads: [] });
  t.send(503, { thread: 8, text: "other chat", uploads: [] });
  await t.settle();
  assert.deepEqual(t.posted.map((m) => m.text), ["other chat"]);
  t.finish();
  await t.settle();
  assert.deepEqual(t.posted.map((m) => m.text), ["other chat", "with file", "next"]);
  t.core.close();
});

test("failed_upload_keeps_the_message_and_retry_uploads_before_delivery", async () => {
  const t = await queuedUpload();
  t.send(501);
  await t.settle();
  Deferred.doneUnsafe(t.gate, Effect.fail(new CoreError("upload", "offline")));
  await t.settle();
  const failed = t.local.outbox("ws/st", 7)[0];
  assert.equal(failed.state, "failed");
  assert.equal(failed.error, "offline");
  assert.equal(t.posted.length, 0);
  const retry = Deferred.makeUnsafe<J, CoreError>();
  (t.core.inner.stations.requests as J).uploadPart = () => Deferred.await(retry);
  call(t.core, t.ui, 502, "chat.retry", { station: "ws/st", thread: 7, id: failed.id });
  await t.settle();
  assert.equal(t.posted.length, 0);
  Deferred.doneUnsafe(retry, Effect.succeed({ have: 3, file: t.saved }));
  await t.settle();
  assert.equal(t.posted.length, 1);
  assert.deepEqual(t.posted[0].attachments, [t.saved]);
  t.core.close();
});

test("a_message_the_station_refuses_as_it_is_fails_for_good_and_is_not_sent_again", async () => {
  const t = await setup();
  let posts = 0;
  // A file this station does not have (one that went up to another): refused as it is, again and again.
  (t.core.inner.stations as J).post = () => { posts++; return Effect.fail(new CoreError("http_400", "Attachment isn't in uploads", 400)); };
  call(t.core, t.ui, 501, "chat.send", { station: "ws/st", thread: 7, text: "look", attachments: [{ name: "shot.png", path: "/mini/uploads/shot.png", size: 3 }] });
  await t.settle();
  const failed = t.core.inner.views.local.outbox("ws/st", 7)[0];
  assert.deepEqual([failed.state, failed.final, posts], ["failed", true, 1]);
  call(t.core, t.ui, 502, "chat.retry", { station: "ws/st", thread: 7, id: failed.id });
  await t.settle();
  assert.equal(posts, 1);
  // Another failure (the station not reached) stays one to send again.
  (t.core.inner.stations as J).post = () => { posts++; return Effect.fail(new CoreError("unreachable", "offline")); };
  call(t.core, t.ui, 503, "chat.send", { station: "ws/st", thread: 8, text: "later" });
  await t.settle();
  const unsent = t.core.inner.views.local.outbox("ws/st", 8)[0];
  assert.deepEqual([unsent.state, unsent.final], ["failed", undefined]);
  call(t.core, t.ui, 504, "chat.retry", { station: "ws/st", thread: 8, id: unsent.id });
  await t.settle();
  assert.equal(posts, 3);
  t.core.close();
});

test("discarding_a_message_waiting_for_upload_never_sends_it", async () => {
  const t = await queuedUpload();
  t.send(501);
  await t.settle();
  call(t.core, t.ui, 502, "chat.discard", { station: "ws/st", thread: 7, id: t.local.outbox("ws/st", 7)[0].id });
  await t.settle();
  t.finish();
  await t.settle();
  assert.equal(t.posted.length, 0);
  assert.equal(t.local.outbox("ws/st", 7).length, 0);
  t.core.close();
});

test("missing_upload_sources_fail_visibly_instead_of_sending_without_attachments", async () => {
  const t = await queuedUpload();
  t.core.inner.composers.release(t.uploads); // source unavailable after a core restart
  t.send(501);
  await t.settle();
  assert.equal(t.posted.length, 0);
  const entry = t.local.outbox("ws/st", 7)[0];
  assert.equal(entry.state, "failed");
  assert.match(entry.error, /slow.txt/);
  assert.equal(entry.text, "with file");
  t.core.close();
});

test("a_new_chat_keeps_its_queued_upload_until_the_chat_and_file_are_ready", async () => {
  const t = await queuedUpload();
  stationReplies(t.host, (req) => req.method === "POST" && req.url.endsWith("/sessions") ? { key: "ember:new", thread: { id: 9 } } : undefined);
  const key = t.local.pendingNew("ws/st", { runtime: "claude" });
  t.send(501, { thread: undefined, session: key });
  await t.settle();
  assert.equal(t.posted.length, 0);
  // Start its creation after the message has joined the new chat's queue.
  t.core.inner.viewCalls.makeChat(key);
  await t.settle();
  assert.equal(t.posted.length, 0);
  assert.equal(t.local.outbox("ws/st", 9)[0].uploads[0].id, "slow");
  t.finish();
  await t.settle();
  assert.equal(t.posted[0].thread, 9);
  assert.deepEqual(t.posted[0].attachments, [t.saved]);
  t.core.close();
});


test("an_upload_finishing_between_the_click_and_take_still_resolves_the_submitted_file_id", async () => {
  const t = await queuedUpload();
  t.finish();
  await t.settle();
  await t.ask("take", { key: "ws/st:k" });
  t.send(501); // the page's last frame still had this file uploading
  await t.settle();
  assert.deepEqual(t.posted[0].attachments, [t.saved]);
  t.core.close();
});

test("a_message_waits_for_every_upload_and_keeps_already_uploaded_attachments", async () => {
  const t = await queuedUpload();
  const second = Deferred.makeUnsafe<J, CoreError>();
  (t.core.inner.stations.requests as J).uploadPart = () => Deferred.await(second);
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [{ id: "second", name: "second.txt", size: 1, blob: new Blob(["x"]) }] });
  const ready = { name: "ready.txt", path: "/u/ready.txt", size: 1 };
  t.send(501, { attachments: [ready], uploads: [...t.uploads, { id: "second", name: "second.txt", size: 1 }] });
  t.finish();
  await t.settle();
  assert.equal(t.posted.length, 0);
  const saved = { name: "second.txt", path: "/u/second.txt", size: 1 };
  Deferred.doneUnsafe(second, Effect.succeed({ have: 1, file: saved }));
  await t.settle();
  assert.deepEqual(t.posted[0].attachments, [ready, t.saved, saved]);
  t.core.close();
});

test("a_station_file_is_copied_among_its_uploads_not_sent_up_and_goes_with_the_message", async () => {
  const t = await setup();
  const asked: J[] = [];
  let parts = 0;
  (t.core.inner.stations.requests as J).uploadPart = () => { parts++; return Effect.fail(new CoreError("upload", "not this way")); };
  (t.core.inner.stations.requests as J).driveStage = (_addr: unknown, root: string, path: string) => {
    asked.push([root, path]);
    return path === "gone.txt" ? Effect.fail(new CoreError("http_404", "文件或文件夹不存在", 404)) : Effect.succeed({ name: "cut.mp4", path: "/data/uploads/2026-cut.mp4", size: 3 });
  };
  await t.watch(1, "ws/st:k");
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [{ id: "d1", name: "cut.mp4", size: 3, drive: { root: "/Users/me", path: "Movies/cut.mp4" } }] });
  assert.deepEqual(asked, [["/Users/me", "Movies/cut.mp4"]]);
  assert.equal(parts, 0);
  assert.deepEqual([v(t.values, 1).files[0].done.path, v(t.values, 1).uploading, v(t.values, 1).ready], ["/data/uploads/2026-cut.mp4", false, true]);
  // What is sent takes it as an upload's.
  assert.equal((await Effect.runPromise(t.core.inner.composers.uploaded("ws/st", [{ id: "d1", name: "cut.mp4" }])))[0].path, "/data/uploads/2026-cut.mp4");
  // One the station cannot copy says why, in its place.
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [{ id: "d2", name: "gone.txt", size: 1, drive: { root: "/Users/me", path: "gone.txt" } }] });
  assert.equal(v(t.values, 1).files[1].error, "文件或文件夹不存在");
  t.core.close();
});

test("a_file_dragged_in_is_named_by_its_path_until_switched_to_a_file_which_then_goes_up_from_where_it_is", async () => {
  const t = await setup();
  const staged: J[] = [];
  const read: J[] = [];
  const parts: J[] = [];
  const requests = t.core.inner.stations.requests as J;
  requests.driveStage = (_addr: unknown, root: string, path: string, _ctx: unknown, zip = false) => {
    staged.push(zip ? [root, path, "zip"] : [root, path]);
    return Effect.succeed(zip ? { name: "proj.zip", path: "/data/uploads/proj.zip", size: 9 } : { name: "a.mp4", path: "/data/uploads/a.mp4", size: 3 });
  };
  requests.driveRead = (addr: J, root: string, path: string, offset: number, length: number) => {
    read.push([String(addr), root, path, offset, length]);
    return Effect.succeed({ type: "", total: 3, mtime: null, bytes: new Uint8Array([7, 8, 9]).subarray(offset, offset + length) });
  };
  requests.uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => { parts.push([...bytes]); return Effect.succeed({ have: q.size, file: { name: q.name, path: "/data/uploads/b.mp4", size: q.size } }); };
  await t.watch(1, "ws/st:k");
  const ref = (station: string, path: string, dir = false) => ({ station, stationName: station === "ws/st" ? "Studio" : "Mini", path, dir, mode: "path" });
  await t.ask("text", { key: "ws/st:k", text: "看看这个" });
  await t.ask("add", { key: "ws/st:k", station: "ws/st", files: [
    { id: "a", name: "a.mp4", size: 3, ref: ref("ws/st", "/Users/me/a.mp4"), drive: { station: "ws/st", root: "/Users/me", path: "a.mp4" } },
    { id: "b", name: "b.mp4", size: 3, ref: ref("ws/mini", "/Users/me/b.mp4"), drive: { station: "ws/mini", root: "/Users/me", path: "b.mp4" } },
    { id: "c", name: "src", size: 0, ref: ref("ws/st", "/Users/me/src", true) },
    { id: "d", name: "proj", size: 0, ref: ref("ws/st", "/Users/me/proj", true), drive: { station: "ws/st", root: "/Users/me", path: "proj" } },
  ] });
  // Named by their paths: nothing goes up, and it can be sent.
  assert.deepEqual([staged, read, parts], [[], [], []]);
  assert.deepEqual(v(t.values, 1).files.map((f: J) => [f.id, f.ref.mode, f.done ?? null]), [["a", "path", null], ["b", "path", null], ["c", "path", null], ["d", "path", null]]);
  assert.deepEqual([v(t.values, 1).uploading, v(t.values, 1).ready], [false, true]);
  // Switched to files: the chat's station copies its own; another's is read from there and sent up. A folder stays a path.
  await t.ask("mode", { key: "ws/st:k", id: "a", mode: "file" });
  await t.ask("mode", { key: "ws/st:k", id: "b", mode: "file" });
  await t.ask("mode", { key: "ws/st:k", id: "c", mode: "file" });
  // A folder of the chat's own station goes zipped.
  await t.ask("mode", { key: "ws/st:k", id: "d", mode: "file" });
  assert.deepEqual(staged, [["/Users/me", "a.mp4"], ["/Users/me", "proj", "zip"]]);
  assert.deepEqual(read.map((r) => r.slice(0, 4)), [["ws/mini", "/Users/me", "b.mp4", 0]]);
  assert.deepEqual(parts, [[7, 8, 9]]);
  assert.deepEqual(v(t.values, 1).files.map((f: J) => [f.id, f.ref.mode, f.done?.path ?? null]), [["a", "file", "/data/uploads/a.mp4"], ["b", "file", "/data/uploads/b.mp4"], ["c", "path", null], ["d", "file", "/data/uploads/proj.zip"]]);
  // Back to a path: taken as words after what is written; the files as attachments.
  await t.ask("mode", { key: "ws/st:k", id: "b", mode: "path" });
  const taken = t.core.inner.composers.take("ws/st:k");
  assert.equal(taken.text, "看看这个\nMini 上的文件：/Users/me/b.mp4\nStudio 上的文件夹：/Users/me/src");
  assert.deepEqual([taken.attachments.map((f: J) => f.path), taken.files], [["/data/uploads/a.mp4", "/data/uploads/proj.zip"], ["a", "d"]]);
  t.core.close();
});

// The app ended while a message's file went up (Android's system ends it in the background): the file's bytes were kept
// on the device as they went, so the message goes on from them as the app starts again, not failed for a source the
// new core never had.
test("a_message_whose_file_was_going_up_as_the_app_ended_is_sent_from_the_bytes_kept_as_it_went", async () => {
  const t = await queuedUpload();
  t.send(501);
  await t.settle();
  assert.equal(t.tries(), 1);
  assert.equal(t.posted.length, 0);
  await t.host.time.pass(SOON_MS + 50);
  await t.host.settle();
  await Effect.runPromise(t.core.inner.data.written);
  t.core.close();
  t.host.takeEmitted();
  const again = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  try {
    const went: string[] = [];
    (again.inner.stations.requests as J).uploadPart = (_addr: unknown, q: J, bytes: Uint8Array) => {
      // (asked by its hash first whether the station has it: not)
      if (q.sha256 !== undefined) return Effect.succeed({ have: 0 });
      went.push(new TextDecoder().decode(bytes));
      return Effect.succeed({ have: bytes.length, file: { name: q.name, size: bytes.length, path: "/u/again.txt" } });
    };
    const posted: J[] = [];
    (again.inner.stations as J).post = (_station: string, thread: number, message: J) => Effect.sync(() => { posted.push({ thread, ...message }); return posted.length; });
    const ui = again.connect();
    const entry = again.inner.views.local.outbox("ws/st", 7)[0];
    assert.equal(entry.text, "with file");
    call(again, ui, 601, "chat.retry", { station: "ws/st", thread: 7, id: entry.id });
    await t.host.settle();
    await t.host.time.pass(60);
    await t.host.settle();
    assert.deepEqual(went, ["abc"]);
    assert.equal(posted.length, 1);
    assert.deepEqual(posted[0].attachments, [{ name: "slow.txt", size: 3, path: "/u/again.txt" }]);
    // sent: nothing of it kept any more
    assert.equal(await Effect.runPromise(again.inner.driveKept.uploadNoted("slow")), null);
    assert.equal(await Effect.runPromise(again.inner.driveKept.has("outbox\nslow")), false);
  } finally { again.close(); }
});

// Its file was up before the app ended, its message not yet sent: what its station said of the file is kept, and the
// message is sent with it, the file not sent again.
test("a_message_whose_file_was_up_as_the_app_ended_is_sent_without_sending_the_file_again", async () => {
  const t = await queuedUpload();
  (t.core.inner.stations as J).post = () => Effect.fail(new CoreError("mesh", "down"));
  t.send(501);
  t.finish();
  await t.settle();
  await t.host.time.pass(SOON_MS + 50);
  await t.host.settle();
  await Effect.runPromise(t.core.inner.data.written);
  // (the file's bytes let go once it was up)
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has("outbox\nslow")), false);
  t.core.close();
  t.host.takeEmitted();
  const again = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  try {
    let tries = 0;
    (again.inner.stations.requests as J).uploadPart = () => { tries++; return Effect.fail(new CoreError("upload", "not again")); };
    const posted: J[] = [];
    (again.inner.stations as J).post = (_station: string, thread: number, message: J) => Effect.sync(() => { posted.push({ thread, ...message }); return posted.length; });
    const ui = again.connect();
    const entry = again.inner.views.local.outbox("ws/st", 7)[0];
    call(again, ui, 601, "chat.retry", { station: "ws/st", thread: 7, id: entry.id });
    await t.host.settle();
    await t.host.time.pass(60);
    await t.host.settle();
    assert.equal(tries, 0);
    assert.equal(posted.length, 1);
    assert.deepEqual(posted[0].attachments, [t.saved]);
  } finally { again.close(); }
});

test("discarding_a_message_lets_go_of_its_files_kept_bytes", async () => {
  const t = await queuedUpload();
  t.send(501);
  await t.settle();
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has("outbox\nslow")), true);
  call(t.core, t.ui, 502, "chat.discard", { station: "ws/st", thread: 7, id: t.local.outbox("ws/st", 7)[0].id });
  await t.settle();
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.uploadNoted("slow")), null);
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has("outbox\nslow")), false);
  t.core.close();
});
