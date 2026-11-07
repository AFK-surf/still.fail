// A simulator's logs and apps (screens/sim-debug.ts) with simctl played: its lines
// read as a person reads them, what it says of its own left out, the stream started as it is first asked for and only
// once, only an app a person installed started again. side/screen-simulator-debug.test.ts has the real one.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { SimDebug, appsOf, logOf, turnMovie, turnOf } from "../src/screens/sim-debug.ts";

const line = (eventMessage: string, messageType = "Default") =>
  JSON.stringify({ eventMessage, messageType, timestamp: "2026-11-02 13:23:11.123456+0800", processImagePath: "/Users/x/Devices/U/data/Containers/Bundle/Application/A/Demo.app/Demo" });

test("a log line as a person reads it; what is not one is none", () => {
  assert.deepEqual(logOf(line("hello", "Error")), { at: "2026-11-02 13:23:11.123456+0800", level: "Error", app: "Demo", text: "hello" });
  assert.equal(logOf('Filtering the log data using "x"'), null);
  assert.equal(logOf('{"finished":1}'), null);
});

test("the apps a person installed, those running first", () => {
  const installed = {
    "com.apple.Preferences": { ApplicationType: "System", CFBundleDisplayName: "Settings" },
    "fail.still.b": { ApplicationType: "User", CFBundleDisplayName: "Beta" },
    "fail.still.a": { ApplicationType: "User", CFBundleName: "Alpha" },
    "fail.still.c": { ApplicationType: "User" },
  };
  const launchctl = "1\t0\tUIKitApplication:fail.still.b[ff42][rb-legacy]\n2\t0\tUIKitApplication:com.apple.Preferences[1][rb-legacy]\n";
  assert.deepEqual(appsOf(installed, launchctl), [
    { id: "fail.still.b", name: "Beta", running: true },
    { id: "fail.still.a", name: "Alpha", running: false },
    { id: "fail.still.c", name: "fail.still.c", running: false },
  ]);
});

/// A device with `fail.still.a` installed, its log played by hand.
function played() {
  const runs: string[][] = [];
  const streams: { args: string[]; line: (text: string) => void; ended: () => void; stopped: boolean }[] = [];
  const debug = new SimDebug(
    "simctl",
    "U",
    async (file, args) => {
      runs.push([file, ...args]);
      return file === "/bin/sh" ? JSON.stringify({ "fail.still.a": { ApplicationType: "User", CFBundleName: "Alpha" } }) : "";
    },
    async () => new Uint8Array(),
    (args, line, ended) => {
      const s = { args, line, ended, stopped: false };
      streams.push(s);
      return { stop: () => void (s.stopped = true) };
    },
  );
  return { debug, runs, streams };
}

test("the log followed from the first look, each look saying what came since", () => {
  const { debug, streams } = played();
  assert.deepEqual(debug.logs(0), { next: 0, lines: [] });
  debug.logs(0);
  assert.equal(streams.length, 1, "one stream however often it is asked");
  assert.deepEqual(streams[0]!.args.slice(0, 5), ["simctl", "spawn", "U", "log", "stream"]);
  streams[0]!.line("Filtering the log data");
  streams[0]!.line(line("one"));
  streams[0]!.line(line("two"));
  const first = debug.logs(0);
  assert.deepEqual(first.lines.map((l) => l.text), ["one", "two"]);
  assert.equal(first.next, 2);
  streams[0]!.line(line("three"));
  assert.deepEqual(debug.logs(first.next).lines.map((l) => l.text), ["three"]);
  debug.close();
  assert.equal(streams[0]!.stopped, true, "it goes with the device");
});

test("a log that ended by itself is started again at the next look; closed, never", () => {
  const { debug, streams } = played();
  debug.logs(0);
  streams[0]!.ended();
  debug.logs(0);
  assert.equal(streams.length, 2);
  debug.close();
  debug.logs(0);
  assert.equal(streams.length, 2);
});

test("only the newest lines go at once, and only so many are held", () => {
  const { debug, streams } = played();
  debug.logs(0);
  for (let i = 0; i < 2500; i++) streams[0]!.line(line(`${i}`));
  const { next, lines } = debug.logs(0);
  assert.equal(next, 2500);
  assert.equal(lines.length, 500);
  assert.equal(lines.at(-1)!.text, "2499");
  debug.close();
});

test("only an app installed here is started again", async () => {
  const { debug, runs } = played();
  assert.equal(await debug.relaunch("--help"), false);
  assert.equal(await debug.relaunch("com.apple.Preferences"), false);
  assert.ok(!runs.some((r) => r.includes("launch")));
  assert.equal(await debug.relaunch("fail.still.a"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "launch", "--terminate-running-process", "U", "fail.still.a"]);
  debug.close();
});

test("a link is opened only if it is one, an option never", async () => {
  const { debug, runs } = played();
  assert.equal(await debug.openUrl("--help"), false);
  assert.equal(await debug.openUrl("not a link"), false);
  assert.equal(runs.length, 0);
  assert.equal(await debug.openUrl("myapp://open/3"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "openurl", "U", "myapp://open/3"]);
  debug.close();
});

test("a place is set only if it is on the earth, and cleared", async () => {
  const { debug, runs } = played();
  for (const bad of ["", "shanghai", "91,0", "0,181", "1,2,3", "--help"]) assert.equal(await debug.location(bad), false, bad);
  assert.equal(runs.length, 0);
  assert.equal(await debug.location(" 31.23, -121.47 "), true);
  assert.deepEqual(runs.at(-1), ["simctl", "location", "U", "set", "31.23,-121.47"]);
  assert.equal(await debug.location(null), true);
  assert.deepEqual(runs.at(-1), ["simctl", "location", "U", "clear"]);
  debug.close();
});

test("the status bar tidy, and as it is", async () => {
  const { debug, runs } = played();
  await debug.statusBar(true);
  assert.deepEqual(runs.at(-1)!.slice(0, 6), ["simctl", "status_bar", "U", "override", "--time", "9:41"]);
  await debug.statusBar(false);
  assert.deepEqual(runs.at(-1), ["simctl", "status_bar", "U", "clear"]);
  debug.close();
});

test("a notification goes only to an app installed here, saying something", async () => {
  const { debug, runs } = played();
  assert.equal(await debug.push("com.apple.Preferences", "hi"), false);
  assert.equal(await debug.push("fail.still.a", "  "), false);
  assert.ok(!runs.some((r) => r.includes("push")));
  assert.equal(await debug.push("fail.still.a", "hi"), true);
  const sent = runs.at(-1)!;
  assert.deepEqual(sent.slice(0, 4), ["simctl", "push", "U", "fail.still.a"]);
  assert.match(sent[4]!, /\.apns$/);
  debug.close();
});

test("an app is installed and started from a file gone up, which is let go of", async () => {
  const runs: string[][] = [];
  const debug = new SimDebug(
    "simctl",
    "U",
    async (file, args) => {
      runs.push([file, ...args]);
      if (file === "ditto") mkdirSync(join(args[3]!, "Payload", "Demo.app"), { recursive: true });
      return file === "plutil" ? JSON.stringify({ CFBundleIdentifier: "fail.still.demo" }) : "";
    },
    async () => new Uint8Array(),
    () => ({ stop: () => {} }),
  );
  const folder = debug.installFolder();
  const put = (name: string) => {
    const path = join(folder, name);
    writeFileSync(path, "x");
    return path;
  };
  assert.equal(await debug.install("/etc/passwd.ipa"), null);
  assert.equal(await debug.install(put("notes.txt")), null);
  assert.equal(runs.length, 0);
  rmSync(join(folder, "notes.txt"));
  const ipa = put("Demo.ipa");
  assert.equal(await debug.install(ipa), "fail.still.demo");
  assert.deepEqual(runs[0]!.slice(0, 3), ["ditto", "-x", "-k"]);
  assert.deepEqual(runs[1]!.slice(0, 3), ["simctl", "install", "U"]);
  assert.match(runs[1]![3]!, /Payload\/Demo\.app$/);
  assert.deepEqual(runs.at(-1), ["simctl", "launch", "--terminate-running-process", "U", "fail.still.demo"]);
  assert.equal(existsSync(ipa), false);
  debug.close();
});

test("a recording: told which display a panel is, ended, its movie where the drive reads it", async () => {
  const runs: string[][] = [];
  const asked: string[][] = [];
  let stopped = 0;
  const debug = new SimDebug(
    "simctl",
    "U",
    async (file, args) => {
      runs.push([file, ...args]);
      return "";
    },
    async () => new Uint8Array(),
    () => ({ stop: () => {} }),
    (args) => {
      asked.push(args);
      writeFileSync(args.at(-1)!, "movie");
      return { started: Promise.resolve(), ended: Promise.resolve(), stop: () => void stopped++ };
    },
  );
  assert.equal(await debug.recordStop(), null);
  await debug.recordStart("inner");
  assert.ok(asked[0]!.includes("--display=3"));
  assert.equal(debug.recording, true);
  await debug.recordStart("inner");
  assert.equal(asked.length, 1);
  const got = (await debug.recordStop())!;
  assert.equal(stopped, 1);
  assert.equal(debug.recording, false);
  assert.ok(existsSync(join(got.root, got.path)));
  await debug.recordStart("cover");
  assert.ok(asked[1]!.includes("--display=1"));
  assert.equal(existsSync(join(got.root, got.path)), false, "the last one's let go of");
  await debug.recordStop();
  await debug.recordStart(null);
  assert.ok(!asked[2]!.some((a) => a.startsWith("--display")));
  await debug.recordStop();
  debug.close();
});

test("a panel's turn as simctl says it, and a movie told it", async () => {
  const said = "Device Name: primary\n  UI Orientation: Portrait\nDevice Name: primary-1\n  UI Orientation: Landscape Left\n";
  assert.equal(turnOf(said, "primary"), 0);
  assert.equal(turnOf(said, "primary-1"), 1);
  const box = (kind: string, ...body: Buffer[]) => {
    const b = Buffer.concat(body);
    const h = Buffer.alloc(8);
    h.writeUInt32BE(b.length + 8, 0);
    h.write(kind, 4, "latin1");
    return Buffer.concat([h, b]);
  };
  const tkhd = Buffer.alloc(84);
  tkhd.writeUInt32BE(2006 * 0x10000, 76);
  tkhd.writeUInt32BE(2852 * 0x10000, 80);
  const hdlr = Buffer.alloc(24);
  hdlr.write("vide", 8, "latin1");
  const movie = Buffer.concat([box("ftyp", Buffer.alloc(8)), box("mdat", Buffer.alloc(16)), box("moov", box("mvhd", Buffer.alloc(100)), box("trak", box("tkhd", tkhd), box("mdia", box("hdlr", hdlr))))]);
  const file = join(mkdtempSync(join(tmpdir(), "movie-")), "m.mp4");
  writeFileSync(file, movie);
  assert.equal(await turnMovie(file, 1), true);
  const out = readFileSync(file);
  const at = out.indexOf("tkhd") + 4 + 40;
  assert.deepEqual([out.readInt32BE(at), out.readInt32BE(at + 4), out.readInt32BE(at + 12), out.readInt32BE(at + 16), out.readInt32BE(at + 24), out.readInt32BE(at + 28), out.readInt32BE(at + 32)], [0, 0x10000, -0x10000, 0, 2852 * 0x10000, 0, 0x40000000]);
  writeFileSync(file, "");
  assert.equal(await turnMovie(file, 0), false, "nothing recorded");
});

test("Face ID's and an app's going, told as simctl takes them", async () => {
  const { debug, runs } = played();
  assert.equal(await debug.biometrics("--help"), false);
  assert.equal(runs.length, 0);
  assert.equal(await debug.biometrics("enrol"), true);
  assert.deepEqual(runs.at(-2), ["simctl", "spawn", "U", "notifyutil", "-s", "com.apple.BiometricKit.enrollmentChanged", "1"]);
  assert.deepEqual(runs.at(-1), ["simctl", "spawn", "U", "notifyutil", "-p", "com.apple.BiometricKit.enrollmentChanged"]);
  assert.equal(await debug.biometrics("nomatch"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "spawn", "U", "notifyutil", "-p", "com.apple.BiometricKit_Sim.pearl.nomatch"]);
  assert.equal(await debug.uninstall("com.apple.Preferences"), false);
  assert.equal(await debug.uninstall("fail.still.a"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "uninstall", "U", "fail.still.a"]);
  debug.close();
});

test("a setting is set only to what simctl takes, and said back", async () => {
  const { debug, runs } = played();
  assert.equal(await debug.setSetting("appearance", "sepia"), false);
  assert.equal(await debug.setSetting("volume", "11"), false);
  assert.equal(runs.length, 0);
  assert.equal(await debug.setSetting("appearance", "dark"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "ui", "U", "appearance", "dark"]);
  assert.equal(await debug.setSetting("textSize", "accessibility-large"), true);
  assert.deepEqual(runs.at(-1), ["simctl", "ui", "U", "content_size", "accessibility-large"]);
  debug.close();
});
