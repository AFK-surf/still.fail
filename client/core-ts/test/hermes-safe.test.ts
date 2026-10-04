// The core runs in Hermes on Android without the Java side Hermes's Intl and locale functions call into: one of them
// called there aborts the whole app (2026-10-05: localeCompare in the profiles view, opening Profile crashed it).
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { lowerCase, upperCase } from "../src/hosts/hermes-case.ts";

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

test("case is converted without Java: ASCII and Latin-1 letters, the rest as it is, the length kept", () => {
  const java = (s: string) => {
    if (!/^[\x00-\x7f]*$/.test(s)) throw new Error("Java");
    return s;
  };
  assert.equal(lowerCase("Login 页面 ÀÉ×", (s) => java(s).toLowerCase()), "login 页面 àé×");
  assert.equal(upperCase("读了 file.ts é÷", (s) => java(s).toUpperCase()), "读了 FILE.TS É÷");
  assert.equal(lowerCase("ABC", (s) => java(s).toLowerCase()), "abc");
  assert.equal(lowerCase("Ünïcode 😀", (s) => java(s)).length, "Ünïcode 😀".length);
});
