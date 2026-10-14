// What the share page has of web/src/ChatRef.tsx (in its place: web/vite.share.config.ts): a link to another chat is
// a member's, which a visitor cannot open; its words stay.
import type { ReactNode } from "react";

export function RefChip({ title }: { title: ReactNode; href: string }) {
  return <>{title}</>;
}
