import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, watch, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { hearLines } from "../src/ops/log.ts";
import { Updates } from "../src/updates/updates.ts";
import { settle, testClock } from "../test/hub-fakes.ts";
import { feedOf, trusted } from "../test/release-fakes.ts";

for (const outage of [false, true]) test(outage
  ? "a failed installer is retried when the signed feed recovers"
  : "a failed installer is retried once and the release is installed", { skip: process.platform === "win32" }, async (t) => {
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
  let mode: "online" | "offline" | "plan" | "plan-fails" = "online", served = 0;
  const server = createServer((req, res) => {
    if (!req.url?.startsWith("/releases/station.json")) return void res.writeHead(404).end();
    if (mode === "offline") return void res.writeHead(503).end();
    if (mode === "plan-fails") { mode = "online"; return void res.writeHead(503).end(); }
    if (mode === "plan") mode = "plan-fails";
    else if (outage && ++served === 2) mode = "offline";
    res.end(JSON.stringify(feedOf(1310)));
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
  if (outage) {
    await until(() => updates.get()[0]!.latest === undefined);
    const checked = updates.get()[0]!.checkedAt;
    const reread = until(() => updates.get()[0]!.checkedAt !== checked);
    await settle();
    await time.adjust(60_000);
    await reread;
    assert.equal(updates.get()[0]!.latest, undefined, "the retry's first feed read also failed");
    assert.equal(readFileSync(join(data, "attempts"), "utf8"), "ran\n");
    // The next reading succeeds, but the separate feed read to plan the installer fails once.
    const planFailed = new Promise<void>((resolve) => hearLines((line) => {
      if (line.at === "updates" && line.message === "the station not updated by itself") resolve();
    }));
    t.after(() => hearLines(null));
    mode = "plan";
    await settle();
    await time.adjust(120_000);
    await planFailed;
    assert.equal(readFileSync(join(data, "attempts"), "utf8"), "ran\n", "a failed plan did not start the installer");
  }
  const done = until(() => updates.get()[0]!.done !== undefined);
  const doneExit = exit("0");
  await settle();
  await time.adjust(outage ? 240_000 : 60_000);
  await doneExit;
  await settle();
  await time.adjust(200);
  await done;
  assert.equal(readFileSync(join(data, "attempts"), "utf8"), "ran\nran\n");
  assert.equal(readFileSync(join(app, "BUILD"), "utf8").trim(), "1310");
});
