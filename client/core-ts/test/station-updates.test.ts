// The workspace's stations whose newer release waits for a person (views/station-updates.ts): read of what is kept beside
// each overview (db/schema.ts overviewSoftwareOf), an owner's or admin's, of those that do not update themselves.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { link, overview, prefs, setup, ui, workspace } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const ws = (role: string): J => ({
  id: "ws",
  role,
  stations: [
    { id: "a", name: "alpha", last_seen: null, version: null },
    { id: "b", name: "beta", last_seen: null, version: null },
  ],
});
const own = (patch: J = {}): J => ({
  id: "station", name: "still.fail", installed: true, version: "0.1.100", latest: "0.1.120", newer: true, channel: "stable", auto: false,
  updatable: true, state: "idle", ...patch,
});
const overviewWith = (station: J | null): J => ({
  viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: 0, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [],
  slackApps: [], disk: null, logins: [],
  updates: [{ id: "claude", name: "Claude Code", installed: true, version: "1", latest: "2", newer: true, updatable: true, state: "idle" }, ...(station === null ? [] : [station])],
});
const asked = { topic: "stationUpdates", scope: "ws" } as const;

async function rig(role = "owner") {
  const t = setup({ all: true });
  const u = ui();
  t.set(workspace(), ws(role));
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/b"), { state: "online" });
  t.set(overview("ws/a"), overviewWith(own()));
  t.set(overview("ws/b"), overviewWith(own({ auto: true })));
  t.set(prefs(), {});
  t.subscribe(1, asked);
  await t.read(u, 1);
  assert.equal(u.error, undefined, JSON.stringify(u.error));
  return { t, u };
}

test("an owner is offered a station's newer release where it does not update itself, the one that does not", async () => {
  const { u } = await rig();
  assert.deepEqual(u.value.items.map((i: J) => [i.station, i.name, i.state, i.versionText, i.canUpdate]), [["ws/a", "alpha", "offered", "0.1.100 → 0.1.120", true]]);
  assert.equal(u.value.offered, 1);
  assert.equal(u.value.labelText, "1 台 station 有新版本");
});

test("an admin is offered it too; a member nothing, nobody else can update it", async () => {
  assert.equal((await rig("admin")).u.value.items.length, 1);
  assert.deepEqual((await rig("member")).u.value.items, []);
  assert.equal((await rig("member")).u.value.labelText, "");
});

test("one under way is shown how far, one that failed what it said; one updated is gone", async () => {
  const { t, u } = await rig();
  t.set(overview("ws/a"), overviewWith(own({ state: "updating", percent: 42.4, progress: "正在下载" })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items.map((i: J) => [i.state, i.percent, i.detail, i.canUpdate]), [["updating", 42, "正在下载", false]]);
  assert.equal(u.value.offered, 0);
  assert.equal(u.value.labelText, "1 台 station 正在更新");
  // (away as its update hands over: still shown)
  t.set(link("ws/a"), { state: "offline", cause: "updating" });
  await t.read(u, 1);
  assert.equal(u.value.items.length, 1);
  t.set(link("ws/a"), { state: "online" });
  t.set(overview("ws/a"), overviewWith(own({ state: "failed", message: "下载失败" })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items.map((i: J) => [i.state, i.detail, i.canUpdate]), [["failed", "下载失败", true]]);
  t.set(overview("ws/a"), overviewWith(own({ version: "0.1.120", newer: false })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
});

test("one away is not offered till it is back; one turned to update itself, or unable to be updated here, is none", async () => {
  const { t, u } = await rig();
  t.set(link("ws/a"), { state: "offline" });
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  assert.equal(u.value.items.length, 1);
  t.set(overview("ws/a"), overviewWith(own({ auto: true })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
  t.set(overview("ws/a"), overviewWith(own({ updatable: false })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
  // (a station from before 自动更新 says no `auto`: offered)
  const { auto: _auto, ...older } = own();
  t.set(overview("ws/a"), overviewWith(older));
  await t.read(u, 1);
  assert.equal(u.value.items.length, 1);
  t.set(overview("ws/a"), overviewWith(null));
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
});

test("a version let be on a chat's notice is not offered; the next one is", async () => {
  const { t, u } = await rig();
  t.set(prefs(), { stationUpdatesDismissed: { "ws/a": "stable:0.1.120" } });
  await t.read(u, 1);
  assert.deepEqual(u.value.items, []);
  t.set(overview("ws/a"), overviewWith(own({ latest: "0.1.130" })));
  await t.read(u, 1);
  assert.deepEqual(u.value.items.map((i: J) => i.versionText), ["0.1.100 → 0.1.130"]);
});
