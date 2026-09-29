import assert from "node:assert/strict";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { moveUserData } from "../apps/desktop/src/moves.mts";

/** An Application Support of its own: `ember` (the old app's data) with a sign-in and a page's storage. */
function support(): { dir: string; now: string; former: string } {
  const dir = mkdtempSync(join(tmpdir(), "stillfail-moves-"));
  const former = join(dir, "ember");
  mkdirSync(join(former, "core"), { recursive: true });
  writeFileSync(join(former, "core", "core.db"), "sign-ins");
  mkdirSync(join(former, "Local Storage"));
  return { dir, now: join(dir, "still.fail"), former };
}

const nobody = () => false;

test("the old app's data moves to the new name, a link left at the old place", () => {
  const { dir, now, former } = support();
  assert.deepEqual(moveUserData(now, former, nobody), { dir: now, moved: true });
  assert.equal(readFileSync(join(now, "core", "core.db"), "utf8"), "sign-ins");
  assert.equal(readlinkSync(former), now);
  // Once: the next start finds the link and moves nothing.
  assert.deepEqual(moveUserData(now, former, nobody), { dir: now, moved: false });
  rmSync(dir, { recursive: true });
});

test("a new place Electron made already gets what it lacks", () => {
  const { dir, now, former } = support();
  mkdirSync(join(now, "Crashpad"), { recursive: true });
  mkdirSync(join(former, "Crashpad"));
  assert.equal(moveUserData(now, former, nobody).dir, now);
  assert.equal(readFileSync(join(now, "core", "core.db"), "utf8"), "sign-ins");
  assert.ok(lstatSync(join(now, "Local Storage")).isDirectory());
  rmSync(dir, { recursive: true });
});

test("a new place in use, or an old app running on the old one, leaves the old one as it is", () => {
  const { dir, now, former } = support();
  mkdirSync(join(now, "core"), { recursive: true });
  assert.deepEqual(moveUserData(now, former, nobody), { dir: now, moved: false });
  assert.ok(lstatSync(former).isDirectory());
  rmSync(now, { recursive: true });
  symlinkSync("studio-4242", join(former, "SingletonLock"));
  assert.deepEqual(moveUserData(now, former, (pid) => pid === 4242), { dir: former, moved: false });
  // Its process gone, the lock is only left over.
  assert.equal(moveUserData(now, former, nobody).moved, true);
  rmSync(dir, { recursive: true });
});

test("a machine that never ran the old app starts in the new place", () => {
  const dir = mkdtempSync(join(tmpdir(), "stillfail-moves-"));
  assert.deepEqual(moveUserData(join(dir, "still.fail"), join(dir, "ember"), nobody), { dir: join(dir, "still.fail"), moved: false });
  rmSync(dir, { recursive: true });
});
