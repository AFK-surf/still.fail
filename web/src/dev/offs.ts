// In the development build, what is off as it shows: each corner, small panel and contrast measured as the stories' tests
// measure them (test/browser/measure.mjs, docs/ui-panels.md), again whenever the page changes, and what is off outlined
// in red, saying why when pointed at (and in the console, once each). A part written with its own corner or padding is
// seen wrong the first time it is looked at, not when CI measures a story that may never reach it.
import { contrast, corners, panels } from "../../../test/browser/measure.mjs";

const said = new Set<string>();
let queued = 0;

function measure() {
  queued = 0;
  for (const el of document.querySelectorAll("[data-off]")) el.removeAttribute("data-off");
  for (const why of [...corners(true).wrong, ...panels(true).wrong, ...contrast(true).wrong]) {
    if (said.has(why)) continue;
    said.add(why);
    console.warn(`off (docs/ui-panels.md): ${why}`);
  }
}

/** Measures the page now and after each change to it (once the change has settled), outlining what is off. */
export function watchOffs(): void {
  const style = document.createElement("style");
  style.textContent = "[data-off] { outline: 2px solid #ff2d55 !important; outline-offset: -1px; }";
  document.head.append(style);
  const again = () => { clearTimeout(queued); queued = window.setTimeout(measure, 400); };
  // Its own marks are no change.
  new MutationObserver((changes) => { if (changes.some((c) => c.attributeName !== "data-off")) again(); })
    .observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
  addEventListener("resize", again);
  document.addEventListener("transitionend", again, true);
  again();
}
