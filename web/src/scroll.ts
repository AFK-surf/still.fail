// Keeps a scrolling pane's distance from its bottom while its content changes
// (messages arriving, images loading, text streaming, blocks folding): at the
// bottom stays at the bottom, 300px up stays 300px up. Only the reader moves
// that distance, by scrolling themselves.
import { useEffect, type RefObject } from "react";

export function useStickToBottom(ref: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let gap = 0;
    // The reader is scrolling while a pointer is down on the pane, or shortly after a wheel, touch or key.
    let pointerDown = false;
    let lastInput = 0;
    const reading = () => pointerDown || Date.now() - lastInput < 400;
    const distance = () => el.scrollHeight - el.scrollTop - el.clientHeight;
    const hold = () => {
      const target = Math.max(0, el.scrollHeight - el.clientHeight - gap);
      if (Math.abs(el.scrollTop - target) > 0.5) el.scrollTop = target;
    };
    const onScroll = () => {
      if (reading()) gap = Math.max(0, distance());
      else hold();
    };
    const input = () => { lastInput = Date.now(); };
    const down = () => { pointerDown = true; };
    const up = () => { if (pointerDown) { pointerDown = false; gap = Math.max(0, distance()); } };
    el.addEventListener("scroll", onScroll, { passive: true });
    for (const type of ["wheel", "touchmove", "keydown"]) el.addEventListener(type, input, { passive: true });
    el.addEventListener("pointerdown", down);
    window.addEventListener("pointerup", up);
    // Any change of size, inside or of the pane itself, is held to the same distance from the bottom.
    const resize = new ResizeObserver(hold);
    const watch = () => { resize.disconnect(); resize.observe(el); for (const child of el.children) resize.observe(child); };
    watch();
    const mutations = new MutationObserver(() => { watch(); hold(); });
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
  }, [ref]);
}
