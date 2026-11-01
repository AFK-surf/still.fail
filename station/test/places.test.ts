// The directories and files people and agents name for the station, on a Mac (src/ops/places.ts; docs/drive.md "Folders
// macOS protects"): one in a folder macOS protects is never touched by the station's thread: still.fail Helper is asked
// (`files.stat`, a file copied with `files.read`), or, with no helper for it, a child process killed after its time; a
// grant the helper lacks refuses it naming the folder and puts the helper's window up once (helper/grants.ts), the agent
// told to ask with the permissions tool. macOS's protection refuses nothing here: the protected folders of a home made
// for the test are left out of it on disk (or made unreadable), so a direct look would find nothing, or fail.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { protectedPlace, protectedTop } from "../src/drive/fs.ts";
import { parseMounts } from "../src/platform/text.ts";
import type { Fs } from "../src/drive/fs.ts";
import { HelperFiles } from "../src/helper/files.ts";
import { HelperGrants } from "../src/helper/grants.ts";
import { PlaceRefused, Places, type PlaceHelper, follow, nodeProbe, realOutside, walk } from "../src/ops/places.ts";
import { WINDOWS } from "../src/platform/index.ts";

const home = () => realpathSync(mkdtempSync(join(tmpdir(), "places-")));
const locked = (h: string) => (p: string) => protectedPlace(p, h);

/// still.fail Helper as Places sees it: every request noted; `stat` answers files.stat (or throws its refusal).
function fakeHelper(stat: (op: any) => any): PlaceHelper & { asked: any[]; windows: any[] } {
  const asked: any[] = [];
  const windows: any[] = [];
  return {
    asked,
    windows,
    request: async (op) => {
      asked.push(op);
      return stat(op);
    },
    ask: async (grant, top) => {
      windows.push({ grant, top });
      return "up";
    },
    fs: () => {
      throw new Error("no file copied in this test");
    },
  };
}

test("the folders macOS protects are told by their names, one source for the drive and the station's own looks", () => {
  const h = home();
  assert.deepEqual(protectedPlace(join(h, "Desktop", "proj"), h), { top: join(h, "Desktop"), helper: true });
  assert.deepEqual(protectedPlace(join(h, "documents"), h), { top: join(h, "Documents"), helper: true });
  // iCloud Drive and the other file providers' folders: protected too, but still.fail Helper has no grant for them.
  assert.deepEqual(protectedPlace(join(h, "Library", "Mobile Documents", "com~apple~CloudDocs", "x"), h), { top: join(h, "Library", "Mobile Documents"), helper: false });
  assert.deepEqual(protectedPlace(join(h, "Library", "CloudStorage", "Dropbox"), h), { top: join(h, "Library", "CloudStorage"), helper: false });
  assert.equal(protectedPlace(join(h, "Movies"), h), null);
  // The drive reaches only those the helper opens.
  assert.equal(protectedTop(join(h, "Desktop", "a"), h), join(h, "Desktop"));
  assert.equal(protectedTop(join(h, "Library", "Mobile Documents", "a"), h), null);
  rmSync(h, { recursive: true });
});

test("a disk is protected wherever it is mounted, not only in /Volumes", () => {
  // (2026-11-02: OrbStack's NFS mounted at ~/OrbStack; the station opened it itself and waited for good on macOS asking)
  const h = home();
  const mounts = [join(h, "OrbStack"), join(h, "OrbStack", "inner")];
  assert.deepEqual(protectedPlace(join(h, "OrbStack", "docker", "x"), h, mounts), { top: join(h, "OrbStack"), helper: true });
  assert.deepEqual(protectedPlace(join(h, "OrbStack", "inner", "y"), h, mounts), { top: join(h, "OrbStack", "inner"), helper: true }, "the deepest mount");
  assert.equal(protectedTop(join(h, "OrbStack"), h, mounts), join(h, "OrbStack"));
  assert.equal(protectedPlace(join(h, "OrbStackNot"), h, mounts), null, "a name that only starts so");
  assert.equal(protectedPlace(join(h, "code"), h, mounts), null);
  rmSync(h, { recursive: true });
});

test("mount's list is read for the disks mounted, the machine's own volumes left out", () => {
  const out = [
    "/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)",
    "devfs on /dev (devfs, local, nobrowse)",
    "/dev/disk3s6 on /System/Volumes/VM (apfs, local, noexec, journaled, noatime, nobrowse)",
    "/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse, protect, root data)",
    "map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)",
    "OrbStack:/OrbStack on /Users/lin/OrbStack (nfs, nodev, nosuid, noatime, mounted by lin)",
    "/dev/disk5s1 on /Volumes/T7 (exfat, local, nodev, nosuid, noowners, noatime, mounted by lin)",
    "//lin@nas/share on /Users/lin/mnt/share name (smbfs, nodev, nosuid, mounted by lin)",
  ].join("\n");
  assert.deepEqual(parseMounts(out), ["/Users/lin/OrbStack", "/Volumes/T7", "/Users/lin/mnt/share name"]);
});

test("a path is walked link by link and stops at a protected folder, never stepping into it", { skip: WINDOWS }, () => {
  const h = home();
  // ~/Desktop is a folder nobody may list: a walk touching anything in it would fail.
  mkdirSync(join(h, "Desktop", "proj"), { recursive: true });
  chmodSync(join(h, "Desktop"), 0o000);
  mkdirSync(join(h, "work", "app"), { recursive: true });
  symlinkSync(join(h, "Desktop", "proj"), join(h, "work", "linked"));
  symlinkSync("../work/app", join(h, "work", "rel"));
  try {
    assert.deepEqual(walk(join(h, "Desktop", "proj", "src"), locked(h)), { state: "protected", path: join(h, "Desktop", "proj", "src"), top: join(h, "Desktop"), helper: true });
    // Through a link into it: where the link leads, the rest after it.
    assert.deepEqual(walk(join(h, "work", "linked", "src"), locked(h)), { state: "protected", path: join(h, "Desktop", "proj", "src"), top: join(h, "Desktop"), helper: true });
    assert.deepEqual(walk(join(h, "work", "rel"), locked(h)), { state: "ok", real: join(h, "work", "app") });
    assert.deepEqual(walk(join(h, "work", "nope"), locked(h)), { state: "gone" });
    writeFileSync(join(h, "work", "file"), "x");
    assert.deepEqual(walk(join(h, "work", "file"), locked(h)), { state: "not_a_directory" });
    assert.deepEqual(follow(join(h, "work", "linked"), locked(h)).state, "protected");
    // As realpath would say it, but not into the protected folder.
    assert.equal(realOutside(join(h, "work", "rel"), h), join(h, "work", "app"));
  } finally {
    chmodSync(join(h, "Desktop"), 0o755);
    rmSync(h, { recursive: true });
  }
});

test("a directory in a protected folder is asked of still.fail Helper, not looked at by the station", async () => {
  const h = home();
  // Not on disk: the station looking itself would find it gone.
  const dir = join(h, "Desktop", "proj");
  const helper = fakeHelper(() => ({ dir: true, file: false, link: false, size: 0, mtime: 0 }));
  const places = new Places({ mac: true, home: h, helper, probe: { command: "/nonexistent-never-run", args: () => [] } });
  assert.equal(await places.directory(dir, { lang: "en" }), dir);
  assert.deepEqual(helper.asked, [{ op: "files.stat", path: dir, follow: true, roots: [join(h, "Desktop")], protect: [] }]);
  // One the helper says is gone, or a file: refused as that.
  const gone = new Places({ mac: true, home: h, helper: fakeHelper(() => Promise.reject(Object.assign(new Error("no such file"), { code: "ENOENT" }))) });
  await assert.rejects(gone.directory(dir, { lang: "en" }), (e: any) => e instanceof PlaceRefused && e.code === "gone" && e.message.includes(dir));
  const file = new Places({ mac: true, home: h, helper: fakeHelper(() => ({ dir: false, file: true })) });
  await assert.rejects(file.directory(dir, { lang: "zh" }), (e: any) => e.code === "not_a_directory" && e.message === `${dir} 不是文件夹`);
  // Off macOS nothing is protected: looked at directly, as before.
  const elsewhere = new Places({ mac: false, home: h, helper });
  await assert.rejects(elsewhere.directory(dir, { lang: "en" }), (e: any) => e.code === "gone");
  assert.equal(helper.asked.length, 1);
  rmSync(h, { recursive: true });
});

test("with no helper, a protected folder is looked at by a child process, killed after its time: the station keeps answering", { skip: WINDOWS }, async () => {
  const h = home();
  const pids: number[] = [];
  // A child held as a prompt of macOS's would hold it: blocked, never answering.
  const hung = { command: process.execPath, args: () => ["-e", "Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0)"] };
  const places = new Places({ mac: true, home: h, helper: null, probe: hung, timeoutMs: 300, started: (pid) => pids.push(pid) });
  let ticks = 0;
  let ticking = true;
  const tick = () => {
    ticks++;
    if (ticking) setImmediate(tick);
  };
  tick();
  const dir = join(h, "Documents", "proj");
  const asked = places.directory(dir, { lang: "en", agent: true });
  // Asked again meanwhile: the same look, not a second process.
  const again = places.directory(dir, { lang: "en", agent: true });
  await assert.rejects(asked, (e: any) => e instanceof PlaceRefused && e.code === "timeout" && e.message.startsWith(`Couldn't check ${dir} within 1 seconds. macOS protects this folder`));
  await assert.rejects(again, (e: any) => e.code === "timeout");
  ticking = false;
  assert.ok(ticks > 10, `the station's thread went on meanwhile (${ticks})`);
  assert.equal(pids.length, 1);
  // Nothing left running.
  assert.throws(() => process.kill(pids[0]!, 0), (e: any) => e.code === "ESRCH");
  rmSync(h, { recursive: true });
});

test("with no helper, a protected folder that answers is used as the child found it", { skip: WINDOWS }, async () => {
  const h = home();
  const dir = join(h, "Library", "Mobile Documents", "proj");
  mkdirSync(dir, { recursive: true });
  const pids: number[] = [];
  // iCloud Drive: no helper grant for it, so a child process looks even where there is a helper.
  const helper = fakeHelper(() => {
    throw new Error("not asked");
  });
  const places = new Places({ mac: true, home: h, helper, probe: nodeProbe, started: (pid) => pids.push(pid) });
  assert.equal(await places.directory(dir, { lang: "en" }), dir);
  await assert.rejects(places.directory(join(h, "Library", "Mobile Documents", "nope"), { lang: "zh" }), (e: any) => e.code === "gone" && e.message.endsWith("不存在"));
  assert.equal(helper.asked.length, 0);
  assert.equal(pids.length, 2);
  for (const pid of pids) assert.throws(() => process.kill(pid, 0), (e: any) => e.code === "ESRCH");
  rmSync(h, { recursive: true });
});

test("a task's folder the station syncs itself is looked at off its thread even with the helper there", { skip: WINDOWS }, async () => {
  const h = home();
  const dir = join(h, "Downloads", "repo");
  mkdirSync(dir, { recursive: true });
  const helper = fakeHelper(() => ({ dir: true }));
  const places = new Places({ mac: true, home: h, helper, probe: nodeProbe });
  assert.equal(await places.directory(dir, { lang: "en", agent: true, self: true }), dir);
  assert.equal(helper.asked.length, 0, "the helper's grant does not let the station read it itself");
  rmSync(h, { recursive: true });
});

/// still.fail Helper as HelperFiles and HelperGrants talk to it, in this process: macOS has not given it `grant`;
/// its window comes up when asked (`shown`) and is up until `close`.
function grantless(grant: string, top: string) {
  const shown: any[] = [];
  let up = false;
  const app = {
    request: async (op: any) => {
      switch (op.op) {
        case "status":
          return { capture: false, control: false, files: {}, asking: up, asked: up ? [grant] : [] };
        case "permissions.show":
          shown.push(op);
          up = true;
          return { ok: true };
        case "files.access":
          return { access: [] };
        default:
          throw Object.assign(new Error(`macOS has not let still.fail Helper open ${top}`), { code: "grant", grant, state: "unknown", top });
      }
    },
    listen: () => () => {},
    onBack: () => () => {},
  } as any;
  const grants = new HelperGrants({ helper: app, reach: async () => null });
  const files = new HelperFiles({ helper: app, grants, changed: () => {} });
  return { files, shown, close: () => void (up = false) };
}

test("a grant the helper lacks refuses naming the folder, its window put up once, the agent told to ask with permissions", async () => {
  const h = home();
  const top = join(h, "Desktop");
  const dir = join(top, "proj");
  const helper = grantless("desktop", top);
  const places = new Places({ mac: true, home: h, helper: helper.files });
  // A person's: in their words, where to allow it.
  await assert.rejects(places.directory(dir, { lang: "zh" }), (e: any) => {
    assert.ok(e instanceof PlaceRefused && e.code === "grant" && e.grant === "desktop" && e.window === "up");
    assert.ok(e.message.startsWith(`station 需要「桌面」（${top}）的权限才能使用 ${dir}。`), e.message);
    return true;
  });
  // An agent's, twice at once: the same window, not shown again; told how to ask a person for it.
  const both = await Promise.allSettled([places.directory(dir, { lang: "en", agent: true }), places.directory(join(top, "other"), { lang: "en", agent: true })]);
  for (const b of both) {
    assert.equal(b.status, "rejected");
    const e = (b as PromiseRejectedResult).reason;
    assert.equal(e.code, "grant");
    assert.ok(e.message.includes(`needs permission for Desktop (${top})`), e.message);
    assert.ok(e.message.includes("call the permissions tool with request=desktop, post what it says with chat_post kind=need_human"), e.message);
  }
  assert.equal(helper.shown.length, 1);
  assert.deepEqual(helper.shown[0].grants, ["desktop"]);
  // Closed a moment ago: not put up again, and said so.
  helper.close();
  await assert.rejects(places.directory(dir, { lang: "en" }), (e: any) => e.window === "closed" && e.message.includes("was closed a moment ago"));
  assert.equal(helper.shown.length, 1);
  rmSync(h, { recursive: true });
});

test("a file attached from a protected folder is copied by still.fail Helper, or by a child process, never read by the station", { skip: WINDOWS }, async () => {
  const h = home();
  const into = join(h, "uploads");
  mkdirSync(into);
  const path = join(h, "Desktop", "shot.png");
  const copied: string[] = [];
  const fs = {
    stat: async (p: string) => (assert.equal(p, path), { dir: false, file: true, link: false, size: 3, mtimeMs: 0 }),
    copyTo: async (p: string, to: string) => {
      copied.push(p);
      writeFileSync(to, "png");
    },
  } as unknown as Fs;
  const scopes: any[] = [];
  const helper: PlaceHelper = { request: async () => ({}), ask: async () => "up", fs: (scope) => (scopes.push(scope), fs) };
  const places = new Places({ mac: true, home: h, helper });
  const copy = await places.file(path, into, { lang: "en", agent: true }, 50);
  assert.ok(copy.startsWith(`${into}/.stillfail-staged-`) && copy.endsWith("/shot.png"), copy);
  assert.equal(readFileSync(copy, "utf8"), "png");
  assert.deepEqual(copied, [path]);
  assert.deepEqual(scopes, [{ roots: [join(h, "Desktop")], protect: [] }]);
  // Over what may be attached: refused, nothing left behind.
  await assert.rejects(places.file(path, into, { lang: "en", agent: true }, 2), (e: any) => e.code === "too_large");
  assert.equal(readdirSync(into).length, 1);
  // One outside them: itself, for its caller to look at as before.
  assert.equal(await places.file(join(h, "a.txt"), into, { lang: "en" }, 50), join(h, "a.txt"));
  // iCloud Drive's: by a child process.
  const cloud = join(h, "Library", "Mobile Documents", "notes.md");
  mkdirSync(join(h, "Library", "Mobile Documents"), { recursive: true });
  writeFileSync(cloud, "notes");
  const viaChild = await places.file(cloud, into, { lang: "en" }, 50);
  assert.equal(readFileSync(viaChild, "utf8"), "notes");
  assert.ok(existsSync(cloud));
  rmSync(h, { recursive: true });
});
