import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readlinkSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { linkAgentHome } from "../src/agent-home.ts";

test("profile homes link to the shared memory and skills under their runtime's names", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-agent-"));
  const agent = join(root, "agent");
  const profiles = [
    { id: "cc", runtime: "claude" as const, home: join(root, "cc"), env: {} },
    { id: "cx", runtime: "codex" as const, home: join(root, "cx"), env: {} },
  ];
  linkAgentHome(agent, profiles);
  linkAgentHome(agent, profiles); // idempotent
  assert.equal(readlinkSync(join(root, "cc", "CLAUDE.md")), join(agent, "MEMORY.md"));
  assert.equal(readlinkSync(join(root, "cc", "skills")), join(agent, "skills"));
  assert.equal(readlinkSync(join(root, "cx", "AGENTS.md")), join(agent, "MEMORY.md"));
  assert.equal(readlinkSync(join(root, "cx", "skills")), join(agent, "skills"));
});

test("a hand-written file in a profile home is left alone", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-agent-"));
  mkdirSync(join(root, "cc"));
  writeFileSync(join(root, "cc", "CLAUDE.md"), "mine");
  linkAgentHome(join(root, "agent"), [{ runtime: "claude", home: join(root, "cc") }]);
  assert.equal(readFileSync(join(root, "cc", "CLAUDE.md"), "utf8"), "mine");
});
