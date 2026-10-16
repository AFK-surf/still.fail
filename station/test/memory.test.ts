// The agents' memory as GET /memory reads it (src/read/memory.ts): the global one, and each skill with the other
// Markdown files beside its SKILL.md.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { memory } from "../src/read/memory.ts";

test("a_skill_comes_with_its_other_files", () => {
  const data = mkdtempSync(join(tmpdir(), "memory-"));
  const skill = join(data, "agent/skills/ember");
  mkdirSync(skill, { recursive: true });
  writeFileSync(join(data, "agent/MEMORY.md"), "# memory\n");
  writeFileSync(join(skill, "SKILL.md"), "---\nname: ember\ndescription: 项目记忆：ember\n---\n总览\n");
  writeFileSync(join(skill, "verify.md"), "验证\n");
  writeFileSync(join(skill, "design.md"), "设计\n");
  writeFileSync(join(skill, "SKILL.conflict-mini.md"), "冲突\n");
  writeFileSync(join(skill, "shot.png"), "png");
  const read = memory(data) as any;
  assert.equal(read.global.text, "# memory\n");
  assert.equal(read.skills[0].project, true);
  assert.deepEqual(read.skills[0].files, [{ name: "design.md", text: "设计\n" }, { name: "verify.md", text: "验证\n" }]);
});
