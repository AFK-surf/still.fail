// What a chat's page (ChatPage.tsx) and a new chat's (../NewChat.tsx) share: the side panel that slides in beside the
// page, its 文件 tab (DriveTab.tsx), and the page as a place to drop files on.
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Tabs } from "radix-ui";
import { Close, Folder } from "@stillfail/ui/icons.tsx";
import { animate, EASE_OUT, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import { scopeOf } from "../station.tsx";
import { useTopicSelect } from "../core/react.ts";
import type { StationView } from "../core/shapes.ts";
import { carriesDrive, draggedNow, droppedFrom, droppedFromFinder, droppedOf, endDrag, nameByType, setDropOver } from "../drive/drag.ts";
import { takeOff } from "../drive/flight.ts";
import { offerToDraft } from "../draft.ts";
import { useThisMachine } from "../thisMachine.ts";
import { FileTile } from "../Chat.tsx";
import { keptWidth } from "../ui.tsx";
import * as css from "./ChatPage.css.ts";
import { t } from "../i18n.ts";

/** Pressed, the panel's switch leaves the focus where it was: the composer, typed in, keeps it (and its shape; taking
 * it away folded the composer to a capsule in the same frames the panel slid in). */
export const keepFocus = (e: { preventDefault(): void }) => e.preventDefault();

/**
 * The side panel's width beside a page `page` wide, as its styles lay it out (session.css.ts: the width dragged, else
 * 38% and at least 360, leaving the chat 360; ChatPage.css.ts: over the chat where the page is narrow).
 */
function panelWidth(page: number, narrow: boolean): number {
  if (narrow) return Math.min(460, window.innerWidth);
  // The width dragged, as it is kept (and on the root from here on): read off the root alone, it was not there at the
  // first opening after a load (its handle puts it there, once the panel is made), and the panel slid in at the width
  // of none dragged, then jumped to the one kept.
  const wanted = keptWidth("--panel-w", PANEL_MIN, PANEL_MAX) ?? Math.max(360, Math.floor(page * 0.38));
  return Math.max(0, Math.min(wanted, page - 360));
}
/** How narrow and how wide the side panel is dragged. */
export const PANEL_MIN = 320;
export const PANEL_MAX = 960;

/** The panel as it was when its last tab closed, kept while it slides out over the page (which takes the room at once). */
export type Leaving = { tabs: string[]; shown: string; width: number };

/**
 * The side panel of a page with the tabs `open`, `shown` in front: where it is (`pageRef` on the page, `panelRef` on the
 * panel), what it shows (`side`: its tabs, or while it slides out, what it showed), and `changing`, told as its tabs
 * are asked to change whether any will be open (they come as the core has them, a moment later: it slides in once
 * they are there, out once they are gone). Opened, the panel's column widens from nothing and the page narrows with
 * it, frame by frame; closed, the other way. The panel keeps its whole width all along and shows through its column
 * as it grows, so it comes in from the right edge without its content re-laying out. Turned back on its way, it goes
 * on from the width it has. Where the panel lies over the page (`max-width: 1100px`) it slides instead.
 */
export function useSidePanel(open: string[], shown: string | null) {
  const pageRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const [leaving, setLeaving] = useState<Leaving | null>(null);
  // Whether the panel is being opened here (it slides in then), not shown with the page as it was left.
  const [opening, setOpening] = useState(false);
  const changing = (any: boolean) => {
    if (any) {
      setLeaving(null);
      if (open.length === 0) setOpening(true);
    } else {
      setOpening(false);
      if (open.length && shown && panelRef.current) setLeaving({ tabs: open, shown, width: panelRef.current.getBoundingClientRect().width });
    }
  };
  const sliding = leaving && !(open.length && shown) ? "out" : opening && open.length && shown ? "in" : null;
  const slide = useRef<{ run?: AnimationPlaybackControls; value: number } | null>(null);
  // The page's width as last laid out, told by an observer: the panel's width is worked out from it (as its styles
  // have it) rather than read off the panel just made, which laid the whole page out in the middle of the commit and
  // again for the frame.
  const pageWidth = useRef(0);
  useLayoutEffect(() => {
    // The width dragged for the panel is on the root from the page's first frame, not from the panel's first opening:
    // put there then, the whole page was styled anew in the frame of the click.
    keptWidth("--panel-w", PANEL_MIN, PANEL_MAX);
    const page = pageRef.current;
    if (!page) return;
    const seen = new ResizeObserver(([entry]) => { if (entry) pageWidth.current = entry.borderBoxSize[0]?.inlineSize ?? entry.contentRect.width; });
    seen.observe(page);
    return () => seen.disconnect();
  }, []);
  useLayoutEffect(() => {
    const page = pageRef.current;
    const el = panelRef.current;
    // Slid out: the page has laid itself out without the panel now, so the column it held is let go of in the same frame.
    if (!sliding) {
      page?.style.removeProperty("grid-template-columns");
      page?.style.removeProperty("--panel-visible-width");
      return;
    }
    if (!page || !el) return;
    const was = slide.current;
    was?.run?.stop();
    const narrow = matchMedia("(max-width: 1100px)").matches;
    // Its width at rest, without what the motion holds.
    page.style.removeProperty("grid-template-columns");
    el.style.removeProperty("width");
    el.style.removeProperty("transform");
    const whole = sliding === "out" && leaving ? leaving.width : panelWidth(pageWidth.current || page.getBoundingClientRect().width, narrow);
    const start = was ? was.value : sliding === "in" ? 0 : whole;
    const goal = sliding === "in" ? whole : 0;
    const draw = (v: number) => {
      page.style.setProperty("--panel-visible-width", `${v}px`);
      el.style.width = `${whole}px`;
      if (narrow) el.style.transform = `translateX(${whole - v}px)`;
      else page.style.gridTemplateColumns = `minmax(0, 1fr) ${v}px`;
    };
    draw(start);
    // With reduced motion, motion calls its last update after its end: drawn then, the motion's width stayed on the
    // page for good (the chat crushed beside a panel as wide as it was when opened, once the window or the sidebar
    // left less room). Updates count only while it is the current one, known as such before it starts.
    const now: { value: number; run?: AnimationPlaybackControls } = { value: start };
    slide.current = now;
    now.run = animate(start, goal, {
      duration: sliding === "in" ? 0.28 : 0.24, ease: EASE_OUT,
      onUpdate: (v) => { if (slide.current !== now) return; now.value = v; draw(v); },
      onComplete: () => {
        if (slide.current !== now) return;
        slide.current = null;
        if (sliding === "out") return setLeaving(null);
        page.style.removeProperty("grid-template-columns");
        el.style.removeProperty("width");
        el.style.removeProperty("transform");
        setOpening(false);
      },
    });
  }, [sliding]);
  const side = open.length && shown ? { tabs: open, shown } : leaving;
  return { pageRef, panelRef, leaving, side, changing };
}

/** The 文件 tab's key: the files of the workspace's stations (DriveTab.tsx). */
export const FILES = "files";

/** Whether any station of the workspace `station` is in has files to show (one from before the drive has none): only
 * that, so the page is not drawn again for the rest of their overviews. */
export function useStationDrive(station: string): boolean {
  return useTopicSelect<StationView[], boolean>({ topic: "stations", scope: scopeOf(station) }, (s) => !!s.value?.some((x) => x.overview?.drive));
}
/** A side tab's and its pane's ids, each naming the other (a tab's key can hold a space; an id cannot). */
export function tabId(key: string): string { return `side-tab-${encodeURIComponent(key)}`; }
export function paneId(key: string): string { return `side-pane-${encodeURIComponent(key)}`; }
/** A side tab's pane: there while its tab is the one shown, `kept` there (not shown) under another too. Not Radix's
 * Tabs.Content, which reads its animation's name as it comes in: the style of the page worked out in the middle of
 * the panel opening. */
export function SidePane({ of, shown, kept = false, children }: { of: string; shown: string; kept?: boolean; children?: ReactNode }) {
  const active = of === shown;
  if (!active && !kept) return null;
  return <div className={css.sideContent} role="tabpanel" id={paneId(of)} aria-labelledby={tabId(of)} data-state={active ? "active" : "inactive"} tabIndex={0}>{children}</div>;
}
/** The 文件 tab in the panel's bar, closed by its ×. */
export function FilesTab({ onClose }: { onClose(): void }) {
  return (
    <span className={css.sideTabWrap}>
      <Tabs.Trigger className={css.sideTab} value={FILES} id={tabId(FILES)} aria-controls={paneId(FILES)}>
        <span className={css.sideTabAgent}><Folder size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-pages.chat.files")}>{t("web-pages.chat.files")}</span></span>
      </Tabs.Trigger>
      <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.closeFiles")} onClick={onClose}><Close size={12} strokeWidth={2} /></button>
    </span>
  );
}

/** What is dragged over the chat, each shown by its mark (Chat.tsx FileTile): its name (or one its type gives), whether
 * it is a folder. */
type Over = { kind: "path" | "file"; marks: { name: string; dir: boolean }[] };

/**
 * The chat as a place to drop files on, all of it: while they are over it, it frosts over and shows them, each by its
 * mark (as its card will have it), with what letting go does (DropHint); let go, they go into its message (the draft
 * `chat`), and their marks fly there, each onto its card (drive/flight.ts). The composer leaves a drop on it to this.
 */
export function useChatDrop(chat: string, station: string) {
  const here = useThisMachine(station);
  const [over, setOver] = useState<Over | null>(null);
  // Let go: the frost going while the marks fly off it.
  const [leaving, setLeaving] = useState<string | null>(null);
  const depth = useRef(0);
  const shown = useRef<HTMLDivElement>(null);
  // The composer knows files are over its chat, and leaves them to it (Chat.tsx).
  useEffect(() => {
    setDropOver(over?.kind ?? null);
    return () => setDropOver(null);
  }, [over?.kind]);
  const kind = (dt: DataTransfer): "path" | "file" | null =>
    carriesDrive(dt) ? "path" : dt.types.includes("Files") ? (here && window.stillfailDesktop?.pathOf ? "path" : "file") : null;
  // A station's files dragged from this page are known by name; Finder's only by type, until they are dropped.
  const marks = (dt: DataTransfer) => carriesDrive(dt)
    ? (draggedNow() ?? []).map((d) => ({ name: d.name, dir: d.dir }))
    : [...dt.items].filter((i) => i.kind === "file").map((i) => ({ name: nameByType(i.type), dir: false }));
  const label = (o: Over) => (o.marks.length > 1 ? t("web-main.composer.dropMany", { n: o.marks.length }) : t("web-main.composer.dropHere"));
  const handlers = {
    onDragEnter: (e: React.DragEvent) => {
      const k = kind(e.dataTransfer);
      if (!k) return;
      depth.current++;
      if (depth.current === 1) setOver({ kind: k, marks: marks(e.dataTransfer) });
    },
    onDragOver: (e: React.DragEvent) => { if (!kind(e.dataTransfer)) return; e.preventDefault(); e.dataTransfer.dropEffect = "copy"; },
    onDragLeave: (e: React.DragEvent) => { if (!kind(e.dataTransfer)) return; depth.current = Math.max(0, depth.current - 1); if (depth.current === 0) setOver(null); },
    onDrop: (e: React.DragEvent) => {
      depth.current = 0;
      if (e.defaultPrevented || !kind(e.dataTransfer)) { setOver(null); return; }
      e.preventDefault();
      // Their marks take off from where they are shown; the frost fades as they fly.
      takeOff([...(shown.current?.querySelectorAll("svg") ?? [])]);
      setLeaving(over ? label(over) : null);
      setOver(null);
      endDrag();
      if (carriesDrive(e.dataTransfer)) { offerToDraft(chat, { files: [], quotes: [], dropped: droppedOf(e.dataTransfer).map(droppedFrom) }); return; }
      const named = droppedFromFinder(e.dataTransfer, here);
      offerToDraft(chat, named ? { files: [], quotes: [], dropped: named } : { files: [...e.dataTransfer.files], quotes: [] });
    },
  };
  return { over, leaving, gone: () => setLeaving(null), handlers, shown, label };
}

/** Files over the chat (useChatDrop): it frosts over, and says where they go. */
export function DropHint({ drop }: { drop: ReturnType<typeof useChatDrop> }) {
  return (
    <>
      {drop.leaving && !drop.over && <div className={css.dropHint} data-leaving="" aria-hidden="true" onAnimationEnd={drop.gone}><div className={css.dropMarks} /><span>{drop.leaving}</span></div>}
      {drop.over && (
        <div className={css.dropHint} aria-hidden="true">
          {/* What is dragged, each by its mark, a few fanned out as a stack. */}
          <div ref={drop.shown} className={css.dropMarks} style={{ "--n": Math.min(3, Math.max(1, drop.over.marks.length)) } as CSSProperties}>
            {(drop.over.marks.length ? drop.over.marks : [{ name: "file", dir: false }]).slice(0, 3).map((m, i) => (
              <FileTile key={i} name={m.name} dir={m.dir} style={{ "--i": i } as CSSProperties} />
            ))}
          </div>
          <span>{drop.label(drop.over)}</span>
        </div>
      )}
    </>
  );
}
