// What picking a station's mark sends (the settings' stations, wide and phone): its icon and its emoji, set together. A
// glyph keeps its emoji beside it, so older clients (which know only emoji) show the nearest; an emoji or a picture
// takes the other away. "" takes either away.
import { STATION_ICONS } from "./icons.tsx";
import { isPicture, stationGlyph } from "./StationMark.tsx";

export type Mark = { emoji: string; icon: string };
export type Kind = "glyph" | "emoji";

export const NO_MARK: Mark = { emoji: "", icon: "" };
export const glyphMark = (g: (typeof STATION_ICONS)[number]): Mark => ({ icon: `glyph:${g.name}`, emoji: g.emoji });
export const emojiMark = (emoji: string): Mark => ({ emoji, icon: "" });
export const pictureMark = (url: string): Mark => ({ emoji: "", icon: url });

/** The emoji offered (any other can be pasted or typed): the first are those offered before there were icons. */
export const EMOJI = [
  "🖥️", "💻", "🍎", "🐧", "🪟", "☁️", "🏠", "🏢", "🚀", "⚡", "🔥", "🧪", "🛠️", "🐳", "🦀", "🐙", "🌲", "🌊", "🌙", "☀️", "🍊", "🍋", "🍇", "🐱",
  "🐶", "🦊", "🐼", "🐸", "🦉", "🐝", "🦄", "🐢", "🌵", "🌸", "🍄", "🌈", "❄️", "⭐", "🪐", "🌍", "🍉", "🍒", "🥑", "🍕", "☕", "🎧", "🎮", "🤖",
];

/** Which grid a station's mark is picked in first: the one it has (a picture's, or none's, the icons). */
export function kindOf(emoji: string | null | undefined, icon: string | null | undefined): Kind {
  return !stationGlyph(icon) && !isPicture(icon) && emoji ? "emoji" : "glyph";
}

/** Whether `m` is what the station has now (nothing to send). */
export function same(m: Mark, emoji: string | null | undefined, icon: string | null | undefined): boolean {
  return m.icon === (icon ?? "") && m.emoji === (emoji ?? "");
}

/** The first emoji of what was typed or pasted, as a person sees one (a flag, a family are one); null for none. */
export function firstEmoji(text: string): string | null {
  const one = [...new Intl.Segmenter().segment(text.trim())][0]?.segment;
  return one && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(one) ? one : null;
}

/** How long a picture's data URL may be (cloud/src/directory.ts takes 48 000). */
const MOST = 46_000;
const SIDE = 96;

/**
 * A picture put up as a station's icon: cropped to its middle square and drawn at 96 px, as a data URL small enough to go
 * with the workspace (WebP where the browser makes it, else PNG, else JPEG). Rejects what is not a picture it can read.
 */
export async function pictureOf(file: Blob): Promise<string> {
  const image = await createImageBitmap(file);
  const side = Math.min(image.width, image.height);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = SIDE;
  const g = canvas.getContext("2d")!;
  g.imageSmoothingQuality = "high";
  g.drawImage(image, (image.width - side) / 2, (image.height - side) / 2, side, side, 0, 0, SIDE, SIDE);
  image.close();
  for (const [type, quality] of [["image/webp", 0.86], ["image/png", undefined], ["image/jpeg", 0.85], ["image/jpeg", 0.6]] as const) {
    const url = canvas.toDataURL(type, quality);
    if (url.startsWith(`data:${type};`) && url.length <= MOST) return url;
  }
  throw new Error("too_big");
}

/** A picture among what was pasted (a screenshot, an image copied), if any. */
export function pastedPicture(data: DataTransfer | null): File | null {
  return [...(data?.files ?? [])].find((f) => /^image\/(png|jpeg|webp|gif)$/.test(f.type)) ?? null;
}
