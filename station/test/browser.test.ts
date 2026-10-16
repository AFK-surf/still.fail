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
import type { Cdp, CdpEvent } from "../src/browser/cdp.ts";
import { type ChromeHost, type Running, chromeArgs, headfulAgent, parseActivePort, readState } from "../src/browser/chrome.ts";
import { Tabs } from "../src/browser/tabs.ts";
import { TabView, jpegSize, keyCode, keyEvent, toViewport } from "../src/browser/view.ts";
import { makeScreens } from "../src/screens/source.ts";
import { browserTools, howTo } from "../src/tools/browser.ts";

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
  for (const a of headful) assert.doesNotMatch(a, /enable-automation|remote-debugging-pipe|headless|user-agent|use-mock-keychain|password-store/);
  const headless = chromeArgs({ profile: "/p", port: 9333, headless: true, userAgent: "UA" });
  assert.ok(headless.includes("--headless=new") && headless.includes("--remote-debugging-port=9333") && headless.includes("--user-agent=UA"));
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

test("a tab behind another is brought to the front when a view opens on it", async () => {
  const cdp = new FakeCdp();
  cdp.answers["Runtime.evaluate"] = () => ({ result: { value: "hidden" } });
  const v = new TabView({ cdp, session: "S", targetId: "T", now: () => 0 });
  await v.start({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] }, { width: 10, height: 10 });
  assert.deepEqual(cdp.of("Target.activateTarget")[0]!.params, { targetId: "T" });
});

/// Tabs over a fake browser connection, into a registry; each view's connection a new fake.
async function tabs() {
  const cdp = new FakeCdp();
  const screens = makeScreens();
  const lists: string[][] = [];
  screens.watch((all) => lists.push(all.map((s) => `${s.id} ${s.title()}`)));
  let used = 0;
  const views: FakeCdp[] = [];
  const timers: { ms: number; f: () => void }[] = [];
  const t = new Tabs({
    cdp, screens, now: () => 0, activity: () => used++,
    later: (ms, f) => {
      const timer = { ms, f };
      timers.push(timer);
      return () => timers.splice(timers.indexOf(timer) >>> 0, 1);
    },
    connect: async () => {
      const c = new FakeCdp();
      c.answers["Target.attachToTarget"] = () => ({ sessionId: `V${views.length}` });
      c.answers["Runtime.evaluate"] = () => ({ result: { value: "visible" } });
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
  return { cdp, screens, lists, t, views, timers, used: () => used };
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
  const v = await tab.open({ maxWidth: 100, maxHeight: 100, codecs: ["jpeg"] });
  assert.equal(views.length, 1);
  assert.deepEqual(views[0]!.of("Target.attachToTarget")[0]!.params, { targetId: "A", flatten: true });
  assert.equal(cdp.of("Target.attachToTarget").length, 0, "not on the browser's own connection");
  assert.equal(t.viewing(), 1);
  v.close();
  assert.equal(t.viewing(), 0);
});

/// A Chrome of the test's making: started, found, killed, each a connection the test can end (the browser dying).
function fakeChrome() {
  const made: FakeCdp[] = [];
  const calls: string[] = [];
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
      made.push(c);
      return c;
    },
  };
  return { host, made, calls, leave: (r: Running | null) => (left = r) };
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
  const text = howTo(a);
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
  assert.equal(chrome.made.length, connected + 1);
  assert.equal(next.status().running, true);
  assert.deepEqual(screens.list().map((s) => s.id), ["browser:A"]);
  assert.equal((await next.endpoint()).ws, r.ws, "the same browser");
  assert.equal(chrome.calls.filter((x) => x === "launch").length, 1);
  await next.close();
});

test("the browser tool: endpoint by default, tabs, status, stop", async () => {
  const chrome = fakeChrome();
  const { clock: c } = clock();
  const b = new StationBrowser({ later: () => () => {}, dir: scratch(), chrome: chrome.host, clock: c });
  const [tool] = browserTools(b);
  assert.equal(tool!.name, "browser");
  assert.equal((tool!.inputSchema as any).type, "object");
  assert.match(await tool!.run("s", { action: "status" }), /Not running/);
  assert.match(await tool!.run("s", {}), /DevTools: http:\/\/127\.0\.0\.1:9300/);
  chrome.made[0]!.emit("Target.targetCreated", { targetInfo: { targetId: "A", type: "page", title: "Docs", url: "https://docs/" } });
  assert.match(await tool!.run("s", { action: "tabs" }), /A "Docs" https:\/\/docs\//);
  assert.match(await tool!.run("s", { action: "status" }), /Running: http:\/\/127\.0\.0\.1:9300.*1 tab/);
  assert.match(await tool!.run("s", { action: "stop" }), /closed/);
  assert.equal(b.status().running, false);
  await assert.rejects(tool!.run("s", { action: "nope" }), /unknown action/);
  await b.close();
});
