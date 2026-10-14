// What the share page has of web/src/ui.tsx (in its place: web/vite.share.config.ts): a tip says nothing more there
// (what it would say is on the page already), and people's tiles are the chat's.
import type { ReactNode } from "react";

export { Avatar } from "../../Avatar.tsx";

export function Tip({ children }: { label?: ReactNode; children: ReactNode; side?: string; shortcut?: unknown; cut?: boolean }) {
  return <>{children}</>;
}
