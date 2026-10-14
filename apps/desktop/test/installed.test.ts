// installed.ts against a home and commands of its own: launchctl, plutil and curl are scripts that write down what they
// were asked, so nothing of the machine's own station is touched. macOS only (the service is launchd's there).
// Run: node --test apps/desktop/test/installed.test.ts
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const mac = process.platform === "darwin";
const home = mkdtempSync(join(tmpdir(), "stillfail-installed-"));
const bin = join(home, "bin");
const said = join(home, "said");
mkdirSync(bin);
const script = (name: string, body: string) => {
  writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`);
  chmodSync(join(bin, name), 0o755);
};
// kickstart fails while the service is not loaded (the file `unloaded` there), as launchctl's does.
script("launchctl", `echo "launchctl $*" >> "${said}"; [ "$1" = kickstart ] && [ -f "${home}/unloaded" ] && exit 113; exit 0`);
script("plutil", `echo "/agents/bin:/usr/bin:/bin"`);
// The installer: what it was run with, said back.
script("curl", `echo "curl $*" >> "${said}"; echo 'echo "installer channel=$STILLFAIL_CHANNEL path=$PATH" >> "${said}"'`);
process.env.HOME = home;
process.env.PATH = `${bin}:/usr/bin:/bin`;
const { controlService, installedService, servicePath, updateInstalled } = await import("../src/installed.ts");
const lines = () => readFileSync(said, "utf8").trim().split("\n");
after(() => rmSync(home, { recursive: true, force: true }));

test("an installed service is found by its label, the name from before the rename too", { skip: !mac }, () => {
  assert.equal(installedService(), null);
  const agents = join(home, "Library", "LaunchAgents");
  mkdirSync(agents, { recursive: true });
  writeFileSync(join(agents, "org.3720.ember.station.plist"), "");
  assert.deepEqual(installedService(), { kind: "launchd", name: "org.3720.ember.station", definition: join(agents, "org.3720.ember.station.plist") });
  writeFileSync(join(agents, "fail.still.station.plist"), "");
  assert.equal(installedService()?.name, "fail.still.station");
});

test("stopped, started, restarted through launchd; one not loaded is loaded", { skip: !mac }, async () => {
  const service = installedService()!;
  const target = `gui/${process.getuid!()}/fail.still.station`;
  writeFileSync(said, "");
  await controlService(service, "stop");
  writeFileSync(join(home, "unloaded"), "");
  await controlService(service, "start");
  rmSync(join(home, "unloaded"));
  await controlService(service, "restart");
  assert.deepEqual(lines(), [
    `launchctl bootout ${target}`,
    `launchctl kickstart ${target}`,
    `launchctl bootstrap gui/${process.getuid!()} ${service.definition}`,
    `launchctl kickstart -k ${target}`,
  ]);
});

test("updated in place by the installer, with the service's PATH and the app's channel", { skip: !mac }, async () => {
  const service = installedService()!;
  writeFileSync(said, "");
  const path = servicePath(service, "/fallback");
  assert.equal(path, "/agents/bin:/usr/bin:/bin");
  await updateInstalled(service, "https://cloud.example", { ...process.env, PATH: `${bin}:${path}`, STILLFAIL_CHANNEL: "beta", ELECTRON_RUN_AS_NODE: "1" });
  assert.deepEqual(lines(), [
    "curl -fsSL https://cloud.example/install.sh",
    `installer channel=beta path=${bin}:/agents/bin:/usr/bin:/bin`,
  ]);
});

test("an installer that fails says why", { skip: !mac }, async () => {
  script("curl", `echo "curl: (22) The requested URL returned error: 404" >&2; exit 22`);
  await assert.rejects(updateInstalled(installedService()!, "https://cloud.example", { ...process.env }), /404/);
});
