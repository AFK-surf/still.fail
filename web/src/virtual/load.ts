import { useEffect, useRef } from "react";
import type { VirtualList } from "./list.tsx";

/**
 * One page per approach to an edge of the pane: a page is asked when the reader is within a screenful of `edge`
 * (`can`: there is one; `at`: what is shown at that edge, asked after once). The pane is judged as the reader
 * scrolls, not as the page comes in: until the pane has put the reader's message back (virtual/model.ts),
 * it still looks near the edge, and would ask for another page at once. So after a page, nothing is asked until a
 * frame after it is in, and then only as the reader scrolls (or while what is loaded does not fill the pane).
 */
export function useLoadNear(virtual: VirtualList, edge: "top" | "bottom", can: boolean, at: number | string | undefined, load: () => Promise<unknown>): void {
  const latest = useRef({ load, at });
  latest.current = { load, at };
  const asked = useRef<number | string | undefined>(undefined);
  /** Judges the pane now; set while it is up. */
  const fill = useRef<(() => void) | null>(null);
  const { model } = virtual;
  useEffect(() => {
    if (!can) return;
    let live = true;
    let busy = false;
    const near = () => model.paneHeight > 0 && (edge === "top" ? model.toStart : model.toEnd) <= model.paneHeight;
    const check = () => {
      const { load, at } = latest.current;
      if (busy || asked.current === at || !near()) return;
      asked.current = at;
      busy = true;
      // Two frames on, the page is in and the reader's place kept (or the page never came: asked again).
      const settle = () => requestAnimationFrame(() => requestAnimationFrame(() => {
        busy = false;
        if (live && model.fits) check();
      }));
      void load().then(settle, () => { asked.current = undefined; settle(); });
    };
    fill.current = () => { if (model.fits) check(); };
    check();
    // As the reader scrolls: where the pane is, not what came into it.
    let top = model.layout().scrollTop;
    const stop = virtual.watch(() => { const now = model.layout().scrollTop; if (now !== top) { top = now; check(); } });
    return () => {
      live = false;
      fill.current = null;
      stop();
    };
  }, [model, can, edge]); // eslint-disable-line react-hooks/exhaustive-deps
  // A page in that does not fill the pane leaves nothing to scroll: the next is asked without waiting for the reader.
  useEffect(() => fill.current?.(), [at]);
}
