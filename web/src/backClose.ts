// Back closes what lies over the page, on a touch screen as a phone's apps do: each open layer (a sheet, a menu, a file
// over everything, a dialog) holds an entry of the browser's history of its own, the page's address with `emberLayer`
// (how many layers deep) added to the router's state, so the router sees the same page. Back leaves that entry and the
// layers over where it lands close; a layer closed another way (its ×, the scrim) goes back off its entry itself.
import { useEffect, useRef } from "react";

interface Layer { depth: number; close: () => void; gone: boolean }

const layers: Layer[] = [];
/** The entry in view as last seen: back or forward is told by where it came from. */
let last = { idx: 0, layer: 0 };
/** A back of our own on its way (a layer closed by hand): navigations wait for it, or it would undo them. */
let pending: { done: Promise<void>; settle: () => void } | null = null;

const layerOf = (state: unknown) => (state as { emberLayer?: number } | null)?.emberLayer ?? 0;
const idxOf = (state: unknown) => (state as { idx?: number } | null)?.idx ?? 0;
const touch = () => window.matchMedia("(hover: none) and (pointer: coarse)").matches;

let listening = false;
function listen() {
  if (listening) return;
  listening = true;
  const seen = () => { last = { idx: idxOf(history.state), layer: layerOf(history.state) }; };
  seen();
  // Where back or forward went is told by where it came from, so the entries the router writes are noted too.
  for (const name of ["pushState", "replaceState"] as const) {
    const write = history[name];
    history[name] = function (this: History, ...args: Parameters<History["pushState"]>) {
      write.apply(this, args);
      seen();
    };
  }
  window.addEventListener("popstate", () => {
    pending?.settle();
    pending = null;
    const layer = layerOf(history.state), idx = idxOf(history.state);
    const backward = idx < last.idx || (idx === last.idx && layer < last.layer);
    last = { idx, layer };
    while (layers.length && layers.at(-1)!.depth > layer) {
      const gone = layers.pop()!;
      gone.gone = true;
      gone.close();
    }
    // Landed on the entry of a layer no longer open (left by a page opened from it): pass it the way we were going;
    // forward with nothing past it, back to where that came from, as if forward had nothing to go to.
    if (layer > 0 && !layers.some((l) => l.depth === layer)) {
      if (backward) history.back();
      else {
        const at = history.state as unknown;
        history.forward();
        setTimeout(() => { if (history.state === at) history.back(); }, 200);
      }
    }
  });
}

function hold(close: () => void): Layer {
  listen();
  const layer: Layer = { depth: layers.length + 1, close, gone: false };
  layers.push(layer);
  const state = { ...(history.state as object | null), emberLayer: layer.depth };
  // The entry of a layer just closed by hand, not yet gone back off (a menu giving way to the sheet it opened): reused.
  if (layerOf(history.state) >= layer.depth) history.replaceState(state, "");
  else history.pushState(state, "");
  return layer;
}

function release(layer: Layer) {
  if (layer.gone) return;
  layer.gone = true;
  layers.splice(layers.indexOf(layer), 1);
  // After what closed it has run: a page it opened has taken the entry's place (then it stays, passed by back later),
  // or another layer has taken it over.
  setTimeout(() => {
    if (layerOf(history.state) !== layer.depth || layers.some((l) => l.depth >= layer.depth)) return;
    let settle = () => {};
    const done = new Promise<void>((resolve) => { settle = resolve; });
    pending = { done, settle };
    history.back();
  });
}

/** While `open` (on a touch screen), back calls `close` instead of leaving the page. */
export function useBackClose(open: boolean, close: () => void) {
  const latest = useRef(close);
  latest.current = close;
  useEffect(() => {
    if (!open || !touch()) return;
    const layer = hold(() => latest.current());
    return () => release(layer);
  }, [open]);
}

/** Runs a navigation once a back of our own (a layer closed by hand) has landed. */
export function afterBack(go: () => void) {
  if (pending) void pending.done.then(go);
  else go();
}
