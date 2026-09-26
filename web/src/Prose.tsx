// Markdown as ember shows it: GitHub-flavoured, code blocks highlighted with
// their language named and a copy button, the palette following the page.
import { Check, Copy } from "lucide-react";
import { isValidElement, useState, type ReactNode } from "react";
import Markdown, { type Components } from "react-markdown";
import rehypeHighlight from "rehype-highlight";
import remarkGfm from "remark-gfm";

/** The plain text of rendered children, for copying a highlighted block. */
function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return textOf(node.props.children);
  return "";
}

function CodeBlock({ children }: { children?: ReactNode }) {
  const [copied, setCopied] = useState(false);
  const code = isValidElement<{ className?: string; children?: ReactNode }>(children) ? children : null;
  const language = /language-([\w+-]+)/.exec(code?.props.className ?? "")?.[1];
  const copy = () => {
    void navigator.clipboard.writeText(textOf(code?.props.children ?? children).replace(/\n$/, "")).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  };
  return (
    <div className="code-block">
      <div className="code-bar">
        <span className="code-lang">{language ?? "text"}</span>
        <button type="button" className="code-copy" onClick={copy} aria-label="复制代码">
          {copied ? <Check size={12} /> : <Copy size={12} />}{copied ? "已复制" : "复制"}
        </button>
      </div>
      <pre>{children}</pre>
    </div>
  );
}

const components: Components = { pre: ({ children }) => <CodeBlock>{children}</CodeBlock> };
const rehype = [[rehypeHighlight, { detect: false, ignoreMissing: true }]] as never;

export function Prose({ children }: { children: string }) {
  return <Markdown remarkPlugins={[remarkGfm]} rehypePlugins={rehype} components={components}>{children}</Markdown>;
}
