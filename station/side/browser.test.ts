// The station's browser on the machine's real Chrome (src/browser/): started as the station starts it, driven by an
// agent's own DevTools connection while a person's view of the same tab casts frames and types into it, let go of by
// one station process and taken up by the next, started again when it dies, then closed. Real processes over real time: beside the checks
// (`pnpm test:side`), skipped where there is no Chrome.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { StationBrowser } from "../src/browser/browser.ts";
import { type Cdp, connectCdp } from "../src/browser/cdp.ts";
import { chromeHost } from "../src/browser/chrome.ts";
import { jpegSize } from "../src/browser/view.ts";
import { makeScreens } from "../src/screens/source.ts";
import { platform } from "../src/platform/index.ts";

const binary = platform.browsers(process.env)[0];
/// The agent's page, served here: an input, and a counter that keeps the page drawing.
const PAGE = `<title>side</title><body style="margin:0"><input id=i style="position:absolute;left:100px;top:100px;width:300px;height:40px"><div id=n></div><script>let k=0;setInterval(()=>n.textContent=k++,30)</script>`;

async function until<T>(what: () => T | Promise<T>, why: string, ms = 15_000): Promise<NonNullable<Awaited<T>>> {
  const end = Date.now() + ms;
  for (;;) {
    const v = await what();
    if (v) return v as NonNullable<Awaited<T>>;
    if (Date.now() > end) throw new Error(`timed out: ${why}`);
    await new Promise((r) => setTimeout(r, 50));
  }
}

const alive = async (http: string) => {
  try {
    return (await fetch(`${http}/json/version`, { signal: AbortSignal.timeout(2000) })).ok;
  } catch {
    return false;
  }
};

for (const headless of process.env.CI ? [true] : [false, true]) {
  test(`the station's Chrome (${headless ? "headless" : "headful"}): an agent and a person on one tab, a handover, a stop`, { skip: binary === undefined && "no Chrome here" }, async () => {
    const dir = mkdtempSync(join(tmpdir(), "side-browser-"));
    const screens = makeScreens();
    const first = new StationBrowser({ dir, chrome: chromeHost({ dir, headless }), screens });
    let agent: Cdp | null = null;
    let next: StationBrowser | null = null;
    let third: StationBrowser | null = null;
    const server = createServer((_, res) => res.writeHead(200, { "content-type": "text/html" }).end(PAGE));
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/`;
    try {
      const s = await first.endpoint();
      assert.ok(s.running && s.http && s.ws);
      assert.ok(await alive(s.http!));

      // The agent: its own connection, its own tab.
      agent = await connectCdp(s.ws!);
      const { targetId } = await agent.send("Target.createTarget", { url });
      const { sessionId } = await agent.send("Target.attachToTarget", { targetId, flatten: true });
      const evaluate = async (expression: string) => (await agent!.send("Runtime.evaluate", { expression, returnByValue: true }, sessionId)).result?.value;
      await until(async () => (await evaluate("document.readyState")) === "complete", "the page loads");
      assert.equal(await evaluate("navigator.webdriver"), false, "not said to be automated");
      assert.doesNotMatch(String(await evaluate("navigator.userAgent")), /Headless/);

      // The person: the tab is a screen; its view casts frames and types where they click.
      const tab = await until(() => screens.get(`browser:${targetId}`), "the tab is a screen");
      await until(() => tab.title() === "side", "its title");
      // A page going on to another address (as a single-page app does) and naming itself again.
      await evaluate("history.pushState({}, '', '/renamed'); document.title = 'renamed'");
      await until(() => tab.title() === "renamed", "its title follows the page's");
      const view = await tab.open({ maxWidth: 800, maxHeight: 600, codecs: ["jpeg"] });
      const frame = await view.next();
      assert.ok(frame && frame.config?.codec === "jpeg");
      const size = jpegSize(frame.data)!;
      assert.ok(size.width > 0 && size.width <= 800 && size.height <= 600, JSON.stringify(size));
      assert.deepEqual({ width: frame.config.width, height: frame.config.height }, size);
      const later = await view.next();
      assert.ok(later && later.ts > frame.ts, "the counter moves: frames keep coming as they are asked for");

      const [w, h] = (await evaluate("[innerWidth, innerHeight]")) as [number, number];
      await view.input({ t: "pointer", kind: "down", x: 250 / w, y: 120 / h, buttons: 1 });
      await view.input({ t: "pointer", kind: "up", x: 250 / w, y: 120 / h, buttons: 0 });
      await until(async () => (await evaluate("document.activeElement.id")) === "i", "the click focused the input");
      for (const [key, code] of [["h", "KeyH"], ["i", "KeyI"]]) {
        await view.input({ t: "key", kind: "down", key: key!, code: code!, mods: 0 });
        await view.input({ t: "key", kind: "up", key: key!, code: code!, mods: 0 });
      }
      await view.input({ t: "text", text: "你好" });
      await view.input({ t: "key", kind: "down", key: "Backspace", code: "Backspace", mods: 0 });
      await view.input({ t: "key", kind: "up", key: "Backspace", code: "Backspace", mods: 0 });
      assert.equal(await evaluate("i.value"), "hi你", "typed by the person, read by the agent");
      view.close();

      // The station process ends: the browser stays, and the next one takes it up, the agent's tab a screen again.
      await first.close();
      assert.ok(await alive(s.http!), "still running");
      const again = makeScreens();
      next = new StationBrowser({ dir, chrome: chromeHost({ dir, headless }), screens: again });
      await next.resume();
      assert.equal(next.status().ws, s.ws, "the same browser");
      await until(() => again.get(`browser:${targetId}`), "its tab is a screen again");
      assert.equal(await evaluate("i.value"), "hi你", "the agent's connection went on");

      // It dies in use: started again, at the same address.
      const pid = next.status().pid;
      assert.ok(typeof pid === "number", "its process known to the next station process");
      process.kill(-pid, "SIGKILL");
      await until(() => next!.status().running && next!.status().ws !== s.ws, "started again");
      assert.equal(next.status().http, s.http, "on the same port");
      assert.ok(await alive(s.http!));

      // Given its port, Chrome writes no DevToolsActivePort: the next station process finds it by its record.
      const restarted = next.status().ws;
      await next.close();
      third = new StationBrowser({ dir, chrome: chromeHost({ dir, headless }), screens: makeScreens() });
      await third.resume();
      assert.equal(third.status().ws, restarted, "the restarted browser taken up");

      await third.stop();
      assert.equal(await alive(s.http!), false, "closed");
      await until(() => agent!.closed.then(() => true), "the agent's connection ended with it");
      assert.equal(third.status().running, false);
    } finally {
      agent?.close();
      await first.stop().catch(() => {});
      await next?.stop().catch(() => {});
      await first.close();
      await next?.close();
      await third?.stop().catch(() => {});
      await third?.close();
      server.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
