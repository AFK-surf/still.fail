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

/** The painted stack, including the page behind a modal. Radix disables its pointer events, not its paint. */
function layers(): Element[] {
  const body = document.body;
  const pointer = body.style.getPropertyValue("pointer-events");
  const priority = body.style.getPropertyPriority("pointer-events");
  try {
    body.style.setProperty("pointer-events", "auto", "important");
    return document.elementsFromPoint(document.documentElement.clientWidth - 70, 22);
  } finally {
    // Restored synchronously before any input can run; the modal still blocks interaction with the page.
    if (pointer) body.style.setProperty("pointer-events", pointer, priority);
    else body.style.removeProperty("pointer-events");
  }
}

/** Composite translucent grounds (a dialog's shade too) over the first opaque one, in paint order. */
function under(paint: CanvasRenderingContext2D, elements: Element[]): [string, string] {
  const grounds: { color: string; opacity: number }[] = [];
  let foreground = getComputedStyle(document.body).color;
  for (const el of elements) {
    const style = getComputedStyle(el);
    const opacity = Number(style.opacity);
    const ground = hex(style.backgroundColor, paint);
    grounds.push({ color: style.backgroundColor, opacity });
    if (ground.alpha === 1 && opacity === 1) {
      foreground = style.color;
      break;
    }
  }
  const symbol = hex(foreground, paint).hex;
  paint.clearRect(0, 0, 1, 1);
  paint.fillStyle = "#ffffff";
  paint.fillRect(0, 0, 1, 1);
  for (const ground of grounds.reverse()) {
    paint.globalAlpha = ground.opacity;
    paint.fillStyle = ground.color;
    paint.fillRect(0, 0, 1, 1);
  }
  paint.globalAlpha = 1;
  const rgb = paint.getImageData(0, 0, 1, 1).data.slice(0, 3);
  return [`#${Array.from(rgb, (n) => n.toString(16).padStart(2, "0")).join("")}`, symbol];
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
    const elements = layers();
    const colors = under(paint, elements);
    if (colors.join() !== told) {
      told = colors.join();
      desktop.windowColors?.(...colors);
    }
    // Only follow motion under the controls, not every animation elsewhere in the app.
    if (elements.some((el) => el.getAnimations().some((animation) => animation.playState === "running"))) soon();
  };
  // At most once a frame, including the shade's fade and the theme's colour transitions.
  const soon = () => {
    if (due) return;
    due = requestAnimationFrame(tell);
  };
  new MutationObserver(soon).observe(document.documentElement, {
    attributes: true, attributeFilter: ["class", "data-theme", "data-sidebar", "data-state"], childList: true, subtree: true,
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", soon);
  window.addEventListener("resize", soon);
  document.addEventListener("transitionend", soon);
  document.addEventListener("transitionrun", soon);
  document.addEventListener("animationstart", soon);
  document.addEventListener("animationend", soon);
  soon();
}
