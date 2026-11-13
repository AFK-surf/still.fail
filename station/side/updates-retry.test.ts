import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, watch, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { Updates } from "../src/updates/updates.ts";
import { settle, testClock } from "../test/hub-fakes.ts";
import { feedOf, trusted } from "../test/release-fakes.ts";

test("a failed installer is retried once and the release is installed", { skip: process.platform === "win32" }, async (t) => {
  const data = mkdtempSync(join(tmpdir(), "updates-retry-side-"));
  const app = join(data, "app"), run = join(data, "run");
  mkdirSync(join(app, "bin"), { recursive: true });
  mkdirSync(run);
  writeFileSync(join(app, "BUILD"), "1300\n");
  writeFileSync(join(app, "bin", "install.zh.sh"), `#!/bin/sh
set -eu
echo ran >> "$STILLFAIL_DATA/attempts"
if [ ! -f "$STILLFAIL_DATA/first" ]; then
  touch "$STILLFAIL_DATA/first"
  echo 'database is locked' >&2
  exit 1
fi
printf 'handoff\\n' > "$STILLFAIL_DATA/run/update.step"
printf '1310\\n' > "$STILLFAIL_DATA/app/BUILD"
`);
  const server = createServer((req, res) => {
    if (req.url?.startsWith("/releases/station.json")) res.end(JSON.stringify(feedOf(1310)));
    else res.writeHead(404).end();
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const config = new ConfigFile(data);
  config.update((raw) => (raw.autoUpdate = true));
  const time = testClock();
  const updates = new Updates({ app, data, config, origin: () => origin, env: { PATH: "/usr/bin:/bin" }, stationOnly: true, trusted, clock: time.clock });
  t.after(async () => { await updates.close(); await new Promise<void>((resolve) => server.close(() => resolve())); rmSync(data, { recursive: true, force: true }); });
  const until = (predicate: () => boolean) => new Promise<void>((resolve) => {
    const off = updates.changes(() => { if (predicate()) { off(); resolve(); } });
    if (predicate()) { off(); resolve(); }
  });
  const exit = (code: string) => new Promise<void>((resolve, reject) => {
    const observed = () => {
      try {
        if (readFileSync(join(run, "update.exit"), "utf8").trim() !== code) return;
      } catch { return; }
      watcher.close();
      t.signal.removeEventListener("abort", aborted);
      resolve();
    };
    const watcher = watch(run, observed);
    const aborted = () => { watcher.close(); reject(t.signal.reason); };
    t.signal.addEventListener("abort", aborted, { once: true });
    observed();
  });
  const failed = until(() => updates.get()[0]!.state === "failed");
  const failedExit = exit("1");
  updates.start();
  await failedExit;
  await settle();
  await time.adjust(200);
  await failed;
  assert.equal(readFileSync(join(data, "attempts"), "utf8"), "ran\n");
  const done = until(() => updates.get()[0]!.done !== undefined);
  const doneExit = exit("0");
  await settle();
  await time.adjust(60_000);
  await doneExit;
  await settle();
  await time.adjust(200);
  await done;
  assert.equal(readFileSync(join(data, "attempts"), "utf8"), "ran\nran\n");
  assert.equal(readFileSync(join(app, "BUILD"), "utf8").trim(), "1310");
});
