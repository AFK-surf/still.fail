// The agents' memory kept level between the stations of a workspace (src/share/memory.ts, memory-merge.ts): stations
// as directories of their own, a cloud that only lists who is in the workspace, the station transport a direct call.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Cloud } from "../src/cloud/state.ts";
import { MemorySync, decide, type Rec } from "../src/share/memory.ts";
import { merge3, unionLines } from "../src/share/memory-merge.ts";

const A = "a".repeat(64);
const B = "b".repeat(64);
const C = "c".repeat(64);
const NAMES: Record<string, string> = { [A]: "ccvm", [B]: "Studio", [C]: "Mini1" };

type Station = { id: string; data: string; home: string; sync: MemorySync; up: boolean };

function world(ids: string[], opts: { old?: string[] } = {}) {
  const stations = new Map<string, Station>();
  const peers = ids.map((id) => ({ id, name: NAMES[id]! }));
  const cloudFor = (station: string) =>
    Object.defineProperties(Object.create(Cloud.prototype), Object.getOwnPropertyDescriptors({
      peersCurrent: true,
      lock: null,
      get state() {
        return { station, name: NAMES[station], workspace: "w", workspace_name: "w", peers, revocations: [], joined: [] } as any;
      },
      listen() {
        return () => {};
      },
    })) as Cloud;
  for (const id of ids) {
    const data = mkdtempSync(join(tmpdir(), "memory-"));
    const home = join(data, "agent");
    mkdirSync(join(home, "skills"), { recursive: true });
    const sync = new MemorySync({
      data,
      cloud: cloudFor(id),
      agentHome: () => home,
      still: true,
      ask: async (to, ws, request) => {
        const other = stations.get(to);
        if (!other || !other.up) throw new Error("peer unavailable");
        if (opts.old?.includes(to)) throw new Error(`unsupported peer method: ${request.method}`);
        return JSON.parse(JSON.stringify(await other.sync.handle(id, request, ws)));
      },
    });
    stations.set(id, { id, data, home, sync, up: true });
  }
  const level = async (...order: string[]) => {
    for (const id of order.length > 0 ? order : ids) if (stations.get(id)!.up) await stations.get(id)!.sync.levelNow();
  };
  const done = async () => {
    for (const s of stations.values()) {
      await s.sync.stop();
      rmSync(s.data, { recursive: true, force: true });
    }
  };
  return { stations, level, done, at: (id: string) => stations.get(id)! };
}

const write = (s: Station, path: string, text: string) => {
  mkdirSync(join(s.home, path, ".."), { recursive: true });
  writeFileSync(join(s.home, path), text);
};
const read = (s: Station, path: string) => (existsSync(join(s.home, path)) ? readFileSync(join(s.home, path), "utf8") : null);

test("two stations' memories of before come to one: each line once, a line one alone had marked with its station", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "MEMORY.md", "# 全局记忆\n\n- /tmp 各会话共用。\n- ccvm 盘小，不编译。\n");
    write(w.at(B), "MEMORY.md", "# 全局记忆\n\n- /tmp 各会话共用。\n- UI 改动先出图。\n");
    await w.level(A, B);
    const a = read(w.at(A), "MEMORY.md");
    assert.equal(a, read(w.at(B), "MEMORY.md"));
    assert.match(a!, /^- \/tmp 各会话共用。$/m);
    assert.match(a!, /^- \[ccvm\] ccvm 盘小，不编译。$/m);
    assert.match(a!, /^- \[Studio\] UI 改动先出图。$/m);
    assert.equal(a!.match(/全局记忆/g)!.length, 1);
  } finally {
    await w.done();
  }
});

test("a station with nothing of its own takes the memory as it is", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "MEMORY.md", "# 全局记忆\n\n- 一条。\n");
    write(w.at(B), "MEMORY.md", "# still.fail memory\n");
    await w.level(B);
    assert.equal(read(w.at(B), "MEMORY.md"), "# 全局记忆\n\n- 一条。\n");
  } finally {
    await w.done();
  }
});

test("an edit, a new skill and a delete reach the other station; what was deleted does not come back", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "MEMORY.md", "- one\n");
    write(w.at(A), "skills/proj/SKILL.md", "---\nname: proj\n---\n- a\n");
    await w.level(A);
    assert.equal(read(w.at(B), "skills/proj/SKILL.md"), "---\nname: proj\n---\n- a\n");
    write(w.at(B), "MEMORY.md", "- one\n- two\n");
    await w.level(B);
    assert.equal(read(w.at(A), "MEMORY.md"), "- one\n- two\n");
    rmSync(join(w.at(A).home, "skills", "proj"), { recursive: true });
    await w.level(A);
    assert.equal(read(w.at(B), "skills/proj/SKILL.md"), null);
    assert.equal(existsSync(join(w.at(B).home, "skills", "proj")), false);
    await w.level(B, A);
    assert.equal(read(w.at(A), "skills/proj/SKILL.md"), null);
  } finally {
    await w.done();
  }
});

test("two stations adding to MEMORY.md at once, one of them off: both lines kept once it is back", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "MEMORY.md", "- one\n- two\n");
    await w.level(A);
    w.at(B).up = false;
    write(w.at(A), "MEMORY.md", "- one\n- two\n- from ccvm\n");
    await w.level(A);
    w.at(B).up = true;
    write(w.at(B), "MEMORY.md", "- one changed\n- two\n- from Studio\n");
    await w.level(B);
    const a = read(w.at(A), "MEMORY.md");
    assert.equal(a, read(w.at(B), "MEMORY.md"));
    assert.deepEqual(a!.split("\n").filter(Boolean).sort(), ["- from Studio", "- from ccvm", "- one changed", "- two"].sort());
  } finally {
    await w.done();
  }
});

test("an edit beside a delete is kept", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "skills/p/SKILL.md", "- a\n");
    await w.level(A);
    w.at(B).up = false;
    rmSync(join(w.at(A).home, "skills", "p"), { recursive: true });
    await w.level(A);
    w.at(B).up = true;
    write(w.at(B), "skills/p/SKILL.md", "- a\n- b\n");
    await w.level(B, A);
    assert.equal(read(w.at(A), "skills/p/SKILL.md"), "- a\n- b\n");
  } finally {
    await w.done();
  }
});

test("two skills of one name and nothing alike are kept apart: the smaller under its station's name", async () => {
  const w = world([A, C]);
  try {
    write(w.at(A), "skills/stillfail/SKILL.md", `---\nname: stillfail\ndescription: 项目记忆：still.fail\n---\n${"- 项目的事。\n".repeat(50)}`);
    write(w.at(C), "skills/stillfail/SKILL.md", "---\nname: stillfail\ndescription: 发布机上的本地配置\n---\n本机的发布配置。\n");
    write(w.at(C), "skills/stillfail/notes.md", "本机。\n");
    await w.level(C, A);
    for (const s of [w.at(A), w.at(C)]) {
      assert.match(read(s, "skills/stillfail/SKILL.md")!, /项目记忆/);
      assert.match(read(s, "skills/stillfail-Mini1/SKILL.md")!, /^---\nname: stillfail-Mini1\ndescription: \[Mini1\] 发布机上的本地配置\n---\n本机的发布配置。\n$/);
      assert.equal(read(s, "skills/stillfail-Mini1/notes.md"), "本机。\n");
      assert.equal(read(s, "skills/stillfail/notes.md"), null);
    }
  } finally {
    await w.done();
  }
});

test("what stays on its machine: a file only its owner reads, a built-in skill, a linked one", async () => {
  const w = world([A, B]);
  try {
    write(w.at(A), "skills/p/SKILL.md", "- a\n");
    write(w.at(A), "skills/p/host", "secret\n");
    chmodSync(join(w.at(A).home, "skills/p/host"), 0o600);
    write(w.at(A), "skills/p/__pycache__/x.pyc", "x");
    write(w.at(A), "skills/stillfail-jobs/SKILL.md", "built in\n");
    const site = mkdtempSync(join(tmpdir(), "site-"));
    writeFileSync(join(site, "SKILL.md"), "the deployment's\n");
    symlinkSync(site, join(w.at(A).home, "skills", "site"));
    await w.level(A);
    assert.equal(read(w.at(B), "skills/p/SKILL.md"), "- a\n");
    assert.equal(read(w.at(B), "skills/p/host"), null);
    assert.equal(read(w.at(B), "skills/p/__pycache__/x.pyc"), null);
    assert.equal(read(w.at(B), "skills/stillfail-jobs/SKILL.md"), null);
    assert.equal(read(w.at(B), "skills/site/SKILL.md"), null);
    rmSync(site, { recursive: true, force: true });
  } finally {
    await w.done();
  }
});

test("a station from before is passed over, and keeps its own", async () => {
  const w = world([A, B], { old: [B] });
  try {
    write(w.at(A), "MEMORY.md", "- one\n");
    write(w.at(B), "MEMORY.md", "- other\n");
    await w.level(A);
    assert.equal(read(w.at(B), "MEMORY.md"), "- other\n");
  } finally {
    await w.done();
  }
});

test("three stations come to one memory whatever the order", async () => {
  for (const order of [[A, B, C], [C, B, A], [B, A, C]]) {
    const w = world([A, B, C]);
    try {
      write(w.at(A), "MEMORY.md", "- shared\n- a\n");
      write(w.at(B), "MEMORY.md", "- shared\n- b\n");
      write(w.at(C), "MEMORY.md", "- shared\n- c\n");
      await w.level(...order);
      await w.level(...order);
      const a = read(w.at(A), "MEMORY.md");
      assert.equal(read(w.at(B), "MEMORY.md"), a);
      assert.equal(read(w.at(C), "MEMORY.md"), a);
      for (const line of ["- shared", "a", "b", "c"]) assert.ok(a!.includes(line), `${line} in ${a}`);
      assert.equal(a!.match(/- shared/g)!.length, 1);
    } finally {
      await w.done();
    }
  }
});

test("merge3: both sides' changes in different places taken, one place changed by both keeps both, the newer first", () => {
  assert.equal(merge3("a\nb\nc\n", "A\nb\nc\n", "a\nb\nC\n"), "A\nb\nC\n");
  assert.equal(merge3("a\nb\n", "a\nb\nnew\n", "a\nb\nold\n"), "a\nb\nnew\nold\n");
  assert.equal(merge3("a\nb\n", "a\n", "a\nb\n"), "a\n");
});

test("unionLines: lines both had once and unmarked", () => {
  assert.equal(unionLines("- x\n- y\n", "- [ccvm] x\n- z\n", null, "Studio"), "- x\n- y\n- [Studio] z\n");
});

test("decide: a version made after this one's is taken, an older one kept", () => {
  const r = (hash: string, prev: string[], at: number): Rec => ({ hash, at, by: A, prev, size: 1, mode: 0o644 });
  const h1 = "1".repeat(64);
  const h2 = "2".repeat(64);
  assert.equal(decide("MEMORY.md", r(h1, [], 1), r(h2, [h1], 2), () => null, () => "").kind, "take");
  assert.equal(decide("MEMORY.md", r(h2, [h1], 2), r(h1, [], 1), () => null, () => "").kind, "keep");
});

test("one skill each station kept on since it was copied: merged, each line once, not kept apart", async () => {
  const w = world([A, B]);
  try {
    const base = "---\nname: proj\ndescription: 项目记忆：proj\n---\n- one\n- two\n- three\n- four\n";
    write(w.at(A), "skills/proj/SKILL.md", `${base}- only ccvm\n`);
    write(w.at(B), "skills/proj/SKILL.md", base.replace("- two\n", "- two\n- only Studio\n"));
    await w.level(A, B);
    const a = read(w.at(A), "skills/proj/SKILL.md")!;
    assert.equal(read(w.at(B), "skills/proj/SKILL.md"), a);
    assert.equal(existsSync(join(w.at(A).home, "skills", "proj-Studio")), false);
    for (const line of ["- one", "- two", "- only Studio", "- three", "- four", "- only ccvm"]) assert.equal(a.split("\n").filter((l) => l === line).length, 1, line);
  } finally {
    await w.done();
  }
});

test("a skill kept apart is named for the station that made it, once, wherever it went first; its own files go with it", async () => {
  const D = "d".repeat(64);
  NAMES[D] = "MBA";
  const w = world([A, C, D]);
  try {
    write(w.at(A), "skills/stillfail/SKILL.md", `---\nname: stillfail\ndescription: 项目记忆：still.fail\n---\n${"- 项目的事。\n".repeat(50)}`);
    write(w.at(C), "skills/stillfail/SKILL.md", "---\nname: stillfail\ndescription: 发布机\n---\n本机的发布配置在同目录 host。\n");
    write(w.at(C), "skills/stillfail/host", "mini\n");
    chmodSync(join(w.at(C).home, "skills/stillfail/host"), 0o600);
    // MBA has none: it takes Mini1's first, then meets ccvm's.
    await w.level(D, C, A, D, C, A);
    for (const s of [w.at(A), w.at(C), w.at(D)]) {
      assert.match(read(s, "skills/stillfail/SKILL.md")!, /项目记忆/);
      assert.match(read(s, "skills/stillfail-Mini1/SKILL.md")!, /本机的发布配置/);
      assert.equal(existsSync(join(s.home, "skills", "stillfail-MBA")), false);
    }
    assert.equal(read(w.at(C), "skills/stillfail-Mini1/host"), "mini\n");
    assert.equal(read(w.at(C), "skills/stillfail/host"), null);
    assert.equal(read(w.at(A), "skills/stillfail-Mini1/host"), null);
  } finally {
    await w.done();
  }
});

test("a station from before 0.1.9133, answering as it answers what it does not know, is passed over", async () => {
  const w = world([A, B]);
  try {
    w.at(B).sync.handle = async () => {
      throw new Error("session and task key are required (at most 256 / 128 bytes)");
    };
    write(w.at(A), "MEMORY.md", "- one\n");
    await w.level(A);
    assert.equal(read(w.at(A), "MEMORY.md"), "- one\n");
  } finally {
    await w.done();
  }
});
