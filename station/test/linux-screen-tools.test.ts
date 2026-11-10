import assert from "node:assert/strict";
import { execFile, spawnSync } from "node:child_process";
import { closeSync, constants, openSync } from "node:fs";
import { mkdir, mkdtemp, open, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";
import { LinuxScreenTools } from "../src/screens/linux-tools.ts";
import { X11Desktop } from "../src/screens/x11-desktop.ts";

// A fake package source and extractor keep these tests offline and as the station user. The real APT and dpkg-deb
// path is also exercised against a disposable X11 server in the Linux integration checks.
async function rig() {
  const dir = await mkdtemp(join(tmpdir(), "stillfail-linux-screen-"));
  const bin = join(dir, "bin"), fixtures = join(dir, "fixtures"), data = join(dir, "data");
  await Promise.all([mkdir(bin), mkdir(fixtures), mkdir(data)]);
  const put = (path: string, body: string) => writeFile(path, body, { mode: 0o755 });
  await Promise.all([
    put(join(bin, "apt-get"), `#!/bin/sh
printf x >> "$APT_TEST_COUNT"
printf '%s\n' "$@" > "$APT_TEST_ARGS"
for arg in "$@"; do case "$arg" in Dir::Cache::archives=*) archives="\${arg#*=}";; esac; done
/bin/cp "$APT_TEST_FIXTURES/ffmpeg.deb" "$APT_TEST_FIXTURES/xdotool.deb" "$archives/"
`),
    put(join(bin, "dpkg-deb"), `#!/bin/sh
/bin/mkdir -p "$3/usr/bin"
case "$2" in
  */ffmpeg.deb) /bin/cp "$APT_TEST_FIXTURES/ffmpeg" "$3/usr/bin/ffmpeg";;
  */xdotool.deb) /bin/cp "$APT_TEST_FIXTURES/xdotool" "$3/usr/bin/xdotool";;
  *) exit 1;;
esac
`),
    put(join(fixtures, "ffmpeg"), `#!/bin/sh
if [ "$2" = "-devices" ]; then
  if [ "$APT_TEST_BAD_FFMPEG" = 1 ]; then echo ' D  other'; else echo ' D  x11grab X11'; fi
  exit 0
fi
printf '\\377\\330A\\377\\331'
exec /bin/sleep 30
`),
    put(join(fixtures, "xdotool"), `#!/bin/sh
case "$1" in
  --version) echo 'xdotool test';;
  getdisplaygeometry) echo '800 600';;
  *) printf '%s\n' "$*" >> "$APT_TEST_INPUT";;
esac
`),
    writeFile(join(fixtures, "ffmpeg.deb"), "ffmpeg"),
    writeFile(join(fixtures, "xdotool.deb"), "xdotool"),
  ]);
  const env: NodeJS.ProcessEnv = {
    ...process.env, PATH: bin, DISPLAY: ":99", XDG_SESSION_TYPE: "x11", WAYLAND_DISPLAY: "",
    APT_TEST_FIXTURES: fixtures, APT_TEST_COUNT: join(dir, "count"), APT_TEST_ARGS: join(dir, "args"), APT_TEST_INPUT: join(dir, "input"),
  };
  delete env.LD_LIBRARY_PATH;
  return { dir, data, env, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

test("a Linux screen prepares a private pair once and uses it for capture and input", { skip: process.platform !== "linux", timeout: 60_000 }, async (t) => {
  const r = await rig();
  t.after(r.cleanup);
  const tools = new LinuxScreenTools(r.data);
  const desktop = new X11Desktop({ env: r.env, tools, changed: () => {}, prepareWaitMs: 30_000 });
  t.after(() => desktop.close());
  await desktop.refresh(true);
  assert.equal(desktop.access().reason, "linuxTools");
  const view = await desktop.open({ maxWidth: 400, maxHeight: 300, codecs: ["jpeg"] });
  assert.deepEqual(desktop.size(), { width: 800, height: 600 });
  const frame = await view.next();
  assert.ok(frame);
  assert.deepEqual([...frame.data], [0xff, 0xd8, 65, 0xff, 0xd9]);
  await view.input({ t: "pointer", kind: "down", x: 0.5, y: 0.5, buttons: 1 });
  await view.input({ t: "pointer", kind: "up", x: 0.5, y: 0.5, buttons: 0 });
  assert.match(await readFile(r.env.APT_TEST_INPUT!, "utf8"), /mousedown 1/);
  assert.equal(await readFile(r.env.APT_TEST_COUNT!, "utf8"), "x");
  const args = await readFile(r.env.APT_TEST_ARGS!, "utf8");
  assert.match(args, /--download-only/);
  assert.match(args, /--no-remove/);
  assert.match(args, /Dir::Cache::archives=/);
  assert.equal(tools.prepared(r.env)?.env.LD_LIBRARY_PATH?.startsWith(join(r.data, "screen-tools", "apt", "root")), true);
  assert.deepEqual(await readdir(join(r.data, "screen-tools")), ["apt"]);
  view.close();
});

test("a failed preparation leaves no pair and a later opening retries it", { skip: process.platform !== "linux", timeout: 60_000 }, async (t) => {
  const r = await rig();
  t.after(r.cleanup);
  r.env.APT_TEST_BAD_FFMPEG = "1";
  const tools = new LinuxScreenTools(r.data);
  const desktop = new X11Desktop({ env: r.env, tools, changed: () => {}, prepareWaitMs: 30_000 });
  t.after(() => desktop.close());
  await assert.rejects(desktop.open({ maxWidth: 400, maxHeight: 300, codecs: ["jpeg"] }), /could not be prepared automatically/);
  assert.equal(tools.prepared(r.env), null);
  assert.deepEqual(await readdir(join(r.data, "screen-tools")), []);
  delete r.env.APT_TEST_BAD_FFMPEG;
  const view = await desktop.open({ maxWidth: 400, maxHeight: 300, codecs: ["jpeg"] });
  assert.ok(await view.next());
  assert.equal(await readFile(r.env.APT_TEST_COUNT!, "utf8"), "xx");
  view.close();
});

test("concurrent requests share a preparation and a stopped station cancels it", { skip: process.platform !== "linux", timeout: 60_000 }, async (t) => {
  const r = await rig();
  t.after(r.cleanup);
  const tools = new LinuxScreenTools(r.data);
  const a = tools.prepare(r.env), b = tools.prepare(r.env);
  assert.equal(a, b);
  tools.close();
  await assert.rejects(a);
  assert.equal(tools.prepared(r.env), null);
  assert.deepEqual(await readdir(join(r.data, "screen-tools")), []);
});

test("a preparation stopped ends what its command started, before its stage is removed", { skip: process.platform !== "linux" && process.platform !== "darwin", timeout: 60_000 }, async (t) => {
  // (CI, 2026-11-10: apt-get ended alone left the process it had started copying a package into the stage as the stage
  // was removed, and the stage stayed.) This apt-get starts a process that waits to be told to go on, on a FIFO the test
  // holds the writing end of: written to once the preparation has failed, it has no reader left.
  const r = await rig();
  const go = join(r.dir, "go");
  assert.equal(spawnSync("mkfifo", [go]).status, 0);
  let told: Awaited<ReturnType<typeof open>> | undefined;
  t.after(async () => {
    // (a writer's opening that no reader ever met is met here, so that it ends with the test)
    closeSync(openSync(go, constants.O_RDONLY | constants.O_NONBLOCK));
    await told?.close();
    await r.cleanup();
  });
  await writeFile(join(r.dir, "bin", "apt-get"), `#!/bin/sh
for arg in "$@"; do case "$arg" in Dir::Cache::archives=*) archives="\${arg#*=}";; esac; done
( read line < "$APT_TEST_GO"; /bin/cp "$APT_TEST_FIXTURES/ffmpeg.deb" "$archives/" ) &
wait
`, { mode: 0o755 });
  r.env.APT_TEST_GO = go;
  const tools = new LinuxScreenTools(r.data);
  const preparing = tools.prepare(r.env);
  // Opened once the command's own process has opened it to read: it is running, and waits.
  told = await open(go, "w");
  tools.close();
  await assert.rejects(preparing);
  await assert.rejects(told.write("go\n"), { code: "EPIPE" }, "a process of the command still read what it waited for");
  assert.equal(tools.prepared(r.env), null);
  assert.deepEqual(await readdir(join(r.data, "screen-tools")), []);
});

test("the private APT pair captures and controls a disposable X11 desktop", { skip: process.env.STILLFAIL_TEST_X11_APT !== "1", timeout: 240_000 }, async (t) => {
  const kept = process.env.STILLFAIL_TEST_X11_DATA;
  const data = kept ?? await mkdtemp(join(tmpdir(), "stillfail-x11-apt-"));
  if (!kept) t.after(() => rm(data, { recursive: true, force: true }));
  const tools = new LinuxScreenTools(data);
  await tools.prepare(process.env);
  const pair = tools.prepared(process.env);
  assert.ok(pair);
  const desktop = new X11Desktop({ env: pair.env, ffmpeg: pair.ffmpeg, xdotool: pair.xdotool, changed: () => {} });
  t.after(() => desktop.close());
  const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["jpeg"] });
  const frame = await view.next();
  assert.ok(frame);
  const decoded = spawnSync(pair.ffmpeg, ["-nostdin", "-loglevel", "error", "-f", "mjpeg", "-i", "pipe:0", "-frames:v", "1", "-f", "null", "-"], { env: pair.env, input: frame.data, timeout: 15_000 });
  assert.equal(decoded.status, 0, decoded.stderr?.toString());
  await view.input({ t: "pointer", kind: "move", x: 0.25, y: 0.35, buttons: 0 });
  const { stdout } = await promisify(execFile)(pair.xdotool, ["getmouselocation", "--shell"], { env: pair.env, timeout: 10_000 });
  assert.match(stdout, /X=320\n/);
  assert.match(stdout, /Y=280\n/);
  view.close();
});
