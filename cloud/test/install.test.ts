import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { installScript, releaseType } from "../src/install.ts";

test("the installer braces every variable that words follow, so no shell takes a character for part of its name", () => {
  const script = installScript("https://ember.test");
  // A $name right before a non-ASCII character: under set -u some shells read the character's first byte as the name's.
  assert.deepEqual(script.match(/\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f])/g) ?? [], []);
  assert.match(script, /程序：\$\{app\}（/);
});

test("without a token the installer only updates a station already in a workspace", () => {
  const script = installScript("https://ember.test");
  assert.match(script, /if \[ -z "\$token" \] && \[ ! -f "\$cur\/mesh\/cloud.json" \]; then/);
  assert.match(script, /if \[ -n "\$token" \]; then\n  echo "加入 workspace…"/);
});

test("an update hands over to the new release only when the running station says it can and its service is unchanged", () => {
  const script = installScript("https://ember.test");
  assert.match(script, /if \[ -n "\$pid" \] && \[ -z "\$migrate" \] && \[ -n "\$\(said handoff\)" \] && same_service; then/);
  // The caller's PATH is not a change: an update from another shell (an agent's, the station's own) still hands over.
  assert.match(script, /without_path\(\) \{ sed -e 's#<key>PATH<\/key><string>\[\^<\]\*<\/string>##' -e '\/\^Environment=PATH=\/d'/);
  assert.match(script, /kill -USR2 "\$pid"/);
  // Otherwise drained first (when it can be), then restarted as before.
  assert.match(script, /if \[ -z "\$handed" \] && \[ -n "\$pid" \] && \[ -n "\$\(said drain\)" \]/);
  assert.match(script, /kill -USR1 "\$pid"/);
  assert.match(script, /KillMode=process/);
});

test("an update started inside the station restarts it in the background, and one to the running release does nothing", () => {
  const script = installScript("https://ember.test");
  // The drain waits for the caller's own turn: waiting on it there would wait on itself.
  assert.match(script, /if \[ -z "\$handed" \] && \[ -n "\$pid" \] && inside_station; then/);
  assert.match(script, /set -m\n  \( trap '' HUP; restart_and_finish; rm -rf "\$tmp" \) > "\$cur\/run\/update.log" 2>&1 < \/dev\/null &\n  exit 0/);
  assert.match(script, /cmp -s "\$tmp\/stillfail\/VERSION" "\$app\/VERSION" && same_service; then/);
});

test("the releases bucket serves the station's releases and the apps' builds, and nothing else", () => {
  assert.equal(releaseType("stillfail-station-linux-x64.tar.gz"), "application/gzip");
  // The last release from before the rename, for installers from before it.
  assert.equal(releaseType("ember-station-linux-x64.tar.gz"), "application/gzip");
  assert.equal(releaseType("other-station-linux-x64.tar.gz"), null);
  // The Node a release runs on, kept apart from it once per version, with its checksum.
  assert.equal(releaseType("node/node-v24.21.0-linux-x64.tar.gz"), "application/gzip");
  assert.equal(releaseType("node/node-v24.21.0-darwin-arm64.tar.gz.sha256"), "text/plain; charset=utf-8");
  assert.equal(releaseType("node/node-latest-linux-x64.tar.gz"), null);
  assert.equal(releaseType("node/other.tar.gz"), null);
  assert.equal(releaseType("desktop/stillfail-mac.yml"), "text/yaml; charset=utf-8");
  assert.equal(releaseType("desktop/stillfail-0.1.1092-arm64-mac.zip"), "application/zip");
  assert.equal(releaseType("desktop/stillfail-0.1.1092-arm64-mac.zip.blockmap"), "application/octet-stream");
  // The old app's feed is not served: it is replaced by hand.
  assert.equal(releaseType("desktop/latest-mac.yml"), null);
  assert.equal(releaseType("desktop/ember-0.1.1092-arm64-mac.zip"), null);
  assert.equal(releaseType("desktop/other-mac.yml"), null);
  assert.equal(releaseType("android/latest.json"), "application/json");
  assert.equal(releaseType("station.json"), "application/json");
  assert.equal(releaseType("android/stillfail-1124.apk"), "application/vnd.android.package-archive");
  // Builds from before the rename keep being served: the latest.json of then names them.
  assert.equal(releaseType("android/ember-890.apk"), "application/vnd.android.package-archive");
  assert.equal(releaseType("android/other-890.apk"), null);
  assert.equal(releaseType("android/../secret"), null);
  assert.equal(releaseType("desktop/other.zip"), null);
});

/**
 * Runs the installer on a machine made up in a temporary directory: its HOME, a release of a stand-in command (it says
 * what it was asked), and launchctl, curl and uname that say what they were asked (a Mac, whatever runs the test).
 */
function machine() {
  const root = mkdtempSync(join(tmpdir(), "install-test-"));
  const home = join(root, "home");
  const stub = join(root, "stub");
  const release = join(root, "release", "stillfail");
  mkdirSync(home, { recursive: true });
  mkdirSync(stub);
  mkdirSync(join(release, "bin"), { recursive: true });
  writeFileSync(join(release, "bin", "stillfail"), '#!/bin/sh\necho "stillfail $*" >> "$HOME/said"\n', { mode: 0o755 });
  symlinkSync("stillfail", join(release, "bin", "ember"));
  writeFileSync(join(release, "VERSION"), "new\n");
  execFileSync("tar", ["-czf", join(root, "release.tar.gz"), "-C", join(root, "release"), "stillfail"]);
  const tool = (name: string, body: string) => writeFileSync(join(stub, name), `#!/bin/sh\necho "${name} $*" >> "$HOME/said"\n${body}`, { mode: 0o755 });
  tool("launchctl", '[ "$1" = print ] && exit 1\nexit 0\n');
  tool("curl", `while [ $# -gt 0 ]; do [ "$1" = -o ] && cp "${join(root, "release.tar.gz")}" "$2"; shift; done\n`);
  tool("uname", '[ "$1" = -m ] && echo arm64 || echo Darwin\n');
  const run = (args: string[] = [], env: Record<string, string> = {}) => {
    const done = spawnSync("sh", ["-c", installScript("https://app.still.fail"), "sh", ...args], {
      // Only these: not the caller's (an agent's STILLFAIL_DATA or EMBER_DATA would aim it at the real station).
      env: { HOME: home, PATH: `${stub}:/usr/bin:/bin:/usr/sbin:/sbin`, ...env } as unknown as NodeJS.ProcessEnv,
      encoding: "utf8",
    });
    return { status: done.status, out: done.stdout + done.stderr, said: existsSync(join(home, "said")) ? readFileSync(join(home, "said"), "utf8") : "" };
  };
  return { root, home, run, done: () => rmSync(root, { recursive: true, force: true }) };
}

test("an install from before the rename is moved, not installed beside it", () => {
  const m = machine();
  try {
    const old = join(m.home, ".ember");
    mkdirSync(join(old, "mesh"), { recursive: true });
    mkdirSync(join(old, "app", "bin"), { recursive: true });
    writeFileSync(join(old, "mesh", "cloud.json"), '{"origin": "https://ember.3720.org"}');
    writeFileSync(join(old, "ember.db"), "the store");
    mkdirSync(join(m.home, "Library", "LaunchAgents"), { recursive: true });
    writeFileSync(join(m.home, "Library", "LaunchAgents", "org.3720.ember.station.plist"), "<plist/>");
    mkdirSync(join(m.home, ".local", "bin"), { recursive: true });
    symlinkSync(join(old, "app", "bin", "ember"), join(m.home, ".local", "bin", "ember"));

    // Run from an agent of the old station: its environment says the old place.
    const first = m.run([], { EMBER_DATA: old });
    assert.equal(first.status, 0, first.out);
    const data = join(m.home, ".stillfail");
    assert.ok(lstatSync(data).isDirectory());
    assert.equal(readFileSync(join(data, "ember.db"), "utf8"), "the store");
    assert.equal(readlinkSync(old), data, "a link left at the old place");
    assert.equal(readFileSync(join(data, "app", "VERSION"), "utf8"), "new\n");
    const agents = join(m.home, "Library", "LaunchAgents");
    assert.ok(!existsSync(join(agents, "org.3720.ember.station.plist")), "the old service's definition removed");
    const plist = readFileSync(join(agents, "fail.still.station.plist"), "utf8");
    assert.match(plist, new RegExp(`<string>${data}/app/bin/stillfail</string><string>start</string>`));
    assert.match(plist, new RegExp(`<key>STILLFAIL_DATA</key><string>${data}</string>`));
    assert.match(first.said, /launchctl bootout gui\/\d+\/org\.3720\.ember\.station/);
    assert.match(first.said, /launchctl bootstrap gui\/\d+ .*fail\.still\.station\.plist/);
    assert.match(first.said, /curl .*\/releases\/stillfail-station-darwin-arm64\.tar\.gz/);
    for (const name of ["stillfail", "ember"]) assert.equal(readlinkSync(join(m.home, ".local", "bin", name)), join(data, "app", "bin", "stillfail"));

    // Again: nothing more moves.
    const again = m.run();
    assert.equal(again.status, 0, again.out);
    assert.equal(readlinkSync(old), data);
    assert.equal(readFileSync(join(data, "ember.db"), "utf8"), "the store");
    assert.doesNotMatch(again.out, /搬/);
  } finally {
    m.done();
  }
});

test("with both places there the new one is used and the old one left; a fresh machine gets only the new one", () => {
  const both = machine();
  try {
    mkdirSync(join(both.home, ".ember"), { recursive: true });
    writeFileSync(join(both.home, ".ember", "config.json"), "old");
    mkdirSync(join(both.home, ".stillfail", "mesh"), { recursive: true });
    writeFileSync(join(both.home, ".stillfail", "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    const done = both.run();
    assert.equal(done.status, 0, done.out);
    assert.ok(lstatSync(join(both.home, ".ember")).isDirectory());
    assert.equal(readFileSync(join(both.home, ".ember", "config.json"), "utf8"), "old");
    assert.ok(existsSync(join(both.home, ".stillfail", "app", "VERSION")));
  } finally {
    both.done();
  }
  const fresh = machine();
  try {
    const done = fresh.run(["tok"]);
    assert.equal(done.status, 0, done.out);
    assert.ok(existsSync(join(fresh.home, ".stillfail", "app", "VERSION")));
    assert.ok(!existsSync(join(fresh.home, ".ember")));
    assert.match(done.said, /stillfail station enroll https:\/\/app\.still\.fail tok/);
  } finally {
    fresh.done();
  }
});

test("the release says which channel it came from, for the station to go back from the beta", () => {
  const m = machine();
  try {
    const beta = m.run(["tok"], { STILLFAIL_CHANNEL: "beta" });
    assert.equal(beta.status, 0, beta.out);
    assert.match(beta.said, /curl .*\/releases\/beta\/stillfail-station-darwin-arm64\.tar\.gz/);
    assert.equal(readFileSync(join(m.home, ".stillfail", "app", "CHANNEL"), "utf8"), "beta\n");
    // In a workspace now: updated without a token, on a channel it does not know (the stable one).
    mkdirSync(join(m.home, ".stillfail", "mesh"), { recursive: true });
    writeFileSync(join(m.home, ".stillfail", "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    const stable = m.run([], { STILLFAIL_CHANNEL: "anything" });
    assert.equal(stable.status, 0, stable.out);
    assert.equal(readFileSync(join(m.home, ".stillfail", "app", "CHANNEL"), "utf8"), "stable\n");
  } finally {
    m.done();
  }
});
