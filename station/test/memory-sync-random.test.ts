// The agents' memory brought level from what stations had before it was shared, in many random worlds
// (src/share/memory.ts): 2 to 5 stations, each with its own MEMORY.md (rules alike, edited, its own, none), a skill
// several copied and went on editing, a skill of one name each made apart, a file only its owner reads; stations
// bringing each other level in a random order, some off for a while, then all on until nothing changes. What every
// world must come to:
//   one: every station has the same shared files;
//   nothing lost: every line any station had is in MEMORY.md, every line of the skill copied is in it;
//   apart once: each body of the skill made apart is there once, under its name or as `<name>-<its station>`;
//   own files stay: a file only its owner reads is where it was, on its machine alone;
//   settled: one more round changes nothing.
// MEMORY_RANDOM_SEEDS=<n> runs more worlds than the default.
import assert from "node:assert/strict";
import { chmodSync, lstatSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { type MemoryStation, memoryWorld, readAt, writeAt } from "./memory-world.ts";

const SEEDS = Number(process.env.MEMORY_RANDOM_SEEDS ?? 150);

function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const unmark = (line: string) => line.replace(/^(\s*(?:[-*+]|\d+\.)\s+|)\[[^\]\n]{1,80}\] /, "$1");
const body = (t: string) => t.replace(/^---\n[\s\S]*?\n---\n?/, "");

/// The files shared of a station (path → content), files only their owner reads left out.
function shared(s: MemoryStation): Map<string, string> {
  const out = new Map<string, string>();
  const walk = (rel: string) => {
    for (const e of readdirSync(join(s.home, rel), { withFileTypes: true })) {
      const sub = join(rel, e.name);
      if (e.isDirectory()) walk(sub);
      else if ((lstatSync(join(s.home, sub)).mode & 0o077) !== 0) out.set(sub, readAt(s, sub)!);
    }
  };
  if (readAt(s, "MEMORY.md") !== null) out.set("MEMORY.md", readAt(s, "MEMORY.md")!);
  walk("skills");
  return out;
}

async function run(seed: number) {
  const r = rng(seed);
  const pick = <T>(xs: T[]) => xs[Math.floor(r() * xs.length)]!;
  const n = 2 + Math.floor(r() * 4);
  const names = ["ccvm", "Studio", "Mini1", "MBA", "Windows"].slice(0, n);
  const stations = names.map((name, i) => ({ id: String.fromCharCode(97 + i).repeat(64), name }));
  const w = memoryWorld(stations);
  const memoryLines = new Set<string>();
  const copiedLines = new Set<string>();
  const apartBodies = new Map<string, string>(); // body → its station's name
  const own: { station: string; path: string; text: string }[] = [];
  const rules = Array.from({ length: 12 }, (_, k) => `- rule ${k}`);
  const copied = ["---", "name: proj", "description: 项目记忆：proj", "---", ...Array.from({ length: 20 }, (_, k) => `- proj fact ${k}`)];
  try {
    for (const { id, name } of stations) {
      const s = w.at(id);
      if (r() < 0.2) writeAt(s, "MEMORY.md", "# still.fail memory\n");
      else {
        const lines = ["# 全局记忆", ""];
        for (const rule of rules) if (r() < 0.6) lines.push(r() < 0.15 ? `${rule} (as ${name} has it)` : rule);
        for (let j = 0; j < 1 + Math.floor(r() * 3); j++) lines.push(`- only ${name} ${j}`);
        for (const l of lines) if (l.trim() !== "" && !l.startsWith("#")) memoryLines.add(l);
        writeAt(s, "MEMORY.md", `${lines.join("\n")}\n`);
      }
      if (r() < 0.7) {
        const lines = [...copied];
        for (let j = 0; j < 1 + Math.floor(r() * 3); j++) lines.splice(4 + Math.floor(r() * 20), 0, `- ${name} learnt ${j}`);
        for (const l of lines.slice(4)) copiedLines.add(l);
        writeAt(s, "skills/proj/SKILL.md", `${lines.join("\n")}\n`);
      }
      if (r() < 0.5) {
        const text = `---\nname: conf\ndescription: ${name} 本机的配置\n---\n${Array.from({ length: 1 + Math.floor(r() * 4) }, (_, j) => `${name} 的第 ${j} 项设置`).join("\n")}\n`;
        apartBodies.set(body(text), name);
        writeAt(s, "skills/conf/SKILL.md", text);
        if (r() < 0.5) {
          writeAt(s, "skills/conf/host", `${name}\n`);
          chmodSync(join(s.home, "skills/conf/host"), 0o600);
          own.push({ station: id, path: "skills/conf/host", text: `${name}\n` });
        }
      }
    }
    const ids = stations.map((s) => s.id);
    const said = (what: string) => process.env.MEMORY_RANDOM_ONLY && console.log(what);
    for (const id of ids) said(`== ${w.at(id).name} before\n${readAt(w.at(id), "MEMORY.md")}`);
    for (let step = 0; step < 4 * n; step++) {
      if (r() < 0.25) {
        const s = w.at(pick(ids));
        s.up = !s.up;
      }
      const who = pick(ids);
      said(`step ${step}: ${w.at(who).name} levels (${[...w.all.values()].filter((x) => !x.up).map((x) => x.name).join(",") || "all up"} off) ${w.at(who).up ? "" : "(itself off)"}`);
      await w.level(who);
    }
    for (const s of w.all.values()) s.up = true;
    let last = "";
    let settled = false;
    for (let round = 0; round < 8 && !settled; round++) {
      await w.level(...ids);
      const now = JSON.stringify(ids.map((id) => [...shared(w.at(id))].sort()));
      settled = now === last;
      last = now;
    }
    const where = `seed ${seed}, ${n} stations`;
    assert.ok(settled, `${where}: still changing after 8 rounds`);
    const first = shared(w.at(ids[0]!));
    for (const id of ids.slice(1)) assert.deepEqual([...shared(w.at(id))].sort(), [...first].sort(), `${where}: ${w.at(id).name} differs from ${w.at(ids[0]!).name}`);
    const memory = new Set((first.get("MEMORY.md") ?? "").split("\n").map(unmark));
    for (const l of memoryLines) assert.ok(memory.has(l), `${where}: MEMORY.md lost ${JSON.stringify(l)}`);
    const proj = new Set((first.get("skills/proj/SKILL.md") ?? "").split("\n"));
    for (const l of copiedLines) assert.ok(proj.has(l), `${where}: proj lost ${JSON.stringify(l)}`);
    const confs = [...first].filter(([p]) => /^skills\/conf(-[^/]+)?\/SKILL\.md$/.test(p));
    const bodies = confs.map(([, t]) => body(t));
    assert.equal(new Set(bodies).size, bodies.length, `${where}: a body of conf kept twice: ${confs.map(([p]) => p).join(", ")}`);
    assert.deepEqual([...new Set(bodies)].sort(), [...apartBodies.keys()].sort(), `${where}: the bodies of conf are not those the stations had`);
    for (const [p, t] of confs) {
      const dir = p.split("/")[1]!;
      if (dir !== "conf") assert.equal(dir, `conf-${apartBodies.get(body(t))}`, `${where}: ${dir} not named for the station whose it is`);
    }
    for (const [p] of first) assert.ok(!p.includes(".conflict-"), `${where}: ${p} left to merge`);
    for (const o of own) {
      assert.equal(readAt(w.at(o.station), o.path), o.text, `${where}: ${w.at(o.station).name}'s ${o.path} not where it was`);
      for (const id of ids) if (!own.some((x) => x.station === id)) assert.equal(readAt(w.at(id), o.path), null, `${where}: ${o.path} on ${w.at(id).name}`);
    }
  } finally {
    await w.done();
  }
}

test(`random worlds come to one memory, nothing lost, a skill made apart kept once under its station's name (${SEEDS} seeds)`, async () => {
  const only = process.env.MEMORY_RANDOM_ONLY;
  if (only) await run(Number(only));
  else for (let seed = 1; seed <= SEEDS; seed++) await run(seed);
});
