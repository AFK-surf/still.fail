// The station's and its runtimes' versions and updating them (the Rust station's updates.rs's tests), with fake release
// servers, fake installers and fake npm/vp/curl commands in temporary directories: nothing real is installed or read.
import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { type Env, type Found, howToInstall, howToUpdate, findCommand, ownNode, pinNpmVersion, run, runLines, Unable, kindCommand, kindPackage } from "../src/updates/runtimes.ts";
import { hold } from "../src/updates/holds.ts";
import { Updates, type UpdatesOptions } from "../src/updates/updates.ts";
import { WINDOWS, platform as machine } from "../src/platform/index.ts";
import { windowsUpdateScript, wingetPackage } from "../src/platform/windows.ts";
import {
  channelOf, curlPercent, downloading, feed, INSTALLING, newer, offer, releaseChannel, say, stationDownloadPercent, stationVersion, stepOf, tail, versionIn,
} from "../src/updates/versions.ts";
import { setChannelIn } from "../src/updates/channel.ts";
import { exe, launcher, script as stand_in } from "./accounts-fakes.ts";
import { OTHER, SHA_A, SHA_B, feedOf, trusted } from "./release-fakes.ts";
import { settle, testClock } from "./hub-fakes.ts";

delete process.env.STILLFAIL_CONFIG;
delete process.env.EMBER_CONFIG;

const temp = () => realpathSync(mkdtempSync(join(tmpdir(), "stillfail-updates-")));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `f` holds: what real processes, files and sockets do has no event here. No deadline (it
/// comes, however slow the machine, or the test hangs).
async function until(_what: string, f: () => boolean) {
  while (!f()) await sleep(20);
}
/// An executable script at `path` (a shell one by the launcher the stand-ins share: see accounts-fakes.ts).
const script = (path: string, text: string) => {
  mkdirSync(dirname(path), { recursive: true });
  stand_in(path, text);
};

/// A station installed by the installer (<data>/app, BUILD `build`, from `channel`, carrying `installer` as its
/// bin/install.zh.sh), in a cloud that answers nothing; it takes the tests' release key.
function installed(data: string, build: string, channel: string | null, more: Partial<UpdatesOptions> = {}, installer?: string): Updates {
  const app = join(data, "app");
  mkdirSync(join(app, "bin"), { recursive: true });
  writeFileSync(join(app, "BUILD"), build);
  if (channel !== null) writeFileSync(join(app, "CHANNEL"), channel);
  if (installer !== undefined) writeFileSync(join(app, "bin", "install.zh.sh"), installer);
  const updates = new Updates({
    app, data, config: new ConfigFile(data), origin: () => "http://127.0.0.1:1", registry: "http://127.0.0.1:1", devinManifest: "http://127.0.0.1:1", env: { PATH: "/nowhere" },
    timing: { followLook: 200 }, trusted, ...more,
  });
  return updates;
}

const station = (u: Updates) => u.get("zh")[0]!;

/// A PATH of `bin` and the system's commands.
const withSystem = (bin: string) => (WINDOWS ? `${bin};${process.env.SystemRoot ?? "C:\\Windows"}\\System32` : `${bin}:/usr/bin:/bin`);

/// A server answering `routes` (path → status and body, or a function of the request's path and query).
type Said = { status?: number; type?: string; body: string | Buffer } | null;
async function serve(routes: (path: string, search: string) => Said | Promise<Said>): Promise<[string, Server]> {
  const server = createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://x");
    const said = await routes(url.pathname, url.search);
    if (said === null) return void res.writeHead(404).end("no");
    const body = typeof said.body === "string" ? Buffer.from(said.body) : said.body;
    res.writeHead(said.status ?? 200, { "content-type": said.type ?? "application/json", "content-length": body.length }).end(body);
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  return [`http://127.0.0.1:${(server.address() as AddressInfo).port}`, server];
}

/// A still.fail cloud with a release out (`latest` on the stable feed, signed with the tests' key; `feed` instead when
/// given), and the installer the station's release carries (the last of what this gives), playing the real one's part
/// on a temporary data directory: says its steps and what it was told, puts the new BUILD in the release, ends 0. Its
/// download goes on until `finish` is called (asking the cloud for /download, which answers then); unless `held`, it
/// goes on at once.
async function cloudWithRelease(latest: string, build: string, held = false, feed?: object): Promise<[string, Server, string[], () => void, string]> {
  const asked: string[] = [];
  let finish = () => {};
  const finished = held ? new Promise<void>((r) => (finish = r)) : Promise.resolve();
  let origin = "";
  const installer = () => `#!/bin/sh
set -eu
run="$STILLFAIL_DATA/run"
printf 'download\\n' > "$run/update.step"
echo "### 50.0%"
printf '%s %s %s\\n' "$STILLFAIL_CHANNEL" "$EMBER_DATA" "$STILLFAIL_DATA" > "$STILLFAIL_DATA/installer-saw"
printf '%s %s %s %s\\n' "$STILLFAIL_ORIGIN" "$STILLFAIL_RELEASE_SHA256" "$STILLFAIL_NODE_SHA256" "$STILLFAIL_INSTALL_LANG" >> "$STILLFAIL_DATA/installer-saw"
echo ran >> "$STILLFAIL_DATA/installer-ran"
curl -fsS "${origin}/download" > /dev/null
printf 'handoff\\n' > "$run/update.step"
printf '${build}\\n' > "$STILLFAIL_DATA/app/BUILD"
`;
  const [base, server] = await serve(async (path, search) => {
    asked.push(path + search);
    if (path === "/releases/station.json") return { body: JSON.stringify(feed ?? feedOf(Number(latest.split(".").at(-1)))) };
    if (path === "/download") return finished.then(() => ({ type: "text/plain", body: "" }));
    return null;
  });
  origin = base;
  return [origin, server, asked, finish, installer()];
}

/// A registry with Codex 0.47.0 out, its build for this machine downloadable; and a bin with a fake npm that records
/// what it is asked and, asked to install, puts a `codex` saying `version` beside itself (none: it installs nothing).
async function codexWorld(version: string | null): Promise<[string, Server, string, string]> {
  const tarball = Buffer.alloc(300_000, 1);
  let base = "";
  const [registry, server] = await serve((path) => {
    if (path === "/@openai/codex/latest") return { body: JSON.stringify({ version: "0.47.0" }) };
    if (path.startsWith("/@openai/codex/0.47.0-")) return { body: JSON.stringify({ dist: { tarball: `${base}/codex.tgz` } }) };
    if (path === "/codex.tgz") return { type: "application/octet-stream", body: tarball };
    if (path === "/@anthropic-ai/claude-code/latest") return { body: JSON.stringify({ version: "2.1.300" }) };
    return null;
  });
  base = registry;
  const bin = join(temp(), "bin");
  const said = join(dirname(bin), "npm-asked");
  // On Windows what is installed is a .cmd (as npm's shims are), written by Git's sh: its paths with /.
  const [b, s] = [bin, said].map((p) => p.replaceAll("\\", "/"));
  const codex = WINDOWS ? `printf '@echo codex-cli ${version}\\r\\n' > "${b}/codex.cmd"` : `printf '#!/bin/sh\\necho "codex-cli ${version}"\\n' > "${b}/codex.sh"; /bin/ln "${launcher()}" "${b}/codex"`;
  script(join(bin, "npm"), `#!/bin/sh
echo "$*" >> "${s}"
if [ "$1" = install ]; then
  echo "==> Downloading codex"
  ${version === null ? ":" : codex}
  echo "added 1 package"
fi
exit 0
`);
  return [registry, server, bin, said];
}

const found = (real: string): Found => ({ onPath: "/nowhere/bin/x", real });

describe("updates", { concurrency: true }, () => {
  test("an install says where it is as it goes", async () => {
    const env: Env = { PATH: "/usr/bin:/bin" };
    const steps: string[] = [];
    const program = "console.log('==> Downloading https://x'); console.log('==> Pouring codex'); console.error('Warning: x'); process.exitCode = 3";
    const [ok, said, code] = await runLines(process.execPath, ["-e", program], env, 10_000, (line) => {
      const s = stepOf(line);
      if (s) steps.push(say(s, "zh"));
    });
    assert.deepEqual([ok, code], [false, 3]);
    assert.deepEqual(steps, ["正在下载", say(INSTALLING, "zh")]);
    // Both streams kept (their order between them is not known).
    assert.ok(said.includes("==> Pouring codex") && said.includes("Warning: x"));
    assert.deepEqual(stepOf("Setting up Claude Code..."), INSTALLING);
    assert.equal(stepOf("added 2 packages in 4s"), null);
    const [a, p] = downloading("0.159.3", 60_000_000, 133_847_481);
    assert.deepEqual([say(a, "zh"), p], ["正在下载 0.159.3（134 MB）", 44]);
    const [b, q] = downloading("0.159.3", 60_000_000, null);
    assert.deepEqual([say(b, "zh"), q], ["正在下载 0.159.3：已下载 60 MB", null]);
  });

  test("versions compare number by number", () => {
    assert.ok(newer("2.1.9", "2.1.10"));
    assert.ok(!newer("2.1.10", "2.1.9"));
    assert.ok(!newer("0.1.1200", "0.1.1200"));
    assert.ok(newer("0.46.0", "0.47.0-alpha.1"));
  });

  test("a version is read from what the command says", () => {
    assert.equal(versionIn("2.1.284 (Claude Code)"), "2.1.284");
    assert.equal(versionIn("codex-cli 0.46.0\n"), "0.46.0");
    assert.equal(versionIn("nothing here"), null);
  });

  test("a release says its version and a clone none", () => {
    const dir = temp();
    assert.equal(stationVersion(dir), undefined);
    writeFileSync(join(dir, "BUILD"), "1234\n");
    assert.equal(stationVersion(dir), "0.1.1234");
  });

  test("the latest comes from the channel's feed and a station is on the channel it was installed from", () => {
    assert.equal(feed("stable", "https://app.still.fail"), "https://app.still.fail/releases/station.json");
    assert.equal(feed("beta", "https://app.still.fail"), "https://app.still.fail/releases/station-beta.json");
    const dir = temp();
    // An install from before channels, and a config that says none: stable.
    assert.equal(releaseChannel(dir), null);
    assert.equal(channelOf({}, dir), "stable");
    assert.equal(channelOf({ updateChannel: "nonsense" }, dir), "stable");
    // Installed from the beta: on it, until the config says otherwise.
    writeFileSync(join(dir, "CHANNEL"), "beta\n");
    assert.equal(channelOf({}, dir), "beta");
    assert.equal(channelOf({ updateChannel: "stable" }, dir), "stable");
    assert.equal(channelOf({ updateChannel: "beta" }, dir), "beta");
  });

  test("an older version is offered only back from the beta", () => {
    // Newer is newer on either channel.
    assert.deepEqual(offer("0.1.10", "0.1.12", "stable", "stable"), [true, false]);
    assert.deepEqual(offer("0.1.10", "0.1.12", "beta", "stable"), [true, false]);
    // A stable station never goes back by itself, nor a beta one to an older beta.
    assert.deepEqual(offer("0.1.12", "0.1.10", "stable", "stable"), [false, false]);
    assert.deepEqual(offer("0.1.12", "0.1.10", "beta", "beta"), [false, false]);
    // Switched back from the beta: the older stable release is offered, as going back.
    assert.deepEqual(offer("0.1.12", "0.1.10", "stable", "beta"), [false, true]);
    // The same build (a beta promoted): nothing.
    assert.deepEqual(offer("0.1.12", "0.1.12", "stable", "beta"), [false, false]);
    assert.deepEqual(offer(null, "0.1.10", "stable", "beta"), [false, false]);
    assert.deepEqual(offer("0.1.12", null, "stable", "beta"), [false, false]);
  });

  test("an update started before a handover is followed to its end", async (t) => {
    const dir = temp();
    const runDir = join(dir, "run");
    mkdirSync(runDir, { recursive: true });
    // Started by the release this one took over from, which was 0.1.1299; the installer is handing over.
    writeFileSync(join(runDir, "update.started"), JSON.stringify({ at: Date.now(), from: "0.1.1299" }));
    writeFileSync(join(runDir, "update.step"), "handoff\n");
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    updates.countRunning(() => 2);
    updates.followStarted();
    assert.deepEqual([station(updates).state, station(updates).progress], ["updating", "正在交接给新版本（agent 不中断）"]);
    // Had it had to restart: what the drain waits on.
    writeFileSync(join(runDir, "update.step"), "drain\n");
    await until("draining", () => station(updates).progress === "等待 2 个 agent 完成本轮后重启（新消息将排队）");
    writeFileSync(join(runDir, "update.step"), "handoff\n");
    writeFileSync(join(runDir, "update.exit"), "0\n");
    await until("done", () => station(updates).state === "idle");
    const line = station(updates);
    assert.deepEqual([line.state, line.progress, line.done], ["idle", undefined, "已更新到 0.1.1300，agent 未中断"]);
    assert.ok(!existsSync(join(runDir, "update.started")) && !existsSync(join(runDir, "update.step")));
    // Read again (the next check), it still says so; and in English to an English page.
    await updates.check();
    assert.equal(station(updates).done, "已更新到 0.1.1300，agent 未中断");
    assert.equal(updates.get("en")[0]!.done?.includes("0.1.1300"), true);
  });

  test("an update started too long ago is not followed", async (t) => {
    const dir = temp();
    const runDir = join(dir, "run");
    mkdirSync(runDir, { recursive: true });
    writeFileSync(join(runDir, "update.started"), JSON.stringify({ at: Date.now() - 21 * 60_000, from: "0.1.1299" }));
    writeFileSync(join(runDir, "update.step"), "drain\n");
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    updates.followStarted();
    assert.equal(station(updates).state, "idle");
    assert.ok(!existsSync(join(runDir, "update.started")) && !existsSync(join(runDir, "update.step")));
  });

  test("the installer's download percent reads complete curl bars", () => {
    assert.equal(curlPercent("下载 still.fail station…\n\r                 0.0%"), 0);
    assert.equal(curlPercent("\r###   12.4%\r########   44.9%\r#########  45."), 44);
    assert.equal(curlPercent("\r######## 100.0%\n"), 100);
    for (const log of ["", "\r#=#=#", "error 44.0%", "### NaN%", "### 101.0%", "### -1.0%"]) assert.equal(curlPercent(log), null, log);
    const dir = temp();
    const log = join(dir, "update.log");
    assert.equal(stationDownloadPercent(log), null);
    writeFileSync(log, `${"old output\n".repeat(1000)}\r### 37.2%`);
    assert.equal(stationDownloadPercent(log), 37);
  });

  test("the station's download percent changes are told and cleared", async (t) => {
    const dir = temp();
    const runDir = join(dir, "run");
    mkdirSync(runDir, { recursive: true });
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    let told = 0;
    updates.changes(() => told++);
    writeFileSync(join(runDir, "update.step"), "download\n");
    writeFileSync(join(runDir, "update.log"), "\r### 12.4%");
    updates.follow({ at: Date.now(), from: "0.1.1300" });
    assert.equal(station(updates).percent, 12);
    writeFileSync(join(runDir, "update.log"), "\r### 12.4%\r######## 44.9%");
    await until("44%", () => station(updates).percent === 44);
    assert.ok(told >= 2);
    writeFileSync(join(runDir, "update.step"), "handoff\n");
    await until("handoff", () => station(updates).percent === undefined);
    assert.equal(station(updates).progress, "正在交接给新版本（agent 不中断）");
    writeFileSync(join(runDir, "update.exit"), "0\n");
    await until("ended", () => station(updates).state === "idle");
    assert.equal(station(updates).percent, undefined);
    // The same version as it started from: it says so.
    assert.equal(station(updates).done, "已是最新版本");
  });

  test("a failed installer says what it said last", async (t) => {
    const dir = temp();
    const runDir = join(dir, "run");
    mkdirSync(runDir, { recursive: true });
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    writeFileSync(join(runDir, "update.log"), "one\ntwo\nthree\nfour\nfive\n");
    updates.follow({ at: Date.now(), from: "0.1.1300" });
    writeFileSync(join(runDir, "update.exit"), "1\n");
    await until("failed", () => station(updates).state === "failed");
    assert.equal(station(updates).message, "two\nthree\nfour\nfive");
  });

  test("switched back from the beta the stable release is offered and kept in the config", async (t) => {
    const dir = temp();
    const updates = installed(dir, "1300", "beta");
    t.after(() => updates.close());
    assert.equal(updates.channel(), "beta");
    let line = updates.stationWith("0.1.1310");
    assert.deepEqual([line.channel, line.newer, line.downgrade], ["beta", true, false]);

    await updates.setChannel("stable");
    assert.equal(updates.channel(), "stable");
    assert.equal(JSON.parse(readFileSync(join(dir, "config.json"), "utf8")).updateChannel, "stable");
    // What was read from the beta's feed is not the stable one's.
    line = station(updates);
    assert.deepEqual([line.latest, line.newer, line.downgrade], [undefined, false, false]);
    line = updates.stationWith("0.1.1200");
    assert.deepEqual([line.channel, line.newer, line.downgrade], ["stable", false, true]);

    // A station that never was on the beta is not offered an older one.
    const other = temp();
    const stable = installed(other, "1300", null);
    t.after(() => stable.close());
    line = stable.stationWith("0.1.1200");
    assert.deepEqual([line.channel, line.newer, line.downgrade], ["stable", false, false]);
    // Read again in a new process from a config that says beta: the feed it reads is the beta's.
    setChannelIn(other, "beta");
    const again = installed(other, "1300", null);
    t.after(() => again.close());
    assert.equal(again.channel(), "beta");
  });

  test("turned on, the station updates itself to each newer release once", async (t) => {
    const dir = temp();
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    assert.equal(updates.stationWith("0.1.1310").auto, false);
    assert.equal(updates.toUpdateTo(), null, "not unless turned on");
    new ConfigFile(dir).update((raw) => (raw.autoUpdate = true));
    assert.equal(updates.stationWith("0.1.1310").auto, true);
    assert.equal(updates.toUpdateTo(), "0.1.1310");
    // Already the latest, or the latest is older: nothing.
    updates.stationWith("0.1.1300");
    assert.equal(updates.toUpdateTo(), null);
    updates.stationWith("0.1.1290");
    assert.equal(updates.toUpdateTo(), null);
    // A version it went for (and failed to get) is not tried again; the next one is.
    updates.tried = "0.1.1310";
    updates.stationWith("0.1.1310");
    assert.equal(updates.toUpdateTo(), null);
    updates.stationWith("0.1.1320");
    assert.equal(updates.toUpdateTo(), "0.1.1320");
    // While a runtime installs: not yet, nor by hand (a handover or restart would leave it unfollowed).
    updates.poke("codex", (i) => (i.updating = Date.now()));
    assert.equal(updates.toUpdateTo(), null);
    await assert.rejects(updates.update("station", "zh"), (e: Error) => e.message.includes("Codex 正在安装"));
    updates.poke("codex", (i) => (i.updating = null));
    assert.equal(updates.toUpdateTo(), "0.1.1320");
    // While an update goes on: nothing more, nor a runtime installed meanwhile.
    updates.poke("station", (i) => (i.updating = Date.now()));
    assert.equal(updates.toUpdateTo(), null);
    await assert.rejects(updates.update("codex", "zh"), (e: Error) => e.message.includes("station 正在更新"));

    // Switched back from the beta, the older stable release is offered, but not gone to by itself.
    const other = temp();
    const beta = installed(other, "1300", "beta");
    t.after(() => beta.close());
    new ConfigFile(other).update((raw) => {
      raw.autoUpdate = true;
      raw.updateChannel = "stable";
    });
    assert.ok(beta.stationWith("0.1.1200").downgrade);
    assert.equal(beta.toUpdateTo(), null);
  });

  test("automatic updates do not wait for running turns or people using the station", async (t) => {
    const dir = temp();
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    new ConfigFile(dir).update((raw) => (raw.autoUpdate = true));
    updates.stationWith("0.1.1310");
    // A turn running (a Slack one too): it is handed over, not waited for.
    updates.countRunning(() => 1);
    assert.equal(updates.toUpdateTo(), "0.1.1310");
  });

  test("an automatic update waits for a command run with a vault grant, whose proxy would go with this process", async (t) => {
    const dir = temp();
    const updates = installed(dir, "1300", null);
    t.after(() => updates.close());
    new ConfigFile(dir).update((raw) => (raw.autoUpdate = true));
    updates.stationWith("0.1.1310");
    const first = hold(), second = hold();
    assert.equal(updates.toUpdateTo(), null);
    first();
    first();
    assert.equal(updates.toUpdateTo(), null, "one still runs (letting go twice is once)");
    second();
    assert.equal(updates.toUpdateTo(), "0.1.1310");
  });

  // The installer here is install.sh, run by sh; Windows' (install.ps1, by a scheduled task) is the next test's.
  const shInstaller = { skip: WINDOWS && "install.sh is macOS's and Linux's" };

  test("on Windows the update's script runs the release's install.ps1, its words in UTF-8 and its exit kept", { skip: !WINDOWS && "Windows'" }, async () => {
    const dir = temp();
    const run = join(dir, "run 'x'");
    mkdirSync(run);
    // The release's installer, as startInstaller copies it there.
    writeFileSync(join(run, "install.ps1"), String.fromCharCode(0xfeff) + [
      "Write-Host ('下载 still.fail station… ' + $env:STILLFAIL_CHANNEL + ' ' + $env:STILLFAIL_DATA + ' ' + $env:STILLFAIL_RELEASE_SHA256)",
      "[Console]::Error.WriteLine('没能更新')",
      "exit 3",
    ].join("\r\n"));
    const env = { STILLFAIL_DATA: dir, STILLFAIL_CHANNEL: "beta", STILLFAIL_RELEASE_SHA256: SHA_A, PATH: "C:\\nowhere" };
    const ps1 = join(run, "update.ps1");
    const text = windowsUpdateScript(run, env, "still.fail station (test, not registered) update");
    // Only the station's own variables: the task has the user's PATH.
    assert.ok(!text.includes("nowhere"));
    writeFileSync(ps1, text);
    // Run here as the task runs it (no task: its removal at the end finds none).
    await new Promise<void>((resolve, reject) =>
      execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ps1], { timeout: 60_000 }, (e, _out, err) => (e ? reject(new Error(`${e.message} ${err}`)) : resolve())),
    );
    assert.equal(readFileSync(join(run, "update.exit"), "utf8").trim(), "3");
    const log = readFileSync(join(run, "update.log"), "utf8");
    assert.ok(log.includes(`下载 still.fail station… beta ${dir} ${SHA_A}`), log);
    assert.ok(log.includes("没能更新"), log);
  });

  test("the station is updated by the installer its release carries, told what the signed release hashes to, followed to its end", shInstaller, async (t) => {
    const dir = temp();
    const [origin, server, asked, finish, installer] = await cloudWithRelease("0.1.1310", "1310", true);
    t.after(() => server.close());
    const updates = installed(dir, "1300", null, { origin: () => origin, env: { PATH: "/usr/bin:/bin" } }, installer);
    t.after(() => updates.close());
    await updates.check();
    assert.deepEqual([station(updates).latest, station(updates).newer, station(updates).updatable], ["0.1.1310", true, true]);
    await updates.update("station", "zh");
    assert.equal(station(updates).state, "updating");
    assert.ok(existsSync(join(dir, "run", "update.started")));
    // Asked again meanwhile: refused.
    await assert.rejects(updates.update("station", "zh"), (e: Error) => e.message === "Station 正在更新");
    finish();
    await until("ended", () => station(updates).state === "idle");
    assert.equal(station(updates).done, "已更新到 0.1.1310，agent 未中断");
    // Never the cloud's installer.
    assert.ok(!asked.some((a) => a.startsWith("/install")), asked.join());
    assert.equal(readFileSync(join(dir, "installer-saw"), "utf8").trim(), `stable ${dir} ${dir}\n${origin} ${SHA_A} ${SHA_B} zh`);
    assert.ok(!existsSync(join(dir, "run", "update.started")));
    assert.equal(readFileSync(join(dir, "run", "update.exit"), "utf8").trim(), "0");
  });

  test("a feed that does not verify offers nothing, and nothing is installed from it", shInstaller, async (t) => {
    const unsigned = { version: "0.1.1310", build: 1310, commit: "0".repeat(40) };
    const forged = feedOf(1310, {}, OTHER);
    // Words changed after signing: the archive's hash swapped for another.
    const good = feedOf(1310);
    const words = JSON.parse(Buffer.from(good.release, "base64").toString("utf8"));
    for (const b of Object.values<any>(words.builds)) b.sha256 = "c".repeat(64);
    const tampered = { ...good, release: Buffer.from(JSON.stringify(words)).toString("base64") };
    // The signed words of 1310 under a feed that says 1320.
    const relabeled = { ...feedOf(1310), version: "0.1.1320" };
    for (const [name, feed] of Object.entries({ unsigned, forged, tampered, relabeled })) {
      const dir = temp();
      const [origin, server, asked, , installer] = await cloudWithRelease("0.1.1310", "1310", false, feed);
      t.after(() => server.close());
      const updates = installed(dir, "1300", null, { origin: () => origin, env: { PATH: "/usr/bin:/bin" } }, installer);
      t.after(() => updates.close());
      new ConfigFile(dir).update((raw) => (raw.autoUpdate = true));
      await updates.check();
      assert.deepEqual([station(updates).latest, station(updates).newer, updates.toUpdateTo()], [undefined, false, null], name);
      // Asked anyway (a page from before it read): refused, and not left updating.
      await assert.rejects(updates.update("station", "zh"), (e: Error) => e.message.startsWith("此版本签名校验失败"), name);
      assert.equal(station(updates).state, "idle", name);
      assert.ok(!existsSync(join(dir, "installer-ran")), name);
      assert.ok(!asked.some((a) => a.startsWith("/install")), name);
    }
  });

  test("an older signed release is not installed, but back to the stable one from the beta", shInstaller, async (t) => {
    const [origin, server, , , installer] = await cloudWithRelease("0.1.1290", "1290");
    t.after(() => server.close());
    const dir = temp();
    const updates = installed(dir, "1300", null, { origin: () => origin, env: { PATH: "/usr/bin:/bin" } }, installer);
    t.after(() => updates.close());
    await updates.check();
    assert.deepEqual([station(updates).latest, station(updates).newer, station(updates).downgrade], ["0.1.1290", false, false]);
    await assert.rejects(updates.update("station", "zh"), (e: Error) => e.message === "0.1.1290 早于当前的 0.1.1300，不予更新");
    assert.ok(!existsSync(join(dir, "installer-ran")));
    // Installed from the beta and put on the stable channel by a person: going back is theirs to ask.
    const beta = temp();
    const back = installed(beta, "1300", "beta", { origin: () => origin, env: { PATH: "/usr/bin:/bin" } }, installer);
    t.after(() => back.close());
    await back.setChannel("stable");
    assert.deepEqual([station(back).latest, station(back).downgrade], ["0.1.1290", true]);
    await back.update("station", "zh");
    await until("ended", () => station(back).state === "idle");
    assert.equal(readFileSync(join(beta, "installer-ran"), "utf8"), "ran\n");
  });

  test("turned on, the station updates itself by the installer as soon as it reads a newer release, once", shInstaller, async (t) => {
    const dir = temp();
    const [origin, server, asked, , installer] = await cloudWithRelease("0.1.1310", "1310");
    t.after(() => server.close());
    const time = testClock();
    const updates = installed(dir, "1300", null, { origin: () => origin, env: { PATH: "/usr/bin:/bin" }, timing: { followLook: 200 }, clock: time.clock }, installer);
    t.after(() => updates.close());
    new ConfigFile(dir).update((raw) => (raw.autoUpdate = true));
    /// Moves its time on by `ms` until `f` holds (what it waits for meanwhile may be a real process).
    const steps = async (ms: number, f: () => boolean) => {
      while (!f()) {
        await time.adjust(ms);
        await sleep(10);
      }
    };
    // A reading of what is out after the update ended once the feed was asked a third time (the first reading, the
    // update's own, then that one; it decides as it ends).
    const feeds = () => asked.filter((a) => a.startsWith("/releases/station.json")).length;
    let readAgain = false;
    updates.changes(() => void (feeds() >= 3 && (readAgain = true)));
    updates.start();
    // It reads what is out at once, and updates itself by the installer.
    await until("read", () => station(updates).latest === "0.1.1310");
    await steps(50, () => station(updates).state === "updating");
    await until("the installer ended", () => existsSync(join(dir, "run", "update.exit")));
    await steps(200, () => station(updates).done === "已更新到 0.1.1310，agent 未中断");
    // Then reads what is out again: the feed still says 0.1.1310 and the release is 0.1.1310, so nothing more (its
    // decision taken as the reading ends), nor on its rounds after.
    await until("read again", () => readAgain);
    for (let i = 0; i < 5; i++) {
      await time.adjust(50);
      await settle();
    }
    assert.equal(station(updates).state, "idle");
    assert.equal(readFileSync(join(dir, "installer-ran"), "utf8"), "ran\n");
  });

  test("a station not installed by the installer, or not in a workspace, is not updated here", async (t) => {
    const dir = temp();
    const app = join(dir, "elsewhere");
    mkdirSync(app);
    writeFileSync(join(app, "BUILD"), "1300");
    const updates = new Updates({ app, data: dir, config: new ConfigFile(dir), origin: () => "http://127.0.0.1:1", registry: "http://127.0.0.1:1", devinManifest: "http://127.0.0.1:1", env: { PATH: "/nowhere" } });
    t.after(() => updates.close());
    await updates.check();
    let line = station(updates);
    assert.deepEqual([line.note, line.updatable, line.channel, line.auto], ["并非通过安装脚本安装，无法在此更新", false, undefined, undefined]);
    await assert.rejects(updates.update("station", "en"), /Station: /);
    await assert.rejects(updates.setAuto(true, "zh"), (e: Error) => e.message === "Station：并非通过安装脚本安装，无法在此更新");
    const unjoined = installed(temp(), "1300", null, { origin: () => null });
    t.after(() => unjoined.close());
    await unjoined.check();
    line = station(unjoined);
    assert.equal(line.note, "尚未加入 workspace，无法更新");
    await assert.rejects(unjoined.update("nope", "zh"), (e: Error) => e.message === "不存在 nope");
  });

  describe("Codex installed by npm (one build file in the temp directory: one at a time)", () => {
    test("a runtime the machine has not is installed with npm, its download measured, its version pinned", async (t) => {
      const [registry, server, bin, said] = await codexWorld("0.47.0");
      t.after(() => server.close());
      const dir = temp();
      let changed = 0;
      const updates = installed(dir, "1300", null, { registry, env: { PATH: withSystem(bin), HOME: dir }, runtimeChanged: () => changed++ });
      t.after(() => updates.close());
      await updates.check();
      let codex = updates.get("zh")[2]!;
      assert.deepEqual([codex.installed, codex.updatable, codex.latest, codex.state], [false, true, "0.47.0", "idle"]);
      const percents: number[] = [];
      updates.changes(() => {
        const p = updates.get("zh")[2]!.percent;
        if (p !== undefined) percents.push(p);
      });
      await updates.update("codex", "zh");
      assert.equal(updates.get("zh")[2]!.state, "updating");
      await until("installed", () => updates.get("zh")[2]!.state !== "updating");
      codex = updates.get("zh")[2]!;
      assert.deepEqual([codex.installed, codex.version, codex.newer, codex.state, codex.message], [true, "0.47.0", false, "idle", undefined]);
      assert.equal(changed, 1);
      assert.equal(percents.at(-1), 100);
      const asked = readFileSync(said, "utf8").trim().split("\n");
      assert.ok(asked[0]!.startsWith("cache add "), asked.join("|"));
      assert.equal(asked[1], "install -g @openai/codex@0.47.0 --prefer-online");
    });

    test("an install that leaves nothing on the station's PATH says so", async (t) => {
      const [registry, server, bin] = await codexWorld(null);
      t.after(() => server.close());
      const dir = temp();
      const updates = installed(dir, "1300", null, { registry, env: { PATH: withSystem(bin), HOME: dir } });
      t.after(() => updates.close());
      await updates.check();
      await updates.update("codex", "zh");
      await until("failed", () => updates.get("zh")[2]!.state === "failed");
      assert.equal(updates.get("zh")[2]!.message, `${exe(join(bin, "npm"))} 已完成，但 station 的 PATH 中仍找不到 codex：可能安装到了其他位置`);
    });
  });

  test("a runtime npm installs in its own Node's bin, off PATH, is linked beside the npm on PATH", { skip: WINDOWS && "npm's .cmd stays in its prefix (on PATH)" }, async (t) => {
    const [registry, server] = await serve((path) => (path === "/@xai-official/grok/latest" ? { body: JSON.stringify({ version: "1.0.62" }) } : null));
    t.after(() => server.close());
    // A Node unpacked in its own directory, only its npm linked into a directory on PATH (as ~/.local/bin).
    const dir = temp();
    const [node, bin] = [join(dir, "node-v24"), join(dir, "bin")];
    script(join(node, "bin", "npm"), `#!/bin/sh
case "$1" in
  prefix) echo "${node}" ;;
  install) printf '#!/bin/sh\necho "grok 1.0.62 (1474f9cb)"\n' > "${node}/bin/grok.sh"; /bin/ln "${launcher()}" "${node}/bin/grok"; echo "added 1 package" ;;
esac
`);
    mkdirSync(bin);
    symlinkSync(join(node, "bin", "npm"), join(bin, "npm"));
    const updates = installed(dir, "1300", null, { registry, env: { PATH: withSystem(bin), HOME: dir } });
    t.after(() => updates.close());
    await updates.check();
    const grok = () => updates.get("zh").find((v) => v.id === "grok")!;
    assert.deepEqual([grok().installed, grok().updatable], [false, true]);
    await updates.update("grok", "zh");
    await until("installed", () => grok().state !== "updating");
    assert.deepEqual([grok().installed, grok().version, grok().state, grok().message], [true, "1.0.62", "idle", undefined]);
    assert.equal(readlinkSync(join(bin, "grok")), join(node, "bin", "grok"));
  });

  /// nodejs.org as the station reads it: Node `version`'s build for this machine (an npm that installs Grok Build in the
  /// prefix it is given, as npm puts a command there: bin/ and lib/node_modules, on Windows a .cmd at its top), and its
  /// SHASUMS256 (`sum`: the build's, unless given); and the registry's latest Grok Build.
  async function nodeWorld(version: string, sum?: string): Promise<[string, Server]> {
    const dir = temp();
    const build = machine.nodeBuild(version)!;
    const bin = join(dir, build.dist, build.bin);
    mkdirSync(bin, { recursive: true });
    script(join(bin, "npx"), "#!/bin/sh\nexit 0\n");
    script(join(bin, "npm"), `#!/bin/sh
prefix=
while [ $# -gt 0 ]; do [ "$1" = --prefix ] && prefix="$2"; shift; done
${WINDOWS
  ? `printf '@echo grok 1.0.62 (1474f9cb)\\r\\n' > "$prefix/grok.cmd"`
  : `pkg="$prefix/lib/node_modules/@xai-official/grok"
mkdir -p "$pkg/bin" "$prefix/bin"
printf '#!/bin/sh\\necho "grok 1.0.62 (1474f9cb)"\\n' > "$pkg/bin/grok"
chmod +x "$pkg/bin/grok"
ln -s ../lib/node_modules/@xai-official/grok/bin/grok "$prefix/bin/grok"`}
echo "added 1 package"
`);
    const archive = join(dir, build.archive);
    execFileSync(build.tar, [WINDOWS ? "-a" : "-z", "-cf", archive, "-C", dir, build.dist]);
    const bytes = readFileSync(archive);
    const sums = `${"0".repeat(64)}  node-v${version}-aix-ppc64.tar.gz\n${sum ?? createHash("sha256").update(bytes).digest("hex")}  ${build.archive}\n`;
    const [base, server] = await serve((path) =>
      path === "/@xai-official/grok/latest" ? { body: JSON.stringify({ version: "1.0.62" }) }
      : path === `/dist/v${version}/SHASUMS256.txt` ? { type: "text/plain", body: sums }
      : path === `/dist/v${version}/${build.archive}` ? { type: "application/octet-stream", body: bytes }
      : null);
    return [base, server];
  }

  test("where the machine has no npm, a runtime npm installs is installed with nodejs.org's Node, kept in the station's data and on its PATH only", async (t) => {
    const [base, server] = await nodeWorld("24.22.1");
    t.after(() => server.close());
    const dir = temp();
    const [data, home] = [join(dir, "data"), join(dir, "home")];
    const bin = join(home, ".local", "bin");
    mkdirSync(bin, { recursive: true });
    const env: Env = { PATH: withSystem(bin), HOME: home };
    assert.equal(findCommand("npm", env), null, "no npm on the system's PATH");
    const own = ownNode(data, "24.22.1")!;
    // Links an earlier release made into ~/.local/bin to that Node are taken away; others are left.
    if (!WINDOWS) {
      for (const name of ["node", "npm", "grok"]) symlinkSync(join(own.bin, name), join(bin, name));
      symlinkSync(join(dir, "elsewhere", "claude"), join(bin, "claude"));
    }
    const updates = installed(data, "1300", null, { registry: base, nodeDist: `${base}/dist`, env });
    writeFileSync(join(data, "app", "NODE_VERSION"), "24.22.1\n");
    t.after(() => updates.close());
    if (!WINDOWS) assert.deepEqual(readdirSync(bin), ["claude"]);
    await updates.check();
    const grok = () => updates.get("zh").find((v) => v.id === "grok")!;
    assert.deepEqual([grok().installed, grok().updatable, grok().note], [false, true, undefined]);
    await updates.update("grok", "zh");
    await until("installed", () => grok().state !== "updating");
    assert.deepEqual([grok().installed, grok().version, grok().state, grok().message], [true, "1.0.62", "idle", undefined]);
    // Nothing of the download left beside it, nothing put in ~/.local/bin; the station's PATH has it, last.
    assert.deepEqual(readdirSync(join(data, "node")), [own.build.dist]);
    if (!WINDOWS) assert.deepEqual(readdirSync(bin), ["claude"]);
    assert.ok(machine.pathOf(env).endsWith(own.bin), machine.pathOf(env));
    assert.equal(findCommand("npm", env)!.onPath.toLowerCase(), join(own.bin, own.build.npm).toLowerCase());
    // A station started again finds it there; Grok Build updated with that Node's npm.
    const again: Env = { PATH: withSystem(bin), HOME: home };
    const later = installed(data, "1300", null, { registry: base, nodeDist: `${base}/dist`, env: again });
    t.after(() => later.close());
    assert.equal(machine.pathOf(again), machine.pathOf(env));
    if (!WINDOWS) {
      assert.deepEqual(howToUpdate("grok", findCommand("grok", env)!, env), { program: join(own.bin, "npm"), args: ["install", "-g", "@xai-official/grok@latest", "--prefix", own.at] });
    }
  });

  test("a Node whose download does not match nodejs.org's checksum is not installed, nor anything with it", async (t) => {
    const [base, server] = await nodeWorld("24.22.1", "f".repeat(64));
    t.after(() => server.close());
    const dir = temp();
    const [data, home] = [join(dir, "data"), join(dir, "home")];
    mkdirSync(home);
    const env: Env = { PATH: withSystem(join(home, ".local", "bin")), HOME: home };
    const updates = installed(data, "1300", null, { registry: base, nodeDist: `${base}/dist`, env });
    writeFileSync(join(data, "app", "NODE_VERSION"), "24.22.1\n");
    t.after(() => updates.close());
    await updates.check();
    const grok = () => updates.get("zh").find((v) => v.id === "grok")!;
    await updates.update("grok", "zh");
    await until("failed", () => grok().state !== "updating");
    assert.deepEqual([grok().installed, grok().state, grok().message], [false, "failed", "下载的 Node 校验失败"]);
    assert.equal(updates.get("en").find((v) => v.id === "grok")!.message, "The downloaded Node failed verification");
    assert.deepEqual(readdirSync(join(data, "node")), []);
    assert.equal(machine.pathOf(env), withSystem(join(home, ".local", "bin")));
  });

  test("Devin's latest is its installer's manifest's, and Devin as its installer put it is updated by its installer again, without the `devin setup` it ends with", { skip: WINDOWS && "a link to the version the installer keeps" }, async (t) => {
    const [manifest, server] = await serve((path) => (path === "/cli/current/manifest.json" ? { body: JSON.stringify({ version: "3000.12.0", platforms: {} }) } : null));
    t.after(() => server.close());
    // As the installer leaves it: the versions in its data directory, the command on PATH a link to the current one.
    const dir = temp();
    const [versions, bin] = [join(dir, "share", "devin", "cli", "_versions", "3000.11.92"), join(dir, "bin")];
    const now = join(dir, "now");
    script(join(versions, "devin"), `#!/bin/sh
case "$1" in
  setup) echo "Error: Login canceled" >&2; exit 1 ;;
  --version) if [ -f "${now}" ]; then echo "devin $(cat "${now}")"; else echo "devin 3000.11.92"; fi ;;
esac
`);
    mkdirSync(bin);
    symlinkSync(join(versions, "devin"), join(bin, "devin"));
    // The installer as curl fetches it: the latest put in place, then the setup it ends with (a sign-in that wants a
    // terminal).
    script(join(bin, "curl"), `#!/bin/sh
cat <<'END'
echo 3000.12.0 > "${now}"
echo "Installed devin v3000.12.0"
"${join(versions, "devin")}" setup
END
`);
    const updates = installed(dir, "1300", null, { devinManifest: `${manifest}/cli/current/manifest.json`, env: { PATH: withSystem(bin), HOME: dir } });
    t.after(() => updates.close());
    await updates.check();
    const devin = () => updates.get("zh").find((v) => v.id === "devin")!;
    assert.deepEqual([devin().installed, devin().version, devin().latest, devin().newer, devin().updatable], [true, "3000.11.92", "3000.12.0", true, true]);
    await updates.update("devin", "zh");
    await until("updated", () => devin().state !== "updating");
    assert.deepEqual([devin().version, devin().newer, devin().state, devin().message], ["3000.12.0", false, "idle", undefined]);
  });

  test("on Windows a command beside vp.exe is Vite+'s, updated with it; one in npm's prefix with that npm", { skip: !WINDOWS && "Windows'" }, () => {
    const dir = temp();
    writeFileSync(join(dir, "vp.exe"), "");
    writeFileSync(join(dir, "codex.cmd"), "@echo codex-cli 0.1.0\r\n");
    const env: Env = { PATH: dir };
    assert.deepEqual(howToUpdate("codex", findCommand("codex", env)!, env), { program: join(dir, "vp.exe"), args: ["install", "-g", "@openai/codex@latest"] });
    const prefix = temp();
    mkdirSync(join(prefix, "node_modules", "@anthropic-ai", "claude-code"), { recursive: true });
    writeFileSync(join(prefix, "claude.cmd"), "@echo 2.1.0\r\n");
    writeFileSync(join(prefix, "npm.cmd"), "");
    const there: Env = { PATH: prefix };
    assert.deepEqual(howToUpdate("claude", findCommand("claude", there)!, there), {
      program: join(prefix, "npm.cmd"), args: ["install", "-g", "@anthropic-ai/claude-code@latest", "--prefix", prefix],
    });
  });

  test("a winget package is named by the directory winget unpacked it in", () => {
    const at = (dir: string) => wingetPackage(`C:\\Users\\a\\AppData\\Local\\Microsoft\\WinGet\\Packages\\${dir}\\claude.exe`);
    assert.equal(at("Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe"), "Anthropic.ClaudeCode");
    assert.equal(at("Some_Tool_Microsoft.Winget.Source_8wekyb3d8bbwe"), "Some_Tool");
    assert.equal(wingetPackage("C:\\Program Files\\WinGet\\Packages\\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe\\bin\\codex.exe"), "OpenAI.Codex");
    assert.equal(wingetPackage("C:\\Users\\a\\.local\\bin\\claude.exe"), null);
  });

  test("on Windows a command winget installed is updated with winget", { skip: !WINDOWS && "Windows'" }, () => {
    const dir = join(temp(), "WinGet", "Packages", "Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "claude.exe"), "");
    const apps = temp();
    writeFileSync(join(apps, "winget.exe"), "");
    const env: Env = { PATH: [dir, apps].join(";") };
    assert.deepEqual(howToUpdate("claude", findCommand("claude", env)!, env), {
      program: join(apps, "winget.exe"),
      noUpdate: 0x8a15002b,
      args: ["upgrade", "--id", "Anthropic.ClaudeCode", "--exact", "--silent", "--disable-interactivity", "--accept-source-agreements", "--accept-package-agreements"],
    });
  });

  test("on Windows winget with no update to apply says so, not that the update failed", { skip: !WINDOWS && "Windows'" }, async (t) => {
    const [registry, server] = await serve((path) => (path === "/@anthropic-ai/claude-code/latest" ? { body: JSON.stringify({ version: "2.2.0" }) } : null));
    t.after(() => server.close());
    const dir = temp();
    const pkg = join(dir, "WinGet", "Packages", "Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe");
    mkdirSync(pkg, { recursive: true });
    writeFileSync(join(pkg, "claude.cmd"), "@echo 2.1.0 (Claude Code)\r\n");
    const apps = join(dir, "apps");
    mkdirSync(apps);
    // winget's APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE, as cmd exits with it.
    writeFileSync(join(apps, "winget.cmd"), "@echo No available upgrade found.\r\n@exit /b -1978335189\r\n");
    const updates = installed(dir, "1300", null, { registry, env: { PATH: [pkg, apps, withSystem(dir)].join(";"), USERPROFILE: dir } });
    t.after(() => updates.close());
    await updates.check();
    const claude = () => updates.get("zh").find((v) => v.id === "claude")!;
    assert.deepEqual([claude().version, claude().latest, claude().updatable], ["2.1.0", "2.2.0", true]);
    await updates.update("claude", "zh");
    await until("failed", () => claude().state === "failed");
    assert.equal(claude().message, "winget 暂无可在此安装的更新（其源可能还没有最新版本），未做改动：No available upgrade found.");
  });

  test("vite shims update the package with their own vp", { skip: WINDOWS && "Windows' Vite+ commands are shims of their own (the test before)" }, async () => {
    const dir = temp();
    script(join(dir, "vp"), "#!/bin/sh\nprintf '%s\\n' \"$@\"\n");
    for (const kind of ["claude", "codex"] as const) {
      symlinkSync("vp", join(dir, kindCommand(kind)));
      const env: Env = { PATH: dir };
      const f = findCommand(kindCommand(kind), env)!;
      const how = howToUpdate(kind, f, env);
      assert.ok(!(how instanceof Unable));
      const [ok, said] = await run(how.program, how.args, env, 10_000);
      assert.ok(ok);
      assert.equal(said, `install\n-g\n${kindPackage(kind)}@latest\n`);
    }
  });

  test("a standalone update keeps the actual home and path, with shell characters", shInstaller, async () => {
    const dir = temp();
    const home = join(dir, "custom codex ' $home");
    const real = join(home, "packages/standalone/releases/0.155.1-aarch64-apple-darwin/bin/codex");
    const bin = join(dir, "visible bin ' $bin");
    script(real, "#!/bin/sh\necho 'codex-cli 0.155.1'\n");
    mkdirSync(bin, { recursive: true });
    symlinkSync(real, join(bin, "codex"));
    // A harmless installer instead of downloading or changing any real installation.
    script(join(bin, "curl"), `#!/bin/sh
cat <<'INSTALLER'
test "$CODEX_NON_INTERACTIVE" = 1 || exit 1
test "$1" = --release && test "$2" = latest || exit 2
printf '%s\\n' "$CODEX_HOME" "$CODEX_INSTALL_DIR"
INSTALLER
`);
    const env: Env = { PATH: `${bin}:/usr/bin:/bin`, CODEX_HOME: "/wrong/home" };
    const f = findCommand("codex", env)!;
    const how = howToUpdate("codex", f, env);
    assert.ok(!(how instanceof Unable));
    const [ok, said] = await run(how.program, how.args, env, 10_000);
    assert.ok(ok, said);
    assert.equal(said, `${realpathSync(home)}\n${bin}\n`);
    assert.ok(howToUpdate("codex", { onPath: real, real }, env) instanceof Unable);
  });

  test("each runtime is updated the way it was installed", () => {
    const dir = temp();
    for (const name of ["brew", "npm"]) script(join(dir, name), "#!/bin/sh\n");
    const env: Env = { PATH: dir };
    const [brew, npm] = [exe(join(dir, "brew")), exe(join(dir, "npm"))];
    assert.deepEqual(howToUpdate("claude", found("/Users/a/.local/share/claude/versions/2.1.284"), env), { program: "/nowhere/bin/x", args: ["update"] });
    assert.deepEqual(howToUpdate("claude", found("/opt/homebrew/Caskroom/claude-code/2.1.284/claude"), env), { program: brew, args: ["upgrade", "--cask", "claude-code"] });
    assert.deepEqual(howToUpdate("codex", found("/opt/homebrew/Cellar/codex/0.46.0/bin/codex"), env), { program: brew, args: ["upgrade", "codex"] });
    assert.deepEqual(howToUpdate("codex", found("/Users/a/.nvm/versions/node/v24/lib/node_modules/@openai/codex/bin/codex.js"), env), {
      program: npm, args: ["install", "-g", "@openai/codex@latest", "--prefix", "/Users/a/.nvm/versions/node/v24"],
    });
    assert.deepEqual(howToUpdate("claude", found("/Users/a/node/lib/node_modules/@anthropic-ai/claude-code/cli.js"), env), {
      program: npm, args: ["install", "-g", "@anthropic-ai/claude-code@latest", "--prefix", "/Users/a/node"],
    });
    // Linked from a directory beside another Node's npm: its own Node's npm, not that one.
    const node = join(dir, "node/v24.3.0");
    mkdirSync(join(node, "bin"), { recursive: true });
    writeFileSync(join(node, "bin/npm"), "");
    const linked: Found = { onPath: join(dir, "codex"), real: join(node, "lib/node_modules/@openai/codex/bin/codex.js") };
    const how = howToUpdate("codex", linked, env);
    assert.deepEqual(how, { program: join(node, "bin/npm"), args: ["install", "-g", "@openai/codex@latest", "--prefix", node] });
    assert.deepEqual(pinNpmVersion(how as any, "@openai/codex", "0.159.3").args, ["install", "-g", "@openai/codex@0.159.3", "--prefix", node, "--prefer-online"]);
    const say_ = (h: unknown) => (h as Unable).say("zh");
    assert.ok(say_(howToUpdate("codex", found("/project/node_modules/@openai/codex/bin/codex.js"), env)).includes("全局安装目录"));
    assert.ok(say_(howToUpdate("codex", found("/usr/local/bin/codex"), env)).includes("手动更新"));
    // Codex's standalone installer is a shell script: on Windows not run.
    if (WINDOWS) assert.ok(say_(howToUpdate("codex", found("C:/Users/a/.codex/packages/standalone/releases/0.1.0-x86_64-pc-windows-msvc/bin/codex.exe"), env)).includes("手动更新"));
    assert.deepEqual(howToInstall("codex", env), { program: npm, args: ["install", "-g", "@openai/codex@latest"] });
    const bare: Env = { PATH: "/nowhere", HOME: "/Users/a" };
    // Without npm: Codex by its own installer (a shell script: on Windows, a Node of the station's npm).
    const own = ownNode(join("/", "data"), "24.22.1")!;
    const build = machine.nodeBuild("24.22.1")!;
    assert.deepEqual(own, { version: "24.22.1", build, at: join("/", "data", "node", build.dist), bin: join("/", "data", "node", build.dist, build.bin) });
    const ownNpm = (pkg: string) => ({ program: join(own.bin, build.npm), args: ["install", "-g", pkg, "--prefix", own.at], node: own });
    if (WINDOWS) assert.deepEqual(howToInstall("codex", bare, own), ownNpm("@openai/codex@latest"));
    else assert.equal((howToInstall("codex", bare, own) as any).args[2], "stillfail-codex-install");
    // DeepSeek Harness and Grok Build by npm: the machine's, else a Node of the station's put in place first, into it.
    for (const kind of ["dsh", "grok"] as const) {
      const pkg = `${kindPackage(kind)}@latest`;
      assert.deepEqual(howToInstall(kind, env, own), { program: npm, args: ["install", "-g", pkg] });
      assert.deepEqual(howToInstall(kind, bare, own), ownNpm(pkg));
      assert.equal(say_(howToInstall(kind, bare)), `安装 ${kind === "dsh" ? "DeepSeek Harness" : "Grok Build"} 需要 npm：请先在本机安装 Node（含 npm）`);
    }
    assert.equal((howToInstall("claude", bare) as any).program, WINDOWS ? "powershell" : "/bin/sh");
    // Devin by its own installer: run again where it put it (`devin update` wants a terminal), by hand anywhere else;
    // installed by its installer.
    assert.deepEqual(howToUpdate("devin", found("/Users/a/.local/share/devin/cli/_versions/3000.11.92/devin"), env), machine.devinInstall);
    if (WINDOWS) assert.deepEqual(howToUpdate("devin", found("C:\\Users\\a\\AppData\\Local\\devin\\cli\\_versions\\3000.11.92\\devin.exe"), env), machine.devinInstall);
    const elsewhere = howToUpdate("devin", found("/opt/homebrew/bin/devin"), env);
    assert.ok(elsewhere instanceof Unable);
    assert.deepEqual([elsewhere.key, elsewhere.args], ["station.updates.devinElsewhere", { path: "/opt/homebrew/bin/devin" }]);
    assert.ok(say_(elsewhere).includes("/opt/homebrew/bin/devin"));
    assert.deepEqual(howToInstall("devin", bare), machine.devinInstall);
    assert.equal((howToInstall("devin", bare) as any).program, WINDOWS ? "powershell" : "/bin/sh");
    assert.equal(kindPackage("devin"), "", "no npm package");
  });

  test("a command's failure shown as its last lines, without a terminal's escapes and a progress bar's returns", () => {
    const said = "\u001b[0;32m✓\u001b[0m Installed devin\n##   44.4%\r####   95.5%\r#####  100.0%\n\u001b[1A\u001b[2KError: Login canceled\n\u001b[?2004l";
    assert.equal(tail(said, "en"), "✓ Installed devin\n#####  100.0%\nError: Login canceled");
  });
});
