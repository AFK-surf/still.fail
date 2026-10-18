// Modules the station installs itself (src/modules/packages.ts, docs/station-modules.md「包」), against a fake release
// server: a module packed and its feed signed as CI does it (scripts/module-bundle.ts, scripts/release-sign.ts) with the
// tests' key, installed from the feed, run by the station's own Node, updated to a newer build and gone back from one
// that never comes up; and refused: a signature by a key it does not take, words that are not this module's release,
// an archive that is not the one signed, a release for a newer station, one older than what came up. The real media
// service packed the same way runs too.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { pack } from "../../scripts/module-bundle.ts";
import { stationDrive } from "../src/drive/drive.ts";
import { ask } from "../src/modules/forward.ts";
import { keep, type Life } from "../src/modules/live.ts";
import { ModuleSet, modulesOf } from "../src/modules/modules.ts";
import { Packages, readInstalled } from "../src/modules/packages.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { readArchive, writeArchive } from "../src/updates/archive.ts";
import { Unverified, sha256, verifyModule } from "../src/updates/signed.ts";
import { Updates } from "../src/updates/updates.ts";
import { KEY, OTHER, signed, trusted } from "./release-fakes.ts";

delete process.env.STILLFAIL_CONFIG;
delete process.env.EMBER_CONFIG;

const MEDIA = fileURLToPath(new URL("../../media/service", import.meta.url));
const temp = (prefix: string) => realpathSync(mkdtempSync(join(tmpdir(), prefix)));

/// Looks every 20 ms until `what` holds (a process starting, a socket answering: no event here). No deadline.
const until = async (what: () => boolean | Promise<boolean>) => {
  while (!(await what())) await new Promise((r) => setTimeout(r, 20));
};

/// A release server: <dir>/<path> at /releases/<path>; what was asked, in order.
async function releases(t: { after: (f: () => unknown) => void }) {
  const dir = temp("mp-r-");
  const asked: string[] = [];
  const server = createServer((req, res) => {
    asked.push(req.url!);
    const file = join(dir, decodeURIComponent(req.url!.replace(/^\/releases\//, "")));
    if (!req.url!.startsWith("/releases/") || !existsSync(file)) return void res.writeHead(404).end();
    res.writeHead(200).end(readFileSync(file));
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  });
  return { dir, asked, base: `http://127.0.0.1:${(server.address() as AddressInfo).port}` };
}

/// The fake module's code at `build`: it answers its manifest and, at any other path, its build and what it was given;
/// `crash`: it ends at once (exit 3), never answering.
const fakeMain = (build: number, crash = false) => `import { createServer } from "node:http";
if (${crash}) process.exit(3);
process.stdin.on("end", () => process.exit(0));
process.stdin.resume();
createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  if (req.url === "/manifest") return res.end("{}");
  res.end(JSON.stringify({ build: ${build}, argv: process.argv.slice(1), electron: process.env.ELECTRON_RUN_AS_NODE ?? null, extra: process.env.FAKE_EXTRA ?? null }));
}).listen(process.env.STILLFAIL_MODULE_SOCKET);
`;

/// The fake module at `build` packed into the releases (`beta` or stable feed) and its feed signed with the tests' key,
/// as CI packs and signs one: the archive's and the feed's names. Its source is TypeScript, an entry importing another
/// file: bundled into main.mjs as it is packed.
function packFake(out: string, build: number, o: { crash?: boolean; beta?: boolean; needsStation?: number } = {}): [string, string] {
  const dir = temp("mp-m-");
  try {
    writeFileSync(join(dir, "module.json"), JSON.stringify({ id: "fake", entry: "src/main.ts", files: ["lib"], needsStation: o.needsStation ?? 100 }));
    mkdirSync(join(dir, "src"));
    writeFileSync(join(dir, "src", "build.ts"), `export const BUILD: number = ${build};\n`);
    writeFileSync(join(dir, "src", "main.ts"), `import { BUILD } from "./build.ts";\nconst kept: number = BUILD;\n${fakeMain(build, o.crash).replace(`build: ${build},`, "build: kept,")}`);
    mkdirSync(join(dir, "lib"));
    writeFileSync(join(dir, "lib", "words.txt"), `build ${build}`);
    writeFileSync(join(dir, "lib", ".hidden"), "not packed");
    return pack(dir, out, { beta: o.beta ?? true, build, unsignedOk: false, env: { ...process.env, CI: "", RELEASE_SIGNING_KEY: KEY.pem } });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/// A module release's words (fake's, build `build`), signed as a feed carries them (by `key`), written as the feed of
/// `channel`; with the archive it names, unless it is given.
function feedOf(out: string, build: number, o: { words?: object; key?: typeof KEY; archive?: Buffer; channel?: "beta" | "stable"; needsStation?: number } = {}) {
  const archive = o.archive ?? Buffer.from(writeArchive([{ path: "module.json", bytes: Buffer.from(JSON.stringify({ id: "fake", entry: "main.mjs" })) }, { path: "main.mjs", bytes: Buffer.from(fakeMain(build)) }]));
  const words = { kind: "stillfail-module-release", id: "fake", version: `0.1.${build}`, build, needsStation: o.needsStation ?? 100, builds: { any: { sha256: sha256(archive), size: archive.length } }, ...o.words };
  mkdirSync(join(out, "modules", "fake"), { recursive: true });
  writeFileSync(join(out, "modules", "fake", `fake-0.1.${build}.tar.gz`), archive);
  writeFileSync(join(out, "modules", "fake", `fake${o.channel === "stable" ? "" : "-beta"}.json`), JSON.stringify({ id: "fake", version: `0.1.${build}`, build, ...signed(words, o.key) }));
  return archive;
}

/// A station's data, its config naming `modules` (fake, by its package), the packages from `base`; with `run`, the
/// modules followed as ModulesLive follows them.
function station(t: { after: (f: () => unknown) => void }, base: string, o: { station?: number | null; channel?: () => "beta" | "stable"; modules?: unknown[]; run?: boolean } = {}) {
  const root = temp("mp-");
  const data = join(root, "d");
  mkdirSync(data);
  writeFileSync(join(data, "config.json"), JSON.stringify({ modules: o.modules ?? [{ id: "fake", package: "fake", args: ["--more"], env: { FAKE_EXTRA: "x" } }] }));
  const config = new ConfigFile(data);
  const modules = new ModuleSet(data);
  const packages = new Packages({ data, station: o.station === undefined ? 200 : o.station, base: () => base, channel: o.channel ?? (() => "beta"), trusted, previousGone: Promise.resolve() });
  const life: Life = { data, modules, drive: stationDrive(config, () => [], null), config, previousGone: Promise.resolve(), packages };
  const fiber = o.run === false ? null : Effect.runFork(Effect.scoped(Effect.andThen(keep(life), Effect.never)));
  t.after(async () => {
    if (fiber) await Effect.runPromise(Fiber.interrupt(fiber));
    await packages.close();
    rmSync(root, { recursive: true, force: true });
  });
  const app = packages.appOf("fake");
  /// What the running fake module says of itself.
  const said = async () => {
    const module = modules.get("fake");
    if (!module?.running) return null;
    try {
      return JSON.parse((await ask(module.socket, "/about")).body.toString());
    } catch {
      return null;
    }
  };
  return { data, config, modules, packages, app, state: () => readInstalled(app), said };
}

const named = [{ id: "fake", package: "fake", args: [], env: {} }];

test("config.json names a module by a command or by a package, one of the two; ids as the client core's", () => {
  const { specs, refused } = modulesOf({
    modules: [
      { id: "media", package: "media" },
      { id: "books", package: "media", args: ["--x"], env: { A: "1" } },
      { id: "both", package: "media", command: "/bin/x" },
      { id: "neither" },
      { id: "badpkg", package: "Media" },
      { id: "with-hyphen", command: "/bin/x" },
      { id: "emptycmd", command: "" },
    ],
  });
  assert.deepEqual(specs, [
    { id: "media", package: "media", args: [], env: {} },
    { id: "books", package: "media", args: ["--x"], env: { A: "1" } },
  ]);
  assert.equal(refused.length, 5);
  assert.ok(refused.some((r) => r.includes("with-hyphen")));
});

test("a module release's words verified: signed by a key taken, of this module, the feed's version the signed one", () => {
  const words = { kind: "stillfail-module-release", id: "fake", version: "0.1.7", build: 7, needsStation: 3, builds: { any: { sha256: "a".repeat(64), size: 9 } } };
  assert.equal(verifyModule({ version: "0.1.7", ...signed(words) }, "fake", trusted).build, 7);
  const refused = (feed: object, id = "fake") => assert.throws(() => verifyModule(feed, id, trusted), Unverified);
  refused({ ...signed(words, OTHER) });
  refused({ ...signed(words) }, "other");
  refused({ version: "0.1.8", ...signed(words) });
  refused({ ...signed({ ...words, kind: "stillfail-station-release" }) });
  refused({ ...signed({ ...words, version: "0.1.6" }) });
  refused({ ...signed({ ...words, needsStation: "3" }) });
  refused({ ...signed({ ...words, builds: {} }) });
  refused({ ...signed({ ...words, builds: { any: { sha256: "x", size: 9 } } }) });
  refused({ release: signed(words).release });
});

test("a module packed: its files and module.json, hidden ones left out, the same bytes each time; its feed signed", (t) => {
  const out = temp("mp-p-");
  t.after(() => rmSync(out, { recursive: true, force: true }));
  const [archive, feed] = packFake(out, 41);
  assert.deepEqual([archive, feed], ["modules/fake/fake-0.1.41.tar.gz", "modules/fake/fake-beta.json"]);
  const bytes = readFileSync(join(out, archive));
  const files = readArchive(bytes);
  assert.deepEqual(files.map((f) => f.path), ["lib/words.txt", "main.mjs", "module.json"]);
  // The entry bundled, its types gone, nothing of where it was made; the package says to run it.
  const main = Buffer.from(files.find((f) => f.path === "main.mjs")!.bytes).toString();
  assert.match(main, /(const|let|var) kept = BUILD;/);
  assert.match(main, /(const|let|var) BUILD = 41;/);
  assert.doesNotMatch(main, /: number|mp-m-|\/tmp\/|\/var\//);
  assert.deepEqual(JSON.parse(Buffer.from(files.find((f) => f.path === "module.json")!.bytes).toString()), { id: "fake", entry: "main.mjs", files: ["main.mjs", "lib"], needsStation: 100 });
  packFake(out, 41);
  assert.deepEqual(readFileSync(join(out, archive)), bytes);
  const release = verifyModule(JSON.parse(readFileSync(join(out, feed), "utf8")), "fake", trusted);
  assert.deepEqual(release, { kind: "stillfail-module-release", id: "fake", version: "0.1.41", build: 41, needsStation: 100, builds: { any: { sha256: sha256(bytes), size: bytes.length } } });
  // The stable channel's feed names the same archive.
  assert.equal(packFake(out, 41, { beta: false })[1], "modules/fake/fake.json");
});

test("a package: installed from its signed feed, run by the station's Node, updated, and gone back from a build that never comes up", async (t) => {
  const r = await releases(t);
  packFake(r.dir, 101);
  const s = station(t, r.base);
  await until(async () => (await s.said())?.build === 101);
  const first = await s.said();
  assert.deepEqual(first.argv, [join(s.app, "101", "main.mjs"), "--more"]);
  assert.deepEqual([first.electron, first.extra], ["1", "x"]);
  assert.deepEqual(readdirSync(join(s.app, "101")).sort(), ["lib", "main.mjs", "module.json"]);
  await until(() => s.state().ran === 101);
  assert.deepEqual(s.state(), { package: "fake", current: 101, previous: null, ran: 101, failed: [] });
  assert.deepEqual(r.asked.slice(0, 2), ["/releases/modules/fake/fake-beta.json", "/releases/modules/fake/fake-0.1.101.tar.gz"]);
  assert.deepEqual(s.packages.get("en"), [{ id: "module:fake", name: "Module fake", installed: true, version: "0.1.101", latest: "0.1.101", newer: false, downgrade: false, updatable: true, state: "idle" }]);

  // A newer build: installed when the packages are read, and run in place of the one before (kept).
  packFake(r.dir, 102);
  await s.packages.read();
  await until(async () => (await s.said())?.build === 102);
  assert.deepEqual({ ...s.state(), ran: null }, { package: "fake", current: 102, previous: 101, ran: null, failed: [] });
  await until(() => s.state().ran === 102);
  assert.deepEqual(readdirSync(s.app).sort(), ["101", "102", "state.json"]);

  // One that ends before it answers, again and again: the one before it is gone back to, and not taken again.
  packFake(r.dir, 103, { crash: true });
  await s.packages.read();
  assert.equal(s.state().current, 103);
  assert.deepEqual(readdirSync(s.app).sort(), ["102", "103", "state.json"]);
  await until(() => s.state().current === 102);
  assert.deepEqual(s.state(), { package: "fake", current: 102, previous: null, ran: 102, failed: [103] });
  assert.equal(existsSync(join(s.app, "103")), false);
  await until(async () => (await s.said())?.build === 102);
  const line = s.packages.get("en")[0]!;
  assert.deepEqual([line.version, line.state, line.message], ["0.1.102", "failed", "0.1.103 didn't start; back on 0.1.102"]);
  const asked = r.asked.length;
  await s.packages.read();
  assert.equal(s.state().current, 102);
  assert.deepEqual(r.asked.slice(asked), ["/releases/modules/fake/fake-beta.json"], "the archive not fetched again");

  // Named no more: ended; what is installed stays for when it is named again.
  s.config.update((raw) => (raw.modules = []));
  await until(() => s.modules.get("fake") === undefined);
  assert.equal(s.state().current, 102);
  assert.deepEqual(s.packages.get("en"), []);
});

test("a package not taken: a key it does not take, words not this module's release, bytes not the ones signed", async (t) => {
  const r = await releases(t);
  const s = station(t, r.base, { run: false });
  s.packages.named(named);
  const refused = async (why: RegExp) => {
    await assert.rejects(s.packages.update("module:fake", "en"), why);
    assert.equal(s.state().current, null);
    assert.equal(existsSync(s.app) && readdirSync(s.app).length > 0, false, "nothing installed");
  };
  await refused(/fake-beta\.json: 404/);
  feedOf(r.dir, 101, { key: OTHER });
  await refused(/signature couldn't be verified.*a key this station does not take/);
  feedOf(r.dir, 101, { words: { kind: "stillfail-station-release" } });
  await refused(/signature couldn't be verified.*not a module release/);
  feedOf(r.dir, 101, { words: { id: "other" } });
  await refused(/signature couldn't be verified.*the module other, not fake/);
  // The archive changed after it was signed: other bytes of the same size, then more of them.
  const archive = feedOf(r.dir, 101);
  writeFileSync(join(r.dir, "modules/fake/fake-0.1.101.tar.gz"), Buffer.from(archive).fill(7, 100, 110));
  await refused(/isn't the one signed/);
  writeFileSync(join(r.dir, "modules/fake/fake-0.1.101.tar.gz"), Buffer.concat([archive, Buffer.alloc(10)]));
  await refused(/isn't the one signed/);
  // Signed, but no package: a path out of it.
  const evil = Buffer.from(writeArchive([{ path: "module.json", bytes: Buffer.from('{"entry":"main.mjs"}') }]));
  feedOf(r.dir, 101, { archive: evil });
  await refused(/can't be opened.*no entry/);
  const line = s.packages.get("en")[0]!;
  assert.deepEqual([line.installed, line.state, line.latest], [false, "failed", "0.1.101"]);
  // Fine at last.
  feedOf(r.dir, 101);
  await s.packages.update("module:fake", "en");
  assert.equal(s.state().current, 101);
});

test("a package for a newer station waits for it; one older than what came up is never run again", async (t) => {
  const r = await releases(t);
  let channel: "beta" | "stable" = "beta";
  const s = station(t, r.base, { station: 150, run: false, channel: () => channel });
  s.packages.named(named);
  feedOf(r.dir, 105, { needsStation: 151 });
  await assert.rejects(s.packages.update("module:fake", "en"), /0\.1\.105 needs station 0\.1\.151 or newer \(this one is 0\.1\.150\)/);
  assert.equal(s.state().current, null);
  const waiting = s.packages.get("en")[0]!;
  assert.deepEqual([waiting.note, waiting.updatable, waiting.newer], ["0.1.105 needs station 0.1.151 or newer (this one is 0.1.150); update the station first", false, true]);
  feedOf(r.dir, 105, { needsStation: 150 });
  await s.packages.update("module:fake", "en");
  assert.equal(s.packages.get("en")[0]!.note, undefined);
  s.packages.up({ id: "fake", command: process.execPath, args: [], env: {}, installed: { package: "fake", build: 105 } });
  assert.equal(s.state().ran, 105);

  // Back on the stable channel, whose release is older: not taken (its code may not read what 105 wrote).
  channel = "stable";
  feedOf(r.dir, 104, { channel: "stable" });
  await s.packages.update("module:fake", "en");
  assert.deepEqual(s.state(), { package: "fake", current: 105, previous: null, ran: 105, failed: [] });
  const line = s.packages.get("en")[0]!;
  assert.deepEqual([line.version, line.latest, line.newer, line.downgrade], ["0.1.105", "0.1.104", false, false]);
  // Nor gone back to an older one after a newer came up: 106 came up, ended later; 105 is not run again.
  channel = "beta";
  feedOf(r.dir, 106);
  await s.packages.update("module:fake", "en");
  const spec = { id: "fake", command: process.execPath, args: [], env: {}, installed: { package: "fake", build: 106 } };
  s.packages.up(spec);
  for (let i = 0; i < 5; i++) assert.equal(s.packages.down(spec), false);
  assert.equal(s.state().current, 106);
});

test("the station's updates read the packages with the rest, a line each after them, updated by their id", async (t) => {
  const r = await releases(t);
  const s = station(t, r.base, { run: false });
  feedOf(r.dir, 101);
  s.packages.named(named);
  const app = join(s.data, "app");
  mkdirSync(app);
  writeFileSync(join(app, "BUILD"), "150");
  const updates = new Updates({ app, data: s.data, config: s.config, origin: () => "http://127.0.0.1:1", registry: "http://127.0.0.1:1", env: { PATH: "/nowhere" }, trusted });
  t.after(() => updates.close());
  let told = 0;
  updates.changes(() => told++);
  const leave = updates.add(s.packages);
  assert.ok(told > 0);
  // The station before this one is gone (told a tick after the packages are made): until then they are not read.
  await new Promise((r) => setImmediate(r));
  await updates.check();
  const lines = updates.get("en");
  assert.equal(lines[0]!.id, "station");
  const module = lines.at(-1)!;
  assert.deepEqual([module.id, module.installed, module.version, typeof module.checkedAt], ["module:fake", true, "0.1.101", "number"]);
  feedOf(r.dir, 102);
  await updates.update("module:fake", "en");
  assert.equal(updates.get("en").at(-1)!.version, "0.1.102");
  await assert.rejects(updates.update("module:other", "en"), /No item module:other/);
  leave();
  assert.equal(updates.get("en").some((l) => l.id.startsWith("module:")), false);
});

test("the media service, packed as CI packs it (one bundled main.mjs), installed and run as module media", async (t) => {
  const r = await releases(t);
  pack(MEDIA, r.dir, { beta: true, build: 3600, unsignedOk: false, env: { ...process.env, CI: "", RELEASE_SIGNING_KEY: KEY.pem } });
  const s = station(t, r.base, { station: 4000, modules: [{ id: "media", package: "media" }] });
  await until(() => s.modules.get("media")?.running === true);
  const at = s.packages.appOf("media");
  assert.deepEqual(readInstalled(at).current, 3600);
  assert.deepEqual(readdirSync(join(at, "3600")).sort(), ["main.mjs", "module.json"]);
  assert.equal(JSON.parse(readFileSync(join(at, "3600", "module.json"), "utf8")).entry, "main.mjs");
  assert.deepEqual(s.modules.get("media")!.spec.args, [join(at, "3600", "main.mjs")]);
  // Its data where it always was, beside the code.
  await until(() => existsSync(join(s.data, "modules", "media", "media.db")));
});
