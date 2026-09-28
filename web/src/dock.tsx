// The composer of the chat pages (a new chat, a chat) is one, made once and kept: pages hold a place for it (a
// `ComposerSlot`, with what it writes to) and it sits over that place, so going from a page to another (a new chat
// becoming its chat, one chat to the next) moves it without making it again. What is typed, the focus, a composition
// under way all stay. What is typed is kept by chat (its `draftKey`): each chat has its own, and a new chat's goes on
// into the chat it makes.
import { createContext, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Composer, type ComposerProps } from "./Chat.tsx";
import { StationContext, type Station } from "./station.tsx";

export interface ComposerSpec extends ComposerProps {
  /** The station it sends to (uploads, warming, sending are its). */
  station: Station;
  /** Whose draft it shows. */
  draftKey: string;
  /** Laid out for a new chat (in the page, roomy) or a chat (at its foot). */
  variant: "new" | "chat";
}

interface Dock {
  place(slot: HTMLElement, spec: ComposerSpec): void;
  leave(slot: HTMLElement): void;
  /** The composer's height, which its place keeps. */
  height: number;
  /** The next page's draft goes on from what is typed now (a new chat becoming its chat). */
  carryTo(key: string): void;
}

const DockContext = createContext<Dock | null>(null);

export function ComposerDock({ children }: { children: ReactNode }) {
  const [spec, setSpec] = useState<ComposerSpec | null>(null);
  const [height, setHeight] = useState(0);
  const slot = useRef<HTMLElement | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const carry = useRef<string | null>(null);
  const put = () => {
    const el = box.current;
    const at = slot.current;
    if (!el || !at || !at.isConnected) return;
    const host = el.offsetParent as HTMLElement | null;
    const base = host?.getBoundingClientRect() ?? { left: 0, top: 0 };
    const r = at.getBoundingClientRect();
    const left = `${Math.round(r.left - base.left)}px`, top = `${Math.round(r.top - base.top)}px`, width = `${Math.round(r.width)}px`;
    if (el.style.left !== left) el.style.left = left;
    if (el.style.top !== top) el.style.top = top;
    if (el.style.width !== width) el.style.width = width;
  };
  // Without a place (not a chat page), it is put away by the next frame; while a new chat hands its draft on to the chat
  // it makes (the chat page may take a moment to hold a place), it stays where it was, focus and all.
  const [shown, setShown] = useState(true);
  const away = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [dock] = useState<Dock>(() => ({
    place(at, next) { clearTimeout(away.current); slot.current = at; setSpec(next); setShown(true); },
    leave(at) {
      if (slot.current !== at) return;
      slot.current = null;
      clearTimeout(away.current);
      away.current = setTimeout(() => { if (!slot.current) setShown(false); }, carry.current ? 1000 : 16);
    },
    height: 0,
    carryTo(key) { carry.current = key; },
  }));
  // Where its place is, now and as the page lays out anew (it moves with it, at once).
  useLayoutEffect(put);
  useLayoutEffect(() => {
    let frame = requestAnimationFrame(function follow() { put(); frame = requestAnimationFrame(follow); });
    return () => cancelAnimationFrame(frame);
  }, []);
  // Its height, for its place to keep: watched once it is there (the first page to hold a place makes it).
  const made = spec !== null;
  useLayoutEffect(() => {
    const el = box.current;
    if (!made || !el) return;
    setHeight(el.offsetHeight);
    const resize = new ResizeObserver(() => setHeight(el.offsetHeight));
    resize.observe(el);
    return () => resize.disconnect();
  }, [made]);
  // Laid out for another page, its new height is taken at once, not when the observer tells of it: a new chat becoming
  // its chat takes its picture of the page in the same moment, and the place would still be the new chat's height (the
  // box moved down to where it would stop, then jumped).
  useLayoutEffect(() => {
    if (box.current) setHeight(box.current.offsetHeight);
  }, [spec?.variant]);
  // The frame its layout changes with the page (a chat's foot, a new chat's roomy box) it changes at once: eased, its
  // corners showed as a jump (app.css eases them as it grows while typed in).
  const [settled, setSettled] = useState(spec?.variant);
  const switching = spec !== null && spec.variant !== settled;
  useEffect(() => {
    if (!switching) return;
    const frame = requestAnimationFrame(() => setSettled(spec.variant));
    return () => cancelAnimationFrame(frame);
  }, [switching, spec?.variant]);
  // Changes only with the height: the places re-render then, not each time a page hands over what it writes to.
  const value = useMemo(() => ({ ...dock, height }), [dock, height]);
  return (
    <DockContext.Provider value={value}>
      {children}
      {spec && (
        <div ref={box} className="composer-dock" data-variant={spec.variant} data-switching={switching || undefined} hidden={!shown}>
          <StationContext.Provider value={spec.station}>
            <Composer {...spec} carry={carry} />
          </StationContext.Provider>
        </div>
      )}
    </DockContext.Provider>
  );
}

/** The composer's place on a page, and what it writes to there. */
export function ComposerSlot(spec: ComposerSpec) {
  const dock = useContext(DockContext);
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => { if (ref.current) dock?.place(ref.current, spec); });
  useLayoutEffect(() => { const at = ref.current; return () => { if (at) dock?.leave(at); }; }, [dock]);
  return <div ref={ref} className="composer-slot" data-variant={spec.variant} style={{ height: dock?.height || undefined }} />;
}

/** The next page's draft goes on from what is typed now. */
export function useCarryDraft(): (key: string) => void {
  const dock = useContext(DockContext);
  return (key) => dock?.carryTo(key);
}
