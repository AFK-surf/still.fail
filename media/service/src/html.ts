// (X)HTML as an EPUB has it, read tolerantly (no parser of its own: tags, text, entities), and a chapter's file made
// into blocks (blocks.ts): paragraphs with their bold, italic, links and ruby; headings; images; rules.
import type { Block, Run } from "./blocks.ts";

export type Token =
  | { k: "text"; text: string }
  | { k: "open"; name: string; attrs: Record<string, string>; self: boolean }
  | { k: "close"; name: string };

const NAMED: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ensp: " ", emsp: " ", thinsp: " ",
  zwnj: "‌", zwj: "‍", shy: "­", hellip: "…", mdash: "—", ndash: "–", lsquo: "‘", rsquo: "’",
  ldquo: "“", rdquo: "”", sbquo: "‚", bdquo: "„", laquo: "«", raquo: "»", lsaquo: "‹", rsaquo: "›", middot: "·",
  bull: "•", copy: "©", reg: "®", trade: "™", times: "×", divide: "÷", deg: "°", plusmn: "±", sect: "§", para: "¶",
  dagger: "†", Dagger: "‡", prime: "′", Prime: "″", iexcl: "¡", iquest: "¿", cent: "¢", pound: "£", yen: "¥",
  euro: "€", larr: "←", rarr: "→", uarr: "↑", darr: "↓", hearts: "♥", star: "☆", eacute: "é", egrave: "è",
  agrave: "à", aacute: "á", ccedil: "ç", ouml: "ö", uuml: "ü", auml: "ä", szlig: "ß", ntilde: "ñ", oacute: "ó",
  iacute: "í", uacute: "ú", ecirc: "ê", acirc: "â", ocirc: "ô", icirc: "î", ucirc: "û", aring: "å", oslash: "ø",
  aelig: "æ", oelig: "œ",
};

/// Text with its character references made characters; one not known is left as it is.
export function decode(s: string): string {
  if (!s.includes("&")) return s;
  return s.replace(/&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,31});/g, (whole, ref: string) => {
    if (ref[0] === "#") {
      const n = ref[1] === "x" || ref[1] === "X" ? parseInt(ref.slice(2), 16) : parseInt(ref.slice(1), 10);
      return n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : "�";
    }
    return NAMED[ref] ?? whole;
  });
}

/// A name without its namespace prefix, in lower case (`dc:title` → `title`, `svg:image` → `image`).
const local = (name: string) => name.slice(name.indexOf(":") + 1).toLowerCase();

const RAW = new Set(["script", "style"]);

/// The tokens of `src`: comments, doctype and processing instructions dropped, CDATA as text, script and style skipped
/// whole. Tag names lower case without prefix; attribute names lower case as written (`xlink:href`, `epub:type`).
export function tokens(src: string): Token[] {
  const out: Token[] = [];
  const n = src.length;
  let i = 0;
  while (i < n) {
    const lt = src.indexOf("<", i);
    if (lt < 0) {
      out.push({ k: "text", text: decode(src.slice(i)) });
      break;
    }
    if (lt > i) out.push({ k: "text", text: decode(src.slice(i, lt)) });
    if (src.startsWith("<!--", lt)) {
      const e = src.indexOf("-->", lt + 4);
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (src.startsWith("<![CDATA[", lt)) {
      const e = src.indexOf("]]>", lt + 9);
      out.push({ k: "text", text: src.slice(lt + 9, e < 0 ? n : e) });
      i = e < 0 ? n : e + 3;
      continue;
    }
    const c = src[lt + 1] ?? "";
    if (c === "!" || c === "?") {
      const e = src.indexOf(">", lt);
      i = e < 0 ? n : e + 1;
      continue;
    }
    if (c === "/") {
      const e = src.indexOf(">", lt);
      out.push({ k: "close", name: local(src.slice(lt + 2, e < 0 ? n : e).trim()) });
      i = e < 0 ? n : e + 1;
      continue;
    }
    if (!/[A-Za-z]/.test(c)) {
      out.push({ k: "text", text: "<" });
      i = lt + 1;
      continue;
    }
    let j = lt + 1;
    while (j < n && !/[\s/>]/.test(src[j]!)) j++;
    const name = local(src.slice(lt + 1, j));
    const attrs: Record<string, string> = {};
    let self = false;
    while (j < n) {
      while (j < n && /\s/.test(src[j]!)) j++;
      if (src[j] === ">") {
        j++;
        break;
      }
      if (src[j] === "/") {
        j++;
        if (src[j] === ">") {
          self = true;
          j++;
          break;
        }
        continue;
      }
      const a = j;
      while (j < n && !/[\s=/>]/.test(src[j]!)) j++;
      const key = src.slice(a, j).toLowerCase();
      while (j < n && /\s/.test(src[j]!)) j++;
      let value = "";
      if (src[j] === "=") {
        j++;
        while (j < n && /\s/.test(src[j]!)) j++;
        const q = src[j];
        if (q === '"' || q === "'") {
          const e = src.indexOf(q, j + 1);
          value = src.slice(j + 1, e < 0 ? n : e);
          j = e < 0 ? n : e + 1;
        } else {
          const v = j;
          while (j < n && !/[\s>]/.test(src[j]!)) j++;
          value = src.slice(v, j);
        }
      }
      if (key && !(key in attrs)) attrs[key] = decode(value);
      if (a === j) j++;
    }
    out.push({ k: "open", name, attrs, self });
    i = j;
    if (RAW.has(name) && !self) {
      const e = src.toLowerCase().indexOf(`</${name}`, i);
      const gt = e < 0 ? -1 : src.indexOf(">", e);
      i = gt < 0 ? n : gt + 1;
      out.push({ k: "close", name });
    }
  }
  return out;
}

/// Elements that end the paragraph before them and start a new one after.
const BLOCK = new Set([
  "p", "div", "li", "ul", "ol", "blockquote", "section", "article", "body", "header", "footer", "aside", "nav", "main",
  "figure", "figcaption", "table", "tr", "td", "th", "thead", "tbody", "tfoot", "caption", "dl", "dt", "dd", "pre",
  "center", "address", "hgroup", "details", "summary",
]);
/// Elements whose content is not text of the chapter.
const SKIP = new Set(["head", "script", "style", "rp", "noscript", "template", "math"]);

const WS = /[ \t\n\r\f]+/g;
/// A line break between two CJK characters (or full-width marks) is no space (CSS Text's segment break rule).
const CJK = "\u2e80-\u9fff\uf900-\ufaff\uff00-\uffef";
const CJK_BREAK = new RegExp(`([${CJK}])[ \\t\\r\\f]*\\n[ \\t\\n\\r\\f]*(?=[${CJK}])`, "g");

/// A paragraph's runs as they are shown: white space collapsed as HTML does (one space, none at the ends), a full-width
/// indent dropped, runs of the same style joined, empty ones gone.
export function finish(raw: Run[]): Run[] {
  const out: Run[] = [];
  for (const r of raw) {
    let text = r.text.replace(CJK_BREAK, "$1").replace(WS, " ");
    const last = out.length > 0 ? out[out.length - 1]!.text : "";
    if (text.startsWith(" ") && (out.length === 0 || last.endsWith(" "))) text = text.slice(1);
    if (out.length === 0) text = text.replace(/^[　  ]+/, "");
    if (!text) continue;
    out.push({ ...r, text });
  }
  while (out.length > 0) {
    const r = out[out.length - 1]!;
    r.text = r.text.replace(/ +$/, "");
    if (r.text) break;
    out.pop();
  }
  const joined: Run[] = [];
  for (const r of out) {
    const prev = joined[joined.length - 1];
    if (prev && prev.ruby === undefined && r.ruby === undefined && prev.b === r.b && prev.i === r.i && prev.href === r.href) prev.text += r.text;
    else joined.push(r);
  }
  return joined;
}

const plain = (r: Run) => r.b === undefined && r.i === undefined && r.href === undefined && r.ruby === undefined;

/// An image the chapter shows, by its `src` as written there: its ref and size, or null when the book does not have it.
export type ImageOf = (src: string) => { ref: string; w?: number; h?: number } | null;

/// A chapter's (X)HTML as blocks; `image` resolves an image's source.
export function toBlocks(src: string, image: ImageOf): Block[] {
  const blocks: Block[] = [];
  let runs: Run[] = [];
  let heading = 0;
  let bold = 0;
  let italic = 0;
  const links: (string | null)[] = [];
  let skip: string | null = null;
  let skipDepth = 0;
  let svg = 0;
  let ruby = 0;
  let rt = false;
  let base = "";
  let reading = "";

  const style = (): Omit<Run, "text"> => {
    const s: Omit<Run, "text"> = {};
    if (bold > 0) s.b = true;
    if (italic > 0) s.i = true;
    const href = links.findLast((h) => h !== null);
    if (href) s.href = href;
    return s;
  };
  const flush = () => {
    const done = finish(runs);
    runs = [];
    if (done.length === 0) return;
    if (heading > 0) blocks.push({ t: "h", level: heading, text: done.map((r) => r.text).join("") });
    else if (done.every(plain)) blocks.push({ t: "p", text: done.map((r) => r.text).join("") });
    else blocks.push({ t: "p", runs: done });
  };
  const endRuby = () => {
    if (base) runs.push({ text: base, ...style(), ...(reading.trim() ? { ruby: reading.replace(WS, " ").trim() } : {}) });
    base = "";
    reading = "";
  };
  const picture = (src: string | undefined) => {
    if (!src) return;
    const found = image(src);
    if (!found) return;
    flush();
    blocks.push({ t: "img", ref: found.ref, ...(found.w ? { w: found.w } : {}), ...(found.h ? { h: found.h } : {}) });
  };

  for (const tok of tokens(src)) {
    if (skip !== null) {
      if (tok.k === "open" && tok.name === skip && !tok.self) skipDepth++;
      else if (tok.k === "close" && tok.name === skip && --skipDepth === 0) skip = null;
      continue;
    }
    if (tok.k === "text") {
      if (svg > 0) continue;
      if (ruby > 0) {
        if (rt) reading += tok.text;
        else base += tok.text;
      } else runs.push({ text: tok.text, ...style() });
      continue;
    }
    const name = tok.name;
    if (tok.k === "open") {
      if (SKIP.has(name)) {
        if (!tok.self) {
          skip = name;
          skipDepth = 1;
        }
      } else if (name === "svg") {
        if (!tok.self) svg++;
      } else if (name === "image" && svg > 0) {
        picture(tok.attrs["xlink:href"] ?? tok.attrs["href"]);
      } else if (name === "img") {
        picture(tok.attrs["src"]);
      } else if (svg > 0) {
        continue;
      } else if (/^h[1-6]$/.test(name)) {
        flush();
        heading = Number(name[1]);
      } else if (name === "hr") {
        flush();
        blocks.push({ t: "hr" });
      } else if (name === "br") {
        if (ruby > 0) continue;
        flush();
      } else if (BLOCK.has(name)) {
        if (!tok.self) flush();
      } else if (tok.self) {
        continue;
      } else if (name === "b" || name === "strong") {
        bold++;
      } else if (name === "i" || name === "em" || name === "cite" || name === "var" || name === "dfn") {
        italic++;
      } else if (name === "a") {
        links.push(tok.attrs["href"] || null);
      } else if (name === "ruby") {
        if (ruby++ === 0) {
          base = "";
          reading = "";
          rt = false;
        }
      } else if (name === "rt") {
        if (ruby > 0) rt = true;
      }
      continue;
    }
    // A close.
    if (name === "svg") {
      if (svg > 0) svg--;
    } else if (svg > 0) {
      continue;
    } else if (/^h[1-6]$/.test(name)) {
      flush();
      heading = 0;
    } else if (BLOCK.has(name)) {
      flush();
    } else if (name === "b" || name === "strong") {
      if (bold > 0) bold--;
    } else if (name === "i" || name === "em" || name === "cite" || name === "var" || name === "dfn") {
      if (italic > 0) italic--;
    } else if (name === "a") {
      links.pop();
    } else if (name === "rt") {
      if (ruby > 0 && rt) {
        rt = false;
        endRuby();
      }
    } else if (name === "ruby") {
      if (ruby > 0 && --ruby === 0) {
        rt = false;
        endRuby();
      }
    }
  }
  if (ruby > 0) endRuby();
  flush();
  return blocks;
}

/// The text of the first heading of `blocks`, else the start of its first paragraph.
export function titleOf(blocks: Block[]): string | null {
  const h = blocks.find((b) => b.t === "h");
  if (h) return h.text;
  const p = blocks.find((b) => b.t === "p");
  if (!p) return null;
  const text = "text" in p ? p.text : p.runs.map((r) => r.text).join("");
  return text.length > 24 ? `${text.slice(0, 24)}…` : text;
}
