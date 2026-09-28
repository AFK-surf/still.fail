import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// theme.css, app.css and mobile.css go in as `@layer legacy`, under the scoped *.css.ts styles (web/src/legacy.css).
// A stray `}` in one would end its layer early and put the rest over the scoped styles; outside a layer the browser
// takes it as the start of the next rule, and drops that rule.
for (const file of ["web/src/theme.css", "web/src/app.css", "web/src/mobile/mobile.css"]) {
  test(`${file}: every brace closes one it opened`, () => {
    const css = readFileSync(new URL(`../${file}`, import.meta.url), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, (comment) => comment.replace(/[^\n]/g, " "))
      .replace(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/g, (string) => " ".repeat(string.length));
    let depth = 0;
    css.split("\n").forEach((line, i) => {
      for (const ch of line) {
        if (ch === "{") depth++;
        else if (ch === "}") assert.ok(--depth >= 0, `${file}:${i + 1}: a "}" that closes nothing`);
      }
    });
    assert.equal(depth, 0, `${file} leaves ${depth} block(s) open`);
  });
}
