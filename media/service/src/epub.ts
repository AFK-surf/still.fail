// An EPUB (2 or 3) made into a book: container.xml names the package (OPF); its metadata give the title, the author and
// the cover; its spine the chapters, one per file, in order; the table of contents (nav.xhtml, else toc.ncx) their
// titles and levels, else a chapter's first heading. Images are kept by a ref of their content.
import { createHash } from "node:crypto";
import { posix } from "node:path";
import type { Chapter, Image, Parsed } from "./blocks.ts";
import { MediaError } from "./errors.ts";
import { titleOf, toBlocks, tokens } from "./html.ts";
import { sniff } from "./images.ts";
import { type ZipEntry, ZipError, readZip, unzip } from "./zip.ts";

/// Whether `buf` is a zip that holds an EPUB.
export function isEpub(buf: Buffer): boolean {
  if (buf.length < 4 || buf.readUInt32LE(0) !== 0x04034b50) return false;
  if (buf.toString("latin1", 30, 58) === "mimetypeapplication/epub+zip") return true;
  try {
    return readZip(buf).has("META-INF/container.xml");
  } catch {
    return false;
  }
}

/// A path named in the book (`href`, relative to `from`'s folder, %-escaped, maybe with a fragment) as an entry's name.
export function resolve(from: string, href: string): string {
  let path = href.split("#")[0]!.split("?")[0]!;
  try {
    path = decodeURIComponent(path);
  } catch {}
  if (path.startsWith("/")) return posix.normalize(path).slice(1);
  return posix.normalize(posix.join(posix.dirname(from), path)).replace(/^(\.\/)+/, "");
}

type Item = { id: string; href: string; type: string; props: string[] };
type TocAt = { file: string; title: string; level: number };

const text = (src: string) => src.replace(/\s+/g, " ").trim();

/// The book in `buf` (an EPUB). `name` (its file's name) titles it when its metadata do not.
export function parseEpub(buf: Buffer, name: string): Parsed {
  let zip: Map<string, ZipEntry>;
  try {
    zip = readZip(buf);
  } catch (e) {
    throw new MediaError("bad_request", `无法读取这本 EPUB（文件损坏）：${(e as Error).message}`);
  }
  const files = new Map<string, ZipEntry>();
  for (const [k, v] of zip) files.set(k.toLowerCase(), v);
  const entry = (path: string) => zip.get(path) ?? files.get(path.toLowerCase()) ?? null;
  const read = (path: string): Buffer | null => {
    const e = entry(path);
    if (!e) return null;
    try {
      return unzip(buf, e);
    } catch (err) {
      if (err instanceof ZipError) return null;
      throw err;
    }
  };
  const readText = (path: string) => {
    const b = read(path);
    return b === null ? null : new TextDecoder("utf-8").decode(b);
  };

  const container = readText("META-INF/container.xml");
  const opfPath = container === null ? null : (tokens(container).find((t) => t.k === "open" && t.name === "rootfile" && t.attrs["full-path"]) as { attrs: Record<string, string> } | undefined)?.attrs["full-path"];
  const opf = opfPath ? readText(opfPath) : null;
  if (!opfPath || opf === null) throw new MediaError("bad_request", "这本 EPUB 缺少内容清单（OPF），无法导入");

  // The package: metadata, manifest, spine.
  let title = "";
  let authors: string[] = [];
  let coverId: string | null = null;
  let ncxId: string | null = null;
  const items = new Map<string, Item>();
  const spine: string[] = [];
  let into: "title" | "creator" | null = null;
  let got = "";
  for (const t of tokens(opf)) {
    if (t.k === "text") {
      if (into) got += t.text;
    } else if (t.k === "open") {
      if ((t.name === "title" || t.name === "creator") && !t.self) {
        into = t.name === "title" ? "title" : "creator";
        got = "";
      } else if (t.name === "meta" && t.attrs["name"] === "cover" && t.attrs["content"]) {
        coverId = t.attrs["content"];
      } else if (t.name === "item" && t.attrs["id"] && t.attrs["href"]) {
        items.set(t.attrs["id"], { id: t.attrs["id"], href: resolve(opfPath, t.attrs["href"]), type: t.attrs["media-type"] ?? "", props: (t.attrs["properties"] ?? "").split(/\s+/) });
      } else if (t.name === "spine") {
        ncxId = t.attrs["toc"] ?? null;
      } else if (t.name === "itemref" && t.attrs["idref"]) {
        spine.push(t.attrs["idref"]);
      }
    } else if (into && t.name === into) {
      if (into === "title" && !title) title = text(got);
      if (into === "creator" && text(got)) authors.push(text(got));
      into = null;
    }
  }
  authors = [...new Set(authors)];

  // Content another program encrypted (DRM): not readable here. Fonts obfuscated as EPUB allows are fine.
  const encryption = readText("META-INF/encryption.xml");
  if (encryption !== null) {
    const locked = new Set<string>();
    let method = "";
    for (const t of tokens(encryption)) {
      if (t.k !== "open") continue;
      if (t.name === "encryptionmethod") method = t.attrs["algorithm"] ?? "";
      if (t.name === "cipherreference" && t.attrs["uri"] && !/idpf\.org\/2008\/embedding|ns\.adobe\.com\/pdf\/enc#RC/.test(method)) locked.add(resolve("", t.attrs["uri"]));
    }
    if (spine.some((id) => { const it = items.get(id); return it !== undefined && locked.has(it.href); })) {
      throw new MediaError("unsupported", "这本书有 DRM 加密，无法导入");
    }
  }

  // Images, by a ref of their content (the same picture used twice is kept once).
  const images = new Map<string, Image>();
  const seen = new Map<string, { ref: string; w?: number; h?: number } | null>();
  const typeOf = new Map([...items.values()].map((it) => [it.href, it.type]));
  const imageAt = (path: string) => {
    if (seen.has(path)) return seen.get(path)!;
    const bytes = read(path);
    let found: { ref: string; w?: number; h?: number } | null = null;
    if (bytes !== null && bytes.length > 0) {
      const s = sniff(bytes, typeOf.get(path) ?? "");
      const ref = createHash("sha256").update(bytes).digest("hex").slice(0, 20);
      images.set(ref, { type: s.type, bytes });
      found = { ref, ...(s.w ? { w: s.w } : {}), ...(s.h ? { h: s.h } : {}) };
    }
    seen.set(path, found);
    return found;
  };

  // The table of contents: the first entry naming each file, with its level.
  const toc = new Map<string, TocAt>();
  const nav = [...items.values()].find((it) => it.props.includes("nav"));
  const navSrc = nav ? readText(nav.href) : null;
  if (nav && navSrc !== null) {
    const toks = tokens(navSrc);
    /// The nav that is the table of contents (`epub:type="toc"`), else the first one (not landmarks, not page lists).
    const navs = toks.filter((t) => t.k === "open" && t.name === "nav") as { attrs: Record<string, string> }[];
    const tocNav = Math.max(0, navs.findIndex((t) => /\btoc\b/.test(t.attrs["epub:type"] ?? "")));
    let navAt = -1;
    let navDepth = 0;
    let depth = 0;
    let link: { href: string; title: string } | null = null;
    for (const t of toks) {
      if (t.k === "open" && t.name === "nav") {
        if (navDepth++ === 0) navAt++;
        continue;
      }
      if (t.k === "close" && t.name === "nav") {
        navDepth = Math.max(0, navDepth - 1);
        continue;
      }
      if (navDepth === 0 || navAt !== tocNav) continue;
      if (t.k === "open" && t.name === "ol" && !t.self) depth++;
      else if (t.k === "close" && t.name === "ol") depth--;
      else if (t.k === "open" && t.name === "a" && t.attrs["href"]) link = { href: t.attrs["href"], title: "" };
      else if (t.k === "text" && link) link.title += t.text;
      else if (t.k === "close" && t.name === "a" && link) {
        const file = resolve(nav.href, link.href);
        if (!toc.has(file) && text(link.title)) toc.set(file, { file, title: text(link.title), level: Math.max(1, depth) });
        link = null;
      }
    }
  }
  const ncx = ncxId ? items.get(ncxId) : [...items.values()].find((it) => it.type === "application/x-dtbncx+xml");
  const ncxSrc = toc.size === 0 && ncx ? readText(ncx.href) : null;
  if (ncx && ncxSrc !== null) {
    const points: { title: string; src: string | null }[] = [];
    let label = false;
    for (const t of tokens(ncxSrc)) {
      if (t.k === "open" && t.name === "navpoint" && !t.self) points.push({ title: "", src: null });
      else if (t.k === "close" && t.name === "navpoint") points.pop();
      else if (t.k === "open" && t.name === "text" && !t.self) label = true;
      else if (t.k === "close" && t.name === "text") label = false;
      else if (t.k === "text" && label && points.length > 0) points[points.length - 1]!.title += t.text;
      else if (t.k === "open" && t.name === "content" && t.attrs["src"] && points.length > 0) {
        const file = resolve(ncx.href, t.attrs["src"]);
        const title = text(points[points.length - 1]!.title);
        if (!toc.has(file) && title) toc.set(file, { file, title, level: points.length });
      }
    }
  }

  // The chapters: the spine's files that have something in them.
  const chapters: Chapter[] = [];
  for (const id of spine) {
    const it = items.get(id);
    if (!it || !/x?html|xml/.test(it.type || "html")) continue;
    const src = readText(it.href);
    if (src === null) continue;
    const blocks = toBlocks(src, (s) => (s.startsWith("data:") ? null : imageAt(resolve(it.href, s))));
    if (blocks.length === 0) continue;
    const at = toc.get(it.href);
    const fallback = chapters.length === 0 && blocks.every((b) => b.t === "img") ? "封面" : `第 ${chapters.length + 1} 部分`;
    chapters.push({ title: at?.title ?? titleOf(blocks) ?? fallback, level: at?.level ?? 1, blocks });
  }
  if (chapters.length === 0) throw new MediaError("bad_request", "这本 EPUB 里没有读到正文");

  // The cover: EPUB 3's `cover-image`, else EPUB 2's <meta name="cover">.
  const coverItem = [...items.values()].find((it) => it.props.includes("cover-image")) ?? (coverId ? items.get(coverId) : undefined);
  const cover = coverItem && coverItem.type.startsWith("image/") ? (imageAt(coverItem.href)?.ref ?? null) : null;

  return { title: title || name.replace(/\.[^.]+$/, ""), author: authors.join("、"), format: "epub", cover, chapters, images };
}
