import { strict as assert } from "node:assert";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { DiagnosticLog } from "../src/diagnostic-log.mts";

test("an unfinished run is recorded on restart; only successful quit clears it", () => {
  const dir = mkdtempSync(join(tmpdir(), "desktop-log-"));
  try {
    const first = new DiagnosticLog(dir);
    first.start({ version: "test" });
    first.finish(1);
    assert.ok(existsSync(first.marker));
    const second = new DiagnosticLog(dir);
    second.start({ version: "test2" });
    const rows = readFileSync(second.file, "utf8").trim().split("\n").map((s) => JSON.parse(s));
    assert.equal(rows.find((r) => r.event === "previous-run-incomplete").previous.version, "test");
    second.finish(0);
    assert.equal(existsSync(second.marker), false);
    const third = new DiagnosticLog(dir);
    third.start({ version: "test3" });
    assert.equal(readFileSync(third.file, "utf8").split("previous-run-incomplete").length, 2);
    third.finish(0);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("logs rotate, errors retain stacks, and storage failures do not throw", () => {
  const dir = mkdtempSync(join(tmpdir(), "desktop-log-"));
  try {
    const log = new DiagnosticLog(dir, 300);
    for (let i = 0; i < 8; i++) log.write("sample", { i, padding: "x".repeat(150) });
    assert.ok(existsSync(`${log.file}.2`));
    assert.equal(existsSync(`${log.file}.3`), false);
    log.write("exception", { error: new Error("test failure") });
    const row = JSON.parse(readFileSync(log.file, "utf8").trim());
    assert.equal(row.error.message, "test failure");
    assert.match(row.error.stack, /test failure/);
    const blocked = join(dir, "file-instead-of-directory");
    writeFileSync(blocked, "blocked");
    const unavailable = new DiagnosticLog(blocked);
    assert.doesNotThrow(() => { unavailable.start({}); unavailable.write("sample"); unavailable.finish(0); });
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
