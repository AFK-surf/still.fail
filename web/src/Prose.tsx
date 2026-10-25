// Markdown as still.fail shows it, drawn from the core's tree of it (`Md`, client/core-ts/src/markdown.ts), never
// parsed here: an agent's message comes with its tree (the chat's `md`, read in the core's worker); other words (a
// file, a memory) are read by the core's own reader, here, kept by their text. Code blocks in the colours the core
// says (`ink`, client/core-ts/src/highlight.ts: vitesse light and dark, as every client paints them), with their
// language named and a copy button.
import { Check, Copy } from "@stillfail/ui/icons.tsx";
import { Fragment, isValidElement, lazy, memo, Suspense, useEffect, useMemo, useRef, useState, type ComponentProps, type ComponentType, type CSSProperties, type ReactNode } from "react";
import type { Attachment } from "./core/shapes.ts";
import type { Md, MdNode } from "./core/md.ts";
import { inlineFile, inlineFiles } from "./Prose.css.ts";
import * as css from "./Prose.css.ts";
import { RefChip } from "./ChatRef.tsx";
import { adbOfLink, isChatLink, screenOfLink } from "./chatRefs.ts";
import { ScreenCard, ScreenName } from "./screen/ScreenLink.tsx";
import { AdbCard, AdbName } from "./AdbLink.tsx";
import { bareLinks } from "./bareLinks.ts";
import { nameOf } from "../../client/core-ts/src/placed.ts";
import { codeChunks } from "./codeChunks.ts";
import { runsOf } from "../../client/core-ts/src/highlight.ts";
import type { MathDrawing } from "../../client/core-ts/src/mathDrawing.ts";
import { core } from "./core/react.ts";
import { isWords, wordsOf } from "../../client/core-ts/src/mdWords.ts";
import { FileRef, LinkHover, pathIn } from "./Peeks.tsx";
import { Tip } from "./ui.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { Mermaid } from "./Viz.tsx";
import { t } from "./i18n.ts";

// Only a math-containing view loads the shared alphabet. This chunk draws the core's layout; it has no TeX parser.
const MathView = lazy<ComponentType<{ text: string; drawing?: MathDrawing | null | undefined }>>(() => import("./Math.tsx").then((m) => ({ default: m.Formula })).catch(() => ({ default: ({ text }: { text: string }) => <code>{text}</code> })));
function Formula(props: { text: string; drawing?: MathDrawing | null | undefined }) {
  if (!props.drawing) return <code>{props.text}</code>;
  return <Suspense fallback={<code>{props.text}</code>}><MathView {...props} /></Suspense>;
}

/** A block of code as markdown shows one: in the colours the core says of its language (`ink`: the core's tree's own, or
 * read by the core's highlighter here), with a copy button. */
export function Code({ text, language, ink }: { text: string; language?: string | undefined; ink?: string | null | undefined }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const [read, setRead] = useState<{ text: string; language: string; ink: string | null }>();
  useEffect(() => {
    if (ink !== undefined || !language) return;
    let active = true;
    void core().call("code.ink", { code: text, lang: language.toLowerCase() }).then((value) => {
      if (active) setRead({ text, language, ink: (value as { ink: string | null }).ink });
    }).catch(() => undefined);
    return () => { active = false; };
  }, [ink, text, language]);
  const colours = ink !== undefined ? ink : read?.text === text && read.language === language ? read.ink : null;
  const coloured = useMemo(() => colours && text.length <= 16000
    ? runsOf(text, colours).map(([words, scope], i) => <span key={i} className={css.ink[scope]}>{words}</span>) : null, [text, colours]);
  const copy = () => {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  };
  return (
    <div className={css.codeBlock}>
      <div className={css.codeBar}>
        <span className={css.codeLang}>{language ?? "text"}</span>
        <button type="button" className={css.codeCopy} onClick={copy} aria-label={t("web-main.prose.copyCode")}>
          {copied ? <Check size={12} /> : <Copy size={12} />}{copied ? t("common.copied") : t("common.copy")}
        </button>
      </div>
      <pre className={css.codePre}><code>{colours && text.length > 16000 ? <LongCode text={text} ink={colours} /> : coloured ?? text}</code></pre>
    </div>
  );
}

/** Plain text is present even far offscreen: browser find, selection, and copying still see the whole block.
 * Highlight each group once, close to the viewport. Never replace text nodes while a selection touches the block. */
function LongCode({ text, ink }: { text: string; ink: string }) {
  const chunks = useMemo(() => codeChunks(text, ink), [text, ink]);
  const root = useRef<HTMLSpanElement>(null);
  const [painted, setPainted] = useState<{ chunks: typeof chunks; indices: Set<number> }>(() => ({ chunks, indices: new Set() }));
  const indices = painted.chunks === chunks ? painted.indices : new Set<number>();
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const waiting = new Set<number>();
    const apply = () => {
      const selection = window.getSelection();
      if (selection && !selection.isCollapsed && selection.containsNode(el, true)) return;
      if (!waiting.size) return;
      const add = [...waiting];
      waiting.clear();
      setPainted(old => ({ chunks, indices: new Set([...(old.chunks === chunks ? old.indices : []), ...add]) }));
    };
    if (typeof IntersectionObserver === "undefined") {
      chunks.forEach((_, i) => waiting.add(i));
      apply();
      return;
    }
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        waiting.add(Number((entry.target as HTMLElement).dataset.codeChunk));
        observer.unobserve(entry.target);
      }
      apply();
    }, { rootMargin: "800px 0px" });
    for (const child of el.children) observer.observe(child);
    document.addEventListener("selectionchange", apply);
    return () => { observer.disconnect(); document.removeEventListener("selectionchange", apply); };
  }, [chunks]);
  return <span ref={root}>{chunks.map((chunk, i) => <CodePart key={i} chunk={chunk} index={i} painted={indices.has(i)} />)}</span>;
}
const CodePart = memo(function CodePart({ chunk, index, painted }: { chunk: ReturnType<typeof codeChunks>[number]; index: number; painted: boolean }) {
  return <span data-code-chunk={index}>{painted
    ? chunk.runs.map(([words, scope], i) => <span key={i} className={css.ink[scope]}>{words}</span>)
    : chunk.text}</span>;
});

/** The plain text of drawn children. */
function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return textOf(node.props.children);
  return "";
}

/** A link's words are the link itself (a bare link, not `[its words](link)`). */
const bare = (href: string, words: string) => [href, safeDecode(href)].includes(words.trim());

/** An address as a page may open it: a web page's, mail's, or one within the app (a file's path, a chat's); any other
 * scheme (`javascript:`) none. */
function safeUrl(url: string): string {
  const colon = url.indexOf(":");
  const scheme = url.slice(0, colon);
  if (colon < 0 || /[/?#]/.test(scheme) || /^(https?|ircs?|mailto|xmpp)$/i.test(scheme)) return url;
  return "";
}

/** A link to a station's screen (screen/ScreenLink.tsx) or 共享调试 (AdbLink.tsx) alone on its line: its card; else null. */
function linkCard(href: string, words: string, key?: number): ReactNode {
  const own = bare(href, words) ? null : words.trim();
  if (screenOfLink(href)) return <div key={key} className={inlineFile}><ScreenCard href={href} words={own} /></div>;
  if (adbOfLink(href)) return <div key={key} className={inlineFile}><AdbCard href={href} words={own} /></div>;
  return null;
}

/** Inline code (`code`, drawn as given) by what its words are: a web address alone is a link too, its ends the link's so
 * nothing after it is swallowed; a file's path, its chip. */
function inlineCode(words: string, code: ReactNode, children: ReactNode): ReactNode {
  const text = words.trim();
  if (/^https?:\/\/(?:localhost|[\w-]+(?:\.[\w-]+)+)(?::\d+)?(?:[/?#]\S*)?$/i.test(text) && !text.includes("…")) return link({ href: text, children: code });
  const found = pathIn(text);
  return found ? <FileRef path={found.path} line={found.line}>{children}</FileRef> : code;
}

/** A link in a message as it is drawn (but one naming the message's own files, which Prose places). A web page opens in
 * a tab of its own, not in place of the app (the desktop app's opens in the browser, as before). */
function link(props: ComponentProps<"a">) {
  const href = props.href ?? "";
  // A bare link (its words the link itself): the chip says the chat's title, not the link; a screen's, its title; a
  // station's 共享调试, that.
  if (isChatLink(href)) return <RefChip title={bare(href, textOf(props.children)) ? null : props.children} href={href} />;
  if (screenOfLink(href) && bare(href, textOf(props.children))) return <ScreenName href={href} />;
  if (adbOfLink(href) && bare(href, textOf(props.children))) return <AdbName href={href} />;
  if (/^https?:\/\//i.test(href)) return <LinkHover href={href} label={textOf(props.children)}><a {...props} title={undefined} target="_blank" rel="noopener noreferrer" /></LinkHover>;
  const file = /^[a-z][\w+.-]*:/i.test(href) ? null : pathIn(safeDecode(href));
  if (file) return <FileRef path={file.path} line={file.line} words={props.children}>{props.children}</FileRef>;
  return <Tip label={props.title}><a {...props} title={undefined} /></Tip>;
}

const safeDecode = (s: string) => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
};

/** Plain words (what a person wrote) with their bare addresses as the links a message draws (bareLinks.ts). */
export function withBareLinks(text: string): ReactNode {
  return bareLinks(text).map((part, i) => (typeof part === "string" ? part : <Fragment key={i}>{link({ href: part.url, className: css.bareLink, children: part.url })}</Fragment>));
}

/** An image in a row of them: widths in proportion to their shapes, so a row's images share one height (120px or a little more, 200px at most). */
function rowItem(f: Attachment): CSSProperties {
  const r = f.width && f.height ? Math.min(4, Math.max(0.25, f.width / f.height)) : 1.5;
  return { flex: `${r} ${r} ${Math.round(r * 120)}px`, maxWidth: `${Math.round(r * 200)}px`, "--ratio": r } as CSSProperties;
}

/** How a tree is drawn: the text its runs are of, and a message's files where its words place them. */
type Cx = {
  source: string;
  /** A link or image naming one of the message's files: the file (placeFiles, client/core-ts/src/placed.ts). */
  at: (url: string) => Attachment | undefined;
  /** A file drawn where the words place it: shown whole (an image, a link on a line of its own), or a link (its words). */
  draw: (f: Attachment, as: "shown" | "link", words?: ReactNode) => ReactNode;
};

/**
 * Markdown, read by the core's reader (kept by its text), or `md`, the core's tree of `children` already. With `files`
 * (from placeFiles, client/core-ts/src/placed.ts), a link or image naming one of the message's files shows it there, as
 * `file` draws it: shown whole for an image, or a link on a line of its own; a link within a sentence stays a link (its
 * words), opening the file.
 */
export const Prose = memo(function Prose({ children, md, files, file }: { children: string; md?: Md | undefined; files?: Map<string, Attachment>; file?: (f: Attachment, as: "shown" | "link", words?: ReactNode) => ReactNode }) {
  const [read, setRead] = useState<{ text: string; md: Md }>();
  useEffect(() => {
    if (md) return;
    let active = true;
    void core().call("markdown", { text: children }).then((value) => {
      if (active) setRead({ text: children, md: (value as { md: Md }).md });
    }).catch(() => { if (active) setRead({ text: children, md: [["p", [children]]] }); });
    return () => { active = false; };
  }, [md, children]);
  const tree = md ?? (read?.text === children ? read.md : undefined);
  return tree ? <MdView md={tree} source={children} files={files} file={file} /> : null;
});

/**
 * Markdown as the core read it (`Md`, client/core-ts/src/markdown.ts) from `source`: drawn here, never parsed. Each of its
 * blocks is drawn again only when it changes: the core hands the same tree for the same words, and a keyed delta keeps
 * what it does not change as it was (core/delta.ts), so a history that grows draws only what came.
 */
export const MdView = memo(function MdView({ md, source, files, file }: { md: Md; source: string; files?: Map<string, Attachment> | undefined; file?: ((f: Attachment, as: "shown" | "link", words?: ReactNode) => ReactNode) | undefined }) {
  // The files and how to draw one as last given: blocks drawn again only for new words or files to place, not for a
  // new `file` function each render (an image fetched again, flashing).
  const given = useRef({ files, file });
  given.current = { files, file };
  const placing = !!files?.size && !!file;
  const cx = useMemo<Cx>(() => ({
    source,
    at: (url) => (placing ? given.current.files?.get(nameOf(url)) : undefined),
    draw: (f, as, words) => given.current.file?.(f, as, words),
  }), [source, placing, placing ? files : null]);
  return <>{md.map((node, i) => <MdBlock key={i} node={node} cx={cx} />)}</>;
});

const MdBlock = memo(function MdBlock({ node, cx }: { node: MdNode; cx: Cx }) {
  return drawMd(node, 0, cx);
});

type Kind = Exclude<MdNode, string | [number, number]>;
const attrsOf = (node: Kind): Record<string, unknown> => ((Array.isArray(node[1]) ? node[2] : node[1]) ?? {}) as Record<string, unknown>;
const kidsOf = (node: Kind): MdNode[] => (Array.isArray(node[1]) ? node[1] : []);
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const ALIGN = new Set(["left", "right", "center"]);
/** A table's cell keeps its words on one line while they are this short (in ems of its font); a longer one wraps, this
 * wide at least. */
const LINE = 14;
const WIDE = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\u3000-\u303f\uff01-\uff60\uffe0-\uffe6]/u;
/** About how wide words are on one line, in ems: a CJK or full-width character about one, any other about half. */
const emsOf = (words: string) => [...words].reduce((n, c) => n + (WIDE.test(c) ? 1 : 0.55), 0);

/** A node's words, inline code's too. */
const mdText = (node: MdNode, cx: Cx): string => (isWords(node) ? wordsOf(node, cx.source) : node[0] === "code" ? wordsOf(attrsOf(node).content, cx.source) : kidsOf(node).map((k) => mdText(k, cx)).join(""));

function drawMd(node: MdNode, key: number, cx: Cx): ReactNode {
  if (isWords(node)) return wordsOf(node, cx.source);
  const kind = node[0];
  const a = attrsOf(node);
  const kids = () => kidsOf(node).map((k, i) => drawMd(k, i, cx));
  switch (kind) {
    case "p": {
      const parts = kidsOf(node).filter((c) => !isWords(c) || wordsOf(c, cx.source).trim());
      const only = parts.length === 1 && !isWords(parts[0]) && parts[0]![0] === "a" ? (parts[0] as Kind) : null;
      if (only) {
        const href = str(attrsOf(only).href) ?? "";
        // A link alone naming one of the message's files: the file, shown; to a station's screen or 共享调试: its card.
        const f = cx.at(href);
        if (f) return <div key={key} className={inlineFile}>{cx.draw(f, "shown")}</div>;
        const card = linkCard(safeUrl(href), mdText(only, cx), key);
        if (card) return card;
      }
      // A paragraph of the message's images and nothing else: side by side, wrapping when they don't fit.
      const images = parts.map((c) => (!isWords(c) && c[0] === "img" ? cx.at(str(attrsOf(c as Kind).src) ?? "") : undefined));
      if (images.length > 1 && images.every(Boolean)) return <div key={key} className={inlineFiles}>{images.map((f, i) => <span key={i} className={css.inlineFilesItem} style={rowItem(f!)}>{cx.draw(f!, "shown")}</span>)}</div>;
      return <p key={key}>{kids()}</p>;
    }
    case "h": {
      const H = `h${Math.min(6, Math.max(1, Number(a.depth) || 1))}` as "h1";
      return <H key={key}>{kids()}</H>;
    }
    case "pre": {
      const code = wordsOf(a.code, cx.source);
      if (a.math === true) return <div key={key} className={css.mathBlock}><Formula text={code} drawing={a.drawing as MathDrawing | null | undefined} /></div>;
      const language = str(a.lang);
      // A mermaid block is a chart, drawn (Viz.tsx); anything else is code.
      return language?.toLowerCase() === "mermaid" && code.trim() ? <Mermaid key={key} code={code} /> : <Code key={key} text={code} language={language} ink={str(a.ink) ?? null} />;
    }
    case "quote": return <blockquote key={key}>{kids()}</blockquote>;
    case "list": {
      const start = typeof a.start === "number" ? a.start : undefined;
      return a.ordered ? <ol key={key} start={start}>{kids()}</ol> : <ul key={key}>{kids()}</ul>;
    }
    case "li":
      return typeof a.checked === "boolean"
        ? <li key={key} className="task-list-item"><input type="checkbox" checked={a.checked} disabled readOnly /> {kids()}</li>
        : <li key={key}>{kids()}</li>;
    case "table": {
      const [head, ...rows] = kidsOf(node);
      const align = Array.isArray(a.align) ? a.align : [];
      const row = (r: MdNode | undefined, i: number) => {
        if (!r || isWords(r)) return null;
        return <tr key={i}>{kidsOf(r).map((cell, j) => {
          if (isWords(cell)) return null;
          // No column narrower than its widest cell's words on one line, or LINE of them where they are longer (nor
          // than a word of them; its padding besides): the browser would else squeeze a CJK column to a character or
          // two a line.
          const style: CSSProperties = emsOf(mdText(cell, cx)) < LINE ? { whiteSpace: "nowrap" } : { minWidth: `${LINE}em`, boxSizing: "content-box" };
          if (ALIGN.has(String(align[j]))) style.textAlign = align[j] as "left";
          const inner = kidsOf(cell).map((k, n) => drawMd(k, n, cx));
          return cell[0] === "th" ? <th key={j} style={style}>{inner}</th> : <td key={j} style={style}>{inner}</td>;
        })}</tr>;
      };
      // A table wider than the message scrolls sideways within it, its cells keeping their words whole; its frame is
      // the table's, scrolling with it.
      return <div key={key} className={css.tableScroll}><div className={css.tableFrame}><table><thead>{row(head, 0)}</thead>{rows.length > 0 && <tbody>{rows.map((r, i) => row(r, i))}</tbody>}</table></div></div>;
    }
    case "hr": return <hr key={key} />;
    case "b": return <strong key={key}>{kids()}</strong>;
    case "i": return <em key={key}>{kids()}</em>;
    case "s": return <del key={key}>{kids()}</del>;
    case "br": return <br key={key} />;
    case "code": {
      const content = wordsOf(a.content, cx.source);
      if (a.math === true) return <Formula key={key} text={content} drawing={a.drawing as MathDrawing | null | undefined} />;
      return <Fragment key={key}>{inlineCode(content, <code>{content}</code>, content)}</Fragment>;
    }
    case "a": {
      const href = str(a.href) ?? "";
      const f = cx.at(href);
      if (f) return <Fragment key={key}>{cx.draw(f, "link", kids())}</Fragment>;
      return <Fragment key={key}>{link({ href: safeUrl(href), title: str(a.title), children: kids() })}</Fragment>;
    }
    case "img": {
      const src = str(a.src) ?? "";
      const f = cx.at(src);
      if (f) return <span key={key} className={inlineFile}>{cx.draw(f, "shown")}</span>;
      return <Tip key={key} label={str(a.title)}><img src={safeUrl(src)} alt={str(a.alt) ?? ""} /></Tip>;
    }
    default: return <Fragment key={key}>{kids()}</Fragment>;
  }
}
