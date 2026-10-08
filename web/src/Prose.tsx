// Markdown as ember shows it: GitHub-flavoured, code blocks highlighted by
// Shiki (VS Code's grammars) with their language named and a copy button.
// Grammars load on demand, one chunk per language, with Shiki's JavaScript
// regex engine so no wasm is fetched.
import { Check, Copy } from "./icons.tsx";
import { isValidElement, memo, useEffect, useMemo, useRef, useState, type ComponentProps, type CSSProperties, type ReactNode } from "react";
import Markdown, { defaultUrlTransform, type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import type { HighlighterCore } from "shiki/core";
import type { Attachment } from "./core/shapes.ts";
import { inlineFile, inlineFiles } from "./Prose.css.ts";
import * as css from "./Prose.css.ts";
import { RefChip } from "./ChatRef.tsx";
import { isChatLink } from "./chatRefs.ts";
import { FileRef, LinkHover, pathIn } from "./Peeks.tsx";
import { Tip } from "./ui.tsx";
import { failure, useToast } from "./toast.tsx";
import { Mermaid } from "./Viz.tsx";
import { t } from "./i18n.ts";

/** GFM's links found in bare text end only at a space, so in Chinese they swallow the words after them
 * (`（https://…/2854）已改到`); a link is one written as [label](url) or <url>, and a bare one stays text. */
function noBareLinks() {
  type Node = { type: string; children?: Node[]; position?: { start: { offset?: number } } };
  return (tree: Node, file: { value: unknown }) => {
    const source = String(file.value);
    const unwrap = (nodes: Node[]): Node[] => nodes.flatMap((n) => {
      // Bare ones come from GFM without a position (www.…) or start at the URL itself.
      const start = n.position?.start.offset;
      if (n.type === "link" && (start === undefined || (source[start] !== "[" && source[start] !== "<"))) return unwrap(n.children ?? []);
      if (n.children) n.children = unwrap(n.children);
      return [n];
    });
    if (tree.children) tree.children = unwrap(tree.children);
  };
}

let highlighter: Promise<HighlighterCore> | null = null;
/** Light and dark at once (Shiki's dual themes): light inline, dark as `--shiki-dark` vars the dark page picks (Prose.css.ts). */
const THEMES = { light: "vitesse-light", dark: "vitesse-dark" } as const;

function getHighlighter(): Promise<HighlighterCore> {
  highlighter ??= (async () => {
    const [{ createHighlighterCore }, { createJavaScriptRegexEngine }] = await Promise.all([import("shiki/core"), import("shiki/engine/javascript")]);
    return createHighlighterCore({ themes: [import("shiki/themes/vitesse-light.mjs"), import("shiki/themes/vitesse-dark.mjs")], langs: [], engine: createJavaScriptRegexEngine() });
  })();
  return highlighter;
}

const cache = new Map<string, string>();

/** Highlighted HTML for a block, or null when the language is unknown to Shiki. */
async function highlight(code: string, language: string): Promise<string | null> {
  const key = `${language}\n${code}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const { bundledLanguages } = await import("shiki/langs");
  const lang = language.toLowerCase();
  const load = bundledLanguages[lang as keyof typeof bundledLanguages];
  if (!load) return null;
  const h = await getHighlighter();
  if (!h.getLoadedLanguages().includes(lang)) await h.loadLanguage(load);
  const html = h.codeToHtml(code, { lang, themes: THEMES });
  if (cache.size > 300) cache.delete(cache.keys().next().value!);
  cache.set(key, html);
  return html;
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

/** A block of code as markdown shows one: highlighted when its language is known (a name or a file extension Shiki knows), with a copy button. */
export function Code({ text, language }: { text: string; language?: string | undefined }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const [html, setHtml] = useState<string | null>(null);
  useEffect(() => {
    if (!language) return;
    let live = true;
    // While a reply streams the block keeps changing; highlight once it settles.
    const timer = setTimeout(() => void highlight(text, language).then((h) => { if (live) setHtml(h); }, () => {}), cache.has(`${language}\n${text}`) ? 0 : 120);
    return () => { live = false; clearTimeout(timer); };
  }, [language, text]);
  const copy = () => {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  };
  const current = html && cache.get(`${language}\n${text}`) === html ? html : null;
  return (
    <div className={css.codeBlock}>
      <div className={css.codeBar}>
        <span className={css.codeLang}>{language ?? "text"}</span>
        <button type="button" className={css.codeCopy} onClick={copy} aria-label={t("web-main.prose.copyCode")}>
          {copied ? <Check size={12} /> : <Copy size={12} />}{copied ? t("common.copied") : t("common.copy")}
        </button>
      </div>
      {current ? <div className={css.codeShiki} dangerouslySetInnerHTML={{ __html: current }} /> : <pre><code>{text}</code></pre>}
    </div>
  );
}

const components: Components = {
  pre: ({ children }) => <CodeBlock>{children}</CodeBlock>,
  // A table wider than the message scrolls sideways within it, its cells keeping their words whole.
  table: ({ node: _, ...props }) => <div className={css.tableScroll}><table {...props} /></div>,
  // A link to another chat: a reference to it, drawn as the composer showed it; a web link, with its card on hover; a
  // file on the station by its path, its chip (Peeks.tsx).
  a: ({ node: _, ...props }) => link(props),
  // Inline code that is a file's path: its chip (a block of code is CodeBlock's, never drawn as this).
  code: ({ node: _, className, children, ...props }) => {
    const found = className ? null : pathIn(textOf(children));
    return found ? <FileRef path={found.path} line={found.line}>{children}</FileRef> : <code className={className} {...props}>{children}</code>;
  },
};

/** A link in a message as it is drawn (but one naming the message's own files, which Prose places). */
function link(props: ComponentProps<"a">) {
  const href = props.href ?? "";
  if (isChatLink(href)) return <RefChip title={props.children} href={href} />;
  if (/^https?:\/\//i.test(href)) return <LinkHover href={href} label={textOf(props.children)}><a {...props} title={undefined} /></LinkHover>;
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

/** The file a link or image in the text names, by its file name (the last part of its path): `shot.png`, `/w/shot.png`, `ember-file://…/shot.png`. */
function nameOf(url: string): string {
  let u = url.trim().replace(/^(ember-)?file:\/\//, "");
  try { u = decodeURIComponent(u); } catch { /* kept as written */ }
  return u.slice(u.lastIndexOf("/") + 1);
}

/**
 * Which of a message's files its text places, by the name its links and
 * images give (`![](shot.png)`, `[the report](report.pdf)`), and the rest,
 * shown below the text. Code is passed over: a name in it places nothing.
 */
export function placeFiles(text: string, files: Attachment[] | undefined): { placed: Map<string, Attachment>; rest: Attachment[] } {
  const placed = new Map<string, Attachment>();
  if (!files?.length || !text) return { placed, rest: files ?? [] };
  const prose = text.replace(/^ {0,3}(`{3,}|~{3,})[^]*?(^ {0,3}\1|(?![^]))/gm, "").replace(/(`+)[^]*?\1/g, "");
  for (const [, url] of prose.matchAll(/\]\(\s*<?([^)\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g)) {
    const name = nameOf(url!);
    const file = files.find((f) => f.name === name);
    if (file) placed.set(name, file);
  }
  const used = new Set(placed.values());
  return { placed, rest: files.filter((f) => !used.has(f)) };
}

/** An image in a row of them: widths in proportion to their shapes, so a row's images share one height (120px or a little more, 200px at most). */
function rowItem(f: Attachment): CSSProperties {
  const r = f.width && f.height ? Math.min(4, Math.max(0.25, f.width / f.height)) : 1.5;
  return { flex: `${r} ${r} ${Math.round(r * 120)}px`, maxWidth: `${Math.round(r * 200)}px`, "--ratio": r } as CSSProperties;
}

/**
 * Markdown. With `files` (from placeFiles), a link or image naming one of the
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
  return <Markdown remarkPlugins={[remarkGfm, noBareLinks]} components={withFiles} urlTransform={url}>{children}</Markdown>;
});
