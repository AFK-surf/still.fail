// The sandbox bridge's heartbeat (src/agents/sandbox-bridge.mjs) on real time, so beside the checks (`pnpm test:side`):
// a connection that breaks without either end being told (the far side's input never ends) ends the program there
// within its silence, and the side here says the connection was lost. test/sandbox.test.ts covers the rest.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, test } from "node:test";
import { BRIDGE, CONNECTION_LOST, LOST_EXIT } from "../src/agents/sandbox.ts";

const dir = mkdtempSync("/tmp/sbx-side-");
after(() => rmSync(dir, { recursive: true, force: true }));

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};
const until = async (check: () => boolean) => {
  while (!check()) await new Promise((r) => setTimeout(r, 20));
};

test("a connection gone silent ends the program in the sandbox, and is said here to be lost", async () => {
  // A stand-in ssh whose stream can be held: the far side detached with its stdio through a relay here, which the test
  // stops (SIGSTOP), as a network that drops packets without closing anything.
  const ssh = join(dir, "ssh");
  writeFileSync(
    ssh,
    `#!${process.execPath}
const { spawn } = require("node:child_process");
const { writeFileSync } = require("node:fs");
writeFileSync(${JSON.stringify(join(dir, "ssh.pid"))}, String(process.pid));
const far = spawn("/bin/sh", ["-c", process.argv.at(-1)], { detached: true, stdio: ["pipe", "pipe", "inherit"] });
process.stdin.pipe(far.stdin);
far.stdin.on("error", () => {});
far.stdout.pipe(process.stdout);
far.on("exit", (code) => process.exit(code ?? 1));
`,
  );
  chmodSync(ssh, 0o755);
  const pidFile = join(dir, "pid");
  const spec = { ssh: [ssh, "s-x.ws@host"], program: "/bin/sh", args: ["-c", `echo $$ > ${pidFile}; exec tail -f /dev/null`], cwd: dir, ports: [], silentMs: 900 };
  const child = spawn(process.execPath, [BRIDGE, "host", JSON.stringify(spec)], { stdio: ["pipe", "ignore", "pipe"] });
  let err = "";
  child.stderr.on("data", (b) => (err += b));
  const ended = new Promise<number | null>((r) => child.on("close", (code) => r(code)));
  await until(() => existsSync(pidFile) && readFileSync(pidFile, "utf8").trim() !== "");
  const pid = Number(readFileSync(pidFile, "utf8"));
  process.kill(Number(readFileSync(join(dir, "ssh.pid"), "utf8")), "SIGSTOP");
  await until(() => !alive(pid));
  assert.equal(await ended, LOST_EXIT);
  assert.ok(err.includes(CONNECTION_LOST), err);
});
