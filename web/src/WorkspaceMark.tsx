// A workspace where it is switched to: the mark its managers gave it (the workspace's settings; an icon of still.fail's,
// a picture or an emoji, as a station's: StationMark), else its first letter.
import { isPicture, StationMark } from "./StationMark.tsx";

/** Whether the workspace has a mark of its own (else its letter is shown). */
export const marked = (w: { emoji?: string | null | undefined; icon?: string | null | undefined }): boolean => !!w.emoji || !!w.icon;

/**
 * Its mark at `size` (a picture at `picture`, filling its square), else its first letter. `still`: a GIF holds its first
 * frame (a workspace listed beside the one in use: only that one's moves).
 */
export function WorkspaceMark({ w, size = 16, picture = size, still }: { w: { name: string; emoji?: string | null | undefined; icon?: string | null | undefined }; size?: number; picture?: number; still?: boolean }) {
  if (!marked(w)) return <>{[...w.name.trim()][0]?.toUpperCase() ?? "·"}</>;
  return <StationMark emoji={w.emoji} icon={w.icon} size={isPicture(w.icon) ? picture : size} still={still} />;
}
