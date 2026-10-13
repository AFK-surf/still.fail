// An entry's mark by what opens it (the core's `kind`), still.fail's own line icons (design/icons): no tinted tile.
import type { DriveKind } from "../core/shapes.ts";
import { File, FileAudio, FileCode, FilePdf, FileText, FileVideo, Folder, Photo } from "../icons.tsx";

const ICONS = {
  folder: Folder, video: FileVideo, audio: FileAudio, image: Photo, markdown: FileText, text: FileText, subtitle: FileText,
  code: FileCode, csv: FileCode, html: FileCode, pdf: FilePdf, other: File,
} as const;

export function KindIcon({ kind, size = 22, className }: { kind: DriveKind; size?: number; className?: string }) {
  const Icon = ICONS[kind] ?? File;
  return <Icon size={size} strokeWidth={1.6} {...(className ? { className } : {})} />;
}
