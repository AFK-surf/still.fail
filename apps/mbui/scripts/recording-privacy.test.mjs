import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { containsLocalInformation } from "./recording-privacy.mjs";

const config = { home: "/Users/example", work: "/Users/example/private-run", hostname: "example-machine" };
const line = (value) => JSON.stringify(value) + "\n";

test("a recording rejects raw and partially scrubbed local paths", () => {
  for (const note of [
    "/Users/example/file", "/Users/example/private-run/agent", "/test-home/private-run/agent", "example-machine",
  ]) {
    assert.equal(containsLocalInformation(line({ in: { note } }), config), true);
  }
  assert.equal(containsLocalInformation(line({ in: { note: "/test-e2e/agent" } }), config), false);
});

test("a recording rejects local information inside captured bytes", () => {
  const b = Buffer.from('{"path":"/test-home/private-run/agent"}').toString("hex");
  assert.equal(containsLocalInformation(line({ in: { b } }), config), true);
  assert.equal(containsLocalInformation(line({ in: { b: Buffer.from("ordinary bytes").toString("hex") } }), config), false);
});

test("a private checkout parent is rejected even in a sibling directory", () => {
  const options = { ...config, workspace: "/Users/example/private-session" };
  assert.equal(containsLocalInformation(line({ note: "/test-home/private-session/other/file" }), options), true);
  assert.equal(containsLocalInformation(line({ note: "/test-home/other/file" }), { ...options, workspace: options.home }), false);
});

test("private identifiers are rejected in text and bytes without being committed", () => {
  const options = { ...config, privateTerms: ["", "Private-Station", "  "] };
  assert.equal(containsLocalInformation(line({ note: "private-station is online" }), options), true);
  assert.equal(containsLocalInformation(line({ b: Buffer.from("PRIVATE-STATION").toString("hex") }), options), true);
  assert.equal(containsLocalInformation(line({ note: "a fictional station" }), options), false);
});

test("the recording check reads a private list and fails closed if it is unavailable", () => {
  const dir = mkdtempSync(join(tmpdir(), "recording-privacy-"));
  try {
    const terms = join(dir, "terms");
    const trace = join(dir, "trace");
    writeFileSync(terms, "Private-Station\n");
    writeFileSync(trace, line({ note: "private-station" }));
    const run = () => spawnSync(process.execPath, [fileURLToPath(new URL("./recording-privacy.mjs", import.meta.url)), trace], {
      env: { ...process.env, E2E_PRIVATE_TERMS_FILE: terms },
    });
    assert.equal(run().status, 1);
    writeFileSync(trace, line({ note: "fictional station" }));
    assert.equal(run().status, 0);
    rmSync(terms);
    assert.equal(run().status, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
