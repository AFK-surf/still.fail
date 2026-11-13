import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { hold } from "../src/updates/holds.ts";
import { Updates } from "../src/updates/updates.ts";
import { settle, testClock } from "./hub-fakes.ts";

test("a failed automatic update gets one delayed retry, still waiting for vault work", async (t) => {
  const data = mkdtempSync(join(tmpdir(), "updates-retry-"));
  const app = join(data, "app"), run = join(data, "run");
  mkdirSync(app);
  mkdirSync(run);
  writeFileSync(join(app, "BUILD"), "1300\n");
  const config = new ConfigFile(data);
  config.update((raw) => (raw.autoUpdate = true));
  const time = testClock();
  const updates = new Updates({ app, data, config, origin: () => null, stationOnly: true, clock: time.clock });
  const letGo = hold();
  t.after(async () => { letGo(); await updates.close(); rmSync(data, { recursive: true, force: true }); });
  const attempts: string[] = [];
  // Keep the real update decision, but substitute the installer and version fetch.
  updates.check = async () => {};
  (updates as unknown as { updateStation(): Promise<void> }).updateStation = async () => {
    const to = updates.get()[0]!.latest!;
    attempts.push(to);
    updates.tried = to;
  };
  updates.stationWith("0.1.1310");
  updates.tried = "0.1.1310";
  updates.start();
  writeFileSync(join(run, "update.log"), "handover failed: database is locked\n");
  writeFileSync(join(run, "update.exit"), "1\n");
  updates.follow({ at: time.clock.currentTimeMillisUnsafe(), from: "0.1.1300" });
  await settle();
  assert.equal(updates.get()[0]!.state, "failed");
  await time.adjust(59_999);
  await settle();
  assert.deepEqual(attempts, []);
  letGo();
  await settle();
  assert.deepEqual(attempts, [], "releasing the vault hold cannot bypass the delay");
  const heldAgain = hold();
  t.after(heldAgain);
  await time.adjust(1);
  await settle();
  assert.deepEqual(attempts, [], "the vault command still holds the update");
  heldAgain();
  await settle();
  assert.deepEqual(attempts, ["0.1.1310"]);

  // A second failure of that release does not cause an endless series of handovers.
  updates.follow({ at: time.clock.currentTimeMillisUnsafe(), from: "0.1.1300" });
  await settle();
  await time.adjust(120_000);
  await settle();
  assert.deepEqual(attempts, ["0.1.1310"]);
  updates.stationWith("0.1.1320");
  assert.equal(updates.toUpdateTo(), "0.1.1320", "a newer release is not blocked");
  const nextHold = hold();
  nextHold();
  await settle();
  assert.deepEqual(attempts, ["0.1.1310", "0.1.1320"]);
});
