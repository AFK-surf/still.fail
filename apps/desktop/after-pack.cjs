// electron-builder's afterPack (build.sh): each executable of the Mac app given a Mach-O UUID (LC_UUID) of its own, before
// it is signed. Electron's executables carry the same UUID in every app built on one Electron, and macOS's Local Network
// privacy knows a program by its main executable's UUID (TN3179: two with one UUID confuse it). On 2026-10-18 a MacBook
// had youdid.wtf, an old copy of it and still.fail, all one UUID: youdid.wtf could reach nothing on its LAN, and System
// Settings' switch for it did not change that. Each UUID is now made from the app's id, its version and the file's place
// in the app, so no other app or build has it.
"use strict";
const { createHash } = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { readdirSync, readFileSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");

const LC_UUID = 0x1b;
const MH_MAGIC_64 = 0xfeedfacf;
const FAT_MAGIC = 0xcafebabe;

/** Sets the UUID of a 64-bit Mach-O at `base` in `buf`; whether it had one. */
function setThin(buf, base, uuid) {
  if (buf.readUInt32LE(base) !== MH_MAGIC_64) return false;
  const ncmds = buf.readUInt32LE(base + 16);
  let at = base + 32;
  for (let i = 0; i < ncmds; i++) {
    if (buf.readUInt32LE(at) === LC_UUID) {
      uuid.copy(buf, at + 8);
      return true;
    }
    at += buf.readUInt32LE(at + 4);
  }
  return false;
}

/** Sets the UUID of a Mach-O in place: a 64-bit one's, or each slice's of a universal one. How many it set. */
function setUuid(buf, uuid) {
  if (buf.readUInt32BE(0) !== FAT_MAGIC) return setThin(buf, 0, uuid) ? 1 : 0;
  let set = 0;
  for (let i = 0; i < buf.readUInt32BE(4); i++) if (setThin(buf, buf.readUInt32BE(8 + i * 20 + 8), uuid)) set++;
  return set;
}

/** A UUID made from `seed`, shaped as RFC 9562's name-based ones. */
function uuidOf(seed) {
  const u = Buffer.from(createHash("sha256").update(seed).digest().subarray(0, 16));
  u[6] = (u[6] & 0x0f) | 0x50;
  u[8] = (u[8] & 0x3f) | 0x80;
  return u;
}

/** The app's executables: its own, then each helper app's. */
function executables(app, name) {
  const out = [join(app, "Contents/MacOS", name)];
  const frameworks = join(app, "Contents/Frameworks");
  for (const helper of readdirSync(frameworks).filter((f) => f.endsWith(".app"))) {
    const dir = join(frameworks, helper, "Contents/MacOS");
    for (const f of readdirSync(dir)) out.push(join(dir, f));
  }
  return out;
}

async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;
  const info = context.packager.appInfo;
  const app = join(context.appOutDir, `${info.productFilename}.app`);
  for (const file of executables(app, info.productFilename)) {
    const buf = readFileSync(file);
    if (setUuid(buf, uuidOf(`${info.id} ${info.version} ${file.slice(app.length)}`)) === 0) throw new Error(`no LC_UUID in ${file}`);
    writeFileSync(file, buf);
    // Its signature no longer holds: signed anew ad hoc, so it runs unsigned too (UNSIGNED=1); electron-builder signs it
    // with the certificate after.
    execFileSync("codesign", ["--force", "--sign", "-", file], { stdio: "pipe" });
  }
}

module.exports = { default: afterPack, setUuid, uuidOf };
