// What the share page has of web/src/FilePreview.tsx (in its place: web/vite.share.config.ts), for Viz.tsx: the share
// page draws a visualization from what it read (VizHtml), not from a station's session, and opens no preview of it.
import type { Attachment } from "../../core/shapes.ts";

export function useFileText(_sessionKey: string, _file: Attachment): { state: "loading" } | { state: "error" } | { state: "ready"; text: string } {
  return { state: "error" };
}

export function FilePreview(_: { open: boolean; onClose(): void; sessionKey: string; file: Attachment }) {
  return null;
}
