// Modules beside the station (src/modules, docs/station-modules.md) against a fake module (test/fake/module.mjs, a Node
// script on its socket): started with what it is told, the admin API's `/m/<id>/…` passed on to it, directly and over
// the mesh (a body streamed in, a long answer and an event stream streamed out, let go of when the caller goes), who asks told and a forged teller
// dropped, a viewer's writes refused but those its manifest declares, started again after it crashes, ended as config.json
// stops naming it; and the station's local API for it: its token, who it acts for, the drive's rules (a viewer only in
// the pinned folders, the station's data never), thumbnails made again as an image changes.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { Admin } from "../src/api/admin.ts";
import type { Answer, Request } from "../src/api/request.ts";
import { stationDrive } from "../src/drive/drive.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { follow, type Life } from "../src/modules/live.ts";
import { listen, localApi } from "../src/modules/local.ts";
import { ModuleSet, isModulePath, moduleOf, modulesOf, viewerHeader, viewerOfHeader } from "../src/modules/modules.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { type Codecs, idOf } from "../src/drive/thumbs.ts";
import { randomBytes } from "node:crypto";
import { Cloud, writeState } from "../src/cloud/state.ts";
import type { Stream as MeshStream } from "../src/mesh/native.ts";
import { ALPN, Reader, serve } from "../src/mesh/serve.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { memoryMesh } from "./memory-mesh.ts";

const FAKE = fileURLToPath(new URL("./fake/module.mjs", import.meta.url));

/// Looks every 20 ms until `what` holds (a process starting, a socket answering: no event here). No deadline.
const until = async (what: () => boolean) => {
  while (!what()) await new Promise((r) => setTimeout(r, 20));
};

const owner: Viewer = { sub: "usr_o", email: "o@x", name: "Ō 主人", role: "owner", workspace: "ws1", device: "d", home: true };
const viewer: Viewer = { sub: "usr_v", email: "v@x", name: "Vee", role: "viewer", workspace: "ws1", device: "d", home: true };

const ask = (admin: Admin, who: Viewer, method: string, path: string, more: Partial<Request> = {}) => {
  const at = path.indexOf("?");
  return admin.handle({ method, path: at < 0 ? path : path.slice(0, at), query: [], search: at < 0 ? "" : path.slice(at), headers: {}, body: Buffer.alloc(0), viewer: who, lang: "en", ...more });
};

async function whole(answer: Answer): Promise<Buffer> {
  if (Buffer.isBuffer(answer.body)) return answer.body;
  const parts: Buffer[] = [];
  for await (const chunk of answer.body) parts.push(chunk);
  return Buffer.concat(parts);
}
const asJson = async (answer: Answer) => JSON.parse((await whole(answer)).toString());

/// A GET of the station's local API at `socket`: status, headers, body.
function local(socket: string, path: string, headers: Record<string, string>): Promise<{ status: number; headers: Record<string, unknown>; body: Buffer }> {
  return new Promise((resolve, reject) => {
    request({ socketPath: socket, path, headers }, async (res) => {
      const parts: Buffer[] = [];
      for await (const chunk of res) parts.push(chunk);
      resolve({ status: res.statusCode!, headers: res.headers, body: Buffer.concat(parts) });
    })
      .on("error", reject)
      .end();
  });
}

/// A station's data and config naming the fake module, its drive with a pinned folder, and the modules followed.
function station(t: { after: (f: () => unknown) => void }) {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "mod-")));
  const data = join(base, "d");
  const shared = join(base, "shared");
  const other = join(base, "other");
  for (const d of [data, shared, other]) mkdirSync(d, { recursive: true });
  writeFileSync(join(shared, "a.txt"), "shared text");
  writeFileSync(join(other, "b.txt"), "not shared");
  writeFileSync(join(data, "config.json"), JSON.stringify({ drive: { roots: [shared] }, modules: [{ id: "fake", command: process.execPath, args: [FAKE], env: { FAKE_EXTRA: "x" } }] }));
  const config = new ConfigFile(data);
  const drive = stationDrive(config, () => [], null);
  let changes = 0;
  const modules = new ModuleSet(data, () => changes++);
  const life: Life = { data, modules, drive, config, previousGone: Promise.resolve() };
  let again: Effect.Effect<void> = Effect.void;
  const fiber = Effect.runFork(
    Effect.scoped(
      Effect.gen(function* () {
        again = yield* follow(life);
        yield* again;
        yield* Effect.never;
      }),
    ),
  );
  t.after(async () => {
    await Effect.runPromise(Fiber.interrupt(fiber));
    rmSync(base, { recursive: true, force: true });
  });
  const admin = new Admin({ names: new Map() } as any, { modules });
  const dir = join(data, "modules", "fake");
  const starts = () => (existsSync(join(dir, "starts")) ? readFileSync(join(dir, "starts"), "utf8").trim().split("\n").map((l) => JSON.parse(l)) : []);
  return { base, data, shared, other, config, modules, admin, dir, starts, changes: () => changes, again: () => Effect.runPromise(again), fiber };
}

test("modules in config.json: ids and commands checked, those turned off left out; their paths", () => {
  const { specs, refused } = modulesOf({
    modules: [
      { id: "media", command: "/bin/media", args: ["--x"], env: { A: "1" } },
      { id: "Media", command: "x" },
      { id: "media", command: "y" },
      { id: "off", command: "z", enabled: false },
      { id: "noargs", command: "z", args: [1] },
    ],
  });
  assert.deepEqual(specs, [{ id: "media", command: "/bin/media", args: ["--x"], env: { A: "1" } }]);
  assert.equal(refused.length, 3);
  assert.deepEqual(moduleOf("/m/media/books/1"), { id: "media", path: "/books/1" });
  assert.deepEqual(moduleOf("/m/media"), { id: "media", path: "/" });
  assert.equal(moduleOf("/mx/media"), null);
  assert.equal(isModulePath("/m/media/x?y=1"), true);
  assert.equal(isModulePath("/m/media?y=1"), true);
  assert.equal(isModulePath("/media"), false);
  // Who asks, as a header's value: non-ASCII escaped, read back the same.
  const said = viewerHeader(owner);
  assert.match(said, /^[\x20-\x7e]+$/);
  assert.deepEqual(viewerOfHeader(said), { ...owner, device: "" });
  assert.equal(viewerOfHeader('{"role":"owner"}'), null);
});

test("a module: started with what it is told, asked as the admin API is, who asks told, bodies streamed both ways", async (t) => {
  const s = station(t);
  await until(() => s.modules.get("fake")?.running === true);
  assert.deepEqual(s.modules.listed(), [{ id: "fake", running: true }]);
  assert.ok(s.changes() >= 2);
  const [start] = s.starts();
  assert.equal(start.id, "fake");
  assert.equal(start.socket, join(s.dir, "module.sock"));
  assert.equal(start.station, join(s.dir, "station.sock"));
  assert.equal(start.extra, "x");
  assert.ok(start.token.length >= 32);
  assert.ok(existsSync(join(s.dir, "log")));

  // Passed on: its own path and the query, who asks as the station has them; one the caller says is dropped.
  const echo = await ask(s.admin, owner, "GET", "/m/fake/echo?a=1&b=%20", { headers: { "stillfail-viewer": '{"role":"owner","sub":"forged"}', "x-mine": "1", "accept-encoding": "zstd" } });
  assert.equal(echo.status, 200);
  const said = await asJson(echo);
  assert.equal(said.path, "/echo?a=1&b=%20");
  assert.deepEqual(JSON.parse(said.viewer), { sub: "usr_o", email: "o@x", name: "Ō 主人", role: "owner", workspace: "ws1", home: true });
  assert.equal(said.headers["x-mine"], "1");
  assert.equal(said.headers["accept-encoding"], undefined);

  // A body as it comes (three parts of a megabyte), and a whole one.
  async function* parts() {
    for (let i = 0; i < 3; i++) yield Buffer.alloc(1 << 20, i);
  }
  const up = await asJson(await ask(s.admin, owner, "POST", "/m/fake/echo", { upload: parts() }));
  assert.equal(up.size, 3 << 20);
  assert.equal(up.method, "POST");
  const small = await asJson(await ask(s.admin, owner, "PUT", "/m/fake/echo", { body: Buffer.from("hello") }));
  assert.equal(small.size, 5);

  // A long answer as it comes (not one buffer).
  const big = await ask(s.admin, owner, "GET", "/m/fake/big?n=20000000");
  assert.equal(big.status, 200);
  assert.ok(!Buffer.isBuffer(big.body));
  let n = 0;
  for await (const chunk of big.body as AsyncIterable<Buffer>) n += chunk.length;
  assert.equal(n, 20_000_000);

  // An event stream as it comes, let go of when the caller goes: the module hears it.
  const events = await ask(s.admin, owner, "GET", "/m/fake/events");
  assert.equal(events.headers["content-type"], "text/event-stream");
  const it = (events.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  let text = "";
  while (!text.includes("data: 2")) text += (await it.next()).value.toString();
  await it.return?.();
  await until(() => existsSync(join(s.dir, "closed")));

  // A module not named; a path of none.
  assert.deepEqual([(await ask(s.admin, owner, "GET", "/m/nope/x")).status, await asJson(await ask(s.admin, owner, "GET", "/m/nope/x"))], [404, { error: "no module nope" }]);
});

test("a viewer reads a module, and writes only what its manifest declares", async (t) => {
  const s = station(t);
  await until(() => s.modules.get("fake")?.running === true);
  assert.equal((await ask(s.admin, viewer, "GET", "/m/fake/echo")).status, 200);
  const saved = await ask(s.admin, viewer, "PUT", "/m/fake/progress/book-1", { body: Buffer.from("{}") });
  assert.deepEqual([saved.status, await asJson(saved)], [200, { saved: "book-1" }]);
  // A whole path only: not one under it, nor another method's elsewhere.
  assert.equal((await ask(s.admin, viewer, "PUT", "/m/fake/progress/book-1/more")).status, 403);
  const refused = await ask(s.admin, viewer, "POST", "/m/fake/echo");
  assert.deepEqual([refused.status, await asJson(refused)], [403, { error: "read-only members cannot change this station" }]);
  // The station's own writes stay refused.
  assert.equal((await ask(s.admin, viewer, "PUT", "/drive/roots")).status, 403);
});

test("a module that crashes is started again, with a new token; one config.json no longer names is ended", async (t) => {
  const s = station(t);
  await until(() => s.modules.get("fake")?.running === true);
  const first = s.starts()[0];
  // Its answer never comes: it is gone.
  const crashed = await ask(s.admin, owner, "GET", "/m/fake/crash");
  assert.equal(crashed.status, 503);
  await until(() => s.starts().length === 2 && s.modules.get("fake")?.running === true);
  const second = s.starts()[1];
  assert.notEqual(second.pid, first.pid);
  assert.notEqual(second.token, first.token);
  assert.equal((await ask(s.admin, owner, "GET", "/m/fake/echo")).status, 200);
  // While it is down it says so.
  s.modules.setRunning(s.modules.get("fake")!, false);
  assert.equal((await ask(s.admin, owner, "GET", "/m/fake/echo")).status, 503);

  // Named no more: ended, not listed.
  s.config.update((raw) => (raw.modules = []));
  await s.again();
  assert.deepEqual(s.modules.listed(), []);
  await until(() => {
    try {
      process.kill(second.pid, 0);
      return false;
    } catch {
      return true;
    }
  });
  assert.equal(existsSync(join(s.dir, "station.sock")), false);
});

test("over the mesh: a member's request to a module streamed in, its event stream let go of as the member goes", async (t) => {
  const s = station(t);
  await until(() => s.modules.get("fake")?.running === true);
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [at, device] = await Promise.all([bind(), bind()]);
  const grant = new GrantKey("k1");
  const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
  writeState(s.data, { origin: "o", station: at.id(), workspace: WS, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [], grant_keys: { keys: [grant.jwk] }, peers: [], revocations: [] });
  const cloud = new Cloud(s.data);
  t.after(async () => {
    cloud.close();
    await Promise.all([at.close(), device.close()]);
  });
  void (async () => {
    for (;;) {
      const conn = await at.accept();
      if (!conn) return;
      void serve({ cloud, admin: s.admin, up: () => true, shares: {} as any }, conn).catch(() => {});
    }
  })();
  const line = (stream: MeshStream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));
  const conn = await device.connect({ id: at.id(), ips: [`127.0.0.1:${at.sockets()[0]!.split(":").at(-1)}`] }, ALPN);
  const now = Math.floor(Date.now() / 1000);
  const first = await conn.openBi();
  const credential = (role: string) => grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: `usr_${role}`, email: `${role}@x`, name: role, ws: WS, role, device: device.id(), sid: "s", iat: now, exp: now + 3600 });
  await line(first, { credential: credential("owner"), protocol: 2 });
  assert.equal((await new Reader(first).line()).ok, true);

  // A body of three megabytes, in parts as they come; a forged teller dropped.
  const up = await conn.openBi();
  await line(up, { method: "POST", path: "/admin/api/m/fake/echo?x=1", headers: { "stillfail-viewer": '{"role":"owner","sub":"forged"}' } });
  for (let i = 0; i < 3; i++) await up.write(Buffer.alloc(1 << 20, i));
  await up.finish();
  const upReader = new Reader(up);
  assert.equal((await upReader.line()).status, 200);
  const echoed = JSON.parse((await upReader.rest()).toString());
  assert.deepEqual([echoed.size, echoed.path, JSON.parse(echoed.viewer).sub, JSON.parse(echoed.viewer).home], [3 << 20, "/echo?x=1", "usr_owner", true]);

  // An event stream: events as they come, until the member lets go of it.
  const events = await conn.openBi();
  await line(events, { method: "GET", path: "/admin/api/m/fake/events", headers: {} });
  await events.finish();
  const reader = new Reader(events);
  const head = await reader.line();
  assert.deepEqual([head.status, head.headers["content-type"]], [200, "text/event-stream"]);
  let text = reader.carry.toString();
  while (!text.includes("data: 2")) text += (await events.read())!.toString();
  await events.reset(0);
  await until(() => existsSync(join(s.dir, "closed")));
});

test("the station's local API: the module's token, who it acts for, the drive's rules for them", async (t) => {
  const s = station(t);
  await until(() => s.modules.get("fake")?.running === true);
  const { station: socket, token } = s.starts()[0];
  const as = (who: Viewer) => ({ authorization: `Bearer ${token}`, "stillfail-viewer": viewerHeader(who) });
  const q = (root: string, path: string) => `root=${encodeURIComponent(root)}&path=${encodeURIComponent(path)}`;

  assert.equal((await local(socket, `/drive/list?${q(s.shared, "")}`, { "stillfail-viewer": viewerHeader(viewer) })).status, 401);
  assert.equal((await local(socket, `/drive/list?${q(s.shared, "")}`, { authorization: "Bearer nope", "stillfail-viewer": viewerHeader(viewer) })).status, 401);
  assert.equal((await local(socket, `/drive/list?${q(s.shared, "")}`, { authorization: `Bearer ${token}` })).status, 400);

  // A viewer: the pinned folder, read as the admin API reads it; nothing else.
  const listed = await local(socket, `/drive/list?${q(s.shared, "")}`, as(viewer));
  assert.equal(listed.status, 200);
  assert.deepEqual(JSON.parse(listed.body.toString()).entries.map((e: any) => e.name), ["a.txt"]);
  const read = await local(socket, `/drive/read?${q(s.shared, "a.txt")}&offset=7&length=4`, as(viewer));
  assert.deepEqual([read.status, read.body.toString(), read.headers["stillfail-total"]], [200, "text", "11"]);
  const out = await local(socket, `/drive/read?${q(s.other, "b.txt")}`, as(viewer));
  assert.deepEqual([out.status, JSON.parse(out.body.toString()).code], [404, "not_a_root"]);
  assert.equal(JSON.parse((await local(socket, `/drive/read?${q(s.shared, "../other/b.txt")}`, as(viewer))).body.toString()).code, "path_escape");
  // A member who may write: any folder, but never the station's own data.
  assert.equal((await local(socket, `/drive/read?${q(s.other, "b.txt")}`, as(owner))).body.toString(), "not shared");
  const own = await local(socket, `/drive/read?${q(s.data, "config.json")}`, as(owner));
  assert.deepEqual([own.status, JSON.parse(own.body.toString()).code], [403, "protected"]);
  // Reads only.
  assert.equal((await local(socket, "/nothing", as(owner))).status, 404);
});

test("the local API's thumbnails: made by the codecs, kept, made again once the image is newer; none of what is no image", async (t) => {
  const s = station(t);
  const image = join(s.shared, "p.png");
  writeFileSync(image, Buffer.alloc(30_000, 1));
  let made = 0;
  const codecs: Codecs = {
    thumbnail: async (img, dir) => {
      const path = join(dir, `${idOf(img)}.jpg`);
      if (!existsSync(path)) {
        made++;
        mkdirSync(dir, { recursive: true });
        writeFileSync(path, `thumb ${made}`);
      }
      return { path, type: "image/jpeg" };
    },
    thumbhash: async () => ({ hash: "aGFzaA==", width: 4, height: 3 }),
  };
  const socket = join(s.base, "t.sock");
  const server = await listen(socket, localApi({ drive: stationDrive(s.config, () => [], null), config: s.config, thumbs: join(s.data, "thumbs"), token: () => "tok", codecs }));
  t.after(() => server.close());
  const headers = { authorization: "Bearer tok", "stillfail-viewer": viewerHeader(viewer) };
  const thumb = await local(socket, `/thumb?root=${encodeURIComponent(s.shared)}&path=p.png`, headers);
  assert.deepEqual([thumb.status, thumb.body.toString(), thumb.headers["content-type"], thumb.headers["stillfail-thumbhash"], thumb.headers["stillfail-width"]], [200, "thumb 1", "image/jpeg", "aGFzaA==", "4"]);
  assert.ok(existsSync(join(s.data, "thumbs", "drive", `${idOf(image)}.jpg`)));
  assert.equal((await local(socket, `/thumb?root=${encodeURIComponent(s.shared)}&path=p.png`, headers)).body.toString(), "thumb 1");
  const later = Date.now() / 1000 + 60;
  utimesSync(image, later, later);
  assert.equal((await local(socket, `/thumb?root=${encodeURIComponent(s.shared)}&path=p.png`, headers)).body.toString(), "thumb 2");
  assert.equal((await local(socket, `/thumb?root=${encodeURIComponent(s.shared)}&path=a.txt`, headers)).status, 404);
  assert.equal((await local(socket, `/poster?root=${encodeURIComponent(s.shared)}&path=a.txt`, headers)).status, 404);
  assert.equal((await local(socket, `/thumb?root=${encodeURIComponent(s.other)}&path=b.png`, headers)).status, 404);
});
