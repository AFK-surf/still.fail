// A simulator's logs and apps (screens/sim-debug.ts, docs/remote-screens.md "Simulators") with simctl played: its lines
// read as a person reads them, what it says of its own left out, the stream started as it is first asked for and only
// once, only an app a person installed started again. side/screen-simulator-debug.test.ts has the real one.
import assert from "node:assert/strict";
import { test } from "node:test";
import { SimDebug, appsOf, logOf } from "../src/screens/sim-debug.ts";

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
