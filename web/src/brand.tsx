import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useDark } from "./theme.ts";
import type { AppUpdate } from "./core/client.ts";
import { shortcutOf, useKeymap, useShortcut } from "./keymap.ts";
import * as css from "./brand.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import { moveState } from "./motion.ts";
import { Tip } from "./ui.tsx";
// ember's brand, from web/public (see the brand package's brand.md): the station
// buddy mark, the lockup and the illustrations. Marks and lockup have -dark twins,
// picked by the OS theme like the rest of the app; the illustrations switch themselves.

const BASE = import.meta.env.BASE_URL;

/** A light asset and its -dark twin, as the page's 外观 has it. */
function Themed({ name, width, height, alt = "", className }: { name: string; width: number; height: number; alt?: string; className?: string | undefined }) {
  const dark = useDark();
  return <img className={className} src={`${BASE}${name}${dark ? "-dark" : ""}.svg`} alt={alt} width={width} height={height} />;
}

/** The buddy: the simplified 16-grid drawing up to 16 px, the full one from 22 px. */
export function Mark({ size, className }: { size: number; className?: string }) {
  return <Themed name={size <= 16 ? "mark-16" : "mark"} width={size} height={size} className={className} />;
}

/** Buddy and name; 132 × 30 at the smallest. */
export function Lockup({ height = 30, alt = "ember" }: { height?: number; alt?: string }) {
  return <Themed name="lockup" width={Math.round((height * 264) / 60)} height={height} alt={alt} className={css.brandLockup} />;
}

/**
 * The sidebar's top. The buddy holds the sidebar open: it stands on the sidebar's edge pushing it, and a click closes
 * the sidebar while it hops to rest at the top left (beside the window's buttons in the desktop app); a click there
 * opens it again. On the web the name stays at the top; on a phone, where the sidebar is a page, it is the lockup.
 */
export function SidebarBrand() {
  return (
    <>
      {!window.emberDesktop && <Themed name="wordmark" width={81} height={22} alt="ember" className={css.brandWordmark} />}
      {!window.emberDesktop && <span className={css.brandPhone}><Lockup /></span>}
      <SidebarBuddy />
      <UpdateButton />
    </>
  );
}

/** The wordmark alone, for a page with no sidebar (a workspace's onboarding); none in the desktop app, whose window has its title bar there. */
export function PageBrand() {
  return window.emberDesktop ? null : <Themed name="wordmark" width={81} height={22} alt="ember" className={css.brandWordmark} />;
}

type Pose = "push" | "hop" | "rest";
const SIDEBAR = "ember.sidebar";

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

function SidebarBuddy() {
  const [closed, setClosed] = useState(() => document.documentElement.dataset.sidebar === "closed");
  const [pose, setPose] = useState<Pose>(closed ? "rest" : "push");
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  const toggle = () => {
    const next = !closed;
    // It moves (and the sidebar with it, the page bars' room for it, 更新 by it) only now: resizing the sidebar follows
    // the pointer at once.
    const moves = (selector: string, props: string[]) => [...document.querySelectorAll<HTMLElement>(selector)].map((el) => [el, props] as [HTMLElement, string[]]);
    moveState([
      ...moves(`.${shellCss.shell}`, ["grid-template-columns"]),
      ...moves(`.${css.sidebarBuddy}`, ["left"]),
      ...moves(`.${css.sidebarUpdate}`, ["left", "transform"]),
      ...moves(`.${sidebarCss.pageBar}`, ["padding-left"]),
    ], () => closeSidebar(next));
    setClosed(next);
    // It hops on the way, and lands in the pose of where it goes.
    setPose("hop");
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setPose(next ? "rest" : "push"), 380);
  };
  useShortcut("sidebar.toggle", toggle);
  useKeymap();
  const keys = shortcutOf("sidebar.toggle");
  // On the page itself, not in the sidebar: a closed sidebar clips what is in it, and the desktop app's window would
  // then take a click on the buddy for a drag of the window.
  const buddy = (
    <Tip label={`${closed ? "展开侧边栏" : "收起侧边栏"}${keys ? `  ${keys}` : ""}`}><button type="button" className={css.sidebarBuddy} data-pose={pose} onClick={toggle} aria-label={closed ? "展开侧边栏" : "收起侧边栏"}>
      <Themed name={`buddy/${pose}`} width={28} height={28} />
    </button></Tip>
  );
  return onPage(buddy);
}

/**
 * The desktop app has a newer build: 更新 beside the buddy, wherever it stands. Clicked, the build is downloaded (the
 * button says how far) and the app restarts as it.
 */
function UpdateButton() {
  const updates = window.emberDesktop?.appUpdate;
  const [state, setState] = useState<AppUpdate | null>(null);
  useEffect(() => {
    if (!updates) return;
    let live = true;
    void updates.state().then((s) => { if (live) setState(s); });
    const stop = updates.watch(setState);
    return () => { live = false; stop(); };
  }, [updates]);
  if (!updates || !state) return null;
  const label = state.phase === "downloading" ? `下载中 ${state.percent}%` : state.phase === "installing" ? "正在重启…" : state.phase === "failed" ? "更新失败，重试" : "更新";
  const busy = state.phase === "downloading" || state.phase === "installing";
  const title = state.phase === "failed" ? state.message : `更新到 ${state.version}：下载后 ember 会重启`;
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
export function Illustration({ name }: { name: Illus }) {
  const [width, height] = ILLUS_SIZE[name];
  return <img className={css.illus} src={illustrationUrl(name)} alt="" width={width} height={height} decoding="sync" />;
}
