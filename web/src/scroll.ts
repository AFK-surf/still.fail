// Keeps a scrolling pane at its bottom while the reader is there: new content,
// images finishing loading, code getting highlighted, text streaming in. Once
// the reader scrolls up it lets go, until they come back down.
import { useEffect, useRef, type RefObject } from "react";

export function useStickToBottom(ref: RefObject<HTMLElement | null>): RefObject<boolean> {
  const pinned = useRef(true);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const toBottom = () => { if (pinned.current) el.scrollTop = el.scrollHeight; };
    // Only the reader lets go of the bottom: scrolls caused by layout (content settling, clamping) never do.
    let byReader = 0;
    const reader = () => { byReader = Date.now(); };
    const onScroll = () => {
      const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
      if (atBottom) pinned.current = true;
      else if (Date.now() - byReader < 600) pinned.current = false;
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.addEventListener(type, reader, { passive: true });
    // Any child growing (an image decoding, a block being highlighted) moves the bottom.
    const resize = new ResizeObserver(toBottom);
    const watch = () => { resize.disconnect(); resize.observe(el); for (const child of el.children) resize.observe(child); };
    watch();
    const mutations = new MutationObserver(() => { watch(); toBottom(); });
    mutations.observe(el, { childList: true, subtree: true, characterData: true });
    // Images load after layout; catch them as they finish.
    const onLoad = (e: Event) => { if (e.target instanceof HTMLImageElement) toBottom(); };
    el.addEventListener("load", onLoad, true);
    toBottom();
    // For a moment after opening, settle every frame: fonts, highlighting and late layout all move the bottom.
    const until = Date.now() + 1500;
    let frame = requestAnimationFrame(function settle() {
      toBottom();
      if (Date.now() < until) frame = requestAnimationFrame(settle);
    });
    return () => {
      cancelAnimationFrame(frame);
      el.removeEventListener("scroll", onScroll);
      for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.removeEventListener(type, reader);
      el.removeEventListener("load", onLoad, true);
      resize.disconnect();
      mutations.disconnect();
    };
  }, [ref]);
  return pinned;
}
