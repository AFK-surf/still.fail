// client/core/src/changelog.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { item } from "../src/changelog.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();
const entry = (version: number, parts: string[]) => ({ version, commit: "c", at: 1_790_000_000, text: ["修复：一件事"], fixes: [], parts });

test("a_change_says_whether_this_app_has_it", () => {
  const released = { android: 1340, web: 1330, station: null, desktop: null };
  const had = item(entry(1320, ["android"]), "android", 1323, released);
  assert.deepEqual([had.has, had.note, had.place], [true, "你的版本已包含", "安卓 app 0.1.1320"]);
  const update = item(entry(1335, ["android", "web"]), "android", 1323, released);
  assert.deepEqual([update.has, update.note], [false, "更新到 0.1.1335 后就有"]);
  assert.equal(item(entry(1345, ["android"]), "android", 1323, released).note, "还没发布");
  assert.equal(item(entry(1325, ["web"]), "web", 1323, released).note, "刷新页面后就有");
  const station = item(entry(1320, ["station"]), "android", 1323, released);
  assert.deepEqual([station.has, station.note, station.mine], [null, "还没发布", false]);
  const cloud = item(entry(1350, ["cloud"]), "web", 1, released);
  assert.deepEqual([cloud.note, cloud.place], ["已上线", ""]);
  assert.equal(item(entry(1320, ["web"]), "desktop", 1323, released).has, true);
  assert.equal(item({ version: 1, text: [], parts: [] }, "web", null, released), null);
});
