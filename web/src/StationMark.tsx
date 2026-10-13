// A station where it is named: what its workspace gave it (the settings' stations), else the server icon. Its `icon` comes
// first: one of still.fail's (glyph:<name>, design/station-icons; glyph:<name>:<colour> in one of MARK_COLORS, else the
// colour of the words it sits in) or a picture put up (a data URL); else its emoji. A glyph this build does not know shows
// the emoji (it is kept beside every glyph, for older clients too).
import { Server, STATION_ICONS } from "./icons.tsx";
import * as css from "./StationMark.css.ts";

const BY_NAME = new Map(STATION_ICONS.map((s) => [s.name, s]));
const WINDOWS = typeof navigator !== "undefined" && /Win/.test(navigator.platform);

/** The colours a glyph can be given, in the picker's order (StationMark.css.ts has each one's, per theme). */
export const MARK_COLORS = ["red", "orange", "amber", "green", "teal", "blue", "purple", "pink"] as const;
export type MarkColor = (typeof MARK_COLORS)[number];

/** The one of still.fail's icons `icon` names; undefined for a picture, none, or one this build does not know. */
export function stationGlyph(icon: string | null | undefined): (typeof STATION_ICONS)[number] | undefined {
  return icon?.startsWith("glyph:") ? BY_NAME.get(icon.slice(6).split(":")[0]!) : undefined;
}

/** The colour a glyph was given; undefined for none, or one this build does not know (drawn in the words' colour). */
export function glyphColor(icon: string | null | undefined): MarkColor | undefined {
  const color = icon?.startsWith("glyph:") ? icon.slice(6).split(":")[1] : undefined;
  return MARK_COLORS.find((c) => c === color);
}

/** A colour of MARK_COLORS as CSS, for the theme in use. */
export const markColor = (color: MarkColor | undefined): string | undefined => color && `var(--mark-${color})`;

/** Whether `icon` is a picture put up (a data URL). */
export function isPicture(icon: string | null | undefined): icon is string {
  return !!icon && icon.startsWith("data:image/");
}

export function StationMark({ emoji, icon, size = 14, className }: { emoji?: string | null | undefined; icon?: string | null | undefined; size?: number; className?: string | undefined }) {
  const glyph = stationGlyph(icon);
  if (glyph) return <glyph.Icon size={size} className={className} style={{ color: markColor(glyphColor(icon)) }} />;
  const more = className ? ` ${className}` : "";
  if (isPicture(icon)) return <img src={icon} alt="" width={size} height={size} className={`${css.picture}${more}`} draggable={false} />;
  if (!emoji) return <Server size={size} className={className} />;
  return (
    <span className={`${css.emoji}${more}`} style={{ width: size, height: size, fontSize: Math.round(size * 0.9) }} aria-hidden="true"><Glyph emoji={emoji} /></span>
  );
}

/** An emoji centred where it is put, whatever room its font gives it. */
export function Glyph({ emoji }: { emoji: string }) {
  return <span className={`${css.glyph}${WINDOWS ? ` ${css.windowsGlyph}` : ""}`}>{emoji}</span>;
}
