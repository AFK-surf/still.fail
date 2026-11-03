import assert from "node:assert/strict";
import { watch } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { LinuxDesktop } from "../src/screens/linux-desktop.ts";
import { ScreenRefused } from "../src/screens/hub.ts";
import { WaylandDesktop } from "../src/screens/linux-portal.ts";
import { graphicalSession } from "../src/screens/linux-session.ts";

test("graphical session metadata identifies the station user's desktop", () => {
  const properties = "User=123\nClass=user\nType=wayland\nActive=yes\nRemote=no\nDisplay=\n";
  assert.deepEqual(graphicalSession("2", 123, properties), {
    id: "2", uid: 123, type: "wayland", active: true, remote: false, display: undefined,
  });
  assert.equal(graphicalSession("2", 999, properties), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Class=user", "Class=greeter")), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Type=wayland", "Type=tty")), null);
  assert.equal(graphicalSession("2", 123, properties.replace("Active=yes", "Active=no"))?.active, false);
});

test("the Linux desktop follows a change between Wayland and X11 sessions", async () => {
  let env: NodeJS.ProcessEnv = { XDG_SESSION_TYPE: "wayland", WAYLAND_DISPLAY: "wayland-0" };
  let changes = 0;
  const desktop = new LinuxDesktop({ data: tmpdir(), env: {}, discover: async () => env, changed: () => { changes++; } });
  try {
    await desktop.refresh(true);
    assert.equal(desktop.access().capture, true);
    env = { XDG_SESSION_TYPE: "x11" };
    await desktop.refresh(true);
    assert.equal(desktop.access().reason, "linuxNoDisplay");
    assert.ok(changes >= 2);
  } finally {
    await desktop.close();
  }
});

test("a portal view carries its first picture, input and close across the helper pipe", { skip: process.platform === "win32", timeout: 5_000 }, async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "sf-portal-test-"));
  const runner = join(dir, "runner");
  await writeFile(runner, '#!/bin/sh\nshift\nexec "$STILLFAIL_TEST_NODE" "$@"\n', { mode: 0o700 });
  const helper = fileURLToPath(new URL("./fixtures/portal-helper.mjs", import.meta.url));
  let changes = 0;
  const desktop = new WaylandDesktop({
    changed: () => { changes++; },
    env: { ...process.env, STILLFAIL_TEST_NODE: process.execPath, STILLFAIL_TEST_CLOSE_MARKER: join(dir, "closed") },
    python: runner,
    helper,
  });
  try {
    await assert.rejects(desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["h264"] }), /JPEG/);
    const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["jpeg"] });
    assert.deepEqual(desktop.size(), { width: 1280, height: 800 });
    const first = await view.next();
    assert.ok(first);
    assert.deepEqual(first.config, { codec: "jpeg", width: 640, height: 400 });
    assert.deepEqual([...first.data], [0xff, 0xd8, 0xff, 0xd9]);
    assert.equal(first.key, true);
    assert.ok(changes > 0);

    await view.input({ t: "pointer", kind: "move", x: 0.25, y: 0.5, buttons: 0 });
    const pointer = await view.next();
    assert.ok(pointer);
    assert.deepEqual(JSON.parse(Buffer.from(pointer.data).toString()), { t: "pointer", kind: "move", x: 0.25, y: 0.5, buttons: 0 });
    assert.ok(pointer.ts > first.ts);

    await view.input({ t: "key", kind: "down", code: "KeyA", key: "a", mods: 0 });
    const key = await view.next();
    assert.ok(key);
    assert.deepEqual(JSON.parse(Buffer.from(key.data).toString()), { t: "key", keycode: 30, kind: "down" });

    const pending = view.next();
    let sawClose!: () => void;
    const closed = new Promise<void>((resolve) => { sawClose = resolve; });
    const watcher = watch(dir, (_event, name) => { if (name === "closed") sawClose(); });
    t.after(() => watcher.close());
    view.close();
    assert.equal(await pending, null);
    await closed;
    watcher.close();
  } finally {
    await desktop.close();
    await rm(dir, { recursive: true, force: true });
  }
});

test("simultaneous portal openings get separate sessions", { skip: process.platform === "win32", timeout: 5_000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), "sf-portal-concurrent-"));
  const runner = join(dir, "runner");
  await writeFile(runner, '#!/bin/sh\nshift\nexec "$STILLFAIL_TEST_NODE" "$@"\n', { mode: 0o700 });
  const helper = fileURLToPath(new URL("./fixtures/portal-helper.mjs", import.meta.url));
  const desktop = new WaylandDesktop({ changed: () => {}, env: { ...process.env, STILLFAIL_TEST_NODE: process.execPath }, python: runner, helper });
  try {
    const options = { maxWidth: 640, maxHeight: 400, codecs: ["jpeg" as const] };
    const [first, second] = await Promise.all([desktop.open(options), desktop.open(options)]);
    assert.notEqual(first, second);
    assert.deepEqual((await first.next())?.config, { codec: "jpeg", width: 640, height: 400 });
    assert.deepEqual((await second.next())?.config, { codec: "jpeg", width: 640, height: 400 });
    first.close();
    second.close();
  } finally {
    await desktop.close();
    await rm(dir, { recursive: true, force: true });
  }
});

test("an unanswered portal dialog stays pending until the desktop is closed", { skip: process.platform === "win32", timeout: 5_000 }, async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "sf-portal-consent-"));
  const runner = join(dir, "runner");
  await writeFile(runner, '#!/bin/sh\nshift\nexec "$STILLFAIL_TEST_NODE" "$@"\n', { mode: 0o700 });
  const helper = fileURLToPath(new URL("./fixtures/portal-helper.mjs", import.meta.url));
  const desktop = new WaylandDesktop({
    changed: () => {},
    env: { ...process.env, STILLFAIL_TEST_NODE: process.execPath, STILLFAIL_TEST_HOLD_CONSENT: "1", STILLFAIL_TEST_CLOSE_MARKER: join(dir, "closed") },
    python: runner,
    helper,
    consentWaitMs: 200,
  });
  let sawClose!: () => void;
  const closed = new Promise<void>((resolve) => { sawClose = resolve; });
  const watcher = watch(dir, (_event, name) => { if (name === "closed") sawClose(); });
  t.after(() => watcher.close());
  try {
    await assert.rejects(desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["jpeg"] }), (error: unknown) => {
      assert.ok(error instanceof ScreenRefused);
      assert.equal(error.key, "station.screen.linuxPortalConsent");
      assert.equal(error.access?.asking, true);
      return true;
    });
    assert.equal(desktop.access().asking, true);
  } finally {
    await desktop.close();
    await closed;
    watcher.close();
    await rm(dir, { recursive: true, force: true });
  }
});
