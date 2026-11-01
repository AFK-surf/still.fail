// The station's drive (src/drive/drive.ts, api/routes/drive.ts): the roots it names, a path staying in its root (`..`,
// links out, the station's own data), listings, parts of files read and written, and who may change what.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { Drive, DriveError } from "../src/drive/drive.ts";
import { routes } from "../src/api/routes/drive.ts";
import { ConfigFile } from "../src/ops/config.ts";
import type { Request } from "../src/api/request.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { platform } from "../src/platform/index.ts";

function place() {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "drive-")));
  const root = join(base, "root");
  const data = join(root, ".stillfail");
  mkdirSync(join(root, "Season 1"), { recursive: true });
  mkdirSync(data, { recursive: true });
  writeFileSync(join(data, "key"), "secret");
  writeFileSync(join(root, "Season 1", "E10.mp4"), "ten");
  writeFileSync(join(root, "Season 1", "E2.mp4"), "two");
  writeFileSync(join(root, "Season 1", "e1.mp4"), "one");
  writeFileSync(join(root, "notes.md"), "# hello\n");
  writeFileSync(join(base, "outside.txt"), "out");
  const config = { drive: { roots: [root] } } as any;
  // What is deleted goes to this place's own trash, not the machine's.
  const drive = new Drive({ config: () => config, protect: () => [data], home: base });
  return { base, root, data, config, drive };
}

/// What every member is told the drive does here: deleting to the trash (where there is one), watching folders,
/// copying into it (routes/transfers.ts).
const CAN = { ...(platform.trash ? { trash: true } : {}), watch: true, transfers: true };

const code = async (p: Promise<unknown>) => {
  try {
    await p;
  } catch (e) {
    return (e as DriveError).code;
  }
  return "ok";
};

test("list: folders first, names by their numbers; the station's own data left out", async () => {
  const { root, drive } = place();
  const top = await drive.list(root, "");
  assert.deepEqual(top.entries.map((e) => [e.name, e.dir]), [["Season 1", true], ["notes.md", false]]);
  assert.equal(top.entries[1].type, "text/markdown; charset=utf-8");
  const season = await drive.list(root, "Season 1");
  assert.deepEqual(season.entries.map((e) => e.name), ["e1.mp4", "E2.mp4", "E10.mp4"]);
  assert.equal(season.entries[0].type, "video/mp4");
  assert.equal(season.path, "Season 1");
});

test("a path stays in its root: `..`, a link out, the station's data, a root not named", async () => {
  const { base, root, drive } = place();
  symlinkSync(join(base, "outside.txt"), join(root, "out-link"));
  symlinkSync(join(root, "notes.md"), join(root, "in-link"));
  assert.equal(await code(drive.read(root, "../outside.txt", 0, 10)), "path_escape");
  assert.equal(await code(drive.read(root, "Season 1/../../outside.txt", 0, 10)), "path_escape");
  assert.equal(await code(drive.read(root, "out-link", 0, 10)), "path_escape");
  assert.equal(await code(drive.read(root, ".stillfail/key", 0, 10)), "protected");
  assert.equal(await code(drive.list(base, "")), "not_a_root");
  // A link within the root is followed; one out is not listed.
  assert.equal((await drive.read(root, "in-link", 0, 100)).bytes.toString(), "# hello\n");
  assert.deepEqual((await drive.list(root, "")).entries.map((e) => e.name), ["Season 1", "in-link", "notes.md"]);
});

test("read: a part from an offset, none past the end, the whole size told", async () => {
  const { root, drive } = place();
  const part = await drive.read(root, "notes.md", 2, 3);
  assert.equal(part.bytes.toString(), "hel");
  assert.equal(part.total, 8);
  assert.equal((await drive.read(root, "notes.md", 100, 3)).bytes.length, 0);
  assert.equal(await code(drive.read(root, "Season 1", 0, 3)), "is_a_directory");
  assert.equal(await code(drive.read(root, "nothing", 0, 3)), "not_found");
});

test("upload: parts put together beside, the file there only once whole; a gap says how much is there", async () => {
  const { root, drive } = place();
  const a = await drive.upload(root, "Season 1/E3.mp4", "u1", 0, 6, Buffer.from("abc"), false);
  assert.equal(a.have, 3);
  assert.equal(a.entry, null);
  assert.equal(existsSync(join(root, "Season 1", "E3.mp4")), false);
  // Hidden from listings while it is being written.
  assert.deepEqual((await drive.list(root, "Season 1")).entries.map((e) => e.name), ["e1.mp4", "E2.mp4", "E10.mp4"]);
  // A part asked again is written again.
  assert.equal((await drive.upload(root, "Season 1/E3.mp4", "u1", 0, 6, Buffer.from("abc"), false)).have, 3);
  try {
    await drive.upload(root, "Season 1/E3.mp4", "u1", 5, 6, Buffer.from("f"), false);
    assert.fail("a gap is refused");
  } catch (e) {
    assert.equal((e as DriveError).code, "upload_lost");
    assert.equal((e as DriveError).have, 3);
  }
  const done = await drive.upload(root, "Season 1/E3.mp4", "u1", 3, 6, Buffer.from("def"), false);
  assert.equal(done.entry?.size, 6);
  assert.equal(readFileSync(join(root, "Season 1", "E3.mp4"), "utf8"), "abcdef");
  assert.deepEqual(readdirSync(join(root, "Season 1")).filter((n) => n.startsWith(".")), []);
  // There already: replaced only when asked.
  assert.equal(await code(drive.upload(root, "notes.md", "u2", 0, 1, Buffer.from("x"), false)), "exists");
  await drive.upload(root, "notes.md", "u3", 0, 1, Buffer.from("x"), true);
  assert.equal(readFileSync(join(root, "notes.md"), "utf8"), "x");
  // An empty file is one part of nothing.
  assert.equal((await drive.upload(root, "empty.txt", "u4", 0, 0, Buffer.alloc(0), false)).entry?.size, 0);
  assert.equal(await code(drive.upload(root, "x.txt", "../bad", 0, 1, Buffer.from("x"), false)), "invalid_request");
});

test("mkdir, rename, remove: within the root, nothing replaced, the root itself kept", async () => {
  const { root, drive } = place();
  assert.equal((await drive.mkdir(root, "Season 2/extras")).dir, true);
  assert.equal(await code(drive.mkdir(root, "Season 2")), "exists");
  assert.equal((await drive.rename(root, "notes.md", "Season 2/notes.md")).name, "notes.md");
  assert.equal(existsSync(join(root, "Season 2", "notes.md")), true);
  assert.equal(await code(drive.rename(root, "Season 2/notes.md", "Season 1/E2.mp4")), "exists");
  assert.equal(await code(drive.rename(root, "Season 2", "Season 2/extras/in")), "invalid_request");
  assert.equal(await code(drive.rename(root, "Season 2", "../away")), "path_escape");
  await drive.remove(root, "Season 2");
  assert.equal(existsSync(join(root, "Season 2")), false);
  assert.equal(await code(drive.remove(root, "")), "invalid_request");
  assert.equal(await code(drive.remove(root, ".stillfail")), "protected");
  assert.equal(existsSync(join(root, ".stillfail", "key")), true);
});

test("remove puts it in the trash, a name there taken given a number, as the machine's file browser does; for good on asking", async () => {
  const { base, root, drive } = place();
  if (platform.trash === null) return;
  const trash = platform.trash === "finder" ? join(base, ".Trash") : join(base, ".local", "share", "Trash", "files");
  writeFileSync(join(root, "a.txt"), "1");
  await drive.remove(root, "a.txt");
  writeFileSync(join(root, "a.txt"), "2");
  await drive.remove(root, "a.txt");
  assert.equal(existsSync(join(root, "a.txt")), false);
  assert.equal(readFileSync(join(trash, "a.txt"), "utf8"), "1");
  assert.equal(readFileSync(join(trash, "a 2.txt"), "utf8"), "2");
  if (platform.trash === "freedesktop") assert.match(readFileSync(join(trash, "..", "info", "a 2.txt.trashinfo"), "utf8"), /^\[Trash Info\]\nPath=.*a\.txt\nDeletionDate=/);
  await drive.remove(root, "Season 1", false, true);
  assert.equal(existsSync(join(root, "Season 1")), false);
  assert.equal(existsSync(join(trash, "Season 1")), false);
});

test("a folder zipped to download: read from its own place as any file of the drive is, by a member who may write", async () => {
  const { root, drive } = place();
  const zip = await drive.zip(root, "Season 1", 1 << 20, true);
  assert.equal(zip.name, "Season 1.zip");
  const read = await drive.read(zip.root, zip.path, 0, 4, true);
  assert.deepEqual([...read.bytes.subarray(0, 4)], [0x50, 0x4b, 0x03, 0x04]);
  assert.equal(await code(drive.zip(root, "notes.md", 1 << 20, true)), "not_a_directory");
});

test("a folder watched: told once something in it changes, a change between two askings not lost", async () => {
  const { FolderWatches } = await import("../src/drive/watch.ts");
  const { root, drive } = place();
  const watches = new FolderWatches(1500, 5000);
  const dir = await drive.folderToWatch(root, "Season 1");
  // The first asking starts the watch (macOS may tell of the writes just before it); then nothing changes.
  await watches.changed(dir, "c");
  assert.equal(await watches.changed(dir, "c"), false);
  const asked = watches.changed(dir, "c");
  setTimeout(() => writeFileSync(join(root, "Season 1", "E3.mp4"), "three"), 100);
  assert.equal(await asked, true);
  // Between two askings: kept for the next.
  writeFileSync(join(root, "Season 1", "E4.mp4"), "four");
  await new Promise((r) => setTimeout(r, 600));
  const started = Date.now();
  assert.equal(await watches.changed(dir, "c"), true);
  assert.ok(Date.now() - started < 500);
  watches.close();
  assert.equal(await code(drive.folderToWatch(root, "notes.md")), "not_a_directory");
});

test("a link removed is the link, not what it points at", async () => {
  const { root, drive } = place();
  symlinkSync(join(root, "Season 1"), join(root, "shortcut"));
  await drive.remove(root, "shortcut");
  assert.equal(existsSync(join(root, "Season 1", "E2.mp4")), true);
});

function request(method: string, path: string, query: Record<string, string> = {}, body: unknown = null, role = "member"): Request {
  return {
    method,
    path,
    query: Object.entries(query),
    headers: {},
    body: body === null ? Buffer.alloc(0) : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body)),
    viewer: { sub: "u", email: "a@x", name: "A", role, workspace: "w", device: "d" },
    lang: "en",
  };
}

async function ask(table: ReturnType<typeof routes>, r: Request) {
  const route = table.find((x) => x.method === r.method && x.pattern.test(r.path))!;
  const a = await route.handle(r, []);
  const b = a.body as Buffer;
  return { status: a.status, headers: a.headers, body: b, json: a.headers["content-type"] === "application/json" ? JSON.parse(b.toString()) : null };
}

test("routes: a folder another file system is mounted on is listed as a disk, not opened", { skip: process.getuid?.() === 0 }, async () => {
  // (2026-11-02: Studio's ~/OrbStack, OrbStack's NFS with its machine stopped: opening it never returned, and the
  // station's thread, listing the home for 浏览文件夹, with it)
  const { base, data } = place();
  const config = new ConfigFile(mkdtempSync(join(tmpdir(), "drive-config-")));
  const mounted = join(base, "OrbStack");
  mkdirSync(mounted);
  // (were it opened, it would be said unreadable)
  chmodSync(mounted, 0);
  try {
    const drive = new Drive({ config: () => config.raw(), protect: () => [data], disk: async (dir) => (dir === mounted ? 2 : 1) });
    const table = routes({ drive, config, home: base, changed: () => {} });
    const listed = await ask(table, request("GET", "/drive/folders", {}, null, "owner"));
    assert.deepEqual(listed.json.entries.find((e: any) => e.name === "OrbStack"), { name: "OrbStack", path: mounted, unreadable: false, disk: true });
  } finally {
    chmodSync(mounted, 0o755);
  }
});

test("routes: folders pinned by any member who may write, kept in config.json; reads with their size", async () => {
  const { base, root, data } = place();
  const configDir = mkdtempSync(join(tmpdir(), "drive-config-"));
  const config = new ConfigFile(configDir);
  let told = 0;
  const drive = new Drive({ config: () => config.raw(), protect: () => [data] });
  const table = routes({ drive, config, home: base, changed: () => told++ });
  assert.deepEqual((await ask(table, request("GET", "/drive"))).json, { roots: [], manage: false, write: true, anywhere: true, home: base, ...CAN, zip: true });
  assert.deepEqual((await ask(table, request("GET", "/drive", {}, null, "viewer"))).json, { roots: [], manage: false, write: false, ...CAN });
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: [root] }, "viewer"))).status, 403);
  assert.equal((await ask(table, request("GET", "/drive/folders", {}, null, "viewer"))).status, 403);
  mkdirSync(join(base, ".hidden"));
  mkdirSync(join(base, "Movies"));
  const picked = await ask(table, request("GET", "/drive/folders", {}, null, "owner"));
  // Hidden folders are left out; each says where it is and whether it can be listed; the way there starts at home.
  assert.deepEqual(picked.json.folders, ["Movies", "root"]);
  assert.deepEqual(picked.json.entries.map((e: any) => [e.name, e.path, e.unreadable]), [["Movies", join(base, "Movies"), false], ["root", root, false]]);
  assert.equal(picked.json.path, base);
  assert.deepEqual(picked.json.crumbs, [{ name: "Home", path: base }]);
  assert.deepEqual(picked.json.places.slice(0, 2).map((p: any) => [p.name, p.path]), [["Home", base], ["Movies", join(base, "Movies")]]);
  const deeper = await ask(table, request("GET", "/drive/folders", { path: join(root, "Season 1") }, null, "owner"));
  assert.deepEqual(deeper.json.crumbs.map((c: any) => c.name), ["Home", "root", "Season 1"]);
  // One outside the home: the way there from the top of its disk, each step a folder.
  const above = await ask(table, request("GET", "/drive/folders", { path: dirname(base) }, null, "owner"));
  assert.deepEqual(above.json.crumbs[0], { name: "/", path: "/" });
  assert.equal(above.json.crumbs.at(-1).path, dirname(base));
  assert.deepEqual(above.json.crumbs.slice(1).map((c: any) => c.path), above.json.crumbs.slice(1).map((c: any, i: number) => join(above.json.crumbs[i].path, c.name)));
  // One the station may not list: there, said so, nothing in it.
  if (process.getuid?.() !== 0) {
    mkdirSync(join(base, "Locked"));
    chmodSync(join(base, "Locked"), 0);
    const locked = await ask(table, request("GET", "/drive/folders", { path: join(base, "Locked") }, null, "owner"));
    chmodSync(join(base, "Locked"), 0o755);
    assert.deepEqual([locked.status, locked.json.unreadable, locked.json.entries], [200, true, []]);
    assert.equal((await ask(table, request("GET", "/drive/folders", {}, null, "owner"))).json.entries.find((e: any) => e.name === "Locked")?.unreadable, false);
  }
  // The station's data is not a root, nor a folder that is not there.
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: [data] }, "admin"))).json.code, "protected");
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: [join(base, "none")] }, "admin"))).json.code, "not_found");
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: ["relative"] }, "admin"))).json.code, "invalid_request");
  const set = await ask(table, request("PUT", "/drive/roots", {}, { roots: [root, root] }, "owner"));
  assert.equal(set.status, 200);
  assert.deepEqual(set.json.roots, [{ path: root, name: "root", state: "ok" }]);
  assert.equal(set.json.manage, true);
  assert.equal(told, 1);
  assert.deepEqual(JSON.parse(readFileSync(config.path, "utf8")).drive, { roots: [root] });
  const read = await ask(table, request("GET", "/drive/read", { root, path: "notes.md", offset: "2", length: "2" }));
  assert.equal(read.body.toString(), "he");
  assert.equal(read.headers["stillfail-total"], "8");
  assert.equal(read.headers["content-type"], "text/markdown; charset=utf-8");
  const escape = await ask(table, request("GET", "/drive/read", { root, path: "../outside.txt" }));
  assert.equal(escape.status, 403);
  assert.equal(escape.json.code, "path_escape");
  const up = await ask(table, request("PUT", "/drive/upload", { root, path: "new.txt", id: "a", offset: "0", total: "2" }, Buffer.from("hi")));
  assert.equal(up.json.entry.size, 2);
  const lost = await ask(table, request("PUT", "/drive/upload", { root, path: "big.txt", id: "b", offset: "4", total: "8" }, Buffer.from("x")));
  assert.equal(lost.status, 409);
  assert.deepEqual([lost.json.code, lost.json.have], ["upload_lost", 0]);
  assert.equal((await ask(table, request("POST", "/drive/mkdir", {}, { root, path: "Made" }))).json.dir, true);
  assert.equal((await ask(table, request("POST", "/drive/rename", {}, { root, from: "Made", to: "Renamed" }))).json.name, "Renamed");
  assert.equal((await ask(table, request("POST", "/drive/remove", {}, { root, path: "Renamed" }))).status, 200);
  assert.equal((await ask(table, request("POST", "/drive/remove", {}, { root }))).json.code, "invalid_request");
  // A root named before stays though it is gone for now.
  config.update((raw) => (raw.drive.roots = [root, join(base, "unplugged")]));
  const kept = await ask(table, request("PUT", "/drive/roots", {}, { roots: [join(base, "unplugged"), root] }, "owner"));
  assert.deepEqual(kept.json.roots.map((r: any) => r.state), ["missing", "ok"]);
  assert.doesNotThrow(() => checkConfig({ drive: { roots: [root] } }, base));
  assert.throws(() => checkConfig({ drive: { roots: [1] } }, base), /drive.roots/);
});

test("anywhere: a member who may write reaches every folder, a read-only one only those pinned; the station's data never", async () => {
  const { base, root, data } = place();
  const config = new ConfigFile(mkdtempSync(join(tmpdir(), "drive-config-")));
  const drive = new Drive({ config: () => config.raw(), protect: () => [data] });
  const table = routes({ drive, config, home: base });
  symlinkSync(join(base, "outside.txt"), join(root, "out-link"));
  // Not pinned: any absolute folder is a root for a member, none for a viewer.
  const listed = await ask(table, request("GET", "/drive/list", { root: base, path: "" }));
  assert.deepEqual(listed.json.entries.map((e: any) => e.name), ["root", "outside.txt"]);
  assert.equal((await ask(table, request("GET", "/drive/list", { root: base, path: "" }, null, "viewer"))).json.code, "not_a_root");
  assert.equal((await ask(table, request("GET", "/drive/list", { root: "relative", path: "" }))).json.code, "not_a_root");
  // A link out of a folder is followed for a member (listed and read), not for a viewer of a pinned one.
  assert.equal((await ask(table, request("GET", "/drive/read", { root, path: "out-link" }))).body.toString(), "out");
  config.update((raw) => (raw.drive = { roots: [root] }));
  assert.equal((await ask(table, request("GET", "/drive/read", { root, path: "out-link" }, null, "viewer"))).json.code, "path_escape");
  assert.equal((await ask(table, request("GET", "/drive/read", { root, path: "notes.md" }, null, "viewer"))).body.toString(), "# hello\n");
  // `..` is refused all the same, and the station's data from anywhere.
  assert.equal((await ask(table, request("GET", "/drive/read", { root, path: "../outside.txt" }))).json.code, "path_escape");
  assert.equal((await ask(table, request("GET", "/drive/read", { root: data, path: "key" }))).json.code, "protected");
  assert.equal((await ask(table, request("GET", "/drive/list", { root: base, path: "root/.stillfail" }))).json.code, "protected");
  assert.equal((await ask(table, request("GET", "/drive/list", { root: base, path: "root" }))).json.entries.some((e: any) => e.name === ".stillfail"), false);
  // Pinned by a member.
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: [root, base] }))).status, 200);
  assert.deepEqual(config.raw().drive.roots, [root, base]);
});

test("stage: a file copied among the uploads for a message to send; not a folder, not by a viewer", async () => {
  const { base, root, data } = place();
  const config = new ConfigFile(mkdtempSync(join(tmpdir(), "drive-config-")));
  const drive = new Drive({ config: () => config.raw(), protect: () => [data] });
  const uploads = mkdtempSync(join(tmpdir(), "drive-uploads-"));
  let n = 0;
  const table = routes({ drive, config, home: base, stage: (name) => ({ safe: name, path: join(uploads, `${n++}-${name}`) }) });
  const staged = await ask(table, request("POST", "/drive/stage", {}, { root, path: "Season 1/E2.mp4" }));
  assert.deepEqual(staged.json, { name: "E2.mp4", path: join(uploads, "0-E2.mp4"), size: 3 });
  assert.equal(readFileSync(join(uploads, "0-E2.mp4"), "utf8"), "two");
  assert.equal(readFileSync(join(root, "Season 1", "E2.mp4"), "utf8"), "two");
  assert.equal((await ask(table, request("POST", "/drive/stage", {}, { root, path: "Season 1" }))).json.code, "is_a_directory");
  assert.equal((await ask(table, request("POST", "/drive/stage", {}, { root, path: ".stillfail/key" }))).json.code, "protected");
  assert.equal((await ask(table, request("POST", "/drive/stage", {}, { root, path: "notes.md" }, "viewer"))).status, 403);
  assert.equal((await ask(table, request("POST", "/drive/stage", {}, { root: base, path: "outside.txt" }))).json.name, "outside.txt");
});

test("stage a folder as a zip: every file under it, links not followed, the station's own data left out", async () => {
  const { root, data } = place();
  const { inflateRawSync } = await import("node:zlib");
  const config = new ConfigFile(mkdtempSync(join(tmpdir(), "drive-config-")));
  const drive = new Drive({ config: () => config.raw(), protect: () => [data] });
  const uploads = mkdtempSync(join(tmpdir(), "drive-uploads-"));
  const table = routes({ drive, config, home: root, stage: (name) => ({ safe: name, path: join(uploads, name) }) });
  writeFileSync(join(root, "Season 1", "big.txt"), "x".repeat(10_000));
  symlinkSync(join(root, "notes.md"), join(root, "Season 1", "link.md"));
  const staged = await ask(table, request("POST", "/drive/stage", {}, { root, path: "", zip: true }));
  assert.equal(staged.json.name, "root.zip");
  // Read back from its central directory.
  const zip = readFileSync(staged.json.path);
  const end = zip.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  let at = zip.readUInt32LE(end + 16);
  const files: Record<string, string> = {};
  for (let i = 0; i < zip.readUInt16LE(end + 10); i++) {
    const [method, packed, n, local] = [zip.readUInt16LE(at + 10), zip.readUInt32LE(at + 20), zip.readUInt16LE(at + 28), zip.readUInt32LE(at + 42)];
    const name = zip.subarray(at + 46, at + 46 + n).toString();
    const body = zip.subarray(local + 30 + zip.readUInt16LE(local + 26), local + 30 + zip.readUInt16LE(local + 26) + packed);
    files[name] = (method === 8 ? inflateRawSync(body) : body).toString();
    at += 46 + n;
  }
  assert.deepEqual(Object.keys(files).sort(), ["root/", "root/Season 1/", "root/Season 1/E10.mp4", "root/Season 1/E2.mp4", "root/Season 1/big.txt", "root/Season 1/e1.mp4", "root/notes.md"]);
  assert.equal(files["root/Season 1/big.txt"], "x".repeat(10_000));
  assert.equal(files["root/notes.md"], "# hello\n");
  assert.equal(staged.json.size, zip.length);
  // A file is not zipped; a folder not asked to be is refused.
  assert.equal((await ask(table, request("POST", "/drive/stage", {}, { root, path: "Season 1" }))).json.code, "is_a_directory");
});

test("a workspace the station joined keeps its own pinned folders, and reaches the machine as the home one does", async () => {
  const { base, root, data } = place();
  const config = new ConfigFile(mkdtempSync(join(tmpdir(), "drive-config-")));
  const drive = new Drive({ config: () => config.raw(), protect: () => [data] });
  const table = routes({ drive, config, home: base });
  const theirs = (r: Request, role = "member") => ({ ...r, viewer: { ...r.viewer, role, workspace: "w2", home: false } });
  const season = join(root, "Season 1");
  // Theirs: none pinned yet, the whole machine for a member who may write, as for the home workspace's.
  assert.deepEqual((await ask(table, theirs(request("GET", "/drive")))).json, { roots: [], manage: false, write: true, anywhere: true, home: base, ...CAN, zip: true });
  assert.equal((await ask(table, theirs(request("GET", "/drive/list", { root, path: "" })))).status, 200);
  // Each workspace pins its own list.
  assert.equal((await ask(table, request("PUT", "/drive/roots", {}, { roots: [root] }))).status, 200);
  assert.equal((await ask(table, theirs(request("PUT", "/drive/roots", {}, { roots: [season] })))).status, 200);
  assert.deepEqual(config.raw().drive, { roots: [root], workspaces: { w2: [season] } });
  assert.doesNotThrow(() => checkConfig(config.raw(), base));
  assert.deepEqual((await ask(table, theirs(request("GET", "/drive")))).json.roots.map((r: any) => r.path), [season]);
  assert.deepEqual((await ask(table, request("GET", "/drive"))).json.roots.map((r: any) => r.path), [root]);
  // A read-only member of theirs: only what theirs pinned.
  assert.equal((await ask(table, theirs(request("GET", "/drive/list", { root, path: "" }), "viewer"))).json.code, "not_a_root");
  assert.deepEqual((await ask(table, theirs(request("GET", "/drive/list", { root: season, path: "" }), "viewer"))).json.entries.map((e: any) => e.name), ["e1.mp4", "E2.mp4", "E10.mp4"]);
});
