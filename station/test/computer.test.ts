// The agents' computer tool (docs/remote-screens.md, "Agents on a screen") on a fake screen source: screenshots and
// how their pixels map to the contract's 0..1, each action's input events, one view per session and screen closed when
// idle, a person driving the screen holding the agent off, a missing grant answered with the person's link, and the
// screenshot as MCP image content. Time is the test's own (FakeTimers).
import assert from "node:assert/strict";
import { test } from "node:test";
import { ScreenHub, ScreenRefused } from "../src/screens/hub.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "../src/screens/source.ts";
import { Computer, FIRST_MS, IDLE_MS, SETTLE_MS, type Timers, computerTools, keyPresses, toUnit, typing } from "../src/tools/computer.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";

class FakeTimers implements Timers {
  now = 0;
  #due: { at: number; f: () => void; live: boolean }[] = [];
  later(ms: number, f: () => void) {
    const t = { at: this.now + ms, f, live: true };
    this.#due.push(t);
    return () => void (t.live = false);
  }
  advance(ms: number) {
    const end = this.now + ms;
    for (;;) {
      const next = this.#due.filter((t) => t.live && t.at <= end).sort((a, b) => a.at - b.at)[0];
      if (next === undefined) break;
      this.now = next.at;
      next.live = false;
      next.f();
    }
    this.now = end;
  }
}

const flush = async () => {
  for (let i = 0; i < 10; i++) await new Promise((resolve) => setImmediate(resolve));
};

/// A JPEG-ish picture: what a frame carries is passed through as it is.
const picture = (n: number) => new Uint8Array([0xff, 0xd8, n, 0xff, 0xd9]);

/// A view whose frames the test gives (`show`), recording the input it is sent.
class FakeView implements ScreenView {
  inputs: ScreenInput[] = [];
  closed = false;
  #queue: Frame[] = [];
  #waiter: ((f: Frame | null) => void) | null = null;
  #ts = 0;
  #sized = "";
  show(n: number, size = { width: 640, height: 360 }) {
    const key = `${size.width}x${size.height}`;
    const config = key !== this.#sized ? { config: { codec: "jpeg" as const, ...size } } : {};
    this.#sized = key;
    const frame: Frame = { ...config, key: true, ts: ++this.#ts, data: picture(n) };
    if (this.#waiter) {
      const w = this.#waiter;
      this.#waiter = null;
      w(frame);
    } else this.#queue.push(frame);
  }
  next(): Promise<Frame | null> {
    if (this.closed) return Promise.resolve(null);
    const f = this.#queue.shift();
    if (f) return Promise.resolve(f);
    return new Promise((resolve) => (this.#waiter = resolve));
  }
  keyframe() {}
  async input(event: ScreenInput) {
    this.inputs.push(event);
  }
  close() {
    this.closed = true;
    const w = this.#waiter;
    this.#waiter = null;
    w?.(null);
  }
  /// The source went away.
  end() {
    this.close();
  }
}

class FakeSource implements ScreenSource {
  readonly kind: "browser" | "desktop";
  readonly id: string;
  views: FakeView[] = [];
  opened: ViewOptions[] = [];
  refuse: Error | null = null;
  granted: ScreenAccess | null = null;
  /// The first picture a view shows as it opens (none: it shows nothing yet).
  first: number | null = 1;
  constructor(id = "browser:T1", kind: "browser" | "desktop" = "browser") {
    this.id = id;
    this.kind = kind;
  }
  title() {
    return "Docs";
  }
  size() {
    return { width: 1280, height: 720 };
  }
  access?(): ScreenAccess;
  async open(options: ViewOptions): Promise<ScreenView> {
    this.opened.push(options);
    if (this.refuse) throw this.refuse;
    const view = new FakeView();
    if (this.first !== null) view.show(this.first);
    this.views.push(view);
    return view;
  }
}

function setup(source = new FakeSource()) {
  const hub = new ScreenHub();
  hub.add(source);
  const timers = new FakeTimers();
  const computer = new Computer({ hub, base: () => "https://still.fail/w/W/s/S", name: (s) => `agent: Chat ${s}`, timers });
  return { hub, timers, computer, source };
}

const text = (r: { content: { type: string; text?: string }[] }) => r.content.filter((c) => c.type === "text").map((c) => c.text).join("\n");
const pointer = (kind: string, x: number, y: number, buttons: number) => ({ t: "pointer", kind, x, y, buttons });

test("a screenshot: the view's newest frame, its size and its scale to the screen; asked as JPEG within 1280", async () => {
  const { computer, source } = setup();
  const r = await computer.act("s1", { screen: "browser:T1" });
  assert.deepEqual(source.opened, [{ maxWidth: 1280, maxHeight: 1280, codecs: ["jpeg"] }]);
  assert.deepEqual(r.content[1], { type: "image", data: Buffer.from(picture(1)).toString("base64"), mimeType: "image/jpeg" });
  assert.match(text(r), /browser:T1 "Docs": screenshot 640×360 px \(scale 2: 1 screenshot px = 2 screen px\)\. Give x\/y in this screenshot's pixels\./);
  // A newer frame came (the screen changed): the next screenshot is it.
  source.views[0]!.show(2);
  await flush();
  assert.deepEqual((await computer.act("s1", { screen: "browser:T1", action: "screenshot" })).content[1], { type: "image", data: Buffer.from(picture(2)).toString("base64"), mimeType: "image/jpeg" });
  assert.equal(source.opened.length, 1, "the same view");
});

test("coordinates: screenshot pixels → 0..1 of the frame, at any scale", async () => {
  assert.deepEqual(toUnit({ x: 320, y: 90 }, { width: 640, height: 360 }), { x: 0.5, y: 0.25 });
  assert.deepEqual(toUnit({ x: 640, y: 360 }, { width: 640, height: 360 }), { x: 1, y: 1 });
  const { computer, source } = setup();
  await computer.act("s1", { screen: "browser:T1", action: "click", x: 160, y: 270, wait: 0 });
  assert.deepEqual(source.views[0]!.inputs, [pointer("move", 0.25, 0.75, 0), pointer("down", 0.25, 0.75, 1), pointer("up", 0.25, 0.75, 0)]);
  // The screen's frames got bigger: the same point is now elsewhere in 0..1.
  source.views[0]!.show(2, { width: 1280, height: 720 });
  await flush();
  source.views[0]!.inputs = [];
  await computer.act("s1", { screen: "browser:T1", action: "move", x: 160, y: 270, screenshot: false });
  assert.deepEqual(source.views[0]!.inputs, [pointer("move", 0.125, 0.375, 0)]);
  await assert.rejects(computer.act("s1", { screen: "browser:T1", action: "click", x: 1281, y: 10 }), /outside the screenshot \(1280×720\)/);
  await assert.rejects(computer.act("s1", { screen: "browser:T1", action: "click", x: "a" }), /needs numbers x and y/);
});

test("each action's input: clicks, double and right clicks, drags, scrolls, keys and combinations, text", async () => {
  const { computer, source } = setup();
  const act = async (args: Record<string, unknown>) => {
    await computer.act("s1", { screen: "browser:T1", screenshot: false, ...args });
    const view = source.views[0]!;
    const got = view.inputs;
    view.inputs = [];
    return got;
  };
  assert.deepEqual(await act({ action: "click", x: 64, y: 36, double: true }), [
    pointer("move", 0.1, 0.1, 0), pointer("down", 0.1, 0.1, 1), pointer("up", 0.1, 0.1, 0), pointer("down", 0.1, 0.1, 1), pointer("up", 0.1, 0.1, 0),
  ]);
  assert.deepEqual(await act({ action: "click", x: 64, y: 36, button: "right" }), [pointer("move", 0.1, 0.1, 0), pointer("down", 0.1, 0.1, 2), pointer("up", 0.1, 0.1, 0)]);
  const drag = await act({ action: "drag", from: [0, 0], to: [320, 180] });
  assert.deepEqual(drag.slice(0, 2), [pointer("move", 0, 0, 0), pointer("down", 0, 0, 1)]);
  assert.deepEqual(drag.slice(2, -1).map((e: any) => [e.kind, e.buttons]), Array(8).fill(["move", 1]));
  assert.deepEqual(drag.at(-2), pointer("move", 0.5, 0.5, 1));
  assert.deepEqual(drag.at(-1), pointer("up", 0.5, 0.5, 0));
  assert.deepEqual(await act({ action: "scroll", x: 320, y: 180, dy: 400 }), [pointer("move", 0.5, 0.5, 0), { t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 400 }]);
  assert.deepEqual(await act({ action: "key", key: "cmd+c" }), [
    { t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 },
    { t: "key", kind: "down", key: "c", code: "KeyC", mods: 4 },
    { t: "key", kind: "up", key: "c", code: "KeyC", mods: 4 },
    { t: "key", kind: "up", key: "Meta", code: "MetaLeft", mods: 0 },
  ]);
  assert.deepEqual(await act({ action: "key", key: "Enter" }), [{ t: "key", kind: "down", key: "Enter", code: "Enter", mods: 0 }, { t: "key", kind: "up", key: "Enter", code: "Enter", mods: 0 }]);
  assert.deepEqual(await act({ action: "type", text: "hi\nthere" }), [{ t: "text", text: "hi" }, ...keyPresses("Enter"), { t: "text", text: "there" }]);
  // Combinations as agents write them.
  const keys = (combo: string, mods?: string[]) => keyPresses(combo, mods).map((e) => `${e.kind} ${e.key}/${e.code} ${e.mods}`);
  assert.deepEqual(keys("ctrl+shift+t"), ["down Control/ControlLeft 2", "down Shift/ShiftLeft 10", "down T/KeyT 10", "up T/KeyT 10", "up Shift/ShiftLeft 2", "up Control/ControlLeft 0"]);
  assert.deepEqual(keys("Left", ["alt"]), ["down Alt/AltLeft 1", "down ArrowLeft/ArrowLeft 1", "up ArrowLeft/ArrowLeft 1", "up Alt/AltLeft 0"]);
  assert.deepEqual(keys("cmd++"), ["down Meta/MetaLeft 4", "down Shift/ShiftLeft 12", "down +/Equal 12", "up +/Equal 12", "up Shift/ShiftLeft 4", "up Meta/MetaLeft 0"]);
  assert.deepEqual(keys("F5"), ["down F5/F5 0", "up F5/F5 0"]);
  assert.throws(() => keyPresses("hyper+x"), /no modifier/);
  assert.throws(() => keyPresses("Launch"), /unknown key/);
  assert.deepEqual(typing("a\r\nb"), [{ t: "text", text: "a" }, ...keyPresses("Enter"), { t: "text", text: "b" }]);
  await assert.rejects(computer.act("s1", { screen: "browser:T1", action: "fly" }), /unknown action fly/);
  await assert.rejects(computer.act("s1", { action: "screenshot" }), /screen is required: .*browser:T1/);
  await assert.rejects(computer.act("s1", { screen: "desktop" }), /no screen desktop on this station \(it has: browser:T1\)/);
});

test("after an action its screenshot waits for the screen to answer (500 ms, or `wait`); a view's first picture is waited for", async () => {
  const { computer, source, timers } = setup();
  await computer.act("s1", { screen: "browser:T1" });
  const got: { done?: any } = {};
  void computer.act("s1", { screen: "browser:T1", action: "click", x: 10, y: 10 }).then((r) => (got.done = r));
  await flush();
  assert.equal(source.views[0]!.inputs.length, 3, "sent at once");
  assert.equal(Boolean(got.done), false, "the screenshot waits");
  source.views[0]!.show(7);
  timers.advance(SETTLE_MS - 1);
  await flush();
  assert.equal(Boolean(got.done), false);
  timers.advance(1);
  await flush();
  assert.match(text(got.done), /^Clicked at \(10, 10\)\./);
  assert.equal(got.done.content[1].data, Buffer.from(picture(7)).toString("base64"));
  // A screen showing nothing yet: its first picture, when it comes; none in FIRST_MS is said so.
  const blank = new FakeSource("browser:T2");
  blank.first = null;
  const { computer: c2 } = setup(blank);
  let first = null as any;
  void c2.act("s1", { screen: "browser:T2" }).then((r) => (first = r));
  await flush();
  blank.views[0]!.show(3);
  await flush();
  assert.equal(first.content[1].data, Buffer.from(picture(3)).toString("base64"));
  const late = new FakeSource("browser:T3");
  late.first = null;
  const { computer: c3, timers: t3 } = setup(late);
  const failed = assert.rejects(c3.act("s1", { screen: "browser:T3" }), /showed nothing within 10 s/);
  await flush();
  t3.advance(FIRST_MS);
  await failed;
});

test("one view per session and screen, among the screen's people as the agent, closed after a minute unused", async () => {
  const { computer, source, timers, hub } = setup();
  await computer.act("s1", { screen: "browser:T1" });
  timers.advance(IDLE_MS - 1);
  await computer.act("s1", { screen: "browser:T1", action: "click", x: 1, y: 1, wait: 0 });
  assert.equal(source.views.length, 1, "reused, its idle time from the last use");
  timers.advance(1000);
  await computer.act("s2", { screen: "browser:T1" });
  assert.equal(source.views.length, 2, "another session's own");
  assert.deepEqual(hub.people("browser:T1"), { viewers: ["agent: Chat s1", "agent: Chat s2"], controlledBy: ["agent: Chat s1", "agent: Chat s2"] });
  assert.deepEqual(computer.open(), ["s1 browser:T1", "s2 browser:T1"]);
  timers.advance(IDLE_MS - 1001);
  assert.deepEqual([source.views[0]!.closed, source.views[1]!.closed], [false, false]);
  timers.advance(1);
  assert.deepEqual([source.views[0]!.closed, source.views[1]!.closed], [true, false]);
  assert.deepEqual(hub.people("browser:T1").controlledBy, ["agent: Chat s2"]);
  // Used again: a new view.
  await computer.act("s1", { screen: "browser:T1" });
  assert.equal(source.views.length, 3);
  // The chat archived: its views close; the station stopping: all do.
  computer.closeSession("s1");
  assert.equal(source.views[2]!.closed, true);
  hub.close();
  assert.equal(source.views[1]!.closed, true);
  assert.deepEqual(hub.people("browser:T1"), { viewers: [], controlledBy: [] });
  // A view whose source ended is opened again on the next call.
  await computer.act("s3", { screen: "browser:T1" });
  source.views[3]!.end();
  await flush();
  assert.deepEqual(computer.open(), []);
  await computer.act("s3", { screen: "browser:T1" });
  assert.equal(source.views.length, 5);
});

test("a person driving the screen holds the agent's input off (screenshots go on); watchers and other agents do not", async () => {
  const { computer, source, hub } = setup();
  await computer.act("s1", { screen: "browser:T1" });
  const watching = hub.join("browser:T1", { name: "Vic", control: false, tell: () => {} });
  await computer.act("s1", { screen: "browser:T1", action: "click", x: 1, y: 1, wait: 0 });
  await computer.act("s2", { screen: "browser:T1", action: "click", x: 2, y: 2, wait: 0 });
  const pat = hub.join("browser:T1", { name: "Pat", control: true, tell: () => {} });
  source.views[0]!.inputs = [];
  await assert.rejects(computer.act("s1", { screen: "browser:T1", action: "type", text: "x" }), /Pat is controlling browser:T1 right now, so your input was not sent: do not fight them\. Wait .* or ask them/);
  assert.deepEqual(source.views[0]!.inputs, []);
  const shot = await computer.act("s1", { screen: "browser:T1" });
  assert.match(text(shot), /Also on this screen: Vic, agent: Chat s2, Pat\./);
  pat();
  watching();
  await computer.act("s1", { screen: "browser:T1", action: "type", text: "x", screenshot: false });
  assert.deepEqual(source.views[0]!.inputs, [{ t: "text", text: "x" }]);
});

test("a missing grant: the access message and the screen's link for a person; no Accessibility refuses input only", async () => {
  const desktop = new FakeSource("desktop", "desktop");
  const access: ScreenAccess = { capture: false, control: false, app: "still.fail Helper", path: "/Applications/still.fail Helper.app" };
  desktop.access = () => access;
  desktop.refuse = new ScreenRefused(503, "station.screen.captureOff", { app: access.app, path: access.path }, access);
  const { computer } = setup(desktop);
  await assert.rejects(
    computer.act("s1", { screen: "desktop" }),
    (e: Error) =>
      /This Mac hasn't let still\.fail Helper record its screen or control it yet/.test(e.message) &&
      e.message.includes("https://still.fail/w/W/s/S/screen/desktop") &&
      /chat_post kind=need_human/.test(e.message),
  );
  // Seen but not driven.
  desktop.refuse = null;
  access.capture = true;
  await computer.act("s1", { screen: "desktop" });
  await assert.rejects(computer.act("s1", { screen: "desktop", action: "click", x: 1, y: 1 }), (e: Error) => /hasn't allowed still\.fail Helper to control it yet \(Accessibility\)/.test(e.message) && /input was not sent/.test(e.message) && e.message.includes("/screen/desktop"));
  assert.deepEqual(desktop.views[0]!.inputs, []);
  // A source sending no JPEG (a desktop before its helper did).
  const old = new FakeSource("desktop", "desktop");
  old.refuse = new ScreenRefused(415, "station.screen.codec", { codec: "H.264" });
  await assert.rejects(setup(old).computer.act("s1", { screen: "desktop" }), /sends no JPEG\): update the station/);
});

test("over MCP: the screenshot is image content beside its text; refusals are tool errors", async () => {
  const { computer } = setup();
  const mcp = new McpEndpoint((t) => (t === "tok" ? "s1" : undefined), computerTools(computer));
  const call = async (args: Record<string, unknown>) =>
    ((await mcp.handle("POST", "Bearer tok", JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "computer", arguments: args } }))).body as any).result;
  const shot = await call({ screen: "browser:T1" });
  assert.equal(shot.isError, undefined);
  assert.deepEqual(shot.content.map((c: any) => c.type), ["text", "image"]);
  assert.deepEqual([shot.content[1].mimeType, Buffer.from(shot.content[1].data, "base64")], ["image/jpeg", Buffer.from(picture(1))]);
  const refused = await call({ screen: "nope" });
  assert.deepEqual([refused.isError, refused.content[0].text], [true, "no screen nope on this station (it has: browser:T1)"]);
  // `run`: the text alone.
  assert.match(await computerTools(computer)[0]!.run("s1", { screen: "browser:T1" }), /screenshot 640×360 px[\s\S]*\[image\/jpeg screenshot\]/);
});

/// A desktop whose apps answer as agent-desktop does: its commands recorded, its answers the test's.
class TreeDesktop extends FakeSource {
  commands: string[][] = [];
  answers: unknown[] = [];
  constructor() {
    super("desktop", "desktop");
  }
  async ui(args: string[]): Promise<unknown> {
    this.commands.push(args);
    return this.answers.shift() ?? { ok: true, data: {} };
  }
}

const calculator = (snapshot: string, shown: string) => ({
  ok: true,
  data: {
    app: "Calculator",
    snapshot_id: snapshot,
    window: { id: "w-44", title: "Calculator" },
    complete: true,
    tree: {
      role: "window",
      name: "Calculator",
      children: [
        { role: "group", children: [{ role: "scrollarea", name: "Edit field", ref_id: `@${snapshot}:e1`, children: [{ role: "statictext", name: shown, value: shown }] }] },
        { role: "button", name: "7", ref_id: `@${snapshot}:e2`, available_actions: ["Click"] },
        { role: "button", name: "Zoom", ref_id: `@${snapshot}:e3`, states: ["disabled"] },
      ],
    },
  },
});

test("on the desktop, an app's tree as text, a line an element with its ref; no app: the apps running", async () => {
  const desktop = new TreeDesktop();
  const { computer } = setup(desktop);
  desktop.answers.push({ ok: true, data: { apps: [{ name: "Finder", presentation: "foreground" }, { name: "Dock", presentation: "background" }, { name: "imagent" }, { name: "Calculator", presentation: "foreground" }] } });
  assert.equal(text(await computer.act("s1", { screen: "desktop", action: "tree" })), "Apps running (give one as app with action=tree): Finder, Calculator");
  desktop.answers.push(calculator("s1", "0"));
  const tree = await computer.act("s1", { screen: "desktop", action: "tree", app: "Calculator" });
  assert.equal(
    text(tree),
    ['Calculator window w-44 "Calculator". Act on an element by its ref (ref: "e12").', 'window "Calculator"', '  e1 scrollarea "Edit field"', '    statictext "0"', '  e2 button "7"', '  e3 button "Zoom" [disabled]'].join("\n"),
  );
  assert.deepEqual(desktop.commands, [["list-apps"], ["snapshot", "--compact", "--app", "Calculator"]]);
  // Nothing was opened: no picture, no view.
  assert.deepEqual(desktop.opened, []);
  // A part of it, and a big window's outline.
  desktop.answers.push(calculator("s2", "0"), calculator("s3", "0"));
  await computer.act("s1", { screen: "desktop", action: "tree", ref: "e1" });
  await computer.act("s1", { screen: "desktop", action: "tree", app: "Calculator", skeleton: true });
  assert.deepEqual(desktop.commands.slice(2), [
    ["snapshot", "--compact", "--app", "Calculator", "--window-id", "w-44", "--root", "@s1:e1"],
    ["snapshot", "--compact", "--app", "Calculator", "--skeleton"],
  ]);
});

test("an action by ref goes to the latest tree's element and answers with the app's tree again; while a person drives the screen too", async () => {
  const desktop = new TreeDesktop();
  const { computer, hub, timers } = setup(desktop);
  await assert.rejects(computer.act("s1", { screen: "desktop", action: "click", ref: "e2" }), /no tree read yet on desktop: call action=tree with app first/);
  desktop.answers.push(calculator("s1", "0"));
  await computer.act("s1", { screen: "desktop", action: "tree", app: "Calculator" });
  const pat = hub.join("desktop", { name: "Pat", control: true, tell: () => {} });
  desktop.answers.push({ ok: true, data: { action: "click" } }, calculator("s2", "7"));
  const clicked = computer.act("s1", { screen: "desktop", action: "click", ref: "e2" });
  await flush();
  // The tree is read again once the app had a moment to answer.
  assert.equal(desktop.commands.length, 2);
  timers.advance(200);
  assert.match(text(await clicked), /^Clicked e2\.\nCalculator window w-44[^\n]*\nwindow "Calculator"\n  e1 scrollarea "Edit field"\n    statictext "7"/);
  assert.deepEqual(desktop.commands.slice(1), [["click", "@s1:e2"], ["snapshot", "--compact", "--app", "Calculator", "--window-id", "w-44"]]);
  pat();
  // The refs now are the new tree's.
  desktop.answers.push({ ok: true, data: {} }, calculator("s3", "7"), { ok: true, data: {} }, calculator("s4", "7"), { ok: true, data: {} }, calculator("s5", "7"), { ok: true, data: {} }, calculator("s6", "7"), { ok: true, data: {} });
  await computer.act("s1", { screen: "desktop", action: "type", ref: "e1", text: "12", wait: 0 });
  await computer.act("s1", { screen: "desktop", action: "set", ref: "e1", text: "", wait: 0 });
  await computer.act("s1", { screen: "desktop", action: "scroll", ref: "e1", dy: 250, wait: 0 });
  await computer.act("s1", { screen: "desktop", action: "click", ref: "e2", button: "right", wait: 0 });
  await computer.act("s1", { screen: "desktop", action: "key", app: "Calculator", key: "Enter", mods: ["cmd"], tree: false });
  assert.deepEqual(
    desktop.commands.slice(3).filter((c) => c[0] !== "snapshot"),
    [["type", "@s2:e1", "12"], ["set-value", "@s3:e1", ""], ["scroll", "@s4:e1", "--direction", "down", "--amount", "3"], ["right-click", "@s5:e2"], ["press", "cmd+Enter", "--app", "Calculator"]],
  );
  // Another session's refs are its own.
  await assert.rejects(computer.act("s2", { screen: "desktop", action: "click", ref: "e2" }), /no tree read yet/);
});

test("by ref: agent-desktop's refusal as the agent reads it, whether it may be tried again; a screen without trees says so", async () => {
  const desktop = new TreeDesktop();
  const { computer } = setup(desktop);
  desktop.answers.push(calculator("s1", "0"), { ok: false, error: { code: "STALE_REF", message: "The element is gone", suggestion: "Take a new snapshot and use its refs.", disposition: { delivery: "not_delivered", retry: "safe" } } });
  await computer.act("s1", { screen: "desktop", action: "tree", app: "Calculator" });
  await assert.rejects(computer.act("s1", { screen: "desktop", action: "click", ref: "e2" }), (e: Error) => e.message === "click: STALE_REF: The element is gone\nTake a new snapshot and use its refs.\nIt was not done; it is safe to try again.");
  desktop.answers.push({ ok: false, error: { code: "AMBIGUOUS_TARGET", message: "2 windows", details: { windows: ["w-1", "w-2"] } } });
  await assert.rejects(computer.act("s1", { screen: "desktop", action: "tree", app: "Finder" }), /tree: AMBIGUOUS_TARGET: 2 windows\nDetails: \{"windows":\["w-1","w-2"\]\}/);
  // Not driven (no Accessibility): the person's link.
  desktop.access = () => ({ capture: true, control: false, app: "still.fail Helper" });
  await assert.rejects(computer.act("s1", { screen: "desktop", action: "tree", app: "Calculator" }), (e: Error) => /control it yet \(Accessibility\)/.test(e.message) && e.message.includes("/screen/desktop"));
  await assert.rejects(setup().computer.act("s1", { screen: "browser:T1", action: "tree", app: "Calculator" }), /The screen browser:T1 has no accessibility trees: use screenshots/);
});
