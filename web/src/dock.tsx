// The composer of the chat pages (a new chat, a chat) is one, made once and kept: pages hold a place for it (a
// `ComposerSlot`, with what it writes to) and it sits over that place, so going from a page to another (a new chat
// becoming its chat, one chat to the next) moves it without making it again. What is typed, the focus, a composition
// under way all stay. What is typed is kept by chat (its `draftKey`): each chat has its own, and a new chat's goes on
// into the chat it makes.
import { createContext, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent, type ReactNode } from "react";
import { flushSync } from "react-dom";
import { useNavigate } from "react-router";
import { Composer, type ComposerProps } from "./Chat.tsx";
import { StationContext, type Station } from "./station.tsx";
import { pageChanging, transitionTo } from "./ui.tsx";
import * as composerCss from "./styles/composer.css.ts";
import * as css from "./dock.css.ts";
import { easeOut, morph, shapeOf, stop, type Shape } from "./morph.ts";

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

/** Frames its place stays put before it stops following it. */
const STILL_FRAMES = 30;

export function ComposerDock({ children }: { children: ReactNode }) {
  const [spec, setSpec] = useState<ComposerSpec | null>(null);
  const [height, setHeight] = useState(0);
  const heightNow = useRef(0);
  heightNow.current = height;
  const slot = useRef<HTMLElement | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const carry = useRef<string | null>(null);
  const held = useRef<{ shape: Shape; release(): void } | null>(null);
  const put = () => {
    if (held.current && variant.current === "new") return false;
    const el = box.current;
    const at = slot.current;
    if (!el || !at || !at.isConnected) return false;
    const host = el.offsetParent as HTMLElement | null;
    const base = host?.getBoundingClientRect() ?? { left: 0, top: 0, bottom: window.innerHeight };
    const r = at.getBoundingClientRect();
    // At a chat's foot it hangs from its place's bottom: growing (a line more, capsule to box) it grows upwards at once,
    // not down past the window until its place has followed.
    const foot = variant.current === "chat";
    const left = `${Math.round(r.left - base.left)}px`, width = `${Math.round(r.width)}px`;
    const top = foot ? "" : `${Math.round(r.top - base.top)}px`, bottom = foot ? `${Math.round(base.bottom - r.bottom)}px` : "";
    if (el.style.left === left && el.style.top === top && el.style.bottom === bottom && el.style.width === width) return false;
    el.style.left = left;
    el.style.top = top;
    el.style.bottom = bottom;
    el.style.width = width;
    return true;
  };
  // Without a place (not a chat page), it is put away by the next frame; while a new chat hands its draft on to the chat
  // it makes (the chat page may take a moment to hold a place), it stays where it was, focus and all.
  const [shown, setShown] = useState(true);
  const away = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [dock] = useState<Dock>(() => ({
    place(at, next) {
      // Laid out for another page: where it is now is where it goes from, read once (a page may hand over its place
      // again before the dock has drawn the change, and by then it has moved there).
      if (next.variant !== variant.current && next.variant !== seenFor.current) { seen(); seenFor.current = next.variant; }
      clearTimeout(away.current);
      if (slot.current !== at) { slot.current = at; wake.current(); }
      // The same as before (a page drawn again as the composer's height changes, every frame it grows): kept, so the
      // composer is not drawn again for nothing.
      setSpec((now) => (now && Object.keys({ ...now, ...next }).every((k) => now[k as keyof ComposerSpec] === next[k as keyof ComposerSpec]) ? now : next));
      setShown(true);
    },
    leave(at) {
      if (slot.current !== at) return;
      slot.current = null;
      clearTimeout(away.current);
      away.current = setTimeout(() => { if (!slot.current) setShown(false); }, carry.current ? 1000 : 16);
    },
    height: 0,
    carryTo(key) { carry.current = key; },
  }));
  // Where its place is, now and as the page lays out anew (it moves with it, at once). It is followed frame by frame
  // only while something may be moving it (the window or its place resized, a transition or animation starting, a new
  // place), until it has stayed still a moment: a loop every frame kept the page from ever being idle, and cost
  // scrolling frames.
  const wake = useRef(() => {});
  useLayoutEffect(() => { put(); });
  useLayoutEffect(() => {
    let frame = 0;
    let still = 0;
    const follow = () => {
      still = put() ? 0 : still + 1;
      frame = still < STILL_FRAMES ? requestAnimationFrame(follow) : 0;
    };
    const start = () => {
      still = 0;
      if (!frame) frame = requestAnimationFrame(follow);
    };
    const resize = new ResizeObserver(start);
    wake.current = () => {
      resize.disconnect();
      const at = slot.current;
      for (const el of [at, at?.parentElement, box.current?.offsetParent, document.documentElement]) if (el) resize.observe(el);
      start();
    };
    wake.current();
    window.addEventListener("resize", start);
    document.addEventListener("transitionrun", start, true);
    document.addEventListener("animationstart", start, true);
    return () => {
      cancelAnimationFrame(frame);
      resize.disconnect();
      wake.current = () => {};
      window.removeEventListener("resize", start);
      document.removeEventListener("transitionrun", start, true);
      document.removeEventListener("animationstart", start, true);
    };
  }, []);
  // Laid out for another page (a new chat becoming its chat, a chat left for a new one), the box goes from where and how
  // big it was to where and how big it is now: one composer changing, not one fading out as another fades in. Where it
  // was is read as the new page takes it (`place`); a page change's picture leaves it out (its styles), so what shows of
  // it is the live box.
  const inner = () => box.current?.querySelector<HTMLElement>(`.${composerCss.composerBox}`) ?? null;
  const was = useRef<Shape | null>(null);
  const seenFor = useRef<string | undefined>(undefined);
  const seen = () => {
    const b = inner();
    // Not while it is put away (no page held a place): it would start from nowhere, off the page's corner.
    if (b && b.getClientRects().length && b.getBoundingClientRect().width > 0) was.current = held.current?.shape ?? shapeOf(b);
  };
  const variant = useRef(spec?.variant);
  // Laid out for another page, its new height is taken at once, not when the observer tells of it: a new chat becoming
  // its chat takes its picture of the page in the same moment, and the place would still be the new chat's height (the
  // box moved down to where it would stop, then jumped). Taken before the box starts from its old size, and kept while
  // it moves: its place followed the sizes it goes through, and moved it (it stood 28px up at the start).
  const moving = useRef(false);
  useLayoutEffect(() => {
    if (box.current) setHeight(box.current.offsetHeight);
  }, [spec?.variant]);
  useLayoutEffect(() => {
    const before = variant.current;
    variant.current = spec?.variant;
    const from = was.current;
    seenFor.current = undefined;
    const b = inner();
    const wrap = b?.parentElement;
    if (!before || !spec || before === spec.variant || !from || !b || !wrap) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    // From where it was to where its place is now (read without the move under way), its shape and what it holds with
    // it (morph.ts).
    const animate = () => {
      held.current?.release();
      stop(b);
      // Its place keeps the height it has now (read with the next page's draft in it), and it goes to where that
      // place is laid out then: kept at the height it had before, a centred place moved it once it was over.
      if (box.current && box.current.offsetHeight !== heightNow.current) flushSync(() => setHeight(box.current!.offsetHeight));
      put();
      const to = b.getBoundingClientRect();
      // Laid out from the wrap's left edge while it moves (its auto margins would move it as its width changes).
      const left = wrap.getBoundingClientRect().left + parseFloat(getComputedStyle(wrap).paddingLeft);
      // Hung from its place's foot (a chat's), its top follows its height as it goes: it is placed by its foot then.
      const foot = !!box.current?.style.bottom;
      const y = foot ? from.rect.bottom - to.bottom : from.rect.top - to.top;
      const all = morph(b, "page", from, [
        // A new chat's box holds a least height (dock.css.ts): not while it grows to it from a capsule.
        { marginLeft: "0px", transform: `translate(${from.rect.left - left}px, ${y}px)`, width: `${from.rect.width}px`, height: `${from.rect.height}px`, minHeight: "0px" },
        { marginLeft: "0px", transform: `translate(${to.left - left}px, 0px)`, width: `${to.width}px`, height: `${to.height}px`, minHeight: "0px" },
      ], { duration: 340, easing: easeOut() });
      moving.current = true;
      void all[0]!.finished.then(() => {
        moving.current = false;
        if (box.current) setHeight(box.current.offsetHeight);
      }, () => {});
      return all;
    };
    // Read once what the page's change changes in it has been drawn too (its text: the next page's draft comes in an
    // update of its own, right after this), before anything is shown: its new shape is what it will have.
    queueMicrotask(() => {
      if (variant.current !== spec.variant || !b.isConnected) return;
      let move = animate();
      // In a page change it waits where it starts until the change moves, and starts from where its place is by then:
      // the next page may be waited for, and put its place elsewhere (a chat's, read, is not where it was while read).
      const changing = pageChanging();
      if (changing) {
        for (const a of move) a.pause();
        changing.settle.push(() => {
          if (variant.current !== spec.variant || !b.isConnected) return;
          move = animate();
          for (const a of move) a.pause();
        });
        void changing.moving.then(() => {
          // Its place may have moved again as the next page settled (its list, its height): read it now, as the change
          // starts to show it, and go from where it was to there.
          if (variant.current !== spec.variant || !b.isConnected) return;
          move = animate();
          // A page change draws it over the pages (a picture of its own, dock.css.ts): what lies over it on the next
          // page (a chat's panel over a narrow chat, `data-over-composer`) would be under it. It is cut where they are
          // until the change is over.
          const dock = box.current;
          if (!dock) return;
          const at = dock.getBoundingClientRect();
          const over = [...document.querySelectorAll("[data-over-composer]")]
            .filter((e) => getComputedStyle(e).position === "fixed")
            .map((e) => e.getBoundingClientRect())
            .filter((r) => r.width > 0 && r.left > at.left);
          if (!over.length) return;
          const x = Math.min(...over.map((r) => r.left)) - at.left;
          dock.style.clipPath = `polygon(-100vw -100vh, ${x}px -100vh, ${x}px 200vh, -100vw 200vh)`;
          void changing.done.then(() => { dock.style.clipPath = ""; });
        });
      }
    });
  }, [spec?.variant]); // eslint-disable-line react-hooks/exhaustive-deps
  // Its height, for its place to keep: watched once it is there (the first page to hold a place makes it).
  const made = spec !== null;
  useLayoutEffect(() => {
    const dock = box.current;
    if (!dock) return;
    const hold = (event: Event) => {
      const b = inner();
      if (!b || variant.current !== "new" || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      held.current?.release();
      const shape = shapeOf(b);
      const before = { height: b.style.height, width: b.style.width, borderRadius: b.style.borderRadius };
      stop(b);
      Object.assign(b.style, { height: `${shape.rect.height}px`, width: `${shape.rect.width}px`, borderRadius: `${shape.radius}px` });
      b.dataset.sendHeld = "";
      const hold = { shape, release: () => {
        if (held.current !== hold) return;
        Object.assign(b.style, before);
        delete b.dataset.sendHeld;
        held.current = null;
      } };
      held.current = hold;
      (event as CustomEvent<{ release?: () => void }>).detail.release = hold.release;
    };
    dock.addEventListener("hold-first-composer", hold);
    return () => { dock.removeEventListener("hold-first-composer", hold); held.current?.release(); };
  }, [made]);
  useLayoutEffect(() => {
    const el = box.current;
    if (!made || !el) return;
    setHeight(el.offsetHeight);
    // Taken in the frame it changes (the composer growing a line, or moving from capsule to box): its place, and the
    // list's foot with it, keep up with it frame by frame rather than a frame or two behind.
    const resize = new ResizeObserver(() => { if (!moving.current) flushSync(() => setHeight(el.offsetHeight)); });
    resize.observe(el);
    return () => resize.disconnect();
  }, [made]);
  // The frame its layout changes with the page (a chat's foot, a new chat's roomy box) it changes at once: eased, its
  // corners showed as a jump (its styles ease them as it grows while typed in).
  const [settled, setSettled] = useState(spec?.variant);
  const switching = spec !== null && spec.variant !== settled;
  useEffect(() => {
    if (!switching) return;
    const frame = requestAnimationFrame(() => setSettled(spec.variant));
    return () => cancelAnimationFrame(frame);
  }, [switching, spec?.variant]);
  // Changes only with the height: the places re-render then, not each time a page hands over what it writes to.
  const value = useMemo(() => ({ ...dock, height }), [dock, height]);
  // Drawn anew with what the page hands it, not with the dock's own height (which changes every frame it grows).
  const composer = useMemo(() => spec && <Composer {...spec} carry={carry} />, [spec]);
  return (
    <DockContext.Provider value={value}>
      {children}
      {spec && (
        <div ref={box} className={css.composerDock} data-made-composer data-variant={spec.variant} data-switching={switching || undefined} hidden={!shown}>
          <StationContext.Provider value={spec.station}>
            {composer}
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
  return <div ref={ref} className={css.composerSlot} data-variant={spec.variant} style={{ height: dock?.height || undefined }} />;
}

/** The composer's height: what a page running under it leaves free at its foot. */
export function useComposerHeight(): number {
  return useContext(DockContext)?.height ?? 0;
}

/** The next page's draft goes on from what is typed now. */
export function useCarryDraft(): (key: string) => void {
  const dock = useContext(DockContext);
  return (key) => dock?.carryTo(key);
}

/**
 * A link's click between a new chat and a chat (the sidebar's): the composer moves between their places as when a new
 * chat's first message is sent, and the rest crossfades. A chat's page is waited for until its composer is in its place
 * (what the motion lands on), not for its messages: they come from the station, at no time known, and the page is frozen
 * while a view transition waits; they show when they are there. Plain clicks between chats, or with a key held, are
 * left to the link.
 */
export function useComposerMove(): (event: MouseEvent<HTMLAnchorElement>, to: string, next: "new" | "chat") => void {
  const navigate = useNavigate();
  return (event, to, next) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const dock = document.querySelector<HTMLElement>(`.${css.composerDock}:not([hidden])`);
    if (!dock || dock.dataset.variant === next) return;
    event.preventDefault();
    void transitionTo(() => navigate(to), next === "chat" ? () => document.querySelector(`.${css.composerDock}[data-variant="chat"]:not([hidden])`) !== null : undefined, 400);
  };
}
