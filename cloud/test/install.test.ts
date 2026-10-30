import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createHash } from "node:crypto";
import { bundledInstallScript, installScript, releaseType } from "../src/install.ts";

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
  assert.match(script, /if \[ -n "\$pid" \] && \[ -z "\$migrate" \] && \[ -n "\$\(said handoff\)" \] && \[ -n "\$\(said renew\)" \] && same_service; then/);
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
  // The Mac app's own updater's feeds (mbui's, in the Electron app's place), naming the zips above.
  assert.equal(releaseType("mac/latest.json"), "application/json");
  assert.equal(releaseType("mac/beta/latest.json"), "application/json");
  assert.equal(releaseType("mac/other/latest.json"), null);
  // and the Windows one's (mbui's, the beta's first), naming the installers below.
  assert.equal(releaseType("win/latest.json"), "application/json");
  assert.equal(releaseType("win/beta/latest.json"), "application/json");
  assert.equal(releaseType("win/other/latest.json"), null);
  // The Windows app's: its feed (named by the channel alone), its installer and that one's blockmap.
  assert.equal(releaseType("desktop/stillfail.yml"), "text/yaml; charset=utf-8");
  assert.equal(releaseType("desktop/stillfail-beta.yml"), "text/yaml; charset=utf-8");
  assert.equal(releaseType("desktop/web/stillfail-beta-web.json"), "application/json");
  assert.equal(releaseType("desktop/web/stillfail-beta-web-0.1.3000.tar.gz"), "application/gzip");
  assert.equal(releaseType("desktop/web/../station.json"), null);
  assert.equal(releaseType("desktop/stillfail-0.1.2400-x64-win.exe"), "application/vnd.microsoft.portable-executable");
  assert.equal(releaseType("desktop/stillfail-beta-0.1.2400-x64-win.exe.blockmap"), "application/octet-stream");
  assert.equal(releaseType("desktop/stillfail-0.1.2400-arm64-win.exe"), null);
  assert.equal(releaseType("desktop/other.yml"), null);
  // The old app's feed is not served: it is replaced by hand.
  assert.equal(releaseType("desktop/latest-mac.yml"), null);
  assert.equal(releaseType("desktop/ember-0.1.1092-arm64-mac.zip"), null);
  assert.equal(releaseType("desktop/other-mac.yml"), null);
  // The modules' packages: each one's feeds and its archives, one for every machine or a platform's.
  assert.equal(releaseType("modules/media/media.json"), "application/json");
  assert.equal(releaseType("modules/media/media-beta.json"), "application/json");
  assert.equal(releaseType("modules/media/media-0.1.3600.tar.gz"), "application/gzip");
  assert.equal(releaseType("modules/media/media-0.1.3600-linux-x64.tar.gz"), "application/gzip");
  for (const file of ["modules/media/books.json", "modules/media/books-0.1.3600.tar.gz", "modules/media/media-0.1.3600-other.tar.gz", "modules/media/media-1.tar.gz", "modules/my-mod/my-mod.json", "modules/media/x/media.json", "modules/media.json"]) {
    assert.equal(releaseType(file), null, file);
  }
  // The prebuilt native parts (scripts/native.ts prebuild), by part, target and key.
  assert.equal(releaseType("natives/shell-win32-x64-e873ee4f2e77b28f78c16a38.tar.gz"), "application/gzip");
  assert.equal(releaseType("natives/engine-win32-x64-95311552b24140105c1a54aa.tar.gz"), "application/gzip");
  for (const file of ["natives/shell-win32-x64-e873.tar.gz", "natives/shell-other-e873ee4f2e77b28f78c16a38.tar.gz", "natives/../station.json", "natives/x/shell-win32-x64-e873ee4f2e77b28f78c16a38.tar.gz"]) {
    assert.equal(releaseType(file), null, file);
  }
  // The relays' iroh-relay (.github/workflows/relay.yml), by the iroh commit it is built from.
  assert.equal(releaseType("relay/iroh-relay-43a6892ffe0689de0cf2545e3a8f3d567146b408-linux-x64"), "application/octet-stream");
  for (const file of ["relay/iroh-relay-43a6892f-linux-x64", "relay/iroh-relay-43a6892ffe0689de0cf2545e3a8f3d567146b408-darwin-arm64", "relay/../station.json"]) {
    assert.equal(releaseType(file), null, file);
  }
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
 * `os` "linux" or "wsl" makes it a Linux (x64) instead, with a systemd for the user (`systemd`) or none; "wsl" is
 * Windows' Linux (its kernel says microsoft) with Windows' cmd.exe and wslpath, its drive C: in <root>/c.
 */
function machine(os: "mac" | "linux" | "wsl" = "mac", systemd = true) {
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
  if (os === "mac") tool("uname", '[ "$1" = -m ] && echo arm64 || echo Darwin\n');
  else tool("uname", '[ "$1" = -m ] && echo x86_64 || echo Linux\n');
  const osrelease = join(root, "osrelease");
  writeFileSync(osrelease, os === "wsl" ? "6.6.87.2-microsoft-standard-WSL2\n" : "6.8.0-45-generic\n");
  tool("systemctl", systemd ? "exit 0\n" : "exit 1\n");
  tool("loginctl", "exit 0\n");
  if (os === "wsl") {
    mkdirSync(join(root, "c/Users/kim/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"), { recursive: true });
    tool("cmd.exe", 'case "$*" in *APPDATA*) printf \'%s\\r\\n\' \'C:\\Users\\kim\\AppData\\Roaming\' ;; esac\n');
    tool("wslpath", `case $1 in
  -u) printf '%s\\n' "$2" | sed -e 's#^C:#${root}/c#' -e 's#\\\\#/#g' ;;
  -w) printf '%s\\n' "$2" | sed -e 's#^${root}/c#C:#' -e 's#/#\\\\#g' ;;
esac
`);
    tool("pgrep", "exit 1\n");
  }
  const run = (args: string[] = [], env: Record<string, string> = {}, installer = installScript("https://app.still.fail")) => {
    const script = installer.replaceAll("/proc/sys/kernel/osrelease", osrelease);
    const done = spawnSync("sh", ["-c", script, "sh", ...args], {
      // Only these: not the caller's (an agent's STILLFAIL_DATA or EMBER_DATA would aim it at the real station).
      env: { HOME: home, PATH: `${stub}:/usr/bin:/bin:/usr/sbin:/sbin`, ...env } as unknown as NodeJS.ProcessEnv,
      encoding: "utf8",
    });
    return { status: done.status, out: done.stdout + done.stderr, said: existsSync(join(home, "said")) ? readFileSync(join(home, "said"), "utf8") : "" };
  };
  return { root, home, run, done: () => rmSync(root, { recursive: true, force: true }) };
}

test("in WSL the station runs without Windows' PATH, and Windows keeps WSL up from its sign-in on", () => {
  const m = machine("wsl");
  try {
    const done = m.run(["tok"], { WSL_DISTRO_NAME: "Ubuntu", PATH: `${join(m.root, "stub")}:/usr/bin:/bin:/mnt/c/Program Files/nodejs:/mnt/c/Windows` });
    assert.equal(done.status, 0, done.out);
    const unit = readFileSync(join(m.home, ".config/systemd/user/stillfail-station.service"), "utf8");
    const path = /^Environment=PATH=(.*)$/m.exec(unit)?.[1] ?? "";
    assert.match(path, /\/usr\/bin/);
    assert.doesNotMatch(path, /\/mnt\//, "none of Windows' directories");
    const keeper = join(m.root, "c/Users/kim/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/stillfail-station-Ubuntu.vbs");
    assert.equal(readFileSync(keeper, "utf8"), 'CreateObject("WScript.Shell").Run "wsl.exe -d ""Ubuntu"" --exec sleep 3153600000", 0, False\r\n');
    // Started now too, as at the next sign-in.
    assert.match(done.said, /cmd\.exe \/c wscript\.exe C:\\Users\\kim\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\stillfail-station-Ubuntu\.vbs/);
    assert.match(done.out, /stillfail-station-Ubuntu\.vbs/);
    assert.match(done.said, /systemctl --user enable stillfail-station\.service/);
  } finally {
    m.done();
  }
  const bare = machine("wsl", false);
  try {
    // No systemd: run in the background, and told how to turn it on (no keeper: nothing would start it with WSL).
    const done = bare.run(["tok"], { WSL_DISTRO_NAME: "Ubuntu" });
    assert.equal(done.status, 0, done.out);
    assert.match(done.out, /\/etc\/wsl\.conf/);
    assert.doesNotMatch(done.said, /wscript/);
  } finally {
    bare.done();
  }
  const linux = machine("linux");
  try {
    // Another Linux keeps its PATH as it is and hears nothing of WSL.
    const done = linux.run(["tok"], { PATH: `${join(linux.root, "stub")}:/usr/bin:/bin:/mnt/tools/bin` });
    assert.equal(done.status, 0, done.out);
    assert.match(readFileSync(join(linux.home, ".config/systemd/user/stillfail-station.service"), "utf8"), /^Environment=PATH=.*:\/mnt\/tools\/bin/m);
    // (its own words: the test's directory, named at random, may hold the letters too, as install-test-6JZWSL did)
    assert.doesNotMatch(done.out.replaceAll(linux.root, ""), /WSL/);
  } finally {
    linux.done();
  }
});

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
    assert.match(done.said, /stillfail station enroll https:\/\/app\.still\.fail tok --stay/);
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

test("a handover the new release cannot take leaves the station running on the old release, not restarted", () => {
  const m = machine();
  const data = join(m.home, ".stillfail");
  let pid = 0;
  try {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    assert.equal(m.run().status, 0, "installed, with its service");
    writeFileSync(join(data, "app", "VERSION"), "old\n");
    // The running station, as ps tells it: asked to hand over (SIGUSR2), it says its new Node did not come up.
    const fake = join(m.root, "stillfail-station");
    writeFileSync(
      fake,
      `#!/bin/sh\ntrap 'echo "the new release did not start" > "${data}/run/handoff-failed"' USR2\ntouch "${m.root}/listening"\nwhile :; do sleep 0.2; done\n`,
      { mode: 0o755 },
    );
    // Not this process's child (the installer runs while this waits, so none is reaped here): one that has ended goes.
    pid = Number(execFileSync("sh", ["-c", `"${fake}" </dev/null >/dev/null 2>&1 & echo $!`], { encoding: "utf8" }));
    while (!existsSync(join(m.root, "listening"))) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    mkdirSync(join(data, "run"), { recursive: true });
    const said = `{"pid": ${pid}, "startedAt": 1700000000000, "handoff": 1, "drain": 1, "renew": 1}`;
    writeFileSync(join(data, "run", "station.json"), said);
    writeFileSync(join(m.home, "said"), "");

    const update = m.run();
    assert.equal(update.status, 1, update.out);
    assert.match(update.out, /the new release did not start/);
    assert.match(update.out, /无法交接.*station 继续使用原版本运行|Couldn't hand over.*keeps running the previous version/);
    assert.equal(readFileSync(join(data, "app", "VERSION"), "utf8"), "old\n", "the old release back in its place");
    assert.ok(!existsSync(join(data, "app.old")) && !existsSync(join(data, "app.failed")));
    assert.ok(process.kill(pid, 0), "the station still runs");
    assert.doesNotMatch(update.said, /launchctl (bootout|bootstrap)/, "and is not restarted");
    assert.equal(readFileSync(join(data, "run", "station.json"), "utf8"), said);
  } finally {
    if (pid) process.kill(pid, "SIGKILL");
    m.done();
  }
});

test("a station whose launcher would not become the new release's own is restarted once, not handed over", () => {
  const m = machine();
  const data = join(m.home, ".stillfail");
  let pid = 0;
  try {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    assert.equal(m.run().status, 0, "installed, with its service");
    writeFileSync(join(data, "app", "VERSION"), "old\n");
    // A launcher from before (its station.json says no renew): it hands over to new Nodes, itself never changed.
    const fake = join(m.root, "stillfail-station");
    writeFileSync(
      fake,
      `#!/bin/sh\ntrap 'echo handover >> "${m.root}/told"' USR2\ntrap 'echo drain >> "${m.root}/told"; echo idle > "${data}/run/drained"' USR1\ntouch "${m.root}/listening"\nwhile :; do sleep 0.2; done\n`,
      { mode: 0o755 },
    );
    pid = Number(execFileSync("sh", ["-c", `"${fake}" </dev/null >/dev/null 2>&1 & echo $!`], { encoding: "utf8" }));
    while (!existsSync(join(m.root, "listening"))) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    mkdirSync(join(data, "run"), { recursive: true });
    writeFileSync(join(data, "run", "station.json"), `{"pid": ${pid}, "startedAt": 1700000000000, "handoff": 1, "drain": 1, "channel": 1}`);
    writeFileSync(join(m.home, "said"), "");

    const update = m.run();
    assert.equal(update.status, 0, update.out);
    assert.equal(readFileSync(join(m.root, "told"), "utf8"), "drain\n", "drained, never asked to hand over");
    assert.match(update.said, /launchctl bootout/);
    assert.match(update.said, /launchctl bootstrap/);
    assert.equal(readFileSync(join(data, "app", "VERSION"), "utf8"), "new\n");
  } finally {
    if (pid) process.kill(pid, "SIGKILL");
    m.done();
  }
});

const sha256Of = (file: string) => createHash("sha256").update(readFileSync(file)).digest("hex");

test("a station updating itself installs only the release its signed words name, by that release's own installer", () => {
  const m = machine();
  const data = join(m.home, ".stillfail");
  try {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    // The release carries its installer (scripts/installers.ts), here one that says it ran and what it was handed.
    const own = bundledInstallScript("zh").replace("set -eu\n", 'set -eu\necho "its own installer: $STILLFAIL_INSTALLER_HANDED $(basename "$STILLFAIL_ARCHIVE")" >> "$HOME/said"\n');
    const release = join(m.root, "release", "stillfail");
    writeFileSync(join(release, "bin", "install.zh.sh"), own);
    execFileSync("tar", ["-czf", join(m.root, "release.tar.gz"), "-C", join(m.root, "release"), "stillfail"]);
    const sha = sha256Of(join(m.root, "release.tar.gz"));
    const bundled = bundledInstallScript("zh");
    const told = { STILLFAIL_ORIGIN: "https://releases.test", STILLFAIL_INSTALL_LANG: "zh" };

    // Not where the station names (no STILLFAIL_ORIGIN): nothing.
    assert.notEqual(m.run([], {}, bundled).status, 0);
    // A download that is not the signed release: not installed.
    const bad = m.run([], { ...told, STILLFAIL_RELEASE_SHA256: "0".repeat(64) }, bundled);
    assert.equal(bad.status, 1, bad.out);
    assert.match(bad.out, /与签名不符/);
    assert.ok(!existsSync(join(data, "app")), "nothing installed");
    assert.match(bad.said, /curl .*https:\/\/releases\.test\/releases\/stillfail-station-darwin-arm64\.tar\.gz/);

    // The signed one: downloaded once, then installed by the installer it carries, handed the download.
    writeFileSync(join(m.home, "said"), "");
    const good = m.run([], { ...told, STILLFAIL_RELEASE_SHA256: sha }, bundled);
    assert.equal(good.status, 0, good.out);
    assert.equal(readFileSync(join(data, "app", "VERSION"), "utf8"), "new\n");
    assert.match(good.said, /its own installer: 1 stillfail\.tar\.gz/);
    assert.equal(good.said.match(/^curl /gm)?.length, 1, good.said);
    // The download it was handed is gone with its directory.
    assert.deepEqual(readdirSync("/tmp").filter((f) => f.startsWith("stillfail-handed.") && existsSync(join("/tmp", f, "stillfail.tar.gz")) && sha256Of(join("/tmp", f, "stillfail.tar.gz")) === sha), []);
  } finally {
    m.done();
  }
});

test("a station updating itself runs on the Node its signed words name, the machine's own only when it is that one", () => {
  const m = machine();
  const data = join(m.home, ".stillfail");
  try {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    const release = join(m.root, "release", "stillfail");
    writeFileSync(join(release, "NODE_VERSION"), "24.21.0\n");
    execFileSync("tar", ["-czf", join(m.root, "release.tar.gz"), "-C", join(m.root, "release"), "stillfail"]);
    // The Node, as node-dist.sh keeps it (bin/node in a tarball): a stand-in that says its version.
    const dist = join(m.root, "node");
    mkdirSync(join(dist, "bin"), { recursive: true });
    writeFileSync(join(dist, "bin", "node"), '#!/bin/sh\necho v24.21.0\n', { mode: 0o755 });
    execFileSync("tar", ["-czf", join(m.root, "node.tar.gz"), "-C", dist, "bin/node"]);
    const stub = join(m.root, "stub");
    writeFileSync(join(stub, "curl"), `#!/bin/sh\necho "curl $*" >> "$HOME/said"\nwhile [ $# -gt 1 ]; do\n  case "$1" in */releases/node/*) node=yes ;; esac\n  [ "$1" = -o ] && { [ -n "\${node:-}" ] && cp "${join(m.root, "node.tar.gz")}" "$2" || cp "${join(m.root, "release.tar.gz")}" "$2"; }\n  shift\ndone\n`, { mode: 0o755 });
    const told = { STILLFAIL_ORIGIN: "https://releases.test", STILLFAIL_RELEASE_SHA256: sha256Of(join(m.root, "release.tar.gz")) };
    const bundled = bundledInstallScript("zh");

    const bad = m.run([], { ...told, STILLFAIL_NODE_SHA256: "0".repeat(64) }, bundled);
    assert.equal(bad.status, 1, bad.out);
    assert.match(bad.out, /Node 24\.21\.0 校验失败/);
    assert.deepEqual(readdirSync(join(data, "node")), [], "nothing of it left");
    // No .sha256 asked for: the signed hash is the binary's own.
    assert.doesNotMatch(bad.said, /\.sha256/);

    // A machine's own node of that version that is not that very binary is not taken.
    const ownBin = join(m.root, "own");
    mkdirSync(ownBin);
    writeFileSync(join(ownBin, "node"), '#!/bin/sh\n# another build\necho v24.21.0\n', { mode: 0o755 });
    const good = m.run([], { ...told, STILLFAIL_NODE_SHA256: sha256Of(join(dist, "bin", "node")), PATH: `${stub}:${ownBin}:/usr/bin:/bin:/usr/sbin:/sbin` }, bundled);
    assert.equal(good.status, 0, good.out);
    assert.equal(readFileSync(join(data, "node", "v24.21.0", "bin", "node"), "utf8"), readFileSync(join(dist, "bin", "node"), "utf8"));
    assert.match(good.said, /curl .*\/releases\/node\/node-v24\.21\.0-darwin-arm64\.tar\.gz/);
  } finally {
    m.done();
  }
});

test("a Node another install put there meanwhile is the one kept, and nothing half-made is left beside it", () => {
  const m = machine();
  const data = join(m.home, ".stillfail");
  try {
    mkdirSync(join(data, "mesh"), { recursive: true });
    writeFileSync(join(data, "mesh", "cloud.json"), '{"origin": "https://app.still.fail"}');
    const release = join(m.root, "release", "stillfail");
    writeFileSync(join(release, "NODE_VERSION"), "24.21.0\n");
    execFileSync("tar", ["-czf", join(m.root, "release.tar.gz"), "-C", join(m.root, "release"), "stillfail"]);
    // A stand-in that, asked its version from where this install unpacked it, has the other install (the station's own
    // update, say) finish first: node/v24.21.0 is there by the time this one would move its own in.
    const dist = join(m.root, "node");
    mkdirSync(join(dist, "bin"), { recursive: true });
    const theirs = '#!/bin/sh\necho v24.21.0 # theirs\n';
    writeFileSync(join(dist, "bin", "node"), `#!/bin/sh\nd="$(cd "$(dirname "$0")/../.." && pwd)/v24.21.0"\n[ -x "$d/bin/node" ] || { mkdir -p "$d/bin"; printf '%s' '${theirs}' > "$d/bin/node"; chmod +x "$d/bin/node"; }\necho v24.21.0\n`, { mode: 0o755 });
    execFileSync("tar", ["-czf", join(m.root, "node.tar.gz"), "-C", dist, "bin/node"]);
    const stub = join(m.root, "stub");
    writeFileSync(join(stub, "curl"), `#!/bin/sh\nwhile [ $# -gt 1 ]; do\n  case "$1" in */releases/node/*) node=yes ;; esac\n  [ "$1" = -o ] && { [ -n "\${node:-}" ] && cp "${join(m.root, "node.tar.gz")}" "$2" || cp "${join(m.root, "release.tar.gz")}" "$2"; }\n  shift\ndone\n`, { mode: 0o755 });
    const run = m.run([], {
      STILLFAIL_ORIGIN: "https://releases.test", STILLFAIL_RELEASE_SHA256: sha256Of(join(m.root, "release.tar.gz")),
      STILLFAIL_NODE_SHA256: sha256Of(join(dist, "bin", "node")), PATH: `${stub}:/usr/bin:/bin:/usr/sbin:/sbin`,
    }, bundledInstallScript("zh"));
    assert.equal(run.status, 0, run.out);
    assert.deepEqual(readdirSync(join(data, "node")), ["v24.21.0"]);
    assert.deepEqual(readdirSync(join(data, "node", "v24.21.0")), ["bin"]);
    assert.equal(readFileSync(join(data, "node", "v24.21.0", "bin", "node"), "utf8"), theirs);
  } finally {
    m.done();
  }
});
