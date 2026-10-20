// The app's station opened from Finder or the Dock: launchd's short PATH, and the agents where the login shell's PATH
// has them (nvm's Node's bin). The shell and the station are scripts: the shell says its environment, the station
// writes down the PATH it was started with and exits as one that finds the data held (so it is not started again).
// Run: node --test apps/desktop/test/station-path.test.ts
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const home = mkdtempSync(join(tmpdir(), "stillfail-station-path-"));
const nvm = join(home, ".nvm", "versions", "node", "v22.20.0", "bin");
const script = (path: string, body: string) => {
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
};
// What an interactive login shell prints of its own comes first; its PATH is the one ~/.zshrc made, nvm's first.
script(join(home, "zsh"), `echo "Last login: Mon Oct 19 on ttys001"; PATH="${nvm}:/usr/bin:/bin" /bin/sh -c "$2"`);
const release = join(home, "app");
mkdirSync(join(release, "mesh", "target", "release"), { recursive: true });
script(join(release, "mesh", "target", "release", "stillfail-station"), `printf '%s' "$PATH" > "${home}/said"; exit 3`);
process.env.HOME = home;
process.env.SHELL = join(home, "zsh");
process.env.STILLFAIL_DATA = join(home, "data");
process.env.PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
const { LocalStation } = await import("../src/station.ts");
after(() => rmSync(home, { recursive: true, force: true }));

test("the station opened from Finder has the login shell's PATH: Claude Code under nvm is found", { skip: process.platform === "win32" }, async () => {
  const station = new LocalStation(release);
  station.start();
  while (!station.held) await new Promise((resolve) => setTimeout(resolve, 10));
  const path = `${home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${nvm}:/usr/bin:/bin:/usr/sbin:/sbin`;
  assert.equal(readFileSync(join(home, "said"), "utf8"), path);
  assert.equal(station.path, path);
});
