import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MachineLogins } from "../src/machine-logins.ts";

/** A machine: a HOME, and a bin/ with stand-ins for the CLIs (shell scripts), on a PATH of only that and the system's. */
function machine(clis: Record<string, string>): NodeJS.ProcessEnv {
  const home = mkdtempSync(join(tmpdir(), "ember-machine-"));
  const bin = join(home, "bin");
  mkdirSync(bin);
  for (const [name, script] of Object.entries(clis)) {
    writeFileSync(join(bin, name), `#!/bin/sh\n${script}\n`);
    chmodSync(join(bin, name), 0o755);
  }
  return { HOME: home, PATH: `${bin}:/usr/bin:/bin` };
}

/** An id token as Codex keeps one: only its claims matter here. */
function idToken(claims: object): string {
  return `x.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.y`;
}

test("the machine's own logins are read, with the account and plan, from the machine's own homes", async () => {
  const env = machine({
    // Only answers for the machine's own home: no CLAUDE_CONFIG_DIR may reach it.
    claude: `[ -n "$CLAUDE_CONFIG_DIR" ] && exit 3; echo '{"loggedIn":true,"authMethod":"claude.ai","email":"a@x.com","subscriptionType":"max"}'`,
    codex: `[ "$CODEX_HOME" = "$HOME/.codex" ] || exit 3; echo "Logged in using ChatGPT"`,
  });
  mkdirSync(join(env.HOME!, ".codex"));
  writeFileSync(join(env.HOME!, ".codex", "auth.json"), JSON.stringify({ tokens: { id_token: idToken({ email: "b@x.com", "https://api.openai.com/auth": { chatgpt_plan_type: "plus" } }) } }));
  const logins = new MachineLogins({ ...env, CLAUDE_CONFIG_DIR: "/elsewhere" });
  let changes = 0;
  logins.changes.on("change", () => changes++);
  await logins.refresh();
  await logins.refresh();
  // The pages hear of the first reading, and not of one that says the same.
  assert.equal(changes, 1);
  assert.deepEqual(logins.get(), [
    { runtime: "claude", installed: true, loggedIn: true, email: "a@x.com", plan: "max", text: "Claude Code 已登录 a@x.com（Max）" },
    { runtime: "codex", installed: true, loggedIn: true, email: "b@x.com", plan: "plus", text: "Codex 已登录 b@x.com（Plus）" },
  ]);
});

test("signed out, and not installed, are said as such", async () => {
  const env = machine({
    // Signed out, `auth status` exits non-zero with its JSON; so does `login status`, with its message.
    claude: `echo '{"loggedIn":false}'; exit 1`,
  });
  const logins = new MachineLogins(env);
  await logins.refresh();
  assert.deepEqual(logins.get().map((l) => [l.runtime, l.installed, l.loggedIn, l.text]), [
    ["claude", true, false, "Claude Code 没有登录"],
    ["codex", false, false, "没有装 Codex"],
  ]);
  const out = machine({ codex: `echo "Not logged in" >&2; exit 1` });
  const codex = new MachineLogins(out);
  await codex.refresh();
  assert.deepEqual(codex.get().map((l) => [l.runtime, l.installed, l.loggedIn]), [["claude", false, false], ["codex", true, false]]);
});
