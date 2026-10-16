// What the share page has of web/src/ui.tsx (in its place: web/vite.share.config.ts): a tip says nothing more there
// (what it would say is on the page already, or a button's label); people's tiles and the preview's choice of how a file
// shows (FilePreview.tsx) are @stillfail/ui's own.
import type { ReactNode } from "react";

export { Avatar, Segmented } from "@stillfail/ui/parts.tsx";

export function Tip({ children }: { label?: ReactNode; children: ReactNode; side?: string; shortcut?: unknown; cut?: boolean }) {
  return <>{children}</>;
}
