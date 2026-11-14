// What a web link in a message is (the `linkPreview` topic): read each time its card shows, what was read last shown
// meanwhile, the app opened again too; a pull request's last change in words. Its pictures (a page's icon and picture, a
// pull request's author's face, a picture file's) go out as tokens, their bytes beside a call's answer
// (peek-pictures.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply, call, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, started, status } from "./station-fixture.ts";

const S = "ws/st";
const URL = "https://github.com/acme/app/pull/12";
const ASKED = `GET /link-preview?url=${encodeURIComponent(URL)}`;
const pr = (state: string, updatedAt: number) => ({
  kind: "github_pull_request", url: URL, repository: "acme/app", number: 12, title: "列表按天分组", state,
  author: { login: "lin" }, additions: 120, deletions: 8, changedFiles: 4, updatedAt, checks: { passed: 9, failed: 0, pending: 1 },
});

test("a_link_is_read_as_its_card_shows_and_shows_as_last_read_after_a_restart", async () => {
  const said: Record<string, unknown> = { ...base(), [ASKED]: pr("open", 1) };
  const first = await started(said);
  const reads = () => first.host.requests.flatMap(readsOf).filter((u) => u.includes("/admin/api/link-preview?")).length;
  assert.equal(reads(), 0, "not read until a card shows it");
  const ui = first.core.connect();
  const values = new Map<number, unknown>();
  const topic = { topic: "linkPreview", station: S, url: URL };
  subscribe(first.core, ui, 1, topic);
  await first.host.time.pass(500, 10);
  apply(first.host, values);
  assert.equal(reads(), 1);
  assert.equal(v(values, 1).state, "open");
  assert.equal(v(values, 1).repository, "acme/app");
  assert.equal(typeof v(values, 1).time.updatedAt.ago, "string", "its last change in words");
  // Shown again: read again (its state moves), the card showing what it is now.
  said[ASKED] = pr("merged", 2);
  first.core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  subscribe(first.core, ui, 3, topic);
  await first.host.time.pass(500, 10);
  apply(first.host, values);
  assert.equal(reads(), 2);
  assert.equal(v(values, 3).state, "merged");
  await first.host.time.pass(60_000, 1_000);
  await run(first.core.inner.data.written);
  first.core.close();
  // Opened again, nothing answering yet: as it was read last.
  const host = first.host;
  host.onFetch(() => new Promise(() => {}));
  host.onFetchStream(() => Effect.never);
  host.takeEmitted();
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui2 = core.connect();
  const again = new Map<number, unknown>();
  subscribe(core, ui2, 1, topic);
  await host.time.pass(300, 10);
  apply(host, again);
  assert.equal(v(again, 1).state, "merged");
  core.close();
});

test("a_file_a_message_names_is_read_under_its_session_as_its_card_shows_and_kept", async () => {
  const PEEK = `GET /sessions/s-1/peek?path=${encodeURIComponent("src/a.ts")}&line=12`;
  const peek = (text: string) => ({ path: "/w/src/a.ts", name: "a.ts", size: 120, mtime: 1, type: "text/plain", kind: "text", lines: { start: 9, text: [text], at: 12 } });
  const said: Record<string, unknown> = { ...base(), [PEEK]: peek("const a = 1;") };
  const { core, host } = await started(said);
  const reads = () => host.requests.flatMap(readsOf).filter((u) => u.includes("/admin/api/sessions/s-1/peek?")).length;
  const ui = core.connect();
  const values = new Map<number, unknown>();
  const topic = { topic: "filePeek", station: S, key: "s-1", path: "src/a.ts", line: 12 };
  subscribe(core, ui, 1, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(reads(), 1);
  assert.deepEqual(v(values, 1).lines.text, ["const a = 1;"]);
  assert.equal(typeof v(values, 1).time.mtime.ago, "string", "when it was written, in words");
  // Shown again: read again (it was written meanwhile).
  said[PEEK] = peek("const a = 2;");
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  subscribe(core, ui, 2, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(reads(), 2);
  assert.deepEqual(v(values, 2).lines.text, ["const a = 2;"]);
  core.close();
});

test("a_file_peek_stops_showing_a_kept_file_when_it_is_removed_and_recovers_when_it_returns", async () => {
  const PEEK = `GET /sessions/s-1/peek?path=${encodeURIComponent("src/a.ts")}`;
  const file = { path: "/w/src/a.ts", name: "a.ts", size: 1, mtime: 1, type: "text/plain", kind: "text" };
  const said: Record<string, unknown> = { ...base(), [PEEK]: file };
  const { core, host } = await started(said);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  const topic = { topic: "filePeek", station: S, key: "s-1", path: "src/a.ts" };
  subscribe(core, ui, 1, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(v(values, 1).name, "a.ts");

  said[PEEK] = status(404, { error: "not found" });
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  subscribe(core, ui, 2, topic);
  await host.time.pass(500, 10);
  const removed = host.takeEmitted().map(([, m]) => m as Record<string, unknown>).filter((m) => m.id === 2);
  assert.ok(removed.some((m) => "error" in m), JSON.stringify(removed));

  said[PEEK] = { ...file, size: 2 };
  core.receive(ui, { kind: "unsubscribe", id: 2, unsubscribe: true });
  subscribe(core, ui, 3, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(v(values, 3).size, 2);
  core.close();
});

test("a_message_a_link_names_is_read_alone_as_its_card_shows_and_kept", async () => {
  const ASK = "GET /threads/7/entries?from=2&to=2";
  const entry = (text: string) => ({ last: 9, entries: [{ thread: 7, n: 2, kind: "message", authorKind: "agent", author: "s-1", authorName: "Claude", text, at: 1_000 }] });
  const said: Record<string, unknown> = { ...base(), [ASK]: entry("**列表**按天分组\n做好了"), "GET /threads/7/entries?from=3&to=3": { last: 9, entries: [] } };
  const { core, host } = await started(said);
  const reads = () => host.requests.flatMap(readsOf).filter((u) => u.includes("/admin/api/threads/7/entries?from=2&to=2")).length;
  const ui = core.connect();
  const values = new Map<number, unknown>();
  const topic = { topic: "messagePeek", station: S, thread: 7, seq: 2 };
  subscribe(core, ui, 1, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(reads(), 1);
  assert.equal(v(values, 1).author, "Claude");
  assert.equal(v(values, 1).text, "列表按天分组 做好了", "its words as a chat's row has them");
  assert.equal(typeof v(values, 1).time.at.ago, "string", "when it was said, in words");
  // Shown again: read again.
  said[ASK] = entry("改过了");
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  subscribe(core, ui, 2, topic);
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(reads(), 2);
  assert.equal(v(values, 2).text, "改过了");
  // No such message: nothing, for the card to say so.
  subscribe(core, ui, 3, { ...topic, seq: 3 });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(values.get(3), null);
  core.close();
});

// deno-lint-ignore no-explicit-any
type J = any;
const PAGE = "https://example.com/bench";
const PAGE_ASKED = `GET /link-preview?url=${encodeURIComponent(PAGE)}`;
const bytesOf = (seed: number, n: number) => Uint8Array.from({ length: n }, (_, i) => (i * 31 + seed) & 255);
const dataUrl = (type: string, bytes: Uint8Array) => `data:${type};base64,${Buffer.from(bytes).toString("base64")}`;
const page = (title: string, icon: Uint8Array, image: Uint8Array) => ({ kind: "page", url: PAGE, title, site: "Example", icon: dataUrl("image/png", icon), image: dataUrl("image/jpeg", image) });

/// The answer to call `id` among what went out: its value or its error, and its bytes.
function answered(emitted: [number, unknown][], id: number): { ok?: J; error?: J; bytes?: Uint8Array } {
  const m = emitted.map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m));
  assert.ok(m !== undefined, `call ${id} answered`);
  return m;
}

test("a_link_cards_pictures_go_out_as_tokens_and_come_as_their_bytes_beside_a_call", async () => {
  const icon = bytesOf(1, 600);
  const image = bytesOf(2, 5000);
  const face = bytesOf(3, 300);
  const said: Record<string, unknown> = { ...base(), [PAGE_ASKED]: page("列表", icon, image), [ASKED]: { ...pr("open", 1), author: { login: "lin", avatar: dataUrl("image/png", face) } } };
  const { core, host } = await started(said);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  // Asked before its topic has read it: none, and nothing asked of the station for it.
  call(core, ui, 1, "link.preview.picture", { station: S, url: PAGE, which: "icon" });
  await host.settle();
  assert.equal(answered(host.takeEmitted(), 1).error?.code, "no_picture");
  assert.equal(host.requests.flatMap(readsOf).filter((u) => u.includes("/admin/api/link-preview?")).length, 0);
  subscribe(core, ui, 2, { topic: "linkPreview", station: S, url: PAGE });
  subscribe(core, ui, 3, { topic: "linkPreview", station: S, url: URL });
  await host.time.pass(500, 10);
  apply(host, values);
  const shown = v(values, 2);
  assert.equal(shown.title, "列表");
  assert.ok(typeof shown.icon === "string" && shown.icon !== "" && !shown.icon.startsWith("data:"), shown.icon);
  assert.ok(typeof shown.image === "string" && shown.image !== shown.icon && !shown.image.startsWith("data:"), shown.image);
  assert.ok(JSON.stringify(shown).length < 1000, "no picture in what goes out");
  const face1 = v(values, 3).author.avatar;
  assert.ok(typeof face1 === "string" && !face1.startsWith("data:"), face1);
  // Each picture's bytes, as the station sent them, beside its type; none asked of the station again.
  const reads = host.requests.length;
  call(core, ui, 4, "link.preview.picture", { station: S, url: PAGE, which: "icon" });
  call(core, ui, 5, "link.preview.picture", { station: S, url: PAGE, which: "image" });
  call(core, ui, 6, "link.preview.picture", { station: S, url: URL, which: "avatar" });
  call(core, ui, 7, "link.preview.picture", { station: S, url: URL, which: "image" });
  await host.settle();
  const out = host.takeEmitted();
  for (const [id, type, bytes] of [[4, "image/png", icon], [5, "image/jpeg", image], [6, "image/png", face]] as const) {
    const a = answered(out, id);
    assert.deepEqual(a.ok, { type });
    assert.deepEqual([...(a.bytes ?? [])], [...bytes], `call ${id}: the station's picture's bytes`);
  }
  // A picture it has none of: the error that says so.
  assert.equal(answered(out, 7).error?.code, "no_picture");
  assert.equal(host.requests.length, reads, "nothing asked of the station");
  // Read again with another title: the same tokens; with another icon: another icon's token, the same picture's.
  const again = async (was: number, id: number, value: unknown) => {
    said[PAGE_ASKED] = value;
    core.receive(ui, { kind: "unsubscribe", id: was, unsubscribe: true });
    subscribe(core, ui, id, { topic: "linkPreview", station: S, url: PAGE });
    await host.time.pass(500, 10);
    apply(host, values);
    return v(values, id);
  };
  const retitled = await again(2, 8, page("列表二", icon, image));
  assert.equal(retitled.title, "列表二");
  assert.deepEqual([retitled.icon, retitled.image], [shown.icon, shown.image]);
  const icon2 = bytesOf(9, 600);
  const changed = await again(8, 9, page("列表二", icon2, image));
  assert.notEqual(changed.icon, shown.icon);
  assert.equal(changed.image, shown.image);
  call(core, ui, 10, "link.preview.picture", { station: S, url: PAGE, which: "icon" });
  await host.settle();
  assert.deepEqual([...(answered(host.takeEmitted(), 10).bytes ?? [])], [...icon2]);
  // What the core's own readers read is the whole of it, as the station said it.
  assert.ok(String((core.inner.stations.link(S)?.memory.get(`linkPreview\n${PAGE}`) as J)?.icon).startsWith("data:image/png;base64,"));
  core.close();
});

test("a_file_peeks_picture_goes_out_as_a_token_and_comes_as_its_bytes_beside_a_call", async () => {
  const PEEK = `GET /sessions/s-1/peek?path=${encodeURIComponent("shot.png")}&line=3`;
  const TEXT = `GET /sessions/s-1/peek?path=${encodeURIComponent("src/a.ts")}`;
  const picture = bytesOf(4, 9000);
  const peek = (bytes: Uint8Array, size: number) => ({ path: "/w/shot.png", name: "shot.png", size, mtime: 1, type: "image/png", kind: "image", image: { type: "image/png", data: Buffer.from(bytes).toString("base64") } });
  const said: Record<string, unknown> = { ...base(), [PEEK]: peek(picture, 9000), [TEXT]: { path: "/w/src/a.ts", name: "a.ts", size: 1, mtime: 1, type: "text/plain", kind: "text" } };
  const { core, host } = await started(said);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  const topic = { topic: "filePeek", station: S, key: "s-1", path: "shot.png", line: 3 };
  call(core, ui, 1, "file.peek.picture", { station: S, key: "s-1", path: "shot.png", line: 3 });
  await host.settle();
  assert.equal(answered(host.takeEmitted(), 1).error?.code, "no_picture", "not read yet");
  subscribe(core, ui, 2, topic);
  subscribe(core, ui, 3, { topic: "filePeek", station: S, key: "s-1", path: "src/a.ts" });
  await host.time.pass(500, 10);
  apply(host, values);
  const shown = v(values, 2);
  assert.equal(shown.image.type, "image/png");
  assert.equal(shown.image.data, undefined, "no bytes in what goes out");
  assert.ok(typeof shown.image.picture === "string" && shown.image.picture !== "", shown.image.picture);
  const reads = host.requests.length;
  call(core, ui, 4, "file.peek.picture", { station: S, key: "s-1", path: "shot.png", line: 3 });
  call(core, ui, 5, "file.peek.picture", { station: S, key: "s-1", path: "src/a.ts" });
  call(core, ui, 6, "file.peek.picture", { station: S, key: "s-1", path: "shot.png" });
  await host.settle();
  const out = host.takeEmitted();
  assert.deepEqual(answered(out, 4).ok, { type: "image/png" });
  assert.deepEqual([...(answered(out, 4).bytes ?? [])], [...picture]);
  assert.equal(answered(out, 5).error?.code, "no_picture", "a text file has none");
  assert.equal(answered(out, 6).error?.code, "no_picture", "another line's peek is another topic's, not read");
  assert.equal(host.requests.length, reads, "nothing asked of the station");
  // The station's peek asked by its operation (a file's path pressed: the app reads its `kind`): as the topic gives it,
  // its picture by the same token, no bytes in it.
  call(core, ui, 20, "file.peek", { station: S, key: "s-1", path: "shot.png", line: 3 });
  await host.time.pass(500, 10);
  const op = answered(host.takeEmitted(), 20).ok;
  assert.equal(op.kind, "image");
  assert.equal(op.image.data, undefined, "no bytes in the operation's answer");
  assert.equal(op.image.picture, shown.image.picture, "the topic's token");
  assert.ok(JSON.stringify(op).length < 1000, `the operation's answer: ${JSON.stringify(op).length} B`);
  // Read again: written with the same picture, the same token; another picture, another.
  const again = async (was: number, id: number, value: unknown) => {
    said[PEEK] = value;
    core.receive(ui, { kind: "unsubscribe", id: was, unsubscribe: true });
    subscribe(core, ui, id, topic);
    await host.time.pass(500, 10);
    apply(host, values);
    return v(values, id);
  };
  const same = await again(2, 7, { ...peek(picture, 9000), mtime: 2 });
  assert.equal(same.image.picture, shown.image.picture);
  const other = await again(7, 8, peek(bytesOf(5, 9000), 9000));
  assert.notEqual(other.image.picture, shown.image.picture);
  core.close();
});
