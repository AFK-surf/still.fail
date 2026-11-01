// What macOS lets still.fail Helper do, as the station's page and the agents see it and ask for it (src/helper/grants.ts,
// src/api/routes/permissions.ts, src/tools/permissions.ts; docs/remote-screens.md "Grants"): the grants as the helper
// says them, told again as they change; one asked for puts the helper's window up once (not again while it is up, nor
// within AGAIN_MS when an agent or the drive asks; a person's own ask puts it up again); the answer says whether the screen can be driven (the
// client then opens it) or the person has to go to the Mac. The helper is a fake in this process speaking main.swift's
// `status`, `permissions.show`, `files.access` and `watch`; the station's clock is the test's.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { routes, permissionsView } from "../src/api/routes/permissions.ts";
import type { Request } from "../src/api/request.ts";
import { HELPER_APP, HelperApp } from "../src/helper/app.ts";
import { HelperFiles } from "../src/helper/files.ts";
import { AGAIN_MS, HelperGrants, LOCAL_NETWORK_SETTINGS } from "../src/helper/grants.ts";
import { WINDOWS } from "../src/platform/index.ts";
import { Desktop } from "../src/screens/desktop.ts";
import { permissionTools } from "../src/tools/permissions.ts";

/// still.fail Helper's side: its grants (`screen` the two, `files` the folders'), its window (what it asks for while
/// up), the disks mounted (`disks`: a path and the grant macOS keeps it under). Every request noted (`asked`).
class FakeHelper {
  capture = true;
  control = true;
  files: Record<string, string> = { all: "unknown", documents: "granted", desktop: "unknown", downloads: "granted", removable: "unknown", network: "unknown" };
  up: string[] | null = null;
  shown: any[] = [];
  asked: any[] = [];
  disks = new Map<string, string>();
  #server: net.Server | null = null;
  #where: { path: string; token: string } | null = null;
  #conns = new Set<net.Socket>();
  #watches = new Set<net.Socket>();
  #closed = false;

  launch = async (_app: string, env: Record<string, string>) => {
    if (this.#closed) throw new Error("the test is over");
    this.#where = { path: env.STILLFAIL_HELPER_SOCKET!, token: env.STILLFAIL_HELPER_TOKEN! };
    rmSync(this.#where.path, { force: true });
    const server = net.createServer((c) => this.#serve(c));
    await new Promise<void>((resolve) => server.listen(this.#where!.path, resolve));
    this.#server = server;
  };
  close() {
    this.#closed = true;
    this.#server?.close();
    for (const c of this.#conns) c.destroy();
  }
  /// Its window saw a grant change (or closed): told on the station's watch.
  tell() {
    for (const w of this.#watches) w.write(`${JSON.stringify({ event: "grants" })}\n`);
  }
  #serve(conn: net.Socket) {
    this.#conns.add(conn);
    conn.on("close", () => (this.#conns.delete(conn), this.#watches.delete(conn)));
    conn.on("error", () => {});
    let carry = "";
    conn.setEncoding("utf8");
    conn.on("data", (chunk: string) => {
      carry += chunk;
      const at = carry.indexOf("\n");
      if (at < 0) return;
      const ask = JSON.parse(carry.slice(0, at));
      const end = (v: unknown) => conn.end(`${JSON.stringify(v)}\n`);
      if (ask.token !== this.#where!.token) return end({ error: "not the station's token" });
      if (ask.op !== "hello") this.asked.push(ask);
      switch (ask.op) {
        case "hello":
          return end({ ok: true, v: 1, pid: 100 });
        case "watch":
          this.#watches.add(conn);
          return void conn.write(`${JSON.stringify({ ok: true })}\n`);
        case "quit":
          end({ ok: true });
          this.#server?.close();
          return;
        case "status":
          return end({ capture: this.capture, control: this.control, files: this.files, display: { id: 1, width: 3024, height: 1890 }, asking: this.up !== null, asked: this.up ?? [] });
        case "permissions.show":
          this.shown.push(ask);
          this.up = [...(this.up ?? []), ...ask.grants.filter((g: string) => !this.up?.includes(g))];
          return end({ ok: true });
        case "files.access":
          return end({ access: ask.paths.map((p: string) => (this.disks.has(p) ? { path: p, top: p, grant: this.disks.get(p), state: this.files[this.disks.get(p)!] } : { path: p, grant: null, state: "granted" })) });
        default:
          return end({ error: `unknown op ${ask.op}` });
      }
    });
  }
}

function station(options: { folders?: boolean } = {}) {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "permissions-")));
  const app = join(base, "release", HELPER_APP);
  mkdirSync(join(app, "Contents/MacOS"), { recursive: true });
  mkdirSync(join(app, "Contents/_CodeSignature"), { recursive: true });
  writeFileSync(join(app, "Contents/MacOS/stillfail-helper"), "code");
  writeFileSync(join(app, "Contents/Info.plist"), "<plist/>");
  writeFileSync(join(app, "Contents/_CodeSignature/CodeResources"), "signed");
  const volumes = join(base, "Volumes");
  mkdirSync(volumes);
  // The system's own disk is a link to / there: never asked about.
  symlinkSync("/", join(volumes, "Macintosh HD"));
  const fake = new FakeHelper();
  const helper = new HelperApp({ app, dir: join(base, "helper"), launch: fake.launch });
  const clock = { now: 1_000_000 };
  // Whether the station reaches its LAN (none by default: no LAN), and System Settings' panes opened on the Mac.
  const lan: { now: "granted" | "denied" | null } = { now: null };
  const opened: string[] = [];
  const grants = new HelperGrants({ helper, folders: options.folders, now: () => clock.now, volumes, mounts: () => [], reach: async () => lan.now, open: (url) => void opened.push(url) });
  let changes = 0;
  grants.onChange(() => changes++);
  // Ends with its test: nothing left to keep the process.
  const end = async () => {
    await helper.quit();
    fake.close();
    rmSync(base, { recursive: true, force: true });
  };
  return { base, volumes, fake, helper, grants, clock, lan, opened, changes: () => changes, end };
}

const member: Request["viewer"] = { sub: "u", email: "a@x", name: "A", role: "member", workspace: "w", device: "d" };
const reader: Request["viewer"] = { ...member, role: "viewer" };

/// POST /permissions/request as `lang` asks it: its status and body.
async function ask(grants: HelperGrants, grant: unknown, lang: "zh" | "en" = "zh") {
  const route = routes({ grants }).find((r) => r.pattern.test("/permissions/request"))!;
  const r: Request = { method: "POST", path: "/permissions/request", query: [], headers: {}, body: Buffer.from(JSON.stringify({ grant })), viewer: member, lang };
  const answer = await route.handle(r, []);
  return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()) };
}

/// Until `what` holds (the helper's answers come on its socket).
const until = async (what: () => boolean) => {
  while (!what()) await new Promise((r) => setImmediate(r));
};

test("the grants as the page sees them: none before the first look, then each in order, told again as they change", { skip: WINDOWS }, async () => {
  const s = station();
  // Not looked at yet: nothing said (the overview leaves it out), and the look made now.
  assert.equal(permissionsView(s.grants, member), null);
  await until(() => s.changes() > 0);
  assert.deepEqual(permissionsView(s.grants, member), {
    grants: [
      { grant: "capture", state: "granted" }, { grant: "control", state: "granted" }, { grant: "documents", state: "granted" },
      { grant: "desktop", state: "unknown" }, { grant: "downloads", state: "granted" }, { grant: "removable", state: "unknown" }, { grant: "network", state: "unknown" },
    ],
    asking: [], screen: true, request: true,
  });
  // A read-only member sees them, and may not ask.
  assert.equal(permissionsView(s.grants, reader)!.request, false);
  // Read again and again: what was looked at last, the helper not asked each time.
  const looks = () => s.fake.asked.filter((a) => a.op === "status").length;
  const before = looks();
  for (let i = 0; i < 5; i++) permissionsView(s.grants, member);
  assert.equal(looks(), before);
  // Accessibility taken away in System Settings: seen once the page reads it a while later, told.
  s.fake.control = false;
  s.clock.now += 30_000;
  const told = s.changes();
  permissionsView(s.grants, member);
  await until(() => s.changes() > told);
  assert.equal(permissionsView(s.grants, member)!.screen, false);
  assert.equal(permissionsView(s.grants, member)!.grants[1]!.state, "unknown");
  // Granted in the window: the helper says so on the station's watch, looked at at once.
  s.fake.control = true;
  const again = s.changes();
  s.fake.tell();
  await until(() => s.changes() > again);
  assert.equal(permissionsView(s.grants, member)!.screen, true);
  await s.end();
});

test("a station without the folders' grants lists the screen's two only", { skip: WINDOWS }, async () => {
  const s = station({ folders: false });
  await s.grants.refresh(true);
  assert.deepEqual(s.grants.view()!.grants.map((g) => g.grant), ["capture", "control"]);
  assert.equal((await ask(s.grants, "desktop")).status, 400);
  await s.end();
});

/// 2026-10-18, a MacBook on studio's Wi-Fi: the desktop app (and the station it runs) could reach nothing on its own
/// subnet, macOS's Local Network not switched on for it. The station's own: listed last once it is on a LAN, with the
/// app it is switched on for; asked for, System Settings' Local Network list comes up on the Mac, once in a while.
test("the station's Local Network: listed once on a LAN, asked for it opens System Settings there", { skip: WINDOWS }, async () => {
  const s = station();
  await s.grants.refresh(true);
  assert.ok(!s.grants.view()!.grants.some((g) => g.grant === "localNetwork"));
  assert.equal(s.grants.view()!.localNetworkName, undefined);
  s.lan.now = "denied";
  const told = s.changes();
  await s.grants.refresh(true);
  assert.ok(s.changes() > told);
  const view = s.grants.view()!;
  assert.deepEqual(view.grants.at(-1), { grant: "localNetwork", state: "denied" });
  assert.equal(typeof view.localNetworkName, "string");
  // Asked for: the list up on the Mac; a person asking again a moment later has it up again.
  const first = await ask(s.grants, "localNetwork");
  assert.deepEqual([first.status, first.body.window], [200, "up"]);
  assert.deepEqual(s.opened, [LOCAL_NETWORK_SETTINGS]);
  assert.deepEqual((await ask(s.grants, "localNetwork")).body.window, "up");
  assert.equal(s.opened.length, 2);
  // Switched on (the station started again): granted, nothing opened.
  s.lan.now = "granted";
  s.clock.now += AGAIN_MS;
  assert.deepEqual((await ask(s.grants, "localNetwork")).body, { window: "granted", screen: true });
  assert.equal(s.opened.length, 2);
  // The agents' tool says it and where it is switched on.
  s.lan.now = "denied";
  await s.grants.refresh(true);
  const [tool] = permissionTools(s.grants, () => null);
  const listed = String(await tool!.run("k", {}));
  assert.match(listed, /localNetwork \(Local Network: .*\): refused: the LAN is not reached \(switched on for .* in System Settings › Privacy & Security › Local Network/);
  await s.end();
});

test("a grant asked for: the window up for it once, not again while it is up; a person asking again a while after has it up again", { skip: WINDOWS }, async () => {
  const s = station();
  // Desktop asked for: the window up for that one only, in the asker's words; the screen can be driven (the client opens it).
  const first = await ask(s.grants, "desktop");
  assert.deepEqual(first, { status: 200, body: { window: "up", screen: true } });
  assert.equal(s.fake.shown.length, 1);
  assert.deepEqual(s.fake.shown[0].grants, ["desktop"]);
  assert.equal(s.fake.shown[0].words.title, "允许 still.fail 使用这台 Mac 的权限");
  assert.equal(s.fake.shown[0].words.desktop, "桌面");
  assert.equal(s.fake.shown[0].words.capture, "屏幕录制");
  // The page says it is asking as soon as it is answered.
  assert.deepEqual(s.grants.view()?.asking, ["desktop"]);
  // Asked again while it is up (a second tap, another member): left as it is.
  assert.deepEqual(await ask(s.grants, "desktop"), { status: 200, body: { window: "up", screen: true } });
  assert.equal(s.fake.shown.length, 1);
  // The drive opening the Desktop meanwhile: the same window, not shown again.
  const files = new HelperFiles({ helper: s.helper, changed: () => {}, grants: s.grants });
  assert.equal(await files.ask("desktop", "/Users/a/Desktop"), "up");
  assert.equal(s.fake.shown.length, 1);
  // Closed without it (the helper says so on the station's watch): the page stops saying it asks.
  s.fake.up = null;
  s.fake.tell();
  await until(() => s.grants.view()?.asking.length === 0);
  // The drive asking again within AGAIN_MS: not shown, said so.
  s.clock.now += 60_000;
  assert.equal(await files.ask("desktop", "/Users/a/Desktop"), "closed");
  assert.equal(s.fake.shown.length, 1);
  // 2026-10-20: a person closed it without granting, tapped Request again a moment later and was told to come back in a
  // few minutes. A person's own ask puts it up again.
  assert.deepEqual(await ask(s.grants, "desktop"), { status: 200, body: { window: "up", screen: true } });
  assert.equal(s.fake.shown.length, 2);
  s.fake.up = null;
  // Another grant is not held back by it; one granted already shows nothing.
  s.fake.files.downloads = "denied";
  assert.equal((await ask(s.grants, "downloads")).body.window, "up");
  assert.equal(s.fake.shown.length, 3);
  s.fake.up = null;
  assert.equal((await ask(s.grants, "documents")).body.window, "granted");
  assert.equal(s.fake.shown.length, 3);
  // Once the while has gone by, the drive has it shown again too.
  s.clock.now += AGAIN_MS;
  assert.equal(await files.ask("desktop", "/Users/a/Desktop"), "up");
  assert.equal(s.fake.shown.length, 4);
  // No such grant.
  assert.equal((await ask(s.grants, "camera")).status, 400);
  await s.end();
});

test("the screen not drivable: the answer says so (the client sends the person to the Mac), and a disk's grant asks with a disk", { skip: WINDOWS }, async () => {
  const s = station();
  s.fake.capture = false;
  assert.deepEqual(await ask(s.grants, "capture"), { status: 200, body: { window: "up", screen: false } });
  assert.deepEqual(s.fake.shown[0].grants, ["capture"]);
  // No disk of its kind mounted: nothing to have macOS ask about.
  const none = await ask(s.grants, "removable");
  assert.deepEqual(none, { status: 409, body: { error: "该 Mac 未连接外接磁盘，请连接后再申请" } });
  // One plugged in: the window asks for it with that disk (its Allow opens it, and macOS asks); only its mount looked at.
  const disk = join(s.volumes, "Backup");
  mkdirSync(disk);
  s.fake.disks.set(disk, "removable");
  assert.equal((await ask(s.grants, "removable")).body.window, "up");
  assert.deepEqual(s.fake.shown.at(-1).paths, { removable: disk });
  const looked = s.fake.asked.filter((a) => a.op === "files.access").at(-1);
  assert.deepEqual(looked.paths, [disk]);
  await s.end();
});

test("the agents' tool: the grants, and one asked for with what to post (the screen's link, or go to the Mac)", { skip: WINDOWS }, async () => {
  const s = station();
  const base = "https://still.fail/w/W/s/S";
  const [tool] = permissionTools(s.grants, () => base);
  const listed = await tool!.run("k", {});
  assert.match(listed, /- capture \(Screen Recording.*\): granted/);
  assert.match(listed, /- desktop \(Desktop folder.*\): not granted/);
  assert.match(listed, /can be seen and driven/);
  // The screen drivable: its link to post.
  const asked = await tool!.run("k", { request: "desktop" });
  assert.match(asked, /window asking for Desktop folder is up on /);
  assert.ok(asked.includes(`post ${base}/screen/desktop on a line of its own (it shows as the screen's card) with chat_post kind=need_human`), asked);
  assert.deepEqual(s.fake.shown[0].grants, ["desktop"]);
  // Asked again a moment after it closed: not shown, said so.
  s.fake.up = null;
  assert.match(await tool!.run("k", { request: "desktop" }), /shown less than 3 minutes ago/);
  assert.equal(s.fake.shown.length, 1);
  // Not drivable: the person goes to the Mac.
  s.fake.control = false;
  const there = await tool!.run("k", { request: "control" });
  assert.match(there, /has to do it at the Mac itself: post chat_post kind=need_human asking them to go to /);
  assert.ok(!there.includes("/screen/desktop"));
  // Granted already: nothing shown.
  assert.match(await tool!.run("k", { request: "documents" }), /Documents folder is granted already/);
  await assert.rejects(tool!.run("k", { request: "camera" }), /no grant camera/);
  assert.equal(s.fake.shown.length, 2);
  // Not a Mac: nothing to grant.
  assert.match(await permissionTools(null, () => base)[0]!.run("k", {}), /nothing to grant/);
  await s.end();
});

test("the desktop's screen and the page share one look at the grants", { skip: WINDOWS }, async () => {
  const s = station();
  let screens = 0;
  const desktop = new Desktop({ supported: true, helper: s.helper, grants: s.grants, changed: () => screens++ });
  await desktop.refresh(true);
  assert.equal(desktop.size().width, 3024);
  // The page reads what the screens looked at: the helper not asked again.
  const looks = s.fake.asked.filter((a) => a.op === "status").length;
  assert.equal(s.grants.view()!.screen, true);
  assert.equal(s.fake.asked.filter((a) => a.op === "status").length, looks);
  // A grant changing is told to both.
  s.fake.capture = false;
  const before = screens;
  s.fake.tell();
  await until(() => screens > before);
  assert.equal(desktop.access().capture, false);
  assert.equal(s.grants.view()!.screen, false);
  await s.end();
});
