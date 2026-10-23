import { useEffect, useLayoutEffect, useRef } from "react";
import type { VirtualList } from "./list.tsx";

/** Load once per entry cursor. A request owns its edge until both its answer and the
 * advanced cursor's measured, committed layout arrive. Failure never schedules a retry. */
export function useLoadNear(virtual: VirtualList, edge: "top" | "bottom", can: boolean, at: number | string | undefined, load: () => Promise<unknown>): void {
  const latest = useRef({ virtual, can, at, load });
  const changed = useRef<(() => void) | null>(null);
  // Publish only committed props; an interrupted render must not release an in-flight request.
  useLayoutEffect(() => {
    latest.current = { virtual, can, at, load };
    changed.current?.();
  });
  const { model } = virtual;
  useEffect(() => {
    let live = true;
    let asked: number | string | undefined;
    let busy: { at: number | string; answered: boolean } | null = null;
    let top = model.layout().scrollTop;
    const check = (scrolled = false) => {
      const now = latest.current;
      if (!live || !now.virtual.committed()) return;
      if (busy) {
        if (!busy.answered || now.at === busy.at) return;
        busy = null;
        // Restoring an anchor after a page is not an approach to an edge.
        if (!model.fits) return;
      }
      if (!now.can || now.at === undefined || asked === now.at) return;
      if (asked !== undefined && !scrolled && !model.fits) return;
      if (model.paneHeight <= 0 || (edge === "top" ? model.toStart : model.toEnd) > model.paneHeight) return;
      asked = now.at;
      const request: { at: number | string; answered: boolean } = { at: now.at, answered: false };
      busy = request;
      void now.load().then(() => {
        if (!live || busy !== request) return;
        request.answered = true;
        check();
      }, () => {
        // Keep the attempted cursor: layout notifications must not retry this failure.
        if (live && busy === request) busy = null;
      });
    };
    changed.current = () => check();
    const stop = virtual.watch(() => {
      const next = model.layout().scrollTop;
      const moved = next !== top;
      top = next;
      check(moved);
    });
    check();
    return () => { live = false; changed.current = null; stop(); };
  }, [model, edge]); // eslint-disable-line react-hooks/exhaustive-deps
}
