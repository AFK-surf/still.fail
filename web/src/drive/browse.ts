// How a station's files are worked with on a wide screen, as a local file browser does (Finder): a press chooses (⌘ adds
// or takes one away, ⇧ the ones between), a double click opens, the keys move and act on what is chosen; names are
// changed where they are; what is dragged onto a folder goes into it (a station's files moved there, the computer's put
// up, a folder of them with what it holds); the order and whether hidden files show are the person's, on this device.
// The files' page and a chat's 文件 tab go through it (`useBrowse`), each saying what may be done there. What is chosen,
// the order, a tree's folders open, the columns' widths and where a press or a key goes are the core's (its
// `driveBrowse` topic and `drive.browse`, client/core-ts/src/views/browse.ts): here they are drawn, and what the core
// answers is done (another folder shown, an entry opened, a name changed in place).
import { useEffect, useRef, useState, type MouseEvent } from "react";
import { core, topicNow, useTopic } from "../core/react.ts";
import { CoreError } from "../core/client.ts";
import type { DriveArrangement, DriveBrowseView, DriveEntry, DriveFolder } from "../core/shapes.ts";
import { joinPath, parentOf, refresh, upload, type At } from "./model.ts";
import { drive, named } from "./useDrive.ts";
import { carriesDrive, droppedOf, type Dragged } from "./drag.ts";
import { movesOf } from "./transfer.ts";
import type { Owner } from "./kept.ts";
import type { DriveView } from "../pages/DriveViews.tsx";
import { t } from "../i18n.ts";

// ── what is chosen ──

/** What is chosen: names in one folder (its path under the root), the one ⇧ goes from (`anchor`) and the one the keys
 * move from (`lead`). */
export interface Chosen { folder: string; names: readonly string[]; anchor: string | null; lead: string | null }
const NONE: Chosen = { folder: "", names: [], anchor: null, lead: null };

/** A row the core names: the folder it is in, and its name. */
interface Spot { folder: string; name: string }
/** What a press or a key does, as the core answers it (`drive.browse`). */
interface Done {
  go?: { path: string; replace: boolean };
  open?: Spot;
  preview?: Spot;
  rename?: Spot;
  remove?: Spot[];
  show?: Spot;
}

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

/** What the views draw of a place (DriveViews.tsx `Shown`): each folder's entries in the order shown (undefined while
 * the core has not said it), a tree's folders open, the columns' widths. */
export interface Drawing {
  arranged: (in_: At, entries: readonly DriveEntry[]) => DriveEntry[] | undefined;
  open: ReadonlySet<string>;
  /** A folder of the tree opened or closed (its disclosure). */
  toggle: (path: string) => void;
  /** A column's width dragged (none: as every column is), kept; every column as wide as the rest again. */
  widthOf: (path: string) => number | undefined;
  keepWidth: (path: string, px: number) => void;
  forgetWidths: () => void;
}

export interface Browse {
  chosen: Chosen;
  arrangement: DriveArrangement;
  arrangeAs: (next: Partial<DriveArrangement>) => void;
  drawing: Drawing;
  isChosen: (in_: At, name: string) => boolean;
  /** The row whose name is being changed (`folder\nname`). */
  renaming: string | null;
  startRename: (in_: At, name: string) => void;
  /** A press on a row (a click: ⌘ and ⇧ as Finder has them). */
  press: (in_: At, entry: DriveEntry, e: MouseEvent) => void;
  /** Chosen and nothing else, unless it is among what is (a right click on a row). */
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

/** A key as the core names it (its `keys`): `mod+` before it with ⌘ or Ctrl held, a letter in small; ⌘⇧. its own. */
const keyName = (e: KeyboardEvent) => {
  const mod = e.metaKey || e.ctrlKey;
  if (mod && e.shiftKey && e.code === "Period") return "mod+shift+Period";
  return `${mod ? "mod+" : ""}${e.key.length === 1 ? e.key.toLowerCase() : e.key}`;
};

const NO_FOLDERS: Readonly<Record<string, string[]>> = {};
const NO_WIDTHS: Readonly<Record<string, number>> = {};

/** Where the keys and a press go on the rows of the folder at `o.at` as `o.view` shows it. */
export function useBrowse(o: BrowseOptions): Browse {
  const { owner, view, at } = o;
  // This place's own name to the core: what is chosen is each place's (two sides of the files' page are two).
  const [place] = useState(() => Math.random().toString(36).slice(2, 12));
  const where = { owner, place, view, station: at.station, root: at.root, path: at.path, ...(o.write ? { write: true } : {}) };
  const got = useTopic<DriveBrowseView>({ topic: "driveBrowse", ...where });
  // Moving to another folder, what was shown stays until the core says this one (columns keep the choice that opened it).
  const last = useRef<DriveBrowseView | undefined>(undefined);
  if (got.value) last.current = got.value;
  const v = got.value ?? last.current;
  const now = useRef(v);
  now.current = v;
  const chosen: Chosen = v ? { folder: v.chosen.folder, names: v.chosen.names, anchor: v.chosen.anchor ?? null, lead: v.chosen.lead ?? null } : NONE;
  const arrangement: DriveArrangement = v?.arrangement ?? { by: "name", down: false, hidden: false };
  const folders = v?.folders ?? NO_FOLDERS;
  const widths = v?.widths ?? NO_WIDTHS;
  const [renaming, setRenaming] = useState<string | null>(null);

  const atOf = (folder: string): At => ({ ...at, path: folder });
  const entryOf = (folder: string, name: string) => topicNow<DriveFolder>({ topic: "drive", station: at.station, root: at.root, path: folder })?.entries.find((e) => e.name === name) ?? null;
  const ask = (params: Record<string, unknown>) => core().call("drive.browse", { ...where, ...params });

  /** What the core answers done: another folder shown, an entry opened, previewed, renamed or deleted, a row in view. */
  const after = (done: Done) => {
    if (done.go) o.go(done.go.path, done.go.replace);
    const entry = (s: Spot) => { const e = entryOf(s.folder, s.name); return e ? [{ at: atOf(s.folder), entry: e }] : []; };
    for (const x of done.open ? entry(done.open) : []) o.open(x.at, x.entry);
    for (const x of done.preview ? entry(done.preview) : []) o.preview(x.at, x.entry);
    if (done.rename) setRenaming(rowKey(done.rename.folder, done.rename.name));
    if (done.remove) o.remove(done.remove.flatMap(entry));
    if (done.show) {
      const key = rowKey(done.show.folder, done.show.name);
      requestAnimationFrame(() => {
        const el = document.querySelector<HTMLElement>(`[data-row="${CSS.escape(key)}"]`);
        el?.focus({ preventScroll: true });
        el?.scrollIntoView({ block: "nearest", inline: "nearest" });
      });
    }
  };
  const send = (params: Record<string, unknown>) => void ask(params).then((done) => { if (done) after(done as Done); }, () => undefined);

  // The place shows this folder now: what is chosen in it is as coming here chooses (or as columns carry it).
  useEffect(() => { send({ act: "at" }); }, [place, view, at.station, at.root, at.path]); // eslint-disable-line react-hooks/exhaustive-deps

  const press = (in_: At, entry: DriveEntry, e: MouseEvent) => send({ act: "press", folder: in_.path, name: entry.name, mod: e.metaKey || e.ctrlKey, shift: e.shiftKey });

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
    // Chosen under its new name as soon as the station has it.
    o.act(named(name).then(() => drive.rename(in_, entry, name)).then(() => ask({ act: "choose", folder: in_.path, name })), t("web-pages.drive.renameWhat"));
  };

  const newFolder = async (in_: At, entries: readonly DriveEntry[]) => {
    const { name } = await core().call("drive.name", { name: t("web-pages.drive.untitledFolder"), station: in_.station, root: in_.root, path: in_.path, taken: entries.map((e) => e.name) }) as { name: string };
    await drive.mkdir(in_, name);
    await ask({ act: "choose", folder: in_.path, name });
    setRenaming(rowKey(in_.path, name));
    requestAnimationFrame(() => document.querySelector(`[data-row="${CSS.escape(rowKey(in_.path, name))}"]`)?.scrollIntoView({ block: "nearest" }));
  };

  const onKeyDown = (e: KeyboardEvent) => {
    // Typing into a field (a name being changed, a filter) is the field's.
    const target = e.target as HTMLElement;
    if (target.closest?.("input, textarea, [contenteditable]") || e.isComposing) return;
    const name = keyName(e);
    // A key that does something here now is the rows' (the core says which); a letter goes to a name starting with it.
    if (now.current?.keys.includes(name)) {
      e.preventDefault();
      e.stopPropagation();
      send({ act: "key", key: name, shift: e.shiftKey });
    } else if (!e.metaKey && !e.ctrlKey && !e.altKey && e.key.length === 1 && e.key !== " ") send({ act: "type", letter: e.key });
  };

  // A name being changed lets go when another folder is shown.
  useEffect(() => setRenaming(null), [at.path, view]);

  const open = new Set(v?.open ?? []);
  return {
    chosen, arrangement,
    arrangeAs: (next) => void core().call("drive.arrange", next).catch(() => undefined),
    drawing: {
      arranged: (in_, entries) => {
        const names = folders[in_.path];
        if (!names) return undefined;
        const by = new Map(entries.map((e) => [e.name, e]));
        return names.flatMap((n) => by.get(n) ?? []);
      },
      open,
      toggle: (path) => void ask({ act: "tree", folder: path }).catch(() => undefined),
      widthOf: (path) => widths[path],
      keepWidth: (path, px) => void ask({ act: "width", path, width: px }).catch(() => undefined),
      forgetWidths: () => void ask({ act: "widths" }).catch(() => undefined),
    },
    isChosen: (in_, name) => chosen.folder === in_.path && chosen.names.includes(name),
    renaming,
    startRename: (in_, name) => { send({ act: "choose", folder: in_.path, name }); setRenaming(rowKey(in_.path, name)); },
    press,
    choose: (in_, name) => send({ act: "menu", folder: in_.path, name }),
    chosenWith,
    clear: () => { if (chosen.names.length) send({ act: "clear" }); },
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
  for (const m of await movesOf(items, into, anywhere)) await core().call("drive.rename", { station: into.station, ...m });
  // Each folder shown is read again (one moved by another root is not the same folder to the core).
  const left = new Map(items.filter((i) => i.station === into.station).map((i) => [`${i.root}\n${parentOf(i.path)}`, { root: i.root, path: parentOf(i.path) }]));
  await Promise.all([...left.values()].map((f) => refresh({ station: into.station, ...f })).concat(refresh(into)));
}
