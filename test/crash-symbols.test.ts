import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { parseSymbols, symbolize } from "../scripts/crash-symbols.ts";

// scripts/crash-symbols.ts names a tombstone's libmbui.so frames from a release's symbols (`<address> <name>`, as
// llvm-nm prints them): the function a pc is in and how far into it; every other line as it was.
const SYMBOLS = `0000000000101000 mbui_main
0000000000101200 moonbit_drop_object
0000000000102000 $moonbit.view.Tree.frame
000000000010a000 w_weak_one
`;
const TOMBSTONE = `*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
Build fingerprint: 'google/husky/husky:15/AP4A/1:user/release-keys'
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0000000000000008
backtrace:
      #00 pc 0000000000101234  /data/app/~~a==/fail.still.android.beta-b==/lib/arm64/libmbui.so (BuildId: 0123abcd)
      #01 pc 0000000000102000  /data/app/~~a==/fail.still.android.beta-b==/base.apk!libmbui.so (offset 0x4000) (BuildId: 0123abcd)
      #02 pc 0000000000056789  /apex/com.android.runtime/lib64/bionic/libc.so (abort+164)
      #03 pc 0000000000100010  /data/app/~~a==/fail.still.android.beta-b==/lib/arm64/libmbui.so
`;

test("each libmbui.so frame gets its function and offset; other lines as they are", () => {
  const out = symbolize(TOMBSTONE, parseSymbols(SYMBOLS)).split("\n");
  const lines = TOMBSTONE.split("\n");
  assert.equal(out.length, lines.length);
  assert.equal(out[4], `${lines[4]} moonbit_drop_object+0x34`);
  assert.equal(out[5], `${lines[5]} $moonbit.view.Tree.frame+0x0`);
  // another library's frame, and one before the first function: as they were
  assert.equal(out[6], lines[6]);
  assert.equal(out[7], lines[7]);
  for (const i of [0, 1, 2, 3, 8]) assert.equal(out[i], lines[i]);
});

test("the command: a symbols file, plain or xz'd, and the tombstone from a file or stdin", (t) => {
  const tmp = mkdtempSync(join(tmpdir(), "crash-symbols-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const script = fileURLToPath(new URL("../scripts/crash-symbols.ts", import.meta.url));
  writeFileSync(join(tmp, "plain.syms"), SYMBOLS);
  writeFileSync(join(tmp, "tombstone.txt"), TOMBSTONE);
  const want = symbolize(TOMBSTONE, parseSymbols(SYMBOLS));
  let result = spawnSync(process.execPath, [script, join(tmp, "plain.syms"), join(tmp, "tombstone.txt")], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, want);
  const xz = spawnSync("xz", ["-k", join(tmp, "plain.syms")]);
  assert.equal(xz.status, 0, "xz makes the release's kind of file");
  result = spawnSync(process.execPath, [script, join(tmp, "plain.syms.xz")], { encoding: "utf8", input: TOMBSTONE });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, want);
});
