import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
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
// still.fail's brand, from web/public (design/brand/README.md): the mark (s. in Inter Bold, its dot still.fail's
// orange), the wordmark and the illustrations. Mark and wordmark have -dark twins, picked by the page's 外观 like the
// rest of the app; the illustrations switch themselves.

const BASE = import.meta.env.BASE_URL;

// On the test channel (app.youdid.wtf, the beta desktop app) the name is its own, drawn the same way.
const OWN = NAME !== "still.fail";
// Each drawing's size, in still.fail's: youdid.wtf's y goes below the line, its drawing taller at the same scale.
const WORDMARK = OWN ? { name: "wordmark-beta", width: 393.41, height: 79.39 } : { name: "wordmark", width: 255.16, height: 63.13 };
const WORD_HEIGHT = 63.13;

/** A light asset and its -dark twin, as the page's 外观 has it. */
function Themed({ name, width, height, alt = "", className }: { name: string; width: number; height: number; alt?: string; className?: string | undefined }) {
  const dark = useDark();
  return <img className={className} src={`${BASE}${name}${dark ? "-dark" : ""}.svg`} alt={alt} width={width} height={height} />;
}

/** The mark, s. (its square as wide as the s. nearly). */
export function Mark({ size, className }: { size: number; className?: string }) {
  return <Themed name="mark" width={size} height={size} className={className} />;
}

/** The name, still.fail (youdid.wtf on the test channel), `size` high as still.fail is drawn. */
export function Wordmark({ size = 22, className }: { size?: number; className?: string }) {
  const k = size / WORD_HEIGHT;
  return <Themed name={WORDMARK.name} width={Math.round(WORDMARK.width * k)} height={Math.round(WORDMARK.height * k)} alt={NAME} className={className} />;
}

/** The macOS app's window: its buttons are in the page's top row at the left, no room for the name (Windows' are at the right). */
const titleless = () => !!window.stillfailDesktop && (window.stillfailDesktop.frame ?? "inset") === "inset";

/**
 * The sidebar's top: the name (on a phone, where the sidebar is a page; and on the web and in the Windows app with no
 * rail). Beside the rail (Rail.tsx) the top is the window's: its buttons, 更新; the rail opens and closes the sidebar.
 */
export function SidebarBrand({ rail }: { rail?: boolean }) {
  return (
    <>
      {!titleless() && !rail && <Wordmark className={css.brandWordmark} />}
      {!titleless() && <span className={css.brandPhone}><Wordmark size={24} className={css.brandBlock} /></span>}
      {/* Beside the rail the app's newer build is one of its bubbles (SystemBubbles.tsx). */}
      {!rail && <UpdateButton />}
    </>
  );
}

/** The wordmark alone, for a page with no sidebar (a workspace's onboarding); none in the desktop app on macOS, whose window has its buttons there. */
export function PageBrand() {
  return titleless() ? null : <Wordmark className={css.brandWordmark} />;
}

const SIDEBAR = "stillfail.sidebar";

/** Whether the sidebar is closed: on the page's root (so the layout follows), and kept on this device. */
function closeSidebar(closed: boolean) {
  if (closed) document.documentElement.dataset.sidebar = "closed";
  else delete document.documentElement.dataset.sidebar;
  try { localStorage.setItem(SIDEBAR, closed ? "closed" : "open"); } catch { /* private mode: for this page only */ }
}

/** Where the update button is put: the page, unless the app is drawn in a part of one (the site's demo). */
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
  // One place on the page holds the shortcut (the rail).
  useShortcut("sidebar.toggle", owns ? toggle : null);
  useKeymap();
  const keys = shortcutOf("sidebar.toggle");
  return { closed, toggle, label: `${closed ? t("web-main.sidebar.open") : t("web-main.sidebar.close")}${keys ? `  ${keys}` : ""}` };
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
 * The desktop app has a newer build: 更新 at the sidebar's top. Clicked, the build is downloaded (the
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
