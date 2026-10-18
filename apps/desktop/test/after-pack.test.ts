// after-pack.cjs: each executable of the Mac app gets a Mach-O UUID of its own (TN3179; Electron's are the same in every
// Electron app of a version). Run on copies of the system's own: a universal one (/usr/bin/file) and a thin one (node).
// Run: node --test apps/desktop/test/after-pack.test.ts
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const { setUuid, uuidOf } = createRequire(import.meta.url)("../after-pack.cjs");
const mac = process.platform === "darwin";
const uuids = (file: string) => execFileSync("dwarfdump", ["--uuid", file], { encoding: "utf8" }).match(/UUID: [0-9A-F-]+ \([^)]+\)/g) ?? [];

test("a UUID is the same for a seed, another for another, in RFC 9562's name-based shape", () => {
  assert.deepEqual(uuidOf("fail.still.desktop.beta 0.1.3521 /Contents/MacOS/youdid.wtf"), uuidOf("fail.still.desktop.beta 0.1.3521 /Contents/MacOS/youdid.wtf"));
  assert.notDeepEqual(uuidOf("fail.still.desktop 0.1.3521 /Contents/MacOS/still.fail"), uuidOf("fail.still.desktop.beta 0.1.3521 /Contents/MacOS/youdid.wtf"));
  const u = uuidOf("x");
  assert.equal(u.length, 16);
  assert.equal(u[6]! >> 4, 5);
  assert.equal(u[8]! >> 6, 2);
});

for (const [kind, source] of [["universal", "/usr/bin/file"], ["thin", process.execPath]] as const) {
  test(`a ${kind} Mach-O's UUID is set in each slice`, { skip: !mac }, () => {
    const dir = mkdtempSync(join(tmpdir(), "after-pack-"));
    try {
      const file = join(dir, "exe");
      copyFileSync(source, file);
      chmodSync(file, 0o755);
      const before = uuids(file);
      const buf = readFileSync(file);
      const uuid = uuidOf(`test ${kind}`);
      assert.equal(setUuid(buf, uuid), before.length);
      writeFileSync(file, buf);
      const hex = uuid.toString("hex").toUpperCase().replace(/^(.{8})(.{4})(.{4})(.{4})/, "$1-$2-$3-$4-");
      const after = uuids(file);
      assert.equal(after.length, before.length);
      for (const line of after) assert.ok(line.startsWith(`UUID: ${hex} `), line);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
