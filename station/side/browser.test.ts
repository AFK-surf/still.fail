// The station's browser on the machine's real Chrome (src/browser/): started as the station starts it, driven by an
// agent's own DevTools connection while a person's view of the same tab casts frames and types into it, let go of by
// one station process and taken up by the next, started again when it dies, then closed; a person's view of a tab
// hearing what the page copies and pasting into it. Real processes over real time: beside the checks
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
import { BEHIND } from "../src/browser/proxy.ts";
import { COPY_BINDING, jpegSize } from "../src/browser/view.ts";
import type { Clip } from "../src/screens/source.ts";
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

test("a tab's clipboard, for a person driving it: what the page copies is heard, a paste goes in where its focus is", { skip: binary === undefined && "no Chrome here" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "side-browser-clip-"));
  const screens = makeScreens();
  const browser = new StationBrowser({ dir, chrome: chromeHost({ dir, headless: true }), screens });
  const page = `<title>clip</title><body><input id=i value="select me"><button id=b onclick="navigator.clipboard.writeText('from the button').catch(()=>{})">copy</button><div id=c contenteditable>set by the page</div>
<script>c.addEventListener("copy",(e)=>{e.clipboardData.setData("text/plain","the page's own");e.preventDefault()})</script>`;
  const server = createServer((_, res) => res.writeHead(200, { "content-type": "text/html" }).end(page));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  let agent: Cdp | null = null;
  try {
    const s = await browser.endpoint();
    agent = await connectCdp(s.ws!);
    const { targetId } = await agent.send("Target.createTarget", { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}/` });
    const { sessionId } = await agent.send("Target.attachToTarget", { targetId, flatten: true });
    const evaluate = async (expression: string) => (await agent!.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }, sessionId)).result?.value;
    await until(async () => (await evaluate("document.readyState")) === "complete", "the page loads");
    const tab = await until(() => screens.get(`browser:${targetId}`), "the tab is a screen");
    assert.deepEqual(tab.clipboard?.(), ["text"]);
    const view = await tab.open({ maxWidth: 800, maxHeight: 600, codecs: ["jpeg"] });
    await view.next();
    const heard: Clip[] = [];
    const unwatch = view.watchClipboard!((clip) => heard.push(clip));
    await until(async () => (await evaluate(`typeof window.${COPY_BINDING}`)) === "function", "the binding is there");
    const copy = async () => {
      await view.input({ t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 });
      await view.input({ t: "key", kind: "down", key: "c", code: "KeyC", mods: 4 });
      await view.input({ t: "key", kind: "up", key: "c", code: "KeyC", mods: 4 });
      await view.input({ t: "key", kind: "up", key: "Meta", code: "MetaLeft", mods: 0 });
    };
    // A field's selection copied with ⌘C.
    await evaluate("i.focus(); i.select(); true");
    await copy();
    await until(() => heard.find((c) => c.type === "text" && c.text === "select me"), "a selection copied is heard");
    // What the page sets as it is copied, over what was selected.
    await evaluate("c.focus(); getSelection().selectAllChildren(c); true");
    await copy();
    await until(() => heard.find((c) => c.type === "text" && c.text === "the page's own"), "what the page put on the clipboard is heard");
    // A copy button (navigator.clipboard.writeText).
    await evaluate("b.click(); true");
    await until(() => heard.find((c) => c.type === "text" && c.text === "from the button"), "a page's writeText is heard");
    // A paste: in where the focus is.
    await evaluate("i.value = ''; i.focus(); true");
    await view.setClipboard!({ type: "text", text: "pasted 你好" }, true);
    assert.equal(await evaluate("i.value"), "pasted 你好");
    // No longer watched: a copy is not heard (Chrome stops telling of the binding; the page keeps its function until
    // it loads again), and a page loaded since has none.
    unwatch();
    await new Promise((r) => setTimeout(r, 200));
    const before = heard.length;
    await evaluate("b.click(); true");
    await new Promise((r) => setTimeout(r, 300));
    assert.equal(heard.length, before);
    await evaluate("location.reload(); true");
    await until(async () => (await evaluate("document.readyState")) === "complete" && (await evaluate(`typeof window.${COPY_BINDING}`)) === "undefined", "a page loaded since has no binding");
    assert.equal(await evaluate("navigator.webdriver"), false, "still not said to be automated");
    view.close();
  } finally {
    agent?.close();
    await browser.stop().catch(() => {});
    await browser.close();
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a login's page in the station's Chrome: a tab of the station's own, laid out for a phone while a view with its stage drives it, as it was once that ends, closed when asked", { skip: binary === undefined && "no Chrome here" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "side-browser-fit-"));
  const screens = makeScreens();
  const browser = new StationBrowser({ dir, chrome: chromeHost({ dir, headless: true }), screens });
  // A page laid out by its width, as a sign-in page is: narrow, its column alone; a counter keeps it drawing (a frame is
  // cast only when the page draws).
  const page = `<title>sign in</title><meta name=viewport content="width=device-width,initial-scale=1"><style>#w{display:none}@media (max-width:500px){#w{display:block}}</style><body><div id=w>narrow</div><div id=n></div><script>let k=0;setInterval(()=>n.textContent=k++,30)</script>`;
  const server = createServer((_, res) => res.writeHead(200, { "content-type": "text/html" }).end(page));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  let agent: Cdp | null = null;
  try {
    // The station opens it (the browser started for it): among the screens once it is given, nobody's.
    const id = await browser.openTab(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
    const tab = screens.get(`browser:${id}`);
    assert.ok(tab, "a screen by the time it is given");
    assert.equal(tab.openedBy?.(), undefined);
    // What the page itself says of its width, read on a connection of its own (as an agent's).
    agent = await connectCdp(browser.status().ws!);
    const { sessionId } = await agent.send("Target.attachToTarget", { targetId: id, flatten: true });
    const evaluate = async (expression: string) => (await agent!.send("Runtime.evaluate", { expression, returnByValue: true }, sessionId)).result?.value;
    await until(async () => (await evaluate("document.readyState")) === "complete", "the page loads");
    const wide = await evaluate("innerWidth");
    assert.ok(wide > 500, `a desktop's window: ${wide}`);
    // A phone drives it: laid out for its stage, cast as large as the phone shows it.
    const view = await tab.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["jpeg"], fit: { width: 390, height: 700, scale: 3 } });
    // Its frames the phone's shape, at most twice its CSS pixels.
    const size = await until(async () => {
      const f = await view.next();
      const s = f && jpegSize(f.data);
      return s && Math.abs(s.width / s.height - 390 / 700) < 0.01 ? s : null;
    }, "a frame of the phone's shape");
    assert.ok(size.width >= 390 && size.width <= 780, JSON.stringify(size));
    assert.deepEqual([await evaluate("innerWidth"), await evaluate("getComputedStyle(w).display")], [390, "block"]);
    // A tap lands where the phone shows it.
    await evaluate("window.tapped = null; addEventListener('mousedown', (e) => (window.tapped = [e.clientX, e.clientY])); true");
    await view.input({ t: "pointer", kind: "down", x: 0.5, y: 0.5, buttons: 1 });
    await view.input({ t: "pointer", kind: "up", x: 0.5, y: 0.5, buttons: 0 });
    assert.deepEqual(await evaluate("window.tapped"), [195, 350]);
    // The view ends: the page as it was, for whoever looks next.
    view.close();
    await until(async () => (await evaluate("innerWidth")) === wide, "laid out as before");
    assert.equal(await evaluate("getComputedStyle(w).display"), "none");
    // The login ends: its tab is closed, and leaves the screens.
    await browser.closeTab(id);
    await until(() => !screens.get(`browser:${id}`), "the tab gone");
    assert.equal(browser.hasTab(id), false);
  } finally {
    agent?.close();
    await browser.stop().catch(() => {});
    await browser.close();
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("every tab is drawn without being brought forward: the station's and an agent's (each in a window of its own, behind the others) cast at once", { skip: binary === undefined && "no Chrome here" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "side-browser-windows-"));
  const screens = makeScreens();
  const browser = new StationBrowser({ dir, chrome: chromeHost({ dir }), screens });
  const server = createServer((_, res) => res.writeHead(200, { "content-type": "text/html" }).end(PAGE));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/`;
  let agent: Cdp | null = null;
  try {
    const own = await browser.openTab(url);
    // The agent's tab as the door passes it on (proxy.ts): in a window of its own.
    agent = await connectCdp(browser.status().ws!);
    const { targetId } = await agent.send("Target.createTarget", { url, ...BEHIND });
    const visible = async (id: string) => {
      const { sessionId } = await agent!.send("Target.attachToTarget", { targetId: id, flatten: true });
      return (await agent!.send("Runtime.evaluate", { expression: "document.visibilityState", returnByValue: true }, sessionId)).result?.value;
    };
    assert.deepEqual([await visible(own), await visible(targetId)], ["visible", "visible"], "neither behind the other");
    // Previews (which bring nothing forward) of both cast frames.
    for (const id of [own, targetId]) {
      const tab = await until(() => screens.get(`browser:${id}`), "the tab is a screen");
      const view = await tab.open({ maxWidth: 400, maxHeight: 300, codecs: ["jpeg"], peek: true });
      assert.ok((await view.next())?.config?.codec === "jpeg", `a frame of ${id}`);
      view.close();
    }
  } finally {
    agent?.close();
    await browser.stop().catch(() => {});
    await browser.close();
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
