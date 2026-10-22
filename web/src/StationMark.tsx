// A station where it is named: what its workspace gave it (the settings' stations), else the server icon. Its `icon` comes
// first: one of still.fail's (glyph:<name>, design/station-icons; glyph:<name>:<colour> in one of MARK_COLORS, else the
// colour of the words it sits in) or a picture put up (its address, or a data URL); else its emoji. A glyph this build does not know shows
// the emoji (it is kept beside every glyph, for older clients too).
import { useEffect, useRef } from "react";
import { Server, STATION_ICONS } from "@stillfail/ui/icons.tsx";
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

/** Whether `icon` is a picture put up: its address (still.fail cloud keeps it: cloud/src/icons.ts), or a data URL. */
export function isPicture(icon: string | null | undefined): icon is string {
  return !!icon && (icon.startsWith("data:image/") || icon.startsWith("https://") || icon.startsWith("http://"));
}

/** A station's mark where stations are listed to pick from: its icon or emoji, else its first letter in a box as large,
 * so their names line up either way. */
export function MarkOrLetter({ emoji, icon, name, size = 20 }: { emoji?: string | null | undefined; icon?: string | null | undefined; name: string; size?: number }) {
  if (emoji || icon) return <StationMark emoji={emoji} icon={icon} size={size} />;
  return <span className={css.letter} style={{ width: size, height: size }} aria-hidden="true">{[...name.trim()][0]?.toUpperCase() ?? "·"}</span>;
}

/** `still`: a GIF put up is held at its first frame (a workspace not in use, among the others: WorkspaceMark). */
export function StationMark({ emoji, icon, size = 14, className, still }: { emoji?: string | null | undefined; icon?: string | null | undefined; size?: number; className?: string | undefined; still?: boolean | undefined }) {
  const glyph = stationGlyph(icon);
  if (glyph) return <glyph.Icon size={size} className={className} style={{ color: markColor(glyphColor(icon)) }} />;
  const more = className ? ` ${className}` : "";
  if (isPicture(icon) && still && isGif(icon)) return <StillPicture src={icon} size={size} className={`${css.picture}${more}`} />;
  if (isPicture(icon)) return <img src={icon} alt="" width={size} height={size} className={`${css.picture}${more}`} draggable={false} />;
  if (!emoji) return <Server size={size} className={className} />;
  return (
    <span className={`${css.emoji}${WINDOWS ? ` ${css.windowsEmoji}` : ""}${more}`} style={{ width: size, height: size, fontSize: Math.round(size * 0.9) }} aria-hidden="true"><Glyph emoji={emoji} /></span>
  );
}

/** Whether a picture put up is a GIF (which may move): a data URL's type, or the name still.fail cloud keeps it by. */
const isGif = (icon: string) => icon.startsWith("data:image/gif;") || icon.endsWith(".gif");

/** A GIF held at its first frame: drawn once, filling its square as the picture would (cover). */
function StillPicture({ src, size, className }: { src: string; size: number; className: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const scale = typeof devicePixelRatio === "number" ? Math.max(1, Math.ceil(devicePixelRatio)) : 1;
  useEffect(() => {
    let live = true;
    const image = new Image();
    // Drawn, an animated image gives its first frame (HTML's drawImage).
    image.onload = () => {
      const c = canvas.current;
      if (!live || !c) return;
      const g = c.getContext("2d")!;
      const side = Math.min(image.naturalWidth, image.naturalHeight);
      g.clearRect(0, 0, c.width, c.height);
      g.imageSmoothingQuality = "high";
      g.drawImage(image, (image.naturalWidth - side) / 2, (image.naturalHeight - side) / 2, side, side, 0, 0, c.width, c.height);
    };
    image.src = src;
    return () => { live = false; };
  }, [src, size, scale]);
  return <canvas ref={canvas} width={size * scale} height={size * scale} style={{ width: size, height: size }} className={className} aria-hidden="true" />;
}

/** An emoji centred where it is put, whatever room its font gives it. */
export function Glyph({ emoji }: { emoji: string }) {
  return <span className={`${css.glyph}${WINDOWS ? ` ${css.windowsGlyph}` : ""}`}>{emoji}</span>;
}
