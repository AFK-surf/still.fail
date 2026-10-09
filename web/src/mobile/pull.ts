// Pulling a list down from its top loads the page again, as a phone's browser does: an app on the home screen has no
// browser round it (iOS gives it none), and loading the page again is the way out of anything stuck. The list comes
// down with the finger (iOS bounces it so itself; elsewhere it is moved by hand), and a mark in the gap over it turns
// as it opens; once far enough the mark takes the accent, and letting go then reloads.
import { useRef, type TouchEvent } from "react";

/** How far the finger goes down before letting go reloads. */
const PULL_READY_PX = 80;
/** A list moved by hand goes half as far as the finger, and no farther than this. */
const MOST_PX = 64;
/** The list moving back into place after a pull let go short, as the pane's own moves ease (Home.css.ts). */
const BACK = "transform 240ms var(--m-standard), translate 200ms var(--m-ease)";

/**
 * The touch handlers for the lists' frame (`pane`: the class of the lists that scroll in it) and the ref for the mark
 * they move: its `--pull` from 0 to 1 and `--gap` (how far the list has come down), `data-ready` once letting go
 * reloads, `data-reloading` as it does; `data-pulling` while the finger is on it (no easing behind it).
 */
export function usePullToReload(pane: string) {
  const mark = useRef<HTMLDivElement>(null);
  const pull = useRef<{ x: number; y: number; list: HTMLElement; down: number } | null>(null);
  const show = (list: HTMLElement, down: number) => {
    // iOS bounces the list down itself (scrolled above its top); elsewhere it does not, and it is moved here.
    const bounced = Math.max(0, -list.scrollTop);
    const moved = bounced > 0 ? 0 : Math.min(down / 2, MOST_PX);
    list.style.translate = moved ? `0 ${moved}px` : "";
    const at = mark.current;
    if (!at) return;
    at.style.setProperty("--pull", String(Math.min(1, down / PULL_READY_PX)));
    at.style.setProperty("--gap", `${bounced || moved}px`);
    at.toggleAttribute("data-ready", down >= PULL_READY_PX);
  };
  const stop = () => {
    const at = pull.current;
    pull.current = null;
    mark.current?.removeAttribute("data-pulling");
    if (!at) return;
    at.list.style.transition = BACK;
    show(at.list, 0);
    setTimeout(() => { if (pull.current?.list !== at.list) at.list.style.transition = ""; }, 240);
  };
  const handlers = {
    onTouchStart: (event: TouchEvent) => {
      const list = (event.target as Element).closest?.<HTMLElement>(`.${pane}`);
      const touch = event.touches[0];
      // Only from a list at its top, with one finger.
      if (!list || !touch || event.touches.length !== 1 || list.scrollTop > 0) return void (pull.current = null);
      pull.current = { x: touch.clientX, y: touch.clientY, list, down: 0 };
      // With the finger, not eased behind it.
      list.style.transition = "transform 240ms var(--m-standard)";
      mark.current?.setAttribute("data-pulling", "");
    },
    onTouchMove: (event: TouchEvent) => {
      const at = pull.current;
      const touch = event.touches[0];
      if (!at || !touch) return;
      const down = touch.clientY - at.y;
      const across = touch.clientX - at.x;
      // Across (a row swiped), or the list scrolled after all: no pull.
      if ((Math.abs(across) > 10 && Math.abs(across) > Math.abs(down)) || at.list.scrollTop > 0) return stop();
      at.down = Math.max(0, down);
      show(at.list, at.down);
    },
    onTouchEnd: () => {
      const at = pull.current;
      if (at && at.down >= PULL_READY_PX && mark.current) {
        pull.current = null;
        mark.current.setAttribute("data-reloading", "");
        location.reload();
        return;
      }
      stop();
    },
    onTouchCancel: stop,
  };
  return { handlers, mark };
}
