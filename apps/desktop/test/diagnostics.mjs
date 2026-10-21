// Run explicitly with Electron installed: node apps/desktop/test/diagnostics.mjs
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { build } from "esbuild";
import electron from "electron";

const dir = mkdtempSync(join(tmpdir(), "desktop-diagnostics-"));
const fixture = join(dir, "fixture.cjs");
const data = join(dir, "data");
const records = () => readFileSync(join(data, "diagnostics", "desktop.log"), "utf8").trim().split("\n").map(JSON.parse);
const marker = () => existsSync(join(data, "diagnostics", "running.json"));
const dumps = () => readdirSync(join(data, "diagnostics", "crashes"), { recursive: true }).filter((p) => String(p).endsWith(".dmp"));
async function run(mode) {
  const env = { ...process.env, DIAGNOSTICS_TEST_DIR: data, DIAGNOSTICS_TEST_MODE: mode };
  delete env.ELECTRON_RUN_AS_NODE;
  await new Promise((resolve, reject) => {
    const child = spawn(electron, [fixture], { env, windowsHide: true, stdio: "ignore" });
    const timer = setTimeout(() => { child.kill(); reject(new Error(`fixture timed out: ${mode}`)); }, 30_000);
    child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("exit", (code) => {
      clearTimeout(timer);
      if ((mode === "clean" || mode === "renderer-crash") && code !== 0) reject(new Error(`${mode} exited ${code}`));
      else resolve();
    });
  });
}
try {
  await build({ entryPoints: [join(import.meta.dirname, "diagnostics-app.ts")], outfile: fixture, bundle: true, platform: "node", format: "cjs", external: ["electron"] });
  await run("clean");
  assert.equal(marker(), false);
  assert.ok(records().some((r) => r.event === "quit" && r.code === 0));
  await run("abrupt");
  assert.equal(marker(), true);
  await run("clean");
  assert.ok(records().some((r) => r.event === "previous-run-incomplete"));
  await run("exception");
  assert.equal(marker(), true);
  assert.ok(records().some((r) => r.event === "main-exception" && r.error.message === "diagnostics fixture failure"));
  await run("renderer-crash");
  assert.ok(records().some((r) => r.event === "renderer-gone" && r.reason === "crashed"));
  await run("main-crash");
  assert.equal(marker(), true);
  for (let i = 0; i < 50 && dumps().length < 2; i++) await delay(100);
  assert.ok(dumps().length >= 2, "both renderer and main crashes produce local minidumps");
  console.log("PASS: normal quit, abrupt exit, restart marker, JS exception, renderer crash and main crash (local dumps, uploads disabled)");
} finally {
  rmSync(dir, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
}
