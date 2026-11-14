// The base says its own words with nothing of still.fail's loaded (src/lang.ts and the two files beside it,
// lang.zh.json and lang.en.json; scripts/base.ts holds what the base imports and that these are every key it says):
// this file imports base files alone, so what is said here is what a program built on the base alone is said, of no
// program ("the server"), and what such a program gives in their place. still.fail's own are its catalog's, given
// over them by src/i18n.ts, which only the last test loads (an `import(…)`: scripts/base.ts `ALONE`): from then on
// every key the base says is the catalog's text, byte for byte, so nothing still.fail's programs say moved (they all
// load src/i18n.ts before a word is asked for: scripts/base.ts refuses a file that loads the base's words without it).
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";
import { CoreError, HostError, dateClockSeconds } from "../src/error.ts";
import { has, saidBy, setCurrent, t, tr, words, type Lang, type Words } from "../src/lang.ts";
import { endpointId } from "../src/mesh.ts";
import { GONE } from "../src/wake-words.ts";

const LANGS = ["zh", "en"] as const;
/// The base's own words, as they are written.
const own = (lang: Lang): Record<string, string> => JSON.parse(readFileSync(new URL(`../src/lang.${lang}.json`, import.meta.url), "utf8"));
/// still.fail's catalog, every part of a language: each key with its text and the part it is in.
function catalog(lang: Lang): Map<string, { text: unknown; part: string }> {
  const dir = new URL(`../../i18n/catalog/${lang}/`, import.meta.url);
  const all = new Map<string, { text: unknown; part: string }>();
  for (const part of readdirSync(dir).filter((f) => f.endsWith(".json")).sort()) {
    for (const [key, text] of Object.entries(JSON.parse(readFileSync(new URL(part, dir), "utf8")))) all.set(key, { text, part });
  }
  return all;
}
/// The `{names}` a text takes, each once, sorted.
const names = (text: string): string[] => [...new Set([...text.matchAll(/\{([A-Za-z0-9_]+)\}/g)].map((m) => m[1]!))].sort();

test("the mesh's words are said in Chinese and in English with the mesh alone loaded, of no program", () => {
  assert.equal(typeof endpointId, "function");
  assert.equal(tr("zh", "core-logic.mesh.no_answer"), "无法连接服务器：无响应");
  assert.equal(tr("en", "core-logic.mesh.no_answer"), "Can't reach the server: no response");
  assert.equal(tr("zh", "core-logic.mesh.closed_by_station", { reason: "bye" }), "服务器断开了连接：bye");
  assert.equal(tr("en", "core-logic.mesh.closed_by_station", { reason: "bye" }), "The server closed the connection: bye");
  assert.equal(tr("en", "core-logic.mesh.credential_refused_why", { reason: "no such member" }), "The server refused access: no such member");
  assert.equal(t("core-logic.mesh.timed_out"), "连接超时");
});

test("every word of the base's own is said as it is written, the same keys and names in both languages, and names nothing of still.fail's", () => {
  let n = 0;
  for (const lang of LANGS) {
    for (const [key, text] of Object.entries(own(lang))) {
      assert.equal(typeof text, "string", `${lang} ${key}`);
      assert.equal(has(lang, key), true, `${lang} ${key}`);
      assert.equal(tr(lang, key), text, `${lang} ${key}`);
      // Neither its name nor its things. One key is the base's for something only still.fail has (a station taken
      // out of its workspace, the reason a station closes a connection with: src/mesh.ts `closeMessage`): the base
      // says of it what it says of any reason it does not know, the reason as the peer sent it.
      const said = key === "core-logic.mesh.station_removed" ? text.replace("station_removed", "") : text;
      assert.doesNotMatch(said, /still\.?fail|station|workspace/i, `${lang} ${key}`);
      n += 1;
    }
  }
  assert.ok(n > 0, "the base's words were read empty");
  assert.deepEqual(Object.keys(own("en")).sort(), Object.keys(own("zh")).sort());
  for (const [key, text] of Object.entries(own("zh"))) assert.deepEqual(names(own("en")[key]!), names(text), key);
  assert.equal(tr("zh", "core-logic.mesh.station_removed"), tr("zh", "core-logic.mesh.closed_by_station", { reason: "station_removed" }));
  assert.equal(tr("en", "core-logic.mesh.station_removed"), tr("en", "core-logic.mesh.closed_by_station", { reason: "station_removed" }));
  // Nothing of still.fail's catalog is loaded: a key of the core's own parts is shown as the key.
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
  assert.equal(CoreError.refused(new HostError("not_in_front"), "secure").message, "应用在后台时无法验证身份：请切回后重试");
  setCurrent("en");
  try {
    assert.equal(CoreError.host(new HostError(GONE)).message, "Back in foreground; reconnecting");
    assert.equal(dateClockSeconds(Date.UTC(2026, 9, 27, 16, 40, 14), 480), "Oct 28, 00:40:14");
    assert.equal(CoreError.refused(new HostError("key_invalidated"), "secure").message, "This device's screen lock was turned off, so its key no longer works: set it up again on this device");
  } finally {
    setCurrent("zh");
  }
});

test("a program on the base gives its own words, any of the base's in its place, and how every word is said", () => {
  words({ zh: { "im.hello": "你好，{name}", "im.only_zh": "只有中文" }, en: { "im.hello": { one: "Hello, {name}", other: "Hello all, {name}" } } });
  assert.equal(tr("zh", "im.hello", { name: "左" }), "你好，左");
  assert.equal(tr("en", "im.hello", { name: "Zuo", n: 1 }), "Hello, Zuo");
  assert.equal(tr("en", "im.hello", { name: "Zuo", n: 2 }), "Hello all, Zuo");
  // A key a language lacks is said in Chinese; one neither has is shown as the key.
  assert.equal(tr("en", "im.only_zh"), "只有中文");
  assert.equal(tr("en", "im.none"), "im.none");
  // The base's own stay as they were where none is given for them.
  assert.equal(tr("zh", "core-logic.mesh.timed_out"), "连接超时");
  // One the program gives is said its way from then on, by the base's own files too (the mesh's refusal, an error's
  // words), in each language that gives it: the other keeps the base's.
  const key = "core-logic.mesh.credential_refused_why";
  words({ zh: {}, en: { [key]: "The IM server did not let you in: {reason}", "core-misc.host.failed": "The IM tripped" } });
  try {
    assert.equal(tr("en", key, { reason: "no such member" }), "The IM server did not let you in: no such member");
    assert.equal(tr("zh", key, { reason: "查无此人" }), "服务器拒绝了授权：查无此人");
    setCurrent("en");
    assert.equal(CoreError.plainly("mesh", new Error("boom")).message, "The IM tripped");
    setCurrent("zh");
    assert.equal(CoreError.plainly("mesh", new Error("boom")).message, "此设备上的操作失败");
    // (and given again, the last given is said)
    words({ zh: { [key]: "IM 服务器没让你进：{reason}" }, en: { [key]: "No entry: {reason}" } });
    assert.deepEqual([tr("zh", key, { reason: "x" }), tr("en", key, { reason: "x" })], ["IM 服务器没让你进：x", "No entry: x"]);
  } finally {
    setCurrent("zh");
    words({ zh: own("zh") as Words, en: own("en") as Words });
  }
  for (const lang of LANGS) for (const [k, text] of Object.entries(own(lang))) assert.equal(tr(lang, k), text, `${lang} ${k}`);
  saidBy((text) => text.replace("IM", "another"));
  try {
    words({ zh: {}, en: { "im.named": "Open IM and try again" } });
    assert.equal(tr("en", "im.named"), "Open another and try again");
  } finally {
    saidBy((text) => text);
  }
});

test("still.fail's catalog, given over them, is said for every key the base says, as it is written there", async () => {
  // Until now: the base's own, every one.
  for (const lang of LANGS) for (const [key, text] of Object.entries(own(lang))) assert.equal(tr(lang, key), text, `${lang} ${key}`);
  // What every program of still.fail's loads before it asks for a word.
  await import("../src/i18n.ts");
  const wrong: string[] = [];
  for (const lang of LANGS) {
    const all = catalog(lang);
    for (const [key, base] of Object.entries(own(lang))) {
      const written = all.get(key);
      if (written === undefined) wrong.push(`${lang} ${key}: not in still.fail's catalog, so still.fail would say the base's ${JSON.stringify(base)}`);
      else if (typeof written.text !== "string") wrong.push(`${lang} ${key}: not one text in ${written.part}`);
      else {
        if (tr(lang, key) !== written.text) wrong.push(`${lang} ${key}: said ${JSON.stringify(tr(lang, key))}, ${written.part} writes ${JSON.stringify(written.text)}`);
        if (names(written.text).join() !== names(base).join()) wrong.push(`${lang} ${key}: the base's takes {${names(base)}}, ${written.part}'s {${names(written.text)}}`);
      }
    }
  }
  assert.deepEqual(wrong, []);
  // And the two are told apart: of a key still.fail says its own way, what is said now is not the base's own. (Which
  // texts are the same in both is nobody's to count: a text of the catalog's changes there, client/i18n/catalog.)
  const apart = "core-logic.mesh.credential_refused";
  for (const lang of LANGS) {
    assert.notEqual(tr(lang, apart), own(lang)[apart], `${lang} ${apart}: still.fail's catalog now says it as the base's own words do (src/lang.${lang}.json), so this no longer tells the catalog given from the base alone: name here, as \`apart\`, another key the catalog says its own way (one that names a station), or take these lines out if none is left`);
  }
  // By the base's own files too, the names filled: the mesh's refusal, an error's words.
  const why = "core-logic.mesh.credential_refused_why";
  assert.equal(tr("en", why, { reason: "no such member" }), String(catalog("en").get(why)?.text).replace("{reason}", "no such member"));
  assert.equal(CoreError.refused(new HostError("not_in_front"), "secure").message, catalog("zh").get("core-misc.secure.notInFront")?.text);
  // And the rest of the catalog is there with them.
  assert.deepEqual([has("zh", "core-logic.mesh.lock_unconfirmed"), has("en", "station.core.connecting")], [true, true]);
});
