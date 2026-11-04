import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

test("down stops a test service under a symlinked station", { skip: process.platform !== "darwin" }, async () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "mbui-cleanup-")));
  const station = join(root, "station");
  const link = join(root, "station-link");
  const serviceDir = join(station, "data", "sessions", "service");
  const otherDir = join(root, "other-service");
  mkdirSync(serviceDir, { recursive: true });
  mkdirSync(otherDir);
  symlinkSync(station, link);
  const socket = createServer();
  await new Promise((resolve) => socket.listen(0, "127.0.0.1", resolve));
  const port = socket.address().port;
  await new Promise((resolve) => socket.close(resolve));
  const service = spawn("python3", ["-u", "-m", "http.server", String(port), "--bind", "127.0.0.1"], {
    cwd: serviceDir,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const other = spawn("python3", ["-u", "-m", "http.server", "0", "--bind", "127.0.0.1"], {
    cwd: otherDir,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const stopped = once(service, "exit");
  const otherStopped = once(other, "exit");
  try {
    await Promise.all([once(service.stdout, "data"), once(other.stdout, "data")]);
    const script = join(dirname(fileURLToPath(import.meta.url)), "e2e-local.sh");
    const result = spawnSync("bash", [script, "down"], {
      env: { ...process.env, E2E_WORK: join(root, "work"), E2E_STATION: link, E2E_PORT: String(port - 7), E2E_RELAY: String(port - 8) },
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr);
    await once(service, "exit", { signal: AbortSignal.timeout(1000) });
    assert.equal(other.exitCode, null, "a service outside the test station was stopped");
    assert.equal(other.signalCode, null, "a service outside the test station was killed");
  } finally {
    if (service.exitCode === null && service.signalCode === null) service.kill("SIGTERM");
    if (other.exitCode === null && other.signalCode === null) other.kill("SIGTERM");
    await Promise.all([stopped, otherStopped]);
    rmSync(root, { recursive: true, force: true });
  }
});
