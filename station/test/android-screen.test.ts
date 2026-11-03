import assert from "node:assert/strict";
import { test } from "node:test";
import { AndroidInput, KEYCODES, ScrcpyStream, adbEnv, avcCOf, avccOf, devicesOf, metaOf, nalsOf, panelsOf, shownDevice, sideOf, sizeOf } from "../src/screens/android.ts";

const size = { width: 1000, height: 2000 };

test("adb's devices: only those ready", () => {
  assert.deepEqual(devicesOf("emulator-5554          device product:a model:b\nABC unauthorized usb:1\n123 offline\n\n"), ["emulator-5554"]);
});

test("a screen: an emulator, USB or an address someone connected to; not what adb found by itself, nor a lent phone", () => {
  for (const serial of ["emulator-5554", "3B162S00P0N00000", "192.168.1.20:5555"]) assert.equal(shownDevice(serial), true, serial);
  for (const serial of ["adb-3B162S00P0N00000-KLb58I._adb-tls-connect._tcp", "adb-3B1._adb._tcp", "127.0.0.1:37715"]) assert.equal(shownDevice(serial), false, serial);
});

test("a server started here connects to no phone by itself", () => {
  assert.equal(adbEnv({ PATH: "/bin" }).ADB_MDNS_AUTO_CONNECT, "0");
  assert.equal(adbEnv({ PATH: "/bin" }).PATH, "/bin");
});

test("the size wm says: the override over the physical", () => {
  assert.deepEqual(sizeOf("Physical size: 1140x2616\n"), { width: 1140, height: 2616 });
  assert.deepEqual(sizeOf("Physical size: 1140x2616\nOverride size: 720x1652\n"), { width: 720, height: 1652 });
  assert.deepEqual(sizeOf("nothing"), { width: 0, height: 0 });
});

test("each display's corners as shares of its width, none where it has none", () => {
  const line = (w: number, h: number, r: number) =>
    `    mBaseDisplayInfo=DisplayInfo{"x", real ${w} x ${h}, roundedCorners RoundedCorners{[RoundedCorner{position=TopLeft, radius=${r}, center=Point(1, 1)}, RoundedCorner{position=TopRight, radius=${r}, center=Point(1, 1)}, RoundedCorner{position=BottomRight, radius=${r}, center=Point(1, 1)}, RoundedCorner{position=BottomLeft, radius=${r}, center=Point(1, 1)}]}, FLAG}`;
  const panels = panelsOf([line(1000, 2000, 100), "other", line(2000, 2200, 50), line(1000, 2000, 100), `mBaseDisplayInfo=DisplayInfo{real 5 x 5, roundedCorners null}`].join("\n"));
  assert.deepEqual(panels, [
    { width: 1000, height: 2000, corners: [0.1, 0.1, 0.1, 0.1] },
    { width: 2000, height: 2200, corners: [0.025, 0.025, 0.025, 0.025] },
  ]);
});

test("a view's size: what it asked, at least 1280 to drive; a preview as small as it asked", () => {
  const options = { codecs: ["h264" as const] };
  assert.equal(sideOf({ ...options, maxWidth: 400, maxHeight: 800 }), 1280);
  assert.equal(sideOf({ ...options, maxWidth: 400, maxHeight: 800, peek: true }), 800);
  assert.equal(sideOf({ ...options, maxWidth: 3840, maxHeight: 2160 }), 2560);
});

test("a finger: down, moves, up, in the picture's pixels with its size", () => {
  const input = new AndroidInput();
  assert.deepEqual(input.messages({ t: "pointer", kind: "move", x: 0.5, y: 0.5, buttons: 0 }, size), []);
  const [down] = input.messages({ t: "pointer", kind: "down", x: 0.5, y: 0.25, buttons: 1 }, size);
  assert.equal(down!.length, 32);
  assert.deepEqual([down![0], down![1]], [2, 0]);
  assert.equal(down!.readBigInt64BE(2), -2n);
  assert.deepEqual([down!.readInt32BE(10), down!.readInt32BE(14), down!.readUInt16BE(18), down!.readUInt16BE(20), down!.readUInt16BE(22)], [500, 500, 1000, 2000, 0xffff]);
  assert.equal(input.messages({ t: "pointer", kind: "move", x: 1, y: 1, buttons: 1 }, size)[0]![1], 2);
  // (at the very edge: within the picture)
  assert.equal(input.messages({ t: "pointer", kind: "move", x: 1, y: 1, buttons: 1 }, size)[0]!.readInt32BE(10), 999);
  const [up] = input.messages({ t: "pointer", kind: "up", x: 1, y: 1, buttons: 0 }, size);
  assert.deepEqual([up![1], up!.readUInt16BE(22)], [1, 0]);
  assert.deepEqual(input.messages({ t: "pointer", kind: "up", x: 1, y: 1, buttons: 0 }, size), []);
});

test("a wheel: 21 bytes, down as a negative vertical scroll in 16ths", () => {
  const [m] = new AndroidInput().messages({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 100 }, size);
  assert.equal(m!.length, 21);
  assert.equal(m![0], 3);
  assert.equal(m!.readInt16BE(13), 0);
  assert.equal(m!.readInt16BE(15), -2048);
  assert.deepEqual(new AndroidInput().messages({ t: "wheel", x: 0, y: 0, dx: 0, dy: 0 }, size), []);
});

test("keys: keycode and meta state; the app's device buttons press the device's", () => {
  const input = new AndroidInput();
  const [a] = input.messages({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 8 }, size);
  assert.equal(a!.length, 14);
  assert.deepEqual([a![0], a![1], a!.readInt32BE(2), a!.readInt32BE(10)], [0, 0, KEYCODES.KeyA, metaOf(8)]);
  assert.equal(metaOf(1 | 2 | 4 | 8), 0x12 | 0x3000 | 0x30000 | 0x41);
  const keycodes = (mods: number, code: string, kind: "down" | "up" = "down") => input.messages({ t: "key", kind, key: "", code, mods }, size).map((m) => [m[1], m.readInt32BE(2)]);
  assert.deepEqual(keycodes(4 | 8, "KeyH"), [[0, 3], [1, 3]]);
  assert.deepEqual(keycodes(4 | 8, "KeyH", "up"), []);
  assert.deepEqual(keycodes(2 | 4 | 8, "KeyH"), [[0, 187], [1, 187]]);
  assert.deepEqual(keycodes(4, "KeyL"), [[0, 26], [1, 26]]);
  assert.deepEqual(keycodes(4, "KeyK"), []);
  assert.deepEqual(keycodes(0, "Escape"), [[0, 4]]);
  assert.deepEqual(keycodes(0, "Nothing"), []);
  assert.deepEqual(input.messages({ t: "device", name: "volume_up" }, size).map((m) => m.readInt32BE(2)), [24, 24]);
  assert.deepEqual(input.messages({ t: "device", name: "memory_warning" }, size), []);
  assert.deepEqual(input.messages({ t: "pose", name: "open" }, size), []);
});

test("text: ASCII as keys, the rest pasted", () => {
  const input = new AndroidInput();
  const [ascii] = input.messages({ t: "text", text: "ok!" }, size);
  assert.deepEqual([ascii![0], ascii!.readUInt32BE(1), ascii!.subarray(5).toString()], [1, 3, "ok!"]);
  const [zh] = input.messages({ t: "text", text: "中文" }, size);
  assert.deepEqual([zh![0], zh!.readBigInt64BE(1), zh![9], zh!.readUInt32BE(10), zh!.subarray(14).toString()], [9, 0n, 1, 6, "中文"]);
  assert.deepEqual(input.messages({ t: "text", text: "" }, size), []);
});

test("Annex B to AVCC: start codes of both lengths, the config's units in its avcC", () => {
  const sps = [0x67, 0x42, 0xc0, 0x1f, 0xaa], pps = [0x68, 0xce], idr = [0x65, 0x88, 0x84];
  const nals = nalsOf(new Uint8Array([0, 0, 0, 1, ...sps, 0, 0, 1, ...pps, 0, 0, 0, 1, ...idr]));
  assert.deepEqual(nals.map((n) => [...n]), [sps, pps, idr]);
  assert.deepEqual([...avcCOf(nals)!], [1, 0x42, 0xc0, 0x1f, 0xff, 0xe1, 0, 5, ...sps, 1, 0, 2, ...pps]);
  assert.equal(avcCOf([new Uint8Array(idr)]), null);
  assert.deepEqual([...avccOf(nals)], [0, 0, 0, 3, ...idr]);
});

test("the video socket's stream, however it is cut", () => {
  const head = Buffer.alloc(1 + 64 + 4);
  const session = Buffer.alloc(12);
  session[0] = 0x80;
  session.writeUInt32BE(556, 4);
  session.writeUInt32BE(1280, 8);
  const packet = (flags: number, pts: number, data: number[]) => {
    const h = Buffer.alloc(12);
    h.writeBigUInt64BE(BigInt(pts), 0);
    h[0]! |= flags;
    h.writeUInt32BE(data.length, 8);
    return Buffer.concat([h, Buffer.from(data)]);
  };
  const whole = Buffer.concat([head, session, packet(0x40, 0, [1, 2]), packet(0x20, 500, [3]), packet(0, 533, [4, 5, 6])]);
  for (const cut of [whole.length, 1, 7]) {
    const sizes: unknown[] = [], packets: unknown[] = [];
    const stream = new ScrcpyStream((s) => sizes.push(s), (p) => packets.push([p.config, p.key, Number(p.pts), [...p.data]]));
    for (let at = 0; at < whole.length; at += cut) stream.heard(whole.subarray(at, at + cut));
    assert.deepEqual(sizes, [{ width: 556, height: 1280 }]);
    assert.deepEqual(packets, [[true, false, 0, [1, 2]], [false, true, 500, [3]], [false, false, 533, [4, 5, 6]]]);
  }
});
