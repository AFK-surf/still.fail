// The Rust core's changelog.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { item } from "../src/changelog.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();
const entry = (version: number, parts: string[]) => ({ version, commit: "c", at: 1_790_000_000, text: ["修复：一件事"], fixes: [], parts });

test("a_change_says_whether_this_app_has_it", () => {
  const released = { android: 1340, web: 1330, station: null, desktop: null };
  const had = item(entry(1320, ["android"]), "android", 1323, released);
  assert.deepEqual([had.has, had.note], [true, ""]);
  const update = item(entry(1335, ["android", "web"]), "android", 1323, released);
  assert.deepEqual([update.has, update.note], [false, "更新到 0.1.1335 后就有"]);
  assert.equal(item(entry(1345, ["android"]), "android", 1323, released).note, "还没发布");
  assert.equal(item(entry(1325, ["web"]), "web", 1323, released).note, "刷新页面后就有");
  // Another part's, in this app's tab and in its own: only what is not out is said.
  const station = item(entry(1320, ["station"]), "android", 1323, released);
  assert.deepEqual([station.has, station.note, station.mine], [null, "", false]);
  assert.deepEqual([item(entry(1320, ["station"]), "android", 1323, released, "station").note, item(entry(1320, ["station", "android"]), "web", 1, released, "android").note], ["还没发布", ""]);
  assert.equal(item(entry(1350, ["cloud"]), "web", 1, released).note, "");
  assert.equal(item(entry(1320, ["web"]), "desktop", 1323, released).has, true);
  assert.equal(item({ version: 1, text: [], parts: [] }, "web", null, released), null);
});

test("a_line_has_its_kind_apart", () => {
  const lines = item({ version: 1, text: ["修复：一件事", "新增: 一样东西", "优化：快了", "安卓：别的", "修复："], parts: ["web"] }, "web", 1, {}).lines;
  assert.deepEqual(lines, [
    { kind: "fix", label: "修复", text: "一件事" },
    { kind: "new", label: "新功能", text: "一样东西" },
    { kind: "improve", label: "改进", text: "快了" },
    { label: "", text: "安卓：别的" },
    { label: "", text: "修复：" },
  ]);
});
