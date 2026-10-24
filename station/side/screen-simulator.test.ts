// An iOS Simulator as a screen (docs/remote-screens.md "Simulators") on a real Mac with Xcode: a simulator of this
// test's own made and booted (deleted afterwards), found as the station finds it, viewed through still.fail Helper
// (native/helper, prebuilt by scripts/native.ts; STILLFAIL_HELPER another) as the station starts it. A finger dragged
// across its home screen: says how soon the first picture after it came, the frames a second while it moved, and how
// many came in 2 s once it settled (said, not asserted: the device draws when it will, a home screen just booted
// still animating); keeps the last picture (a JPEG view) in SIM_OUT. Real time, a real device: a side test.
// SIM_CODEC: the view's codec (default h264; jpeg where this Mac encodes no video, a virtual one).
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { HelperApp } from "../src/helper/app.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import { Simulators } from "../src/screens/simulator.ts";
import type { Codec, Frame, ScreenView } from "../src/screens/source.ts";

const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const OUT = process.env.SIM_OUT ?? mkdtempSync(join(tmpdir(), "screen-simulator-"));
const CODEC = (process.env.SIM_CODEC ?? "h264") as Codec;
const simctl = (...args: string[]) => execFileSync("xcrun", ["simctl", ...args], { encoding: "utf8" }).trim();
const hasSimctl = (() => {
  if (platform() !== "darwin") return false;
  try {
    simctl("help");
    return true;
  } catch {
    return false;
  }
})();

/// The newest iOS runtime installed, and an iPhone it runs.
function device(): { runtime: string; type: string } {
  const runtimes = JSON.parse(simctl("list", "-j", "runtimes")).runtimes.filter((r: any) => r.isAvailable && r.platform === "iOS");
  const runtime = runtimes.at(-1);
  const type = runtime.supportedDeviceTypes.find((t: any) => t.productFamily === "iPhone");
  return { runtime: runtime.identifier, type: type.identifier };
}

test("a simulator, seen and driven through still.fail Helper", { skip: !hasSimctl && "no Xcode simulators here" }, async () => {
  const { runtime, type } = device();
  const udid = simctl("create", `still.fail side ${process.pid}`, type, runtime);
  const helper = new HelperApp({ app: process.env.STILLFAIL_HELPER ?? execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", "helper"], { encoding: "utf8" }).trim(), dir: join(OUT, "data", "helper") });
  const hub = new ScreenHub();
  const simulators = new Simulators({ screens: hub, helper });
  let view: ScreenView | null = null;
  try {
    simctl("bootstatus", udid, "-b");
    await simulators.start();
    // A Mac busy booting it may not list it at once: looked at again, as a person's list is.
    for (let i = 0; i < 10 && !hub.get(`simulator:${udid}`); i++) await simulators.refresh();
    const source = hub.get(`simulator:${udid}`);
    assert.ok(source, "the booted simulator is listed");
    console.log(`listed: ${source.title()}, ${source.size().width}×${source.size().height}`);

    view = await source.open({ maxWidth: 1920, maxHeight: 1080, codecs: [CODEC] });
    const frames: { at: number; frame: Frame }[] = [];
    // Two frames asked at a time, as the pace asks before it knows the link.
    let ended = false;
    const pull = async () => {
      while (!ended) {
        const frame = await view!.next();
        if (frame === null) return;
        frames.push({ at: performance.now(), frame });
      }
    };
    const pulling = [pull(), pull()];
    const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
    while (frames.length === 0) await sleep(20);
    const config = frames[0]!.frame.config!;
    console.log(`first picture: ${config.codec} ${config.width}×${config.height}, ${JSON.stringify(view.video?.())}`);
    assert.equal(config.height, 1080, "fitted into the view's bounds");

    // A finger across the home screen and back, a few times: how soon a picture follows it, and how many while it moves.
    const after: number[] = [];
    let moving = 0;
    const started = performance.now();
    for (let k = 0; k < 4; k++) {
      const [from, to] = k % 2 ? [0.2, 0.8] : [0.8, 0.2];
      const before = frames.length;
      const down = performance.now();
      await view.input({ t: "pointer", kind: "down", x: from, y: 0.5, buttons: 1 });
      for (let s = 1; s <= 30; s++) {
        await view.input({ t: "pointer", kind: "move", x: from + ((to - from) * s) / 30, y: 0.5, buttons: 1 });
        await sleep(16);
      }
      await view.input({ t: "pointer", kind: "up", x: to, y: 0.5, buttons: 0 });
      // (the drag's picture, whenever it comes: how soon is said, not held to a time. Taken right at the finger's lift,
      // a picture the simulator drew a moment later counted as none, "every drag showed 3 !== 4", 2026-10-24)
      while (frames.length === before) await sleep(20);
      const first = frames[before]!;
      after.push(Math.round(first.at - down));
      moving += frames.length - before;
      await sleep(1000);
    }
    const seconds = (performance.now() - started) / 1000;
    // Settled: what the device drew by itself meanwhile, if anything.
    await sleep(1500);
    const still = frames.length;
    await sleep(2000);
    const stillFrames = frames.length - still;
    console.log(`a picture ${after.join(", ")} ms after the finger went down; ${(moving / seconds).toFixed(1)} frames a second over ${seconds.toFixed(1)} s of dragging and settling; ${stillFrames} in 2 s still`);
    assert.equal(after.length, 4, "every drag showed");
    const last = frames.at(-1)!.frame;
    if (config.codec === "jpeg") writeFileSync(join(OUT, "simulator.jpg"), last.data);
    ended = true;
    view.close();
    await Promise.all(pulling);
  } finally {
    view?.close();
    simulators.close();
    await helper.quit();
    simctl("shutdown", udid);
    simctl("delete", udid);
  }
  console.log(`kept in ${OUT}`);
});
