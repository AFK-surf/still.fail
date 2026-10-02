import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { readRelease, stable, type Entry } from "../scripts/changelog.ts";

const note = (version: number, lines = "- 新功能：一件事\n- 修复：另一件") => `---\nversion: ${version}\ndate: 2026-10-02\nparts: [web, android]\n---\n${lines}\n`;

test("a release's notes are one entry: its version, day, parts and lines", () => {
  const entry = readRelease(note(1400, "说明不算\n- 新功能：一件事\n  - 修复：另一件\n"));
  assert.deepEqual({ ...entry, at: undefined }, { version: 1400, commit: "", at: undefined, text: ["新功能：一件事", "修复：另一件"], fixes: [], parts: ["android", "web"] });
  assert.equal(new Date(entry.at * 1000).toISOString(), "2026-10-02T04:00:00.000Z");
  assert.throws(() => readRelease("- 没有头\n"), /front matter/);
  assert.throws(() => readRelease(note(1400).replace("web, android", "web, ios")), /parts/);
  assert.throws(() => readRelease(note(1400, "没有一行")), /no lines/);
});

test("the stable channel's entries, newest first, each with the fixes of the test channel's in between", () => {
  const root = mkdtempSync(join(tmpdir(), "stable-"));
  mkdirSync(join(root, "docs/releases"), { recursive: true });
  writeFileSync(join(root, "docs/releases/0.1.1300.md"), note(1300));
  writeFileSync(join(root, "docs/releases/0.1.1400.md"), note(1400));
  writeFileSync(join(root, "docs/releases/README.md"), "not a release");
  const beta = (version: number, fixes: number[]): Entry => ({ version, commit: "c", at: 0, text: ["x"], fixes, parts: ["web"] });
  const entries = stable(root, [beta(1410, [9]), beta(1350, [7, 8]), beta(1300, [5]), beta(1200, [3])]);
  assert.deepEqual(entries.map((e) => [e.version, e.fixes]), [[1400, [7, 8]], [1300, [3, 5]]]);
});
