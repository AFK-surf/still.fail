import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useDark } from "./theme.ts";
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
  return <Themed name="lockup" width={Math.round((height * 264) / 60)} height={height} alt={alt} className="brand-lockup" />;
}

/**
 * The sidebar's top. The buddy holds the sidebar open: it stands on the sidebar's edge pushing it, and a click closes
 * the sidebar while it hops to rest at the top left (beside the window's buttons in the desktop app); a click there
 * opens it again. On the web the name stays at the top; on a phone, where the sidebar is a page, it is the lockup.
 */
export function SidebarBrand() {
  return (
    <>
      {!window.emberDesktop && <Themed name="wordmark" width={81} height={22} alt="ember" className="brand-wordmark" />}
      {!window.emberDesktop && <span className="brand-phone"><Lockup /></span>}
      <SidebarBuddy />
    </>
  );
}

/** The wordmark alone, for a page with no sidebar (a workspace's onboarding); none in the desktop app, whose window has its title bar there. */
export function PageBrand() {
  return window.emberDesktop ? null : <Themed name="wordmark" width={81} height={22} alt="ember" className="brand-wordmark" />;
}

type Pose = "push" | "hop" | "rest";
const SIDEBAR = "ember.sidebar";

/** Whether the sidebar is closed: on the page's root (so the layout follows), and kept on this device. */
function closeSidebar(closed: boolean) {
  if (closed) document.documentElement.dataset.sidebar = "closed";
  else delete document.documentElement.dataset.sidebar;
  try { localStorage.setItem(SIDEBAR, closed ? "closed" : "open"); } catch { /* private mode: for this page only */ }
}

function SidebarBuddy() {
  const [closed, setClosed] = useState(() => document.documentElement.dataset.sidebar === "closed");
  const [pose, setPose] = useState<Pose>(closed ? "rest" : "push");
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  const toggle = () => {
    const next = !closed;
    // It moves (and the sidebar with it) only now: resizing the sidebar follows the pointer at once.
    document.documentElement.dataset.sidebarMoving = "";
    setTimeout(() => { delete document.documentElement.dataset.sidebarMoving; }, 420);
    setClosed(next);
    closeSidebar(next);
    // It hops on the way, and lands in the pose of where it goes.
    setPose("hop");
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setPose(next ? "rest" : "push"), 380);
  };
  // On the page itself, not in the sidebar: a closed sidebar clips what is in it, and the desktop app's window would
  // then take a click on the buddy for a drag of the window.
  return createPortal(
    <button type="button" className="sidebar-buddy" data-pose={pose} onClick={toggle} aria-label={closed ? "展开侧边栏" : "收起侧边栏"} title={closed ? "展开侧边栏" : "收起侧边栏"}>
      <Themed name={`buddy/${pose}`} width={28} height={28} />
    </button>,
    document.body,
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
  return <img className="illus" src={illustrationUrl(name)} alt="" width={width} height={height} decoding="sync" />;
}
