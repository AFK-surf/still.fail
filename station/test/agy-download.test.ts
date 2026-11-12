// How much of the Antigravity CLI's build its own installer has downloaded (src/updates/agy-download.ts): the build its
// manifest names, its size as its server says, the file the installer writes, looked at as the updates' clock says.

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { watchAgyDownload } from "../src/updates/agy-download.ts";
import { platform } from "../src/platform/index.ts";
import { unix } from "../src/platform/unix.ts";
import { windows } from "../src/platform/windows.ts";

/// Looks every 20 ms until `f` holds: a real socket's answer has no event here.
async function until(f: () => boolean, signal: AbortSignal) {
  while (!f()) await sleep(20, undefined, { signal });
}

test("where the installer downloads a build", async () => {
  assert.equal(unix.agyStaging({ HOME: "/h" }, "https://x/cli_mac_arm64.tar.gz"), join("/h", ".cache", "antigravity", "staging", "agy.tar.gz"));
  assert.equal(unix.agyStaging({ HOME: "/h" }, "https://x/agy"), join("/h", ".cache", "antigravity", "staging", "agy"));
  assert.equal(unix.agyStaging({}, "https://x/agy"), null);
  assert.equal(windows.agyStaging({}, "https://x/agy.exe"), null);
  // This machine's build is one the manifests name (CI's Macs and Linux, glibc).
  assert.match((await platform.agyBuild()) ?? "", /^(darwin|linux|windows)_(arm64|amd64)$/);
});

test("how much of the build is in is said as its file grows, until it is whole", async (t) => {
  let base = "";
  const server: Server = createServer((req, res) => {
    if (req.url === "/manifests/darwin_arm64.json") {
      const body = JSON.stringify({ version: "1.5.6", url: `${base}/b/cli_mac_arm64.tar.gz`, sha512: "x" });
      return void res.writeHead(200, { "content-type": "application/json" }).end(body);
    }
    if (req.url === "/b/cli_mac_arm64.tar.gz" && req.method === "HEAD") return void res.writeHead(200, { "content-length": 1000 }).end();
    res.writeHead(404).end();
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => server.close());
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const home = realpathSync(mkdtempSync(join(tmpdir(), "stillfail-agy-")));
  const staging = join(home, ".cache", "antigravity", "staging");
  mkdirSync(staging, { recursive: true });
  const file = join(staging, "agy.tar.gz");
  writeFileSync(file, Buffer.alloc(400));

  const said: [string, number, number][] = [];
  // The updates' clock, moved on by hand: what is to run next.
  let due: (() => void) | null = null;
  const stop = watchAgyDownload({
    manifests: `${base}/manifests`,
    build: async () => "darwin_arm64",
    staging: (url) => unix.agyStaging({ HOME: home }, url),
    after: (ms, f) => {
      assert.equal(ms, 500);
      due = f;
      return () => (due = null);
    },
    said: (version, got, total) => said.push([version, got, total]),
  });
  t.after(stop);
  await until(() => due !== null, t.signal);
  assert.deepEqual(said, [["1.5.6", 400, 1000]]);

  writeFileSync(file, Buffer.alloc(1000));
  const look = due!;
  due = null;
  look();
  await until(() => said.length === 2, t.signal);
  assert.deepEqual(said[1], ["1.5.6", 1000, 1000]);
  // Whole: looked at no more.
  assert.equal(due, null);
});

test("stopped, it looks no more", async (t) => {
  let due: (() => void) | null = null;
  let base = "";
  const server: Server = createServer((req, res) => {
    if (req.url === "/manifests/linux_amd64.json") return void res.writeHead(200).end(JSON.stringify({ version: "1", url: `${base}/agy` }));
    res.writeHead(200, { "content-length": 10 }).end();
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => server.close());
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const home = realpathSync(mkdtempSync(join(tmpdir(), "stillfail-agy-")));
  const said: number[] = [];
  const stop = watchAgyDownload({
    manifests: `${base}/manifests`,
    build: async () => "linux_amd64",
    staging: (url) => unix.agyStaging({ HOME: home }, url),
    after: (_ms, f) => {
      due = f;
      return () => (due = null);
    },
    said: (_v, got) => said.push(got),
  });
  // Not begun yet: nothing said while the file is not there.
  await until(() => due !== null, t.signal);
  assert.deepEqual(said, []);
  stop();
  assert.equal(due, null);
});
