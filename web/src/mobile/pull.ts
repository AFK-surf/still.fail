// Home's virtual panes suppress native rubber-banding. One translation follows the finger to reveal the reload
// mark; never switch between scrollTop bounce and translation partway through the same gesture.
import { useFrameDraw } from "./gesture.ts";
import { useEffect, useRef, type TouchEvent } from "react";
import { reload } from "../reloads.ts";

const PULL_READY_PX = 80;
const MOST_PX = 64;
const BACK = "transform 240ms var(--ease-out), translate 200ms var(--ease-out)";

type Pull = { x: number; y: number; list: HTMLElement; down: number; transition: string; translate: string };

export function usePullToReload(pane: string) {
  const mark = useRef<HTMLDivElement>(null);
  const pull = useRef<Pull | null>(null);
  const settling = useRef<{ pull: Pull; timer: ReturnType<typeof setTimeout> } | null>(null);
  const finish = () => {
    const at = settling.current;
    if (!at) return;
    clearTimeout(at.timer);
    at.pull.list.style.transition = at.pull.transition;
    at.pull.list.style.translate = at.pull.translate;
    settling.current = null;
  };
  const show = (at: Pull, down: number) => {
    const moved = Math.min(down / 2, MOST_PX);
    at.list.style.translate = moved ? `0 ${moved}px` : at.translate;
    const el = mark.current;
    if (!el) return;
    el.style.setProperty("--pull", String(Math.min(1, down / PULL_READY_PX)));
    el.style.setProperty("--gap", `${moved}px`);
    el.toggleAttribute("data-ready", down >= PULL_READY_PX);
  };
  const fingers = useFrameDraw<number>(down => { const at = pull.current; if (at) show(at, down); });
  const stop = (immediate = false) => {
    fingers.cancel();
    finish();
    const at = pull.current;
    pull.current = null;
    mark.current?.removeAttribute("data-pulling");
    if (!at) return;
    at.list.style.transition = immediate ? at.transition : BACK;
    show(at, 0);
    if (!immediate) settling.current = { pull: at, timer: setTimeout(finish, 240) };
  };
  // React Activity also cleans this up when Home is covered: no translated pane or pending timer on return.
  useEffect(() => {
    const el = mark.current;
    return () => {
      stop(true);
      el?.removeAttribute("data-pulling");
      el?.removeAttribute("data-ready");
      el?.removeAttribute("data-reloading");
      el?.style.removeProperty("--pull");
      el?.style.removeProperty("--gap");
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const handlers = {
    onTouchStart: (event: TouchEvent) => {
      if (mark.current?.hasAttribute("data-reloading")) return;
      stop(true);
      const list = (event.target as Element).closest?.<HTMLElement>(`.${pane}`);
      const touch = event.touches[0];
      if (!list || !touch || event.touches.length !== 1 || list.scrollTop > 0) return;
      pull.current = { x: touch.clientX, y: touch.clientY, list, down: 0, transition: list.style.transition, translate: list.style.translate };
      list.style.transition = "transform 240ms var(--ease-out)";
      mark.current?.setAttribute("data-pulling", "");
    },
    onTouchMove: (event: TouchEvent) => {
      const at = pull.current;
      const touch = event.touches[0];
      if (!at) return;
      if (!touch || event.touches.length !== 1) return stop();
      const down = touch.clientY - at.y;
      const across = touch.clientX - at.x;
      if ((Math.abs(across) > 10 && Math.abs(across) > Math.abs(down)) || at.list.scrollTop > 0) return stop();
      at.down = Math.max(0, down);
      fingers.set(at.down);
    },
    onTouchEnd: () => {
      fingers.flush();
      if (mark.current?.hasAttribute("data-reloading")) return;
      const at = pull.current;
      if (at && at.down >= PULL_READY_PX && mark.current) {
        mark.current.removeAttribute("data-pulling");
        mark.current.setAttribute("data-reloading", "");
        reload("pull");
        return;
      }
      stop();
    },
    onTouchCancel: () => stop(),
  };
  return { handlers, mark };
}
