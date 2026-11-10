// A simulator's logs and apps (screens/sim-debug.ts) on a real Mac with Xcode: a
// simulator of this test's own made and booted (deleted afterwards), a small app built for it that logs twice a second,
// installed, found, started again, and its lines read as a person's 日志 reads them. Real time, a real device: a side test.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { SimDebug } from "../src/screens/sim-debug.ts";
import { SIMCTL } from "../src/screens/simulator.ts";

const APP = "fail.still.side.debug";
const SOURCE = `
import UIKit
import os
let logger = Logger(subsystem: "fail.still.side", category: "side")
@objc(SideScene) class Scene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    window = UIWindow(windowScene: scene as! UIWindowScene)
    window!.rootViewController = UIViewController()
    window!.makeKeyAndVisible()
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      logger.error("side-logger")
      NSLog("side-nslog")
      print("side-print")
    }
  }
}
@objc(SideDelegate) class Delegate: UIResponder, UIApplicationDelegate {}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, "SideDelegate")
`;
const PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${APP}</string>
<key>CFBundleName</key><string>SideDebug</string>
<key>CFBundleExecutable</key><string>SideDebug</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SideScene</string>
</dict></array></dict>
</dict>
</dict></plist>`;

const LONG = 5 * 60_000;
const xcrun = (...args: string[]) => execFileSync("xcrun", args, { encoding: "utf8", timeout: LONG }).trim();
// CoreSimulator's own, as the station's: `xcrun simctl` may first run `xcodebuild -runFirstLaunch` and its password window.
const simctl = (...args: string[]) => execFileSync(SIMCTL, args, { encoding: "utf8", timeout: LONG }).trim();
const hasSimctl = platform() === "darwin" && existsSync(SIMCTL);
const run = (file: string, args: string[]) => Promise.resolve(execFileSync(file, args, { encoding: "utf8", maxBuffer: 16 << 20, timeout: 60_000 }));

test("a simulator's app found, started again and its log read", { skip: !hasSimctl && "no Xcode simulators here" }, async () => {
  const runtimes = JSON.parse(simctl("list", "-j", "runtimes")).runtimes.filter((r: any) => r.isAvailable && r.platform === "iOS");
  const runtime = runtimes.at(-1);
  const type = runtime.supportedDeviceTypes.find((t: any) => t.productFamily === "iPhone");
  const udid = simctl("create", `still.fail side debug ${process.pid}`, type.identifier, runtime.identifier);
  const dir = mkdtempSync(join(tmpdir(), "sim-debug-"));
  const debug = new SimDebug(SIMCTL, udid, run, async () => { throw new Error("no view here"); });
  try {
    simctl("bootstatus", udid, "-b");
    const app = join(dir, "SideDebug.app");
    mkdirSync(app);
    writeFileSync(join(dir, "main.swift"), SOURCE);
    writeFileSync(join(app, "Info.plist"), PLIST);
    const sdk = xcrun("--sdk", "iphonesimulator", "--show-sdk-path");
    xcrun("--sdk", "iphonesimulator", "swiftc", "-target", `${process.arch === "arm64" ? "arm64" : "x86_64"}-apple-ios17.0-simulator`, "-sdk", sdk, join(dir, "main.swift"), "-o", join(app, "SideDebug"));
    execFileSync("codesign", ["-s", "-", "--force", app]);
    simctl("install", udid, app);

    const before = await debug.apps();
    const found = before.find((a) => a.id === APP);
    assert.deepEqual(found, { id: APP, name: "SideDebug", running: false });
    assert.equal(await debug.relaunch("com.apple.Preferences"), false, "not an app a person installed");
    assert.equal(await debug.relaunch(APP), true);
    // launchd says it a moment after it started.
    let running = false;
    for (let i = 0; i < 20 && !running; i++) {
      await sleep(500);
      running = (await debug.apps()).find((a) => a.id === APP)?.running === true;
    }
    assert.equal(running, true, "it is said to run");

    let after = 0;
    const said: { level: string; app: string; text: string }[] = [];
    for (let i = 0; i < 40 && !(said.some((l) => l.text === "side-logger") && said.some((l) => l.text.includes("side-nslog"))); i++) {
      await sleep(500);
      const got = debug.logs(after);
      after = got.next;
      said.push(...got.lines);
    }
    const logger = said.find((l) => l.text === "side-logger");
    assert.ok(logger, `the Logger's line came (of ${said.length})`);
    assert.equal(logger.level, "Error");
    assert.equal(logger.app, "SideDebug");
    assert.ok(said.some((l) => l.text.includes("side-nslog")), "NSLog's line came");
    console.log(`lines: ${said.length}; print's among them: ${said.some((l) => l.text.includes("side-print"))}; others: ${JSON.stringify(said.filter((l) => !l.text.includes("side-")).slice(0, 8).map((l) => l.text.slice(0, 80)))}`);

    // Started again: still running, the log going on.
    assert.equal(await debug.relaunch(APP), true);
    let more = 0;
    for (const asked = Date.now(); more === 0 && Date.now() - asked < 60_000;) {
      await sleep(500);
      more = debug.logs(after).lines.length;
    }
    assert.ok(more > 0, "its log goes on after the restart");
  } finally {
    debug.close();
    try {
      simctl("shutdown", udid);
    } catch {}
    simctl("delete", udid);
    rmSync(dir, { recursive: true, force: true });
  }
});
