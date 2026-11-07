// A device turned from a view on a real Mac with Xcode: a simulator of this test's own
// (SIM_TYPE: its type's name, as "iPhone Duo"; the runtime's first iPhone otherwise), a small app that says the shape of its window, turned all the way round through
// still.fail Helper's view as a person's button does; the app turning, and the view's picture with it. SIM_OUT: its pictures.
// STILLFAIL_HELPER and STILLFAIL_HELPER_DIR: another helper. A side test.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { HelperApp } from "../src/helper/app.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import { SimDebug } from "../src/screens/sim-debug.ts";
import { SIMCTL, Simulators } from "../src/screens/simulator.ts";
import type { ScreenView } from "../src/screens/source.ts";

const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const APP = "fail.still.side.rotate";
const SOURCE = `
import UIKit
import Foundation
import os
let logger = Logger(subsystem: "fail.still.side", category: "side")
class Root: UIViewController {
  let words = UILabel()
  override func viewDidLoad() {
    view.backgroundColor = .systemTeal
    words.font = .boldSystemFont(ofSize: 60)
    words.textAlignment = .center
    words.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    words.frame = view.bounds
    view.addSubview(words)
  }
  override func viewDidLayoutSubviews() {
    let s = view.bounds.size
    words.text = "\\(Int(s.width))x\\(Int(s.height)) UP"
    logger.error("side-shape:\\(s.width > s.height ? "wide" : "tall", privacy: .public)")
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    let at = touches.first!.location(in: view)
    let words = String(format: "%.2f,%.2f", Double(at.x / view.bounds.width), Double(at.y / view.bounds.height))
    logger.error("side-touch:\\(words, privacy: .public)")
  }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}
@objc(SideScene) class Scene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    window = UIWindow(windowScene: scene as! UIWindowScene)
    window!.rootViewController = Root()
    window!.makeKeyAndVisible()
    logger.error("side-ready")
  }
}
@objc(SideDelegate) class Delegate: UIResponder, UIApplicationDelegate {}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, "SideDelegate")
`;
const PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${APP}</string>
<key>CFBundleName</key><string>SideRotate</string>
<key>CFBundleExecutable</key><string>SideRotate</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
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
const simctl = (...args: string[]) => execFileSync(SIMCTL, args, { encoding: "utf8", timeout: LONG }).trim();
const hasSimctl = platform() === "darwin" && existsSync(SIMCTL);
const run = (file: string, args: string[]) => Promise.resolve(execFileSync(file, args, { encoding: "utf8", maxBuffer: 16 << 20 }));

test("a simulator turned from its view, all the way round", { skip: !hasSimctl && "no Xcode simulators here", timeout: 10 * 60_000 }, async () => {
  const runtimes = JSON.parse(simctl("list", "-j", "runtimes")).runtimes.filter((r: any) => r.isAvailable && r.platform === "iOS");
  // (SIM_RUNTIME: an older one, as "iOS-17")
  const runtime = runtimes.findLast((r: any) => r.identifier.includes(process.env.SIM_RUNTIME ?? "")) ?? runtimes.at(-1);
  const type = runtime.supportedDeviceTypes.find((t: any) => (process.env.SIM_TYPE ? t.name === process.env.SIM_TYPE : t.productFamily === "iPhone"));
  const udid = simctl("create", `still.fail side rotate ${process.pid}`, type.identifier, runtime.identifier);
  console.log(`on ${type.name}, ${runtime.name}`);
  const dir = mkdtempSync(join(tmpdir(), "sim-rotate-"));
  const debug = new SimDebug(SIMCTL, udid, run, async () => { throw new Error("no view here"); });
  const helper = new HelperApp({ app: process.env.STILLFAIL_HELPER ?? execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", "helper"], { encoding: "utf8" }).trim(), dir: process.env.STILLFAIL_HELPER_DIR ?? join(dir, "helper") });
  const hub = new ScreenHub();
  const simulators = new Simulators({ screens: hub, helper });
  let view: ScreenView | null = null;
  let after = 0;
  const said = async (ms: number) => {
    await sleep(ms);
    const got = debug.logs(after);
    after = got.next;
    return got.lines.map((l) => l.text).filter((t) => t.startsWith("side-"));
  };
  try {
    simctl("boot", udid);
    simctl("bootstatus", udid, "-b");
    const app = join(dir, "SideRotate.app");
    mkdirSync(app);
    writeFileSync(join(dir, "main.swift"), SOURCE);
    writeFileSync(join(app, "Info.plist"), PLIST);
    const sdk = xcrun("--sdk", "iphonesimulator", "--show-sdk-path");
    xcrun("--sdk", "iphonesimulator", "swiftc", "-target", `${process.arch === "arm64" ? "arm64" : "x86_64"}-apple-ios17.0-simulator`, "-sdk", sdk, "-o", join(app, "SideRotate"), join(dir, "main.swift"));
    execFileSync("codesign", ["-s", "-", "--force", app]);
    simctl("install", udid, app);
    debug.logs(0);
    await sleep(1500);
    assert.equal(await debug.relaunch(APP), true);
    // Waited for, not a fixed 6 s (side run 41810080693): how long a device just booted takes is not this test's.
    let up = false;
    for (const asked = Date.now(); !up && Date.now() - asked < 60_000;) up = (await said(500)).includes("side-ready");
    assert.ok(up, "the app came up");

    await simulators.start();
    for (let i = 0; i < 10 && !hub.get(`simulator:${udid}`); i++) await simulators.refresh();
    const source = hub.get(`simulator:${udid}`);
    assert.ok(source, "listed");
    view = await source.open({ maxWidth: 800, maxHeight: 800, codecs: ["jpeg"] });
    const v = view;
    let last: { w: number; h: number; data: Uint8Array } | null = null;
    void (async () => {
      for (let f = await v.next(); f !== null; f = await v.next()) {
        const size = jpegSize(f.data);
        last = { ...size, data: f.data };
      }
    })();
    const shots = process.env.SIM_OUT ?? dir;
    mkdirSync(shots, { recursive: true });
    const shot = async (name: string) => {
      await v.keyframe?.();
      await sleep(800);
      const now = last as { w: number; h: number; data: Uint8Array } | null;
      assert.ok(now, "a picture");
      writeFileSync(join(shots, `${name}.jpg`), now.data);
      console.log(`${name}: picture ${now.w}x${now.h}; ${simctl("io", udid, "enumerate").split("\n").filter((l) => /Device Name|UI Orientation/.test(l)).map((l) => l.trim()).join(" ")}`);
      return now;
    };
    const first = await shot("1-upright");
    const wideFirst = first.w > first.h;
    // Waited for by its picture, as the Duo's poses are (screen-simulator-duo.test.ts): a Duo's first press starts its guest,
    // as long as DuoHIDBridge gives it. 15 s closed before it turned (side run 41798988101); it turned in 36 s, and every
    // later press at once (side run 41804357060). How soon is printed.
    const settled = async (wide: boolean) => {
      const at = Date.now();
      while (Date.now() - at < 60_000) {
        await sleep(250);
        const now = last as { w: number } & { h: number } | null;
        if (now && now.w > now.h === wide) break;
      }
      console.log(`settled in ${Date.now() - at} ms`);
    };
    await v.input({ t: "device", name: "rotate" });
    await settled(!wideFirst);
    // (the app's log a moment behind its picture)
    const turned: string[] = [];
    for (const asked = Date.now(); !turned.some((t) => t.startsWith("side-shape")) && Date.now() - asked < 60_000;) turned.push(...(await said(500)));
    console.log(`turned: ${JSON.stringify(turned)}`);
    const side = await shot("2-turned");
    assert.notEqual(side.w > side.h, wideFirst, "the picture turned");
    assert.ok(turned.some((t) => t.startsWith("side-shape")), "the app turned");
    // A finger on the turned picture lands where it shows: in the app, a quarter across and three quarters down.
    await v.input({ t: "pointer", kind: "down", x: 0.25, y: 0.75, buttons: 1 });
    await sleep(80);
    await v.input({ t: "pointer", kind: "up", x: 0.25, y: 0.75, buttons: 0 });
    let touched: string | undefined;
    for (const asked = Date.now(); !touched && Date.now() - asked < 60_000;) touched = (await said(500)).find((t) => t.startsWith("side-touch:"));
    console.log(`touched: ${touched}`);
    assert.ok(touched, "the finger came");
    const [tx, ty] = touched.slice("side-touch:".length).split(",").map(Number);
    assert.ok(Math.abs(tx! - 0.25) < 0.05 && Math.abs(ty! - 0.75) < 0.05, `as shown: ${touched}`);
    // Three more quarters: upright again. (Upside down is the app's and the device's to refuse: not asserted.)
    for (let i = 0; i < 3; i++) {
      await v.input({ t: "device", name: "rotate" });
      await sleep(2000);
    }
    await settled(wideFirst);
    console.log(`round: ${JSON.stringify(await said(1000))}`);
    const back = await shot("3-back");
    assert.equal(back.w > back.h, wideFirst, "and back");
  } finally {
    view?.close();
    simulators.close();
    debug.close();
    // (the station's own, as this Mac granted it: left running)
    if (!process.env.STILLFAIL_HELPER_DIR) await helper.quit();
    try {
      simctl("shutdown", udid);
    } catch {}
    simctl("delete", udid);
    rmSync(dir, { recursive: true, force: true });
  }
});

/// The width and height a JPEG says of itself.
function jpegSize(d: Uint8Array): { w: number; h: number } {
  for (let i = 2; i + 9 < d.length;) {
    if (d[i] !== 0xff) { i++; continue; }
    const m = d[i + 1]!;
    if (m >= 0xc0 && m <= 0xc3) return { h: (d[i + 5]! << 8) | d[i + 6]!, w: (d[i + 7]! << 8) | d[i + 8]! };
    i += 2 + ((d[i + 2]! << 8) | d[i + 3]!);
  }
  return { w: 0, h: 0 };
}
