// Asks each configured profile's runtime what it knows from the shared agent
// home, to confirm memory and skills are actually loaded. Usage: node scripts/check-agent-home.ts
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expandRoute, loadConfig } from "../src/config.ts";
import { run } from "../spike/lib.ts";

const QUESTION = "Answer only from what you were given at startup, without running tools: " +
  "(1) Which timezone should user-facing times in Slack use? " +
  "(2) List the names of all skills available to you, comma-separated.";

const config = loadConfig();
const cwd = mkdtempSync(join(tmpdir(), "ember-check-"));
for (const profile of config.profiles) {
  const env: NodeJS.ProcessEnv = { ...process.env, ...expandRoute(profile.env, `check-${profile.id}`) };
  let answer: string;
  try {
    if (profile.runtime === "claude") {
      delete env.ANTHROPIC_AUTH_TOKEN;
      env.CLAUDE_CONFIG_DIR = profile.home;
      const out = await run("claude", ["-p", QUESTION, "--model", profile.model ?? config.defaults.model ?? "deepseek-flash"],
        { cwd, env, timeout: 240_000 });
      answer = out.stdout.trim();
    } else {
      delete env.OPENAI_API_KEY;
      env.CODEX_HOME = profile.home;
      const out = await run("codex", ["exec", "--skip-git-repo-check", QUESTION], { cwd, env, timeout: 240_000 });
      answer = out.stdout.trim();
    }
  } catch (error: any) {
    answer = `FAILED: ${String(error.stderr ?? error.message).slice(-400)}`;
  }
  console.log(`\n### ${profile.id} (${profile.runtime})\n${answer}`);
}
