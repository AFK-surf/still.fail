// A station where it is named: the icon its workspace gave it (the settings' stations), else the server icon. What is kept
// is an emoji (older clients show it as one): one of ours is drawn as its icon, any other (picked before there were icons)
// as the emoji.
import { Server, STATION_ICONS, type IconProps } from "./icons.tsx";
import * as css from "./StationMark.css.ts";

const BY_EMOJI = new Map(STATION_ICONS.map((s) => [s.emoji.replace(/️/g, ""), s.Icon]));

/** The icon drawn for an emoji kept, with or without its variation selector; undefined for one not drawn here. */
export function stationIcon(emoji: string): ((props: IconProps) => React.JSX.Element) | undefined {
  return BY_EMOJI.get(emoji.replace(/️/g, ""));
}

export function StationMark({ emoji, size = 14, className }: { emoji?: string | null | undefined; size?: number; className?: string | undefined }) {
  if (!emoji) return <Server size={size} className={className} />;
  const Icon = stationIcon(emoji);
  if (Icon) return <Icon size={size} className={className} />;
  return (
    <span className={`${css.emoji}${className ? ` ${className}` : ""}`} style={{ width: size, height: size, fontSize: Math.round(size * 0.9) }} aria-hidden="true"><Glyph emoji={emoji} /></span>
  );
}

/** An emoji centred where it is put, whatever room its font gives it. */
function Glyph({ emoji }: { emoji: string }) {
  return <span className={css.glyph}>{emoji}</span>;
}
