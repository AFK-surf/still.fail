// The station's browser (src/browser/) without a Chrome: its command line and DevToolsActivePort, a tab's view over a
// fake DevTools connection (frames only as they are asked for, input mapped onto the page), its tabs as screens, and
// the browser kept (started once, closed when idle, started again when it dies in use) on a test clock. The real
// Chrome is side/browser.test.ts's.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { type Clock, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { StationBrowser, IDLE_MS } from "../src/browser/browser.ts";
import { Browsers } from "../src/browser/browsers.ts";
import { Gate } from "../src/browser/gate.ts";
import { expired, keptOf, ofSites, siteCookies, stateOf } from "../src/browser/signins.ts";
import { passkeyOf, sitePasskeys } from "../src/browser/passkeys.ts";
import type { Cdp, CdpEvent } from "../src/browser/cdp.ts";
import { type ChromeHost, type Running, chromeArgs, headfulAgent, parseActivePort, readState } from "../src/browser/chrome.ts";
import { Owners } from "../src/browser/owners.ts";
import { browserDoor, sessionOfPath, sessionPath } from "../src/browser/proxy.ts";
import { Tabs } from "../src/browser/tabs.ts";
import { openAgentsDoor } from "../src/tools/http.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";
import WebSocket, { WebSocketServer } from "ws";
import { TabView, hostOf, jpegSize, rpFor, sameClientData, keyCode, keyEvent, toViewport } from "../src/browser/view.ts";
import { makeScreens } from "../src/screens/source.ts";
import { browserTools, howTo } from "../src/browser/tool.ts";
import { asked, parseFill, parsePasskey } from "../src/mesh/screens.ts";

const dirs: string[] = [];
const scratch = () => {
  const d = mkdtempSync(join(tmpdir(), "browser-"));
  dirs.push(d);
  return d;
};
const scopes: Scope.Closeable[] = [];
after(async () => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
  for (const s of scopes) await Effect.runPromise(Scope.close(s, Exit.void));
});

const turn = async () => {
  for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r));
};

/// A DevTools connection in memory: what was sent, answers by method, events given by the test.
class FakeCdp implements Cdp {
  sent: { method: string; params: any; sessionId?: string }[] = [];
  answers: Record<string, (params: any) => any> = {};
  #listeners = new Set<(e: CdpEvent) => void>();
  #end!: () => void;
  closed = new Promise<void>((r) => (this.#end = r));
  gone = false;
  async send(method: string, params: object = {}, sessionId?: string) {
    if (this.gone) throw new Error("closed");
    this.sent.push({ method, params, sessionId });
    return this.answers[method]?.(params) ?? {};
  }
  on(listener: (e: CdpEvent) => void) {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
  emit(method: string, params: any, sessionId?: string) {
    for (const l of [...this.#listeners]) l({ method, params, sessionId });
  }
  close() {
    this.gone = true;
    this.#end();
  }
  of(method: string) {
    return this.sent.filter((s) => s.method === method);
  }
}

/// The start of a JPEG of `width` × `height`: SOI, an APP0, a SOF0.
function jpeg(width: number, height: number, fill = 0): Uint8Array {
  const app0 = [0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00];
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1];
  return Uint8Array.from([0xff, 0xd8, ...app0, ...sof, fill, 0xff, 0xd9]);
}
const b64 = (data: Uint8Array) => Buffer.from(data).toString("base64");

test("DevToolsActivePort: the port, then the browser's path", () => {
  assert.deepEqual(parseActivePort("53412\n/devtools/browser/0b1c-77\n"), { port: 53412, path: "/devtools/browser/0b1c-77" });
  assert.deepEqual(parseActivePort("9222\r\n/devtools/browser/x"), { port: 9222, path: "/devtools/browser/x" });
  for (const bad of ["", "53412", "0\n/devtools/browser/x", "70000\n/devtools/browser/x", "12a\n/devtools/browser/x", "9222\n/json"]) {
    assert.equal(parseActivePort(bad), null, JSON.stringify(bad));
  }
});

test("Chrome is started as a person's browser: no automation switches, headless only when asked, the headful agent", () => {
  const headful = chromeArgs({ profile: "/d/browser/profile", port: 0, headless: false });
  assert.ok(headful.includes("--user-data-dir=/d/browser/profile"));
  assert.ok(headful.includes("--remote-debugging-port=0"));
  assert.ok(headful.includes("--disable-blink-features=AutomationControlled"), "navigator.webdriver stays false");
  assert.ok(headful.includes("--no-startup-window"), "no window that would come in front of the person's as it starts");
  for (const a of headful) assert.doesNotMatch(a, /enable-automation|remote-debugging-pipe|headless|user-agent|use-mock-keychain|password-store/);
  const headless = chromeArgs({ profile: "/p", port: 9333, headless: true, userAgent: "UA" });
  assert.ok(headless.includes("--headless=new") && headless.includes("--remote-debugging-port=9333") && headless.includes("--user-agent=UA"));
  assert.ok(!headless.includes("--no-startup-window"));
  assert.equal(
    headfulAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/155.0.0.0 Safari/537.36"),
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36",
  );
});

test("a JPEG's size is read from its frame header", () => {
  assert.deepEqual(jpegSize(jpeg(1280, 720)), { width: 1280, height: 720 });
  assert.deepEqual(jpegSize(jpeg(3, 65535)), { width: 3, height: 65535 });
  assert.equal(jpegSize(Uint8Array.from([0x89, 0x50, 0x4e, 0x47])), null);
  assert.equal(jpegSize(Uint8Array.from([0xff, 0xd8, 0xff, 0xd9])), null);
});

test("a point of the frame (0..1) is the same point of the page, in CSS pixels; outside is its edge", () => {
  assert.deepEqual(toViewport(0.5, 0.25, { width: 1200, height: 800 }), { x: 600, y: 200 });
  assert.deepEqual(toViewport(0, 1, { width: 1200, height: 800 }), { x: 0, y: 800 });
  assert.deepEqual(toViewport(-0.2, 1.5, { width: 1200, height: 800 }), { x: 0, y: 800 });
  assert.deepEqual(toViewport(Number.NaN, 0.5, { width: 10, height: 10 }), { x: 0, y: 5 });
});

test("keys: what they type, the codes Chrome acts on, shortcuts as commands", () => {
  assert.equal(keyCode("Enter", "Enter"), 13);
  assert.equal(keyCode("a", "KeyA"), 65);
  assert.equal(keyCode("@", "Digit2"), 50);
  assert.equal(keyCode("F5", "F5"), 116);
  assert.equal(keyCode(";", "Semicolon"), 186);
  assert.deepEqual(keyEvent({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 0 }), {
    type: "keyDown", key: "a", code: "KeyA", modifiers: 0, windowsVirtualKeyCode: 65, nativeVirtualKeyCode: 65, text: "a", unmodifiedText: "a",
  });
  assert.equal(keyEvent({ t: "key", kind: "down", key: "Enter", code: "Enter", mods: 0 }).text, "\r");
  const back = keyEvent({ t: "key", kind: "down", key: "Backspace", code: "Backspace", mods: 0 });
  assert.equal(back.type, "rawKeyDown");
  assert.equal(back.text, undefined);
  // ⌘A / Ctrl+A select all; with shift, ⌘Z redoes; a shortcut types nothing.
  assert.deepEqual(keyEvent({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 4 }).commands, ["selectAll"]);
  assert.deepEqual(keyEvent({ t: "key", kind: "down", key: "z", code: "KeyZ", mods: 4 | 8 }).commands, ["redo"]);
  assert.equal(keyEvent({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 2 }).text, undefined);
  assert.equal(keyEvent({ t: "key", kind: "up", key: "a", code: "KeyA", mods: 8 }).type, "keyUp");
});

/// A view over a fake connection, started; `now` moved by the test.
async function view(viewport = { width: 1000, height: 500 }) {
  const cdp = new FakeCdp();
  cdp.answers["Runtime.evaluate"] = () => ({ result: { value: "visible" } });
  let now = 1000;
  const sizes: { width: number; height: number }[] = [];
  const v = new TabView({ cdp, session: "S", targetId: "T", now: () => now, sized: (s) => sizes.push(s) });
  await v.start({ maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] }, viewport);
  const frame = (ack: number, width = 800, height = 400, meta: any = { deviceWidth: viewport.width, deviceHeight: viewport.height, timestamp: ack }) =>
    cdp.emit("Page.screencastFrame", { data: b64(jpeg(width, height, ack)), sessionId: ack, metadata: meta }, "S");
  const acks = () => cdp.of("Page.screencastFrameAck").map((s) => s.params.sessionId);
  return { cdp, v, frame, acks, sizes, at: (ms: number) => (now = ms) };
}

test("a view casts JPEG within the viewer's size, and acknowledges a frame only once the next is asked for", async () => {
  const { cdp, v, frame, acks } = await view();
  assert.deepEqual(cdp.of("Page.startScreencast")[0]!.params, { format: "jpeg", quality: 70, maxWidth: 1280, maxHeight: 720, everyNthFrame: 1 });
  assert.equal(cdp.of("Page.startScreencast")[0]!.sessionId, "S", "on the view's own session");

  // Asked before any frame: given the first when it comes, with its config.
  const first = v.next();
  frame(1);
  const f1 = (await first)!;
  assert.deepEqual(f1.config, { codec: "jpeg", width: 800, height: 400 });
  assert.equal(f1.key, true);
  assert.equal(f1.ts, 1_000_000);
  assert.deepEqual(acks(), [], "not acknowledged while the viewer has not asked for more");

  // Two more come meanwhile: the next ask takes the first as taken, gives the newest and lets the older go.
  frame(2);
  frame(3);
  const f3 = (await v.next())!;
  assert.equal(f3.data[f3.data.length - 3], 3, "the newest");
  assert.equal(f3.config, undefined, "the same size: no config again");
  assert.deepEqual(acks(), [1, 2]);

  // A size change comes with its config.
  const next = v.next();
  assert.deepEqual(acks(), [1, 2, 3]);
  frame(4, 640, 320);
  assert.deepEqual((await next)!.config, { codec: "jpeg", width: 640, height: 320 });
});

test("a view never holds more than two frames unacknowledged", async () => {
  const { v, frame, acks } = await view();
  frame(1);
  frame(2);
  frame(3);
  assert.deepEqual(acks(), [1], "the oldest let go when a third came");
  assert.equal((await v.next())!.ts, 3_000_000);
  assert.deepEqual(acks(), [1, 2]);
});

test("a key frame asked for is the last frame again, with its config, at once", async () => {
  const { v, frame } = await view();
  frame(1);
  const f1 = (await v.next())!;
  const waiting = v.next();
  v.keyframe();
  const again = (await waiting)!;
  assert.deepEqual(again.config, f1.config);
  assert.deepEqual(again.data, f1.data);
  assert.ok(again.ts > f1.ts, "its time still rises");
});

test("a view ends when its tab goes: a waiting next is null, and so is every one after", async () => {
  const { cdp, v } = await view();
  const waiting = v.next();
  cdp.emit("Target.detachedFromTarget", { sessionId: "S", targetId: "T" });
  assert.equal(await waiting, null);
  assert.equal(await v.next(), null);
});

test("a view laid out for the viewer's phone: its size and scale on the view's own session, cast as large as that, and let go as it ends", async () => {
  const cdp = new FakeCdp();
  const v = new TabView({ cdp, session: "S", targetId: "T", now: () => 0 });
  await v.start({ maxWidth: 1920, maxHeight: 1080, codecs: ["jpeg"], fit: { width: 390, height: 844, scale: 3 } });
  assert.deepEqual(cdp.of("Emulation.setDeviceMetricsOverride").map((x) => [x.params, x.sessionId]), [[{ width: 390, height: 844, deviceScaleFactor: 2, mobile: true }, "S"]]);
  const cast = cdp.of("Page.startScreencast")[0]!.params;
  assert.deepEqual([cast.maxWidth, cast.maxHeight], [780, 1688], "as large as the phone shows it, at most twice its CSS pixels");
  // A tap lands where it is on the phone's page.
  await v.input({ t: "pointer", kind: "down", x: 0.5, y: 0.25, buttons: 1 });
  const press = cdp.of("Input.dispatchMouseEvent")[0]!.params;
  assert.deepEqual([press.x, press.y], [195, 211]);
  v.close();
  await turn();
  assert.equal(cdp.of("Emulation.clearDeviceMetricsOverride").length, 1);
  // A preview, or a view with no phone to lay out for, leaves the page as it is.
  for (const options of [{ peek: true, fit: { width: 390, height: 844, scale: 3 } }, {}]) {
    const other = new FakeCdp();
    const w = new TabView({ cdp: other, session: "S", targetId: "T", now: () => 0 });
    await w.start({ maxWidth: 1280, maxHeight: 720, codecs: ["jpeg"], ...options }, { width: 1200, height: 800 });
    w.close();
    await turn();
    assert.equal(other.of("Emulation.setDeviceMetricsOverride").length + other.of("Emulation.clearDeviceMetricsOverride").length, 0);
  }
});

test("a view's ask: the phone it is laid out for only when it drives the screen, and only a phone's size", () => {
  const fit = { width: 390, height: 844, scale: 3 };
  assert.deepEqual(asked({ codecs: ["jpeg"], control: true, fit }).fit, fit);
  assert.equal(asked({ codecs: ["jpeg"], control: false, fit }).fit, undefined, "only looking: the page stays as others see it");
  assert.equal(asked({ codecs: ["jpeg"], control: true, peek: true, fit }).fit, undefined);
  for (const bad of [{ ...fit, width: 50 }, { ...fit, height: 9000 }, { ...fit, scale: 0 }, { ...fit, scale: "3" }, null]) assert.equal(asked({ codecs: ["jpeg"], control: true, fit: bad }).fit, undefined, JSON.stringify(bad));
});

test("closing a view stops its cast and its connection", async () => {
  const { cdp, v } = await view();
  const waiting = v.next();
  v.close();
  assert.equal(await waiting, null);
  await turn();
  assert.equal(cdp.of("Page.stopScreencast").length, 1);
  assert.equal(cdp.gone, true);
});

test("a person's pointer lands on the page where they see it; a quick second press is a double click", async () => {
  const { cdp, v, frame, at, sizes } = await view({ width: 0, height: 0 });
  // The viewport as the frames say it (here 1200 × 600 CSS pixels, cast smaller).
  frame(1, 800, 400, { deviceWidth: 1200, deviceHeight: 600, timestamp: 1 });
  await v.next();
  assert.deepEqual(sizes.at(-1), { width: 1200, height: 600 });
  await v.input({ t: "pointer", kind: "move", x: 0.5, y: 0.5, buttons: 0 });
  await v.input({ t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 1 });
  await v.input({ t: "pointer", kind: "up", x: 0.25, y: 0.5, buttons: 0 });
  at(1300);
  await v.input({ t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 1 });
  await v.input({ t: "pointer", kind: "up", x: 0.25, y: 0.5, buttons: 0 });
  at(5000);
  await v.input({ t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 2 });
  await v.input({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 120 });
  const mouse = cdp.of("Input.dispatchMouseEvent").map((s) => ({ ...s.params, session: s.sessionId }));
  assert.deepEqual(
    mouse.map((m) => [m.type, m.x, m.y, m.button, m.clickCount]),
    [
      ["mouseMoved", 600, 300, "none", undefined],
      ["mousePressed", 300, 300, "left", 1],
      ["mouseReleased", 300, 300, "left", 1],
      ["mousePressed", 300, 300, "left", 2],
      ["mouseReleased", 300, 300, "left", 2],
      ["mousePressed", 300, 300, "right", 1],
      ["mouseWheel", 600, 300, "none", undefined],
    ],
  );
  assert.equal(mouse.at(-1)!.deltaY, 120);
  assert.ok(mouse.every((m) => m.session === "S"));
  await v.input({ t: "text", text: "你好" });
  assert.deepEqual(cdp.of("Input.insertText")[0]!.params, { text: "你好" });
});

test("a view never brings its tab forward (that would bring the browser in front of the person at the machine)", async () => {
  const cdp = new FakeCdp();
  cdp.answers["Runtime.evaluate"] = () => ({ result: { value: "hidden" } });
  const v = new TabView({ cdp, session: "S", targetId: "T", now: () => 0 });
  await v.start({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] }, { width: 10, height: 10 });
  v.keyframe();
  await v.input({ t: "pointer", kind: "down", x: 0.5, y: 0.5, buttons: 1 });
  await turn();
  assert.deepEqual(cdp.of("Target.activateTarget"), []);
});

/// Tabs over a fake browser connection, into a registry; each view's connection a new fake.
async function tabs(owners?: Owners) {
  const cdp = new FakeCdp();
  const screens = makeScreens();
  const lists: string[][] = [];
  screens.watch((all) => lists.push(all.map((s) => `${s.id} ${s.title()}`)));
  let used = 0;
  const views: FakeCdp[] = [];
  const timers: { ms: number; f: () => void }[] = [];
  // The tabs' viewport as the page says it (Page.getLayoutMetrics).
  const viewport = { clientWidth: 1200, clientHeight: 845 };
  const t = new Tabs({
    cdp, screens, now: () => 0, activity: () => used++, ...(owners ? { owners } : {}),
    later: (ms, f) => {
      const timer = { ms, f };
      timers.push(timer);
      return () => timers.splice(timers.indexOf(timer) >>> 0, 1);
    },
    connect: async () => {
      const c = new FakeCdp();
      c.answers["Target.attachToTarget"] = () => ({ sessionId: `V${views.length}` });
      c.answers["Runtime.evaluate"] = () => ({ result: { value: "visible" } });
      c.answers["Page.getLayoutMetrics"] = () => ({ cssVisualViewport: { ...viewport } });
      views.push(c);
      return c;
    },
  });
  // The tabs there at start are told as created before the answer.
  cdp.answers["Target.setDiscoverTargets"] = () => {
    cdp.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "New Tab", url: "chrome://newtab/", attached: false } });
    cdp.emit("Target.targetCreated", { targetInfo: { targetId: "W", type: "service_worker", title: "sw", url: "https://x/sw.js" } });
    return {};
  };
  await t.start();
  return { cdp, screens, lists, t, views, timers, viewport, used: () => used };
}

test("every page of the browser is a screen while it is there; its title follows it", async () => {
  const { cdp, screens, lists, t, used } = await tabs();
  assert.deepEqual(screens.list().map((s) => [s.id, s.kind, s.title()]), [["browser:A", "browser", "New Tab"]], "pages only");
  assert.equal(used(), 0, "the tabs found at start are no use of it");
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "B", type: "page", title: "", url: "about:blank", attached: true } });
  cdp.emit("Target.targetInfoChanged", { targetInfo: { targetId: "B", type: "page", title: "GitHub", url: "https://github.com/", attached: true } });
  assert.deepEqual(lists.at(-1), ["browser:A New Tab", "browser:B GitHub"]);
  assert.deepEqual(t.list(), [
    { id: "A", title: "New Tab", url: "chrome://newtab/", attached: false },
    { id: "B", title: "GitHub", url: "https://github.com/", attached: true },
  ]);
  cdp.emit("Target.targetDestroyed", { targetId: "A" });
  assert.deepEqual(lists.at(-1), ["browser:B GitHub"]);
  assert.ok(used() >= 3);
  t.close();
  assert.deepEqual(screens.list(), []);
});

test("a title the page gives itself after it loads (Chrome does not tell of it) is read again a little later", async () => {
  const { cdp, lists, timers } = await tabs();
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "B", type: "page", title: "", url: "https://mail/", attached: false } });
  cdp.emit("Target.targetInfoChanged", { targetInfo: { targetId: "B", type: "page", title: "mail", url: "https://mail/", attached: false } });
  assert.deepEqual(timers.map((t) => t.ms), [1000, 5000], "once, after the last change");
  cdp.answers["Target.getTargets"] = () => ({
    targetInfos: [
      { targetId: "A", type: "page", title: "New Tab", url: "chrome://newtab/" },
      { targetId: "B", type: "page", title: "Inbox (3)", url: "https://mail/" },
    ],
  });
  for (const t of timers.splice(0)) t.f();
  await turn();
  assert.deepEqual(lists.at(-1), ["browser:A New Tab", "browser:B Inbox (3)"]);
});

test("a tab's view is on a connection of its own, and only for viewers that take JPEG", async () => {
  const { cdp, screens, views, t } = await tabs();
  const tab = screens.get("browser:A")!;
  await assert.rejects(tab.open({ maxWidth: 100, maxHeight: 100, codecs: ["h264"] }), /JPEG/);
  await turn();
  // The connection that measured the tab's viewport, closed.
  assert.equal(views.length, 1);
  assert.equal(views[0]!.gone, true);
  const v = await tab.open({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] });
  assert.equal(views.length, 2);
  assert.deepEqual(views[1]!.of("Target.attachToTarget")[0]!.params, { targetId: "A", flatten: true });
  assert.equal(cdp.of("Target.attachToTarget").length, 0, "not on the browser's own connection");
  assert.equal(t.viewing(), 1);
  v.close();
  assert.equal(t.viewing(), 0);
});

test("a tab's size is its viewport (not its window), measured as it comes and told again as a view finds it changed", async () => {
  const { cdp, screens, lists, viewport } = await tabs();
  cdp.answers["Browser.getWindowForTarget"] = () => ({ bounds: { width: 1200, height: 932 } });
  await turn();
  const tab = screens.get("browser:A")!;
  assert.deepEqual(tab.size(), { width: 1200, height: 845 });
  // The window made shorter: a view reads the viewport as it starts, and the list hears of it.
  const told = lists.length;
  viewport.clientHeight = 700;
  const v = await tab.open({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] });
  assert.deepEqual(tab.size(), { width: 1200, height: 700 });
  assert.equal(lists.length, told + 1);
  v.close();
  // The same size again is no change.
  (await tab.open({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] })).close();
  assert.equal(lists.length, told + 1);
});

/// A Chrome of the test's making: started, found, killed, each a connection the test can end (the browser dying).
function fakeChrome() {
  const made: FakeCdp[] = [];
  const calls: string[] = [];
  /// Each context's cookies (the default context's under ""), by domain, path and name.
  const jars = new Map<string, Map<string, any>>();
  let left: Running | null = null;
  let n = 0;
  const running = (): Running => ({ pid: 100 + n, started: 0, port: 9300, ws: `ws://127.0.0.1:9300/devtools/browser/${n}`, binary: "chrome", headless: false, userAgent: "UA" });
  const host: ChromeHost = {
    async find() {
      calls.push("find");
      return left;
    },
    async launch() {
      n++;
      calls.push("launch");
      return running();
    },
    async kill(r) {
      calls.push(`kill ${r.pid}`);
      left = null;
    },
    async connect() {
      const c = new FakeCdp();
      c.answers["Browser.close"] = () => {
        queueMicrotask(() => c.close());
        return {};
      };
      // A new tab: its id answered, then told of (as Chrome may).
      c.answers["Target.createTarget"] = (p) => {
        const targetId = `N${c.of("Target.createTarget").length}`;
        setImmediate(() => c.emit("Target.targetCreated", { targetInfo: { targetId, type: "page", title: "", url: p.url, attached: false, ...(p.browserContextId ? { browserContextId: p.browserContextId } : {}) } }));
        return { targetId };
      };
      // A context in memory: its cookies kept by it, as Chrome keeps them (one set to have expired goes).
      c.answers["Target.createBrowserContext"] = () => ({ browserContextId: `C${c.of("Target.createBrowserContext").length}` });
      c.answers["Storage.getCookies"] = (p) => ({ cookies: [...(jars.get(p.browserContextId ?? "") ?? new Map()).values()] });
      c.answers["Storage.setCookies"] = (p) => {
        const jar = jars.get(p.browserContextId ?? "") ?? new Map();
        jars.set(p.browserContextId ?? "", jar);
        for (const k of p.cookies) {
          const key = `${k.domain}\0${k.path}\0${k.name}`;
          if (k.expires === 1) jar.delete(key);
          else jar.set(key, k);
        }
        return {};
      };
      made.push(c);
      return c;
    },
  };
  return { host, made, calls, jars, leave: (r: Running | null) => (left = r) };
}

function clock() {
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  const c = Effect.runSync(Scope.provide(TestClock.make(), scope));
  return { clock: c as Clock.Clock, adjust: async (ms: number) => {
    await Effect.runPromise(c.adjust(ms));
    await turn();
  } };
}

test("the browser is started once however many ask at once, and its endpoint said", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const [a, z] = await Promise.all([b.endpoint(), b.endpoint()]);
  assert.deepEqual(chrome.calls, ["find", "launch"]);
  assert.equal(a.http, "http://127.0.0.1:9300");
  assert.equal(z.ws, "ws://127.0.0.1:9300/devtools/browser/1");
  const text = howTo(a, null);
  assert.match(text, /--browserUrl http:\/\/127\.0\.0\.1:9300/);
  assert.match(text, /connectOverCDP\("http:\/\/127\.0\.0\.1:9300"\)/);
  assert.match(text, /`screen` tool/);
  await b.close();
});

test("unused for an hour it is closed; used meanwhile, it stays", async () => {
  const chrome = fakeChrome();
  const { clock: c, adjust } = clock();
  const dir = scratch();
  const b = new StationBrowser({ later: () => () => {}, dir, chrome: chrome.host, clock: c });
  await b.endpoint();
  await adjust(IDLE_MS - 1000);
  b.used();
  await adjust(1000);
  assert.equal(b.status().running, true, "used a second before the hour");
  await adjust(IDLE_MS);
  assert.equal(b.status().running, false);
  assert.equal(chrome.made[0]!.of("Browser.close").length, 1, "asked to close, so it saves its profile");
  assert.deepEqual(chrome.calls, ["find", "launch", "kill 101"]);
  assert.equal(readState(dir).lastUse, IDLE_MS - 1000, "its last use written down");
  await b.close();
});

test("a person watching a tab keeps it open", async () => {
  const chrome = fakeChrome();
  const { clock: c, adjust } = clock();
  const screens = makeScreens();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c, screens });
  await b.endpoint();
  const cdp = chrome.made[0]!;
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "x", url: "https://x/" } });
  const v = await screens.get("browser:A")!.open({ maxWidth: 10, maxHeight: 10, codecs: ["jpeg"] });
  await adjust(3 * IDLE_MS);
  assert.equal(b.status().running, true);
  v.close();
  await adjust(IDLE_MS);
  assert.equal(b.status().running, false);
  assert.deepEqual(screens.list(), [], "its tabs left the screens");
  await b.close();
});

test("dying in use it is started again, at once after a long run, after a growing pause when it keeps dying", async () => {
  const chrome = fakeChrome();
  const { clock: c, adjust } = clock();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  await b.endpoint();
  await adjust(120_000);
  b.used();
  chrome.made[0]!.close(); // it died
  await turn();
  assert.equal(b.status().running, true, "started again at once");
  assert.deepEqual(chrome.calls, ["find", "launch", "kill 101", "find", "launch"]);
  chrome.made[1]!.close(); // and died again at once
  await turn();
  assert.equal(b.status().running, false);
  await adjust(999);
  assert.equal(b.status().running, false);
  await adjust(1);
  assert.equal(b.status().running, true, "after a second");
  chrome.made[2]!.close();
  await turn();
  await adjust(1999);
  assert.equal(b.status().running, false);
  await adjust(1);
  assert.equal(b.status().running, true, "after two");
  await b.close();
});

test("a station process that ends leaves the browser running, and the next takes it up with its tabs", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const dir = scratch();
  const first = new StationBrowser({ later: () => () => {}, dir, chrome: chrome.host, clock: c });
  const r = await first.endpoint();
  await first.close();
  assert.ok(!chrome.calls.some((x) => x.startsWith("kill")), "not killed");
  assert.equal(chrome.made[0]!.of("Browser.close").length, 0, "not closed");
  chrome.leave({ pid: r.pid!, started: 0, port: 9300, ws: r.ws!, binary: "chrome", headless: false, userAgent: "UA" });

  const screens = makeScreens();
  const next = new StationBrowser({ later: () => () => {}, dir, chrome: chrome.host, clock: c, screens });
  const connected = chrome.made.length;
  chrome.host.connect = async (url) => {
    const cdp = new FakeCdp();
    cdp.answers["Target.setDiscoverTargets"] = () => {
      cdp.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "Mail", url: "https://mail/" } });
      return {};
    };
    chrome.made.push(cdp);
    assert.equal(url, r.ws);
    return cdp;
  };
  await next.resume();
  await turn();
  // Its own connection, and one that measured the tab's viewport and closed.
  assert.equal(chrome.made.length, connected + 2);
  assert.equal(chrome.made[connected + 1]!.gone, true);
  assert.equal(next.status().running, true);
  assert.deepEqual(screens.list().map((s) => s.id), ["browser:A"]);
  assert.equal((await next.endpoint()).ws, r.ws, "the same browser");
  assert.equal(chrome.calls.filter((x) => x === "launch").length, 1);
  await next.close();
});

test("the browser tool: endpoint by default, tabs, status, stop, each of them the chat's own context", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const [tool] = browserTools(b);
  assert.equal(tool!.name, "browser");
  assert.equal((tool!.inputSchema as any).type, "object");
  assert.match(await tool!.run("s", { action: "status" }), /Not running/);
  assert.match(await tool!.run("s", {}), /DevTools for this chat: http:\/\/127\.0\.0\.1:9300/);
  chrome.made[0]!.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "Docs", url: "https://docs/", browserContextId: "C1" } });
  chrome.made[0]!.emit("Target.targetCreated", { targetInfo: { targetId: "Z", type: "page", title: "Login", url: "https://login/" } });
  assert.match(await tool!.run("s", { action: "tabs" }), /A "Docs" https:\/\/docs\//);
  assert.doesNotMatch(await tool!.run("s", { action: "tabs" }), /Login/, "the station's own tab is not the chat's");
  assert.match(await tool!.run("s", { action: "status" }), /Running: http:\/\/127\.0\.0\.1:9300.*1 tab/);
  assert.match(await tool!.run("other", { action: "status" }), /Not running/, "another chat has no context yet");
  assert.match(await tool!.run("other", { action: "tabs" }), /No tabs/);
  assert.match(await tool!.run("s", { action: "stop" }), /closed/);
  assert.deepEqual(chrome.made[0]!.of("Target.disposeBrowserContext").map((x) => x.params), [{ browserContextId: "C1" }]);
  assert.equal(b.status("s").running, false);
  assert.equal(b.station.status().running, true, "the one browser stays for the others");
  await assert.rejects(tool!.run("s", { action: "nope" }), /unknown action/);
  await b.close();
});

test("a tab is the session's that opened it, and a tab it opens is too; a tab gone is forgotten", async () => {
  const owners = new Owners(scratch());
  const { cdp, screens, lists, t } = await tabs(owners);
  const told = lists.length;
  t.owned("A", "chat-1");
  assert.equal(lists.length, told + 1, "the screens' watchers hear who opened it");
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "P", type: "page", title: "", url: "https://login/", attached: false, openerId: "A" } });
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "Q", type: "page", title: "", url: "https://other/", attached: false } });
  assert.deepEqual(screens.list().map((s) => [s.id, s.openedBy?.()]), [["browser:A", "chat-1"], ["browser:P", "chat-1"], ["browser:Q", undefined]]);
  assert.deepEqual(t.list().map((x) => x.session), ["chat-1", "chat-1", undefined]);
  assert.deepEqual(t.ofSession("chat-1"), ["A", "P"]);
  t.owned("A", "chat-1");
  assert.equal(lists.length, told + 3, "the same again is no news (the two tabs came)");
  cdp.emit("Target.targetDestroyed", { targetId: "P" });
  assert.equal(owners.of("P"), undefined);
  t.close();
});

test("a tab is closed from a person's app; the desktop's screen is not a tab", async () => {
  const { cdp, screens, t } = await tabs();
  const tab = screens.get("browser:A")!;
  assert.ok(tab.discard);
  await tab.discard!();
  assert.deepEqual(cdp.of("Target.closeTarget").map((c) => c.params), [{ targetId: "A" }]);
  cdp.emit("Target.targetDestroyed", { targetId: "A" });
  await assert.rejects(tab.discard!(), /closed/);
  t.close();
});

test("whose each tab is outlives the station process, and is forgotten for tabs no longer there", async () => {
  const dir = scratch();
  const first = new Owners(dir);
  first.set("A", "chat-1");
  first.set("Z", "chat-2");
  const owners = new Owners(dir);
  assert.equal(owners.of("A"), "chat-1");
  const { t } = await tabs(owners);
  assert.equal(owners.of("A"), "chat-1", "A is still there");
  assert.equal(new Owners(dir).of("Z"), undefined, "Z closed while no station watched");
  t.close();
});

test("a tab of the station's own: opened at a page in a window of its own behind the others (the browser started for it) once it is among the screens, closed when asked", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const screens = makeScreens();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c, screens });
  assert.equal(b.available(), true, "a Chrome is there to start");
  const id = await b.openTab("https://claude.ai/oauth/authorize?x=1");
  const cdp = chrome.made[0]!;
  assert.deepEqual(cdp.of("Target.createTarget").map((x) => x.params), [{ url: "https://claude.ai/oauth/authorize?x=1", newWindow: true, background: true }]);
  assert.ok(screens.get(`browser:${id}`), "among the screens by the time it is given");
  assert.equal(b.hasTab(id), true);
  assert.equal(b.tabs().find((t) => t.id === id)?.session, undefined, "no session's");
  await b.closeTab(id);
  assert.deepEqual(cdp.of("Target.closeTarget").map((x) => x.params), [{ targetId: id }]);
  await b.closeTab("no-such-tab");
  assert.equal(cdp.of("Target.closeTarget").length, 1);
  await b.close();
  const none = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: { ...chrome.host, installed: () => false }, clock: c });
  assert.equal(none.available(), false);
});

test("a chat archived closes the tabs it opened, and only those", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  await b.closeOf("chat-1");
  await b.endpoint();
  const cdp = chrome.made[0]!;
  for (const id of ["A", "B", "C"]) cdp.emit("Target.targetCreated", { targetInfo: { targetId: id, type: "page", title: id, url: "https://x/" } });
  b.own("A", "chat-1");
  b.own("C", "chat-1");
  b.own("B", "chat-2");
  await b.closeOf("chat-1");
  assert.deepEqual(cdp.of("Target.closeTarget").map((x) => x.params.targetId).sort(), ["A", "C"]);
  await b.close();
});

test("a session's address of the browser: its key, and nothing else", () => {
  for (const key of ["EMBER/1792746112.235000", "slack:C1/1.2", "中文"]) assert.equal(sessionOfPath(sessionPath(key)), key);
  assert.equal(sessionOfPath(`${sessionPath("k")}/`), "k");
  assert.equal(sessionOfPath("/browser/"), null);
  assert.equal(sessionOfPath("/browser/a+b"), null);
  assert.equal(sessionOfPath("/browser/a/devtools/browser/1"), null);
});

test("a session's connection through the door reaches the browser through its chat's gate, the tabs it opens in its context, each in a window of its own behind the others, none brought forward", async () => {
  // Chrome's DevTools of the test's making: answers Target.createTarget with a new tab, echoes the rest.
  const chrome = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise<void>((r) => chrome.once("listening", () => r()));
  const creates: any[] = [];
  const fronts: string[] = [];
  chrome.on("connection", (ws) =>
    ws.on("message", (raw) => {
      const m = JSON.parse(raw.toString());
      if (m.method === "Target.createTarget") creates.push(m);
      if (m.method === "Target.activateTarget" || m.method === "Page.bringToFront") fronts.push(m.method);
      const result = m.method === "Target.createTarget" ? { targetId: `T${m.id}` } : { echo: m.params };
      ws.send(JSON.stringify({ id: m.id, ...(m.sessionId ? { sessionId: m.sessionId } : {}), result }));
    }));
  const opened: string[] = [];
  const asked: string[] = [];
  const browser = {
    open: async (session: string) => (asked.push(session), { ws: `ws://127.0.0.1:${(chrome.address() as any).port}/devtools/browser/x`, gate: { context: "C1", contextOf: () => undefined, opened: (id: string) => opened.push(id) } }),
  };
  const route = browserDoor(browser);
  const door = await openAgentsDoor({ port: 0 }, new McpEndpoint(() => undefined, []), () => ({ status: 404, body: {} }), () => null, () => [route]);
  const at = `ws://127.0.0.1:${door.port}${sessionPath("EMBER/1.2")}`;
  const client = new WebSocket(at);
  await new Promise<void>((r, j) => (client.once("open", () => r()), client.once("error", j)));
  const answers: any[] = [];
  const answered = (n: number) => new Promise<void>((r) => {
    const check = () => (answers.length >= n ? r() : client.once("message", (raw) => (answers.push(JSON.parse(raw.toString())), check())));
    check();
  });
  client.send(JSON.stringify({ id: 1, method: "Browser.getVersion", params: { a: 1 } }));
  client.send(JSON.stringify({ id: 2, method: "Target.createTarget", params: { url: "about:blank" } }));
  await answered(2);
  assert.deepEqual(answers[0], { id: 1, result: { echo: { a: 1 } } });
  assert.deepEqual(asked, ["EMBER/1.2"], "the session's own chat's context");
  assert.deepEqual(opened, ["T2"]);
  // Opened in the chat's context, in a window of its own behind the others, the rest of what was asked as it was.
  assert.deepEqual(creates, [{ id: 2, method: "Target.createTarget", params: { url: "about:blank", browserContextId: "C1", newWindow: true, background: true } }]);
  // Bringing a tab forward is answered as done, and never reaches the browser; a session not the chat's is refused.
  client.send(JSON.stringify({ id: 3, method: "Target.activateTarget", params: { targetId: "T2" } }));
  client.send(JSON.stringify({ id: 4, sessionId: "S", method: "Page.bringToFront", params: {} }));
  client.send(JSON.stringify({ id: 5, method: "Browser.getVersion", params: {} }));
  await answered(5);
  assert.deepEqual(answers.slice(2, 4), [{ id: 3, result: {} }, { id: 4, sessionId: "S", error: { code: -32601, message: "No such session of this chat's." } }]);
  assert.deepEqual(answers[4], { id: 5, result: { echo: {} } });
  assert.deepEqual(fronts, []);

  // Only programs on this machine: a web page (it says its Origin) is refused.
  const page = new WebSocket(at, { headers: { origin: "https://evil.example" } });
  const refused = await new Promise<number>((r) => page.once("unexpected-response", (_req, res) => r(res.statusCode!)));
  assert.equal(refused, 403);
  // Not a WebSocket: what to do with the address.
  assert.equal((await fetch(`http://127.0.0.1:${door.port}${sessionPath("EMBER/1.2")}`)).status, 400);

  client.close();
  await door.close(0);
  await new Promise<void>((r) => chrome.close(() => r()));
});

test("the browser tool gives each session its own address on the door, never Chrome's own port", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const [tool] = browserTools(b, () => "http://127.0.0.1:4750/mcp");
  const said = await tool!.run("EMBER/1.2", {});
  const ws = `ws://127.0.0.1:4750${sessionPath("EMBER/1.2")}`;
  assert.ok(said.includes(`--wsEndpoint ${ws}`), said);
  assert.ok(said.includes(`connectOverCDP("${ws}")`), said);
  assert.ok(!said.includes("9300"), "Chrome's own port is not given");
  await b.close();
});

test("each chat has a context of its own in the one browser; a tab in it is its chat's, one in the station's own context no chat's", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const screens = makeScreens();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c, screens });
  const [one, two] = await Promise.all([b.context("chat-1"), b.context("chat-2")]);
  assert.equal(await b.context("chat-1"), one, "the same context asked again");
  assert.notEqual(one, two);
  assert.deepEqual(chrome.calls, ["find", "launch"], "one Chrome for both");
  const cdp = chrome.made[0]!;
  assert.deepEqual(cdp.of("Target.createBrowserContext").map((x) => x.params), [{ disposeOnDetach: false }, { disposeOnDetach: false }]);
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "", url: "https://a/", browserContextId: one } });
  cdp.emit("Target.targetCreated", { targetInfo: { targetId: "B", type: "page", title: "", url: "https://b/", browserContextId: two } });
  const own = await b.station.openTab("https://login/");
  assert.deepEqual(screens.list().map((x) => [x.id, x.openedBy?.()]), [["browser:A", "chat-1"], ["browser:B", "chat-2"], [`browser:${own}`, undefined]]);
  assert.equal(b.station.contextOf("A"), one);
  const { gate } = await b.open("chat-1");
  assert.equal(gate.context, one);
  assert.equal(gate.contextOf("B"), two, "the gate knows another chat's tab as another's");
  await b.close();
});

test("a chat archived: its context goes, its tabs with it; another's stays", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const one = await b.context("chat-1");
  await b.context("chat-2");
  await b.closeOf("chat-1");
  assert.deepEqual(chrome.made[0]!.of("Target.disposeBrowserContext").map((x) => x.params), [{ browserContextId: one }]);
  assert.equal(b.status("chat-1").running, false);
  assert.equal(b.status("chat-2").running, true);
  await b.closeOf("never-had-one");
  assert.equal(chrome.made[0]!.of("Target.disposeBrowserContext").length, 1);
  await b.close();
});

test("the contexts go with their Chrome: one started again gives each chat a new one as it asks, told so its sign-ins go in again", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const fresh: string[] = [];
  b.onFresh((s) => fresh.push(s));
  const first = await b.context("chat-1");
  await b.station.stop();
  const again = await b.context("chat-1");
  assert.deepEqual(chrome.calls.filter((x) => x === "launch").length, 2);
  assert.deepEqual(chrome.made.at(-1)!.of("Target.createBrowserContext").length, 1, "made in the new Chrome");
  assert.deepEqual(fresh, ["chat-1", "chat-1"]);
  assert.ok(first && again);
  await b.close();
});

test("a station process that ends leaves the chats' contexts in the running browser, and the next takes them up", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const dir = scratch();
  const first = new Browsers({ later: () => () => {}, dir, chrome: chrome.host, clock: c });
  const ctx = await first.context("chat-1");
  const r = first.station.status();
  await first.close();
  chrome.leave({ pid: 7, started: 0, port: 9300, ws: r.ws!, binary: "chrome", headless: true, userAgent: "UA" });
  const screens = makeScreens();
  const next = new Browsers({ later: () => () => {}, dir, chrome: chrome.host, clock: c, screens });
  await next.resume();
  chrome.made.at(-1)!.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "", url: "https://a/", browserContextId: ctx } });
  assert.equal(screens.get("browser:A")?.openedBy?.(), "chat-1", "its tab still its chat's");
  assert.equal(await next.context("chat-1"), ctx, "the same context, not a new one");
  assert.equal(chrome.calls.filter((x) => x === "launch").length, 1);
  await next.close();
});

test("a sign-in goes into its chat's context, its sites' cookies only, and out again when its grant ends, its cookies as they were then given back", async () => {
  const chrome = fakeChrome();
  const { clock: c, adjust } = clock();
  const b = new Browsers({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const back: [string, string, any[]][] = [];
  b.onTakenOut((s, r, cookies) => back.push([s, r, JSON.parse(cookies)]));
  const cookies = [
    { name: "user_session", value: "abc", domain: "github.com", path: "/", secure: true, httpOnly: true, expires: 4_000_000_000 },
    { name: "_gh_sess", value: "x", domain: ".github.com", path: "/", session: true, expires: -1 },
    { name: "other", value: "no", domain: "gitlab.com", path: "/" },
  ];
  await b.signIn("chat-1", { request: "r_1", sites: ["github.com"], cookies: JSON.stringify(cookies), until: 600 });
  const ctx = await b.context("chat-1");
  assert.deepEqual([...chrome.jars.get(ctx)!.values()].map((x) => [x.name, x.expires]), [["user_session", 4_000_000_000], ["_gh_sess", undefined]], "its sites' cookies only, a session cookie without an expiry");
  assert.equal(chrome.jars.get("")?.size ?? 0, 0, "nothing in the station's own context");
  assert.equal(JSON.parse(await b.cookies("chat-2", ["github.com"], false)).length, 0, "another chat's context has none of them");
  // The site gives a new session cookie meanwhile.
  await chrome.made[0]!.send("Storage.setCookies", { browserContextId: ctx, cookies: [{ name: "user_session", value: "renewed", domain: "github.com", path: "/" }] });
  await adjust(599_000);
  assert.equal(chrome.jars.get(ctx)!.size, 2, "in until its grant ends");
  await adjust(1000);
  assert.equal(chrome.jars.get(ctx)!.size, 0, "taken out");
  assert.deepEqual(back.map(([s, r, k]) => [s, r, k.map((x: any) => x.value)]), [["chat-1", "r_1", ["renewed", "x"]]]);
  await b.close();
});

test("a sign-in whose grant ended while the browser was closed is taken out before the chat's agent has it again", async () => {
  const chrome = fakeChrome();
  const { clock: c, adjust } = clock();
  const dir = scratch();
  const first = new Browsers({ later: () => () => {}, dir, chrome: chrome.host, clock: c });
  await first.signIn("chat-1", { request: "r_1", sites: ["github.com"], cookies: JSON.stringify([{ name: "a", value: "1", domain: "github.com", path: "/" }]), until: 60 });
  const r = first.station.status();
  await first.close();
  chrome.leave({ pid: 7, started: 0, port: 9300, ws: r.ws!, binary: "chrome", headless: true, userAgent: "UA" });
  await adjust(120_000);
  const next = new Browsers({ later: () => () => {}, dir, chrome: chrome.host, clock: c });
  const back: string[] = [];
  next.onTakenOut((_s, req) => back.push(req));
  await next.resume();
  await next.endpoint("chat-1");
  assert.deepEqual(back, ["r_1"]);
  await next.close();
});

test("a login form filled from a person's app: what the wire takes (a host, an account or a password, bounded); the tab's host as its address has it", () => {
  assert.deepEqual(parseFill({ t: "fill", host: "github.com", username: "a", password: "p" }), { host: "github.com", username: "a", password: "p" });
  assert.deepEqual(parseFill({ t: "fill", host: "github.com", password: "p" }), { host: "github.com", password: "p" });
  assert.equal(parseFill({ t: "fill", host: "github.com" }), null, "nothing to fill");
  assert.equal(parseFill({ t: "fill", host: "", password: "p" }), null);
  assert.equal(parseFill({ t: "fill", host: "github.com", password: "x".repeat(1025) }), null);
  assert.equal(parseFill({ t: "text", text: "p" }), null);
  assert.equal(hostOf("https://Accounts.Google.com./signin?x=1"), "accounts.google.com");
  assert.equal(hostOf("about:blank"), "");
});

test("a passkey sign-in answered from a person's app: what the wire takes (base64url, bounded; or a browser's error); the relying parties a tab's host may name", () => {
  assert.deepEqual(parsePasskey({ t: "passkey", id: "1", credential: "CQk", authenticatorData: "AAAA", signature: "BwcH", userHandle: "BQ" }), { id: "1", credential: "CQk", authenticatorData: "AAAA", signature: "BwcH", userHandle: "BQ" });
  assert.deepEqual(parsePasskey({ t: "passkey", id: "1", error: "NotAllowedError" }), { id: "1", error: "NotAllowedError" });
  assert.equal(parsePasskey({ t: "passkey", id: "1", credential: "CQk", authenticatorData: "AA==", signature: "BwcH" }), null, "base64url only");
  assert.equal(parsePasskey({ t: "passkey", id: "1", credential: "CQk", signature: "BwcH" }), null);
  assert.equal(parsePasskey({ t: "passkey", id: "1", error: "<script>" }), null);
  assert.equal(parsePasskey({ t: "fill", host: "github.com", password: "p" }), null);
  assert.equal(rpFor("github.com", "github.com"), true);
  assert.equal(rpFor("google.com", "accounts.google.com"), true);
  assert.equal(rpFor("Google.com.", "accounts.google.com"), true);
  assert.equal(rpFor("evil.com", "accounts.google.com"), false);
  assert.equal(rpFor("com", "google.com"), false, "a bare suffix");
  assert.equal(rpFor("ogle.com", "google.com"), false);
  assert.equal(rpFor("", "google.com"), false);
  // A device's own client data (macOS writes it its way): taken only where it says what the station's said.
  const ours = JSON.stringify({ type: "webauthn.get", challenge: "AQID", origin: "https://github.com", crossOrigin: false });
  assert.equal(sameClientData('{"challenge":"AQID","crossOrigin":false,"origin":"https://github.com","type":"webauthn.get"}', ours), true);
  assert.equal(sameClientData('{"type":"webauthn.get","challenge":"AQID","origin":"https://evil.example"}', ours), false);
  assert.equal(sameClientData('{"type":"webauthn.get","challenge":"BBBB","origin":"https://github.com"}', ours), false);
  assert.equal(sameClientData('{"type":"webauthn.get","challenge":"AQID","origin":"https://github.com","crossOrigin":true}', ours), false);
  assert.equal(sameClientData("not json", ours), false);
});

test("a site's cookies: its own and its subdomains', set again as DevTools takes them; taken out by setting them expired", () => {
  assert.equal(ofSites(".github.com", ["github.com"]), true);
  assert.equal(ofSites("api.github.com", ["github.com"]), true);
  assert.equal(ofSites("notgithub.com", ["github.com"]), false);
  assert.deepEqual(siteCookies([{ name: "a", value: "1", domain: ".github.com", path: "/", size: 2, session: true, expires: -1, sameSite: "Lax" }, { nope: 1 }], ["github.com"]), [{ name: "a", value: "1", domain: ".github.com", path: "/", sameSite: "Lax" }]);
  assert.deepEqual(expired([{ name: "a", value: "1", domain: "github.com", path: "/" }]), [{ name: "a", value: "", domain: "github.com", path: "/", expires: 1 }]);
});

test("a sign-in as the vault keeps it: its cookies alone (as every one before passkeys), or with its sites' passkeys", () => {
  const cookie = { name: "a", value: "1", domain: "github.com", path: "/" };
  const key = { credentialId: "AQID", rpId: "github.com", privateKey: "MIGHAgEA", userHandle: "BQ", signCount: 2 };
  assert.equal(keptOf({ cookies: [cookie], passkeys: [] }), JSON.stringify([cookie]));
  assert.deepEqual(stateOf(JSON.stringify([cookie])), { cookies: [cookie], passkeys: [] });
  const both = keptOf({ cookies: [cookie], passkeys: [key] });
  assert.deepEqual(JSON.parse(both), { cookies: [cookie], passkeys: [key] });
  assert.deepEqual(stateOf(both), { cookies: [cookie], passkeys: [key] });
  // What is not a passkey is left out; a count not a count is none; nothing readable is nothing.
  assert.deepEqual(stateOf(JSON.stringify({ cookies: [], passkeys: [{ rpId: "x" }, { ...key, signCount: -1, userHandle: "" }] })).passkeys, [{ credentialId: "AQID", rpId: "github.com", privateKey: "MIGHAgEA", signCount: 0 }]);
  assert.deepEqual(stateOf("not json"), { cookies: [], passkeys: [] });
  assert.equal(passkeyOf({ credentialId: "A" }), null);
  // A site's passkeys: its own and its subdomains', as its cookies.
  assert.deepEqual(sitePasskeys([key, { ...key, rpId: "api.github.com" }, { ...key, rpId: "notgithub.com" }], ["github.com"]).map((p) => p.rpId), ["github.com", "api.github.com"]);
});

/// A gate for chat context C1; other targets' contexts as `known` says.
function gate(known: Record<string, string> = {}) {
  const opened: string[] = [];
  const g = new Gate({ context: "C1", contextOf: (id) => known[id], opened: (id) => opened.push(id) });
  const client = (m: object) => g.fromClient(JSON.stringify(m));
  const chrome = (m: object) => {
    const text = JSON.stringify(m);
    return g.wants(text) ? g.fromChrome(text) : { up: [], down: [text] };
  };
  const json = (p: { up: string[]; down: string[] }) => ({ up: p.up.map((x) => JSON.parse(x)), down: p.down.map((x) => JSON.parse(x)) });
  return { g, opened, client: (m: object) => json(client(m)), chrome: (m: object) => json(chrome(m)) };
}

test("browser activity is attributed to its own tab, without treating passive traffic as use", () => {
  const used: [string, string | undefined][] = [];
  const g = new Gate({ context: "C1", contextOf: (id) => id === "A" ? "C1" : "C2", used: (id, url) => used.push([id, url]) });
  g.fromChrome(JSON.stringify({ method: "Target.attachedToTarget", params: { sessionId: "SA", targetInfo: { targetId: "A", browserContextId: "C1" } } }));
  g.fromClient(JSON.stringify({ id: 1, sessionId: "SA", method: "Page.navigate", params: { url: "https://github.com/" } }));
  g.fromChrome(JSON.stringify({ id: 1, sessionId: "SA", result: {} }));
  g.fromClient(JSON.stringify({ id: 2, sessionId: "SA", method: "Input.dispatchMouseEvent", params: { type: "mouseMoved" } }));
  g.fromClient(JSON.stringify({ id: 3, sessionId: "SA", method: "Input.dispatchMouseEvent", params: { type: "mousePressed" } }));
  g.fromChrome(JSON.stringify({ id: 3, sessionId: "SA", result: {} }));
  g.fromClient(JSON.stringify({ id: 4, sessionId: "SX", method: "Page.navigate", params: { url: "https://other/" } }));
  assert.deepEqual(used, [["A", "https://github.com/"], ["A", undefined]]);
});

test("the gate: a new tab, the cookies, the permissions are the chat's context; another context, another chat's target, the browser itself are refused", () => {
  const { client } = gate({ X: "C2", A: "C1" });
  const refused = (id: number, sessionId?: string) => (r: any) => r.up.length === 0 && r.down[0].id === id && r.down[0].error && (sessionId === undefined || r.down[0].sessionId === sessionId);
  assert.deepEqual(client({ id: 1, method: "Target.createTarget", params: { url: "https://a/" } }).up, [{ id: 1, method: "Target.createTarget", params: { url: "https://a/", browserContextId: "C1", newWindow: true, background: true } }]);
  assert.ok(refused(2)(client({ id: 2, method: "Target.createTarget", params: { url: "https://a/", browserContextId: "C2" } })));
  assert.deepEqual(client({ id: 3, method: "Storage.getCookies", params: {} }).up, [{ id: 3, method: "Storage.getCookies", params: { browserContextId: "C1" } }]);
  assert.deepEqual(client({ id: 4, method: "Browser.grantPermissions", params: { permissions: ["geolocation"] } }).up[0].params.browserContextId, "C1");
  assert.ok(refused(5)(client({ id: 5, method: "Storage.getCookies", params: { browserContextId: "C2" } })));
  assert.ok(refused(6)(client({ id: 6, method: "Target.attachToTarget", params: { targetId: "X", flatten: true } })), "another chat's tab");
  assert.equal(client({ id: 7, method: "Target.attachToTarget", params: { targetId: "A", flatten: true } }).up.length, 1, "its own");
  for (const method of ["Browser.close", "Target.attachToBrowserTarget", "Browser.getBrowserCommandLine", "Tracing.start", "SystemInfo.getProcessInfo"]) {
    assert.ok(refused(8)(client({ id: 8, method, params: {} })), method);
  }
  assert.ok(refused(9)(client({ id: 9, method: "Target.disposeBrowserContext", params: { browserContextId: "C1" } })), "its own context stays");
  assert.deepEqual(client({ id: 10, method: "Target.getBrowserContexts" }).down, [{ id: 10, result: { browserContextIds: [], defaultBrowserContextId: "C1" } }], "its context is its default");
  assert.ok(refused(11, "S9")(client({ id: 11, sessionId: "S9", method: "Runtime.evaluate", params: { expression: "1" } })), "a session not its own");
});

test("the gate: what Chrome tells of other chats' targets never reaches the agent; one attached on its own is let go of at once", () => {
  const { client, chrome, opened } = gate({ A: "C1" });
  // News of targets: its own pass, another's do not.
  assert.equal(chrome({ method: "Target.targetCreated", params: { targetInfo: { targetId: "A", browserContextId: "C1", type: "page" } } }).down.length, 1);
  assert.equal(chrome({ method: "Target.targetCreated", params: { targetInfo: { targetId: "X", browserContextId: "C2", type: "page" } } }).down.length, 0);
  assert.equal(chrome({ method: "Target.targetDestroyed", params: { targetId: "X" } }).down.length, 0);
  // Auto-attached to another's: let go of, and nothing of that session passes.
  const other = chrome({ method: "Target.attachedToTarget", params: { sessionId: "SX", targetInfo: { targetId: "X", browserContextId: "C2" }, waitingForDebugger: true } });
  assert.deepEqual(other.down, []);
  assert.deepEqual(other.up.map((m: any) => [m.method, m.params]), [["Target.detachFromTarget", { sessionId: "SX" }]]);
  assert.deepEqual(chrome({ id: other.up[0].id, result: {} }).down, [], "the gate's own answer is its own");
  assert.deepEqual(chrome({ method: "Runtime.executionContextCreated", params: {}, sessionId: "SX" }).down.length, 1, "a page's own events pass unread (none come from a session let go of at once)");
  assert.deepEqual(chrome({ method: "Target.detachedFromTarget", params: { sessionId: "SX" } }).down, []);
  // Auto-attached to its own: its session is the agent's.
  assert.equal(chrome({ method: "Target.attachedToTarget", params: { sessionId: "SA", targetInfo: { targetId: "A2", browserContextId: "C1" } } }).down.length, 1);
  assert.equal(client({ id: 1, sessionId: "SA", method: "Runtime.evaluate", params: { expression: "1" } }).up.length, 1);
  assert.deepEqual(client({ id: 2, sessionId: "SA", method: "Page.bringToFront", params: {} }).down, [{ id: 2, sessionId: "SA", result: {} }]);
  // The targets asked for: only its own listed; a tab it made is its own at once.
  client({ id: 3, method: "Target.getTargets", params: {} });
  assert.deepEqual(chrome({ id: 3, result: { targetInfos: [{ targetId: "A", browserContextId: "C1" }, { targetId: "X", browserContextId: "C2" }] } }).down, [{ id: 3, result: { targetInfos: [{ targetId: "A", browserContextId: "C1" }] } }]);
  client({ id: 4, method: "Target.createTarget", params: { url: "about:blank" } });
  chrome({ id: 4, result: { targetId: "N" } });
  assert.deepEqual(opened, ["N"]);
  assert.equal(client({ id: 5, method: "Target.closeTarget", params: { targetId: "N" } }).up.length, 1);
  // From a page's session too: the targets it lists are its chat's only, the cookies its context's.
  client({ id: 6, sessionId: "SA", method: "Target.getTargets", params: {} });
  assert.deepEqual(chrome({ id: 6, sessionId: "SA", result: { targetInfos: [{ targetId: "X", browserContextId: "C2" }] } }).down, [{ id: 6, sessionId: "SA", result: { targetInfos: [] } }]);
  assert.equal(client({ id: 7, sessionId: "SA", method: "Storage.getCookies", params: {} }).up[0].params.browserContextId, "C1");
});
