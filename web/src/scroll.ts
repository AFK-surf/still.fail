// How a message pane scrolls while its content changes, with the reader not
// touching it:
// - a new message arriving while the pane is at its bottom is followed down
//   until its top reaches the top of the pane, so a long one is read from its
//   start (a reply streaming in grows the same way);
// - any other change (images loading, text settling, blocks folding) keeps
//   the distance from the bottom: at the bottom stays at the bottom.
// Scrolling by the reader sets the new position.
import { useEffect, type RefObject } from "react";

/** `messages` selects which of the pane's children count as messages. */
export function useStickToBottom(ref: RefObject<HTMLElement | null>, messages = "*"): void {
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let gap = 0;
    /** The message being followed: kept in view from its top. */
    let anchor: Element | null = null;
    let atBottom = true;
    let pointerDown = false;
    let lastInput = 0;
    const reading = () => pointerDown || Date.now() - lastInput < 400;
    const distance = () => el.scrollHeight - el.scrollTop - el.clientHeight;
    const topOf = (node: Element) => el.scrollTop + node.getBoundingClientRect().top - el.getBoundingClientRect().top;
    const isMessage = (n: Node): n is Element => n instanceof Element && n.parentElement === el && n.matches(messages);
    // Transient rows (an activity that will fold away) are never what a replaced message hands over to.
    const lastMessage = () => [...el.children].filter((n) => isMessage(n) && !n.hasAttribute("data-transient")).at(-1) ?? null;
    const hold = () => {
      const bottom = Math.max(0, el.scrollHeight - el.clientHeight);
      // A followed message that was replaced (a streamed reply landing) hands over to the newest.
      if (anchor && !anchor.isConnected) anchor = lastMessage();
      const target = anchor ? Math.min(bottom, Math.max(0, topOf(anchor) - 12)) : Math.max(0, bottom - gap);
      if (Math.abs(el.scrollTop - target) > 0.5) el.scrollTop = target;
      atBottom = distance() <= 2;
    };
    const onScroll = () => {
      if (reading()) {
        anchor = null;
        gap = Math.max(0, distance());
        atBottom = gap <= 2;
      } else hold();
    };
    const input = () => { lastInput = Date.now(); };
    const down = () => { pointerDown = true; };
    const up = () => {
      if (!pointerDown) return;
      pointerDown = false;
      anchor = null;
      gap = Math.max(0, distance());
      atBottom = gap <= 2;
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    for (const type of ["wheel", "touchmove", "keydown"]) el.addEventListener(type, input, { passive: true });
    el.addEventListener("pointerdown", down);
    window.addEventListener("pointerup", up);
    const resize = new ResizeObserver(hold);
    const watch = () => { resize.disconnect(); resize.observe(el); for (const child of el.children) resize.observe(child); };
    watch();
    const mutations = new MutationObserver((records) => {
      const added = records.flatMap((r) => [...r.addedNodes]).filter(isMessage);
      // Only a message arriving at the bottom is followed; one arriving while the reader is further up leaves them where they are.
      if (added.length && atBottom) { anchor = added.at(-1)!; gap = 0; }
      watch();
      hold();
    });
    mutations.observe(el, { childList: true, subtree: true, characterData: true });
    const onLoad = () => hold();
    el.addEventListener("load", onLoad, true);
    hold();
    return () => {
      el.removeEventListener("scroll", onScroll);
      for (const type of ["wheel", "touchmove", "keydown"]) el.removeEventListener(type, input);
      el.removeEventListener("pointerdown", down);
      window.removeEventListener("pointerup", up);
      el.removeEventListener("load", onLoad, true);
      resize.disconnect();
      mutations.disconnect();
    };
  }, [ref, messages]);
}
