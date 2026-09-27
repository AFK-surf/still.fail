// The app on a narrow screen, as the Android app is (apps/android/…/App.kt): the chats of one workspace are home, and
// everything else is a page pushed over it (no tab bar), or a sheet from the bottom. Pages move side by side: the new
// one pushes in whole from the right and the old goes out to the left (and back the other way); the viewer's own page
// comes from the left instead, a new chat rises from the bottom. Each page is an address, so the browser's back and a
// link work as the desktop's do; pages under the top one stay as they were left (their scroll, what was typed).
import { createContext, useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useLocation, useNavigate, useNavigationType, type Location } from "react-router";
import type { Account } from "../cloud/accounts.ts";
import { NavBack } from "./parts.tsx";
import "./mobile.css";

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
  pop: () => void;
  /** The top page gives way to another (a new chat becomes the chat it made). */
  replace: (path: string) => void;
  home: () => void;
  sheet: (spec: SheetSpec | null) => void;
  menu: (spec: MenuSpec | null) => void;
  toast: (text: string) => void;
  reader: (spec: ReaderSpec | null) => void;
}

const Context = createContext<MobileApp | null>(null);

export function useApp(): MobileApp {
  const app = useContext(Context);
  if (!app) throw new Error("outside the narrow app");
  return app;
}

/** How a page comes in and goes: side by side, from the left (the viewer's own page), or rising (a new chat). */
type Way = "side" | "left" | "rise";
function wayOf(path: string): Way {
  if (/\/new$/.test(path)) return "rise";
  if (/\/settings\/account$/.test(path)) return "left";
  return "side";
}

interface Page { key: string; location: Location }

/** The workspace's pages, one route each; `routes` draws the one a location is. */
export function MobileShell({ entry, routes }: { entry: Entry; routes: (location: Location) => ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const type = useNavigationType();
  const home = `/w/${entry.id}`;
  // The pages as the browser's history has them, from the first one opened here to the one in view.
  const [pages, setPages] = useState<Page[]>(() => [{ key: location.key, location }]);
  const [moving, setMoving] = useState<{ from: Page; to: Page; forward: boolean } | null>(null);
  const top = pages.at(-1)!;
  useLayoutEffect(() => {
    if (location.key === top.key) return;
    const page = { key: location.key, location };
    const at = pages.findIndex((p) => p.key === location.key);
    let next: Page[];
    let forward = true;
    if (type === "POP" && at >= 0) {
      next = pages.slice(0, at + 1);
      forward = false;
    } else if (type === "REPLACE") {
      next = [...pages.slice(0, -1), page];
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
  const [reader, setReader] = useState<ReaderSpec | null>(null);
  // A move to another page leaves what lay over this one.
  useEffect(() => { setSheet(null); setMenu(null); setReader(null); }, [location.key]);

  const app: MobileApp = {
    entry,
    at: (path) => `${home}${path}`,
    push: (path) => navigate(path),
    // Back through the pages opened here; from the first one (opened by a link), to the list.
    pop: () => (pages.length > 1 ? navigate(-1) : navigate(home, { replace: true })),
    // One page becoming another (a new chat its chat): crossfaded, what both have (the composer) moving between them.
    replace: (path) => navigate(path, { replace: true, viewTransition: true }),
    home: () => navigate(home),
    sheet: setSheet,
    menu: setMenu,
    toast: (text) => setToast({ text, n: Date.now() }),
    reader: setReader,
  };

  // With a finger, the page is swiped back from the screen's left edge: it follows the finger, the page under it shows,
  // and past a third of the way (or flung) it goes, from where the finger left it.
  const home_ = top.location.pathname.replace(/\/$/, "") === home;
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
      <div className="m">
        {shown.map((p) => {
          const isTop = p.key === top.key;
          const inMove = moving && (p.key === moving.from.key || p.key === moving.to.key);
          const role = !moving ? (isTop ? "top" : swipe !== null && p.key === below ? "peek" : "under") : p.key === moving.to.key ? "in" : p.key === moving.from.key ? "out" : "under";
          const way = moving ? wayOf((moving.forward ? moving.to : moving.from).location.pathname) : "side";
          const style: React.CSSProperties & Record<string, string | number> = { zIndex: moving ? (p.key === (moving.forward ? moving.to.key : moving.from.key) ? 2 : 1) : isTop ? 1 : 0 };
          if (swipe !== null && isTop) style.transform = `translateX(${swipe}px)`;
          if (role === "peek") style.transform = `translateX(calc(-30% + ${swipe! * 0.3}px))`;
          // A page swiped back leaves from where the finger let it go.
          if (role === "out" && moving && !moving.forward) style["--m-from"] = `${from.current}px`;
          return (
            <div key={p.key} className="m-page" data-role={role} data-way={inMove ? way : undefined} data-forward={moving?.forward || undefined}
              data-swiping={(swipe !== null && isTop) || undefined} style={style}>
              {routes(p.location)}
            </div>
          );
        })}
        {/* Where a swipe back starts: a strip along the left edge that the browser leaves to it (a finger only). */}
        {!home_ && !moving && <div className="m-edge" {...swipeProps} />}
        <SheetHost spec={sheet} close={() => setSheet(null)} />
        <ReaderHost spec={reader} close={() => setReader(null)} />
        <MenuHost spec={menu} close={() => { menu?.onDismiss?.(); setMenu(null); }} />
        <ToastHost toast={toast} />
      </div>
    </Context.Provider>
  );
}


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
  const [height, setHeight] = useState(0);
  const [dragging, setDragging] = useState(false);
  const total = () => window.innerHeight;
  useEffect(() => {
    if (spec) {
      // A sheet comes up in the keyboard's place: what was being typed into lets go of it first.
      (document.activeElement as HTMLElement | null)?.blur?.();
      setHeight(spec.height * total());
      setShown(spec);
      requestAnimationFrame(() => requestAnimationFrame(() => setOpen(true)));
      return;
    }
    setOpen(false);
    const timer = setTimeout(() => setShown(null), 300);
    return () => clearTimeout(timer);
  }, [spec]);
  useEffect(() => {
    if (!spec) return;
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") close(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [spec, close]);
  const from = useRef({ y: 0, h: 0, moved: false });
  if (!shown) return null;
  const drag: Drag = {
    draggable: !!shown.draggable,
    start: (y) => { from.current = { y, h: height, moved: false }; setDragging(true); },
    move: (y) => {
      from.current.moved = true;
      setHeight(Math.max(120, Math.min(total() * 0.94, from.current.h + from.current.y - y)));
    },
    end: () => {
      setDragging(false);
      if (!from.current.moved) return;
      const f = height / total();
      if (f < 0.3) close();
      else setHeight(total() * (f > 0.72 ? 0.94 : 0.55));
    },
    tap: () => setHeight(total() * (height > total() * 0.9 ? 0.55 : 0.94)),
  };
  // With a finger the sheet's top (its grabber and head) drags it: a draggable sheet between half and full height or
  // down to close; any other down to close, or back to its height.
  const base = shown.height * total();
  const headDrag = {
    onPointerDown: (e: React.PointerEvent<HTMLDivElement>) => {
      if (e.pointerType !== "touch" || e.clientY - e.currentTarget.getBoundingClientRect().top > 64 || (e.target as HTMLElement).closest("button, input, textarea, a")) return;
      e.currentTarget.setPointerCapture(e.pointerId);
      from.current = { y: e.clientY, h: height, moved: false };
      setDragging(true);
    },
    onPointerMove: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!dragging || !e.currentTarget.hasPointerCapture(e.pointerId)) return;
      from.current.moved = true;
      const next = from.current.h + from.current.y - e.clientY;
      setHeight(Math.max(120, Math.min(shown.draggable ? total() * 0.94 : base, next)));
    },
    onPointerUp: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
      setDragging(false);
      if (!from.current.moved) return;
      if (shown.draggable) return drag.end();
      if (base - height > 80) close();
      else setHeight(base);
    },
  };
  return (
    <div className="m-overlay" data-open={open || undefined}>
      <div className="m-scrim" onClick={close} />
      <div className="m-sheet" data-open={open || undefined} data-dragging={dragging || undefined} style={{ height }} {...headDrag}>
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
    <div className="m-grab" data-draggable={drag?.draggable || undefined}
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
  return <div className="m-sheet-head"><b>{title}</b>{trailing}</div>;
}

// ── the long-press menu, a short note, the reader ─────────────────────

function MenuHost({ spec, close }: { spec: MenuSpec | null; close: () => void }) {
  const [shown, setShown] = useState<MenuSpec | null>(null);
  const [open, setOpen] = useState(false);
  // Only a press that starts on the scrim closes it: the click a browser sends as the long-pressing finger lifts lands
  // on the scrim that has just appeared under it.
  const pressed = useRef(false);
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
    <div className="m-overlay m-menu-layer" data-open={open || undefined}>
      <div className="m-scrim" onPointerDown={() => { pressed.current = true; }} onClick={() => { if (pressed.current) close(); pressed.current = false; }} />
      <div className="m-menu" data-open={open || undefined} style={{ left: x, top: y, width }}>
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
  return <div className="m-toast" data-open={shown ? true : undefined} role="status">{shown?.text}</div>;
}

/** The reader comes in from the side over everything; ‹ returns to where it was opened. */
function ReaderHost({ spec, close }: { spec: ReaderSpec | null; close: () => void }) {
  const [shown, setShown] = useState<ReaderSpec | null>(null);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (spec) { setShown(spec); requestAnimationFrame(() => requestAnimationFrame(() => setOpen(true))); return; }
    setOpen(false);
    const timer = setTimeout(() => setShown(null), 320);
    return () => clearTimeout(timer);
  }, [spec]);
  if (!shown) return null;
  return (
    <div className="m-reader" data-open={open || undefined}>
      <div className="m-reader-bar"><NavBack label="执行历史" onClick={close} /></div>
      <div className="m-reader-body">
        <div className="m-reader-label">{shown.label}</div>
        {shown.content}
      </div>
    </div>
  );
}

