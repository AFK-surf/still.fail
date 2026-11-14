// A chat's Farview (src/browser/farview.ts) without Farview: the switch read from config.json, what a host writes once it
// listens, a view's pictures and input over a frame port served here (pictures only as the host says one changed), and
// the `browser` tool giving Farview where the switch is on and Chrome where it is not. A real host is not run here.
import assert from "node:assert/strict";
import { createServer, type Socket } from "node:net";
import { test } from "node:test";
import { chatDir, farviewConfig, farviewHowTo, hostFileOf, type FarviewTabs } from "../src/browser/farview.ts";
import { DEFAULT_SIZE, FarviewScreen, FrameLink, inputOf, sizeFor } from "../src/browser/farview-screen.ts";
import { decodeAnswer, encodeAsk } from "../src/browser/farview-agent.ts";
import { browserTools, type ToolBrowsers } from "../src/browser/tool.ts";

test("Farview is the chats' browser only where config.json names it with where it is", () => {
  assert.equal(farviewConfig({}), null);
  assert.equal(farviewConfig({ browser: { engine: "chrome" } }), null);
  assert.equal(farviewConfig({ browser: { engine: "farview" } }), null);
  assert.deepEqual(farviewConfig({ browser: { engine: "farview", farview: "/opt/fv" } }), { dir: "/opt/fv", host: "/opt/fv/bin/host.exe", agent: "/opt/fv/bin/agent.exe" });
});

test("a host's file is taken only with its process and three ports", () => {
  assert.deepEqual(hostFileOf({ pid: 12, port: 4000, agent: 4001, frame: 4002 }), { pid: 12, port: 4000, agent: 4001, frame: 4002 });
  assert.equal(hostFileOf({ pid: 12, port: 4000, agent: 4001 }), null);
  assert.equal(hostFileOf({ pid: 0, port: 4000, agent: 4001, frame: 4002 }), null);
  assert.equal(hostFileOf({ pid: 12, port: 70000, agent: 4001, frame: 4002 }), null);
  assert.equal(hostFileOf("x"), null);
});

test("a chat's directory is named by its session, not as it", () => {
  assert.match(chatDir("chat:c-1/2"), /^[0-9a-f]{24}$/);
  assert.notEqual(chatDir("chat:a"), chatDir("chat:b"));
});

test("a view lays the tab out for its viewer's screen, else within its bounds", () => {
  assert.deepEqual(sizeFor({ maxWidth: 4000, maxHeight: 4000, codecs: ["jpeg"] }), DEFAULT_SIZE);
  assert.deepEqual(sizeFor({ maxWidth: 640, maxHeight: 800, codecs: ["jpeg"] }), { width: 1280, height: 800, scale: 0.5 });
  assert.deepEqual(sizeFor({ maxWidth: 4000, maxHeight: 4000, codecs: ["jpeg"], fit: { width: 412, height: 915, scale: 2.6 } }), { width: 412, height: 915, scale: 2.6 });
});

test("a person's pointer reaches the host in the pictures' pixels, the wheel in CSS pixels", () => {
  const size = { width: 400, height: 800, scale: 2 };
  assert.deepEqual(inputOf({ t: "pointer", kind: "down", x: 0.5, y: 0.25, buttons: 1 }, size), { pointer: { type: "down", x: 400, y: 400, button: 0, buttons: 1 } });
  assert.deepEqual(inputOf({ t: "wheel", x: 0, y: 1, dx: 0, dy: 120 }, size), { wheel: { x: 0, y: 800, dx: 0, dy: 120 } });
  assert.deepEqual(inputOf({ t: "key", kind: "down", key: "Enter", code: "Enter", mods: 8 }, size), { key: { type: "down", key: "Enter", code: "Enter", mods: 8 } });
  assert.deepEqual(inputOf({ t: "text", text: "你好" }, size), { text: "你好" });
  assert.equal(inputOf({ t: "pose", name: "open" }, size), null);
});

/// A frame port: every line a connection sends is heard; a picture asked for is answered with `picture`.
async function framePort(picture: Buffer) {
  const heard: any[] = [];
  const sockets: Socket[] = [];
  const server = createServer((s) => {
    sockets.push(s);
    let buf = "";
    s.on("data", (d) => {
      buf += d.toString("latin1");
      let nl;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const m = JSON.parse(buf.slice(0, nl));
        buf = buf.slice(nl + 1);
        heard.push(m);
        if (m.frame) {
          s.write(`${JSON.stringify({ frame: { seq: 3, width: 640, height: 450, format: "jpeg", bytes: picture.length } })}\n`);
          // the bytes in two pieces, the line after them in the same write as the second
          s.write(picture.subarray(0, 2));
          s.write(Buffer.concat([picture.subarray(2), Buffer.from(`${JSON.stringify({ page: { url: "https://a.test/", title: "A" } })}\n`)]));
        }
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;
  const said = (m: object) => {
    for (const s of sockets) s.write(`${JSON.stringify(m)}\n`);
  };
  const close = () => {
    for (const s of sockets) s.destroy();
    server.close();
  };
  return { port, heard, said, close, sockets };
}

/// Until `f` holds, turning the loop (what the sockets carry comes in its own time).
async function until(f: () => boolean) {
  for (let i = 0; i < 2000 && !f(); i++) await new Promise((r) => setImmediate(r));
  assert.ok(f(), "it did not come");
}

test("a picture's bytes are read whole after the line that says them, and the lines after them heard", async () => {
  const picture = Buffer.from([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);
  const port = await framePort(picture);
  const link = new FrameLink(port.port);
  const heard: any[] = [];
  link.heard = (m) => heard.push(m);
  const got = await link.picture();
  assert.deepEqual(got?.data, picture);
  assert.equal(got?.header.seq, 3);
  await until(() => heard.length > 0);
  assert.deepEqual(heard[0], { page: { url: "https://a.test/", title: "A" } });
  link.close();
  assert.equal(await link.picture(), null);
  port.close();
});

test("a view sends its size, a picture first and then only once the host says the tab changed; its input goes to the host", async () => {
  const picture = Buffer.from([0xff, 0xd8, 9, 0xff, 0xd9]);
  const port = await framePort(picture);
  const screen = new FarviewScreen({ session: "chat:c-1", port: port.port });
  assert.match(screen.id, /^browser:fv_[0-9a-f]{24}$/);
  assert.equal(screen.openedBy(), "chat:c-1");
  const view = await screen.open({ maxWidth: 4000, maxHeight: 4000, codecs: ["jpeg"], fit: { width: 400, height: 800, scale: 2 } });
  assert.equal(screen.viewing(), 1);
  const first = await view.next();
  assert.deepEqual(first?.config, { codec: "jpeg", width: 640, height: 450 });
  assert.deepEqual(first?.data, picture);
  assert.deepEqual(port.heard[0], { size: { width: 400, height: 800, scale: 2 } });
  await until(() => screen.page().url === "https://a.test/");
  assert.equal(screen.title(), "A");
  assert.equal(screen.site(), "a.test");
  // nothing changed: no picture is asked for until the host says one
  let second: unknown = undefined;
  const asking = view.next().then((f) => (second = f));
  await until(() => port.heard.length >= 2);
  assert.equal(port.heard.filter((m) => m.frame).length, 1);
  assert.equal(second, undefined);
  port.said({ changed: 4 });
  await asking;
  assert.equal(port.heard.filter((m) => m.frame).length, 2);
  assert.equal((second as any).config, undefined);
  await view.input({ t: "pointer", kind: "down", x: 0.5, y: 0.5, buttons: 1 });
  await until(() => port.heard.some((m) => m.pointer));
  assert.deepEqual(port.heard.find((m) => m.pointer), { pointer: { type: "down", x: 400, y: 800, button: 0, buttons: 1 } });
  // the host tells the tab's viewport (no scale): the view's pictures, and so its pointer, keep its own 2x
  port.said({ size: { width: 400, height: 800 } });
  await until(() => port.heard.length > 0);
  await new Promise((r) => setImmediate(r));
  await view.input({ t: "pointer", kind: "up", x: 0.5, y: 0.5, buttons: 0 });
  await until(() => port.heard.some((m) => m.pointer?.type === "up"));
  assert.deepEqual(port.heard.find((m) => m.pointer?.type === "up"), { pointer: { type: "up", x: 400, y: 800, button: 0, buttons: 0 } });
  view.close();
  assert.equal(await view.next(), null);
  assert.equal(screen.viewing(), 0);
  screen.close();
  port.close();
});

test("a person's paste goes to the tab as typed, and what they copy there reaches their clipboard", async () => {
  const port = await framePort(Buffer.from([0xff, 0xd8, 9, 0xff, 0xd9]));
  const screen = new FarviewScreen({ session: "chat:c-1", port: port.port });
  try {
    assert.deepEqual(screen.clipboard(), ["text"]);
    const view = await screen.open({ maxWidth: 4000, maxHeight: 4000, codecs: ["jpeg"] });
    // (heard once the server took it: the size the view sends first, then the paste, on one connection in order)
    const pasted = new Promise<void>((resolve) => {
      const look = () => (port.heard.some((m) => m.text === "pasted") ? resolve() : setImmediate(look));
      look();
    });
    await view.setClipboard!({ type: "text", text: "pasted" }, true);
    await pasted;
    const copied = new Promise<unknown>((resolve) => view.watchClipboard!((clip) => resolve(clip)));
    await until(() => port.sockets.length > 0);
    port.said({ copied: "copied words" });
    assert.deepEqual(await copied, { type: "text", text: "copied words" });
    view.close();
  } finally {
    screen.close();
    port.close();
  }
});

test("the browser tool gives the chat's Farview where the switch is on, and its Chrome where it is not", async () => {
  const chrome: ToolBrowsers = {
    endpoint: async () => ({ running: true, http: "http://127.0.0.1:9222", ws: "ws://127.0.0.1:9222/devtools/browser/x" }),
    tabs: () => [],
    status: () => ({ running: false }),
    stop: async () => {},
  };
  let on = true;
  const config = { dir: "/opt/fv", host: "/opt/fv/bin/host.exe", agent: "/opt/fv/bin/agent.exe" };
  const started: string[] = [];
  const stopped: string[] = [];
  const farview = {
    active: () => (on ? config : null),
    endpoint: async (s: string) => (started.push(s), { running: true }),
    agentPort: () => 41234,
    tabs: (s: string) => [{ id: "browser:fv_x", title: "A", url: "https://a.test/", attached: false, session: s }],
    status: () => ({ running: true, viewing: 0 }),
    stop: async (s: string) => void stopped.push(s),
  } as unknown as FarviewTabs;
  const [tool] = browserTools(chrome, () => null, farview);
  const told = String(await tool!.run("chat:c-1", {}));
  assert.equal(told, farviewHowTo(config, 41234));
  assert.match(told, /\/opt\/fv\/bin\/agent\.exe 127\.0\.0\.1 41234/);
  assert.deepEqual(started, ["chat:c-1"]);
  assert.match(String(await tool!.run("chat:c-1", { action: "tabs" })), /browser:fv_x "A" https:\/\/a\.test\//);
  await tool!.run("chat:c-1", { action: "stop" });
  assert.deepEqual(stopped, ["chat:c-1"]);
  on = false;
  assert.match(String(await tool!.run("chat:c-1", {})), /DevTools for this chat: http:\/\/127\.0\.0\.1:9222/);
});

test("the station's asks of a Farview tab are its wire's messages, and its answers read", () => {
  // (Farview's src/proto: a 4-byte length, the kind, each string its length and UTF-8 bytes, zigzag varints)
  assert.deepEqual([...encodeAsk({ kind: "look" })], [0, 0, 0, 1, 38]);
  assert.deepEqual([...encodeAsk({ kind: "cookies", verb: "get", arg: "é" })], [0, 0, 0, 8, 70, 6, ...Buffer.from("get"), 4, 0xc3, 0xa9]);
  const body = (kind: number, ...strs: string[]) => {
    const out = [kind * 2];
    for (const s of strs) out.push(Buffer.byteLength(s) * 2, ...Buffer.from(s));
    return Buffer.from(out);
  };
  assert.deepEqual(decodeAnswer(body(33, "[1]")), { kind: "value", value: "[1]" });
  assert.deepEqual(decodeAnswer(body(20, "https://a.test/", "A", "outline")), { kind: "seen", url: "https://a.test/", title: "A", outline: "outline" });
  assert.deepEqual(decodeAnswer(body(21)), { kind: "taken" });
  assert.equal(decodeAnswer(body(12)), null);
});
