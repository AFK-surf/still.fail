// An iPhone Duo folded through still.fail Helper's view as a person folds it, on a real
// Mac with Xcode: a simulator of this test's own, no window of Device Hub's. Each pose's panel shows in the view's picture,
// and its panels' corners are read from its type's masks. STILLFAIL_HELPER and STILLFAIL_HELPER_DIR: another helper; SIM_OUT:
// where its pictures go. A side test.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { HelperApp } from "../src/helper/app.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import { SIMCTL, Simulators } from "../src/screens/simulator.ts";
import type { ScreenView } from "../src/screens/source.ts";

const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const LONG = 5 * 60_000;
const simctl = (...args: string[]) => execFileSync(SIMCTL, args, { encoding: "utf8", timeout: LONG }).trim();
const hasSimctl = platform() === "darwin" && existsSync(SIMCTL);

/// A JPEG's width by height, as its frame header says them.
function shape(jpeg: Uint8Array): number {
  for (let i = 2; i + 8 < jpeg.length; i += 2 + ((jpeg[i + 2]! << 8) | jpeg[i + 3]!)) {
    if (jpeg[i] === 0xff && jpeg[i + 1] === 0xc0) return ((jpeg[i + 7]! << 8) | jpeg[i + 8]!) / ((jpeg[i + 5]! << 8) | jpeg[i + 6]!);
  }
  return 0;
}

test("an iPhone Duo's poses, its picture following", { skip: !hasSimctl && "no Xcode simulators here", timeout: LONG }, async () => {
  const runtimes = JSON.parse(simctl("list", "-j", "runtimes")).runtimes.filter((r: any) => r.isAvailable && r.supportedDeviceTypes?.some((t: any) => t.identifier.endsWith(".iPhone-Duo")));
  if (runtimes.length === 0) return;
  const runtime = runtimes.at(-1);
  const udid = simctl("create", `still.fail side duo ${process.pid}`, "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo", runtime.identifier);
  const dir = mkdtempSync(join(tmpdir(), "sim-duo-"));
  const helper = new HelperApp({ app: process.env.STILLFAIL_HELPER ?? execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", "helper"], { encoding: "utf8" }).trim(), dir: process.env.STILLFAIL_HELPER_DIR ?? join(dir, "helper") });
  const hub = new ScreenHub();
  const simulators = new Simulators({ screens: hub, helper });
  let view: ScreenView | null = null;
  try {
    simctl("boot", udid);
    simctl("bootstatus", udid, "-b");
    await simulators.start();
    for (let i = 0; i < 10 && !hub.get(`simulator:${udid}`); i++) await simulators.refresh();
    const source = hub.get(`simulator:${udid}`);
    assert.ok(source, "listed");
    assert.equal(source.poses, true);
    assert.equal(source.panels?.length, 2);
    console.log("panels", JSON.stringify(source.panels));

    view = await source.open({ maxWidth: 1000, maxHeight: 1400, codecs: ["jpeg"] });
    const v = view;
    let last: Uint8Array | null = null;
    const pulling = (async () => {
      for (let f = await v.next(); f !== null; f = await v.next()) last = f.data;
    })();
    await sleep(8000);
    const shots = process.env.SIM_OUT ?? dir;
    mkdirSync(shots, { recursive: true });
    const look = async (name: string) => {
      await v.keyframe?.();
      await sleep(800);
      assert.ok(last, "a picture");
      writeFileSync(join(shots, `duo-${name}.jpg`), last);
      const s = shape(last);
      console.log(name, s);
      return s;
    };
    const cover = 1398 / 2034;
    const inner = 2853 / 2007;
    const near = (a: number, b: number, what: string) => assert.ok(Math.abs(a - b) < 0.006, `${what}: ${a}, not ${b}`);

    await look("first");
    // A finger on the cover: the device's input process (backboardd) goes on as it was, its picture still there.
    const backboardd = () => /(\d+)\s+\S+\s+com\.apple\.backboardd/.exec(simctl("spawn", udid, "launchctl", "list"))?.[1];
    const running = backboardd();
    const tap = async (x: number, y: number) => {
      await v.input({ t: "pointer", kind: "down", x, y, buttons: 1 });
      await sleep(80);
      await v.input({ t: "pointer", kind: "up", x, y, buttons: 0 });
    };
    // Settings opened by a finger on its icon: a picture of the app's own, then back to the home screen (⇧⌘H).
    const opens = async (x: number, y: number, name: string) => {
      const home = await picture(name + "-home");
      // Waited for by its picture, not a fixed 5 s: Settings had not shown in 5 s once (side run 41554130845);
      // how long it took is said, and one not shown in a minute fails as before.
      const asked = Date.now();
      await tap(x, y);
      let changed = 0;
      let tapped = asked;
      while ((changed = differs(home, await picture(name + "-settings"))) <= 0.2 && Date.now() - asked < 60_000) {
        await sleep(1000);
        // (a tap as the device still turns to the pose lands on nothing, as a person's: tried again)
        if (Date.now() - tapped > 10_000) {
          tapped = Date.now();
          await tap(x, y);
        }
      }
      console.log(name, "changed", changed, "in", Date.now() - asked, "ms");
      assert.ok(changed > 0.2, `${name}: its picture did not change (${changed})`);
      assert.equal(backboardd(), running, `a touch in ${name} took backboardd down`);
      await v.input({ t: "key", kind: "down", key: "h", code: "KeyH", mods: 12 });
      await v.input({ t: "key", kind: "up", key: "h", code: "KeyH", mods: 12 });
      await sleep(3000);
    };
    const picture = async (name: string) => {
      await look(name);
      const file = join(shots, `duo-${name}.jpg`), raw = join(dir, `${name}.bmp`);
      execFileSync("sips", ["-s", "format", "bmp", file, "--out", raw], { stdio: "ignore" });
      return readFileSync(raw);
    };
    /// How much of two pictures of one size differ.
    const differs = (a: Buffer, b: Buffer) => {
      let n = 0;
      for (let i = 0; i < a.length; i += 3) if (Math.abs(a[i]! - b[i]!) > 24) n++;
      return n / (a.length / 3);
    };
    await opens(0.12, 0.13, "cover");
    // Each pose waited for by its picture, not a fixed time: the first unfolding had not shown in 5 s (side run
    // 41517988497); how long each took is said, and one not shown in a minute fails with the shape it was left at.
    for (const [name, want] of [["open", inner], ["closed", cover], ["book", inner], ["open", inner], ["closed", cover]] as const) {
      const asked = Date.now();
      await v.input({ t: "pose", name });
      let s = 0;
      while (Math.abs((s = await look(`${name}-${want === cover ? "cover" : "inner"}`)) - want) >= 0.006 && Date.now() - asked < 60_000) await sleep(1000);
      console.log(name, "shown in", Date.now() - asked, "ms");
      near(s, want, name);
      if (name === "open" && want === inner) await opens(0.525, 0.125, "inner");
    }

    v.close();
    view = null;
    await pulling;

    // Opened again on the inner panel, after all those folds: the picture its shape from the first, not back through them.
    const unfolding = await hub.get(`simulator:${udid}`)!.open({ maxWidth: 1000, maxHeight: 1400, codecs: ["jpeg"] });
    view = unfolding;
    // Waited for by its picture, as the poses above: a new view's first pose took 6.2 s, and a fixed 5 s closed
    // the view before it had unfolded (side run 41635377489).
    let unfolded = 0;
    const following = (async () => {
      for (let f = await unfolding.next(); f !== null; f = await unfolding.next()) unfolded = shape(f.data);
    })();
    const asked = Date.now();
    await unfolding.input({ t: "pose", name: "open" });
    while (Math.abs(unfolded - inner) >= 0.006 && Date.now() - asked < 60_000) await sleep(500);
    console.log("unfolded in", Date.now() - asked, "ms");
    near(unfolded, inner, "unfolded");
    unfolding.close();
    await following;
    await sleep(1000);
    const again = await hub.get(`simulator:${udid}`)!.open({ maxWidth: 1000, maxHeight: 1400, codecs: ["jpeg"] });
    view = again;
    const shapes: number[] = [];
    const seen = (async () => {
      for (let f = await again.next(); f !== null; f = await again.next()) shapes.push(shape(f.data));
    })();
    // (a first picture may be slow to come; then long enough to see any it goes through)
    for (const asked = Date.now(); shapes.length === 0 && Date.now() - asked < 60_000;) await sleep(250);
    await sleep(6000);
    again.close();
    view = null;
    await seen;
    console.log("shapes on opening", shapes.map((n) => n.toFixed(3)).join(" "));
    assert.ok(shapes.length > 0, "a picture");
    near(shapes.at(-1)!, inner, "at the end");
    const wrong = shapes.filter((n) => Math.abs(n - inner) >= 0.006);
    assert.ok(wrong.length <= 1, `its picture went through other shapes: ${shapes}`);
  } finally {
    view?.close();
    simulators.close();
    if (!process.env.STILLFAIL_HELPER_DIR) await helper.quit();
    try {
      simctl("shutdown", udid);
    } catch {}
    simctl("delete", udid);
    rmSync(dir, { recursive: true, force: true });
  }
});
