// A station's name in a line of words, its mark (./StationMark.tsx) before it when its workspace gave it one, as the
// chats' rows and the decisions name it.
import { useStationLook } from "./api.ts";
import { StationMark } from "./StationMark.tsx";
import * as css from "./StationMark.css.ts";

export function StationNamed({ emoji, icon, name, size = 12 }: { emoji?: string | null | undefined; icon?: string | null | undefined; name: string; size?: number }) {
  return <>{(emoji || icon) && <StationMark emoji={emoji} icon={icon} size={size} className={css.inline} />}{name}</>;
}

/**
 * Its mark alone, by its address, before words about it: as the workspace's stations list has it; nothing without one.
 * `alone`: a picture of its own (a row's), the server icon without one.
 */
export function StationMarkAt({ station, size = 12, alone }: { station: string | null | undefined; size?: number; alone?: boolean }) {
  const look = useStationLook(station ?? null);
  if (alone) return <StationMark emoji={look?.emoji} icon={look?.icon} size={size} />;
  return look && (look.emoji || look.icon) ? <StationMark emoji={look.emoji} icon={look.icon} size={size} className={css.inline} /> : null;
}

/** Its name by its address, where only its name is at hand. */
export function StationNamedAt({ station, name, size }: { station: string | null | undefined; name: string; size?: number }) {
  return <><StationMarkAt station={station} {...(size ? { size } : {})} />{name}</>;
}
