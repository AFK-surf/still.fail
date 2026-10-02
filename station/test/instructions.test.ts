// The agent's instructions and the migration notes are the Rust station's, word for word: read from instructions.rs
// and migrations.rs and compared, so the two stations tell agents the same while both run.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import * as ts from "../src/agents/instructions.ts";
import { NOTES, latest, untold } from "../src/agents/migrations.ts";

const rust = readFileSync(new URL("../../mesh/app/src/instructions.rs", import.meta.url), "utf8");
const migrations = readFileSync(new URL("../../mesh/app/src/migrations.rs", import.meta.url), "utf8");

/// A format! template filled as Rust fills it: `{name}` the value, `{{` and `}}` a brace.
const fill = (template: string, values: Record<string, string>) =>
  template.replace(/\{\{|\}\}|\{([a-z_]+)\}/g, (all, name) => (all === "{{" ? "{" : all === "}}" ? "}" : values[name]));

test("the session instructions are the Rust station's", () => {
  const template = /format!\(\s*r#"([\s\S]*?)"#\s*\)/.exec(rust)![1];
  const values = { workspace: "/w/s/workspace", repos_dir: "/w/repos", memory_path: "/w/agent/MEMORY.md" };
  assert.equal(ts.sessionInstructions(values.workspace, null, values.repos_dir, values.memory_path), fill(template, { ...values, project: "" }));
  const project = "- Project directory: /p. This session began outside still.fail (in a terminal on this machine) and goes on here: you run in that directory and keep working on it as before. The session workspace below is for scratch files only.\n";
  assert.equal(ts.sessionInstructions(values.workspace, "/p", values.repos_dir, values.memory_path), fill(template, { ...values, project }));
});

test("the fixed prompts are the Rust station's", () => {
  for (const name of ["NUDGE", "RESUME_AFTER_RESTART", "GO_ON_AFTER_AUTH", "GO_ON_AFTER_SPENT", "RESUME_LOST"] as const) {
    const expected = new RegExp(`pub const ${name}: &str = r#"([\\s\\S]*?)"#;`).exec(rust)![1];
    assert.equal(ts[name], expected, name);
  }
  const waitOver = /pub fn wait_over\(seconds: u64\) -> String \{\s*format!\(\s*r#"([\s\S]*?)"#\s*\)/.exec(rust)![1];
  assert.equal(ts.waitOver(90), fill(waitOver, { seconds: "90" }));
  const continued = JSON.parse(`"${/pub fn continued_here\(instructions: &str\) -> String \{\s*format!\(\s*"([\s\S]*?)"\s*\)/.exec(rust)![1]}"`);
  assert.equal(ts.continuedHere("X"), fill(continued, { instructions: "X" }));
});

test("the migration notes are the Rust station's, numbered 1, 2, 3…", () => {
  const notes = [...migrations.slice(0, migrations.indexOf("pub fn latest")).matchAll(/\((\d+), "((?:[^"\\]|\\.)*)"\)/g)].map((m) => [Number(m[1]), JSON.parse(`"${m[2]}"`)]);
  assert.deepEqual(NOTES, notes);
  assert.equal(untold(latest(), "/w/i.md"), "");
  const all = untold(0, "/w/i.md");
  assert.ok(all.startsWith("[still.fail changed how you work") && all.includes("need_human") && all.includes("/w/i.md"));
});

test("thread addresses as the agent writes them", () => {
  assert.deepEqual(ts.parseThreadAddress(" C123/1790000000.000100 "), ["C123", "1790000000.000100"]);
  for (const bad of ["c123/1.2", "C123/1", "C123/.2", "/1.2", "C123-1.2"]) assert.equal(ts.parseThreadAddress(bad), null, bad);
});
