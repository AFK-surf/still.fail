// How a message pane scrolls while its content changes, with the reader not
// touching it:
// - a new message arriving while the pane is at its bottom is followed down
//   until its top reaches the top of the pane, so a long one is read from its
//   start (a reply streaming in grows the same way);
// - any other change (images loading, text settling, blocks folding) keeps
//   the distance from the bottom: at the bottom stays at the bottom.
// Scrolling by the reader sets the new position.
// Following (a new message, or the bottom as it grows) glides there; keeping
// the reader's place is immediate, so what they read does not move. A
// `to-bottom` event on the pane glides to the bottom and follows it again.
// With a `floor` (an empty last child), the content never gets shorter: what
// leaves the bottom (an activity folding away) leaves its space behind, filled
// by the floor, so nothing above it drops down. A change of the pane's width
// lays everything out anew, so the floor lets go of what it was holding.
import { useEffect, type RefObject } from "react";

/** `messages` selects which of the pane's children count as messages. */
export function useStickToBottom(ref: RefObject<HTMLElement | null>, messages = "*", floor?: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let gap = 0;
    /** The furthest the content has reached; the floor makes up what it has lost since. */
    let reached = 0;
    let width = el.clientWidth;
    const keepHeight = () => {
      const f = floor?.current;
      if (!f) return;
      const end = el.scrollTop + f.getBoundingClientRect().top - el.getBoundingClientRect().top;
      if (el.clientWidth !== width) { width = el.clientWidth; reached = 0; }
      reached = Math.max(reached, end);
      const height = `${Math.round(reached - end)}px`;
      if (f.style.height !== height) f.style.height = height;
    };
    /** The message being followed: kept in view from its top. */
    let anchor: Element | null = null;
    let atBottom = true;
    /** Where a glide is going, and its frame (0: none). The first position is taken at once. */
    let goal = 0;
    let frame = 0;
    let settled = false;
    let lastFrame = 0;
    /** Where this last put the pane: a scroll to anywhere else is someone else's. */
    let placed = -1;
    const place = (top: number) => { el.scrollTop = top; placed = el.scrollTop; };
    /** Whether the reader moved the pane during the press now ending. */
    let movedWhileDown = false;
    const stop = () => { cancelAnimationFrame(frame); frame = 0; };
    // Each frame covers the same share of what is left (about 90% in a quarter second), so a long way is quick and a
    // goal that moves on (a message still unrolling) is followed without a restart.
    const glide = (now: number) => {
      const dt = Math.min(64, now - lastFrame);
      lastFrame = now;
      const left = goal - el.scrollTop;
      if (Math.abs(left) < 1) { place(goal); frame = 0; atBottom = distance() <= 2; return; }
      place(el.scrollTop + left * (1 - Math.exp(-dt / 100)));
      frame = requestAnimationFrame(glide);
    };
    let pointerDown = false;
    let lastInput = 0;
    const reading = () => pointerDown || Date.now() - lastInput < 400;
    const distance = () => el.scrollHeight - el.scrollTop - el.clientHeight;
    const topOf = (node: Element) => el.scrollTop + node.getBoundingClientRect().top - el.getBoundingClientRect().top;
    const isMessage = (n: Node): n is Element => n instanceof Element && n.parentElement === el && n.matches(messages);
    // Transient rows (an activity that will fold away) are never what a replaced message hands over to.
    const lastMessage = () => [...el.children].filter((n) => isMessage(n) && !n.hasAttribute("data-transient")).at(-1) ?? null;
    const hold = () => {
      keepHeight();
      const bottom = Math.max(0, el.scrollHeight - el.clientHeight);
      // A followed message that was replaced (a streamed reply landing) hands over to the newest.
      if (anchor && !anchor.isConnected) anchor = lastMessage();
      const target = anchor ? Math.min(bottom, Math.max(0, topOf(anchor) - 12)) : Math.max(0, bottom - gap);
      // Following on down glides; anything else (the reader's place kept, the first position) is taken at once.
      const follow = settled && (anchor !== null || gap === 0) && target > el.scrollTop + 0.5;
      ((window as unknown as { __sl?: unknown[] }).__sl ??= []).push([Math.round(performance.now()), follow ? "F" : "P", Math.round(el.scrollTop), Math.round(target), Math.round(bottom), anchor ? String((anchor as HTMLElement).className).slice(0, 14) : "-", Math.round(gap)]); // TEMP
      if (follow) {
        goal = target;
        atBottom = true;
        if (!frame) { lastFrame = performance.now(); frame = requestAnimationFrame(glide); }
        return;
      }
      stop();
      if (Math.abs(el.scrollTop - target) > 0.5) place(target);
      atBottom = distance() <= 2;
    };
    const onScroll = () => {
      // A glide's own steps are not the reader's, even under a pressed pointer.
      if (reading() && Math.abs(el.scrollTop - placed) >= 1) {
        ((window as unknown as { __sl?: unknown[] }).__sl ??= []).push([Math.round(performance.now()), "R", Math.round(el.scrollTop), pointerDown, Date.now() - lastInput]); // TEMP
        if (pointerDown) movedWhileDown = true;
        stop();
        anchor = null;
        gap = Math.max(0, distance());
        atBottom = gap <= 2;
      } else hold();
    };
    const input = () => { lastInput = Date.now(); };
    const down = () => { pointerDown = true; movedWhileDown = false; };
    const up = () => {
      if (!pointerDown) return;
      pointerDown = false;
      // A click (on a message, a button) leaves the pane as it goes; only a drag of it is the reader's move.
      if (!movedWhileDown) return;
      stop();
      anchor = null;
      gap = Math.max(0, distance());
      atBottom = gap <= 2;
    };
    const toBottom = () => { anchor = null; gap = 0; hold(); };
    el.addEventListener("to-bottom", toBottom);
    el.addEventListener("scroll", onScroll, { passive: true });
    for (const type of ["wheel", "touchmove", "keydown"]) el.addEventListener(type, input, { passive: true });
    el.addEventListener("pointerdown", down);
    window.addEventListener("pointerup", up);
    const resize = new ResizeObserver(hold);
    const watch = () => { resize.disconnect(); resize.observe(el); for (const child of el.children) resize.observe(child); };
    watch();
    const mutations = new MutationObserver((records) => {
      const added = records.flatMap((r) => [...r.addedNodes]).filter(isMessage);
      // Only messages arriving at the bottom are followed (older ones loaded above are not: the distance from the
      // bottom holds them in place); ones arriving while the reader is further up leave them where they are.
      const kids = [...el.children].filter(isMessage);
      const arrived = added.filter((n) => kids.slice(kids.indexOf(n) + 1).every((k) => added.includes(k) || k.hasAttribute("data-transient")));
      if (arrived.length && atBottom) { anchor = arrived.at(-1)!; gap = 0; }
      watch();
      hold();
    });
    mutations.observe(el, { childList: true, subtree: true, characterData: true });
    const onLoad = () => hold();
    el.addEventListener("load", onLoad, true);
    hold();
    settled = true;
    return () => {
      stop();
      el.removeEventListener("to-bottom", toBottom);
      el.removeEventListener("scroll", onScroll);
      for (const type of ["wheel", "touchmove", "keydown"]) el.removeEventListener(type, input);
      el.removeEventListener("pointerdown", down);
      window.removeEventListener("pointerup", up);
      el.removeEventListener("load", onLoad, true);
      resize.disconnect();
      mutations.disconnect();
    };
  }, [ref, messages, floor]);
}
