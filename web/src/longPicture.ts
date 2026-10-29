// A long picture of what an element shows, however long it is (a chat shared as a picture: Publish.tsx; a table:
// Prose.tsx), on its ground, as far round it as said. The element
// is copied once as modern-screenshot copies it (an SVG's foreignObject, its styles, fonts and pictures put in it), then
// drawn a band at a time into a canvas no taller than a band, and each band's rows written into a PNG as they come
// (each row less the one above it, deflated by the browser's CompressionStream). So no canvas of it all is ever made:
// a long chat's would be past what a browser draws one into (Safari's hold 16 million pixels at most).
import { domToForeignObjectSvg } from "modern-screenshot";

/** How many rows of pixels are drawn at a time. */
const BAND = 2048;

export type LongPicture = {
  /** Its pixels to a CSS pixel. */
  scale: number;
  /** What it is drawn on (the page's ground). */
  background: string;
  /** How far round the element the ground reaches, in CSS pixels (none: its edges are the picture's). */
  margin?: number;
  /** Whether a node of the element is in it (one left out, all it holds too). */
  keep?: (node: Node) => boolean;
  /** Each node of the copy as it is made, changed for the picture where it says (a time said as a date). */
  copied?: (node: Node) => void;
  /** How much of its start (its left padding) is the page's, not the picture's (room for what only the page shows): left
   * out of the picture, what it holds laid out as wide as on the page. */
  start?: number;
};

/** What element `el` shows, all of it, as a PNG. */
export async function longPicture(el: HTMLElement, o: LongPicture): Promise<Blob> {
  const start = o.start ?? 0;
  const width = Math.ceil(el.offsetWidth - start);
  const height = Math.ceil(el.offsetHeight);
  const m = o.margin ?? 0;
  // (its ground the canvas's, filled under each band: the element keeps its own, a table's frame its tint)
  const svg = await domToForeignObjectSvg(el, {
    width, height, timeout: 15000,
    ...(start ? { style: { paddingLeft: `${parseFloat(getComputedStyle(el).paddingLeft) - start}px` } } : {}),
    ...(o.keep ? { filter: o.keep } : {}),
    ...(o.copied ? { onCloneEachNode: o.copied } : {}),
  });
  // (what it holds as large as it is, whatever part of it the SVG is made to show)
  const held = svg.querySelector("foreignObject");
  held?.setAttribute("width", String(width));
  held?.setAttribute("height", String(height));
  held?.setAttribute("x", String(m));
  held?.setAttribute("y", String(m));
  const pw = Math.round((width + 2 * m) * o.scale);
  const ph = Math.round((height + 2 * m) * o.scale);
  const png = pngRows(pw, ph);
  const canvas = document.createElement("canvas");
  canvas.width = pw;
  const g = canvas.getContext("2d", { willReadFrequently: true });
  if (!g) throw new Error("no canvas");
  for (let top = 0; top < ph; top += BAND) {
    const rows = Math.min(BAND, ph - top);
    canvas.height = rows;
    svg.setAttribute("viewBox", `0 ${top / o.scale} ${width + 2 * m} ${rows / o.scale}`);
    svg.setAttribute("width", String(width + 2 * m));
    svg.setAttribute("height", String(rows / o.scale));
    const image = await loaded(`data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(svg))}`);
    // (twice: Safari draws the pictures in a foreignObject once it has decoded them, as modern-screenshot does)
    for (let i = 0; i < 2; i++) {
      g.fillStyle = o.background;
      g.fillRect(0, 0, pw, rows);
      g.drawImage(image, 0, 0, pw, rows);
      if (i === 0) await new Promise((done) => setTimeout(done, 16));
    }
    await png.add(g.getImageData(0, 0, pw, rows).data, rows);
  }
  return png.end();
}

/** The picture at `src`, decoded. */
function loaded(src: string): Promise<HTMLImageElement> {
  return new Promise((done, fail) => {
    const image = new Image();
    image.decoding = "sync";
    image.onload = () => done(image);
    image.onerror = () => fail(new Error("the picture did not draw"));
    image.src = src;
  });
}

/** The CRC-32 of each byte (PNG's). */
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

/** A PNG chunk: its length, its kind, what it holds, the CRC of the last two. */
function chunk(kind: string, data: Uint8Array): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(12 + data.length);
  const view = new DataView(out.buffer);
  view.setUint32(0, data.length);
  for (let i = 0; i < 4; i++) out[4 + i] = kind.charCodeAt(i);
  out.set(data, 8);
  let c = 0xffffffff;
  for (let i = 4; i < 8 + data.length; i++) c = CRC[(c ^ out[i]!) & 0xff]! ^ (c >>> 8);
  view.setUint32(8 + data.length, (c ^ 0xffffffff) >>> 0);
  return out;
}

/** A PNG of `w` × `h` pixels (RGB: what is drawn is opaque), its rows added from the top, deflated as they come. */
function pngRows(w: number, h: number) {
  const z = new CompressionStream("deflate");
  const writer = z.writable.getWriter();
  const parts: Uint8Array[] = [];
  const read = (async () => {
    const reader = z.readable.getReader();
    for (;;) {
      const { value, done } = await reader.read();
      if (done) return;
      parts.push(value);
    }
  })();
  const n = w * 3;
  let prev = new Uint8Array(n);
  return {
    /** `rows` rows more of `rgba` (as wide as it is, 4 bytes a pixel): each filtered by the one above it (PNG's Up). */
    async add(rgba: Uint8ClampedArray, rows: number): Promise<void> {
      const out = new Uint8Array(rows * (n + 1));
      for (let y = 0; y < rows; y++) {
        const cur = new Uint8Array(n);
        for (let x = 0; x < w; x++) {
          cur[3 * x] = rgba[(y * w + x) * 4]!;
          cur[3 * x + 1] = rgba[(y * w + x) * 4 + 1]!;
          cur[3 * x + 2] = rgba[(y * w + x) * 4 + 2]!;
        }
        const at = y * (n + 1);
        out[at] = 2;
        for (let i = 0; i < n; i++) out[at + 1 + i] = (cur[i]! - prev[i]!) & 0xff;
        prev = cur;
      }
      await writer.write(out);
    },
    /** The PNG. */
    async end(): Promise<Blob> {
      await writer.close();
      await read;
      const head = new Uint8Array(13);
      const view = new DataView(head.buffer);
      view.setUint32(0, w);
      view.setUint32(4, h);
      // 8 bits, RGB, deflated, filtered by row, not interlaced
      head.set([8, 2, 0, 0, 0], 8);
      let size = 0;
      for (const p of parts) size += p.length;
      const idat = new Uint8Array(size);
      let at = 0;
      for (const p of parts) {
        idat.set(p, at);
        at += p.length;
      }
      const sign = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      return new Blob([sign, chunk("IHDR", head), chunk("IDAT", idat), chunk("IEND", new Uint8Array(0))], { type: "image/png" });
    },
  };
}
