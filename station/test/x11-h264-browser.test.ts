// Exercise the actual web screen decoder with H.264 frames captured from a disposable X11 display.
import assert from "node:assert/strict";
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { promisify } from "node:util";
import { build } from "esbuild";
import { X11Desktop } from "../src/screens/x11-desktop.ts";

const run = promisify(execFile);
const enabled = process.env.STILLFAIL_TEST_X11 === "1" && process.env.STILLFAIL_TEST_X11_BROWSER === "1";

async function until<T>(get: () => T | null | Promise<T | null>, what: string): Promise<T> {
  const end = performance.now() + 10_000;
  while (performance.now() < end) {
    const value = await get();
    if (value !== null) return value;
    await sleep(50);
  }
  throw new Error(`timed out waiting for ${what}`);
}

test("the web ScreenFrames decoder draws X11 H.264 across encoder restarts", { skip: !enabled, timeout: 45_000 }, async () => {
  const env = { ...process.env };
  const desktop = new X11Desktop({ env, changed: () => {} });
  const observer = spawn("xev", ["-event", "keyboard"], { env, stdio: "ignore" });
  const dir = mkdtempSync(join(tmpdir(), "sf-x11-browser-"));
  let chrome: ChildProcess | undefined;
  let socket: WebSocket | undefined;
  try {
    await until(async () => {
      try { await run("xdotool", ["search", "--name", "Event Tester"], { env }); return true; } catch { return null; }
    }, "the X observer");
    await run("xsetroot", ["-solid", "#ff0000"], { env });
    const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["h264"] });
    const frames: object[] = [];
    try {
      const take = async () => {
        const f = await view.next();
        assert.ok(f);
        frames.push({ key: f.key, ts: f.ts, data: Buffer.from(f.data).toString("base64"), ...(f.config ? { config: { codec: f.config.codec, width: f.config.width, height: f.config.height, description: Buffer.from(f.config.description!).toString("base64") } } : {}) });
      };
      for (let i = 0; i < 3; i++) await take();
      await run("xsetroot", ["-solid", "#0000ff"], { env });
      await sleep(150);
      for (let i = 0; i < 3; i++) await take();
      view.keyframe();
      for (let i = 0; i < 3; i++) await take();
    } finally { view.close(); }

    const built = await build({ entryPoints: [join(import.meta.dirname, "../../web/src/screen/frames.ts")], bundle: true, platform: "browser", format: "iife", globalName: "SfScreen", write: false });
    const bundle = built.outputFiles[0]!.text;
    const html = join(dir, "viewer.html");
    writeFileSync(html, "<!doctype html><canvas width=640 height=400></canvas>");
    const binary = process.env.STILLFAIL_TEST_CHROME ?? "google-chrome";
    chrome = spawn(binary, ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", "--remote-allow-origins=*", "--remote-debugging-port=0", `--user-data-dir=${join(dir, "profile")}`, `file://${html}`], { stdio: "ignore" });
    const port = await until(() => {
      if (chrome!.exitCode !== null) throw new Error("Chrome exited before opening a page");
      try { return Number(readFileSync(join(dir, "profile", "DevToolsActivePort"), "utf8").split("\n")[0]) || null; }
      catch { return null; }
    }, "Chrome's DevTools port");
    const target = await until(async () => {
      try {
        const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json() as { type: string; url: string; webSocketDebuggerUrl: string }[];
        return list.find((entry) => entry.type === "page" && entry.url.startsWith("file:")) ?? null;
      } catch { return null; }
    }, "the test page");
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise<void>((resolve, reject) => { socket!.onopen = () => resolve(); socket!.onerror = () => reject(new Error("DevTools connection failed")); });
    const result = new Promise<any>((resolve, reject) => {
      socket!.onmessage = (event) => {
        const message = JSON.parse(String(event.data));
        if (message.id !== 1) return;
        if (message.error || message.result?.exceptionDetails) reject(new Error(JSON.stringify(message.error ?? message.result.exceptionDetails)));
        else resolve(message.result.result.value);
      };
      socket!.onerror = () => reject(new Error("DevTools connection failed"));
    });
    const expression = `(() => { ${bundle}; return (async () => {
      if (document.readyState === 'loading') await new Promise((resolve) => document.addEventListener('DOMContentLoaded', resolve, { once: true }));
      const decode = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
      const canvas = document.querySelector('canvas');
      const inputs = ${JSON.stringify(frames)};
      const acks = []; let waiting; let lost = 0; let first;
      const screen = new SfScreen.ScreenFrames(canvas, { ack: (ts) => { acks.push(ts); waiting?.(ts); }, keyframe: () => { lost++; }, drawn: () => {} });
      for (const [i, f] of inputs.entries()) {
        if (f.config) screen.config({ codec: f.config.codec, width: f.config.width, height: f.config.height }, decode(f.config.description));
        const ack = new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('decoder did not acknowledge frame ' + i)), 5000);
          waiting = (ts) => { clearTimeout(timer); resolve(ts); };
        });
        screen.frame({ key: f.key, ts: f.ts }, decode(f.data));
        await ack;
        if (i === 0) first = [...canvas.getContext('2d').getImageData(620, 380, 1, 1).data];
      }
      const last = [...canvas.getContext('2d').getImageData(620, 380, 1, 1).data];
      screen.close();
      return { acks, lost, first, last };
    })(); })()`;
    socket.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression, awaitPromise: true, returnByValue: true } }));
    const got = await Promise.race([result, sleep(20_000, undefined, { ref: false }).then(() => { throw new Error("web decoder test timed out"); })]);
    assert.equal(got.acks.length, frames.length);
    assert.equal(got.lost, 0, "the web decoder did not lose its state");
    assert.ok(got.first[0] > 170 && got.first[0] > got.first[2] * 2, `first pixel: ${got.first}`);
    assert.ok(got.last[2] > 170 && got.last[2] > got.last[0] * 2, `last pixel: ${got.last}`);
    console.log(`web ScreenFrames decoded and acknowledged ${got.acks.length} H.264 pictures across a key-frame restart`);
  } finally {
    socket?.close();
    chrome?.kill();
    await desktop.close();
    observer.kill();
    rmSync(dir, { recursive: true, force: true });
  }
});
