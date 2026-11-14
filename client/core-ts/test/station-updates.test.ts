// Unified software and agent runtime updates across a workspace's stations (src/views/updates.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { Inner } from "../src/core.ts";
import { parseCall } from "../src/core/calls.ts";
import { handlers } from "../src/core/execute.ts";
import { CoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic } from "../src/protocol.ts";
import { install, stationUpdatesView } from "../src/views/updates.ts";

holdLanguage();

const A = "aa".repeat(32);
const B = "bb".repeat(32);
const C = "cc".repeat(32);

test("stationUpdatesView aggregates Station and runtimes across stations and produces per-station badges", () => {
  const now = 1_794_650_000_000;
  const view = stationUpdatesView(
    [
      {
        id: A,
        address: `ws/${A}`,
        name: "tokyo-mac-studio-0",
        online: true,
        version: "0.1.9110",
        updates: [
          {
            id: "station",
            name: "Station",
            installed: true,
            version: "0.1.9110",
            latest: "0.1.9111",
            newer: true,
            downgrade: false,
            channel: "beta",
            auto: true,
            updatable: true,
            state: "updating",
            percent: 62,
            progress: "等 2 个 agent 结束本轮",
            checkedAt: now - 30_000,
          },
          {
            id: "claude",
            name: "Claude Code",
            installed: true,
            version: "2.1.4",
            latest: "2.1.4",
            newer: false,
            downgrade: false,
            updatable: true,
            state: "idle",
          },
          {
            id: "codex",
            name: "Codex",
            installed: true,
            version: "0.165.0",
            latest: "0.169.0",
            newer: true,
            downgrade: false,
            updatable: true,
            repairable: true,
            note: "缺少执行组件 codex-code-mode-host",
            state: "idle",
          },
        ],
      },
      {
        id: B,
        address: `ws/${B}`,
        name: "Office-Host-2",
        online: true,
        version: "0.1.9088",
        updates: [
          {
            id: "station",
            name: "Station",
            installed: true,
            version: "0.1.9088",
            latest: "0.1.9111",
            newer: true,
            downgrade: false,
            channel: "beta",
            auto: true,
            updatable: true,
            state: "failed",
            message: "磁盘空间不足",
          },
          {
            id: "claude",
            name: "Claude Code",
            installed: true,
            version: "2.1.1",
            latest: "2.1.4",
            newer: true,
            downgrade: false,
            updatable: true,
            state: "idle",
          },
          {
            id: "hermes",
            name: "Hermes Agent",
            installed: true,
            version: "0.8.0",
            newer: false,
            downgrade: false,
            updatable: false,
            state: "idle",
          },
        ],
      },
      {
        id: C,
        address: `ws/${C}`,
        name: "Joined-Mac",
        online: true,
        joined: true,
        home: "个人",
        version: "0.1.9111",
        updates: [
          {
            id: "station",
            name: "Station",
            installed: true,
            version: "0.1.9111",
            latest: "0.1.9111",
            newer: false,
            downgrade: false,
            updatable: true,
            state: "idle",
          },
        ],
      },
    ],
    true,
    { now, offsetMin: 480 },
  );

  assert.ok(view !== null);
  assert.equal(view.canEdit, true);
  assert.equal(view.channel, "beta");
  assert.equal(view.auto, true);
  assert.match(view.checkedText, /上次检查/);

  const stationItem = view.items.find((i: { id: string }) => i.id === "station");
  assert.ok(stationItem);
  assert.equal(stationItem.state, "failed");
  assert.equal(stationItem.failedText, "1 台失败");
  assert.match(stationItem.versionText, /测试版最新 0\.1\.9111/);
  assert.match(stationItem.versionText, /tokyo-mac-studio-0 正在更新 62%（等 2 个 agent 结束本轮）/);
  assert.match(stationItem.versionText, /1 台来自「个人」/);
  assert.deepEqual(stationItem.notes, ["Office-Host-2（0.1.9088）：磁盘空间不足"]);

  const claudeItem = view.items.find((i: { id: string }) => i.id === "claude");
  assert.ok(claudeItem);
  assert.equal(claudeItem.state, "idle");
  assert.equal(claudeItem.newer, true);
  assert.equal(claudeItem.updatable, true);
  assert.equal(claudeItem.latest, "2.1.4");
  assert.match(claudeItem.versionText, /1 台已最新/);
  assert.match(claudeItem.versionText, /Office-Host-2 2\.1\.1/);

  const codexItem = view.items.find((i: { id: string }) => i.id === "codex");
  assert.ok(codexItem);
  assert.equal(codexItem.state, "failed");
  assert.equal(codexItem.repairable, true);
  assert.equal(codexItem.primaryButton, true);
  assert.equal(codexItem.failedText, "1 台需修复");
  assert.deepEqual(codexItem.notes, ["tokyo-mac-studio-0（0.165.0）：缺少执行组件 codex-code-mode-host"]);

  const hermesItem = view.items.find((i: { id: string }) => i.id === "hermes");
  assert.ok(hermesItem);
  assert.equal(hermesItem.noButton, true);
  assert.equal(hermesItem.statusText, "自行管理");

  assert.deepEqual(view.byStation[`ws/${A}`], { updateText: "Codex 需修复", updateBad: true });
  assert.deepEqual(view.byStation[`ws/${B}`], { updateText: "更新失败", updateBad: true });
});

test("stationUpdates topic and updates.* calls fan out to matching reachable own stations", async () => {
  assert.deepEqual(parseTopic({ topic: "stationUpdates", workspace: "ws" }), { topic: "stationUpdates", workspace: "ws" });

  const performed: { station: string; method: string; path: string; body: unknown }[] = [];
  const updatesByStation: Record<string, unknown[]> = {
    [`ws/${A}`]: [
      { id: "station", installed: true, newer: false, updatable: true, state: "idle" },
      { id: "codex", installed: true, newer: true, updatable: true, repairable: true, state: "idle" },
    ],
    [`ws/${B}`]: [
      { id: "station", installed: true, newer: true, updatable: true, state: "failed" },
      { id: "codex", installed: true, newer: false, updatable: true, state: "idle" },
    ],
  };

  const inner = {
    data: {
      shared: (topic: { workspace: string }) =>
        topic.workspace === "ws" ? { stations: [{ id: A }, { id: B }, { id: C, joined: true }] } : undefined,
      overviewUpdates: (address: string) => updatesByStation[address],
    },
    stations: {
      link: () => ({}),
      reachable: () => true,
      perform: (op: { target: { station: string }; method: string; path: string; body: unknown }) => {
        performed.push({ station: op.target.station, method: op.method, path: op.path, body: op.body });
        return Effect.succeed({ ok: true });
      },
    },
  } as unknown as Inner;

  install(inner);

  const runCall = (name: string, params: Record<string, unknown>) => {
    const parsed = parseCall(name, params);
    return Effect.runPromise(
      Effect.result(handlers.updates!(inner, parsed, (() => {}) as never, ["c", 1] as never, null as never) as Effect.Effect<unknown, CoreError>),
    );
  };

  performed.length = 0;
  const checked = await runCall("updates.check", { workspace: "ws" });
  assert.equal(checked._tag, "Success");
  assert.deepEqual(
    performed.map((p) => `${p.station} ${p.path}`),
    [`ws/${A} /updates/check`, `ws/${B} /updates/check`],
  );

  performed.length = 0;
  const retried = await runCall("updates.retry", { workspace: "ws", id: "station" });
  assert.equal(retried._tag, "Success");
  assert.deepEqual(performed, [{ station: `ws/${B}`, method: "POST", path: "/updates", body: { id: "station" } }]);

  performed.length = 0;
  const repaired = await runCall("updates.repair", { workspace: "ws", id: "codex" });
  assert.equal(repaired._tag, "Success");
  assert.deepEqual(performed, [{ station: `ws/${A}`, method: "POST", path: "/updates", body: { id: "codex", repair: true } }]);
});
