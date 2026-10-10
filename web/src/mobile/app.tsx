// The app on a narrow screen, as the Android app is (apps/android/…/App.kt): the chats of one workspace are home, and
// everything else is a page pushed over it (no tab bar), or a sheet from the bottom. Pages move side by side: the new
// one pushes in whole from the right and the old goes out to the left (and back the other way); settings (from the
// gear at the top left) come from the left instead, a new chat rises from the bottom. Each page is an address, so the browser's back and a
// link work as the desktop's do; pages under the top one stay as they were left (their scroll, what was typed). What
// lies over a page (a sheet, the menu, the reader) is closed by back first.
//
// Wider (WIDE: an opened foldable, a phone on its side), the pages are the screen's whole width, and a button at its
// bottom left, level with the composer (which starts beside it), opens the latest chats over the page: another chat
// from there takes the place of the one open.
import { transitionTo } from "../ui.tsx";
import { said, ToastTo } from "../toast.tsx";
import { afterBack, useBackClose } from "../backClose.ts";
import { backPage } from "../backPage.ts";
import { createContext, memo, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useLocation, useNavigate, useNavigationType, type Location } from "react-router";
import type { Account } from "../cloud/accounts.ts";
import { NavBack } from "./parts.tsx";
import { Chats } from "../icons.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as css from "./app.css.ts";
import { follower, type Follower } from "../motion.ts";
import { useInWorkspace } from "../notify.ts";
import { t } from "../i18n.ts";

/** The workspace in view and the signed-in account that reaches it. */
export interface Entry { id: string; name: string; account: Account }

/** A sheet: how much of the screen it takes at first, and whether its grabber drags it. */
export interface SheetSpec { height: number; draggable?: boolean; content: () => ReactNode }
export interface MenuItem { label: string; icon: ReactNode; action: () => void }
export interface MenuSpec { anchor: DOMRect; items: MenuItem[]; onDismiss?: () => void }
/** One thing in full over everything: what it is (a line, as the history labels it), then all of it. */
export interface ReaderSpec { label: ReactNode; content: ReactNode }

export interface MobileApp {
  entry: Entry;
  /** Where a path of this workspace is: `/w/<id><path>`. */
  at: (path: string) => string;
  push: (path: string) => void;
  /** From the list: pushed; from the latest chats (WIDE), in place of the page open. */
  open: (path: string) => void;
  /** The page in view's path (`/w/<id>…`, as the address has it): the latest chats mark its row. */
  current: string;
  pop: () => void;
  /** The top page gives way to another (a new chat becomes the chat it made); `state`, the history's for it. */
  replace: (path: string, state?: unknown) => void;
  home: () => void;
  sheet: (spec: SheetSpec | null) => void;
  menu: (spec: MenuSpec | null) => void;
  toast: (text: string) => void;
  reader: (spec: ReaderSpec | null) => void;
}

const Context = createContext<MobileApp | null>(null);

/** Whether this is drawn in the narrow app (a phone's way of doing things: ../annotate/ImageMarks.tsx). */
export function useNarrow(): boolean {
  return useContext(Context) !== null;
}

export function useApp(): MobileApp {
  const app = useContext(Context);
  if (!app) throw new Error("outside the narrow app");
  return app;
}

/** Wider than a phone: the pages in a column, the latest chats from the bottom left (styles/root.css.ts has the same width). */
export const WIDE = "(min-width: 680px)";

function useWide(): boolean {
  const [wide, setWide] = useState(() => window.matchMedia(WIDE).matches);
  useEffect(() => {
    const query = window.matchMedia(WIDE);
    const update = () => setWide(query.matches);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return wide;
}

/** How a page comes in and goes: side by side, from the left (settings, from the gear at the top left), or rising (a new chat). */
type Way = "side" | "left" | "rise";
function wayOf(path: string): Way {
  if (/\/new$/.test(path)) return "rise";
  if (/\/settings$/.test(path)) return "left";
  return "side";
}

/** `way`: how the page came in, and so how it goes (a new chat become its chat still sinks back down). */
interface Page { key: string; location: Location; way: Way }

/** The workspace's pages, one route each; `routes` draws the one a location is. */
export function MobileShell({ entry, routes, recent }: { entry: Entry; routes: (location: Location) => ReactNode; recent: () => ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const type = useNavigationType();
  const home = `/w/${entry.id}`;
  useInWorkspace(entry.id);
  // The pages as the browser's history has them, from the first one opened here to the one in view.
  const [pages, setPages] = useState<Page[]>(() => [{ key: location.key, location, way: wayOf(location.pathname) }]);
  const [moving, setMoving] = useState<{ from: Page; to: Page; forward: boolean } | null>(null);
  const top = pages.at(-1)!;
  useLayoutEffect(() => {
    if (location.key === top.location.key) return;
    const page = { key: location.key, location, way: wayOf(location.pathname) };
    const at = pages.findIndex((p) => p.location.key === location.key);
    let next: Page[];
    let forward = true;
    if (type === "POP" && at >= 0) {
      next = pages.slice(0, at + 1);
      forward = false;
    } else if (type === "REPLACE" && (location.state as { fresh?: boolean } | null)?.fresh) {
      // Another chat from the latest chats: a page of its own in place of the one that was open.
      next = [...pages.slice(0, -1), page];
    } else if (type === "REPLACE") {
      // The page becoming another in place (a new chat its chat) stays the same page: what is on it that both have (the
      // composer, with what is typed) is kept.
      next = [...pages.slice(0, -1), { key: top.key, location, way: top.way }];
    } else {
      next = [...pages, page];
    }
    setPages(next);
    if (type !== "REPLACE" && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) setMoving({ from: top, to: page, forward });
  }, [location]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!moving) { from.current = 0; return; }
    const timer = setTimeout(() => setMoving(null), 400);
    return () => clearTimeout(timer);
  }, [moving]);

  const [sheet, setSheet] = useState<SheetSpec | null>(null);
  const [menu, setMenu] = useState<MenuSpec | null>(null);
  const [toast, setToast] = useState<{ text: string; n: number } | null>(null);
  const showToast = useCallback((text: string) => setToast({ text: said(text), n: Date.now() }), []);
  const [reader, setReader] = useState<ReaderSpec | null>(null);
  const wide = useWide();
  // The latest chats over the page (WIDE).
  const [drawer, setDrawer] = useState(false);
  useBackClose(drawer, () => setDrawer(false));
  // Folded below WIDE with them open: they go, and back off their entry of the history with them.
  useEffect(() => { if (!wide) setDrawer(false); }, [wide]);
  // A move to another page leaves what lay over this one.
  useEffect(() => { setSheet(null); setMenu(null); setReader(null); setDrawer(false); }, [location.key]);
  const isHome = (p: Page) => p.location.pathname.replace(/\/$/, "") === home;

  // The same object while the page in view is: everything under it reads it (every row of a chat), and a new one each
  // time the shell draws (a finger swiping back draws it each move) would draw them all again. What it does reads the
  // shell as it is now.
  const now = useRef({ navigate, drawer, top, pages });
  now.current = { navigate, drawer, top, pages };
  const current = top.location.pathname;
  const app = useMemo<MobileApp>(() => ({
    entry,
    at: (path) => `${home}${path}`,
    // Each after the back that a sheet or menu closed just before takes (../backClose.ts), or that back would undo it.
    push: (path) => afterBack(() => now.current.navigate(path)),
    open: (path) => {
      const { navigate, drawer, top } = now.current;
      if (!drawer) return afterBack(() => navigate(path));
      setDrawer(false);
      if (path === top.location.pathname) return;
      // In place of the page under them, once their own entry of the history is gone back off (its back is
      // started a task after it closes, ../backClose.ts): or the page would take that entry, and back would come to the old one.
      const go = () => afterBack(() => (isHome(top) ? navigate(path) : navigate(path, { replace: true, state: { fresh: true } })));
      setTimeout(() => setTimeout(go));
    },
    current,
    // Back through the pages opened here; from the first one (opened by a link), to the list.
    pop: () => afterBack(() => (now.current.pages.length > 1 ? backPage(() => now.current.navigate(-1)) : now.current.navigate(home, { replace: true }))),
    // One page becoming another (a new chat its chat): crossfaded, what both have (the composer) moving between them.
    // The wait for a closing sheet's back is inside the crossfade, which starts a frame later: a sheet closed in the same
    // tap (another workspace from the workspace sheet) starts its back in between, and replacing before that back lands
    // would put the new page on the sheet's entry, which the back then leaves for the old page.
    replace: (path, state) => void transitionTo(() => afterBack(() => now.current.navigate(path, { replace: true, state }))),
    home: () => afterBack(() => now.current.navigate(home)),
    sheet: setSheet,
    menu: setMenu,
    toast: showToast,
    reader: setReader,
  }), [entry, home, current, showToast]); // eslint-disable-line react-hooks/exhaustive-deps

  // With a finger, the page is swiped back from the screen's left edge: it follows the finger, the page under it shows,
  // and past a third of the way (or flung) it goes, from where the finger left it.
  const home_ = isHome(top);
  const [swipe, setSwipe] = useState<number | null>(null);
  const swiping = useRef<{ x: number; at: number; dx: number } | null>(null);
  const from = useRef(0);
  const swipeProps = home_ ? {} : {
    onPointerDown: (e: React.PointerEvent<HTMLDivElement>) => {
      if (e.pointerType !== "touch" || sheet || reader) return;
      swiping.current = { x: e.clientX, at: e.timeStamp, dx: 0 };
      e.currentTarget.setPointerCapture(e.pointerId);
    },
    onPointerMove: (e: React.PointerEvent<HTMLDivElement>) => {
      const s = swiping.current;
      if (!s) return;
      s.dx = Math.max(0, e.clientX - s.x);
      setSwipe(s.dx);
    },
    onPointerUp: (e: React.PointerEvent<HTMLDivElement>) => {
      const s = swiping.current;
      swiping.current = null;
      if (!s) return;
      const flung = s.dx > 40 && s.dx / Math.max(1, e.timeStamp - s.at) > 0.6;
      if (s.dx > window.innerWidth / 3 || flung) { from.current = s.dx; setSwipe(null); app.pop(); } else setSwipe(null);
    },
    onPointerCancel: () => { swiping.current = null; setSwipe(null); },
  };

  // The page leaving on the way back is no longer in the list; it is drawn until it has gone.
  const shown = moving && !moving.forward && !pages.some((p) => p.key === moving.from.key) ? [...pages, moving.from] : pages;
  const below = pages.at(-2)?.key;
  return (
    <Context.Provider value={app}>
      {/* What shared parts say (../toast.tsx useToast, useAct) shows as the phone's own toast. */}
      <ToastTo show={showToast}>
        <div className={rootCss.m}>
          {shown.map((p) => {
            const isTop = p.key === top.key;
            const inMove = moving && (p.key === moving.from.key || p.key === moving.to.key);
            const role = !moving ? (isTop ? "top" : swipe !== null && p.key === below ? "peek" : "under") : p.key === moving.to.key ? "in" : p.key === moving.from.key ? "out" : "under";
            const way = moving ? (moving.forward ? moving.to : moving.from).way : "side";
            const style: React.CSSProperties & Record<string, string | number> = { zIndex: moving ? (p.key === (moving.forward ? moving.to.key : moving.from.key) ? 2 : 1) : isTop ? 1 : 0 };
            if (swipe !== null && isTop) style.transform = `translateX(${swipe}px)`;
            if (role === "peek") style.transform = `translateX(calc(-30% + ${swipe! * 0.3}px))`;
            // A page swiped back leaves from where the finger let it go.
            if (role === "out" && moving && !moving.forward) style["--m-from"] = `${from.current}px`;
            return (
              <div key={p.key} className={css.mPage} data-role={role} data-way={inMove ? way : undefined} data-forward={moving?.forward || undefined}
                data-swiping={(swipe !== null && isTop) || undefined} style={style}>
                <PageBody location={p.location} routes={routes} />
              </div>
            );
          })}
          {/* Where a swipe back starts: a strip along the left edge that the browser leaves to it (a finger only). */}
          {!home_ && !moving && <div className={css.mEdge} {...swipeProps} />}
          {/* The latest chats, from the screen's bottom left, level with the composer; over the page, rising from the button. */}
          {wide && !home_ && <>
            <button type="button" className={`${pagesCss.mFloating} ${css.mRecentButton}`} data-open={drawer || undefined}
              onClick={() => setDrawer((open) => !open)} aria-label={t("web-mobile.app.recent")} aria-expanded={drawer}><Chats size={22} /></button>
            <div className={css.mRecentLayer} data-open={drawer || undefined} inert={!drawer}>
              <div className={css.mRecentCatch} onClick={() => setDrawer(false)} />
              <div className={css.mRecent}>{drawer && recent()}</div>
            </div>
          </>}
          <SheetHost spec={sheet} close={() => setSheet(null)} />
          <ReaderHost spec={reader} close={() => setReader(null)} />
          <MenuHost spec={menu} close={() => { menu?.onDismiss?.(); setMenu(null); }} />
          <ToastHost toast={toast} />
        </div>
      </ToastTo>
    </Context.Provider>
  );
}


/** A page's own content: drawn again only when its address or the routes do, not each time the shell is (a swipe's
 *  every move, a toast). */
const PageBody = memo(function PageBody({ location, routes }: { location: Location; routes: (location: Location) => ReactNode }) {
  return routes(location);
});


// ── the sheet ──────────────────────────────────────────────────────────

interface Drag { draggable: boolean; start: (y: number) => void; move: (y: number) => void; end: () => void; tap: () => void }
const SheetDragContext = createContext<Drag | null>(null);

/**
 * One sheet from the bottom at a time: over a dimmed page, dragged by its grabber between half and full height (or
 * down to close) when it may be, frosted glass as the bars are.
 */
function SheetHost({ spec, close }: { spec: SheetSpec | null; close: () => void }) {
  const [shown, setShown] = useState<SheetSpec | null>(null);
  const [open, setOpen] = useState(false);
  const [dragging, setDragging] = useState(false);
  const sheet = useRef<HTMLDivElement>(null);
  // Its height: following the finger at once while dragged, then on to where it settles at the speed it was let go of.
  const height = useRef<Follower | null>(null);
  height.current ??= follower(0, (v) => { if (sheet.current) sheet.current.style.height = `${v}px`; });
  useEffect(() => () => height.current?.stop(), []);
  const total = () => window.innerHeight;
  useBackClose(!!spec, close);
  useEffect(() => {
    if (spec) {
      // A sheet comes up in the keyboard's place: what was being typed into lets go of it first.
      (document.activeElement as HTMLElement | null)?.blur?.();
      height.current!.jump(spec.height * total());
      setShown(spec);
      requestAnimationFrame(() => requestAnimationFrame(() => setOpen(true)));
      return;
    }
    setOpen(false);
    const timer = setTimeout(() => setShown(null), 300);
    return () => clearTimeout(timer);
  }, [spec]);
  // Drawn as it is when it (re)appears.
  useLayoutEffect(() => { if (shown && sheet.current) sheet.current.style.height = `${height.current!.value}px`; }, [shown]);
  useEffect(() => {
    if (!spec) return;
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") close(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [spec, close]);
  const from = useRef({ y: 0, h: 0, moved: false });
  /** The finger's last moves, for how fast it was going when let go (height per second: up is positive). */
  const trail = useRef<{ y: number; t: number }[]>([]);
  if (!shown) return null;
  const h = () => height.current!.value;
  const follow = (y: number, most: number) => {
    from.current.moved = true;
    const now = performance.now();
    trail.current = [...trail.current.filter((p) => now - p.t < 100), { y, t: now }];
    height.current!.jump(Math.max(120, Math.min(most, from.current.h + from.current.y - y)));
  };
  const speed = () => {
    const [first, last] = [trail.current[0], trail.current.at(-1)];
    return first && last && last.t > first.t ? ((first.y - last.y) / (last.t - first.t)) * 1000 : 0;
  };
  const settle = (to: number) => height.current!.to(to, { type: "spring", visualDuration: 0.32, bounce: 0, velocity: speed() });
  const grab = (y: number) => { from.current = { y, h: h(), moved: false }; trail.current = [{ y, t: performance.now() }]; setDragging(true); };
  const drag: Drag = {
    draggable: !!shown.draggable,
    start: grab,
    move: (y) => follow(y, total() * 0.94),
    end: () => {
      setDragging(false);
      if (!from.current.moved) return;
      const f = h() / total();
      if (f < 0.3) close();
      else settle(total() * (f > 0.72 ? 0.94 : 0.55));
    },
    tap: () => { trail.current = []; settle(total() * (h() > total() * 0.9 ? 0.55 : 0.94)); },
  };
  // With a finger the sheet's top (its grabber and head) drags it: a draggable sheet between half and full height or
  // down to close; any other down to close, or back to its height.
  const base = shown.height * total();
  const headDrag = {
    onPointerDown: (e: React.PointerEvent<HTMLDivElement>) => {
      if (e.pointerType !== "touch" || e.clientY - e.currentTarget.getBoundingClientRect().top > 64 || (e.target as HTMLElement).closest("button, input, textarea, a")) return;
      e.currentTarget.setPointerCapture(e.pointerId);
      grab(e.clientY);
    },
    onPointerMove: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!dragging || !e.currentTarget.hasPointerCapture(e.pointerId)) return;
      follow(e.clientY, shown.draggable ? total() * 0.94 : base);
    },
    onPointerUp: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
      setDragging(false);
      if (!from.current.moved) return;
      if (shown.draggable) return drag.end();
      if (base - h() > 80) close();
      else settle(base);
    },
  };
  return (
    <div className={css.mOverlay} data-open={open || undefined}>
      <div className={css.mScrim} onClick={close} />
      <div ref={sheet} className={css.mSheet} data-open={open || undefined} data-dragging={dragging || undefined} {...headDrag}>
        <SheetDragContext.Provider value={drag}>{shown.content()}</SheetDragContext.Provider>
      </div>
    </div>
  );
}

/** The sheet's grabber: drags a draggable sheet, and a tap switches it between half and full. */
export function SheetGrab() {
  const drag = useContext(SheetDragContext);
  const down = useRef<number | null>(null);
  return (
    <div className={css.mGrab} data-draggable={drag?.draggable || undefined}
      onPointerDown={(e) => {
        if (!drag?.draggable) return;
        down.current = e.clientY;
        e.currentTarget.setPointerCapture(e.pointerId);
        drag.start(e.clientY);
      }}
      onPointerMove={(e) => { if (down.current !== null && Math.abs(e.clientY - down.current) > 3) drag?.move(e.clientY); }}
      onPointerUp={(e) => {
        const moved = down.current !== null && Math.abs(e.clientY - down.current) > 3;
        down.current = null;
        drag?.end();
        if (!moved && drag?.draggable) drag.tap();
      }}
      onPointerCancel={() => { down.current = null; drag?.end(); }}>
      <span />
    </div>
  );
}

export function SheetHead({ title, trailing }: { title: string; trailing?: ReactNode }) {
  return <div className={css.mSheetHead}><b>{title}</b>{trailing}</div>;
}

// ── the long-press menu, a short note, the reader ─────────────────────

function MenuHost({ spec, close }: { spec: MenuSpec | null; close: () => void }) {
  const [shown, setShown] = useState<MenuSpec | null>(null);
  const [open, setOpen] = useState(false);
  // Only a press that starts on the scrim closes it: the click a browser sends as the long-pressing finger lifts lands
  // on the scrim that has just appeared under it.
  const pressed = useRef(false);
  useBackClose(!!spec, close);
  useEffect(() => {
    if (spec) { setShown(spec); requestAnimationFrame(() => requestAnimationFrame(() => setOpen(true))); return; }
    setOpen(false);
    const timer = setTimeout(() => setShown(null), 200);
    return () => clearTimeout(timer);
  }, [spec]);
  if (!shown) return null;
  const width = 180;
  const x = Math.max(12, Math.min(shown.anchor.left, window.innerWidth - width - 12));
  // Under the message, or over it when there is no room below.
  const height = 45 * shown.items.length;
  const below = shown.anchor.bottom + 6;
  const y = below + height < window.innerHeight - 24 ? below : Math.max(24, shown.anchor.top - height - 6);
  return (
    <div className={`${css.mOverlay} ${css.mMenuLayer}`} data-open={open || undefined}>
      <div className={css.mScrim} onPointerDown={() => { pressed.current = true; }} onClick={() => { if (pressed.current) close(); pressed.current = false; }} />
      <div className={css.mMenu} data-open={open || undefined} style={{ left: x, top: y, width }}>
        {shown.items.map((item) => (
          <button key={item.label} type="button" onClick={() => { close(); item.action(); }}>{item.label}{item.icon}</button>
        ))}
      </div>
    </div>
  );
}

function ToastHost({ toast }: { toast: { text: string; n: number } | null }) {
  const [shown, setShown] = useState<{ text: string; n: number } | null>(null);
  useEffect(() => {
    if (!toast) return;
    setShown(toast);
    const timer = setTimeout(() => setShown((t) => (t?.n === toast.n ? null : t)), 2600);
    return () => clearTimeout(timer);
  }, [toast]);
  return <div className={css.mToast} data-open={shown ? true : undefined} role="status">{shown?.text}</div>;
}

/** The reader comes in from the side over everything; ‹ returns to where it was opened. */
function ReaderHost({ spec, close }: { spec: ReaderSpec | null; close: () => void }) {
  const [shown, setShown] = useState<ReaderSpec | null>(null);
  const [open, setOpen] = useState(false);
  useBackClose(!!spec, close);
  useEffect(() => {
    if (spec) { setShown(spec); requestAnimationFrame(() => requestAnimationFrame(() => setOpen(true))); return; }
    setOpen(false);
    const timer = setTimeout(() => setShown(null), 320);
    return () => clearTimeout(timer);
  }, [spec]);
  if (!shown) return null;
  return (
    <div className={css.mReader} data-open={open || undefined}>
      <div className={css.mReaderBar}><NavBack label={t("web-mobile.app.runHistory")} onClick={close} /></div>
      <div className={css.mReaderBody}>
        <div className={css.mReaderLabel}>{shown.label}</div>
        {shown.content}
      </div>
    </div>
  );
}

