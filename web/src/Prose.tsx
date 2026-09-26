// Markdown as ember shows it: GitHub-flavoured, code blocks highlighted by
// Shiki (VS Code's grammars) with their language named and a copy button.
// Grammars load on demand, one chunk per language, with Shiki's JavaScript
// regex engine so no wasm is fetched.
import { Check, Copy } from "lucide-react";
import { isValidElement, useEffect, useState, type ReactNode } from "react";
import Markdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import type { HighlighterCore } from "shiki/core";

let highlighter: Promise<HighlighterCore> | null = null;
const THEME = "vitesse-light";

function getHighlighter(): Promise<HighlighterCore> {
  highlighter ??= (async () => {
    const [{ createHighlighterCore }, { createJavaScriptRegexEngine }] = await Promise.all([import("shiki/core"), import("shiki/engine/javascript")]);
    return createHighlighterCore({ themes: [import("shiki/themes/vitesse-light.mjs")], langs: [], engine: createJavaScriptRegexEngine() });
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
  const html = h.codeToHtml(code, { lang, theme: THEME });
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
  const [copied, setCopied] = useState(false);
  const code = isValidElement<{ className?: string; children?: ReactNode }>(children) ? children : null;
  const language = /language-([\w+#-]+)/.exec(code?.props.className ?? "")?.[1];
  const text = textOf(code?.props.children ?? children).replace(/\n$/, "");
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
    });
  };
  const current = html && cache.get(`${language}\n${text}`) === html ? html : null;
  return (
    <div className="code-block">
      <div className="code-bar">
        <span className="code-lang">{language ?? "text"}</span>
        <button type="button" className="code-copy" onClick={copy} aria-label="复制代码">
          {copied ? <Check size={12} /> : <Copy size={12} />}{copied ? "已复制" : "复制"}
        </button>
      </div>
      {current ? <div className="code-shiki" dangerouslySetInnerHTML={{ __html: current }} /> : <pre><code>{text}</code></pre>}
    </div>
  );
}

const components: Components = { pre: ({ children }) => <CodeBlock>{children}</CodeBlock> };

export function Prose({ children }: { children: string }) {
  return <Markdown remarkPlugins={[remarkGfm]} components={components}>{children}</Markdown>;
}
