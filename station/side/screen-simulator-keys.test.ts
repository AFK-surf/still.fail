// What a person's keys do on an iOS Simulator (docs/remote-screens.md "Simulators") on a real Mac with Xcode: a simulator
// of this test's own, a small app whose focused field logs what it holds, keys and pasted text sent through still.fail
// Helper's view as a person's are. Xcode 27's guest takes keys only through a focused Device Hub window
// (vendor/serve-sim DeviceHubKeyboardBridge), so what arrives is said both without that window and with it, not held to:
// it depends on this Mac's Accessibility grant and on what else is on its screen. STILLFAIL_HELPER and STILLFAIL_HELPER_DIR:
// the station's own helper, with the grants it has. A side test.
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
const APP = "fail.still.side.keys";
const SOURCE = `
import UIKit
import os
let logger = Logger(subsystem: "fail.still.side", category: "side")
@objc(SideScene) class Scene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  let field = UITextField()
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    window = UIWindow(windowScene: scene as! UIWindowScene)
    let root = UIViewController()
    root.view.backgroundColor = .white
    field.frame = CGRect(x: 20, y: 120, width: 300, height: 44)
    field.borderStyle = .roundedRect
    field.addTarget(self, action: #selector(changed), for: .editingChanged)
    root.view.addSubview(field)
    window!.rootViewController = root
    window!.makeKeyAndVisible()
    field.becomeFirstResponder()
    logger.error("side-ready")
  }
  @objc func changed() { logger.error("side-holds:\\(self.field.text ?? "", privacy: .public)") }
}
@objc(SideDelegate) class Delegate: UIResponder, UIApplicationDelegate {}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, "SideDelegate")
`;
const PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${APP}</string>
<key>CFBundleName</key><string>SideKeys</string>
<key>CFBundleExecutable</key><string>SideKeys</string>
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
const simctl = (...args: string[]) => execFileSync(SIMCTL, args, { encoding: "utf8", timeout: LONG }).trim();
const hasSimctl = platform() === "darwin" && existsSync(SIMCTL);
const run = (file: string, args: string[]) => Promise.resolve(execFileSync(file, args, { encoding: "utf8", maxBuffer: 16 << 20, timeout: 60_000 }));

test("keys and text on a simulator, with and without its Device Hub window", { skip: !hasSimctl && "no Xcode simulators here" }, async () => {
  const runtimes = JSON.parse(simctl("list", "-j", "runtimes")).runtimes.filter((r: any) => r.isAvailable && r.platform === "iOS");
  const runtime = runtimes.at(-1);
  const type = runtime.supportedDeviceTypes.find((t: any) => t.productFamily === "iPhone");
  const udid = simctl("create", `still.fail side keys ${process.pid}`, type.identifier, runtime.identifier);
  const dir = mkdtempSync(join(tmpdir(), "sim-keys-"));
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
    simctl("bootstatus", udid, "-b");
    const app = join(dir, "SideKeys.app");
    mkdirSync(app);
    writeFileSync(join(dir, "main.swift"), SOURCE);
    writeFileSync(join(app, "Info.plist"), PLIST);
    const sdk = xcrun("--sdk", "iphonesimulator", "--show-sdk-path");
    xcrun("--sdk", "iphonesimulator", "swiftc", "-target", `${process.arch === "arm64" ? "arm64" : "x86_64"}-apple-ios17.0-simulator`, "-sdk", sdk, join(dir, "main.swift"), "-o", join(app, "SideKeys"));
    execFileSync("codesign", ["-s", "-", "--force", app]);
    simctl("install", udid, app);
    debug.logs(0);
    await sleep(1500);
    assert.equal(await debug.relaunch(APP), true);
    assert.ok((await said(6000)).includes("side-ready"), "the app came up");

    await simulators.start();
    for (let i = 0; i < 10 && !hub.get(`simulator:${udid}`); i++) await simulators.refresh();
    const source = hub.get(`simulator:${udid}`);
    assert.ok(source, "listed");
    view = await source.open({ maxWidth: 800, maxHeight: 800, codecs: ["jpeg"] });
    const v = view;
    // What a viewer sees: the view's own last picture, a JPEG, whichever of a foldable's screens simctl's shows.
    let last: Uint8Array | null = null;
    const pulling = (async () => {
      for (let f = await v.next(); f !== null; f = await v.next()) last = f.data;
    })();

    const shots = process.env.SIM_OUT ?? dir;
    mkdirSync(shots, { recursive: true });
    const shot = async (name: string) => {
      await v.keyframe?.();
      await sleep(500);
      if (last !== null) writeFileSync(join(shots, `${name}-view.jpg`), last);
    };
    console.log(simctl("io", udid, "enumerate").split("\n").filter((l) => /Display|Class|Port|Default|State|Width|Height|Name/i.test(l)).join(" | ").slice(0, 700));
    // The field touched, as a finger does: its keyboard up where the app's own focus did not bring it.
    const size = source.size();
    const scale = 3;
    const at = { x: 0.5, y: (142 * scale) / (size.height || 2622) };
    await v.input({ t: "pointer", kind: "down", x: at.x, y: at.y, buttons: 1 });
    await v.input({ t: "pointer", kind: "up", x: at.x, y: at.y, buttons: 0 });
    await sleep(2000);
    await shot("1-touched");

    // The device's own keyboard, touched: whatever the keys above did. Its tip put away, then a finger along where its rows
    // are.
    const tap = async (x: number, y: number) => {
      await v.input({ t: "pointer", kind: "down", x, y, buttons: 1 });
      await sleep(80);
      await v.input({ t: "pointer", kind: "up", x, y, buttons: 0 });
      await sleep(300);
    };
    await tap(0.5, 0.92);
    await sleep(1500);
    await shot("2-tip-gone");
    for (const y of [0.72, 0.78, 0.84]) for (const x of [0.1, 0.3, 0.5, 0.7, 0.9]) await tap(x, y);
    await shot("3-touched-keys");
    console.log(`the device's keyboard, touched: ${JSON.stringify(await said(1500))}`);

    const type_ = async (text: string) => {
      await v.input({ t: "text", text });
      return said(3000);
    };
    console.log(`no Device Hub window: keys ${JSON.stringify(await type_("abc"))}`);
    console.log(`no Device Hub window: pasted ${JSON.stringify(await type_("中文"))}`);
    await shot("4-no-hub");

    execFileSync("open", [`devices://device/open?id=${udid}`], { timeout: 30_000 });
    await sleep(5000);
    console.log(`Device Hub window: keys ${JSON.stringify(await type_("def"))}`);
    console.log(`Device Hub window: pasted ${JSON.stringify(await type_("汉字"))}`);
    await shot("5-hub");
    // Keys sent put the device in a hardware keyboard's mode, its own keyboard gone: whether 软键盘 brings it back, to see.
    await v.input({ t: "key", kind: "down", key: "k", code: "KeyK", mods: 4 });
    await v.input({ t: "key", kind: "up", key: "k", code: "KeyK", mods: 4 });
    await sleep(2000);
    await shot("5b-keyboard-back");

    // The settings a person changes from the device's panel, and its picture, as simctl does them.
    await debug.setSetting("appearance", "dark");
    await debug.setSetting("textSize", "extra-large");
    const settings = await debug.settings();
    assert.deepEqual(settings, { appearance: "dark", textSize: "extra-large" });
    await debug.setSetting("appearance", "light");
    await debug.setSetting("textSize", "large");
    const picture = await source.debug!.screenshot();
    writeFileSync(join(shots, "6-screenshot.png"), picture);
    assert.equal(picture.subarray(0, 4).toString("latin1"), "\x89PNG");
    console.log(`a screenshot: ${picture.length} bytes`);

    v.close();
    view = null;
    await pulling;
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
