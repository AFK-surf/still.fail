// What is being written in a chat, kept by the core (composer.ts): words, quotes, files going up, taken to send and put
// back, carried on into the chat a new one made, and kept on the device as the chat's draft.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { Core } from "../src/core.ts";
import { dbName, SOON_MS } from "../src/data.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { CoreFiles, PageFiles } from "../src/hosts/file-port.ts";
import { CoreError } from "../src/error.ts";
import { stationReplies, started } from "./station-fixture.ts";
import { HostWire } from "../src/station/wire.ts";

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
  const draft = { text: "还没发", quotes: [{ author: "agent", text: "那段", comment: "为什么", role: "agent" }], files: [{ name: "a.png", path: "/u/a.png", size: 3 }] };
  try {
    subscribe(t.core, t.ui, 1, { topic: "draft", station: "ws/st", chat: pending });
    subscribe(t.core, t.ui, 2, { topic: "draft", station: "ws/st", chat: "ember:made" });
    await t.settle();
    call(t.core, t.ui, 901, "draft.put", { key: `ws/st:${pending}`, ...draft });
    await t.settle();
    assert.deepEqual(v(t.values, 1), draft);
    assert.deepEqual(v(t.values, 2), { text: "", quotes: [], files: [] });

    t.core.inner.views.local.pendingMade(pending, "ember:made", 9);
    await t.settle();
    for (const sub of [1, 2]) assert.deepEqual(v(t.values, sub), draft);
    const edited = { ...draft, text: "继续写" };
    call(t.core, t.ui, 902, "draft.put", { key: "ws/st:ember:made", ...edited });
    await t.settle();
    for (const sub of [1, 2]) assert.deepEqual(v(t.values, sub), edited);

    await t.ask("take", { key: "ws/st:ember:made" });
    for (const sub of [1, 2]) assert.deepEqual(v(t.values, sub), { text: "", quotes: [], files: [] });
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
  t.local.uploadSized("slow", { width: 640, height: 480 });
  assert.deepEqual([t.local.outbox("ws/st", 7)[1].uploads[0].width, t.local.outbox("ws/st", 7)[1].uploads[0].height], [640, 480]);
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
