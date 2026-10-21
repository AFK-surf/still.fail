// Files copied (or moved) into a folder, from the same station or another one (docs/drive.md "Copying between
// stations"): what is already there by those names asked about first (`ask`, answered on the page's dialog: replace,
// keep both or skip, one by one or for all), then the core asks the stations (`drive.transfer`): the files go from one
// station to the other directly, and the page only follows how it goes (the transfers' list). A move within one root
// (or by the top of the disk, for a member who browses everywhere) is still a rename there, at once.
import { useSyncExternalStore } from "react";
import { core, topicNow } from "../core/react.ts";
import type { DriveEntry, DriveFolder } from "../core/shapes.ts";
import { joinPath, parentOf, refresh, type At } from "./model.ts";
import { keptName, movesOf } from "./order.ts";
import type { Dragged } from "./drag.ts";

export type Answer = "replace" | "keep" | "skip";

/** One name asked about: what goes there (its size, its station's name) and what is there. */
export interface Clash { name: string; dir: boolean; coming: { size: number; station: string }; there: DriveEntry }
/** What the page's dialog asks now (none: nothing). */
export interface Asking { into: At; intoName: string; total: number; clashes: Clash[]; answer: (answers: Record<string, Answer> | null) => void }

let asking: Asking | null = null;
const watchers = new Set<() => void>();
const told = () => { for (const f of watchers) f(); };

/** What the dialog asks now. */
export function useAsking(): Asking | null {
  return useSyncExternalStore((f) => (watchers.add(f), () => void watchers.delete(f)), () => asking, () => null);
}

/** A folder's entries as its station has them: held, or read once. */
function entriesOf(at: At): Promise<readonly DriveEntry[]> {
  const topic = { topic: "drive", station: at.station, root: at.root, path: at.path } as const;
  const held = topicNow<DriveFolder>(topic);
  if (held) return Promise.resolve(held.entries);
  return new Promise((resolve, reject) => {
    const stop = core().subscribe(topic, (v) => {
      if (!v) return;
      queueMicrotask(stop);
      resolve((v as DriveFolder).entries);
    }, (e) => {
      queueMicrotask(stop);
      reject(e);
    });
  });
}

/** What is there by the names coming, answered on the dialog; null: the person let it go. */
async function answersFor(items: readonly Dragged[], into: At, intoName: string): Promise<Record<string, Answer> | null> {
  const there = new Map((await entriesOf(into)).map((e) => [e.name.toLowerCase(), e]));
  const clashes = items.flatMap((i): Clash[] => {
    const e = there.get(i.name.toLowerCase());
    return e ? [{ name: i.name, dir: i.dir, coming: { size: i.size, station: i.stationName }, there: e }] : [];
  });
  if (clashes.length === 0) return {};
  return new Promise((resolve) => {
    asking = { into, intoName, total: items.length, clashes, answer: (a) => { asking = null; told(); resolve(a); } };
    told();
  });
}

/**
 * Copies `items` into the folder `into` (`move`: moved instead), as the person asked: what is there by their names
 * asked about first. A move within one station by a root both are under is a rename; anything else a transfer.
 * `intoName`: the folder's name, as the dialog says it. Answers once the stations were asked (not once it is done).
 */
export async function transfer(items: readonly Dragged[], into: At, move: boolean, intoName: string, anywhere: boolean): Promise<void> {
  if (items.length === 0) return;
  // Not into itself, nor where it is already.
  const dest = (i: Dragged) => i.station === into.station && i.root === into.root && (parentOf(i.path) === into.path || into.path === i.path || into.path.startsWith(`${i.path}/`));
  const going = items.filter((i) => !dest(i));
  if (going.length === 0) return;
  // Moved within its station by a root both places are under: renamed there, as before.
  if (move && going.every((i) => i.station === into.station)) {
    const renames = movesOf(going, into, anywhere);
    if (renames.length === going.length) {
      const answers = await answersFor(going, into, intoName);
      if (answers === null) return;
      const taken = [...(await entriesOf(into))];
      for (const m of renames) {
        const name = m.to.split("/").at(-1)!;
        const answer = answers[name];
        if (answer === "skip") continue;
        // The one there to the trash first; or this one beside it, named as Finder names a copy kept.
        if (answer === "replace") await core().call("drive.remove", { station: into.station, root: into.root, path: joinPath(into.path, name) });
        const to = answer === "keep" ? `${m.to.slice(0, m.to.length - name.length)}${keptName(taken, name, going.find((i) => i.name === name)?.dir)}` : m.to;
        taken.push({ name: to.split("/").at(-1)! } as DriveEntry);
        await core().call("drive.rename", { station: into.station, ...m, to });
      }
      const left = new Map(going.map((i) => [`${i.root}\n${parentOf(i.path)}`, { root: i.root, path: parentOf(i.path) }]));
      await Promise.all([...left.values()].map((f) => refresh({ station: into.station, ...f })).concat(refresh(into)));
      return;
    }
  }
  const answers = await answersFor(going, into, intoName);
  if (answers === null) return;
  // One transfer per folder they are in (a drag takes them from one, usually).
  const groups = new Map<string, Dragged[]>();
  for (const i of going) {
    const key = `${i.station}\n${i.root}\n${parentOf(i.path)}`;
    groups.set(key, [...(groups.get(key) ?? []), i]);
  }
  for (const group of groups.values()) {
    const first = group[0]!;
    const names = group.map((i) => i.name).filter((n) => answers[n] !== "skip");
    if (names.length === 0) continue;
    const conflicts = Object.fromEntries(names.filter((n) => answers[n] !== undefined).map((n) => [n, answers[n]!]));
    await core().call("drive.transfer", {
      from: { station: first.station, root: first.root, path: parentOf(first.path), names },
      to: { station: into.station, root: into.root, path: into.path },
      move,
      conflicts,
    });
  }
}

/** The entries of a folder as dragged things (what the menus' 复制到… take). */
export function draggedIn(at: At, entries: readonly DriveEntry[], stationName: string, absoluteOf: (root: string, path: string) => string): Dragged[] {
  return entries.map((e) => {
    const path = joinPath(at.path, e.name);
    return { station: at.station, stationName, root: at.root, path, abs: absoluteOf(at.root, path), name: e.name, size: e.size, dir: e.dir };
  });
}
