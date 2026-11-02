// A background station can find a runtime on the person's shell PATH. These shells, runtimes and Nodes are stand-ins
// in a temporary home; the station's PATH deliberately contains a different Node first.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import { LoginManager } from "../src/accounts/login.ts";
import { MachineLogins } from "../src/accounts/machine.ts";
import { RunnerConnection, startRunner } from "../src/agents/runner.ts";
import { DeviceTools } from "../src/device/tools.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { forgetShellPaths, readShellPath, withShellCommand } from "../src/ops/shell-path.ts";
import { WINDOWS } from "../src/platform/index.ts";
import { run } from "../src/updates/runtimes.ts";
import { Updates } from "../src/updates/updates.ts";

const skip = WINDOWS && "interactive shell discovery is Unix's";
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function until(f: () => boolean) {
  for (let i = 0; i < 300; i++) {
    if (f()) return;
    await sleep(20);
  }
  throw new Error("timed out waiting for the command");
}

function world() {
  const home = mkdtempSync(join(tmpdir(), "stillfail-shell-path-"));
  const installation = join(home, "custom", "node");
  const bin = join(installation, "bin");
  const pkg = join(installation, "lib", "node_modules", "@openai", "codex", "bin");
  const system = join(home, "system");
  const data = join(home, "custom-data");
  const interactive = join(data, "interactive");
  const login = join(data, "login");
  const version = join(home, "version");
  const shell = join(home, "shell");
  mkdirSync(bin, { recursive: true });
  mkdirSync(pkg, { recursive: true });
  mkdirSync(system);
  mkdirSync(data);
  symlinkSync(process.execPath, join(bin, "node"));
  symlinkSync(join(pkg, "codex.js"), join(bin, "codex"));
  writeFileSync(join(system, "node"), "#!/bin/sh\necho wrong-node >&2\nexit 80\n", { mode: 0o755 });
  writeFileSync(version, "0.166.0");
  writeFileSync(interactive, `${bin}:${system}:/usr/bin:/bin`);
  writeFileSync(login, `${system}:/usr/bin:/bin`);
  writeFileSync(shell, `#!/bin/sh
printf '%s' "\${TEST_TOKEN-unset}" > "$HOME/probe-secret"
if [ "$2" = -l ]; then from="$XDG_DATA_HOME/login"; else from="$XDG_DATA_HOME/interactive"; fi
PATH=$(/bin/cat "$from"); export PATH
export OPENAI_API_KEY=shell-only-secret CODEX_HOME=/wrong-home
echo 'shell startup message'
"$STILLFAIL_SHELL_NODE" -e "$STILLFAIL_SHELL_CODE"
`, { mode: 0o755 });
  writeFileSync(join(pkg, "codex.js"), `#!/usr/bin/env node
const fs = require('node:fs');
if (process.argv.includes('--version')) console.log('codex-cli ' + fs.readFileSync(process.env.FAKE_VERSION, 'utf8'));
else if (process.argv.includes('status')) console.log('Not logged in');
else if (process.argv.includes('--device-auth')) { if (process.env.XDG_DATA_HOME) process.exit(8); console.log('https://auth.openai.com/codex/device\\nABCD-12345'); setTimeout(() => process.exit(0), 100); }
else if (process.argv.includes('app-server')) { console.log('shell-app-server-ready'); process.stdin.once('data', () => process.exit(0)); }
`, { mode: 0o755 });
  writeFileSync(join(bin, "npm"), `#!/usr/bin/env node
const fs = require('node:fs');
fs.writeFileSync(process.env.HOME + '/npm-node', process.execPath);
fs.writeFileSync(process.env.FAKE_VERSION, '0.166.1');
`, { mode: 0o755 });
  const env = { HOME: home, SHELL: shell, PATH: `${system}:/usr/bin:/bin`, XDG_DATA_HOME: data, FAKE_VERSION: version, TEST_TOKEN: "do-not-send-to-shell" };
  return { home, bin, system, env, interactive, login };
}

test("a missing command uses the interactive or login shell PATH, without importing the shell's credentials", { skip }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  forgetShellPaths();
  const found = await withShellCommand("codex", w.env);
  assert.notEqual(found, w.env);
  assert.equal(w.env.PATH, `${w.system}:/usr/bin:/bin`);
  assert.equal(found.OPENAI_API_KEY, undefined);
  assert.equal(found.CODEX_HOME, undefined);
  assert.equal(readFileSync(join(w.home, "probe-secret"), "utf8"), "unset");
  assert.equal((await run("codex", ["--version"], w.env, 5000))[1].trim(), "codex-cli 0.166.0");

  // An executable already on PATH wins over the shell. A path explicitly named is never replaced.
  writeFileSync(join(w.system, "codex"), "#!/bin/sh\necho codex-cli 1.2.3\n", { mode: 0o755 });
  assert.equal(await withShellCommand("codex", w.env), w.env);
  assert.equal((await run("codex", ["--version"], w.env, 5000))[1].trim(), "codex-cli 1.2.3");
  assert.equal(await withShellCommand("/elsewhere/codex", w.env), w.env);
  unlinkSync(join(w.system, "codex"));

  // Rechecking after a shell configuration change discovers a command only the login shell exposes.
  writeFileSync(w.interactive, `${w.system}:/usr/bin:/bin`);
  writeFileSync(w.login, `${w.bin}:${w.system}:/usr/bin:/bin`);
  forgetShellPaths();
  assert.equal((await run("codex", ["--version"], w.env, 5000))[1].trim(), "codex-cli 0.166.0");
});

test("a background station reads a real bash startup file", { skip }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  writeFileSync(join(w.home, ".bashrc"), 'export PATH="$HOME/custom/node/bin:$PATH"\n');
  forgetShellPaths();
  const env = { ...w.env, SHELL: "/bin/bash" };
  assert.equal((await run("codex", ["--version"], env, 5000))[1].trim(), "codex-cli 0.166.0");
});

test("a shell's temporary PATH links are resolved before it exits, and a stuck shell is bounded", { skip }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  const link = join(w.home, "temporary-bin");
  const shell = join(w.home, "ephemeral-shell");
  writeFileSync(shell, `#!/bin/sh
/bin/ln -s "$BIN" "$LINK"
PATH="$LINK:/usr/bin:/bin"; export PATH
"$STILLFAIL_SHELL_NODE" -e "$STILLFAIL_SHELL_CODE"
/bin/rm "$LINK"
`, { mode: 0o755 });
  const env = { ...w.env, SHELL: shell, BIN: w.bin, LINK: link };
  const dirs = await readShellPath(shell, false, env);
  assert.equal(dirs?.[0], realpathSync(w.bin));
  forgetShellPaths();
  assert.equal((await run("codex", ["--version"], env, 5000))[1].trim(), "codex-cli 0.166.0");

  const stuck = join(w.home, "stuck-shell");
  writeFileSync(stuck, "#!/bin/sh\n/bin/sleep 30\n", { mode: 0o755 });
  const started = performance.now();
  assert.equal(await readShellPath(stuck, false, env, 150), null);
  assert.ok(performance.now() - started < 3000);
});

test("replacing a sign-in while its shell is being read does not start the cancelled command", { skip }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  const ready = join(w.home, "probe-ready");
  const release = join(w.home, "probe-release");
  writeFileSync(w.env.SHELL, `#!/bin/sh
touch "$HOME/probe-ready"
while [ ! -f "$HOME/probe-release" ]; do sleep 0.02; done
PATH=$(/bin/cat "$XDG_DATA_HOME/interactive"); export PATH
"$STILLFAIL_SHELL_NODE" -e "$STILLFAIL_SHELL_CODE"
`, { mode: 0o755 });
  forgetShellPaths();
  const manager = new LoginManager(join(w.home, ".stillfail"), { claude: "claude", codex: "codex" }, () => w.env);
  t.after(() => manager.close());
  const profile = { id: "replace", runtime: "codex" as const, home: join(w.home, "profile") };
  const first = manager.start(profile, "en");
  await until(() => existsSync(ready));
  const second = manager.start(profile, "en");
  writeFileSync(release, "go");
  assert.equal((await first).state, "cancelled");
  assert.equal((await second).state, "starting");
  await until(() => manager.get(profile.id)?.state === "done" || manager.get(profile.id)?.state === "failed");
  assert.equal(manager.get(profile.id)?.state, "done");
});

test("a terminal-wrapped login finds its command on the shell PATH", { skip }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  writeFileSync(join(w.bin, "devin"), '#!/bin/sh\necho invoked > "$HOME/devin-invoked"\n', { mode: 0o755 });
  writeFileSync(join(w.home, ".bashrc"), 'export PATH="$HOME/custom/node/bin:$PATH"\n');
  forgetShellPaths();
  const env = { ...w.env, SHELL: "/bin/bash" };
  const manager = new LoginManager(join(w.home, ".stillfail"), { claude: "claude", codex: "codex", devin: "devin" }, () => env);
  t.after(() => manager.close());
  await manager.start({ id: "devin", runtime: "devin", home: join(w.home, "profile") }, "en");
  await until(() => manager.get("devin")?.state === "done" || manager.get("devin")?.state === "failed");
  assert.equal(manager.get("devin")?.state, "done");
  assert.equal(readFileSync(join(w.home, "devin-invoked"), "utf8").trim(), "invoked");
});

test("software checks, sign-ins, updates and the runner use the shell's runtime and Node", { skip, timeout: 20_000 }, async (t) => {
  const w = world();
  t.after(() => rmSync(w.home, { recursive: true, force: true }));
  const data = join(w.home, ".stillfail");
  const updates = new Updates({ app: join(data, "app"), data, config: new ConfigFile(data), env: w.env, origin: () => null, registry: "http://127.0.0.1:1", devinManifest: "http://127.0.0.1:1" });
  t.after(() => updates.close());
  await updates.check();
  const codex = () => updates.get("en").find((x) => x.id === "codex")!;
  assert.deepEqual([codex().installed, codex().version, codex().updatable], [true, "0.166.0", true]);

  const machine = new MachineLogins(w.env, undefined, () => "en");
  await machine.refresh();
  assert.deepEqual([machine.get()[1]!.installed, machine.get()[1]!.loggedIn], [true, false]);
  const device = new DeviceTools({ home: w.home, env: w.env });
  t.after(() => device.close());
  const probe = await Effect.runPromise(device.run("runtime.probe", {}, { user_email: "a@x" }, "read")) as any;
  assert.equal(probe.runtimes[0].version, "0.166.0");

  const logins = new LoginManager(data, { claude: "claude", codex: "codex" }, () => w.env);
  t.after(() => logins.close());
  await logins.start({ id: "test", runtime: "codex", home: join(data, "profile") }, "en");
  await until(() => logins.get("test")?.state === "done" || logins.get("test")?.state === "failed");
  assert.equal(logins.get("test")?.state, "done");

  const info = await startRunner(data, "shell-test", "codex", ["app-server"], w.env, w.home);
  const lines: string[] = [];
  const connection = new RunnerConnection(info, (stream, line) => { if (stream === "out") lines.push(line); });
  t.after(() => { connection.signal("KILL"); connection.done(); });
  await until(() => lines.includes("shell-app-server-ready"));
  connection.write("stop\n");
  assert.deepEqual(await connection.exited, { code: 0, signal: null });

  // npm's shebang uses the shell's Node, even though the station's PATH has another node first.
  await updates.update("codex", "en");
  await until(() => codex().state !== "updating");
  assert.equal(codex().state, "idle", codex().message);
  assert.equal(codex().version, "0.166.1");
  assert.equal(realpathSync(readFileSync(join(w.home, "npm-node"), "utf8")), realpathSync(process.execPath));
});
