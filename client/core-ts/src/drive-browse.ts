// How a station's files are worked with, as a local file browser does (docs/drive.md "Clients"), worked out once for
// every client: the order a folder's entries are shown in and the names a change gives; the files' page's tabs; a
// folder typed by its path; what is chosen in a folder and where a press or a key takes it; and what a device holds of
// it (`Browsing`: the `driveBrowse` and `filesTabs` topics' values and the calls, given what it runs in — the core's
// views/browse.ts, or the site's made-up core). It imports nothing: the root's tests and the demo read it as it is.

// ── the order, and the names a change gives ──

export type SortBy = "name" | "time" | "size" | "kind";
/// How a folder's entries are shown: ordered by what, the other way (`down`), hidden ones too.
export interface Arrangement { by: SortBy; down: boolean; hidden: boolean }
/// An entry as its order needs it (`kind` as drive.ts names it: folder, video, text…).
export interface Ordered { name: string; dir: boolean; size: number; mtime: number; kind: string }

/// Names compared as a file browser does, by hand, where the host has no collation (Host.collate; Hermes, the native
/// apps' engine, has none of its own without Java): case aside, the digits in them as numbers ("2" before "10"), the
/// rest by its characters.
const collator = {
  compare(a: string, b: string): number {
    const x = a.toLowerCase().match(/\d+|\D+/g) ?? [];
    const y = b.toLowerCase().match(/\d+|\D+/g) ?? [];
    for (let i = 0; i < Math.min(x.length, y.length); i++) {
      let p = x[i] as string, q = y[i] as string;
      if (/^\d/.test(p) && /^\d/.test(q)) {
        p = p.replace(/^0+(?=\d)/, "");
        q = q.replace(/^0+(?=\d)/, "");
        if (p.length !== q.length) return p.length - q.length;
      }
      if (p !== q) return p < q ? -1 : 1;
    }
    return x.length - y.length;
  },
};
const extOf = (name: string) => { const dot = name.lastIndexOf("."); return dot > 0 ? name.slice(dot + 1).toLowerCase() : ""; };

/// How the files are ordered and whether hidden ones (a name starting with `.`) show, as the prefs' `driveViews` keep it
/// (`sort`: `name`, `time`, `size` or `kind`, `-down` after it for the other way; `hidden`: `shown`): by name, hidden
/// ones not shown, where never said.
export function arrangementOf(views: Readonly<Record<string, unknown>> | undefined): Arrangement {
  const sort = typeof views?.sort === "string" ? views.sort : "name";
  const [by, way] = sort.split("-");
  return { by: by === "time" || by === "size" || by === "kind" ? by : "name", down: way === "down", hidden: views?.hidden === "shown" };
}

/// An arrangement as the prefs' `driveViews` keep it (null: as where never said).
export function arrangementKept(a: Arrangement): { sort: string | null; hidden: string | null } {
  return { sort: a.by === "name" && !a.down ? null : `${a.by}${a.down ? "-down" : ""}`, hidden: a.hidden ? "shown" : null };
}

/// Each name's place in the order people read them (Host.collate), or null where it cannot say.
export type Collate = (names: readonly string[]) => number[] | null;

/// A folder's entries as they are shown: hidden ones left out unless asked for, folders first, then by what was chosen
/// (the newest and the largest first unless turned the other way, names A to Z: as `collate` has them, else by hand).
export function arrange<E extends Ordered>(entries: readonly E[], a: Arrangement, collate?: Collate): E[] {
  const shown = a.hidden ? [...entries] : entries.filter((e) => !e.name.startsWith("."));
  const places = collate?.(shown.map((e) => e.name)) ?? null;
  const placeOf = new Map<E, number>();
  if (places !== null) shown.forEach((e, i) => placeOf.set(e, places[i] ?? 0));
  const byName = (x: E, y: E) => (places !== null ? (placeOf.get(x) ?? 0) - (placeOf.get(y) ?? 0) : 0) || collator.compare(x.name, y.name);
  const by: (x: E, y: E) => number =
    a.by === "time" ? (x, y) => y.mtime - x.mtime || byName(x, y)
    : a.by === "size" ? (x, y) => y.size - x.size || byName(x, y)
    : a.by === "kind" ? (x, y) => collator.compare(x.kind, y.kind) || collator.compare(extOf(x.name), extOf(y.name)) || byName(x, y)
    : byName;
  return shown.sort((x, y) => (x.dir !== y.dir ? (x.dir ? -1 : 1) : a.down ? by(y, x) : by(x, y)));
}

/// A name not taken among `taken`: `base`, else `base 2`, `base 3`…, as Finder names a new folder.
export function freeName(taken: readonly { name: string }[], base: string): string {
  const names = new Set(taken.map((e) => e.name.toLowerCase()));
  if (!names.has(base.toLowerCase())) return base;
  for (let n = 2; ; n++) if (!names.has(`${base} ${n}`.toLowerCase())) return `${base} ${n}`;
}

/// A name beside those taken, as the station keeps both (station/src/drive/transfers.ts `free`): `a 2.txt`, `b 2`.
export function keptName(taken: readonly { name: string }[], name: string, dir = false): string {
  const names = new Set(taken.map((e) => e.name.toLowerCase()));
  const dot = dir ? -1 : name.lastIndexOf(".");
  const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  for (let n = 2; ; n++) if (!names.has(`${stem} ${n}${ext}`.toLowerCase())) return `${stem} ${n}${ext}`;
}

/// A folder of a station: its address, one of its roots, a path under it.
export interface Folder { station: string; root: string; path: string }
/// A station's file dragged: where it is, by its root and absolutely, and its name.
export interface Moving { station: string; root: string; abs: string; name: string }
export interface Move { root: string; from: string; to: string }

/// The separator of a station's paths (Windows' backslash, else a slash), a child of a folder, a folder absolutely.
const sepOf = (path: string) => (path.includes("\\") && !path.includes("/") ? "\\" : "/");
const childOf = (folder: string, name: string) => (folder.endsWith(sepOf(folder)) ? `${folder}${name}` : `${folder}${sepOf(folder)}${name}`);
const absoluteOf = (root: string, path: string) => path.split("/").filter(Boolean).reduce((at, name) => childOf(at, name), root);

/// The renames a drag of a station's files into the folder `into` makes: none for one dragged from another station, one
/// where it is already, or one into itself; each by a root both places are under (the one it was dragged from, or the
/// folder's), else, for a member who browses every folder (`anywhere`), by the top of the disk.
export function movesOf(items: readonly Moving[], into: Folder, anywhere: boolean): Move[] {
  const dest = absoluteOf(into.root, into.path);
  const sep = sepOf(dest);
  const under = (path: string, top: string) => path === top || path.startsWith(top.endsWith(sep) ? top : top + sep);
  const out: Move[] = [];
  for (const item of items) {
    if (item.station !== into.station) continue;
    const target = childOf(dest, item.name);
    if (target === item.abs || under(dest, item.abs)) continue;
    const root = [item.root, into.root].find((r) => under(item.abs, r) && under(target, r)) ?? (anywhere && sep === "/" ? "/" : null);
    if (root === null) continue;
    const rel = (abs: string) => (abs === root ? "" : abs.slice(root.length).replace(/^[/\\]+/, "").split(sep).join("/"));
    out.push({ root, from: rel(item.abs), to: rel(target) });
  }
  return out;
}

// ── a folder typed by its path ──

/// A station as a typed path needs it: its address, its name, its home (a member who browses everywhere).
export interface Named { station: string; name: string; home: string | null }
export interface Typed { station: string; abs: string; parent: string; partial: string }

/// A folder typed by its path (⌘⇧G), worked out: `mba:~/Projects` names the station before the colon (its name, or the
/// start of it), `~` its home, a path with no slash in front is under the folder shown (`from`; another station's: under
/// its home); with the folder it is in (`parent`) and what is typed of its last part (`partial`, what Tab completes).
export function resolveTyped(typed: string, stations: readonly Named[], from: { station: string; abs: string }): Typed | null {
  const colon = typed.indexOf(":");
  const named = colon > 0 && !/^[A-Za-z]:[\\/]/.test(typed) ? typed.slice(0, colon).trim().toLowerCase() : null;
  const s = named === null ? stations.find((v) => v.station === from.station) : stations.find((v) => v.name.toLowerCase() === named) ?? stations.find((v) => v.name.toLowerCase().startsWith(named));
  if (!s) return null;
  const rest = (named === null ? typed : typed.slice(colon + 1)).trim();
  const home = s.home;
  const base = rest === "" || rest === "~" ? home : rest.startsWith("~/") ? (home ? childOf(home, rest.slice(2)) : null) : rest.startsWith("/") || /^[A-Za-z]:[\\/]/.test(rest) ? rest : s.station === from.station ? childOf(from.abs, rest) : home ? childOf(home, rest) : null;
  if (base === null) return null;
  const ends = /[\\/]$/.test(rest) || rest === "" || rest === "~";
  const abs = ends && base.length > 1 ? base.replace(/[\\/]+$/, "") || "/" : base;
  const cut = Math.max(abs.lastIndexOf("/"), abs.lastIndexOf("\\"));
  return { station: s.station, abs, parent: ends ? abs : cut <= 0 ? "/" : abs.slice(0, cut), partial: ends ? "" : abs.slice(cut + 1) };
}

/// The stations with a drive (their overview says one; one from before the drive has none), this machine's (`here`)
/// first, then as the workspace lists them.
export function withDrive<S extends { station: string; overview?: unknown }>(stations: readonly S[], here: string | null): S[] {
  const drives = stations.filter((s) => { const o = s.overview as { drive?: unknown } | null | undefined; return typeof o === "object" && o !== null && typeof o.drive === "object" && o.drive !== null; });
  return here === null ? drives : [...drives].sort((a, b) => (a.station === here ? -1 : b.station === here ? 1 : 0));
}

// ── the files' page's tabs ──

// As Finder's: each a folder of a station of the workspace, or two side by side (one of them in front: what the keys,
// ⌘C and the page's address are about); one shown at a time. The page's address is the folder in front, in the tab
// shown: a link, the sidebar or going back in history moves that one, and the tabs follow it (`arrive`).

/// One side of a tab: a folder of a station.
export interface Pane { station: string; root: string; path: string }
export interface FilesTab { id: string; panes: Pane[]; front: number }
export interface FilesTabs { tabs: FilesTab[]; current: string }

/// At most this many tabs (the oldest let go past it).
export const MOST_TABS = 12;

const same = (a: Pane, b: Pane) => a.station === b.station && a.root === b.root && a.path === b.path;
const isPane = (v: unknown): v is Pane => !!v && typeof v === "object" && ["station", "root", "path"].every((k) => typeof (v as Record<string, unknown>)[k] === "string");
const paneOf = (p: Pane): Pane => ({ station: p.station, root: p.root, path: p.path });

/// What is kept (JSON, as the prefs' `filesTabs` hold it), read: what does not hold together is let go.
export function readTabs(raw: string | undefined): FilesTabs | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as { tabs?: unknown; current?: unknown } | null;
    const tabs = (Array.isArray(v?.tabs) ? (v.tabs as unknown[]) : [])
      .filter((t): t is { id: string; panes: Pane[]; front?: unknown } => {
        const x = t as { id?: unknown; panes?: unknown } | null;
        return typeof x?.id === "string" && Array.isArray(x.panes) && x.panes.length >= 1 && x.panes.length <= 2 && x.panes.every(isPane);
      })
      .map((t) => ({ id: t.id, panes: t.panes.map(paneOf), front: t.front === 1 && t.panes.length === 2 ? 1 : 0 }));
    const first = tabs[0];
    if (first === undefined) return null;
    return { tabs, current: tabs.some((t) => t.id === v?.current) ? (v?.current as string) : first.id };
  } catch {
    return null;
  }
}

const shownOf = (s: FilesTabs): FilesTab => s.tabs.find((t) => t.id === s.current) ?? (s.tabs[0] as FilesTab);

/// The pane in front of the tab shown.
export function frontOf(s: FilesTabs): Pane {
  const tab = shownOf(s);
  return tab.panes[tab.front] ?? (tab.panes[0] as Pane);
}

// What is done to them: each answers the tabs after it (new ones; those given are not changed). `newId`: a new tab's id.

/// The address moved (a link, the sidebar, history): the pane in front shows it; with no tabs yet, the first.
export function arrive(s: FilesTabs | null, p: Pane, newId: () => string): FilesTabs {
  if (!s) {
    const first = { id: newId(), panes: [paneOf(p)], front: 0 };
    return { tabs: [first], current: first.id };
  }
  const tabs = s.tabs.map((t) => (t.id !== s.current || same(t.panes[t.front] as Pane, p) ? t : { ...t, panes: t.panes.map((x, i) => (i === t.front ? paneOf(p) : x)) }));
  return { ...s, tabs };
}

/// A new tab showing `p`, after the one shown, in front.
export function opened(s: FilesTabs, p: Pane, newId: () => string): FilesTabs {
  const tab = { id: newId(), panes: [paneOf(p)], front: 0 };
  const at = s.tabs.findIndex((t) => t.id === s.current);
  const tabs = [...s.tabs.slice(0, at + 1), tab, ...s.tabs.slice(at + 1)];
  const oldest = s.tabs[0]?.id;
  return { tabs: tabs.length > MOST_TABS ? tabs.filter((t) => t.id !== oldest || t.id === tab.id) : tabs, current: tab.id };
}

/// A tab closed (the last one is not: it stays, as Finder keeps a window); the one beside it shown.
export function closed(s: FilesTabs, id: string): FilesTabs {
  if (s.tabs.length <= 1) return s;
  const at = s.tabs.findIndex((t) => t.id === id);
  const tabs = s.tabs.filter((t) => t.id !== id);
  return { tabs, current: s.current === id ? (tabs[Math.min(at, tabs.length - 1)] as FilesTab).id : s.current };
}

/// The tab `id` shown.
export const shown = (s: FilesTabs, id: string): FilesTabs => (s.tabs.some((t) => t.id === id) ? { ...s, current: id } : s);

/// The tab shown split in two (the other side opening on `other`, else where the front is), or one again (the side in
/// front kept).
export function split(s: FilesTabs, other?: Pane): FilesTabs {
  return {
    ...s,
    tabs: s.tabs.map((t) => {
      if (t.id !== s.current) return t;
      const first = t.panes[0] as Pane;
      if (t.panes.length === 2) return { ...t, panes: [t.panes[t.front] as Pane], front: 0 };
      return { ...t, panes: [first, other ? paneOf(other) : first], front: 1 };
    }),
  };
}

/// The side `front` of the tab shown put in front.
export function fronted(s: FilesTabs, front: number): FilesTabs {
  return { ...s, tabs: s.tabs.map((t) => (t.id === s.current && t.panes[front] ? { ...t, front } : t)) };
}

/// `p` on the other side of the tab shown (split first if it is not), put in front.
export function besides(s: FilesTabs, p: Pane): FilesTabs {
  return {
    ...s,
    tabs: s.tabs.map((t) => {
      if (t.id !== s.current) return t;
      if (t.panes.length === 1) return { ...t, panes: [t.panes[0] as Pane, paneOf(p)], front: 1 };
      const other = t.front === 0 ? 1 : 0;
      return { ...t, panes: t.panes.map((x, i) => (i === other ? paneOf(p) : x)), front: other };
    }),
  };
}

// ── what is chosen in a folder, and where the keys take it ──

// As Finder has it: a press chooses (⌘ adds or takes one away, ⇧ the ones between), the arrows move (→ and ← into and
// out of a folder in columns and a tree), ⌘↓ opens, ⌘↑ goes up, typed letters go to a name, ⏎ changes a name (or opens,
// where nothing is changed), space previews, ⌘⌫ deletes, ⌘A chooses all, esc nothing, ⌘⇧. shows hidden files.

export type View = "columns" | "tree" | "list";
export const joinPath = (folder: string, name: string) => (folder ? `${folder}/${name}` : name);
export const parentOf = (path: string) => path.split("/").filter(Boolean).slice(0, -1).join("/");
export const nameOf = (path: string) => path.split("/").filter(Boolean).at(-1) ?? "";

/// What is chosen: names in one folder (its path under the root), the one ⇧ goes from (`anchor`) and the one the keys
/// move from (`lead`).
export interface Chosen { folder: string; names: readonly string[]; anchor: string | null; lead: string | null }
export const NONE: Chosen = { folder: "", names: [], anchor: null, lead: null };
export const only = (folder: string, name: string): Chosen => ({ folder, names: [name], anchor: name, lead: name });

/// A row as the keys go over them: the folder it is in, and its entry.
export interface Spot { folder: string; name: string; dir: boolean }

/// A folder as a place shows it: how (`view`), which (`path`, under its root; columns: the last open), each folder's
/// entries as shown (by its path; none while not read), the folders a tree has open, whether names are changed and
/// things deleted here (`write`).
export interface Place {
  view: View;
  path: string;
  entries: (folder: string) => readonly { name: string; dir: boolean }[];
  open: ReadonlySet<string>;
  write: boolean;
}

/// What a press or a key does: what is chosen after it (none: as it was), and what the client does with it — another
/// folder shown (`go`; `replace`: as the keys go, not a step back in history each), an entry opened, previewed, asked to
/// be deleted or its name changed in place, a row brought into view (`show`). `tree`: a folder of the tree opened or
/// closed; `hidden`: hidden files shown or not.
export interface Done {
  chosen?: Chosen;
  go?: { path: string; replace: boolean };
  open?: Spot;
  preview?: Spot;
  remove?: Spot[];
  rename?: Spot;
  show?: { folder: string; name: string };
  tree?: { path: string; open: boolean };
  hidden?: boolean;
}

/// Coming to a folder, what is chosen: what was last opened in it (`last`: the folder come back up from, the file read);
/// in columns, else the folder itself in the column before.
export function firstChosen(view: View, path: string, last: string | undefined): Chosen {
  if (view === "columns" && path) return last ? only(path, last) : only(parentOf(path), nameOf(path));
  return last ? only(path, last) : NONE;
}

/// Whether what was chosen stays as columns open the folder at `path`: it is what opened it.
export function carried(view: View, path: string, chosen: Chosen): boolean {
  return view === "columns" && ((chosen.folder === parentOf(path) && chosen.names.includes(nameOf(path))) || chosen.folder === path);
}

const spotOf = (p: Place, folder: string, name: string): Spot | null => {
  const e = p.entries(folder).find((x) => x.name === name);
  return e ? { folder, name, dir: e.dir } : null;
};

/// The rows the keys go over, in order: the folder's (list), each open folder's under its own (tree), the column the
/// one chosen is in (columns).
export function rowsOf(p: Place, chosen: Chosen): Spot[] {
  if (p.view === "tree") {
    const out: Spot[] = [];
    const walk = (folder: string) => {
      for (const e of p.entries(folder)) {
        out.push({ folder, name: e.name, dir: e.dir });
        const full = joinPath(folder, e.name);
        if (e.dir && p.open.has(full)) walk(full);
      }
    };
    walk(p.path);
    return out;
  }
  const folder = p.view === "columns" && chosen.lead !== null ? chosen.folder : p.path;
  return p.entries(folder).map((e) => ({ folder, name: e.name, dir: e.dir }));
}

/// Chosen, and shown: columns open a folder chosen alone (and let go of those past a file chosen); the row brought
/// into view.
function moveTo(p: Place, next: Chosen, replace: boolean): Done {
  const out: Done = { chosen: next };
  if (next.lead !== null) {
    if (p.view === "columns") {
      const lead = spotOf(p, next.folder, next.lead);
      const open = lead?.dir && next.names.length === 1 ? joinPath(next.folder, next.lead) : next.folder;
      if (open !== p.path) out.go = { path: open, replace };
    }
    out.show = { folder: next.folder, name: next.lead };
  }
  return out;
}

/// A press on a row (`mod`: ⌘ or Ctrl held, `shift`: ⇧).
export function press(p: Place, chosen: Chosen, folder: string, name: string, mod: boolean, shift: boolean): Done {
  if (mod && chosen.folder === folder) {
    const names = chosen.names.includes(name) ? chosen.names.filter((n) => n !== name) : [...chosen.names, name];
    return { chosen: { folder, names, anchor: name, lead: name } };
  }
  if (shift && chosen.folder === folder && chosen.anchor !== null) {
    const list = p.entries(folder).map((x) => x.name);
    const [a, b] = [list.indexOf(chosen.anchor), list.indexOf(name)];
    if (a >= 0 && b >= 0) return { chosen: { folder, names: list.slice(Math.min(a, b), Math.max(a, b) + 1), anchor: chosen.anchor, lead: name } };
  }
  return moveTo(p, only(folder, name), false);
}

/// An entry opened by the keys: a folder in columns opens beside, its first entry chosen; the rest as a double click.
function openSpot(p: Place, spot: Spot): Done {
  if (spot.dir && p.view === "columns") {
    const full = joinPath(spot.folder, spot.name);
    const first = p.entries(full)[0];
    return first ? moveTo(p, only(full, first.name), true) : {};
  }
  return { open: spot };
}

/// The keys a place acts on, as `key` names them: each as `KeyboardEvent.key` (a letter in small), `mod+` before it with
/// ⌘ or Ctrl held; ⌘⇧. is `mod+shift+Period`.
export const KEYS = [
  ...["ArrowDown", "ArrowUp", "Home", "End", "ArrowRight", "ArrowLeft", "Enter", "o", " ", "Backspace", "Delete", "a", "Escape"].flatMap((k) => [k, `mod+${k}`]),
  "mod+shift+Period",
];

/// What the key `name` (as KEYS names it) does, on `rows` (rowsOf); null: nothing (the key is left to the page). `shift`:
/// ⇧ held (the rows between chosen); `hidden`: whether hidden files show now. Letters typed are `typed`'s.
export function key(p: Place, chosen: Chosen, rows: readonly Spot[], name: string, shift: boolean, hidden: boolean): Done | null {
  const mod = name.startsWith("mod+");
  const k = mod ? name.slice(4) : name;
  const lead = chosen.lead === null ? -1 : rows.findIndex((r) => r.folder === chosen.folder && r.name === chosen.lead);
  const leadSpot = lead >= 0 ? (rows[lead] ?? null) : null;
  const step = (to: number): Done => {
    const spot = rows[Math.max(0, Math.min(rows.length - 1, to))];
    if (!spot) return {};
    if (shift && chosen.anchor !== null && spot.folder === chosen.folder) {
      const names = rows.filter((r) => r.folder === spot.folder).map((r) => r.name);
      const [a, b] = [names.indexOf(chosen.anchor), names.indexOf(spot.name)];
      return moveTo(p, { folder: spot.folder, names: names.slice(Math.min(a, b), Math.max(a, b) + 1), anchor: chosen.anchor, lead: spot.name }, true);
    }
    return moveTo(p, only(spot.folder, spot.name), true);
  };
  switch (k) {
    case "ArrowDown":
      if (mod) return leadSpot ? openSpot(p, leadSpot) : null;
      return step(lead < 0 ? 0 : lead + 1);
    case "ArrowUp":
      if (mod) {
        if (p.view !== "columns" && p.path) return { go: { path: parentOf(p.path), replace: false } };
        if (p.view === "columns" && chosen.folder) return moveTo(p, only(parentOf(chosen.folder), nameOf(chosen.folder)), false);
        return {};
      }
      return step(lead < 0 ? rows.length - 1 : lead - 1);
    case "Home":
      return step(0);
    case "End":
      return step(rows.length - 1);
    case "ArrowRight": {
      if (!leadSpot?.dir) return null;
      const full = joinPath(leadSpot.folder, leadSpot.name);
      if (p.view === "tree" && !p.open.has(full)) return { tree: { path: full, open: true } };
      if (p.view === "tree" || p.view === "columns") {
        const first = p.entries(full)[0];
        return first ? moveTo(p, only(full, first.name), true) : {};
      }
      return {};
    }
    case "ArrowLeft": {
      if (!leadSpot) return null;
      if (p.view === "tree") {
        const full = joinPath(leadSpot.folder, leadSpot.name);
        if (leadSpot.dir && p.open.has(full)) return { tree: { path: full, open: false } };
        if (leadSpot.folder !== p.path) return moveTo(p, only(parentOf(leadSpot.folder), nameOf(leadSpot.folder)), true);
        return {};
      }
      if (p.view === "columns" && leadSpot.folder !== "") return moveTo(p, only(parentOf(leadSpot.folder), nameOf(leadSpot.folder)), true);
      return null;
    }
    case "Enter":
      if (!leadSpot || chosen.names.length !== 1) return null;
      return p.write ? { rename: leadSpot } : openSpot(p, leadSpot);
    case "o":
      return mod && leadSpot ? openSpot(p, leadSpot) : null;
    case " ":
      return leadSpot && !leadSpot.dir ? { preview: leadSpot } : null;
    case "Backspace":
    case "Delete":
      if ((mod || k === "Delete") && p.write && chosen.names.length > 0) return { remove: chosen.names.flatMap((n) => spotOf(p, chosen.folder, n) ?? []) };
      return null;
    case "a": {
      if (!mod) return null;
      const folder = leadSpot?.folder ?? (p.view === "columns" ? chosen.folder || p.path : p.path);
      const names = p.entries(folder).map((x) => x.name);
      const first = names[0];
      return first === undefined ? {} : { chosen: { folder, names, anchor: first, lead: chosen.lead ?? first } };
    }
    case "Escape":
      return chosen.names.length ? { chosen: { ...NONE, folder: chosen.folder } } : null;
    case "shift+Period":
      return mod ? { hidden: !hidden } : null;
    default:
      return null;
  }
}

/// What is typed so far, and when its last letter was: letters typed within a second of each other go on together.
export interface Typing { text: string; at: number }
export const TYPED_NONE: Typing = { text: "", at: -Infinity };

/// A letter typed (`letter`, at `now`): the first row whose name starts with what is typed (in the folder of the one
/// chosen) chosen, as Finder does; null where none does.
export function typed(p: Place, chosen: Chosen, rows: readonly Spot[], was: Typing, letter: string, now: number): { typing: Typing; done: Done | null } {
  const text = (now - was.at < 1000 ? was.text : "") + letter.toLowerCase();
  const folder = chosen.lead !== null ? chosen.folder : rows[0]?.folder;
  const spot = rows.find((r) => r.folder === folder && r.name.toLowerCase().startsWith(text));
  return { typing: { text, at: now }, done: spot ? moveTo(p, only(spot.folder, spot.name), true) : null };
}

// ── a device's browsing ──

/// A topic's or a call's params, as they come.
export type Params = Readonly<Record<string, unknown>>;

/// What a device's browsing takes of what it runs in (the core: views/browse.ts; the site's demo, its made-up core):
/// the prefs as kept and a change of them (`driveViews`, `filesTabs`), a folder's entries as held (null while it is not
/// read), a workspace's stations with a drive, the time, a new tab's id, the error a call's missing or wrong param is;
/// and whom to tell that what the places matching `pick` show (their `driveBrowse` params) may have changed.
export interface Device {
  prefs(): unknown;
  setPrefs(patch: Record<string, unknown>): void;
  entries(station: string, root: string, path: string): Ordered[] | null;
  stations(workspace: string): Named[];
  now(): number;
  newId(): string;
  invalid(what: string): Error;
  changed(pick: (place: Params) => boolean): void;
  /// The visible counts in the person's language (also says when all entries are hidden).
  countText(folders: number, files: number, hiddenOnly: boolean): string;
  /// Names in the order people read them (the host's), where it can say.
  collate?: Collate;
}

/// What is chosen as it goes out (none of `anchor` and `lead` left out).
export interface ChosenShown { folder: string; names: string[]; anchor?: string; lead?: string }
/// The `driveBrowse` topic's value.
export interface BrowseView { arrangement: Arrangement; folders: Record<string, string[]>; countText?: string; chosen: ChosenShown; open: string[]; widths: Record<string, number>; keys: string[] }
/// The `filesTabs` topic's value: the tabs, and the pane in front of the one shown.
export interface TabsView { tabs: FilesTab[]; current: string; front: Pane }
/// What `drive.browse` answers of a place: what is chosen after it, and what the client does.
export interface Answer { acted: boolean; chosen: ChosenShown; go?: { path: string; replace: boolean }; open?: Spot; preview?: Spot; rename?: Spot; remove?: Spot[]; show?: { folder: string; name: string } }

/// The calls a device's browsing answers (`Browsing.call`).
export const CALLS = ["drive.browse", "drive.arrange", "drive.name", "drive.moves", "files.tabs", "files.go"];

/// The most folders each of what is held of them keeps (the least lately changed go past it).
const KEPT = 2000;

/// What a place holds of itself: the folder (and how) it was last at, what is chosen there, what is being typed.
type PlaceState = { for: string; chosen: Chosen; typing: Typing };
/// Where a place is, as its topic (or a call on it) says.
type At = { owner: string; place: string; view: View; station: string; root: string; path: string; write: boolean };

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const objectOf = (v: unknown): Params => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Params) : {});
const keyOf = (owner: string, station: string, root: string, path: string) => [owner, station, root, path].join("\n");
const chosenShown = (c: Chosen): ChosenShown => ({ folder: c.folder, names: [...c.names], ...(c.anchor !== null ? { anchor: c.anchor } : {}), ...(c.lead !== null ? { lead: c.lead } : {}) });

function atOf(v: Params): At {
  const view = v.view === "tree" || v.view === "list" ? v.view : "columns";
  return { owner: str(v.owner) ?? "", place: str(v.place) ?? "", view, station: str(v.station) ?? "", root: str(v.root) ?? "", path: str(v.path) ?? "", write: v.write === true };
}

/// `value` kept under `key`, the most lately put last; the oldest let go past KEPT.
function keep<V>(m: Map<string, V>, key: string, value: V): void {
  m.delete(key);
  m.set(key, value);
  for (const k of m.keys()) {
    if (m.size <= KEPT) break;
    m.delete(k);
  }
}

/// What a device's browsing holds, as JSON keeps it (`Browsing.snapshot`): each of its maps as its entries, in their
/// order (a typing never begun at null). A Browsing given it answers as the one it was taken of.
export interface BrowsingState {
  trees: [string, string[]][];
  widths: [string, number][];
  opened: [string, string][];
  places: [string, { for: string; chosen: { folder: string; names: string[]; anchor: string | null; lead: string | null }; typing: { text: string; at: number | null } }][];
  live: [string, number][];
}

/// How a device browses its stations' files: by owner (`page`, `tab`), station, root and folder, a tree's folders open,
/// a column's width, what was last opened; by place what is chosen in it (let go as its topics go: `started`,
/// `stopped`). Held in memory while it runs (`state`: as a snapshot of another left it). The order and the tabs are the
/// prefs'.
export class Browsing {
  readonly #d: Device;
  readonly #trees = new Map<string, readonly string[]>();
  readonly #widths = new Map<string, number>();
  readonly #opened = new Map<string, string>();
  readonly #places = new Map<string, PlaceState>();
  readonly #live = new Map<string, number>();

  constructor(device: Device, state?: BrowsingState) {
    this.#d = device;
    if (state === undefined) return;
    for (const [k, v] of state.trees) this.#trees.set(k, [...v]);
    for (const [k, v] of state.widths) this.#widths.set(k, v);
    for (const [k, v] of state.opened) this.#opened.set(k, v);
    for (const [k, p] of state.places) {
      const c = p.chosen;
      this.#places.set(k, { for: p.for, chosen: { folder: c.folder, names: [...c.names], anchor: c.anchor, lead: c.lead }, typing: { text: p.typing.text, at: p.typing.at ?? -Infinity } });
    }
    for (const [k, v] of state.live) this.#live.set(k, v);
  }

  /// What it holds now, as JSON keeps it (BrowsingState).
  snapshot(): BrowsingState {
    return {
      trees: [...this.#trees].map(([k, v]) => [k, [...v]]),
      widths: [...this.#widths],
      opened: [...this.#opened],
      places: [...this.#places].map(([k, p]) => [k, {
        for: p.for,
        chosen: { folder: p.chosen.folder, names: [...p.chosen.names], anchor: p.chosen.anchor, lead: p.chosen.lead },
        typing: { text: p.typing.text, at: Number.isFinite(p.typing.at) ? p.typing.at : null },
      }]),
      live: [...this.#live],
    };
  }

  #need(v: unknown, field: string): string {
    if (typeof v !== "string" || v === "") throw this.#d.invalid(field);
    return v;
  }

  /// How the files are ordered on the device, and whether hidden ones show (the prefs' `driveViews`).
  arrangement(): Arrangement {
    return arrangementOf(objectOf(objectOf(this.#d.prefs()).driveViews));
  }

  /// The place at `at` as `key` and the rest take it, its folders read and ordered as they are asked for (once each).
  #place(at: At, a: Arrangement): Place & { read: (folder: string) => Ordered[] | null; hasHidden: (folder: string) => boolean } {
    const read = new Map<string, Ordered[] | null>();
    const total = new Map<string, number>();
    const shown = (folder: string): Ordered[] | null => {
      if (!read.has(folder)) {
        const held = this.#d.entries(at.station, at.root, folder);
        if (held !== null) total.set(folder, held.length);
        read.set(folder, held === null ? null : arrange(held, a, this.#d.collate));
      }
      return read.get(folder) ?? null;
    };
    return {
      view: at.view,
      path: at.path,
      write: at.write,
      open: new Set(this.#trees.get(keyOf(at.owner, at.station, at.root, at.path)) ?? []),
      entries: (folder) => shown(folder) ?? [],
      read: shown,
      hasHidden: (folder) => (total.get(folder) ?? 0) > (shown(folder)?.length ?? 0),
    };
  }

  /// What is chosen in the place as it is at `at`: as it was left there; as it was where columns opened this folder from
  /// the one chosen; else as coming to a folder chooses (what was last opened in it).
  #chosen(at: At): Chosen {
    const was = this.#places.get(at.place);
    if (was && (was.for === `${at.view}\n${at.path}` || carried(at.view, at.path, was.chosen))) return was.chosen;
    return firstChosen(at.view, at.path, this.#opened.get(keyOf(at.owner, at.station, at.root, at.path)));
  }

  /// The `driveBrowse` topic: each folder the place shows, its entries' names in the order shown (the folder and those
  /// before it in columns; it and the folders open under it in a tree), what is chosen, the tree's folders open, the
  /// columns' widths dragged, the keys that act now (KEYS: the others are the page's).
  view(topic: Params): BrowseView {
    const at = atOf(topic);
    const a = this.arrangement();
    const place = this.#place(at, a);
    const chosen = this.#chosen(at);
    const folders: Record<string, string[]> = {};
    let countText: string | undefined;
    const add = (folder: string): Ordered[] => {
      const es = place.read(folder);
      if (es !== null) {
        folders[folder] = es.map((e) => e.name);
        if (folder === at.path) {
          const dirs = es.filter((e) => e.dir).length;
          countText = this.#d.countText(dirs, es.length - dirs, es.length === 0 && place.hasHidden(folder));
        }
      }
      return es ?? [];
    };
    const parts = at.path.split("/").filter(Boolean);
    const columns = ["", ...parts.map((_, i) => parts.slice(0, i + 1).join("/"))];
    if (at.view === "columns") for (const folder of columns) add(folder);
    else if (at.view === "tree") {
      const walk = (folder: string) => {
        for (const e of add(folder)) if (e.dir && place.open.has(joinPath(folder, e.name))) walk(joinPath(folder, e.name));
      };
      walk(at.path);
    } else add(at.path);
    const widths: Record<string, number> = {};
    if (at.view === "columns") {
      for (const folder of columns) {
        const w = this.#widths.get(keyOf(at.owner, at.station, at.root, folder));
        if (w !== undefined) widths[folder] = w;
      }
    }
    const rows = rowsOf(place, chosen);
    return {
      arrangement: { ...a },
      folders,
      ...(countText === undefined ? {} : { countText }),
      chosen: chosenShown(chosen),
      open: [...place.open],
      widths,
      keys: KEYS.filter((k) => key(place, chosen, rows, k, false, a.hidden) !== null),
    };
  }

  /// The `filesTabs` topic: the workspace's tabs as kept; null before any.
  tabsView(workspace: string): TabsView | null {
    const s = this.#tabsKept(workspace);
    return s === null ? null : { tabs: s.tabs, current: s.current, front: frontOf(s) };
  }

  #tabsKept(workspace: string): FilesTabs | null {
    return readTabs(str(objectOf(objectOf(this.#d.prefs()).filesTabs)[workspace]) ?? undefined);
  }

  /// A topic of `place` begun or ended: a place none of whose topics is shown any more is let go, what is chosen in it
  /// with it.
  started(place: string): void {
    this.#live.set(place, (this.#live.get(place) ?? 0) + 1);
  }

  stopped(place: string): void {
    const left = (this.#live.get(place) ?? 1) - 1;
    if (left > 0) this.#live.set(place, left);
    else {
      this.#live.delete(place);
      this.#places.delete(place);
    }
  }

  /// A call by its name (CALLS), answered.
  call(name: string, params: Params): unknown {
    switch (name) {
      case "drive.browse":
        return this.browse(params);
      case "drive.arrange":
        return this.arrange(params);
      case "drive.name":
        return this.name(params);
      case "drive.moves":
        return this.moves(params);
      case "files.tabs":
        return this.tabs(params);
      default:
        return this.go(params);
    }
  }

  /// What is done in a place (`act`), on the place its params say (as its topic does): `at` (the place shows its folder
  /// now), `press` {folder, name, mod?, shift?}, `choose` {folder, name} (that one alone), `menu` (the same, unless it is
  /// among those chosen), `clear`, `key` {key, shift?} (as KEYS names it), `type` {letter}: answering what is chosen
  /// after it and what the client does (Answer). And, of the owner's folders whatever place shows them: `opened` {name}
  /// (what was last opened in the folder), `tree` {folder, open?} (a folder of the tree shown at the folder opened or
  /// closed, or the other way), `width` {width} (the folder's column dragged), `widths` (every column of the owner as
  /// wide as the rest again): null.
  browse(p: Params): Answer | null {
    const act = this.#need(p.act, "act");
    const at = atOf(p);
    this.#need(p.owner, "owner");
    if (act === "widths") {
      for (const k of [...this.#widths.keys()]) if (k.startsWith(`${at.owner}\n`)) this.#widths.delete(k);
      this.#d.changed((x) => x.owner === at.owner);
      return null;
    }
    this.#need(p.station, "station");
    if (typeof p.root !== "string") throw this.#d.invalid("root");
    const folderKey = keyOf(at.owner, at.station, at.root, at.path);
    const theirs = (x: Params) => x.owner === at.owner && x.station === at.station && x.root === at.root;
    switch (act) {
      case "opened":
        keep(this.#opened, folderKey, this.#need(p.name, "name"));
        this.#d.changed(theirs);
        return null;
      case "tree":
        this.#toggle(folderKey, this.#need(p.folder, "folder"), p.open === true ? true : p.open === false ? false : undefined);
        this.#d.changed(theirs);
        return null;
      case "width": {
        const width = p.width;
        if (typeof width !== "number" || !Number.isFinite(width) || width <= 0) throw this.#d.invalid("width");
        keep(this.#widths, folderKey, Math.round(width));
        this.#d.changed(theirs);
        return null;
      }
    }
    this.#need(p.place, "place");
    const a = this.arrangement();
    const place = this.#place(at, a);
    const chosen = this.#chosen(at);
    let typing = this.#places.get(at.place)?.typing ?? TYPED_NONE;
    let done: Done | null;
    switch (act) {
      case "at":
        done = {};
        break;
      case "press":
        done = press(place, chosen, str(p.folder) ?? "", this.#need(p.name, "name"), p.mod === true, p.shift === true);
        break;
      case "choose":
      case "menu": {
        const folder = str(p.folder) ?? "";
        const name = this.#need(p.name, "name");
        done = act === "menu" && chosen.folder === folder && chosen.names.includes(name) ? {} : { chosen: only(folder, name) };
        break;
      }
      case "clear":
        done = chosen.names.length ? { chosen: { ...NONE, folder: chosen.folder } } : {};
        break;
      case "key":
        done = key(place, chosen, rowsOf(place, chosen), this.#need(p.key, "key"), p.shift === true, a.hidden);
        break;
      case "type": {
        const got = typed(place, chosen, rowsOf(place, chosen), typing, this.#need(p.letter, "letter"), this.#d.now());
        typing = got.typing;
        done = got.done;
        break;
      }
      default:
        throw this.#d.invalid(`act: ${act}`);
    }
    const next = done?.chosen ?? chosen;
    this.#places.set(at.place, { for: `${at.view}\n${at.path}`, chosen: next, typing });
    this.#d.changed((x) => x.place === at.place);
    if (done?.tree) {
      this.#toggle(folderKey, done.tree.path, done.tree.open);
      this.#d.changed(theirs);
    }
    if (done?.hidden !== undefined) this.#d.setPrefs({ driveViews: { hidden: done.hidden ? "shown" : null } });
    const spot = (s: Spot): Spot => ({ folder: s.folder, name: s.name, dir: s.dir });
    return {
      acted: done !== null,
      chosen: chosenShown(next),
      ...(done?.go ? { go: { ...done.go } } : {}),
      ...(done?.open ? { open: spot(done.open) } : {}),
      ...(done?.preview ? { preview: spot(done.preview) } : {}),
      ...(done?.rename ? { rename: spot(done.rename) } : {}),
      ...(done?.remove ? { remove: done.remove.map(spot) } : {}),
      ...(done?.show ? { show: { ...done.show } } : {}),
    };
  }

  /// A folder of the tree kept under `tree` opened or closed (`on`; none: the other way).
  #toggle(tree: string, folder: string, on: boolean | undefined): void {
    const open = new Set(this.#trees.get(tree) ?? []);
    if (on ?? !open.has(folder)) open.add(folder);
    else open.delete(folder);
    keep(this.#trees, tree, [...open]);
  }

  /// The order and whether hidden files show, changed (what is not said stays): kept among the prefs' `driveViews`.
  arrange(p: Params): Arrangement {
    const now = this.arrangement();
    const by = (["name", "time", "size", "kind"] as const).find((x) => x === p.by) ?? now.by;
    const next: Arrangement = { by, down: p.down === true || (p.down !== false && now.down), hidden: p.hidden === true || (p.hidden !== false && now.hidden) };
    this.#d.setPrefs({ driveViews: arrangementKept(next) });
    return next;
  }

  /// The name a new thing takes in a folder: `name` where it is free, else as Finder numbers a new folder; `beside`: as
  /// the station names one kept beside another of its name (`a 2.txt`; `dir`: a folder's, whole). Taken: the folder's
  /// entries as held (`station`, `root`, `path`), and `taken`.
  name(p: Params): { name: string } {
    const name = this.#need(p.name, "name");
    const station = str(p.station);
    const root = str(p.root);
    const held = station !== null && root !== null ? (this.#d.entries(station, root, str(p.path) ?? "") ?? []) : [];
    const also = Array.isArray(p.taken) ? (p.taken as unknown[]).filter((n): n is string => typeof n === "string").map((n) => ({ name: n })) : [];
    const taken = [...held, ...also];
    return { name: p.beside === true ? keptName(taken, name, p.dir === true) : freeName(taken, name) };
  }

  /// The renames a drag of a station's files (`items`: each `{station, root, abs, name}`) into the folder `into`
  /// (`{station, root, path}`) makes (movesOf).
  moves(p: Params): { moves: Move[] } {
    const into = objectOf(p.into);
    const folder = { station: this.#need(into.station, "into.station"), root: this.#need(into.root, "into.root"), path: str(into.path) ?? "" };
    const items = (Array.isArray(p.items) ? (p.items as unknown[]) : []).map(objectOf).map((i) => ({ station: str(i.station) ?? "", root: str(i.root) ?? "", abs: str(i.abs) ?? "", name: str(i.name) ?? "" }));
    return { moves: movesOf(items, folder, p.anywhere === true) };
  }

  /// What is done to the files' page's tabs: `arrive` {pane} (the page's address moved there), `open` {pane} (a new
  /// tab), `close` {id}, `show` {id}, `split` {pane?}, `front` {side}, `besides` {pane}; kept among the prefs'
  /// `filesTabs` (as JSON, by workspace) and answered as the topic says them (null: none, nothing kept nor given).
  tabs(p: Params): TabsView | null {
    const ws = this.#need(p.workspace, "workspace");
    const act = this.#need(p.act, "act");
    const given = objectOf(p.pane);
    const [station, root] = [str(given.station), str(given.root)];
    const pane: Pane | null = station !== null && root !== null ? { station, root, path: str(given.path) ?? "" } : null;
    const needPane = (): Pane => {
      if (pane === null) throw this.#d.invalid("pane");
      return pane;
    };
    const newId = () => this.#d.newId();
    const was = this.#tabsKept(ws);
    // Nothing kept yet: the tabs start where the pane given is.
    const s = was ?? (pane !== null ? arrive(null, pane, newId) : null);
    if (s === null) {
      if (act === "arrive") needPane();
      return null;
    }
    const id = str(p.id) ?? "";
    const next =
      act === "arrive" ? (was === null ? s : arrive(s, needPane(), newId))
      : act === "open" ? opened(s, needPane(), newId)
      : act === "close" ? closed(s, id)
      : act === "show" ? shown(s, id)
      : act === "split" ? split(s, pane ?? undefined)
      : act === "front" ? fronted(s, Number(p.side) || 0)
      : act === "besides" ? besides(s, needPane())
      : null;
    if (next === null) throw this.#d.invalid(`act: ${act}`);
    const json = JSON.stringify(next);
    if (was === null || json !== JSON.stringify(was)) this.#d.setPrefs({ filesTabs: { [ws]: json } });
    return { tabs: next.tabs, current: next.current, front: frontOf(next) };
  }

  /// A folder typed by its path (⌘⇧G), worked out among the workspace's stations with a drive (resolveTyped); null where
  /// it names none.
  go(p: Params): Typed | null {
    const ws = this.#need(p.workspace, "workspace");
    const from = { station: this.#need(p.station, "station"), abs: str(p.abs) ?? "" };
    return resolveTyped(str(p.typed) ?? "", this.#d.stations(ws), from);
  }
}
