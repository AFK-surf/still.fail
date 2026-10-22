// Loaded by Prose only for formulas; no DOM scanning or reparsing of the surrounding message.
import { memo, useMemo } from "react";
import katex from "katex";
import "katex/dist/katex.min.css";

export default memo(function Math({ text, display = false }: { text: string; display?: boolean }) {
  const html = useMemo(() => {
    try {
      return katex.renderToString(text, { displayMode: display, throwOnError: false, trust: false, maxSize: 20, maxExpand: 1000 });
    } catch {
      return null;
    }
  }, [text, display]);
  return html === null ? <code>{text}</code> : <span dangerouslySetInnerHTML={{ __html: html }} />;
});
