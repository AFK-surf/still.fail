// electron-builder's afterSign (build.sh): the Mac app signed anew with a designated requirement of its own, then, signed
// with a Developer ID, notarized and its ticket stapled (.github/mac_signing.py notarize), before it is zipped.
// The updater (electron-updater on Squirrel.Mac) installs an update only if it satisfies the designated requirement of
// the app running: this one names AFK's team, not one certificate, so the apps keep taking updates when the Developer ID
// certificate is renewed. (The releases signed with the Apple Development certificate before, 2026-10-20 to 10-21,
// carried both, which moved the installed apps over.)
"use strict";
const { execFileSync } = require("node:child_process");
const { join, resolve } = require("node:path");

/** AFK AI, Inc.'s team (cue.surf), whose Developer ID Application certificate signs the apps. */
const TEAM = "D9AAN3VJK8";

/** The designated requirement of the app `id`: signed by the team's Developer ID. */
function requirement(id) {
  return `designated => identifier "${id}" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "${TEAM}"`;
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
