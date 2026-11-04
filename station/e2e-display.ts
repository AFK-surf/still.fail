// Scratch (not committed): the station's PhoneDisplays against a real emulator.
import { execSync } from "node:child_process";
import { PhoneDisplays } from "./src/adb/displays.ts";
const adb = `${process.env.HOME}/Library/Android/sdk/platform-tools/adb`;
const serial = process.argv[2]!;
const sh = (c: string) => execSync(`${adb} -s ${serial} ${c}`, { encoding: "utf8" });
const d = new PhoneDisplays({ adb: () => adb, usedAt: () => Date.now(), changed: (o) => console.log("changed", o, d.titles(o)) });
const t0 = Date.now();
const disp = await d.open("g1", "me", "测试", 5037, serial);
console.log("opened in", Date.now() - t0, "ms", disp);
console.log(sh(`shell am start --display ${disp.id} -n com.android.settings/.Settings`));
for (const [i, ms] of [[1, 2000], [2, 3000], [3, 4000]] as const) {
  await new Promise((r) => setTimeout(r, ms));
  execSync(`${adb} -s ${serial} exec-out screencap -d ${disp.surface} -p > ../e2e-vd${i}.png`);
}
execSync(`${adb} -s ${serial} exec-out screencap -p > ../e2e-main.png`);
console.log(sh(`shell input -d ${disp.id} tap 540 720`));
for (const [i, ms] of [[1, 1500], [2, 3000]] as const) {
  await new Promise((r) => setTimeout(r, ms));
  execSync(`${adb} -s ${serial} exec-out screencap -d ${disp.surface} -p > ../e2e-tap${i}.png`);
}
console.log(sh(`shell dumpsys activity activities`).split("\n").filter((l) => /Display #|topResumedActivity/.test(l)).join("\n"));
d.close("g1");
await new Promise((r) => setTimeout(r, 2000));
console.log("after close:");
console.log(sh(`shell dumpsys activity activities`).split("\n").filter((l) => /Display #|topResumedActivity|Settings/.test(l)).slice(0, 8).join("\n"));
console.log(sh(`shell dumpsys display`).split("\n").filter((l) => l.includes("mBaseDisplayInfo")).length, "displays");
d.closeAll();
process.exit(0);
