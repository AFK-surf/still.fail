// A found message's line (the core's `chatSearch` messages) with the words looked for drawn out: ⌘K's switcher
// (Switcher.tsx) and the phone's search (mobile/Home.tsx), each bold with a hand-drawn stroke under it (global.css.ts
// `mark[data-stroke]`), as a message a search opened marks them.
import type { CSSProperties, ReactNode } from "react";
import type { TextMark } from "./core/shapes.ts";

/** `text` with each of `marks` (UTF-16 ranges, in order) in a `<mark>` of `className`. */
export function Marked({ text, marks, className }: { text: string; marks: TextMark[]; className: string }) {
  const parts: ReactNode[] = [];
  let from = 0;
  let n = 0;
  for (const m of marks) {
    if (m.from < from || m.to > text.length) continue;
    if (m.from > from) parts.push(text.slice(from, m.from));
    parts.push(<mark key={m.from} className={className} data-stroke="" style={{ "--n": n++ } as CSSProperties}>{text.slice(m.from, m.to)}</mark>);
    from = m.to;
  }
  parts.push(text.slice(from));
  return <>{parts}</>;
}
