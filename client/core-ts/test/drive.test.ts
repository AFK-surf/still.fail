// A station's drive in the core (docs/drive.md): a folder read as it is shown and kept on the device, said refused
// when the station refuses it, said why where it could not be read and nothing is held (the station down, no answer in
// time, failing), read again after a change of it and as its station is back; parts of a file written with what the
// station has.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply as applyDelta } from "../src/delta.ts";
import { Core } from "../src/core.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { kindOf, opensOf } from "../src/drive.ts";
import { wordsAnswer } from "../src/words.ts";
import { apply, answers, call, subscribe, v } from "./helpers.ts";
import { started, stationLater, stationReplies, status } from "./station-fixture.ts";
import { HostError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import { JSON_IDLE_MS } from "../src/station/requests.ts";
import { HostWire } from "../src/station/wire.ts";

const ST = "ws/st";
const ROOT = "/Users/a/Movies";
const DAY = 86_400_000;

const folder = (names: [string, boolean, number?][], mtime: number) => ({
  path: "",
  entries: names.map(([name, dir, size]) => ({ name, dir, size: size ?? 0, mtime, type: dir ? "" : "video/mp4" })),
  truncated: false,
});

test("a folder is read as it is shown, kept on the device, and shown with its kinds and words", async () => {
  const { host, core } = await started();
  const now = host.nowMs();
  let listed = folder([["Season 1", true], ["E2.mp4", false, 3 * 1024 * 1024], ["notes.md", false, 120]], now - 400 * DAY);
  stationReplies(host, (req) => (req.url.includes("/admin/api/drive/list?") ? listed : undefined));
  const lists = () => host.requests.filter((r) => r.url.includes("/admin/api/drive/list?")).length;
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "" });
  await host.settle();
  assert.equal(lists(), 1);
  assert.ok(host.requests.some((r) => r.url.endsWith(`/drive/list?root=${encodeURIComponent(ROOT)}&path=`)));
  const values = new Map();
  apply(host, values);
  const shown = v(values, 1);
  assert.deepEqual(shown.entries.map((e: any) => [e.name, e.kind, e.sizeText]), [["Season 1", "folder", ""], ["E2.mp4", "video", "3.0 MB"], ["notes.md", "markdown", "120 B"]]);
  // what a press on each does: entered, played, read
  assert.deepEqual(shown.entries.map((e: any) => e.opens), ["folder", "play", "read"]);
  assert.match(shown.entries[1].timeText, /^\d{4}\/\d{1,2}\/\d{1,2}$/);
  assert.equal(shown.countText, "1 个文件夹 · 2 个文件");
  // Shown again: what is held at once, and read again (the station says nothing of its disk).
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  // The station not answering now: what is held is shown.
  stationReplies(host, (req) => (req.url.includes("/admin/api/drive/list?") ? status(503, { error: "busy" }) : undefined));
  subscribe(core, ui, 2, { topic: "drive", station: ST, root: ROOT, path: "" });
  await host.settle();
  assert.equal(lists(), 2);
  apply(host, values);
  assert.equal(v(values, 2).entries.length, 3, "what was held");
  core.receive(ui, { kind: "unsubscribe", id: 2, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  listed = folder([["E2.mp4", false, 1]], now);
  stationReplies(host, (req) => (req.url.includes("/admin/api/drive/list?") ? listed : undefined));
  subscribe(core, ui, 3, { topic: "drive", station: ST, root: ROOT, path: "" });
  await host.settle();
  assert.equal(lists(), 3, "read again as it is shown again");
  apply(host, values);
  assert.deepEqual(v(values, 3).entries.map((e: any) => e.name), ["E2.mp4"]);
  core.close();
});

test("a folder the station refuses says why, though one was held", async () => {
  const { host, core } = await started();
  let gone = false;
  stationReplies(host, (req) =>
    req.url.includes("/admin/api/drive/list?") ? (gone ? status(404, { error: "文件或文件夹不存在", code: "not_found" }) : folder([["a.txt", false, 1]], 1)) : undefined,
  );
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "Season 1" });
  await host.settle();
  gone = true;
  call(core, ui, 2, "drive.refresh", { station: ST, root: ROOT, path: "Season 1" });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.ok(answers(emitted, 2)?.ok !== undefined);
  const error = emitted.map(([, m]) => m as any).filter((m) => m.id === 1 && "error" in m).at(-1);
  assert.equal(error?.error.message, "文件或文件夹不存在");
  core.close();
});

/// What a topic said last of why it shows nothing, if it did.
const said = (emitted: [unknown, unknown][], id: number): string | undefined =>
  emitted.map(([, m]) => m as any).filter((m) => m.id === id && ("error" in m || "value" in m)).at(-1)?.error?.message;

test("a folder its station does not answer, nothing of it held, says why rather than waiting on", async () => {
  const { host, core } = await started();
  // The station takes the read and never answers it: no answer in time.
  stationLater(host, (req) => (req.url.includes("/admin/api/drive/list?") ? new Promise(() => {}) : undefined));
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "Desktop" });
  await host.time.pass(JSON_IDLE_MS + 1000, 1000);
  assert.equal(said(host.takeEmitted(), 1), `${t("core-logic.mesh.timed_out")}（10月6日 09:01:00）`);
  // Failing: said too, and read again as it is shown again.
  stationLater(host, () => undefined);
  stationReplies(host, (req) => (req.url.includes("/admin/api/drive/list?") ? status(500, { error: "still.fail Helper did not start", code: "io" }) : undefined));
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  subscribe(core, ui, 2, { topic: "drive", station: ST, root: ROOT, path: "Desktop" });
  await host.settle();
  assert.equal(said(host.takeEmitted(), 2), "still.fail Helper did not start");
  stationReplies(host, (req) => (req.url.includes("/admin/api/drive/list?") ? folder([["a.txt", false, 1]], 1) : undefined));
  call(core, ui, 3, "drive.refresh", { station: ST, root: ROOT, path: "Desktop" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 2).entries.map((e: any) => e.name), ["a.txt"]);
  core.close();
});

test("a folder of a station that is down, nothing of it held, says so, and is read as the station is back", async () => {
  const s = await started();
  let down = true;
  stationLater(s.host, (req) => (down && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  s.gate.stream = "fail";
  s.end();
  await s.host.time.pass(60_000, 1000);
  assert.equal((s.core.inner.stations.link(ST)?.state as { state: string }).state, "offline");
  stationReplies(s.host, (req) => (req.url.includes("/admin/api/drive/list?") ? folder([["a.txt", false, 1]], 1) : undefined));
  const ui = s.core.connect();
  subscribe(s.core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "Desktop" });
  await s.host.time.pass(1000, 250);
  assert.equal(said(s.host.takeEmitted(), 1), t("core-views.station.unreachable", { name: "studio" }));
  // Back: the folder shown is read, not left to the next time it is shown.
  down = false;
  s.gate.stream = "open";
  const n = s.streams.length;
  for (let waited = 0; s.streams.length <= n && waited < 20 * 60_000; waited += 250) await s.host.time.pass(250, 250);
  await s.host.time.pass(2000, 250);
  const values = new Map();
  apply(s.host, values);
  assert.deepEqual(v(values, 1).entries.map((e: any) => e.name), ["a.txt"]);
  s.core.close();
});

test("a change of the drive reads again the folders it touched, before it answers", async () => {
  const { host, core } = await started();
  let made = false;
  stationReplies(host, (req) => {
    if (req.url.includes("/admin/api/drive/list?") && req.url.includes("path=Season%201")) return folder(made ? [["Extras", true]] : [], 1);
    if (req.url.includes("/admin/api/drive/list?")) return folder([["Season 1", true]], 1);
    if (req.method === "POST" && req.url.endsWith("/admin/api/drive/mkdir")) {
      made = true;
      return { name: "Extras", dir: true, size: 0, mtime: 1, type: "" };
    }
    return undefined;
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "Season 1" });
  await host.settle();
  call(core, ui, 2, "drive.mkdir", { station: ST, root: ROOT, path: "Season 1/Extras" });
  await host.settle();
  const mkdir = host.requests.find((r) => r.url.endsWith("/drive/mkdir"))!;
  assert.deepEqual(JSON.parse(new TextDecoder().decode(mkdir.body!)), { root: ROOT, path: "Season 1/Extras" });
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).entries.map((e: any) => e.name), ["Extras"]);
  // The root's own folder was not shown nor held: not read for it.
  assert.equal(host.requests.filter((r) => r.url.endsWith("&path=")).length, 0);
  core.close();
});

test("an upload's parts go with where they start; a gap answers with what the station has, the last reads its folder again", async () => {
  const { host, core } = await started();
  let have = 0;
  stationReplies(host, (req) => {
    if (req.url.includes("/admin/api/drive/list?")) return folder(have === 6 ? [["new.mp4", false, 6]] : [], 1);
    if (req.method !== "PUT" || !req.url.includes("/admin/api/drive/upload?")) return undefined;
    const q = new URL(req.url).searchParams;
    const offset = Number(q.get("offset"));
    if (offset > have) return status(409, { error: "上传中断，需重新上传", code: "upload_lost", have });
    have = offset + (req.body?.length ?? 0);
    return have === Number(q.get("total")) ? { have, entry: { name: "new.mp4", dir: false, size: have, mtime: 1, type: "video/mp4" } } : { have, entry: null };
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "drive", station: ST, root: ROOT, path: "" });
  await host.settle();
  const part = (id: number, offset: number, text: string) => call(core, ui, id, "drive.upload.part", { station: ST, root: ROOT, path: "new.mp4", id: "u1", offset, total: 6 }, new TextEncoder().encode(text));
  part(2, 0, "abc");
  await host.settle();
  part(3, 5, "f");
  await host.settle();
  part(4, 3, "def");
  await host.settle();
  const emitted = host.takeEmitted();
  assert.deepEqual(answers(emitted, 2)?.ok, { have: 3, entry: null });
  assert.deepEqual(answers(emitted, 3)?.ok, { have: 3, entry: null }, "a gap: where to go on from");
  assert.equal((answers(emitted, 4)?.ok as any).entry.name, "new.mp4");
  let listed: any;
  for (const [, m] of emitted as [number, any][]) {
    if (m.id !== 1) continue;
    if ("value" in m) listed = m.value;
    else if ("delta" in m) listed = applyDelta(listed, m.delta);
  }
  assert.deepEqual(listed.entries.map((e: any) => e.name), ["new.mp4"]);
  core.close();
});

test("kinds by name", () => {
  assert.deepEqual(["a.MKV", "b.flac", "c.md", "d.txt", "e.srt", "f.py", "g", "README", "h.pdf", "i.csv"].map(kindOf), ["video", "audio", "markdown", "text", "subtitle", "code", "other", "text", "pdf", "csv"]);
});

test("where a file was left is kept on the device, none before", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  const topic = { topic: "drivePlace", station: ST, root: ROOT, path: "book.txt" };
  subscribe(core, ui, 1, topic);
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1), null);
  const at = host.nowMs();
  call(core, ui, 2, "drive.place", { station: ST, root: ROOT, path: "book.txt", at: 1200, of: 50000 });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).at, v(values, 1).of, v(values, 1).changed], [1200, 50000, at]);
  core.close();
});

test("the reader's settings are the core's: whole, each in its bounds, one changed at a time", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).reader, { size: 20, line: 1.7, margin: 22, face: "sans", indent: true, paper: "follow" });
  call(core, ui, 2, "prefs.set", { reader: { size: 40, paper: "green" } });
  await host.settle();
  call(core, ui, 3, "prefs.set", { reader: { line: 1.93, paper: "nope" } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).reader, { size: 32, line: 1.9, margin: 22, face: "sans", indent: true, paper: "follow" });
  core.close();
});

test("changing the reader's paper does not make its default size a chosen size", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  call(core, ui, 2, "prefs.set", { reader: { paper: "green" } });
  await host.settle();
  apply(host, values);
  const kept = () => (core.inner.data.get({ topic: "prefs" }) as { reader: Record<string, unknown> }).reader;
  assert.deepEqual(kept(), { paper: "green" }, "the size still follows the default");
  assert.equal(v(values, 1).reader.paper, "green");
  call(core, ui, 3, "prefs.set", { reader: { size: 24 } });
  await host.settle();
  call(core, ui, 4, "prefs.set", { reader: { line: 1.9 } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(kept(), { paper: "green", size: 24, line: 1.9 });
  assert.equal(v(values, 1).reader.size, 24, "a size the reader chose stays chosen");
  core.close();
  host.takeEmitted();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui2 = again.connect();
  subscribe(again, ui2, 1, { topic: "prefs" });
  await host.settle();
  const reopened = new Map();
  apply(host, reopened);
  assert.deepEqual(v(reopened, 1).reader, { size: 24, line: 1.9, margin: 22, face: "sans", indent: true, paper: "green" });
  again.close();
});

test("what a press on an entry does, by its kind: entered, read, played, previewed, else saved", () => {
  const of = (name: string) => opensOf(kindOf(name));
  assert.deepEqual(["notes.txt", "README", "a.md", "film.mkv", "song.flac", "shot.png", "doc.pdf", "main.rs", "data.csv", "page.html", "a.srt", "archive.zip"].map(of),
    ["read", "read", "read", "play", "play", "preview", "preview", "preview", "preview", "preview", "preview", "save"]);
  assert.equal(opensOf("folder"), "folder");
});

test("a name typed for a file or folder: empty, a slash, . or .. said in words; anything else none", () => {
  const problem = (name: string) => (wordsAnswer("drive.check", name, name.length, "") as { problem: string | null }).problem;
  assert.equal(problem("  "), "名称不能为空");
  for (const bad of ["a/b", "a\\b", ".", ".."]) assert.equal(problem(bad), "名称不能包含 / 或 \\", bad);
  for (const fine of ["新建文件夹", ".hidden", "a.b.c", " 两头有空格 "]) assert.equal(problem(fine), null, fine);
});
