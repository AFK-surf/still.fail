// The core runs in Hermes on Android without the Java side Hermes's Intl and locale functions call into: one of them
// called there aborts the whole app (2026-10-05: localeCompare in the profiles view, opening Profile crashed it).
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const SRC = new URL("../src/", import.meta.url).pathname;
const FORBIDDEN = /\.localeCompare\(|\.toLocale(?:Lower|Upper)?(?:Case|String|DateString|TimeString)\(|\bIntl\./;

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : name.endsWith(".ts") ? [path] : [];
  });
}

test("the core calls nothing Hermes on Android needs Java for (Intl, locale comparisons and formats)", () => {
  const found = files(SRC).flatMap((path) =>
    readFileSync(path, "utf8").split("\n").flatMap((line, i) => (FORBIDDEN.test(line) && !line.trim().startsWith("//") ? [`${path.slice(SRC.length)}:${i + 1}: ${line.trim()}`] : [])),
  );
  assert.deepEqual(found, []);
});
