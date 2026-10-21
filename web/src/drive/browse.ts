// How a station's files are worked with on a wide screen, as a local file browser does (Finder): a press chooses (⌘ adds
// or takes one away, ⇧ the ones between), a double click opens, the keys move and act on what is chosen; names are
// changed where they are; what is dragged onto a folder goes into it (a station's files moved there, the computer's put
// up, a folder of them with what it holds); the order and whether hidden files show are the person's, on this device.
// The files' page and a chat's 文件 tab go through it (`useBrowse`), each saying what may be done there.
import { useEffect, useRef, useState, type MouseEvent } from "react";
import { core, topicNow } from "../core/react.ts";
import { CoreError } from "../core/client.ts";
import type { DriveEntry, DriveFolder } from "../core/shapes.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { joinPath, nameOf, parentOf, refresh, upload, type At } from "./model.ts";
import { drive, nameProblem } from "./useDrive.ts";
import { carriesDrive, droppedOf, type Dragged } from "./drag.ts";
import { arrange, freeName, movesOf, type Arrangement } from "./order.ts";
import { keptTree, lastOpened, toggleTree, type Owner } from "./kept.ts";
import type { DriveView } from "../pages/DriveViews.tsx";
import { t } from "../i18n.ts";

// ── the order, and hidden files ──

/** How the files are ordered and whether hidden ones (a name starting with `.`) show: one for every place, kept on this
 * device among the prefs' `driveViews` (`sort`: `name`, `time`, `size` or `kind`, `-down` after it for the other way;
 * `hidden`: `shown`). By name, hidden ones not shown, where never said. */
export function useArrangement(): [Arrangement, (next: Partial<Arrangement>) => void] {
  const sort = usePrefs((p) => p.driveViews.sort);
  const hiddenShown = usePrefs((p) => p.driveViews.hidden === "shown");
  const [by, way] = (sort ?? "name").split("-");
  const now: Arrangement = { by: by === "time" || by === "size" || by === "kind" ? by : "name", down: way === "down", hidden: hiddenShown };
  return [now, (next) => {
    const a = { ...now, ...next };
    setPrefs({ driveViews: { sort: a.by === "name" && !a.down ? null : `${a.by}${a.down ? "-down" : ""}`, hidden: a.hidden ? "shown" : null } });
  }];
}

/** A folder's entries as shown, read when asked (a key pressed): none while it is not read yet. */
function entriesNow(at: At, a: Arrangement): DriveEntry[] {
  const folder = topicNow<DriveFolder>({ topic: "drive", station: at.station, root: at.root, path: at.path });
  return folder ? arrange(folder.entries, a) : [];
}

// ── what is chosen ──

/** What is chosen: names in one folder (its path under the root), the one ⇧ goes from (`anchor`) and the one the keys
 * move from (`lead`). */
export interface Chosen { folder: string; names: readonly string[]; anchor: string | null; lead: string | null }
const NONE: Chosen = { folder: "", names: [], anchor: null, lead: null };
const only = (folder: string, name: string): Chosen => ({ folder, names: [name], anchor: name, lead: name });

/** A row as the keys go over them: the folder it is in, and it. */
interface Spot { folder: string; entry: DriveEntry }

export interface BrowseOptions {
  owner: Owner;
  view: DriveView;
  /** The folder shown (columns: the one open, the last). */
  at: At;
  /** Opens an entry by its kind (a folder gone into, a file read, played, previewed or saved). */
  open: (in_: At, entry: DriveEntry) => void;
  /** Shows another folder under the root (by its path; `replace`, as the keys go, not a step back in history each). */
  go: (path: string, replace?: boolean) => void;
  /** What is chosen previewed (space), a file only. */
  preview: (in_: At, entry: DriveEntry) => void;
  /** What may be done here: names changed and things deleted (the files' page, for a member who may write). */
  write: boolean;
  /** The chosen asked to be deleted (⌘⌫). */
  remove: (items: { at: At; entry: DriveEntry }[]) => void;
  /** A change made, said in a toast should it fail. */
  act: (doing: Promise<unknown>, what: string) => void;
}

export interface Browse {
  chosen: Chosen;
  arrangement: Arrangement;
  arrangeAs: (next: Partial<Arrangement>) => void;
  /** The folder's entries as shown. */
  arranged: (entries: readonly DriveEntry[]) => DriveEntry[];
  isChosen: (in_: At, name: string) => boolean;
  /** The row whose name is being changed (`folder\nname`). */
  renaming: string | null;
  startRename: (in_: At, name: string) => void;
  /** A press on a row (a click: ⌘ and ⇧ as Finder has them). */
  press: (in_: At, entry: DriveEntry, e: MouseEvent) => void;
  /** Chosen and nothing else (a right click on a row not chosen). */
  choose: (in_: At, name: string) => void;
  /** What is chosen, if `entry` is among it; else `entry` alone (what a menu or a drag of that row is about). */
  chosenWith: (in_: At, entry: DriveEntry) => { at: At; entry: DriveEntry }[];
  /** Nothing chosen (a press where there is no row). */
  clear: () => void;
  /** A key pressed where the rows are (the page's, anywhere on it but a field). */
  onKeyDown: (e: KeyboardEvent) => void;
  /** A new folder in `in_`, named as Finder does, its name then changed in place. */
  newFolder: (in_: At, entries: readonly DriveEntry[]) => Promise<void>;
  rename: (in_: At, entry: DriveEntry, to: string | null) => void;
}

/** A row's key among those shown (its `data-row`): its folder's path under the root, and its name. */
export const rowKey = (folder: string, name: string) => `${folder}\n${name}`;

/** Where the keys and a press go on the rows of the folder at `o.at` as `o.view` shows it. */
export function useBrowse(o: BrowseOptions): Browse {
  const [arrangement, arrangeAs] = useArrangement();
  const { owner, view, at } = o;
  // Coming to a folder, what was last opened in it chosen (the folder come back up from, the file read).
  const firstChosen = (): Chosen => {
    if (view === "columns" && at.path) {
      const last = lastOpened(owner, at);
      return last ? only(at.path, last) : only(parentOf(at.path), nameOf(at.path));
    }
    const last = lastOpened(owner, at);
    return last ? only(at.path, last) : NONE;
  };
  const [state, setState] = useState(() => ({ for: `${view}\n${at.path}`, chosen: firstChosen() }));
  let chosen = state.chosen;
  if (state.for !== `${view}\n${at.path}`) {
    // Columns open the folder chosen: keep the choice that opened this one.
    const kept = view === "columns" && (state.chosen.folder === parentOf(at.path) && state.chosen.names.includes(nameOf(at.path)) || state.chosen.folder === at.path);
    chosen = kept ? state.chosen : firstChosen();
    setState({ for: `${view}\n${at.path}`, chosen });
  }
  const setChosen = (next: Chosen) => setState({ for: `${view}\n${at.path}`, chosen: next });
  const [renaming, setRenaming] = useState<string | null>(null);
  const typed = useRef({ text: "", at: 0 });

  const atOf = (folder: string): At => ({ ...at, path: folder });
  const entriesOf = (folder: string) => entriesNow(atOf(folder), arrangement);
  const entryOf = (folder: string, name: string) => entriesOf(folder).find((e) => e.name === name) ?? null;

  // The rows the keys go over, in order: the folder's (list), each open folder's under its own (tree), the column the
  // one moved from is in (columns).
  const rows = (): Spot[] => {
    if (view === "tree") {
      const open = keptTree(owner, at);
      const out: Spot[] = [];
      const walk = (folder: string) => {
        for (const entry of entriesOf(folder)) {
          out.push({ folder, entry });
          const full = joinPath(folder, entry.name);
          if (entry.dir && open.has(full)) walk(full);
        }
      };
      walk(at.path);
      return out;
    }
    const folder = view === "columns" && chosen.lead !== null ? chosen.folder : at.path;
    return entriesOf(folder).map((entry) => ({ folder, entry }));
  };

  /** Chosen, and shown: columns open a folder chosen (and let go of those past a file chosen); the row scrolled to. */
  const moveTo = (next: Chosen, replace: boolean) => {
    setChosen(next);
    if (view === "columns" && next.lead !== null) {
      const lead = entryOf(next.folder, next.lead);
      const open = lead?.dir && next.names.length === 1 ? joinPath(next.folder, next.lead) : next.folder;
      if (open !== at.path) o.go(open, replace);
    }
    if (next.lead !== null) {
      const key = rowKey(next.folder, next.lead);
      requestAnimationFrame(() => {
        const el = document.querySelector<HTMLElement>(`[data-row="${CSS.escape(key)}"]`);
        el?.focus({ preventScroll: true });
        el?.scrollIntoView({ block: "nearest", inline: "nearest" });
      });
    }
  };

  const press = (in_: At, entry: DriveEntry, e: MouseEvent) => {
    const folder = in_.path;
    if ((e.metaKey || e.ctrlKey) && chosen.folder === folder) {
      const names = chosen.names.includes(entry.name) ? chosen.names.filter((n) => n !== entry.name) : [...chosen.names, entry.name];
      setChosen({ folder, names, anchor: entry.name, lead: entry.name });
      return;
    }
    if (e.shiftKey && chosen.folder === folder && chosen.anchor !== null) {
      const list = entriesOf(folder).map((x) => x.name);
      const [a, b] = [list.indexOf(chosen.anchor), list.indexOf(entry.name)];
      if (a >= 0 && b >= 0) {
        setChosen({ folder, names: list.slice(Math.min(a, b), Math.max(a, b) + 1), anchor: chosen.anchor, lead: entry.name });
        return;
      }
    }
    moveTo(only(folder, entry.name), false);
  };

  const chosenWith = (in_: At, entry: DriveEntry) => {
    if (chosen.folder === in_.path && chosen.names.includes(entry.name) && chosen.names.length > 1) {
      return chosen.names.flatMap((name) => { const e = entryOf(in_.path, name); return e ? [{ at: in_, entry: e }] : []; });
    }
    return [{ at: in_, entry }];
  };

  const rename = (in_: At, entry: DriveEntry, to: string | null) => {
    setRenaming(null);
    const name = to?.trim();
    if (!name || name === entry.name) return;
    const problem = nameProblem(name);
    // Chosen under its new name as soon as the station has it.
    o.act(problem ? Promise.reject(new Error(problem)) : drive.rename(in_, entry, name).then(() => setState((s) => ({ ...s, chosen: only(in_.path, name) }))), t("web-pages.drive.renameWhat"));
  };

  const newFolder = async (in_: At, entries: readonly DriveEntry[]) => {
    const name = freeName(entries, t("web-pages.drive.untitledFolder"));
    await drive.mkdir(in_, name);
    setState((s) => ({ ...s, chosen: only(in_.path, name) }));
    setRenaming(rowKey(in_.path, name));
    requestAnimationFrame(() => document.querySelector(`[data-row="${CSS.escape(rowKey(in_.path, name))}"]`)?.scrollIntoView({ block: "nearest" }));
  };

  const onKeyDown = (e: KeyboardEvent) => {
    // Typing into a field (a name being changed, a filter) is the field's.
    const target = e.target as HTMLElement;
    if (target.closest?.("input, textarea, [contenteditable]") || e.isComposing) return;
    const mod = e.metaKey || e.ctrlKey;
    const list = rows();
    const lead = chosen.lead === null ? -1 : list.findIndex((r) => r.folder === chosen.folder && r.entry.name === chosen.lead);
    const leadSpot = lead >= 0 ? list[lead]! : null;
    const done = () => { e.preventDefault(); e.stopPropagation(); };
    const step = (to: number) => {
      const spot = list[Math.max(0, Math.min(list.length - 1, to))];
      if (!spot) return;
      if (e.shiftKey && chosen.anchor !== null && spot.folder === chosen.folder) {
        const names = list.filter((r) => r.folder === spot.folder).map((r) => r.entry.name);
        const [a, b] = [names.indexOf(chosen.anchor), names.indexOf(spot.entry.name)];
        moveTo({ folder: spot.folder, names: names.slice(Math.min(a, b), Math.max(a, b) + 1), anchor: chosen.anchor, lead: spot.entry.name }, true);
      } else moveTo(only(spot.folder, spot.entry.name), true);
    };
    switch (e.key) {
      case "ArrowDown":
        if (mod) { if (leadSpot) { done(); openSpot(leadSpot); } return; }
        done(); step(lead < 0 ? 0 : lead + 1); return;
      case "ArrowUp":
        if (mod) { done(); if (view !== "columns" && at.path) o.go(parentOf(at.path)); else if (view === "columns" && chosen.folder) moveTo(only(parentOf(chosen.folder), nameOf(chosen.folder)), false); return; }
        done(); step(lead < 0 ? list.length - 1 : lead - 1); return;
      case "Home": done(); step(0); return;
      case "End": done(); step(list.length - 1); return;
      case "ArrowRight": {
        if (!leadSpot?.entry.dir) return;
        done();
        const full = joinPath(leadSpot.folder, leadSpot.entry.name);
        if (view === "tree") {
          if (!keptTree(owner, at).has(full)) toggleTree(owner, at, full, true);
          else { const first = entriesOf(full)[0]; if (first) moveTo(only(full, first.name), true); }
        } else if (view === "columns") {
          const first = entriesOf(full)[0];
          if (first) moveTo(only(full, first.name), true);
        }
        return;
      }
      case "ArrowLeft": {
        if (!leadSpot) return;
        if (view === "tree") {
          done();
          const full = joinPath(leadSpot.folder, leadSpot.entry.name);
          if (leadSpot.entry.dir && keptTree(owner, at).has(full)) toggleTree(owner, at, full, false);
          else if (leadSpot.folder !== at.path) moveTo(only(parentOf(leadSpot.folder), nameOf(leadSpot.folder)), true);
        } else if (view === "columns" && leadSpot.folder !== "") {
          done();
          moveTo(only(parentOf(leadSpot.folder), nameOf(leadSpot.folder)), true);
        }
        return;
      }
      case "Enter":
        if (!leadSpot || chosen.names.length !== 1) return;
        done();
        if (o.write) setRenaming(rowKey(leadSpot.folder, leadSpot.entry.name));
        else openSpot(leadSpot);
        return;
      case "o": case "O":
        if (mod && leadSpot) { done(); openSpot(leadSpot); }
        else if (!mod) typeAhead(e, list);
        return;
      case " ":
        if (leadSpot && !leadSpot.entry.dir) { done(); o.preview(atOf(leadSpot.folder), leadSpot.entry); }
        return;
      case "Backspace": case "Delete":
        if ((mod || e.key === "Delete") && o.write && chosen.names.length > 0) {
          done();
          o.remove(chosen.names.flatMap((name) => { const entry = entryOf(chosen.folder, name); return entry ? [{ at: atOf(chosen.folder), entry }] : []; }));
        }
        return;
      case "a": case "A":
        if (mod) {
          done();
          const folder = leadSpot?.folder ?? (view === "columns" ? chosen.folder || at.path : at.path);
          const names = entriesOf(folder).map((x) => x.name);
          if (names.length) setChosen({ folder, names, anchor: names[0]!, lead: chosen.lead ?? names[0]! });
        } else typeAhead(e, list);
        return;
      case "Escape":
        if (chosen.names.length) { done(); setChosen({ ...NONE, folder: chosen.folder }); }
        return;
      default:
        // ⌘⇧. shows hidden files, or hides them again.
        if (mod && e.shiftKey && e.code === "Period") { done(); arrangeAs({ hidden: !arrangement.hidden }); return; }
        if (!mod && !e.altKey && e.key.length === 1) typeAhead(e, list);
    }
  };

  // Typed letters go to the first row whose name starts with them (in the folder of the one chosen), as Finder does.
  const typeAhead = (e: KeyboardEvent, list: Spot[]) => {
    const now = Date.now();
    const text = (now - typed.current.at < 1000 ? typed.current.text : "") + e.key.toLowerCase();
    typed.current = { text, at: now };
    const folder = chosen.lead !== null ? chosen.folder : list[0]?.folder;
    const spot = list.find((r) => r.folder === folder && r.entry.name.toLowerCase().startsWith(text));
    if (spot) { e.preventDefault(); moveTo(only(spot.folder, spot.entry.name), true); }
  };

  const openSpot = (spot: Spot) => {
    if (spot.entry.dir && view === "columns") {
      const first = entriesOf(joinPath(spot.folder, spot.entry.name))[0];
      if (first) moveTo(only(joinPath(spot.folder, spot.entry.name), first.name), true);
      return;
    }
    o.open(atOf(spot.folder), spot.entry);
  };

  // A name being changed lets go when another folder is shown.
  useEffect(() => setRenaming(null), [at.path, view]);

  return {
    chosen, arrangement, arrangeAs,
    arranged: (entries) => arrange(entries, arrangement),
    isChosen: (in_, name) => chosen.folder === in_.path && chosen.names.includes(name),
    renaming,
    startRename: (in_, name) => { setChosen(only(in_.path, name)); setRenaming(rowKey(in_.path, name)); },
    press,
    choose: (in_, name) => { if (!(chosen.folder === in_.path && chosen.names.includes(name))) setChosen(only(in_.path, name)); },
    chosenWith,
    clear: () => { if (chosen.names.length) setChosen({ ...NONE, folder: chosen.folder }); },
    onKeyDown,
    newFolder,
    rename,
  };
}


// ── dropped onto a folder ──

/**
 * Whether a drag can go into a folder of `station` here: the computer's files (put up), this station's own (moved, or
 * copied), or another station's (copied, or moved) where `station` takes copies (`transfers`: one from before does not).
 * A drag from another window of the app says what it carries only once it is dropped (`dragged` null).
 */
export function takes(dt: DataTransfer, station: string, dragged: readonly Dragged[] | null, transfers = false): boolean {
  if (carriesDrive(dt)) return dragged === null ? transfers : dragged.length > 0 && (transfers || dragged.every((d) => d.station === station));
  return dt.types.includes("Files");
}

/** What a drop of a station's files into a folder of `station` does: across stations a copy (⌘: a move), within one a
 * move (⌥: a copy), as Finder does across disks and within one. The computer's files are put up (a copy). */
export function effectOf(dt: DataTransfer, station: string, dragged: readonly Dragged[] | null, mods: { alt: boolean; meta: boolean }): "copy" | "move" {
  if (!carriesDrive(dt)) return "copy";
  const across = (dragged ?? droppedOf(dt)).some((d) => d.station !== station) || (dragged === null && droppedOf(dt).length === 0);
  return across ? (mods.meta ? "move" : "copy") : mods.alt ? "copy" : "move";
}

/**
 * A drop into the folder `into`: a station's files moved there (not into themselves; one from elsewhere on the machine
 * by the top of its disk, for a member who browses every folder), the computer's put up there, a folder of them made
 * there and filled.
 */
export async function dropInto(dt: DataTransfer, into: At, anywhere: boolean): Promise<void> {
  if (carriesDrive(dt)) return moveInto(droppedOf(dt), into, anywhere);
  // Read now: what a drop carries is gone once its event is over.
  const items = [...dt.items].filter((i) => i.kind === "file").map((i) => ({ entry: i.webkitGetAsEntry?.() ?? null, file: i.getAsFile() }));
  const files: File[] = [];
  const folders: FileSystemDirectoryEntry[] = [];
  for (const { entry, file } of items) {
    if (entry?.isDirectory) folders.push(entry as FileSystemDirectoryEntry);
    else if (file) files.push(file);
  }
  if (files.length) upload(into.station, into.root, into.path, files);
  for (const folder of folders) await putFolder(folder, into);
}

async function putFolder(dir: FileSystemDirectoryEntry, into: At): Promise<void> {
  const here = { ...into, path: joinPath(into.path, dir.name) };
  // One there already is filled, as Finder merges into it.
  await drive.mkdir(into, dir.name).catch((e: unknown) => { if (!(e instanceof CoreError && e.code === "exists")) throw e; });
  const reader = dir.createReader();
  const all: FileSystemEntry[] = [];
  for (;;) {
    const batch = await new Promise<FileSystemEntry[]>((resolve, reject) => reader.readEntries(resolve, reject));
    if (!batch.length) break;
    all.push(...batch);
  }
  const files = await Promise.all(all.filter((e) => e.isFile).map((e) => new Promise<File>((resolve, reject) => (e as FileSystemFileEntry).file(resolve, reject))));
  if (files.length) upload(here.station, here.root, here.path, files);
  for (const sub of all.filter((e) => e.isDirectory)) await putFolder(sub as FileSystemDirectoryEntry, here);
}

async function moveInto(items: readonly Dragged[], into: At, anywhere: boolean): Promise<void> {
  for (const m of movesOf(items, into, anywhere)) await core().call("drive.rename", { station: into.station, ...m });
  // Each folder shown is read again (one moved by another root is not the same folder to the core).
  const left = new Map(items.filter((i) => i.station === into.station).map((i) => [`${i.root}\n${parentOf(i.path)}`, { root: i.root, path: parentOf(i.path) }]));
  await Promise.all([...left.values()].map((f) => refresh({ station: into.station, ...f })).concat(refresh(into)));
}
