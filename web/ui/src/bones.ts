// A page's bones (a skeleton), measured off what it will show (waiting.tsx Bones; mbui's Ctx::bones draws the same):
// what is drawn inside them, the page's own parts on made-up data, keeps its grounds and edges and none of its ink, and
// over it go the bones: each line of its words a bar as long as the line, in its middle, BONE_SHARE of its size high,
// round; each picture, icon or drawing a shape where it is (a dot at an icon's size, else its box a little round); a
// ground that says something by its colour (an accent, a state's tint, someone's colour) in the bones' colour too; and
// what says it is one piece (a button with a ground of its own, a switch, a pill: `data-bone-whole`) a shape of its
// own box in its own corners, nothing in it drawn.

/** How high a line's bar is, of its words' size: about as high as a line of them is inked. */
export const BONE_SHARE = 0.8;

/** A picture or an icon no bigger than this either way is a dot. */
const ICON_MOST = 24;

/** The corner of a picture's or a drawing's shape. */
const DRAWING_R = 8;

/** A ground this saturated (HSL), or this far off the page (WCAG contrast), says something by its colour. */
const GREY_MOST = 0.3;
const OFF_PAGE_MOST = 1.5;

/** One of the bones: where it stands in the bones' box, its corner (CSS border-radius). */
export interface Bone { x: number; y: number; w: number; h: number; r: string }

interface Box { left: number; top: number; right: number; bottom: number }

/** What cuts what is in it short (its overflow hidden), with its corners' radii (top left, top right, bottom right, bottom left). */
interface Clip extends Box { corners?: readonly [number, number, number, number] }

type Rgba = [number, number, number, number];

/** Colours as the screen shows them, by how a style says them. */
const colours = new Map<string, Rgba | null>();
let paint: CanvasRenderingContext2D | null | undefined;

/**
 * A colour a style says, in whatever way it says it (rgb(), oklch(), color-mix(): the palette's are oklch), as the screen
 * shows it: painted on a pixel and read back.
 */
function rgba(css: string): Rgba | null {
  const known = colours.get(css);
  if (known !== undefined) return known;
  if (paint === undefined) {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    paint = canvas.getContext("2d", { willReadFrequently: true });
  }
  if (!paint) return null;
  paint.clearRect(0, 0, 1, 1);
  // (one it cannot read leaves the transparent before it)
  paint.fillStyle = "rgb(0 0 0 / 0)";
  paint.fillStyle = css;
  paint.fillRect(0, 0, 1, 1);
  const [r, g, b, a] = paint.getImageData(0, 0, 1, 1).data;
  const c: Rgba | null = a ? [r!, g!, b!, a / 255] : null;
  colours.set(css, c);
  return c;
}

function luminance([r, g, b]: Rgba): number {
  const c = (v: number) => { const s = v / 255; return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b);
}

function saturation([r, g, b]: Rgba): number {
  const hi = Math.max(r, g, b) / 255, lo = Math.min(r, g, b) / 255, l = (hi + lo) / 2;
  return hi === lo ? 0 : (hi - lo) / (1 - Math.abs(2 * l - 1));
}

/** The ground the bones lie on: the first one drawn round them. */
function pageOf(el: Element): Rgba {
  for (let a: Element | null = el; a; a = a.parentElement) {
    const c = rgba(getComputedStyle(a).backgroundColor);
    if (c && c[3] > 0.5) return c;
  }
  return [255, 255, 255, 1];
}

/** Whether a ground of `css` says something by its colour on `page` (not a card's, a bubble's, a field's grey). */
function coloured(css: string, page: Rgba): boolean {
  const c = rgba(css);
  if (!c || c[3] === 0) return false;
  const a = c[3];
  const laid: Rgba = [c[0] * a + page[0] * (1 - a), c[1] * a + page[1] * (1 - a), c[2] * a + page[2] * (1 - a), 1];
  const [hi, lo] = [luminance(laid), luminance(page)].sort((x, y) => y - x) as [number, number];
  return saturation(laid) > GREY_MOST || (hi + 0.05) / (lo + 0.05) > OFF_PAGE_MOST;
}

const drawn = (css: string): boolean => { const c = rgba(css); return !!c && c[3] > 0; };

/** A control is no taller than this: a row that is pressed whole (a ground of its own, words in it) is not one. */
const CONTROL_MOST = 48;

/** Whether `el` (drawn `r`) is drawn as one piece: one marked so, a switch, a button with a ground of its own. */
function whole(el: Element, cs: CSSStyleDeclaration, r: DOMRect): boolean {
  if (el.hasAttribute("data-bone-whole") || el.getAttribute("role") === "switch") return true;
  return el.matches("button, [role=button]") && r.height <= CONTROL_MOST && (drawn(cs.backgroundColor) || el.hasAttribute("data-bone-ground"));
}

const PICTURE = /^(IMG|SVG|VIDEO|CANVAS|PICTURE)$/i;

/**
 * The bones of what `body` holds, where they stand in `box`. Grounds that say something by their colour, and what is
 * drawn whole, are marked (`data-bone-ground`, `data-bone-whole`) so that they draw nothing of their own under the
 * bones (waiting.css.ts), and are known again when measured again.
 */
export function bonesOf(box: HTMLElement, body: HTMLElement): Bone[] {
  const at = box.getBoundingClientRect();
  const page = pageOf(box);
  const out: Bone[] = [];
  const put = (r: Box, corner: string) => {
    if (r.right - r.left < 0.5 || r.bottom - r.top < 0.5) return;
    out.push({ x: r.left - at.left, y: r.top - at.top, w: r.right - r.left, h: r.bottom - r.top, r: corner });
  };
  const cut = (r: Box, clip: Box): Box => ({ left: Math.max(r.left, clip.left), top: Math.max(r.top, clip.top), right: Math.min(r.right, clip.right), bottom: Math.min(r.bottom, clip.bottom) });
  const cornerOf = (cs: CSSStyleDeclaration, r: Box, otherwise: string): string =>
    parseFloat(cs.borderTopLeftRadius) > 0 || parseFloat(cs.borderTopRightRadius) > 0 ? `${cs.borderTopLeftRadius} ${cs.borderTopRightRadius} ${cs.borderBottomRightRadius} ${cs.borderBottomLeftRadius}` : otherwise || `${Math.min(r.right - r.left, r.bottom - r.top) / 2}px`;
  const words = (t: Text, cs: CSSStyleDeclaration, clip: Box) => {
    const s = t.data;
    let a = 0, b = s.length;
    while (a < b && /\s/.test(s[a]!)) a++;
    while (b > a && /\s/.test(s[b - 1]!)) b--;
    if (a >= b) return;
    const range = document.createRange();
    range.setStart(t, a);
    range.setEnd(t, b);
    const h = Math.round(parseFloat(cs.fontSize) * BONE_SHARE);
    // One bar a line: a line can come in pieces, or twice over (one cut short with "…": its shown part, and the whole
    // of it), and bars laid over one another are darker where they meet.
    const lines: { left: number; right: number; mid: number }[] = [];
    for (const r of range.getClientRects()) {
      const mid = r.top + r.height / 2;
      if (r.width < 0.5 || mid < clip.top || mid > clip.bottom) continue;
      const same = lines.find((l) => Math.abs(l.mid - mid) < h / 2);
      if (same) { same.left = Math.min(same.left, r.left); same.right = Math.max(same.right, r.right); }
      else lines.push({ left: r.left, right: r.right, mid });
    }
    for (const l of lines) put(cut({ left: l.left, right: l.right, top: l.mid - h / 2, bottom: l.mid + h / 2 }, { ...clip, top: -Infinity, bottom: Infinity }), "999px");
  };
  // A square ground's corners where it meets those of what cuts it short, rounded (a meter's fill in its pill): theirs.
  const clipped = (b: Box, clip: Clip): string => {
    const c = clip.corners;
    if (!c) return "0px";
    const on = (a: number, z: number) => Math.abs(a - z) < 0.5;
    const tl = on(b.left, clip.left) && on(b.top, clip.top) ? c[0] : 0;
    const tr = on(b.right, clip.right) && on(b.top, clip.top) ? c[1] : 0;
    const br = on(b.right, clip.right) && on(b.bottom, clip.bottom) ? c[2] : 0;
    const bl = on(b.left, clip.left) && on(b.bottom, clip.bottom) ? c[3] : 0;
    return `${tl}px ${tr}px ${br}px ${bl}px`;
  };
  const walk = (el: Element, clip: Clip) => {
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || cs.opacity === "0") return;
    const r = el.getBoundingClientRect();
    const shown = cut(r, clip);
    if (PICTURE.test(el.tagName)) {
      if (r.width <= ICON_MOST && r.height <= ICON_MOST) {
        const d = Math.min(r.width, r.height), cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
        put(cut({ left: cx - d / 2, right: cx + d / 2, top: cy - d / 2, bottom: cy + d / 2 }, clip), "50%");
      } else put(shown, cornerOf(cs, r, `${DRAWING_R}px`));
      return;
    }
    if (whole(el, cs, r)) {
      el.setAttribute("data-bone-whole", "");
      put(shown, cornerOf(cs, r, ""));
      return;
    }
    if (el.hasAttribute("data-bone-ground") || coloured(cs.backgroundColor, page)) {
      el.setAttribute("data-bone-ground", "");
      put(shown, cornerOf(cs, r, clipped(shown, clip)));
    }
    const inner: Clip = cs.overflowX !== "visible" || cs.overflowY !== "visible"
      ? { ...shown, corners: [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map((x) => parseFloat(x) || 0) as [number, number, number, number] }
      : clip;
    for (const n of el.childNodes) {
      if (n.nodeType === Node.TEXT_NODE) words(n as Text, cs, inner);
      else if (n.nodeType === Node.ELEMENT_NODE) walk(n as Element, inner);
    }
  };
  const all: Clip = { left: -Infinity, top: -Infinity, right: Infinity, bottom: Infinity };
  walk(body, all);
  return out;
}
