// The words' catalog (client/i18n/catalog/<lang>/<part>.json), as every reader of it needs it: each part in both
// languages, every key Chinese has English has too, with the same `{names}`, and the other way round; a key in the
// part its name starts with, and in that part alone (the base's words are parts of their own, named by more of their
// keys: core-misc.wake.json beside core-misc.json, src/lang.ts); and the core saying every key of the parts it
// carries as it is written, whichever part it is in.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";
import { has, tr } from "../src/i18n.ts";

const CATALOG = new URL("../../i18n/catalog/", import.meta.url);
type Value = string | Record<string, string>;
const part = (lang: string, file: string): Record<string, Value> => JSON.parse(readFileSync(new URL(`${lang}/${file}`, CATALOG), "utf8"));
const parts = (lang: string) => readdirSync(new URL(`${lang}/`, CATALOG)).filter((f) => f.endsWith(".json")).sort();

/// The `{names}` a value takes, each once, sorted.
function names(value: Value): string[] {
  const texts = typeof value === "string" ? [value] : Object.values(value).filter((v) => typeof v === "string");
  const found = texts.flatMap((s) => [...s.matchAll(/\{([A-Za-z0-9_]+)\}/g)].map((m) => m[1]!));
  return [...new Set(found)].sort();
}

test("the languages agree, key for key and name for name", () => {
  assert.deepEqual(parts("en"), parts("zh"));
  const wrong: string[] = [];
  for (const file of parts("zh")) {
    const zh = part("zh", file);
    const en = part("en", file);
    for (const [key, value] of Object.entries(zh)) {
      if (!(key in en)) wrong.push(`${key}: no English`);
      else if (names(en[key]!).join() !== names(value).join()) wrong.push(`${key}: ${names(value)} vs ${names(en[key]!)}`);
    }
    for (const key of Object.keys(en)) if (!(key in zh)) wrong.push(`${key}: no Chinese`);
  }
  assert.deepEqual(wrong.sort(), []);
});

test("a key is in the part its name starts with", () => {
  const wrong: string[] = [];
  for (const lang of ["zh", "en"]) {
    for (const file of parts(lang)) {
      const prefix = `${file.slice(0, -".json".length)}.`;
      for (const key of Object.keys(part(lang, file))) if (!key.startsWith(prefix)) wrong.push(`${lang}/${file}: ${key}`);
    }
  }
  assert.deepEqual(wrong, []);
});

test("a key is in one part alone", () => {
  // (the readers put the parts together, a later part's key over an earlier one's: the app's tables, the core)
  const wrong: string[] = [];
  for (const lang of ["zh", "en"]) {
    const where = new Map<string, string>();
    for (const file of parts(lang)) {
      for (const key of Object.keys(part(lang, file))) {
        if (where.has(key)) wrong.push(`${lang}: ${key} in ${where.get(key)} and ${file}`);
        where.set(key, file);
      }
    }
  }
  assert.deepEqual(wrong, []);
});

test("the core says every key of the parts it carries as it is written", () => {
  // (the login page's words are that page's alone: web/src/login/page.tsx)
  const carried = (lang: string) => parts(lang).filter((file) => file !== "web-login.json");
  const wrong: string[] = [];
  let n = 0;
  for (const lang of ["zh", "en"] as const) {
    for (const file of carried(lang)) {
      for (const [key, value] of Object.entries(part(lang, file))) {
        n += 1;
        const written = typeof value === "string" ? value : value.other;
        if (!has(lang, key)) wrong.push(`${lang}/${file}: ${key} is not the core's`);
        else if (tr(lang, key) !== written) wrong.push(`${lang}/${file}: ${key} is said ${JSON.stringify(tr(lang, key))}`);
        // (of one, its `{n}` filled: the other names stay as they are written)
        if (typeof value !== "string" && value.one !== undefined && tr(lang, key, { n: 1 }) !== value.one.replaceAll("{n}", "1")) wrong.push(`${lang}/${file}: ${key} of one is said ${JSON.stringify(tr(lang, key, { n: 1 }))}`);
      }
    }
  }
  assert.deepEqual(wrong, []);
  // Every part has words, the base's among them (13 of the core's, 7 of the base's).
  assert.equal(carried("zh").length, 20);
  assert.ok(n > 14_000, String(n));
});

test("a key is written once in its part", () => {
  // (JSON.parse keeps a key's last value: the screen's keys row heading, 常用键, put under the key the web's box of
  // keys sent to the screen was named by, 发给屏幕的按键, took its name from it, 2026-10-29, #2651)
  const wrong: string[] = [];
  for (const lang of ["zh", "en"]) {
    for (const file of parts(lang)) {
      const text = readFileSync(new URL(`${lang}/${file}`, CATALOG), "utf8");
      const seen = new Set<string>();
      for (const m of text.matchAll(/^ {2}"((?:[^"\\]|\\.)*)":/gm)) {
        if (seen.has(m[1]!)) wrong.push(`${lang}/${file}: ${m[1]}`);
        seen.add(m[1]!);
      }
      if (seen.size !== Object.keys(part(lang, file)).length) wrong.push(`${lang}/${file}: not one key a line, two spaces in`);
    }
  }
  assert.deepEqual(wrong, []);
});
