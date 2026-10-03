// What the native addon does as the Rust station did (native/mesh/src/local.rs): the archive lock held across
// processes, and local links read with pulldown-cmark (raw HTML and indented code blocks are not links).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { loadMesh } from "../src/mesh/native.ts";
import { prepare } from "../src/sessions/local-links.ts";

test("an archive lock is held across processes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "lock-"));
  const path = join(dir, "archive.lock");
  const mesh = loadMesh();
  const mine = await mesh.fileLock(path);
  // Another process asks for it: it gets it only once this one lets go.
  const native = process.env.STILLFAIL_MESH_NATIVE ?? new URL("../native/mesh/target/release/libstillfail_mesh.dylib", import.meta.url).pathname;
  const child = spawn(process.execPath, ["-e", `const m={exports:{}};process.dlopen(m,${JSON.stringify(native)});m.exports.fileLock(${JSON.stringify(path)}).then(()=>{console.log("got");process.exit(0)})`], { stdio: ["ignore", "pipe", "inherit"] });
  let got = false;
  child.stdout.on("data", () => (got = true));
  await new Promise((r) => setTimeout(r, 400));
  assert.equal(got, false, "not while this process holds it");
  mine.release();
  await new Promise((r) => child.once("exit", r));
  assert.equal(got, true);
});

test("local links are read as pulldown-cmark reads them", () => {
  const dir = mkdtempSync(join(tmpdir(), "links-"));
  const file = join(dir, "report.pdf");
  writeFileSync(file, "x");
  const paths: string[] = [];
  const text = `See [the report](${file}).\n\n<a href="${file}">raw html</a>\n\n    [indented](${file})\n`;
  const out = prepare(text, paths, dir);
  assert.deepEqual(paths, [file]);
  assert.ok(out.startsWith("See [the report](report%2Epdf)."), out);
  // The raw HTML and the indented code block are left as they are.
  assert.ok(out.includes(`<a href="${file}">raw html</a>`) && out.includes(`    [indented](${file})`), out);
  assert.throws(() => prepare(`[x](${join(dir, "missing.pdf")})`, [], dir), /does not name a readable file/);
});
