// How a message pane scrolls while its content changes, with the reader not
// touching it:
// - at the bottom, it follows: a new message arriving is followed down until
//   its top reaches the top of the pane (under whatever floats over it: its
//   `scroll-padding-top`), so a long one is read from its start; the bottom
//   growing otherwise (a reply streaming in, an image loading) is followed too.
//   Following glides there, except to what the list marks `data-caught` (caught
//   up on, not said as the reader watched: history read in after the kept
//   page, what was missed while the link was down), which is taken at once.
// - away from the bottom (the reader scrolled up), what they read stays put:
//   the message at the top of the pane keeps its place, whatever changes
//   above it (older pages loading, images) or below it (new messages, however
//   long). This is immediate, so nothing they read moves.
// What the reader opens in it (a click there growing it: a tool's details, a
// group) is not new: at the bottom too, their place is kept from then on.
// Scrolling by anyone else (the reader: wheel, touch and its momentum, keys,
// the scrollbar; a jump to a message) sets the new position, and whether it is
// at the bottom; the pane carries `data-reading-up` while it is not. A
// `to-bottom` event on the pane glides to the bottom and follows it again
// (taken at once with `detail: "at-once"`).
// A pane `short` of its end (it shows a window of a chat, more of it to load
// below) has no end in view to follow: its bottom is read like anywhere else,
// the reader's place kept as pages come in below it and leave above it. A
// `trimmed` event on the pane says messages left its ends that way (a window
// moving along): the floor lets go of what it held, or the space they took
// would stay behind as blank room.
// With a `floor` (an empty last child), the content never gets shorter: what
// leaves the bottom (an activity folding away) leaves its space behind, filled
// by the floor, so nothing above it drops down. A change of the width its
// content is laid out in (the pane's, or its padding) lays everything out anew, so the floor lets go of what it was holding.
import { useEffect, useRef, type RefObject } from "react";

/**
 * `resize` watching `el` and each of its children: `all` (again) from scratch, `update` as `records` (a MutationObserver's
 * on `el`) say children came and went. Only those: observing every child anew would have each report its size again,
 * every message of a long chat at each change anywhere in it (a second ticking by in an agent's activity).
 */
export function watchChildren(el: Element, resize: ResizeObserver): { all: () => void; update: (records: MutationRecord[]) => void } {
  return {
    all: () => { resize.disconnect(); resize.observe(el); for (const child of el.children) resize.observe(child); },
    update: (records) => {
      for (const r of records) {
        if (r.target !== el || r.type !== "childList") continue;
        for (const n of r.removedNodes) if (n instanceof Element && n.parentNode !== el) resize.unobserve(n);
        for (const n of r.addedNodes) if (n instanceof Element && n.parentNode === el) resize.observe(n);
      }
    },
  };
}

/**
 * The first of `items` (in the order they are laid out, one under another) whose bottom reaches below `y`: found by
 * halves, measuring a few of them rather than every one above it (this runs as the reader scrolls).
 */
export function firstReaching<T extends Element>(items: readonly T[], y: number): T | undefined {
  let lo = 0;
  let hi = items.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (items[mid]!.getBoundingClientRect().bottom > y) hi = mid;
    else lo = mid + 1;
  }
  return items[lo];
}

/** `messages` selects which of the pane's children count as messages; `short`: its bottom is not the end (above). */
export function useStickToBottom(ref: RefObject<HTMLElement | null>, messages = "*", floor?: RefObject<HTMLElement | null>, short = false): void {
  // Read as the pane changes, without starting over.
  const isShort = useRef(short);
  isShort.current = short;
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    /** The furthest the content has reached; the floor makes up what it has lost since. */
    let reached = 0;
    /** The width its content is laid out in: the pane's, less its padding (which can change on its own: making way for
     *  the small web services in the corner, Previews.tsx). */
    const contentWidth = () => {
      const style = getComputedStyle(el);
      return el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    };
    let width = contentWidth();
    const keepHeight = () => {
      const f = floor?.current;
      if (!f) return;
      const end = el.scrollTop + f.getBoundingClientRect().top - el.getBoundingClientRect().top;
      const now = contentWidth();
      if (now !== width) { width = now; reached = 0; }
      // Only messages' room is held: what a pane shows before it has any (loading, an empty chat's note) is not.
      if (!lastMessage()) reached = 0;
      reached = Math.max(reached, end);
      // Not rounded: what grows above it by a fraction of a pixel a frame (an activity opening) would make the content
      // a pixel taller and shorter by turns, and the pane shake.
      const height = `${reached - end}px`;
      if (f.style.height !== height) f.style.height = height;
    };
    /** Following the bottom (or `anchor`, a new message, from its top), or holding the reader's place (`reading`). */
    let following = !isShort.current;
    let anchor: Element | null = null;
    /** Where the reader is: the message at the pane's top, and how far below the pane's top it sat. */
    let reading: { el: Element; offset: number } | null = null;
    /** Where a glide is going, and its frame (0: none). The first position is taken at once. */
    let goal = 0;
    let frame = 0;
    let settled = false;
    /** Whether this change may glide: messages arriving or growing, after the pane's opening moments. Anything else
     *  (a slot or the floor taking its size, the pane resized, what a newly opened chat first shows) is taken at once. */
    let smooth = false;
    const born = performance.now();
    const grown = () => performance.now() - born > 500;
    /** The message a node is in (or is). */
    const messageOf = (node: Node | null): Element | null => {
      for (let n: Node | null = node; n && n !== el; n = n.parentNode) if (isMessage(n)) return n;
      return null;
    };
    let lastFrame = 0;
    /** Where this last put the pane: a scroll to anywhere else is someone else's. */
    let placed = el.scrollTop;
    const place = (top: number) => { el.scrollTop = top; placed = el.scrollTop; };
    const stop = () => { cancelAnimationFrame(frame); frame = 0; };
    const distance = () => el.scrollHeight - el.scrollTop - el.clientHeight;
    const paneTop = () => el.getBoundingClientRect().top;
    const topOf = (node: Element) => el.scrollTop + node.getBoundingClientRect().top - paneTop();
    const isMessage = (n: Node): n is Element => n instanceof Element && n.parentElement === el && n.matches(messages);
    // Transient rows (an activity that will fold away) are never what a replaced message hands over to.
    const lastMessage = () => [...el.children].filter((n) => isMessage(n) && !n.hasAttribute("data-transient")).at(-1) ?? null;
    // Each frame covers the same share of what is left (about 90% in a quarter second), so a long way is quick and a
    // goal that moves on (a message still unrolling) is followed without a restart.
    const glide = (now: number) => {
      const dt = Math.min(64, now - lastFrame);
      lastFrame = now;
      const left = goal - el.scrollTop;
      if (Math.abs(left) < 1) { place(goal); frame = 0; return; }
      place(el.scrollTop + left * (1 - Math.exp(-dt / 100)));
      frame = requestAnimationFrame(glide);
    };
    /** The reader's place, as it is now: the first message reaching below the pane's top. */
    const note = () => {
      const top = paneTop();
      reading = null;
      const child = firstReaching([...el.children].filter((n) => isMessage(n) && !n.hasAttribute("data-transient")), top + 1);
      if (child) reading = { el: child, offset: child.getBoundingClientRect().top - top };
    };
    const hold = () => {
      const glides = smooth;
      smooth = false;
      keepHeight();
      const bottom = Math.max(0, el.scrollHeight - el.clientHeight);
      if (!following) {
        // The reader's message where it was; without it (gone), where the pane is.
        if (!reading || !reading.el.isConnected) note();
        stop();
        if (reading) {
          const target = Math.min(bottom, Math.max(0, topOf(reading.el) - reading.offset));
          if (Math.abs(el.scrollTop - target) > 0.5) place(target);
        }
        return;
      }
      // A followed message that was replaced (a streamed reply landing) hands over to the newest.
      if (anchor && !anchor.isConnected) anchor = lastMessage();
      // A followed message stops just under what covers the pane's top (a floating bar: its `scroll-padding-top`).
      const cover = parseFloat(getComputedStyle(el).scrollPaddingTop) || 0;
      const target = anchor ? Math.min(bottom, Math.max(0, topOf(anchor) - cover - 12)) : bottom;
      // Content leaving the bottom makes the pane shorter for a moment, and the browser pulls it up: that is put back
      // at once, as if it never happened.
      if (settled && el.scrollTop < placed - 0.5 && placed <= bottom) place(placed);
      // A followed message longer than what is left of the pane, reached: it is being read from its start, so from
      // here its place is kept (what comes after it does not take the reader away).
      if (anchor && target < bottom - 0.5 && !frame && Math.abs(el.scrollTop - target) < 1) {
        following = false;
        reading = { el: anchor, offset: anchor.getBoundingClientRect().top - paneTop() };
        anchor = null;
        return;
      }
      // Following on down glides (messages arriving or growing); the first position, back up, or anything else that
      // changed is taken at once.
      // A glide under way goes on (its own steps come back here as scroll events, with nothing new to glide for).
      if (settled && (glides || frame) && target > el.scrollTop + 0.5) {
        goal = target;
        if (!frame) { lastFrame = performance.now(); frame = requestAnimationFrame(glide); }
        return;
      }
      stop();
      if (Math.abs(el.scrollTop - target) > 0.5) place(target);
    };
    /** Someone else moved the pane: at its bottom it follows again; anywhere else the reader's place is kept. */
    const moved = () => {
      stop();
      anchor = null;
      placed = el.scrollTop;
      following = !isShort.current && distance() <= 2;
      if (following) reading = null;
      else note();
      el.toggleAttribute("data-reading-up", !following);
    };
    let lastInput = 0;
    const onScroll = () => {
      // Its own steps.
      if (Math.abs(el.scrollTop - placed) < 1) return hold();
      // Pulled up by the browser as content left the bottom (at the bottom, with no one scrolling): put back.
      if (following && Date.now() - lastInput > 400 && el.scrollTop < placed && distance() <= 1) return hold();
      moved();
    };
    const input = () => { lastInput = Date.now(); };
    /** A click in the pane, until the frame after it: what grows or shrinks by then is the reader's doing. */
    let opening = false;
    const click = () => { opening = true; requestAnimationFrame(() => requestAnimationFrame(() => { opening = false; })); };
    /** The reader opened something while it followed: nothing new came, so their place is kept instead. */
    const readHere = () => {
      if (!opening || !following) return;
      stop();
      following = false;
      anchor = null;
      note();
      el.toggleAttribute("data-reading-up", true);
    };
    el.addEventListener("click", click, true);
    const toBottom = (event: Event) => {
      // At once: what came in meanwhile (a chat's latest page in place of its window) is not followed from its top.
      const atOnce = event instanceof CustomEvent && event.detail === "at-once";
      if (atOnce) { mutations.takeRecords(); watch(); }
      anchor = null; reading = null; following = true; smooth = !atOnce; el.removeAttribute("data-reading-up"); hold();
    };
    el.addEventListener("to-bottom", toBottom);
    const trimmed = () => { reached = 0; };
    el.addEventListener("trimmed", trimmed);
    el.addEventListener("scroll", onScroll, { passive: true });
    for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.addEventListener(type, input, { passive: true });
    // The pane's width changing re-wraps every message: that is taken at once, not glided after (it would lag behind
    // the bottom while the width is dragged).
    let laidWidth = contentWidth();
    const resize = new ResizeObserver((entries) => {
      const rewrapped = contentWidth() !== laidWidth;
      laidWidth = contentWidth();
      smooth = !rewrapped && grown() && entries.some((e) => e.target !== el && isMessage(e.target));
      if (!rewrapped && entries.some((e) => e.target !== el)) readHere();
      hold();
    });
    const watched = watchChildren(el, resize);
    const watch = watched.all;
    watch();
    const mutations = new MutationObserver((records) => {
      const added = records.flatMap((r) => [...r.addedNodes]).filter(isMessage);
      // Only messages arriving at the bottom are followed (older ones loaded above are not); ones arriving while the
      // reader is further up leave them where they are.
      const kids = [...el.children].filter(isMessage);
      const arrived = added.filter((n) => kids.slice(kids.indexOf(n) + 1).every((k) => added.includes(k) || k.hasAttribute("data-transient")));
      if (arrived.length && following) anchor = arrived.at(-1)!;
      // Grown below by what the reader just opened (the bottom moved on with nothing new).
      else if (!arrived.length && distance() > 1) readHere();
      smooth = grown() && (arrived.some((n) => !n.hasAttribute("data-caught")) || records.some((r) => r.target !== el && messageOf(r.target) !== null));
      watched.update(records);
      hold();
    });
    mutations.observe(el, { childList: true, subtree: true, characterData: true });
    // An image loading in a message grows it.
    const onLoad = (event: Event) => { smooth = grown() && messageOf(event.target as Node) !== null; hold(); };
    el.addEventListener("load", onLoad, true);
    el.toggleAttribute("data-reading-up", !following);
    hold();
    settled = true;
    return () => {
      stop();
      el.removeEventListener("to-bottom", toBottom);
      el.removeEventListener("trimmed", trimmed);
      el.removeEventListener("scroll", onScroll);
      el.removeEventListener("click", click, true);
      for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.removeEventListener(type, input);
      el.removeEventListener("load", onLoad, true);
      resize.disconnect();
      mutations.disconnect();
    };
  }, [ref, messages, floor]);
}
