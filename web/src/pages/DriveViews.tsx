// The ways a folder of a station's drive is shown (the files' page, a chat's 文件 tab), switched over its list and kept
// for each place on this device (prefs' `driveViews`): columns (the default: a column a folder, from where it is to
// the one open, as Finder's), a tree (folders opened in place, several at once), or a list (one folder). Each row is
// the same (DriveRow): opened, dragged, its menu on a right click; the place says what a row does (`rowOf`).
import { Fragment, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { DriveEntry } from "../core/shapes.ts";
import { joinPath, useFolder, type At } from "../drive/model.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { ViewColumns, ViewTree, List } from "../icons.tsx";
import { ICON, Tip, type MenuItem } from "../ui.tsx";
import { DriveRow } from "./Drive.tsx";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";

export type DriveView = "columns" | "tree" | "list";
/** What a row of a folder does: its menu, and what opening it does (a file opened; a folder gone into). */
export type RowOf = (at: At, entry: DriveEntry) => { items: MenuItem[]; open: () => void };

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

/** A folder and, under each of its folders opened, that one's, in by a step each: opened and closed in place. */
export function TreeView({ at, rowOf, compact = false, empty }: { at: At; rowOf: RowOf; compact?: boolean; empty?: ReactNode }) {
  const [open, setOpen] = useState<ReadonlySet<string>>(new Set());
  const toggle = (path: string) => setOpen((was) => {
    const next = new Set(was);
    if (next.has(path)) next.delete(path); else next.add(path);
    return next;
  });
  return <TreeFolder at={at} depth={0} open={open} toggle={toggle} rowOf={rowOf} compact={compact} empty={empty} />;
}

function TreeFolder({ at, depth, open, toggle, rowOf, compact, empty }: {
  at: At; depth: number; open: ReadonlySet<string>; toggle: (path: string) => void; rowOf: RowOf; compact: boolean; empty?: ReactNode;
}) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = folder.value?.entries ?? [];
  const note = (words: string, error = false) => <p className={`${css.treeNote} ${error ? css.treeError : shellCss.muted}`} style={{ "--depth": depth } as CSSProperties}>{words}</p>;
  if (folder.error) return note(folder.error.message, true);
  if (!folder.value) return note(t("web-pages.drive.reading"));
  if (!entries.length) return depth === 0 && empty ? <>{empty}</> : note(t("web-pages.drive.emptyFolder"));
  return (
    <>
      {entries.map((e) => {
        const full = joinPath(at.path, e.name);
        const row = rowOf(at, e);
        const isOpen = e.dir && open.has(full);
        return (
          <Fragment key={e.name}>
            <DriveRow at={at} entry={e} items={row.items} compact={compact} depth={depth} expanded={isOpen} onOpen={e.dir ? () => toggle(full) : row.open} />
            {isOpen && <TreeFolder at={{ ...at, path: full }} depth={depth + 1} open={open} toggle={toggle} rowOf={rowOf} compact={compact} />}
          </Fragment>
        );
      })}
    </>
  );
}

// ── columns ──

/**
 * A column a folder, from the one it starts at (`at.path` "" under its root, or where the page is) to the one open
 * (`open`, under it), each with the next open marked; a folder pressed opens next to its column (`onGo`), the
 * columns after it let go. The last is kept in view as more open.
 */
export function ColumnsView({ at, open, onGo, rowOf, empty }: { at: At; open: string; onGo: (path: string) => void; rowOf: RowOf; empty?: ReactNode }) {
  const parts = open.split("/").filter(Boolean);
  const paths = [at.path, ...parts.map((_, i) => joinPath(at.path, parts.slice(0, i + 1).join("/")))];
  const strip = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = strip.current;
    if (el) el.scrollTo({ left: el.scrollWidth, behavior: "smooth" });
  }, [open]);
  return (
    <div ref={strip} className={css.columns}>
      {paths.map((path, i) => (
        <Column key={path} at={{ ...at, path }} next={parts[i] ?? null} onGo={(name) => onGo(joinPath(parts.slice(0, i).join("/"), name))} rowOf={rowOf} empty={i === 0 ? empty : undefined} />
      ))}
    </div>
  );
}

function Column({ at, next, onGo, rowOf, empty }: { at: At; next: string | null; onGo: (name: string) => void; rowOf: RowOf; empty?: ReactNode }) {
  const folder = useFolder(at.station, at.root, at.path);
  const entries = folder.value?.entries ?? [];
  return (
    <div className={css.column}>
      {folder.error ? <p className={`${css.treeNote} ${css.treeError}`}>{folder.error.message}</p>
        : !folder.value ? <p className={`${css.treeNote} ${shellCss.muted}`}>{t("web-pages.drive.reading")}</p>
        : !entries.length ? (empty ?? <p className={`${css.treeNote} ${shellCss.muted}`}>{t("web-pages.drive.emptyFolder")}</p>)
        : entries.map((e) => {
          const row = rowOf(at, e);
          return <DriveRow key={e.name} at={at} entry={e} items={row.items} compact column selected={e.name === next} onOpen={e.dir ? () => onGo(e.name) : row.open} />;
        })}
    </div>
  );
}
