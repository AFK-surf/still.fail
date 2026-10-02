// The agents' memory, for the pages to show (GET /memory; the agents write it): the global one, and the shared skills
// (projects' memories among them). admin/mod.rs's route over agent_home.rs `agent_home_paths` and `list_skills`.
import { readFileSync, readdirSync } from "node:fs";
import type { Json } from "./store.ts";

/// The skills the station brings (agent_home.rs BUILTIN_SKILLS, and FEEDBACK_SKILL): rewritten at every start, so not
/// edited on the pages.
const BUILTIN = ["stillfail-jobs", "stillfail-show", "stillfail-viz", "stillfail-feedback"];
/// What a project memory's description starts with.
const PROJECT_PREFIX = "项目记忆：";

/// Path::join as Rust has it: an absolute path replaces, nothing is normalised.
const joined = (dir: string, name: string) => (name.startsWith("/") ? name : dir.endsWith("/") ? `${dir}${name}` : `${dir}/${name}`);

/// std::fs::read_to_string: the file as UTF-8, none when it does not read or is not UTF-8.
const STRICT = new TextDecoder("utf-8", { fatal: true });
function readText(path: string): string | null {
  try {
    return STRICT.decode(readFileSync(path));
  } catch {
    return null;
  }
}

/// config.rs: the agents' home, `agentHome` in config.json under the data directory (default `agent`).
function agentHome(dataDir: string): string {
  let raw: Json;
  try {
    raw = JSON.parse(readFileSync(joined(dataDir, "config.json"), "utf8"));
  } catch {
    raw = {};
  }
  return joined(dataDir, typeof raw?.agentHome === "string" ? raw.agentHome : "agent");
}

/// front: a SKILL.md's frontmatter field (`key: value`), if it has one.
function front(text: string, key: string): string | null {
  if (!text.startsWith("---\n")) return null;
  const body = text.slice(4);
  const end = body.indexOf("\n---");
  if (end < 0) return null;
  for (const raw of body.slice(0, end).split("\n")) {
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    if (line.startsWith(`${key}:`)) return line.slice(key.length + 1).trim().replace(/^"+|"+$/g, "");
  }
  return null;
}

/// Rust's String order (bytes of UTF-8).
const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// list_skills: the shared skills, the team's first (projects' memories before the rest), then the station's own; by name.
function listSkills(home: string): Json[] {
  const dir = joined(home, "skills");
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  const skills = names.flatMap((name) => {
    const text = readText(joined(joined(dir, name), "SKILL.md"));
    if (text === null) return [];
    const description = front(text, "description") ?? "";
    return [{ name, description, project: description.startsWith(PROJECT_PREFIX), builtin: BUILTIN.includes(name), text }];
  });
  return skills.sort((a, b) => Number(a.builtin) - Number(b.builtin) || Number(!a.project) - Number(!b.project) || byBytes(a.name, b.name));
}

/// GET /memory.
export function memory(dataDir: string): Json {
  const home = agentHome(dataDir);
  const path = joined(home, "MEMORY.md");
  return { global: { path, text: readText(path) ?? "" }, skills: listSkills(home) };
}
