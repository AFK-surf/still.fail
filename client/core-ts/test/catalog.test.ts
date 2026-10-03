// The words' catalog (client/i18n/catalog/<lang>/<part>.json), as every reader of it needs it: each part in both
// languages, every key Chinese has English has too, with the same `{names}`, and the other way round; a key in the
// part its name starts with.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

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
