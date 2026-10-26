// What a web link in a message is (the `linkPreview` topic): read each time its card shows, what was read last shown
// meanwhile, the app opened again too; a pull request's last change in words.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, started } from "./station-fixture.ts";

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
