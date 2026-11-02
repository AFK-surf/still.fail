// Resource and failure tests for an isolated X11 display. Never run them against a person's desktop.
import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { promisify } from "node:util";
import { X11Desktop } from "../src/screens/x11-desktop.ts";

const run = promisify(execFile);
const enabled = process.env.STILLFAIL_TEST_X11 === "1";

async function until(check: () => boolean | Promise<boolean>, what: string, timeout = 5_000) {
  const end = performance.now() + timeout;
  while (performance.now() < end) {
    if (await check()) return;
    await sleep(50);
  }
  assert.fail(`timed out waiting for ${what}`);
}

test("repeated X11 views close their capture processes and release pending reads", { skip: !enabled, timeout: 45_000 }, async () => {
  const env = { ...process.env };
  const desktop = new X11Desktop({ env, changed: () => {} });
  const initial = process.memoryUsage().rss;
  let peak = initial;
  try {
    for (const codec of ["jpeg", "h264"] as const) {
      for (let i = 0; i < 20; i++) {
        const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: [codec], fps: 15 });
        const first = await view.next();
        assert.ok(first && first.config?.codec === codec && first.data.length > 100);
        const pending = view.next();
        view.close();
        await pending; // It either had a new frame already or is resolved by close.
        assert.equal(await view.next(), null);
        view.close(); // Closing a view twice is harmless.
        peak = Math.max(peak, process.memoryUsage().rss);
      }
    }
    await desktop.close();
    await until(async () => {
      const p = await run("ps", ["-o", "comm=", "--ppid", String(process.pid)], { env });
      return !p.stdout.split("\n").some((line) => line.trim() === "ffmpeg");
    }, "all capture and encoder processes to exit");
    const growth = (peak - initial) / (1024 * 1024);
    console.log(`20 open/close cycles per codec: peak RSS grew ${growth.toFixed(1)} MiB; no ffmpeg processes remain`);
    assert.ok(growth < 256, `unexpected RSS growth: ${growth.toFixed(1)} MiB`);
  } finally { await desktop.close(); }
});

test("an X server that exits ends JPEG and H.264 views and is reported unavailable", { skip: !enabled, timeout: 30_000 }, async () => {
  for (const [i, codec] of (["jpeg", "h264"] as const).entries()) {
    const dir = mkdtempSync(join(tmpdir(), "sf-x11-failure-"));
    const auth = join(dir, "Xauthority");
    const display = `:${196 + i}`;
    const env: NodeJS.ProcessEnv = { ...process.env, DISPLAY: display, XAUTHORITY: auth, XDG_SESSION_TYPE: "x11" };
    delete env.WAYLAND_DISPLAY;
    await run("xauth", ["-f", auth, "add", display, ".", randomBytes(16).toString("hex")], { env });
    const xserver = process.env.STILLFAIL_TEST_XSERVER ?? "Xvfb";
    const args = xserver.endsWith("Xvnc")
      ? [display, "-auth", auth, "-nolisten", "tcp", "-rfbport", "-1", "-geometry", "640x480", "-depth", "24"]
      : [display, "-auth", auth, "-nolisten", "tcp", "-screen", "0", "640x480x24"];
    const server = spawn(xserver, args, { env, stdio: "ignore" });
    const desktop = new X11Desktop({ env, changed: () => {} });
    try {
      await until(async () => {
        if (server.exitCode !== null) throw new Error("the disposable X server did not start");
        try { await run("xdotool", ["getdisplaygeometry"], { env }); return true; } catch { return false; }
      }, "the disposable X server");
      const view = await desktop.open({ maxWidth: 640, maxHeight: 480, codecs: [codec] });
      assert.equal((await view.next())?.config?.codec, codec);
      server.kill("SIGTERM");
      let ended = false;
      for (let i = 0; i < 10 && !ended; i++) {
        const got = await Promise.race([view.next(), sleep(5_000, "timeout" as const, { ref: false })]);
        assert.notEqual(got, "timeout", "a lost X server must not leave a frame read hanging");
        ended = got === null;
      }
      assert.ok(ended, "the view ends after its display goes away");
      await desktop.refresh(true);
      assert.equal(desktop.access().reason, "linuxUnavailable");
      view.close();
    } finally {
      server.kill("SIGTERM");
      await desktop.close();
      rmSync(dir, { recursive: true, force: true });
    }
  }
});
