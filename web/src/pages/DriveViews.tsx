// The ways a folder of a station's drive is shown (the files' page, a chat's 文件 tab), switched over its list and kept
// for each place on this device (prefs' `driveViews`): columns (the default: a column a folder, from where it is to
// the one open, as Finder's), a tree (folders opened in place, several at once), or a list (one folder). Each row is
// the same (DriveRow): chosen by a press, opened by a double click, dragged, its menu on a right click; the place says
// what a row does (`rowOf`, ../drive/browse.ts) and in what order a folder's entries go (`arranged`). Each keeps what a
// local file browser does as folders are gone into and left (../drive/kept.ts): how far it was scrolled, a tree's
// folders open.
import { Fragment, useLayoutEffect, useRef, useState, type CSSProperties, type DragEvent, type MouseEvent, type ReactNode } from "react";
import type { DriveEntry } from "../core/shapes.ts";
import { joinPath, useFolder, type At } from "../drive/model.ts";
import { toggleTree, useKeptScroll, useTree, type Owner } from "../drive/kept.ts";
import type { Dragged } from "../drive/drag.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { ViewColumns, ViewTree, List } from "@stillfail/ui/icons.tsx";
import { ICON, Tip, type MenuItem, WaitLine } from "../ui.tsx";
import { DriveRow } from "./Drive.tsx";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";

export type DriveView = "columns" | "tree" | "list";

/** What can go into a folder dragged over it, and what dropping there does. */
export interface DropTarget { takes: (dt: DataTransfer) => boolean; drop: (dt: DataTransfer) => void }

/** What a row of a folder does, as its place says. */
export interface RowProps {
  /** Its menu (a right click, its …): about what is chosen when it is among it. */
  items: MenuItem[];
  /** Opened (a double click, ⌘↓): a folder gone into, a file read, played, previewed or saved. */
  open: () => void;
  /** Pressed: chosen (⌘ and ⇧ as Finder has them); in columns, a folder opened beside. */
  press: (e: MouseEvent) => void;
  /** Right-clicked: chosen, if it is not among what is. */
  menu: () => void;
  chosen: boolean;
  /** Its name being changed in place (`rename`: null leaves it as it was). */
  renaming: boolean;
  rename: (to: string | null) => void;
  /** What a drag of it carries (what is chosen, when it is among it). */
  dragged: () => Dragged[];
  /** A folder: what goes into it. */
  drop?: DropTarget | undefined;
}
export type RowOf = (at: At, entry: DriveEntry) => RowProps;

/** The ways a place shows a folder's rows, the same for each view. */
export interface Shown {
  rowOf: RowOf;
  /** A folder's entries in the order shown (hidden ones left out unless asked). */
  arranged: (entries: readonly DriveEntry[]) => DriveEntry[];
  /** What goes into a folder dropped on where its rows are (not on one of them). */
  dropOn?: ((at: At) => DropTarget | undefined) | undefined;
  /** A press where there is no row: nothing chosen. */
  clear: () => void;
}

/** Where a folder takes a drop: marked while something it takes is over it. */
export function useDropZone(target: DropTarget | undefined): { over: boolean; props: { onDragOver?: (e: DragEvent) => void; onDragLeave?: (e: DragEvent) => void; onDrop?: (e: DragEvent) => void } } {
  const [over, setOver] = useState(false);
  if (!target) return { over: false, props: {} };
  return {
    over,
    props: {
      onDragOver: (e) => { if (!target.takes(e.dataTransfer)) return; e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = e.dataTransfer.types.includes("Files") ? "copy" : "move"; setOver(true); },
      onDragLeave: (e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver(false); },
      onDrop: (e) => { setOver(false); if (!target.takes(e.dataTransfer)) return; e.preventDefault(); e.stopPropagation(); target.drop(e.dataTransfer); },
    },
  };
}

/** How `place` shows a folder, as last chosen there (columns where never chosen), and choosing another. */
export function useDriveView(place: "page" | "tab"): [DriveView, (v: DriveView) => void] {
  const kept = usePrefs((p) => p.driveViews[place]);
  const view: DriveView = kept === "tree" || kept === "list" ? kept : "columns";
  return [view, (v) => setPrefs({ driveViews: { [place]: v } })];
}

/** The three ways, side by side: icons, the one shown pressed. */
export function ViewSwitch({ value, onChange }: { value: DriveView; onChange: (v: DriveView) => void }) {
  const ways: [DriveView, typeof List, string][] = [["columns", ViewColumns, t("web-pages.drive.view.columns")], ["tree", ViewTree, t("web-pages.drive.view.tree")], ["list", List, t("web-pages.drive.view.list")]];
  return (
    <span className={css.views} role="radiogroup" aria-label={t("web-pages.drive.view.label")}>
      {ways.map(([v, Icon, label]) => (
        <Tip key={v} label={label}>
          <button type="button" role="radio" aria-checked={value === v} aria-label={label} className={css.viewButton} data-on={value === v || undefined} onClick={() => onChange(v)}>
            <Icon {...ICON} />
          </button>
        </Tip>
      ))}
    </span>
  );
}

// ── tree ──

/** A folder and, under each of its folders opened, that one's, in by a step each: opened and closed in place (its
 * disclosure, → and ←), those open kept for when the folder is shown again. */
export function TreeView({ owner, at, shown, compact = false, empty }: { owner: Owner; at: At; shown: Shown; compact?: boolean; empty?: ReactNode }) {
  const open = useTree(owner, at);
  return <TreeFolder at={at} depth={0} open={open} toggle={(path) => toggleTree(owner, at, path)} shown={shown} compact={compact} empty={empty} />;
}

function TreeFolder({ at, depth, open, toggle, shown, compact, empty }: {
  at: At; depth: number; open: ReadonlySet<string>; toggle: (path: string) => void; shown: Shown; compact: boolean; empty?: ReactNode;
}) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = shown.arranged(folder.value?.entries ?? []);
  const note = (words: string, error = false) => <p className={`${css.treeNote} ${error ? css.treeError : shellCss.muted}`} style={{ "--depth": depth } as CSSProperties}>{words}</p>;
  if (folder.error) return note(folder.error.message, true);
  if (!folder.value) return <div className={css.treeNote} style={{ "--depth": depth } as CSSProperties}><WaitLine /></div>;
  if (!entries.length) return depth === 0 && empty ? <>{empty}</> : note(t("web-pages.drive.emptyFolder"));
  return (
    <>
      {entries.map((e) => {
        const full = joinPath(at.path, e.name);
        const isOpen = e.dir && open.has(full);
        return (
          <Fragment key={e.name}>
            <DriveRow at={at} entry={e} row={shown.rowOf(at, e)} compact={compact} depth={depth} expanded={isOpen} onToggle={e.dir ? () => toggle(full) : undefined} />
            {isOpen && <TreeFolder at={{ ...at, path: full }} depth={depth + 1} open={open} toggle={toggle} shown={shown} compact={compact} />}
          </Fragment>
        );
      })}
    </>
  );
}

// ── columns ──

/**
 * A column a folder, from the one it starts at (`at.path` "" under its root, or where the page is) to the one open
 * (`open`, under it), each with the next open marked; a folder pressed opens next to its column, the columns after it
 * let go. The last is kept in view as more open (there at once when the columns are first drawn). Each column takes
 * what is dropped on it into its folder.
 */
export function ColumnsView({ owner, at, open, shown, empty }: { owner: Owner; at: At; open: string; shown: Shown; empty?: ReactNode }) {
  const parts = open.split("/").filter(Boolean);
  const paths = [at.path, ...parts.map((_, i) => joinPath(at.path, parts.slice(0, i + 1).join("/")))];
  const strip = useRef<HTMLDivElement>(null);
  const drawn = useRef(false);
  useLayoutEffect(() => {
    const el = strip.current;
    if (el) el.scrollTo({ left: el.scrollWidth, behavior: drawn.current ? "smooth" : "instant" });
    drawn.current = true;
  }, [open]);
  return (
    <div ref={strip} className={css.columns}>
      {paths.map((path, i) => (
        <Column key={path} owner={owner} at={{ ...at, path }} next={parts[i] ?? null} shown={shown} empty={i === 0 ? empty : undefined} />
      ))}
    </div>
  );
}

function Column({ owner, at, next, shown, empty }: { owner: Owner; at: At; next: string | null; shown: Shown; empty?: ReactNode }) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = shown.arranged(folder.value?.entries ?? []);
  const scroller = useKeptScroll<HTMLDivElement>(owner, at, "columns", folder.value !== undefined || folder.error !== null);
  const zone = useDropZone(shown.dropOn?.(at));
  return (
    <div ref={scroller} className={css.column} data-drop={zone.over || undefined} {...zone.props} onClick={(e) => { if (e.target === e.currentTarget) shown.clear(); }}>
      {folder.error ? <p className={`${css.treeNote} ${css.treeError}`}>{folder.error.message}</p>
        : !folder.value ? <div className={css.treeNote}><WaitLine /></div>
        : !entries.length ? (empty ?? <p className={`${css.treeNote} ${shellCss.muted}`}>{t("web-pages.drive.emptyFolder")}</p>)
        : entries.map((e) => <DriveRow key={e.name} at={at} entry={e} row={shown.rowOf(at, e)} compact column along={e.name === next} />)}
    </div>
  );
}
