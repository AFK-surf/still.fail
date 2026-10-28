// A workspace where it is switched to: the mark its managers gave it (the workspace's settings; an icon of still.fail's,
// a picture or an emoji, as a station's: StationMark), else its first letter. Where it is named among other words (a
// list, a chip, a heading), its mark or its letter on a tile goes before its name (WorkspaceNamed).
import type { ReactNode } from "react";
import { isPicture, StationMark } from "./StationMark.tsx";
import * as css from "./WorkspaceMark.css.ts";

type Marked = { emoji?: string | null | undefined; icon?: string | null | undefined };

/** Whether the workspace has a mark of its own (else its letter is shown). */
export const marked = (w: Marked): boolean => !!w.emoji || !!w.icon;

/**
 * Its mark at `size` (a picture at `picture`, filling its square), else its first letter. `still`: a GIF holds its first
 * frame (a workspace listed beside the one in use: only that one's moves).
 */
export function WorkspaceMark({ w, size = 16, picture = size, still }: { w: { name: string } & Marked; size?: number; picture?: number; still?: boolean }) {
  if (!marked(w)) return <>{[...w.name.trim()][0]?.toUpperCase() ?? "·"}</>;
  return <StationMark emoji={w.emoji} icon={w.icon} size={isPicture(w.icon) ? picture : size} still={still} />;
}

/**
 * Its mark at `size`, else its first letter on a tile as large: where it stands before its name, so names line up. A GIF
 * holds its first frame unless `still` is false (the workspace in use).
 */
export function WorkspaceBadge({ w, size = 16, still = true }: { w: { name: string } & Marked; size?: number; still?: boolean }) {
  if (marked(w)) return <StationMark emoji={w.emoji} icon={w.icon} size={size} still={still} />;
  return <span className={css.letter} style={{ width: size, height: size, fontSize: Math.round(size * 0.6) }} aria-hidden="true">{[...w.name.trim()][0]?.toUpperCase() ?? "·"}</span>;
}

/** A workspace named: its mark (WorkspaceBadge), then its name (or `children` in its place: words that name it). */
export function WorkspaceNamed({ w, size = 16, className, children }: { w: { name: string } & Marked; size?: number; className?: string | undefined; children?: ReactNode }) {
  return <span className={className ? `${css.named} ${className}` : css.named}><WorkspaceBadge w={w} size={size} /><span className={css.name}>{children ?? w.name}</span></span>;
}
