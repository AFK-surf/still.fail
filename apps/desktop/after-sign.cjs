// electron-builder's afterSign (build.sh): the Mac app signed anew with a designated requirement of its own, then, signed
// with a Developer ID, notarized and its ticket stapled (.github/mac_signing.py notarize), before it is zipped.
// The updater (electron-updater on Squirrel.Mac) installs an update only if it satisfies the designated requirement of
// the app running; the one codesign makes by itself names the signing certificate, so an app signed with the Apple
// Development certificate would take no update signed with AFK's Developer ID. This one is satisfied by either: the
// releases signed with the old certificate and this requirement carry the installed apps over to the Developer ID ones.
"use strict";
const { execFileSync } = require("node:child_process");
const { join, resolve } = require("node:path");

/** The certificate the apps were signed with before AFK's Developer ID. */
const OLD = "Apple Development: zuozijian1994@gmail.com (9C49UVFRK3)";
/** AFK AI, Inc.'s team (cue.surf), whose Developer ID Application certificate signs the apps. */
const TEAM = "D9AAN3VJK8";

/** The designated requirement of the app `id`: signed by the old certificate or by the team's Developer ID. */
function requirement(id) {
  const old = `certificate leaf[subject.CN] = "${OLD}" and certificate 1[field.1.2.840.113635.100.6.2.1]`;
  const developerId = `certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "${TEAM}"`;
  return `designated => identifier "${id}" and anchor apple generic and ((${old}) or (${developerId}))`;
}

async function afterSign(context) {
  if (context.electronPlatformName !== "darwin") return;
  const info = context.packager.appInfo;
  const app = join(context.appOutDir, `${info.productFilename}.app`);
  // The certificate it is signed with: codesign -d says it on stderr, its first Authority; none when ad hoc (UNSIGNED=1).
  const shown = execFileSync("sh", ["-c", 'codesign -dvv "$0" 2>&1', app], { encoding: "utf8" });
  const identity = /^Authority=(.+)$/m.exec(shown)?.[1];
  if (!identity) return;
  execFileSync("codesign", ["--force", "--sign", identity, "--timestamp", "--preserve-metadata=entitlements,flags", "--requirements", `=${requirement(info.id)}`, app], { stdio: "inherit" });
  execFileSync("codesign", ["--verify", "--strict", app], { stdio: "inherit" });
  if (identity.startsWith("Developer ID Application:")) {
    execFileSync("python3", [resolve(__dirname, "../../.github/mac_signing.py"), "notarize", app], { stdio: "inherit" });
  }
}

module.exports = { default: afterSign, requirement };
