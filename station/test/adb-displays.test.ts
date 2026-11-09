import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { AdbActivity } from "../src/adb/activity.ts";
import { PhoneDisplays, densityOf, displayOf, rootTasksOn, surfaceOf } from "../src/adb/displays.ts";
import { reached } from "../src/adb/tool.ts";

test("the display scrcpy made, as it says it", () => {
  assert.deepEqual(displayOf("[server] INFO: Device: [Google] x (Android 16)\n[server] INFO: New display: 1080x2400/420 (id=2)\n"), { width: 1080, height: 2400, density: 420, id: 2 });
  assert.equal(displayOf("[server] INFO: Device: x"), null);
});

test("the phone's density: the override over the physical", () => {
  assert.equal(densityOf("Physical density: 420\n"), 420);
  assert.equal(densityOf("Physical density: 420\nOverride density: 360\n"), 360);
  assert.equal(densityOf(""), 0);
});

// What an Android 16 emulator said (2026-11-04), shortened.
const DISPLAYS = [
  `    mBaseDisplayInfo=DisplayInfo{"Built-in Screen", displayId 0, displayGroupId 0, FLAG_SECURE, real 1080 x 2400, type INTERNAL, uniqueId "local:4619827259835644672", app 1080 x 2400}`,
  `    mBaseDisplayInfo=DisplayInfo{"scrcpy", displayId 2, displayGroupId 1, FLAG_PRESENTATION, real 1080 x 2400, type VIRTUAL, uniqueId "virtual:com.android.shell,2000,scrcpy,1", owner com.android.shell (uid 2000)}`,
  `    mBaseDisplayInfo=DisplayInfo{"scrcpy", displayId 12, displayGroupId 2, FLAG_PRESENTATION, real 1080 x 2400, type VIRTUAL, uniqueId "virtual:com.android.shell,2000,scrcpy,0", owner com.android.shell (uid 2000)}`,
].join("\n");
const FLINGER = [
  `Display 4619827259835644672 (HWC display 0): port=0 pnpId=GGL displayName="EMU_display_0"`,
  `Display 11529215046400789845 (Virtual display): displayName="scrcpy" uniqueId="virtual:com.android.shell,2000,scrcpy,0"`,
  `Display 11529215049899194809 (Virtual display): displayName="scrcpy" uniqueId="virtual:com.android.shell,2000,scrcpy,1"`,
].join("\n");

test("screencap's id of a display: SurfaceFlinger's, by its unique id, whatever other chats' are up", async () => {
  const none = async () => assert.fail("not needed");
  assert.equal(await surfaceOf(DISPLAYS, FLINGER, 2, none), "11529215049899194809");
  assert.equal(await surfaceOf(DISPLAYS, FLINGER, 12, none), "11529215046400789845");
  // (Android 12: SurfaceFlinger names no virtual display, screencap takes Android's id)
  assert.equal(await surfaceOf(DISPLAYS, FLINGER.split("\n")[0]!, 2, none), null);
  assert.equal(await surfaceOf(DISPLAYS, FLINGER, 3, none), null);
});

test("the root tasks on a display, as am stack list says them", () => {
  const list = [
    "RootTask id=7723 bounds=[0,0][1140,2616] displayId=13 userId=0",
    " configuration={1.0 ?? displayId=13}",
    "  taskId=7723: com.android.settings/com.oplus.settings.feature.homepage.OplusSettingsHomepageActivity bounds=[0,0][1140,2616] userId=0 visible=true",
    "RootTask id=7720 bounds=[0,0][1140,2616] displayId=0 userId=0",
    "RootTask id=7721 bounds=[0,0][1140,2616] displayId=13 userId=0",
  ].join("\n");
  assert.deepEqual(rootTasksOn(list, 13), [7723, 7721]);
  assert.deepEqual(rootTasksOn(list, 0), [7720]);
  assert.deepEqual(rootTasksOn(list, 2), []);
});

test("screencap's id of a display where SurfaceFlinger names no unique ids: by its layer stack", async () => {
  // What an OPPO Find N on ColorOS 17 (Android 17) said (2026-11-04), shortened: screencap refused -d 12.
  const displays = [
    `    mBaseDisplayInfo=DisplayInfo{"内屏", displayId 0, displayGroupId 0, FLAG_SECURE, real 1140 x 2616, type INTERNAL, uniqueId "local:4630946165954792596", layerStack 0, app 1140 x 2616}`,
    `    mBaseDisplayInfo=DisplayInfo{"scrcpy", displayId 12, displayGroupId 0, FLAG_SECURE, real 1140 x 2616, type VIRTUAL, uniqueId "virtual:com.android.shell,2000,scrcpy,1", layerStack 12, owner com.android.shell (uid 2000)}`,
    `    mBaseDisplayInfo=DisplayInfo{"scrcpy", displayId 13, displayGroupId 0, FLAG_SECURE, real 1140 x 2616, type VIRTUAL, uniqueId "virtual:com.android.shell,2000,scrcpy,0", layerStack 13, owner com.android.shell (uid 2000)}`,
  ].join("\n");
  const ids = [
    `Display 4630946317637160339 (HWC display 0): port=147 pnpId=QCM screenPartStatus=UNSUPPORTED displayName=""`,
    `Display 11529215049903610350 (Virtual display): displayName="scrcpy"`,
    `Display 11529215046400789845 (Virtual display): displayName="scrcpy"`,
  ].join("\n");
  const flinger = async () => [
    `Display 4630946165954792596 (physical, "")`,
    `   layerFilter={layerStack=0 toInternalDisplay=true skipScreenshot=false }`,
    ``,
    `Display 11529215046400789845 (virtual, "scrcpy")`,
    `   Composition Display State:`,
    `   layerFilter={layerStack=13 toInternalDisplay=false skipScreenshot=false }`,
    `Display 11529215049903610350 (virtual, "scrcpy")`,
    `   Composition Display State:`,
    `   isEnabled=true isSecure=false usesDeviceComposition=false `,
    `   layerFilter={layerStack=12 toInternalDisplay=false skipScreenshot=false }`,
  ].join("\n");
  assert.equal(await surfaceOf(displays, ids, 12, flinger), "11529215049903610350");
  assert.equal(await surfaceOf(displays, ids, 13, flinger), "11529215046400789845");
  assert.equal(await surfaceOf(displays, ids, 3, flinger), null);
});

function packet(name: string, id = 0, payload = ""): Buffer {
  const data = Buffer.from(payload);
  const head = Buffer.alloc(24);
  const command = Buffer.from(name).readUInt32LE();
  head.writeUInt32LE(command, 0);
  head.writeUInt32LE(id, 4);
  head.writeUInt32LE(data.length, 12);
  head.writeUInt32LE(~command >>> 0, 20);
  return Buffer.concat([head, data]);
}

test("what holds the display up and the station's looks at it are not the agent's use; the agent's on it is", () => {
  const used: boolean[] = [];
  const activity = new AdbActivity("fail.still.android", (force) => used.push(force));
  activity.take(Buffer.concat([
    packet("OPEN", 1, "shell,v2,raw:STILLFAIL_ADB_KEEP=1 STILLFAIL_ADB_DISPLAY=1 CLASSPATH=/data/local/tmp/stillfail-display-0000abcd.jar app_process / com.genymobile.scrcpy.Server 5.0.1\0"),
    packet("WRTE", 1, "[server] INFO: New display"),
    packet("OPEN", 2, "localabstract:scrcpy_0000abcd\0"),
    packet("WRTE", 2, "a frame"),
    packet("OPEN", 3, "shell,v2,raw:STILLFAIL_ADB_KEEP=1 STILLFAIL_ADB_DISPLAY=1 dumpsys display\0"),
    packet("CLSE", 3),
  ]));
  assert.deepEqual(used, []);
  activity.take(Buffer.concat([packet("OPEN", 4, "shell,v2,raw:input -d 2 tap 50 50\0"), packet("CLSE", 4)]));
  assert.deepEqual(used, [true, true]);
});

test("phone_use says the chat's own screen and how to work on it, or why there is none", () => {
  const phones = [{ serial: "127.0.0.1:37001", adb: "connected", device: "Pixel 8" }];
  const said = reached(phones, 41000, null, { id: 2, surface: "11529215049899194809", width: 1080, height: 2400, density: 420 });
  assert.match(said, /adb -P 41000 -s 127\.0\.0\.1:37001/);
  assert.match(said, /display 2 \(1080x2400, density 420\)/);
  assert.match(said, /am start --display 2 /);
  assert.match(said, /input -d 2 tap/);
  assert.match(said, /screencap -d 11529215049899194809 -p/);
  assert.match(reached(phones, 41000, null, { failed: "scrcpy ended" }), /could not be made \(scrcpy ended\).*ask them in the chat before you operate it/);
  assert.doesNotMatch(reached(phones, 41000, null, null), /display/);
});

test("a display made on the phone in the grant's adb server, held while it is used, closed when idle", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-displays-"));
  const calls = join(dir, "calls");
  // What scrcpy's video socket is on the phone: says its first byte, then frames.
  const phone = net.createServer((s) => (s.write(Buffer.from([0])), s.on("error", () => {})));
  await new Promise<void>((r) => phone.listen(0, "127.0.0.1", () => r()));
  const port = (phone.address() as net.AddressInfo).port;
  const adb = join(dir, "adb");
  writeFileSync(adb, `#!/bin/sh
echo "$*" >> "${calls}"
case "$*" in
  *"forward tcp:0"*) echo ${port} ;;
  *ro.build.version.sdk*) echo 34 ;;
  *"stat -c"*) [ -e "${dir}/pushed" ] && wc -c < "${adb}" ;;
  push*|*" push "*) touch "${dir}/pushed" ;;
  *"wm size"*) echo 'Physical size: 1080x2400' ;;
  *"wm density"*) echo 'Physical density: 420' ;;
  *app_process*) echo '[server] INFO: New display: 1080x2400/420 (id=2)'; exec sleep 60 ;;
  *"am stack list"*) printf 'RootTask id=7 bounds=[0,0][1080,2400] displayId=2 userId=0\n  taskId=7: com.android.settings/.Settings\nRootTask id=1 bounds=[0,0][1080,2400] displayId=0 userId=0\n' ;;
  *"dumpsys display"*) cat <<'EOF'
${DISPLAYS}
EOF
  ;;
  *"dumpsys SurfaceFlinger"*) cat <<'EOF'
${FLINGER}
EOF
  ;;
esac
`);
  chmodSync(adb, 0o755);
  const changed: string[][] = [];
  let usedAt: number | null = Date.now();
  const displays = new PhoneDisplays({ adb: () => adb, file: adb, usedAt: () => usedAt, changed: (owner) => changed.push([owner, ...displays.titles(owner)]), idleMs: 60_000 });
  try {
    const [a, b] = await Promise.all([displays.open("g1", "p@x", "修登录页", 41000, "127.0.0.1:37001"), displays.open("g1", "p@x", "修登录页", 41000, "127.0.0.1:37001")]);
    assert.deepEqual(a, { id: 2, width: 1080, height: 2400, density: 420, surface: "11529215049899194809" });
    assert.equal(a, b, "one display for two asks at once");
    assert.deepEqual(changed, [["p@x", "修登录页"]]);
    const said = readFileSync(calls, "utf8");
    const scrcpy = said.split("\n").find((l) => l.includes("app_process"))!;
    assert.match(scrcpy, /^-P 41000 -s 127\.0\.0\.1:37001 shell STILLFAIL_ADB_KEEP=1 STILLFAIL_ADB_DISPLAY=1 CLASSPATH=\/data\/local\/tmp\/stillfail-display-5\.0\.1\.jar /);
    // (its keyboard hidden, not taken over from the person's screen: display_ime_policy=local held it there)
    assert.match(scrcpy, / new_display=1080x2400\/420 display_ime_policy=hide/);
    assert.doesNotMatch(scrcpy, /display_ime_policy=(local|fallback)/);
    assert.match(scrcpy, / control=false .* max_size=320 max_fps=1 /);
    // Used a while ago: kept; past the idle time: closed, and the phone told.
    displays.idle();
    assert.equal(displays.has("g1"), true);
    usedAt = Date.now() - 120_000;
    // (made just now: its own making counts as use)
    displays.idle();
    assert.equal(displays.has("g1"), true);
    usedAt = null;
    displays.idle();
    assert.equal(displays.has("g1"), false, "a grant no longer live");
    assert.deepEqual(changed.at(-1), ["p@x"]);
    // Asked again: made anew, scrcpy's program not put on the phone again.
    await displays.open("g1", "p@x", "修登录页", 41000, "127.0.0.1:37001");
    assert.equal(readFileSync(calls, "utf8").split("\n").filter((l) => / push /.test(l)).length, 1);
    assert.equal(displays.has("g1"), true);
    const closed = displays.close("g1");
    assert.equal(displays.has("g1"), false);
    // Its apps closed before it, the person's screen's left alone, and all that done when the close is (the grant's
    // adb server is stopped only then: stopped at once, the apps were never closed).
    await closed;
    assert.match(readFileSync(calls, "utf8"), /shell STILLFAIL_ADB_KEEP=1 STILLFAIL_ADB_DISPLAY=1 am stack remove 7\n/);
  } finally {
    displays.closeAll();
    phone.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
