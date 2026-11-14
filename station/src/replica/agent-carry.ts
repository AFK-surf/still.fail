// A retired station's agent home put into this station's, as its chats are taken here (retire.ts `#tookPlace`; the
// lead, 2026-11-14: the agents' own memory and skills go along). What it sent is its MEMORY.md, its presets.json and
// the skills people or agents made there (carry-worker.ts `homeFiles`), each file by its hash as the rooms' are. Nothing
// this station has is overwritten:
// - MEMORY.md: put where this one has none (or only the empty one a home is made with), else the retired station's
//   appended under a heading that says which station it came from and when, once (the line under it names the station);
// - presets.json: the retired station's presets whose id this one has not, added after its own;
// - a skill: put whole where this one has none of that name, through a directory beside it that is renamed into place,
//   so a skill is never half there; one of the same name stays as it is here.
// On the main thread, its files read and written by fs/promises: an agent home is a few files, not a room.
import { chmod, copyFile, mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { dirname, isAbsolute, join, relative, sep } from "node:path";
import { randomBytes } from "node:crypto";
import type { CarriedFile, CarriedHome } from "./carry-worker.ts";

/// What an agent home is made with (sessions/agent-home.ts `workspaceAgentHome`): as good as none.
const MADE_EMPTY = "# still.fail memory";

export type HomeMerged = { memory: "put" | "appended" | "kept" | "none"; presets: number; skills: string[]; skillsKept: string[] };

const there = (path: string) => stat(path).then(() => true, () => false);

async function writeWhole(path: string, text: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const tmp = `${path}.${randomBytes(4).toString("hex")}.carrying`;
  await writeFile(tmp, text);
  await rename(tmp, path);
}

/// The line under a retired station's memory appended here, by which it is found again (put in once).
export const memoryMark = (origin: string) => `<!-- the memory of station ${origin}, retired into this one -->`;

/// `home`'s files (as sent: `list` the list's file, each file's bytes `files/<hash>`) merged into `to`, this station's
/// agent home of the workspace. `from`: the retired station's id, its name, and when (the station's clock, ms).
export async function mergeAgentHome(to: string, home: CarriedHome, list: string, files: string, from: { origin: string; name: string; at: number }): Promise<HomeMerged> {
  const out: HomeMerged = { memory: "none", presets: 0, skills: [], skillsKept: [] };
  let memory: CarriedFile | null = null;
  let presets: CarriedFile | null = null;
  const skills = new Map<string, { rel: string; f: Extract<CarriedFile, { hash: string }> }[]>();
  const lines = createInterface({ input: createReadStream(list), crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (line === "") continue;
      let f: CarriedFile;
      try {
        f = JSON.parse(line) as CarriedFile;
      } catch {
        continue;
      }
      if (!("hash" in f)) continue;
      const rel = relative(home.dir, f.path);
      if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) continue;
      const parts = rel.split(sep);
      if (rel === "MEMORY.md") memory = f;
      else if (rel === "presets.json") presets = f;
      else if (parts[0] === "skills" && parts.length > 2 && !parts[1]!.startsWith(".")) {
        const group = skills.get(parts[1]!) ?? [];
        group.push({ rel: parts.slice(2).join(sep), f });
        skills.set(parts[1]!, group);
      }
    }
  } finally {
    lines.close();
  }
  const blob = (f: { hash: string }) => join(files, f.hash);
  const m = memory as CarriedFile | null;
  if (m !== null && "hash" in m && (await there(blob(m)))) {
    const theirs = (await readFile(blob(m), "utf8")).trim();
    const path = join(to, "MEMORY.md");
    const ours = await readFile(path, "utf8").catch(() => "");
    const mark = memoryMark(from.origin);
    if (theirs === "" || theirs === MADE_EMPTY || ours.includes(mark)) out.memory = "kept";
    else if (ours.trim() === "" || ours.trim() === MADE_EMPTY) {
      await writeWhole(path, `${theirs}\n\n${mark}\n`);
      out.memory = "put";
    } else {
      const day = new Date(from.at).toISOString().slice(0, 10);
      await writeWhole(path, `${ours.trimEnd()}\n\n## From station ${from.name || from.origin.slice(0, 12)} (retired into this one on ${day})\n\n${mark}\n\n${theirs}\n`);
      out.memory = "appended";
    }
  }
  const p = presets as CarriedFile | null;
  if (p !== null && "hash" in p && (await there(blob(p)))) {
    const theirs = parsedPresets(await readFile(blob(p), "utf8"));
    const path = join(to, "presets.json");
    const text = await readFile(path, "utf8").catch(() => null);
    const ours = text === null ? { presets: [] as any[] } : parsedFile(text);
    // (a presets.json here that does not read as one is left as it is: nothing of it is lost by a merge)
    if (theirs !== null && ours !== null) {
      const ids = new Set(ours.presets.map((x: any) => x?.id).filter((x: unknown) => typeof x === "string"));
      const fresh = theirs.filter((x: any) => typeof x?.id === "string" && !ids.has(x.id));
      if (fresh.length > 0) {
        await writeWhole(path, `${JSON.stringify({ ...ours, presets: [...ours.presets, ...fresh] }, null, 2)}\n`);
        out.presets = fresh.length;
      }
    }
  }
  for (const [name, group] of [...skills].sort(([a], [b]) => (a < b ? -1 : 1))) {
    const dir = join(to, "skills", name);
    if (await there(dir)) {
      out.skillsKept.push(name);
      continue;
    }
    const beside = join(to, "skills", `.carrying-${name}`);
    await rm(beside, { recursive: true, force: true });
    for (const { rel, f } of group) {
      if (!(await there(blob(f)))) continue;
      const path = join(beside, rel);
      await mkdir(dirname(path), { recursive: true });
      await copyFile(blob(f), path);
      await chmod(path, f.mode).catch(() => {});
    }
    if (!(await there(beside))) continue;
    await rename(beside, dir);
    out.skills.push(name);
  }
  return out;
}

function parsedFile(text: string): { presets: any[] } | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && Array.isArray(v.presets) ? v : null;
  } catch {
    return null;
  }
}

function parsedPresets(text: string): any[] | null {
  return parsedFile(text)?.presets ?? null;
}
