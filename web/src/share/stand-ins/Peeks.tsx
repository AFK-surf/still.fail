// What the share page has of web/src/Peeks.tsx (in its place: web/vite.share.config.ts): a visitor reaches no station's
// files or link cards, so a file's path stays the words it was written as, and a web link a plain link.
import type { ReactElement, ReactNode } from "react";

export { pathIn } from "../../paths.ts";

export function FileRef({ children, words }: { path: string; line: number | null; children: ReactNode; words?: ReactNode }) {
  return words === undefined ? <code>{children}</code> : <>{children}</>;
}

export function LinkHover({ children }: { href: string; label: string; children: ReactElement }) {
  return children;
}
