import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { VirtualList } from "./list.tsx";

/** Load once per entry cursor. A request owns its edge until both its answer and the
 * advanced cursor's measured, committed layout arrive. Failure waits for an explicit retry; layout notifications never retry it. */
export function useLoadNear(virtual: VirtualList, edge: "top" | "bottom", can: boolean, at: number | string | undefined, load: () => Promise<unknown>): { failed: boolean; retry(): void } {
  const [failed, setFailed] = useState(false);
  const retry = useRef<(() => void) | null>(null);
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
    let moved = false;
    const check = (scrolled = false) => {
      moved ||= scrolled;
      const now = latest.current;
      if (!live || !now.virtual.committed()) return;
      if (busy) {
        if (!busy.answered || now.at === busy.at) return;
        busy = null;
        // Restoring an anchor after a page is not an approach to an edge.
        moved = false;
        if (!model.fits) return;
      }
      // A scroll can replace the visible rows. Keep that approach until those rows
      // are measured and committed; its notification may precede the commit.
      const approached = moved;
      moved = false;
      if (!now.can || now.at === undefined || asked === now.at) return;
      if (asked !== undefined && !approached && !model.fits) return;
      if (model.paneHeight <= 0 || (edge === "top" ? model.toStart : model.toEnd) > model.paneHeight) return;
      setFailed(false);
      asked = now.at;
      const request: { at: number | string; answered: boolean } = { at: now.at, answered: false };
      busy = request;
      void now.load().then(() => {
        if (!live || busy !== request) return;
        request.answered = true;
        check();
      }, () => {
        // Keep the attempted cursor: layout notifications must not retry this failure.
        if (live && busy === request) { busy = null; setFailed(true); }
      });
    };
    retry.current = () => {
      if (busy) return;
      asked = undefined;
      check();
    };
    changed.current = () => check();
    const stop = virtual.watch(() => {
      const next = model.layout().scrollTop;
      const scrolled = next !== top;
      top = next;
      check(scrolled);
    });
    check();
    return () => { live = false; changed.current = null; retry.current = null; stop(); };
  }, [model, edge]); // eslint-disable-line react-hooks/exhaustive-deps
  return { failed, retry: () => retry.current?.() };
}

/** Empty entry windows can contain only letters or edits. Search one way at a time
 * so opposite requests cannot shuttle a bounded window over the same records. */
export function usePagingEdges(empty: boolean, more: boolean, newer: boolean): { older: boolean; newer: boolean } {
  const held = useRef<"top" | "bottom" | null>(null);
  let direction = empty ? held.current ?? (newer ? "bottom" : "top") : null;
  if (direction === "bottom" && !newer) direction = "top";
  useLayoutEffect(() => { held.current = direction; });
  return { older: more && direction !== "bottom", newer: newer && direction !== "top" };
}
