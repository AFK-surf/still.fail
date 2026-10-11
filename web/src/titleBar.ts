// The Windows app's window buttons (apps/desktop/src/main.ts, frame `overlay`): the system draws them over the page's top
// right, on a ground of one colour it is told. The page tells it the colours of what lies under them (the chat's bar, a
// settings page, the narrow layout's bar, in either theme) whenever that may have changed, so they read as part of it.

/** A CSS colour as #rrggbb, its alpha with it: what the browser paints it as. */
function hex(color: string, paint: CanvasRenderingContext2D): { hex: string; alpha: number } {
  paint.clearRect(0, 0, 1, 1);
  paint.fillStyle = color;
  paint.fillRect(0, 0, 1, 1);
  const [r = 0, g = 0, b = 0, a = 0] = paint.getImageData(0, 0, 1, 1).data;
  return { hex: `#${[r, g, b].map((n) => n.toString(16).padStart(2, "0")).join("")}`, alpha: a / 255 };
}

/** The colours under the window's buttons: the first opaque ground at the page's top right, and its text's. */
function under(paint: CanvasRenderingContext2D): [string, string] | null {
  let el = document.elementFromPoint(document.documentElement.clientWidth - 70, 22);
  for (; el; el = el.parentElement) {
    const style = getComputedStyle(el);
    const ground = hex(style.backgroundColor, paint);
    if (ground.alpha > 0.9) return [ground.hex, hex(style.color, paint).hex];
  }
  const root = getComputedStyle(document.body);
  return [hex(root.backgroundColor, paint).hex, hex(root.color, paint).hex];
}

/** In the Windows app, keeps the window's buttons in the colours of the page under them; elsewhere does nothing. */
export function followWindowColors(): void {
  const desktop = window.stillfailDesktop;
  if (desktop?.frame !== "overlay" || !desktop.windowColors) return;
  const paint = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  if (!paint) return;
  let told = "";
  let due = 0;
  const tell = () => {
    due = 0;
    const colors = under(paint);
    if (!colors || colors.join() === told) return;
    told = colors.join();
    desktop.windowColors?.(...colors);
  };
  // At most once a frame, and a little after the change (a theme's colours fade in over the page's transitions).
  const soon = () => {
    if (due) return;
    due = window.setTimeout(() => requestAnimationFrame(tell), 50);
  };
  new MutationObserver(soon).observe(document.documentElement, {
    attributes: true, attributeFilter: ["class", "data-theme", "data-sidebar"], childList: true, subtree: true,
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", soon);
  window.addEventListener("resize", soon);
  document.addEventListener("transitionend", soon);
  soon();
}
