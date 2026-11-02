// A folder of a session's own that a runtime reading its rules from a project (Cursor's `.cursor`, Devin's `.devin`)
// is started in: the station's instructions as its always-on rule, the session's workspace's skills linked in.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { linkSync } from "../ops/links.ts";
import { log } from "../ops/log.ts";

/// The folder for session `key` under `runtimeHome` (made, its rule written as `rule` in `<dot>/rules`), the skills at
/// `skills` linked as `<dot>/skills`. `name` is the runtime's, for the log.
export function rulesFolder(runtimeHome: string, key: string, dot: string, rule: { file: string; text: string }, name: string, skills?: string): string {
  const dir = join(runtimeHome, "station", createHash("sha256").update(key).digest("hex").slice(0, 16));
  mkdirSync(join(dir, dot, "rules"), { recursive: true });
  writeFileSync(join(dir, dot, "rules", rule.file), rule.text);
  const linked = (target: string, path: string) => {
    if (!existsSync(target)) return;
    rmSync(path, { recursive: true, force: true });
    try {
      // Where links are refused (Windows without Developer Mode), a junction.
      linkSync(target, path, { junction: true, copy: true });
    } catch (e) {
      log.warn(`agents::${name.toLowerCase()}`, `the workspace's skills not linked for ${name}`, { path, error: (e as Error).message });
    }
  };
  // The skills of the session's workspace (agent-home.ts); its memory is told with the instructions. (An AGENTS.md
  // linked here before was the profile home's, the home workspace's memory whatever the session's workspace: gone.)
  rmSync(join(dir, "AGENTS.md"), { force: true });
  if (skills !== undefined) linked(skills, join(dir, dot, "skills"));
  return dir;
}
