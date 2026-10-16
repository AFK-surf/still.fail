// The drive's protected folders through still.fail Helper (src/drive/fs.ts, src/helper/files.ts; docs/drive.md): which
// path goes through the helper, the bytes streamed both ways, what the station checks before asking and what the helper
// is told, a grant missing (the window, once an attempt), and the helper ending in the middle of a read. The helper is a
// fake in this process, speaking native/helper's `files.*` as Files.swift does, on the real file system; whether the
// station "may open" a protected folder itself is given (`readable`), as only macOS's privacy protection refuses it.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { chmodSync, closeSync, existsSync, fstatSync, fsyncSync, ftruncateSync, lstatSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync, writeSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { routes } from "../src/api/routes/drive.ts";
import type { Request } from "../src/api/request.ts";
import { Drive, DriveError } from "../src/drive/drive.ts";
import { protectedTop } from "../src/drive/fs.ts";
import { HELPER_APP, HelperApp } from "../src/helper/app.ts";
import { HelperFiles } from "../src/helper/files.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { WINDOWS } from "../src/platform/index.ts";

const within = (p: string, d: string) => d === "/" || p === d || p.startsWith(`${d}/`);

/// still.fail Helper's `files.*` (Files.swift) in this process: the roots and what is protected checked again, a folder
/// it has no grant for (`grants`, by top) refused without being touched, a file's bytes in parts of `chunk`. Every
/// request noted (`asked`); `cutAfter`: a read ends after that many bytes (the helper restarted or gone meanwhile);
/// `restartOnce`: the next request answers `restart`, and the helper comes back as another process.
class FakeHelper {
  launches = 0;
  asked: any[] = [];
  shown: any[] = [];
  /// The parts a write's bytes came in.
  parts: number[] = [];
  grants = new Map<string, "granted" | "denied" | "unknown">();
  windowUp = false;
  chunk = 64 * 1024;
  cutAfter: number | null = null;
  restartOnce = false;
  pid = 100;
  #server: net.Server | null = null;
  #where: { path: string; token: string } | null = null;
  #conns = new Set<net.Socket>();
  #watches = new Set<net.Socket>();

  readonly home: string;

  constructor(home: string) {
    this.home = home;
  }

  launch = async (_app: string, env: Record<string, string>) => {
    this.launches++;
    this.#where = { path: env.STILLFAIL_HELPER_SOCKET!, token: env.STILLFAIL_HELPER_TOKEN! };
    await this.#listen();
  };
  async #listen() {
    rmSync(this.#where!.path, { force: true });
    const server = net.createServer((c) => this.#serve(c));
    await new Promise<void>((resolve) => server.listen(this.#where!.path, resolve));
    this.#server = server;
  }
  /// It ends (a crash, macOS's Quit & Reopen): its socket gone, every connection with it.
  crash() {
    this.#server?.close();
    this.#server = null;
    if (this.#where) rmSync(this.#where.path, { force: true });
    for (const c of this.#conns) c.destroy();
  }
  close() {
    this.crash();
  }
  /// Its window saw a grant change: told on the station's watch.
  tell() {
    for (const w of this.#watches) w.write(`${JSON.stringify({ event: "grants" })}\n`);
  }

  #top(path: string): { top: string; grant: string } | null {
    for (const [name, grant] of [["Documents", "documents"], ["Desktop", "desktop"], ["Downloads", "downloads"]] as const) {
      const top = join(this.home, name);
      if (within(path, top)) return { top, grant };
    }
    return null;
  }
  #state(grant: string) {
    return this.grants.get(grant) ?? "unknown";
  }
  /// Refused unless it may open what keeps `path`, as Files.swift's guardGrant.
  #guard(path: string) {
    const at = this.#top(path);
    if (at && this.#state(at.grant) !== "granted") throw { code: "grant", error: "no grant", grant: at.grant, state: this.#state(at.grant), top: at.top };
  }
  #real(path: string): string {
    this.#guard(path);
    try {
      return realpathSync(path);
    } catch {
      const parent = dirname(path);
      return parent === path ? path : join(this.#real(parent), path.slice(parent.length + (parent === "/" ? 0 : 1)));
    }
  }
  #place(ask: any, key = "path", entry = false): string {
    const asked: string = ask[key];
    if (typeof asked !== "string" || !asked.startsWith("/") || asked.split("/").some((p) => p === ".." || p === ".")) throw { code: "outside", error: "a clean path" };
    const roots: string[] = ask.roots ?? [];
    if (!roots.some((r) => within(asked, r))) throw { code: "outside", error: "not under a root" };
    const protect: string[] = ask.protect ?? [];
    if (protect.some((p) => within(asked, p))) throw { code: "protected", error: "the station's own" };
    const found = entry ? join(this.#real(dirname(asked)), asked.split("/").at(-1)!) : this.#real(asked);
    if (!roots.some((r) => within(found, r) || within(found, this.#real(r)))) throw { code: "outside", error: "leads out" };
    if (protect.some((p) => within(found, p))) throw { code: "protected", error: "the station's own" };
    return found;
  }
  #stat(s: import("node:fs").Stats) {
    return { dir: s.isDirectory(), file: s.isFile(), link: s.isSymbolicLink(), size: s.isDirectory() ? 0 : s.size, mtime: s.mtimeMs };
  }

  #serve(conn: net.Socket) {
    this.#conns.add(conn);
    conn.on("close", () => (this.#conns.delete(conn), this.#watches.delete(conn)));
    conn.on("error", () => {});
    let carry = Buffer.alloc(0);
    let body: ((chunk: Buffer) => void) | null = null;
    const line = (v: unknown) => conn.write(`${JSON.stringify(v)}\n`);
    conn.on("data", (chunk: Buffer) => {
      if (body) return body(chunk);
      carry = Buffer.concat([carry, chunk]);
      const at = carry.indexOf(10);
      if (at < 0) return;
      const ask = JSON.parse(carry.subarray(0, at).toString());
      const rest = carry.subarray(at + 1);
      if (ask.token !== this.#where!.token) return void conn.end(`${JSON.stringify({ error: "not the station's token" })}\n`);
      if (ask.op !== "hello") this.asked.push(ask);
      try {
        switch (ask.op) {
          case "hello":
            return void conn.end(`${JSON.stringify({ ok: true, v: 1, pid: this.pid })}\n`);
          case "watch":
            this.#watches.add(conn);
            return void line({ ok: true });
          case "quit":
            conn.end(`${JSON.stringify({ ok: true })}\n`);
            return this.crash();
          case "status":
            return void conn.end(`${JSON.stringify({ capture: true, control: true, asking: this.windowUp, asked: this.windowUp ? this.shown.at(-1).grants : [] })}\n`);
          case "permissions.show":
            this.shown.push(ask);
            this.windowUp = true;
            return void conn.end(`${JSON.stringify({ ok: true })}\n`);
        }
        if (this.restartOnce) {
          this.restartOnce = false;
          const was = this.pid;
          conn.end(`${JSON.stringify({ error: "starting again", code: "restart", pid: was })}\n`);
          // Started again a moment later, another process.
          this.crash();
          setTimeout(() => void this.#listen().then(() => (this.pid = was + 1)), 30);
          return;
        }
        switch (ask.op) {
          case "files.access":
            return void conn.end(`${JSON.stringify({ access: ask.paths.map((p: string) => { const at = this.#top(p); return at ? { path: p, top: at.top, grant: at.grant, state: this.#state(at.grant) } : { path: p, grant: null, state: "granted" }; }) })}\n`);
          case "files.list": {
            const dir = this.#place(ask);
            const names = readdirSync(dir);
            const entries = names.slice(0, ask.most).map((name) => {
              const path = join(dir, name);
              const l = lstatSync(path);
              if (!l.isSymbolicLink()) return { ...this.#stat(l), name, link: false, real: path };
              try {
                const real = this.#real(path);
                if (!(ask.roots as string[]).some((r) => within(real, r))) return { name, link: true, gone: true };
                return { ...this.#stat(statSync(real)), name, link: true, real };
              } catch {
                return { name, link: true, gone: true };
              }
            });
            return void conn.end(`${JSON.stringify({ entries, more: names.length > entries.length })}\n`);
          }
          case "files.names":
            return void conn.end(`${JSON.stringify({ names: readdirSync(this.#place(ask)) })}\n`);
          case "files.stat": {
            const at = this.#place(ask, "path", ask.follow === false);
            return void conn.end(`${JSON.stringify(this.#stat(ask.follow === false ? lstatSync(at) : statSync(at)))}\n`);
          }
          case "files.real":
            return void conn.end(`${JSON.stringify({ path: this.#place(ask) })}\n`);
          case "files.read": {
            const at = this.#place(ask);
            const s = statSync(at);
            if (s.isDirectory()) throw { code: "EISDIR", error: "a folder" };
            const want = Math.max(0, Math.min(ask.length, s.size - ask.offset));
            line({ size: s.size, mtime: s.mtimeMs, length: want });
            const bytes = readFileSync(at).subarray(ask.offset, ask.offset + want);
            const cut = this.cutAfter;
            let sent = 0;
            // Part after part, each once the socket took the one before.
            const next = () => {
              if (sent >= bytes.length || conn.destroyed) return void conn.end();
              if (cut !== null && sent >= cut) return void conn.destroy();
              const part = bytes.subarray(sent, sent + this.chunk);
              sent += part.length;
              if (conn.write(part)) setImmediate(next);
              else conn.once("drain", next);
            };
            return next();
          }
          case "files.write": {
            const at = this.#place(ask);
            const fd = openSync(at, ask.create ? "w" : "r+");
            line({ size: fstatSync(fd).size });
            let done = 0;
            const end = () => {
              if (ask.truncate !== undefined) ftruncateSync(fd, ask.truncate);
              if (ask.sync) fsyncSync(fd);
              const size = fstatSync(fd).size;
              closeSync(fd);
              conn.end(`${JSON.stringify({ size })}\n`);
            };
            conn.on("close", () => {
              try {
                closeSync(fd);
              } catch {}
            });
            body = (part: Buffer) => {
              this.parts.push(part.length);
              writeSync(fd, part, 0, part.length, ask.offset + done);
              done += part.length;
              if (done >= ask.length) end();
            };
            if (ask.length === 0) return end();
            if (rest.length > 0) body(rest);
            return;
          }
          case "files.mkdir":
            mkdirSync(this.#place(ask, "path", true), { recursive: ask.recursive });
            return void conn.end("{}\n");
          case "files.rename":
            renameSync(this.#place(ask, "from", true), this.#place(ask, "to", true));
            return void conn.end("{}\n");
          case "files.remove":
            rmSync(this.#place(ask, "path", true), { recursive: true });
            return void conn.end("{}\n");
          case "files.trash": {
            const at = this.#place(ask, "path", true);
            mkdirSync(join(this.home, ".Trash"), { recursive: true });
            const to = join(this.home, ".Trash", at.split("/").at(-1)!);
            renameSync(at, to);
            return void conn.end(`${JSON.stringify({ to })}\n`);
          }
          case "files.unlink":
            unlinkSync(this.#place(ask, "path", true));
            return void conn.end("{}\n");
        }
      } catch (e: any) {
        const answer = e?.code && e?.error ? e : { error: String(e?.message ?? e), code: e?.code ?? "EIO" };
        return void conn.end(`${JSON.stringify(answer)}\n`);
      }
    });
  }
}

/// A machine: a home with Documents (a pinned project in it, the station's data in it too), the helper's release, a
/// drive with the helper, and which protected folders the station may not open itself (`locked`).
function machine() {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "drive-helper-")));
  const home = join(base, "home");
  const docs = join(home, "Documents");
  const project = join(docs, "project");
  const data = join(docs, ".stillfail");
  mkdirSync(join(project, "Season 1"), { recursive: true });
  mkdirSync(data, { recursive: true });
  mkdirSync(join(home, "Movies"), { recursive: true });
  writeFileSync(join(data, "key"), "secret");
  writeFileSync(join(project, "notes.md"), "# hello\n");
  writeFileSync(join(project, "Season 1", "E2.mp4"), "two");
  writeFileSync(join(project, "Season 1", "E10.mp4"), "ten");
  writeFileSync(join(home, "Movies", "film.mp4"), "film");
  writeFileSync(join(base, "outside.txt"), "out");
  // The release's helper app (its code files only), installed under the station's data.
  const app = join(base, "release", HELPER_APP);
  mkdirSync(join(app, "Contents/MacOS"), { recursive: true });
  mkdirSync(join(app, "Contents/_CodeSignature"), { recursive: true });
  writeFileSync(join(app, "Contents/MacOS/stillfail-helper"), "code");
  writeFileSync(join(app, "Contents/Info.plist"), "<plist/>");
  writeFileSync(join(app, "Contents/_CodeSignature/CodeResources"), "signed");
  const fake = new FakeHelper(home);
  fake.grants.set("documents", "granted");
  const helper = new HelperApp({ app, dir: join(base, "helper"), launch: fake.launch });
  let changed = 0;
  const files = new HelperFiles({ helper, changed: () => changed++, lang: () => "zh" });
  const locked = new Set([docs]);
  const config = { drive: { roots: [project] } } as any;
  const drive = new Drive({ config: () => config, protect: () => [data], files, home, readable: (top) => !locked.has(top) });
  return { base, home, docs, project, data, fake, helper, files, drive, config, locked, changed: () => changed };
}

const code = async (p: Promise<unknown>) => {
  try {
    await p;
  } catch (e) {
    return (e as DriveError).code;
  }
  return "ok";
};

/// Until `what` holds (the helper's answers come on its socket).
const until = async (what: () => boolean) => {
  while (!what()) await new Promise((r) => setImmediate(r));
};

const ops = (fake: FakeHelper) => fake.asked.map((a) => a.op).filter((o) => o.startsWith("files."));

test("which way: a protected folder the station may open is read directly, one it may not through still.fail Helper", { skip: WINDOWS }, async () => {
  const { home, docs, project, fake, drive, locked } = machine();
  // Documents, Desktop, Downloads and the disks are the protected folders, by name, case aside; the rest is not.
  assert.equal(protectedTop(join(project, "notes.md"), home), docs);
  assert.equal(protectedTop(join(home, "documents", "x"), home), docs);
  assert.equal(protectedTop(join(home, "Movies", "film.mp4"), home), null);
  assert.equal(protectedTop("/Volumes/Nope/x", home), null);
  // Readable by the station itself (a station the desktop app runs, with its grant): the helper is not even started.
  locked.clear();
  assert.deepEqual((await drive.list(project, "")).entries.map((e) => e.name), ["Season 1", "notes.md"]);
  assert.equal(fake.launches, 0);
  // Not readable: the same answers, through the helper.
  locked.add(docs);
  const listed = await drive.list(project, "");
  assert.deepEqual(listed.entries.map((e) => [e.name, e.dir, e.type]), [["Season 1", true, ""], ["notes.md", false, "text/markdown; charset=utf-8"]]);
  assert.deepEqual((await drive.list(project, "Season 1")).entries.map((e) => e.name), ["E2.mp4", "E10.mp4"]);
  assert.equal((await drive.read(project, "notes.md", 2, 3)).bytes.toString(), "hel");
  assert.equal((await drive.stat(project, "notes.md")).size, 8);
  assert.equal(fake.launches, 1);
  assert.ok(ops(fake).includes("files.list") && ops(fake).includes("files.read"));
  // A folder outside the protected ones, for a member who reaches every folder: directly, nothing asked of the helper.
  const before = fake.asked.length;
  assert.deepEqual((await drive.list(join(home, "Movies"), "", true)).entries.map((e) => e.name), ["film.mp4"]);
  assert.equal(fake.asked.length, before);
  fake.close();
});

test("changes through the helper: a folder made, renamed, removed; an upload in parts, put in place once whole", { skip: WINDOWS }, async () => {
  const { project, fake, drive } = machine();
  await drive.mkdir(project, "Season 2");
  assert.ok(statSync(join(project, "Season 2")).isDirectory());
  assert.equal(await code(drive.mkdir(project, "Season 2")), "exists");
  await drive.rename(project, "Season 2", "Specials");
  assert.ok(existsSync(join(project, "Specials")) && !existsSync(join(project, "Season 2")));
  const a = await drive.upload(project, "Specials/E1.mp4", "u1", 0, 6, Buffer.from("abc"), false);
  assert.deepEqual([a.have, a.entry], [3, null]);
  assert.equal(existsSync(join(project, "Specials", "E1.mp4")), false);
  // A gap says how much is there; the rest finishes it.
  const gap = await drive.upload(project, "Specials/E1.mp4", "u1", 5, 6, Buffer.from("f"), false).catch((e) => e);
  assert.deepEqual([gap.code, gap.have], ["upload_lost", 3]);
  const b = await drive.upload(project, "Specials/E1.mp4", "u1", 3, 6, Buffer.from("def"), false);
  assert.equal(b.entry?.size, 6);
  assert.equal(readFileSync(join(project, "Specials", "E1.mp4"), "utf8"), "abcdef");
  assert.deepEqual(readdirSync(join(project, "Specials")), ["E1.mp4"]);
  assert.equal(await code(drive.upload(project, "Specials/E9.mp4", "u2", 3, 6, Buffer.from("def"), false)), "upload_lost");
  // Removed: into the trash through the helper (macOS's own there), or for good when asked.
  await drive.remove(project, "Specials");
  assert.equal(existsSync(join(project, "Specials")), false);
  assert.ok(existsSync(join(fake.home, ".Trash", "Specials", "E1.mp4")));
  await drive.mkdir(project, "Gone");
  await drive.remove(project, "Gone", false, true);
  assert.equal(existsSync(join(project, "Gone")), false);
  assert.ok(["files.write", "files.rename", "files.trash", "files.remove"].every((o) => ops(fake).includes(o)));
  fake.close();
});

test("a file's bytes stream over the helper's socket both ways, in parts, never asked for whole", { skip: WINDOWS }, async () => {
  const { base, project, fake, drive } = machine();
  const big = randomBytes(3 * 1024 * 1024 + 123);
  writeFileSync(join(project, "big.bin"), big);
  // A read of 8 MB at most comes in the helper's parts.
  const read = await drive.read(project, "big.bin", 1000, 8 * 1024 * 1024);
  assert.equal(read.total, big.length);
  assert.ok(read.bytes.equals(big.subarray(1000)));
  assert.equal(fake.asked.filter((a) => a.op === "files.read").at(-1).length, 8 * 1024 * 1024);
  // An upload's part goes as the socket takes it.
  const part = randomBytes(2 * 1024 * 1024);
  await drive.upload(project, "up.bin", "u3", 0, part.length, part, false);
  assert.ok(readFileSync(join(project, "up.bin")).equals(part));
  assert.ok(fake.parts.length > 1, `in parts (${fake.parts.length})`);
  // Sent in a chat: copied into the station's uploads as it comes.
  const uploads = join(base, "uploads");
  mkdirSync(uploads);
  const staged = await drive.stage(project, "big.bin", (name) => ({ safe: name, path: join(uploads, name) }), 1 << 30);
  assert.equal(staged.size, big.length);
  assert.ok(readFileSync(join(uploads, "big.bin")).equals(big));
  fake.close();
});

test("the station checks a path before the helper is asked; the helper is told the roots and what is protected", { skip: WINDOWS }, async () => {
  const { base, docs, project, data, fake, drive, config } = machine();
  symlinkSync(join(base, "outside.txt"), join(project, "out-link"));
  symlinkSync(join(project, "notes.md"), join(project, "in-link"));
  // `..` refused before anything is asked.
  assert.equal(await code(drive.read(project, "../.stillfail/key", 0, 10)), "path_escape");
  assert.equal(fake.launches, 0);
  // A link out of a pinned folder is not followed for a read-only member (found through the helper), nor listed.
  assert.equal(await code(drive.read(project, "out-link", 0, 10)), "path_escape");
  assert.equal(fake.asked.some((a) => a.op === "files.read"), false);
  assert.equal((await drive.read(project, "in-link", 0, 100)).bytes.toString(), "# hello\n");
  assert.deepEqual((await drive.list(project, "")).entries.map((e) => e.name), ["Season 1", "in-link", "notes.md"]);
  // The helper is told the pinned folder as its root, and the station's own data.
  const told = fake.asked.find((a) => a.op === "files.list");
  assert.deepEqual(told.roots, [project]);
  assert.ok(told.protect.includes(data));
  // A member who reaches every folder: the protected folder is the root it is told; the station's data is refused here
  // first, never asked of the helper.
  config.drive.roots.push(docs);
  const reads = fake.asked.filter((a) => a.op === "files.read").length;
  assert.equal(await code(drive.read(docs, ".stillfail/key", 0, 10, true)), "protected");
  assert.equal(fake.asked.filter((a) => a.op === "files.read").length, reads);
  assert.deepEqual((await drive.list(docs, "", true)).entries.map((e) => e.name), ["project"]);
  assert.deepEqual(fake.asked.filter((a) => a.op === "files.list").at(-1).roots, [docs]);
  // The helper refuses on its own what it was not told (asked outside its roots): the drive's path_escape.
  const fs = (drive as any).deps.files.fs({ roots: [project], protect: [data] });
  await assert.rejects(fs.read(join(base, "outside.txt"), 0, 10), (e: any) => e.code === "outside");
  await assert.rejects(fs.stat(join(data, "key")), (e: any) => e.code === "outside" || e.code === "protected");
  fake.close();
});

test("without the grant: refused saying so, the helper's window up on that Mac once, readable as soon as it is given", { skip: WINDOWS }, async () => {
  const { project, fake, drive, changed } = machine();
  fake.grants.set("documents", "unknown");
  // The root, looked at in the background (told once it is known): unreadable while the helper may not open it.
  assert.equal(drive.roots()[0]!.state, "unreadable");
  await until(() => changed() > 0);
  assert.equal(drive.roots()[0]!.state, "unreadable");
  assert.ok(fake.asked.some((a) => a.op === "files.access"));
  // A person opens it: refused, the window up asking for Documents, in the station's words.
  const e = (await drive.list(project, "").catch((x) => x)) as DriveError;
  assert.equal(e.code, "permission");
  assert.deepEqual(e.need, { grant: "documents", top: join(fake.home, "Documents"), asking: true });
  assert.equal(fake.shown.length, 1);
  assert.deepEqual(fake.shown[0].grants, ["documents"]);
  assert.equal(fake.shown[0].words.title, "允许 still.fail 打开这台 Mac 上的文件夹");
  assert.equal(fake.shown[0].paths.documents, join(fake.home, "Documents"));
  // Read again while it is up (a page reads a folder again): not put up again.
  await assert.rejects(drive.list(project, "Season 1"));
  assert.equal(fake.shown.length, 1);
  // As the route says it, in the asker's language.
  const table = routes({ drive, config: new ConfigFile(join(fake.home, "config.json")) });
  const r: Request = { method: "GET", path: "/drive/list", query: [["root", project], ["path", ""]], headers: {}, body: Buffer.alloc(0), viewer: { sub: "u", email: "a@x", name: "A", role: "viewer", workspace: "w", device: "d" }, lang: "en" };
  const answer = await table.find((x) => x.pattern.test("/drive/list"))!.handle(r, []);
  assert.equal(answer.status, 403);
  assert.deepEqual(JSON.parse((answer.body as Buffer).toString()), { error: "This Mac hasn't let still.fail Helper open “Documents” yet. A window is up on that Mac: click Allow there and it opens.", code: "permission" });
  // Granted in the window: the helper says so on the station's watch, the roots are told again, and it opens.
  const told = changed();
  fake.grants.set("documents", "granted");
  fake.windowUp = false;
  fake.tell();
  await until(() => changed() > told);
  assert.equal(drive.roots()[0]!.state, "ok");
  assert.deepEqual((await drive.list(project, "")).entries.map((e) => e.name), ["Season 1", "notes.md"]);
  fake.close();
});

test("the helper ending in the middle of a read: a clean refusal, and the next read works", { skip: WINDOWS }, async () => {
  const { project, fake, drive } = machine();
  const big = randomBytes(1024 * 1024);
  writeFileSync(join(project, "big.bin"), big);
  // It is restarted (or gone) after a part: the read is refused, nothing half given.
  fake.cutAfter = 128 * 1024;
  assert.equal(await code(drive.read(project, "big.bin", 0, big.length)), "io");
  fake.cutAfter = null;
  assert.ok((await drive.read(project, "big.bin", 0, big.length)).bytes.equals(big));
  // Gone altogether: started again for the next request.
  fake.cutAfter = 64 * 1024;
  const reading = drive.read(project, "big.bin", 0, big.length);
  const failed = await code(reading);
  fake.crash();
  fake.cutAfter = null;
  assert.equal(failed, "io");
  assert.ok((await drive.read(project, "big.bin", 0, big.length)).bytes.equals(big));
  assert.equal(fake.launches, 2);
  // Granted since it started: it starts again by itself, and is asked once more.
  fake.restartOnce = true;
  assert.equal((await drive.read(project, "notes.md", 0, 100)).bytes.toString(), "# hello\n");
  assert.equal(fake.launches, 2);
  fake.close();
});

test("the station's own permission errors stay as they were where there is no helper", { skip: WINDOWS || process.getuid?.() === 0 }, async () => {
  const { docs, project, fake } = machine();
  const config = { drive: { roots: [project] } } as any;
  const drive = new Drive({ config: () => config, protect: () => [] });
  chmodSync(docs, 0o000);
  try {
    assert.equal(drive.roots()[0]!.state, "unreadable");
    assert.equal(await code(drive.list(project, "")), "permission");
  } finally {
    chmodSync(docs, 0o755);
  }
  assert.equal(fake.launches, 0);
  fake.close();
});
