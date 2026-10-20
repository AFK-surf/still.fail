// What the share page has of web/src/annotate/ImageMarks.tsx (in its place: web/vite.share.config.ts), for
// FilePreview.tsx: an image is marked to go into a chat's draft, and a visitor has no chat to send it to: no marking.
import type { CSSProperties, ReactNode } from "react";

export function useImageMarks(_: { url: string | null; name: string; natural: { w: number; h: number } | null; scale: number; pass: unknown; onDone(): void }) {
  return { on: false, bar: null as ReactNode, tools: null as ReactNode, sheet: (_place: CSSProperties | null): ReactNode => null };
}
