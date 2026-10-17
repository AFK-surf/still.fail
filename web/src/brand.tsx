import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useDark } from "./theme.ts";
import type { AppUpdate } from "./core/client.ts";
import { shortcutOf, useKeymap, useShortcut } from "./keymap.ts";
import * as css from "./brand.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import * as railCss from "./Rail.css.ts";
import * as listCss from "./Sidebar.css.ts";
import * as bubblesCss from "./SystemBubbles.css.ts";
import { moveState } from "@stillfail/ui/motion.ts";
import { Tip } from "./ui.tsx";
import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
// still.fail's brand, from web/public (see the brand package's brand.md): the station
// buddy mark, the lockup and the illustrations. Marks and lockup have -dark twins,
// picked by the OS theme like the rest of the app; the illustrations switch themselves.

const BASE = import.meta.env.BASE_URL;

// On the test channel (app.youdid.wtf, the beta desktop app) the name is its own, drawn the same way.
const OWN = NAME !== "still.fail";
// youdid.wtf's y goes below the line: its drawing is taller (64 to still.fail's 60), at the same scale.
const WORDMARK = OWN ? { name: "wordmark-beta", width: 128, height: 23.5 } : { name: "wordmark", width: 81, height: 22 };
const LOCKUP = OWN ? { name: "lockup-beta", width: 371 } : { name: "lockup", width: 264 };

/** A light asset and its -dark twin, as the page's 外观 has it. */
function Themed({ name, width, height, alt = "", className }: { name: string; width: number; height: number; alt?: string; className?: string | undefined }) {
  const dark = useDark();
  return <img className={className} src={`${BASE}${name}${dark ? "-dark" : ""}.svg`} alt={alt} width={width} height={height} />;
}

/** The buddy's face, idle (as a station with nothing to do has it; Android's buddy_idle). */
export function IdleFace({ size, className }: { size: number; className?: string }) {
  return <Themed name="idle" width={size} height={size} className={className} />;
}

/** The buddy: the simplified 16-grid drawing up to 16 px, the full one from 22 px. */
export function Mark({ size, className }: { size: number; className?: string }) {
  return <Themed name={size <= 16 ? "mark-16" : "mark"} width={size} height={size} className={className} />;
}

/** Buddy and name; 132 × 30 at the smallest. */
export function Lockup({ height = 30, alt = NAME }: { height?: number; alt?: string }) {
  return <Themed name={LOCKUP.name} width={Math.round((height * LOCKUP.width) / 60)} height={height} alt={alt} className={css.brandLockup} />;
}

/** The macOS app's window: its buttons are in the page's top row at the left, no room for the name (Windows' are at the right). */
const titleless = () => !!window.stillfailDesktop && (window.stillfailDesktop.frame ?? "inset") === "inset";

/**
 * The sidebar's top. The buddy holds the sidebar open: it stands on the sidebar's edge pushing it, and a click closes
 * the sidebar while it hops to rest at the top left (beside the window's buttons in the desktop app); a click there
 * opens it again. On the web and in the Windows app the name stays at the top; on a phone, where the sidebar is a page, it is the lockup.
 */
export function SidebarBrand({ rail }: { rail?: boolean }) {
  // Beside the rail (Rail.tsx) the top is the window's: its buttons, 更新; the rail opens and closes the sidebar.
  return (
    <>
      {!titleless() && !rail && <Themed name={WORDMARK.name} width={WORDMARK.width} height={WORDMARK.height} alt={NAME} className={css.brandWordmark} />}
      {!titleless() && <span className={css.brandPhone}><Lockup /></span>}
      {!rail && <SidebarBuddy />}
      {/* Beside the rail the app's newer build is one of its bubbles (SystemBubbles.tsx). */}
      {!rail && <UpdateButton />}
    </>
  );
}

/** The wordmark alone, for a page with no sidebar (a workspace's onboarding); none in the desktop app on macOS, whose window has its buttons there. */
export function PageBrand() {
  return titleless() ? null : <Themed name={WORDMARK.name} width={WORDMARK.width} height={WORDMARK.height} alt={NAME} className={css.brandWordmark} />;
}

type Pose = "push" | "hop" | "rest";
const SIDEBAR = "stillfail.sidebar";

/** Whether the sidebar is closed: on the page's root (so the layout follows), and kept on this device. */
function closeSidebar(closed: boolean) {
  if (closed) document.documentElement.dataset.sidebar = "closed";
  else delete document.documentElement.dataset.sidebar;
  try { localStorage.setItem(SIDEBAR, closed ? "closed" : "open"); } catch { /* private mode: for this page only */ }
}

/** Where the buddy (and the update button by it) is put: the page, unless the app is drawn in a part of one (the site's demo). */
let pageRoot: HTMLElement | null = null;
export function setPageRoot(element: HTMLElement): void {
  pageRoot = element;
}

/** Put on the page (pageRoot), or in place where there is no page yet (the site built to HTML, where it lands the same). */
function onPage(node: ReactNode): ReactNode {
  const page = pageRoot ?? document.body;
  return page ? createPortal(node, page) : node;
}

/** The sidebar's latest opening or closing: only its end lets the sidebar overflow again. */
let moving = 0;

/**
 * The sidebar opened, closed or made wider or narrower by `change`, the page following as it moves (and the sidebar with
 * it, the page bars' room for it, 更新 by it). Only so: resizing the sidebar follows the pointer at once.
 */
export function moveSidebar(change: () => void): void {
  const moves = (selector: string, props: string[]) => [...document.querySelectorAll<HTMLElement>(selector)].map((el) => [el, props] as [HTMLElement, string[]]);
  // Cut to its column while it moves, opening too (open, it is not: its resize handle stands over its edge). Else what
  // is drawn over the list (its frosted top and foot) shows at its whole width over the page from the first frame.
  const turn = ++moving;
  document.documentElement.dataset.sidebarMoving = "";
  void moveState([
    ...moves(`.${shellCss.shell}`, ["grid-template-columns"]),
    // The page as wide as it was, moved aside for the folded sidebar shown a while (shell.css.ts main, Rail.tsx peekShift).
    ...moves(`.${shellCss.shell} > .${shellCss.main}`, ["left"]),
    ...moves(`.${css.sidebarBuddy}`, ["left"]),
    ...moves(`.${css.sidebarUpdate}`, ["left", "transform"]),
    ...moves(`.${railCss.edge}`, ["left"]),
    // The rail as narrow as the closed bar and its places as far from its edges, with its margins (no transitions of
    // their own: on other clocks and eases they shook the places).
    ...moves(`.${railCss.rail}`, ["width", "padding-top", "padding-bottom"]),
    ...moves(`.${railCss.top}`, ["height", "margin-bottom"]),
    // The block's margins (closed, it stands off the window's edges; shown a while, it reaches over the page) at the same
    // pace as its column, not a transition of their own that would run ahead of it.
    // Its corner, ground, shadow and line as well: every part of it on one clock and ease (Motion), no CSS transitions.
    ...moves(`.${shellCss.dock}`, ["margin-top", "margin-right", "margin-bottom", "margin-left", "border-radius", "background-color", "box-shadow", "--dock-line"]),
    // The sidebar in it (open, reaching 8 into the rail; its width the group's) and its frosted bands' ground.
    ...moves(`.${shellCss.dock} > .${listCss.sidebar}`, ["margin-inline-start", "width"]),
    ...moves(`.${listCss.navTop}, .${listCss.navFoot}`, ["background-color"]),
    // Its top row, none in the closed bar (under the window's buttons).
    ...moves(`.${listCss.brand}`, ["height"]),
    // The lists' marks on the rail, and the app's bubbles beside it.
    ...moves(`.${railCss.listMark}`, ["opacity", "transform"]),
    ...moves(`.${bubblesCss.stack}`, ["left", "bottom"]),
    ...moves(`.${sidebarCss.pageBar}`, ["padding-left", "margin-left", "margin-right"]),
  ], change).then(() => { if (turn === moving) delete document.documentElement.dataset.sidebarMoving; });
}

/**
 * Opening and closing the sidebar (its shortcut too, unless `keys` is false: one place on the page holds it), the page
 * following as it moves; `moved` is told where it goes as it starts.
 */
/** Whether the sidebar is closed, as the page's root says: the same to everything reading it. */
export function useSidebarClosed(): boolean {
  return useSyncExternalStore((changed) => {
    const watch = new MutationObserver(changed);
    watch.observe(document.documentElement, { attributes: true, attributeFilter: ["data-sidebar"] });
    return () => watch.disconnect();
  }, () => document.documentElement.dataset.sidebar === "closed", () => false);
}

/** Told when the person opens or closes the sidebar (its edge, its shortcut), not when a place shows or hides it. */
let chosen: ((closed: boolean) => void) | null = null;
export function onSidebarChosen(told: ((closed: boolean) => void) | null): void {
  chosen = told;
}

/** The sidebar shown or not as a place has it (Rail.tsx), moving as when toggled (with `also` in the same move: its new
 * width); not the person's choice. */
export function showSidebar(open: boolean, also?: () => void): void {
  if ((document.documentElement.dataset.sidebar === "closed") !== open) { also?.(); return; }
  moveSidebar(() => { also?.(); closeSidebar(!open); });
}

export function useSidebarToggle(moved?: (closed: boolean) => void, { keys: owns = true }: { keys?: boolean } = {}): { closed: boolean; toggle: () => void; label: string } {
  const closed = useSidebarClosed();
  const toggle = () => {
    const next = !closed;
    // A page with no sidebar of its own (Rail.tsx): nothing to open.
    if (!next && "sidebarNone" in document.documentElement.dataset) return;
    chosen?.(next);
    moveSidebar(() => closeSidebar(next));
    moved?.(next);
  };
  // One place on the page holds the shortcut (the rail, or the buddy where there is none).
  useShortcut("sidebar.toggle", owns ? toggle : null);
  useKeymap();
  const keys = shortcutOf("sidebar.toggle");
  return { closed, toggle, label: `${closed ? t("web-main.sidebar.open") : t("web-main.sidebar.close")}${keys ? `  ${keys}` : ""}` };
}

function SidebarBuddy() {
  const [pose, setPose] = useState<Pose>(() => document.documentElement.dataset.sidebar === "closed" ? "rest" : "push");
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  // It hops on the way, and lands in the pose of where it goes.
  const { closed, toggle, label } = useSidebarToggle((next) => {
    setPose("hop");
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setPose(next ? "rest" : "push"), 380);
  });
  // On the page itself, not in the sidebar: a closed sidebar clips what is in it, and the desktop app's window would
  // then take a click on the buddy for a drag of the window.
  const buddy = (
    <Tip label={label}><button type="button" className={css.sidebarBuddy} data-pose={pose} onClick={toggle} aria-label={closed ? t("web-main.sidebar.open") : t("web-main.sidebar.close")}>
      <Themed name={`buddy/${pose}`} width={28} height={28} />
    </button></Tip>
  );
  return onPage(buddy);
}

/** The desktop app's newer build, as its main process says (null in a browser, or while there is none). */
export function useAppUpdate(): AppUpdate | null {
  const updates = window.stillfailDesktop?.appUpdate;
  const [state, setState] = useState<AppUpdate | null>(null);
  useEffect(() => {
    if (!updates) return;
    let live = true;
    void updates.state().then((s) => { if (live) setState(s); });
    const stop = updates.watch(setState);
    return () => { live = false; stop(); };
  }, [updates]);
  return state;
}

/**
 * The desktop app has a newer build: 更新 beside the buddy, wherever it stands. Clicked, the build is downloaded (the
 * button says how far) and the app restarts as it; a newer web app alone (kind "web") is downloaded already, and
 * clicked, the pages reload on it.
 */
function UpdateButton() {
  const updates = window.stillfailDesktop?.appUpdate;
  const state = useAppUpdate();
  if (!updates || !state) return null;
  const web = state.kind === "web";
  const label = state.phase === "downloading" ? t("web-main.appUpdate.downloading", { percent: state.percent })
    : state.phase === "installing" ? t(web ? "web-main.appUpdate.reloading" : "web-main.appUpdate.restarting")
    : state.phase === "failed" ? t("web-main.appUpdate.failed")
    : t(web ? "web-main.webUpdate.refresh" : "web-main.versions.update");
  const busy = state.phase === "downloading" || state.phase === "installing";
  const title = state.phase === "failed" ? state.message : t(web ? "web-main.appUpdate.webTitle" : "web-main.appUpdate.title", { version: state.version, app: NAME });
  return onPage(
    <Tip label={title}><button type="button" className={css.sidebarUpdate} disabled={busy} aria-busy={busy} onClick={() => updates.start()}>
      {label}
    </button></Tip>,
  );
}

type Illus = "new-chat" | "no-station" | "station-offline" | "sign-in" | "no-profile" | "no-connect";
const ILLUS_SIZE: Record<Illus, [number, number]> = {
  "new-chat": [320, 160], "no-station": [320, 160], "station-offline": [320, 160], "sign-in": [360, 200],
  "no-profile": [320, 160], "no-connect": [320, 160],
};

/**
 * The scenes, fetched and decoded as the app starts and kept: the first page to show one (a new chat) draws it in its
 * first frame, instead of an empty box that fills a moment later.
 */
export const illustrationUrl = (name: Illus) => `${BASE}illus-${name}.svg`;
const decoded = (Object.keys(ILLUS_SIZE) as Illus[]).map((name) => {
  const img = new Image();
  img.src = illustrationUrl(name);
  void img.decode().catch(() => {});
  return img;
});
void decoded;

/** A scene beside text that says the same, hence no alt. */
export function Illustration({ name, ...marks }: { name: Illus; "data-made-leave"?: string }) {
  const [width, height] = ILLUS_SIZE[name];
  return <img className={css.illus} src={illustrationUrl(name)} alt="" width={width} height={height} decoding="sync" {...marks} />;
}
