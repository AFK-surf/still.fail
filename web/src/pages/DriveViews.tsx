// The ways a folder of a station's drive is shown (the files' page, a chat's 文件 tab), switched over its list and kept
// for each place on this device (prefs' `driveViews`): columns (the default: a column a folder, from where it is to
// the one open, as Finder's), a tree (folders opened in place, several at once), or a list (one folder). Each row is
// the same (DriveRow): chosen by a press, opened by a double click, dragged, its menu on a right click; the place says
// what a row does (`rowOf`, ../drive/browse.ts) and in what order a folder's entries go (`arranged`, as the core says).
// Each keeps what a local file browser does as folders are gone into and left: how far it was scrolled
// (../drive/kept.ts), a tree's folders open and a column's width (the core's, through the place: `Shown`).
import { Fragment, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type DragEvent, type MouseEvent, type ReactNode } from "react";
import type { DriveEntry } from "../core/shapes.ts";
import { joinPath, useFolder, type At } from "../drive/model.ts";
import { useKeptScroll, type Owner } from "../drive/kept.ts";
import type { Drawing } from "../drive/browse.ts";
import type { Dragged } from "../drive/drag.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { ViewColumns, ViewTree, List } from "@stillfail/ui/icons.tsx";
import { ICON, Tip, type MenuItem, usePointerTip, WaitLine } from "../ui.tsx";
import { resizeHandle } from "@stillfail/ui/parts.css.ts";
import { DriveRow } from "./Drive.tsx";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";

export type DriveView = "columns" | "tree" | "list";

/** What can go into a folder dragged over it, and what dropping there does. */
/** Keys held as something is dropped: across stations ⌘ moves (else a copy), within one ⌥ copies (else a move), as
 * Finder has them across disks and within one. */
export interface Mods { alt: boolean; meta: boolean }
export const modsOf = (e: { altKey: boolean; metaKey: boolean; ctrlKey: boolean }): Mods => ({ alt: e.altKey, meta: e.metaKey || e.ctrlKey });
/** What a folder takes dropped on it, what a drop there does (`effect`: its files copied or moved, the computer's put up
 * as a copy), and the drop. */
export interface DropTarget { takes: (dt: DataTransfer) => boolean; effect?: (dt: DataTransfer, mods: Mods) => "copy" | "move"; drop: (dt: DataTransfer, mods: Mods) => void }

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

/** The ways a place shows a folder's rows, the same for each view: with what the core says of the place (`Drawing`: a
 * folder's entries in the order shown, hidden ones left out unless asked; a tree's folders open; the columns' widths). */
export interface Shown extends Drawing {
  rowOf: RowOf;
  /** What goes into a folder dropped on where its rows are (not on one of them). */
  dropOn?: ((at: At) => DropTarget | undefined) | undefined;
  /** A press where there is no row: nothing chosen. */
  clear: () => void;
}

/** Where a folder takes a drop: marked while something it takes is over it (not while a folder in it takes it instead). */
export function useDropZone(target: DropTarget | undefined): {
  over: boolean;
  props: { onDragOverCapture?: () => void; onDragOver?: (e: DragEvent) => void; onDragLeave?: (e: DragEvent) => void; onDropCapture?: () => void; onDrop?: (e: DragEvent) => void };
} {
  const [over, setOver] = useState(false);
  if (!target) return { over: false, props: {} };
  return {
    over,
    props: {
      // Unmarked on the way down, marked again on the way up: a folder in it that takes the drag stops it on its way up.
      onDragOverCapture: () => setOver(false),
      onDropCapture: () => setOver(false),
      onDragOver: (e) => {
        if (!target.takes(e.dataTransfer)) return;
        e.preventDefault();
        e.stopPropagation();
        e.dataTransfer.dropEffect = target.effect?.(e.dataTransfer, modsOf(e)) ?? (e.dataTransfer.types.includes("Files") ? "copy" : "move");
        setOver(true);
      },
      onDragLeave: (e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver(false); },
      onDrop: (e) => { if (!target.takes(e.dataTransfer)) return; e.preventDefault(); e.stopPropagation(); target.drop(e.dataTransfer, modsOf(e)); },
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
export function TreeView({ at, shown, compact = false, empty }: { at: At; shown: Shown; compact?: boolean; empty?: ReactNode }) {
  return <TreeFolder at={at} depth={0} open={shown.open} toggle={shown.toggle} shown={shown} compact={compact} empty={empty} />;
}

function TreeFolder({ at, depth, open, toggle, shown, compact, empty }: {
  at: At; depth: number; open: ReadonlySet<string>; toggle: (path: string) => void; shown: Shown; compact: boolean; empty?: ReactNode;
}) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = shown.arranged(at, folder.value?.entries ?? []);
  const note = (words: string, error = false) => <p className={`${css.treeNote} ${error ? css.treeError : shellCss.muted}`} style={{ "--depth": depth } as CSSProperties}>{words}</p>;
  if (folder.error) return note(folder.error.message, true);
  if (!folder.value || !entries) return <div className={css.treeNote} style={{ "--depth": depth } as CSSProperties}><WaitLine /></div>;
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

/** A column's width: as wide as every column is until one is dragged (240 until all are, kept on this device). */
const COLUMN = 240, COLUMN_MIN = 160, COLUMN_MAX = 640;
const clampColumn = (px: number) => Math.round(Math.min(COLUMN_MAX, Math.max(COLUMN_MIN, px)));
/** A column being dragged wider or narrower: that folder's (`path`), or (null, ⌥ held) every one. */
type Dragging = { path: string | null; px: number } | null;

/**
 * A column a folder, from the one it starts at (`at.path` "" under its root, or where the page is) to the one open
 * (`open`, under it), each with the next open marked; a folder pressed opens next to its column, the columns after it
 * let go. The last is kept in view as more open (there at once when the columns are first drawn). Each column takes
 * what is dropped on it into its folder. Its edge, dragged, makes it wider or narrower (as Finder's: with ⌥ held every
 * column, and the columns opened after; a double click as wide as its longest name).
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
  // Every column's width: as kept on this device, or as just dragged until the kept one comes back from the core.
  const kept = Number(usePrefs((p) => p.driveViews.column)) || COLUMN;
  const [all, setAll] = useState<number | null>(null);
  useEffect(() => setAll(null), [kept]);
  const [dragging, setDragging] = useState<Dragging>(null);
  const setEvery = (px: number) => {
    shown.forgetWidths();
    setAll(px);
    setPrefs({ driveViews: { column: px === COLUMN ? null : String(px) } });
  };
  return (
    <div ref={strip} className={css.columns}>
      {paths.map((path, i) => (
        <Column key={path} owner={owner} at={{ ...at, path }} next={parts[i] ?? null} shown={shown} empty={i === 0 ? empty : undefined}
          every={all ?? kept} dragging={dragging} onDrag={setDragging} onEvery={setEvery} />
      ))}
    </div>
  );
}

function Column({ owner, at, next, shown, empty, every, dragging, onDrag, onEvery }: {
  owner: Owner; at: At; next: string | null; shown: Shown; empty?: ReactNode;
  every: number; dragging: Dragging; onDrag: (d: Dragging) => void; onEvery: (px: number) => void;
}) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = shown.arranged(at, folder.value?.entries ?? []);
  const scroller = useKeptScroll<HTMLDivElement>(owner, at, "columns", (folder.value !== undefined && entries !== undefined) || folder.error !== null);
  const zone = useDropZone(shown.dropOn?.(at));
  const own = shown.widthOf(at.path);
  const width = dragging && (dragging.path === null || dragging.path === at.path) ? dragging.px : own ?? every;
  // As wide as its longest name needs (narrower too), its rows as they are drawn.
  const fit = () => {
    const el = scroller.current;
    if (!el) return;
    let need = -Infinity;
    for (const name of el.querySelectorAll<HTMLElement>(`.${css.name}`)) {
      const range = document.createRange();
      range.selectNodeContents(name);
      need = Math.max(need, range.getBoundingClientRect().width - name.clientWidth);
    }
    if (need !== -Infinity) shown.keepWidth(at.path, clampColumn(width + Math.ceil(need) + 1));
  };
  return (
    <div className={css.columnBox} style={{ width }}>
      <div ref={scroller} className={css.column} data-drop={zone.over || undefined} {...zone.props} onClick={(e) => { if (e.target === e.currentTarget) shown.clear(); }}>
        {folder.error ? <p className={`${css.treeNote} ${css.treeError}`}>{folder.error.message}</p>
          : !folder.value || !entries ? <div className={css.treeNote}><WaitLine /></div>
          : !entries.length ? (empty ?? <p className={`${css.treeNote} ${shellCss.muted}`}>{t("web-pages.drive.emptyFolder")}</p>)
          : entries.map((e) => <DriveRow key={e.name} at={at} entry={e} row={shown.rowOf(at, e)} compact column along={e.name === next} />)}
      </div>
      <ColumnEdge width={width} dragging={dragging !== null && (dragging.path === null || dragging.path === at.path)}
        onMove={(px, every) => onDrag({ path: every ? null : at.path, px })}
        onDone={(px, every) => { if (every) onEvery(px); else shown.keepWidth(at.path, px); onDrag(null); }}
        onFit={fit} />
    </div>
  );
}

/** A column's edge (as the app's other columns' edges look, ui.tsx ResizeHandle): dragged, its width; ⌥ held, every one's. */
function ColumnEdge({ width, dragging, onMove, onDone, onFit }: {
  width: number; dragging: boolean; onMove: (px: number, every: boolean) => void; onDone: (px: number, every: boolean) => void; onFit: () => void;
}) {
  const tip = usePointerTip();
  const words = t("web-pages.drive.resizeColumn");
  return (
    <>
      <div className={`${resizeHandle} ${css.columnEdge}`} data-edge="right" data-active={dragging || undefined} role="separator" aria-orientation="vertical"
        aria-label={words} {...tip.on} onDoubleClick={onFit}
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          tip.hide();
          const handle = e.currentTarget;
          const from = e.clientX;
          let moved = false, px = width, every = e.altKey;
          handle.setPointerCapture(e.pointerId);
          const move = (ev: PointerEvent) => {
            if (!moved && Math.abs(ev.clientX - from) < 3) return;
            if (!moved) { moved = true; document.body.dataset.resizing = "true"; }
            px = clampColumn(width + ev.clientX - from);
            every = ev.altKey;
            onMove(px, every);
          };
          const up = () => {
            handle.removeEventListener("pointermove", move);
            handle.removeEventListener("pointerup", up);
            handle.removeEventListener("pointercancel", up);
            delete document.body.dataset.resizing;
            if (moved) onDone(px, every);
          };
          handle.addEventListener("pointermove", move);
          handle.addEventListener("pointerup", up);
          handle.addEventListener("pointercancel", up);
          e.preventDefault();
        }} />
      {!dragging && tip.draw(words, "right")}
    </>
  );
}
