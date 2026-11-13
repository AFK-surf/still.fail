// The base says its own words with nothing of still.fail's loaded (src/lang.ts; scripts/base.ts holds what the base
// imports): this file imports base files alone, never src/i18n.ts, so the catalog here is the base's own parts, and
// what another program built on the base gives it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CoreError, HostError, dateClockSeconds } from "../src/error.ts";
import { has, saidBy, setCurrent, t, tr, words, type Lang } from "../src/lang.ts";
import { endpointId } from "../src/mesh.ts";
import { GONE } from "../src/wake-words.ts";

const PARTS = ["core-logic.format", "core-logic.mesh", "core-misc.call", "core-misc.error", "core-misc.host", "core-misc.secure", "core-misc.wake"];
const part = (lang: Lang, name: string): Record<string, string | { one?: string; other?: string }> => JSON.parse(readFileSync(new URL(`../../i18n/catalog/${lang}/${name}.json`, import.meta.url), "utf8"));

test("the mesh's words are said in Chinese and in English with the mesh alone loaded", () => {
  assert.equal(typeof endpointId, "function");
  assert.equal(tr("zh", "core-logic.mesh.no_answer"), "无法连接此 station：无响应");
  assert.equal(tr("en", "core-logic.mesh.no_answer"), "Can't reach this station: no response");
  assert.equal(tr("zh", "core-logic.mesh.closed_by_station", { reason: "bye" }), "station 断开了连接：bye");
  assert.equal(tr("en", "core-logic.mesh.closed_by_station", { reason: "bye" }), "Station closed the connection: bye");
  assert.equal(t("core-logic.mesh.timed_out"), "连接超时");
});

test("every word of the base's parts is said as it is written, and nothing of still.fail's catalog is here", () => {
  let n = 0;
  for (const lang of ["zh", "en"] as const) {
    for (const name of PARTS) {
      for (const [key, value] of Object.entries(part(lang, name))) {
        assert.equal(has(lang, key), true, `${lang} ${key}`);
        assert.equal(tr(lang, key), typeof value === "string" ? value : value.other, `${lang} ${key}`);
        n += 1;
      }
    }
  }
  assert.equal(n, 2 * 46);
  // The core's own parts are not loaded: a key of theirs is shown as the key.
  for (const key of ["core-logic.accounts.login.cancelled", "core-logic.mesh.lock_unconfirmed", "core-misc.host.crashed", "common.report.title", "station.core.connecting"]) {
    assert.deepEqual([has("zh", key), has("en", key), tr("en", key)], [false, false, key], key);
  }
});

test("an error says its words and its moment in either language", () => {
  assert.equal(CoreError.host(new HostError(GONE)).message, "页面回到前台，重新连接");
  assert.equal(CoreError.plainly("mesh", new Error("connection refused")).message, "网络连接失败");
  assert.equal(dateClockSeconds(Date.UTC(2026, 9, 27, 16, 40, 14), 480), "10月28日 00:40:14");
  const failed = CoreError.plainly("mesh", new Error("boom"));
  failed.stamped(Date.UTC(2026, 10, 2, 6, 46, 33), 480);
  assert.equal(failed.message, "此设备上的操作失败（11月2日 14:46:33）");
  setCurrent("en");
  try {
    assert.equal(CoreError.host(new HostError(GONE)).message, "Back in foreground; reconnecting");
    assert.equal(dateClockSeconds(Date.UTC(2026, 9, 27, 16, 40, 14), 480), "Oct 28, 00:40:14");
  } finally {
    setCurrent("zh");
  }
});

test("a program on the base gives its own words, and how every word is said", () => {
  words({ zh: { "im.hello": "你好，{name}", "im.only_zh": "只有中文" }, en: { "im.hello": { one: "Hello, {name}", other: "Hello all, {name}" } } });
  assert.equal(tr("zh", "im.hello", { name: "左" }), "你好，左");
  assert.equal(tr("en", "im.hello", { name: "Zuo", n: 1 }), "Hello, Zuo");
  assert.equal(tr("en", "im.hello", { name: "Zuo", n: 2 }), "Hello all, Zuo");
  // A key a language lacks is said in Chinese; one neither has is shown as the key.
  assert.equal(tr("en", "im.only_zh"), "只有中文");
  assert.equal(tr("en", "im.none"), "im.none");
  // The base's own stay as they were.
  assert.equal(tr("zh", "core-logic.mesh.timed_out"), "连接超时");
  saidBy((text) => text.replace("still.fail", "another"));
  try {
    assert.equal(tr("en", "core-misc.secure.notInFront"), "Couldn't verify it's you while another is in the background: open it and try again");
  } finally {
    saidBy((text) => text);
  }
});
