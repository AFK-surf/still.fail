// The agents' memory on a station (the `memory` topic): read each time a page shows it, what was read last shown
// meanwhile, the app opened again too; read again once a skill's sharing changes.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply, call, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, started } from "./station-fixture.ts";

const S = "ws/st";
const skill = { name: "deploy", description: "项目记忆：发布时", project: true, builtin: false, text: "---\nname: deploy\n---\n发布前先跑检查", files: [] };
const memory = (text: string) => ({ global: { path: "/m/MEMORY.md", text }, skills: [skill] });

test("the_memory_is_read_as_it_is_shown_and_shows_as_last_read_after_a_restart", async () => {
  const said = { ...base(), "GET /memory": memory("# 记忆\n## 合并\n- 绿了就合"), "POST /skills/deploy/share": { ok: true } };
  const first = await started(said);
  const reads = () => first.host.requests.flatMap(readsOf).filter((u) => u.endsWith("/admin/api/memory")).length;
  assert.equal(reads(), 0, "not read until a page shows it");
  const ui = first.core.connect();
  const values = new Map<number, unknown>();
  subscribe(first.core, ui, 1, { topic: "memory", station: S });
  await first.host.time.pass(500, 10);
  apply(first.host, values);
  assert.equal(reads(), 1);
  assert.deepEqual(v(values, 1).global.sections.map((s: { title: string }) => s.title), ["合并"]);
  assert.equal(v(values, 1).skills[0].group, "project");
  // A skill shared: read again, the page showing it as it is now.
  said["GET /memory"] = memory("# 记忆\n## 合并\n- 绿了就合\n## 部署\n- 先测");
  call(first.core, ui, 2, "skill.share", { station: S, name: "deploy", on: true });
  await first.host.time.pass(500, 10);
  apply(first.host, values);
  assert.equal(reads(), 2);
  assert.deepEqual(v(values, 1).global.sections.map((s: { title: string }) => s.title), ["合并", "部署"]);
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
  subscribe(core, ui2, 1, { topic: "memory", station: S });
  await host.time.pass(300, 10);
  apply(host, again);
  assert.deepEqual(v(again, 1).global.sections.map((s: { title: string }) => s.title), ["合并", "部署"]);
  core.close();
});

test("a_memory_never_read_says_why_once_its_station_cannot_be_asked", async () => {
  const { host, core } = await started({ ...base() });
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "memory", station: S });
  await host.time.pass(500, 10);
  const said = host.takeEmitted().map(([, m]) => m as Record<string, unknown>).filter((m) => m.id === 1);
  assert.ok(said.some((m) => "error" in m), JSON.stringify(said));
  assert.equal(values.size, 0);
  core.close();
});
