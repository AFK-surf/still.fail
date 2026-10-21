// Markdown as ember shows it: GitHub-flavoured, code blocks in the colours the
// core says (`code.ink`, client/core-ts/src/highlight.ts: vitesse light and
// dark, as every client paints them) with their language named and a copy
// button.
import { Check, Copy } from "@stillfail/ui/icons.tsx";
import { Fragment, isValidElement, memo, useEffect, useMemo, useRef, useState, type ComponentProps, type CSSProperties, type ReactNode } from "react";
import Markdown, { defaultUrlTransform, type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Attachment } from "./core/shapes.ts";
import type { Md, MdNode } from "./core/md.ts";
import { inlineFile, inlineFiles } from "./Prose.css.ts";
import * as css from "./Prose.css.ts";
import { RefChip } from "./ChatRef.tsx";
import { adbOfLink, isChatLink, screenOfLink } from "./chatRefs.ts";
import { ScreenCard, ScreenName } from "./screen/ScreenLink.tsx";
import { AdbCard, AdbName } from "./AdbLink.tsx";
import { bareLinks } from "./bareLinks.ts";
import { nameOf, placeFiles } from "../../client/core-ts/src/placed.ts";
import { runsOf } from "../../client/core-ts/src/highlight.ts";
import { core } from "./core/react.ts";
import { FileRef, LinkHover, pathIn } from "./Peeks.tsx";
import { Tip } from "./ui.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { Mermaid } from "./Viz.tsx";
import { t } from "./i18n.ts";

/** GFM's links found in bare text end only at a space, so in Chinese they swallow the words after them
 * (`（https://…/2854）已改到`): a bare address is linked where a reader sees it end (bareLinks.ts) instead, and
 * `www.…` and e-mail addresses stay text. [label](url) and <url> are links as written. */
function linkBare() {
  type Node = { type: string; value?: string; url?: string; title?: null; children?: Node[]; position?: { start: { offset?: number } } };
  return (tree: Node, file: { value: unknown }) => {
    const source = String(file.value);
    const within = (nodes: Node[], inLink: boolean): Node[] => nodes.flatMap((n) => {
      // GFM's own bare ones come without a position (www.…) or start at the address itself: their words, read again.
      const start = n.position?.start.offset;
      if (n.type === "link" && (start === undefined || (source[start] !== "[" && source[start] !== "<"))) return within(n.children ?? [], inLink);
      if (n.type === "text" && !inLink) {
        return bareLinks(n.value ?? "").map((part): Node => (typeof part === "string" ? { type: "text", value: part } : { type: "link", url: part.url, title: null, children: [{ type: "text", value: part.url }] }));
      }
      if (n.children) n.children = within(n.children, inLink || n.type === "link" || n.type === "linkReference");
      return [n];
    });
    if (tree.children) tree.children = within(tree.children, false);
  };
}

const inks = new Map<string, string | null>();

/** The colours of a block of code (its `ink`), the core's: null when it shows as it is. */
async function inkOf(code: string, language: string): Promise<string | null> {
  const key = `${language}\n${code}`;
  if (inks.has(key)) return inks.get(key)!;
  const { ink } = (await core().call("code.ink", { code, lang: language })) as { ink: string | null };
  if (inks.size > 300) inks.delete(inks.keys().next().value!);
  inks.set(key, ink);
  return ink;
}

/** The plain text of rendered children. */
function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return textOf(node.props.children);
  return "";
}

function CodeBlock({ children }: { children?: ReactNode }) {
  const code = isValidElement<{ className?: string; children?: ReactNode }>(children) ? children : null;
  const language = /language-([\w+#-]+)/.exec(code?.props.className ?? "")?.[1];
  const text = textOf(code?.props.children ?? children).replace(/\n$/, "");
  // A mermaid block is a chart, drawn (Viz.tsx); anything else is code.
  if (language?.toLowerCase() === "mermaid" && text.trim()) return <Mermaid code={text} />;
  return <Code text={text} language={language} />;
}

/** A block of code as markdown shows one: in the colours the core says of its language (`ink`, the core's Markdown's own
 * where it read it, else asked of it), with a copy button. */
export function Code({ text, language, ink }: { text: string; language?: string | undefined; ink?: string | null | undefined }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const [asked, setAsked] = useState<{ key: string; ink: string | null } | null>(null);
  const key = `${language}\n${text}`;
  useEffect(() => {
    if (!language || ink !== undefined) return;
    let live = true;
    // While a reply streams the block keeps changing; asked of once it settles.
    const timer = setTimeout(() => void inkOf(text, language).then((i) => { if (live) setAsked({ key: `${language}\n${text}`, ink: i }); }, () => {}), inks.has(key) ? 0 : 120);
    return () => { live = false; clearTimeout(timer); };
  }, [language, text, ink, key]);
  const copy = () => {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  };
  const current = ink !== undefined ? ink : asked?.key === key ? asked.ink : (inks.get(key) ?? null);
  return (
    <div className={css.codeBlock}>
      <div className={css.codeBar}>
        <span className={css.codeLang}>{language ?? "text"}</span>
        <button type="button" className={css.codeCopy} onClick={copy} aria-label={t("web-main.prose.copyCode")}>
          {copied ? <Check size={12} /> : <Copy size={12} />}{copied ? t("common.copied") : t("common.copy")}
        </button>
      </div>
      <pre><code>{current ? runsOf(text, current).map(([words, scope], i) => <span key={i} className={css.ink[scope]}>{words}</span>) : text}</code></pre>
    </div>
  );
}

/** A link's words are the link itself (a bare link, not `[its words](link)`). */
const bare = (href: string, words: string) => [href, safeDecode(href)].includes(words.trim());

type Hast = { type: string; value?: string; tagName?: string; properties?: Record<string, unknown>; children?: Hast[] };
const hastText = (n: Hast): string => n.value ?? (n.children ?? []).map(hastText).join("");

/** A link to a station's screen (screen/ScreenLink.tsx) or 共享调试 (AdbLink.tsx) alone on its line: its card; else null. */
function linkCard(href: string, words: string, key?: number): ReactNode {
  const own = bare(href, words) ? null : words.trim();
  if (screenOfLink(href)) return <div key={key} className={inlineFile}><ScreenCard href={href} words={own} /></div>;
  if (adbOfLink(href)) return <div key={key} className={inlineFile}><AdbCard href={href} words={own} /></div>;
  return null;
}

/** A paragraph that is a link with a card and nothing else: the card (linkCard); else null. */
function cardParagraph(node: Hast | undefined): ReactNode {
  const parts = node?.children?.filter((c) => c.type !== "text" || c.value?.trim()) ?? [];
  const only = parts.length === 1 && parts[0]!.type === "element" && parts[0]!.tagName === "a" ? parts[0]! : null;
  const href = only && typeof only.properties?.href === "string" ? only.properties.href : null;
  return href ? linkCard(href, hastText(only!)) : null;
}

const components: Components = {
  p: ({ node, children, ...props }) => cardParagraph(node as Hast | undefined) ?? <p {...props}>{children}</p>,
  pre: ({ children }) => <CodeBlock>{children}</CodeBlock>,
  // A table wider than the message scrolls sideways within it, its cells keeping their words whole.
  table: ({ node: _, ...props }) => <div className={css.tableScroll}><table {...props} /></div>,
  // A link to another chat: a reference to it, drawn as the composer showed it; a web link, with its card on hover; a
  // file on the station by its path, its chip (Peeks.tsx).
  a: ({ node: _, ...props }) => link(props),
  // Inline code that is a file's path: its chip (a block of code is CodeBlock's, never drawn as this).
  code: ({ node: _, className, children, ...props }) => {
    if (className) return <code className={className} {...props}>{children}</code>;
    return inlineCode(textOf(children), <code {...props}>{children}</code>, children);
  },
};

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

/**
 * Markdown. With `files` (from placeFiles, client/core-ts/src/placed.ts), a link or image naming one of the
 * message's files shows it there, as `file` draws it: shown whole for an
 * image, or a link on a line of its own; a link within a sentence stays a
 * link (its words), opening the file.
 */
// Parsing Markdown is the costly part of drawing a message: drawn again only when what it is given changes (a history
// or chat that draws again for something else leaves its texts as they are).
export const Prose = memo(function Prose({ children, files, file }: { children: string; files?: Map<string, Attachment>; file?: (f: Attachment, as: "shown" | "link", words?: ReactNode) => ReactNode }) {
  // The components are made once and read the files as last given: new ones each render would be new component types,
  // and React would draw what they hold anew (an image fetched again, flashing, whenever the message rendered).
  const given = useRef({ files, file });
  given.current = { files, file };
  const placing = !!files?.size && !!file;
  const withFiles = useMemo<Components>(() => {
    if (!placing) return components;
    const at = (url: unknown) => (typeof url === "string" ? given.current.files?.get(nameOf(url)) : undefined);
    const draw = (f: Attachment, as: "shown" | "link", words?: ReactNode) => given.current.file?.(f, as, words);
    return {
      ...components,
      p: ({ node, children, ...props }) => {
        const parts = node?.children.filter((c) => c.type !== "text" || c.value.trim()) ?? [];
        const only = parts.length === 1 && parts[0]!.type === "element" && parts[0]!.tagName === "a" ? at(parts[0]!.properties.href) : undefined;
        if (only) return <div className={inlineFile}>{draw(only, "shown")}</div>;
        const screen = cardParagraph(node as Hast | undefined);
        if (screen) return screen;
        // A paragraph of the message's images and nothing else: side by side, wrapping when they don't fit.
        const images = parts.map((c) => (c.type === "element" && c.tagName === "img" ? at(c.properties.src) : undefined));
        if (images.length > 1 && images.every(Boolean)) return <div className={inlineFiles}>{images.map((f, i) => <span key={i} className={css.inlineFilesItem} style={rowItem(f!)}>{draw(f!, "shown")}</span>)}</div>;
        return <p {...props}>{children}</p>;
      },
      img: ({ node: _, ...props }) => { const f = at(props.src); return f ? <span className={inlineFile}>{draw(f, "shown")}</span> : <Tip label={props.title}><img {...props} title={undefined} /></Tip>; },
      a: ({ node: _, ...props }) => { const f = at(props.href); return f ? draw(f, "link", props.children) : link(props); },
    };
  }, [placing]);
  // Links to the files are kept as written (the default would empty a file:// one); any other goes through the default.
  const url = (u: string) => (files?.has(nameOf(u)) ? u : defaultUrlTransform(u));
  return <Markdown remarkPlugins={[remarkGfm, linkBare]} components={withFiles} urlTransform={url}>{children}</Markdown>;
});

/**
 * An agent's Markdown as the core read it (`Md`, client/core-ts/src/markdown.ts): drawn here, never parsed. Each of its
 * blocks is drawn again only when it changes: the core hands the same tree for the same words, and a keyed delta keeps
 * what it does not change as it was (core/delta.ts), so a history that grows draws only what came.
 */
export const MdView = memo(function MdView({ md }: { md: Md }) {
  return <>{md.map((node, i) => <MdBlock key={i} node={node} />)}</>;
});

const MdBlock = memo(function MdBlock({ node }: { node: MdNode }) {
  return drawMd(node, 0);
});

const attrsOf = (node: Exclude<MdNode, string>): Record<string, unknown> => ((Array.isArray(node[1]) ? node[2] : node[1]) ?? {}) as Record<string, unknown>;
const kidsOf = (node: Exclude<MdNode, string>): MdNode[] => (Array.isArray(node[1]) ? node[1] : []);
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const ALIGN = new Set(["left", "right", "center"]);

const mdText = (node: MdNode): string => (typeof node === "string" ? node : kidsOf(node).map(mdText).join(""));

function drawMd(node: MdNode, key: number): ReactNode {
  if (typeof node === "string") return node;
  const kind = node[0];
  const a = attrsOf(node);
  const kids = () => kidsOf(node).map(drawMd);
  switch (kind) {
    case "p": {
      // A link to a station's screen or 共享调试 alone: its card.
      const parts = kidsOf(node).filter((c) => typeof c !== "string" || c.trim());
      const only = parts.length === 1 && typeof parts[0] !== "string" && parts[0]![0] === "a" ? parts[0]! : null;
      const href = only ? defaultUrlTransform(str(attrsOf(only).href) ?? "") : "";
      return (only && linkCard(href, kidsOf(only).map(mdText).join(""), key)) || <p key={key}>{kids()}</p>;
    }
    case "h": {
      const H = `h${Math.min(6, Math.max(1, Number(a.depth) || 1))}` as "h1";
      return <H key={key}>{kids()}</H>;
    }
    case "pre": {
      const code = str(a.code) ?? "";
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
        if (!r || typeof r === "string") return null;
        return <tr key={i}>{kidsOf(r).map((cell, j) => {
          if (typeof cell === "string") return null;
          const style = ALIGN.has(String(align[j])) ? { textAlign: align[j] as "left" } : undefined;
          return cell[0] === "th" ? <th key={j} style={style}>{kidsOf(cell).map(drawMd)}</th> : <td key={j} style={style}>{kidsOf(cell).map(drawMd)}</td>;
        })}</tr>;
      };
      // A table wider than the message scrolls sideways within it, its cells keeping their words whole.
      return <div key={key} className={css.tableScroll}><table><thead>{row(head, 0)}</thead>{rows.length > 0 && <tbody>{rows.map((r, i) => row(r, i))}</tbody>}</table></div>;
    }
    case "hr": return <hr key={key} />;
    case "b": return <strong key={key}>{kids()}</strong>;
    case "i": return <em key={key}>{kids()}</em>;
    case "s": return <del key={key}>{kids()}</del>;
    case "br": return <br key={key} />;
    case "code": {
      const content = str(a.content) ?? "";
      return <Fragment key={key}>{inlineCode(content, <code>{content}</code>, content)}</Fragment>;
    }
    case "a": return <Fragment key={key}>{link({ href: defaultUrlTransform(str(a.href) ?? ""), title: str(a.title), children: kids() })}</Fragment>;
    case "img": return <Tip key={key} label={str(a.title)}><img src={defaultUrlTransform(str(a.src) ?? "")} alt={str(a.alt) ?? ""} /></Tip>;
    default: return <Fragment key={key}>{kids()}</Fragment>;
  }
}
