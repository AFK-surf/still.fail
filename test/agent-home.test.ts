import assert from "node:assert/strict";
import { lstatSync, mkdirSync, mkdtempSync, readlinkSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { linkAgentHome, linkTranscripts } from "../src/agent-home.ts";

test("profile homes link to the shared memory and skills under their runtime's names", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-agent-"));
  const agent = join(root, "agent");
  const profiles = [
    { id: "cc", runtimes: ["claude" as const], home: join(root, "cc") },
    { id: "cx", runtimes: ["codex" as const], home: join(root, "cx") },
    { id: "both", runtimes: ["claude" as const, "codex" as const], home: join(root, "both") },
  ];
  linkAgentHome(agent, profiles);
  linkAgentHome(agent, profiles); // idempotent
  assert.equal(readlinkSync(join(root, "cc", "CLAUDE.md")), join(agent, "MEMORY.md"));
  assert.equal(readlinkSync(join(root, "cc", "skills")), join(agent, "skills"));
  assert.equal(readlinkSync(join(root, "cx", "AGENTS.md")), join(agent, "MEMORY.md"));
  assert.equal(readlinkSync(join(root, "cx", "skills")), join(agent, "skills"));
  // An account run on both reads the memory under both names.
  assert.equal(readlinkSync(join(root, "both", "CLAUDE.md")), join(agent, "MEMORY.md"));
  assert.equal(readlinkSync(join(root, "both", "AGENTS.md")), join(agent, "MEMORY.md"));
});

test("a hand-written file in a profile home is left alone", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-agent-"));
  mkdirSync(join(root, "cc"));
  writeFileSync(join(root, "cc", "CLAUDE.md"), "mine");
  linkAgentHome(join(root, "agent"), [{ runtimes: ["claude"], home: join(root, "cc") }]);
  assert.equal(readFileSync(join(root, "cc", "CLAUDE.md"), "utf8"), "mine");
});

test("every profile's transcripts are a runtime's one shared place; a real directory is left alone", () => {
  const root = mkdtempSync(join(tmpdir(), "ember-transcripts-"));
  mkdirSync(join(root, "own", "sessions"), { recursive: true });
  linkTranscripts(root, [
    { id: "both", runtimes: ["claude", "codex"], home: join(root, "both") },
    { id: "own", runtimes: ["codex"], home: join(root, "own") },
  ]);
  assert.equal(readlinkSync(join(root, "both", "projects")), join(root, "transcripts", "claude"));
  assert.equal(readlinkSync(join(root, "both", "sessions")), join(root, "transcripts", "codex"));
  assert.equal(lstatSync(join(root, "own", "sessions")).isDirectory(), true);
});
