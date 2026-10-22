// What picking a station's mark sends (the settings' stations, wide and phone): its icon and its emoji, set together. A
// glyph keeps its emoji beside it, so older clients (which know only emoji) show the nearest; an emoji or a picture
// takes the other away. "" takes either away.
import { STATION_ICONS } from "@stillfail/ui/icons.tsx";
import { gifOf, type GifFrame } from "./gifEncode.ts";
import { isPicture, stationGlyph, type MarkColor } from "./StationMark.tsx";

export type Mark = { emoji: string; icon: string };
export type Kind = "glyph" | "emoji";

export const NO_MARK: Mark = { emoji: "", icon: "" };
/** A glyph in `color` (none: the colour of the words it sits in). */
export const glyphMark = (g: (typeof STATION_ICONS)[number], color?: MarkColor): Mark => ({ icon: `glyph:${g.name}${color ? `:${color}` : ""}`, emoji: g.emoji });
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

/** How long a picture's data URL may be (cloud/src/directory.ts takes 48 000, and 160 000 for a GIF). */
const MOST = 46_000;
const MOST_GIF = 156_000;
const SIDE = 96;

/**
 * A picture put up as a station's icon: cropped to its middle square and drawn at 96 px, as a data URL small enough to go
 * with the workspace (WebP where the browser makes it, else PNG, else JPEG); a GIF that moves stays a GIF (movingOf).
 * Rejects what is not a picture it can read.
 */
export async function pictureOf(file: Blob): Promise<string> {
  if (file.type === "image/gif") {
    const moving = await movingOf(file);
    if (moving) return moving;
  }
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

/**
 * A GIF that moves, kept moving: as it is where it is small enough, else its frames drawn again as pictureOf draws one
 * (smaller, then with fewer frames, until it fits). Null for a GIF of one frame (made a picture like any other); too_big
 * for one that does not fit even so, or that this browser cannot take apart (no ImageDecoder).
 */
async function movingOf(file: Blob): Promise<string | null> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (typeof ImageDecoder === "undefined") {
    if (!manyFrames(bytes)) return null;
    const url = dataUrl(bytes);
    if (url.length <= MOST_GIF) return url;
    throw new Error("too_big");
  }
  const decoder = new ImageDecoder({ data: bytes, type: "image/gif" });
  try {
    await Promise.all([decoder.tracks.ready, decoder.completed]);
    const count = Math.min(decoder.tracks.selectedTrack?.frameCount ?? 1, 300);
    if (count <= 1) return null;
    const asIs = dataUrl(bytes);
    if (asIs.length <= MOST_GIF) return asIs;
    for (const side of [SIDE, 72, 48]) {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = side;
      const g = canvas.getContext("2d", { willReadFrequently: true })!;
      g.imageSmoothingQuality = "high";
      const frames: GifFrame[] = [];
      for (let i = 0; i < count; i++) {
        const { image } = await decoder.decode({ frameIndex: i });
        const crop = Math.min(image.displayWidth, image.displayHeight);
        g.clearRect(0, 0, side, side);
        g.drawImage(image, (image.displayWidth - crop) / 2, (image.displayHeight - crop) / 2, crop, crop, 0, 0, side, side);
        frames.push({ pixels: g.getImageData(0, 0, side, side).data, delay: (image.duration ?? 100_000) / 1000 });
        image.close();
      }
      for (const step of [1, 2, 3]) {
        const url = dataUrl(gifOf(everyOther(frames, step), side));
        if (url.length <= MOST_GIF) return url;
      }
    }
    throw new Error("too_big");
  } finally {
    decoder.close();
  }
}

/** Every `step`th frame, each shown for as long as those it stands for. */
function everyOther(frames: GifFrame[], step: number): GifFrame[] {
  const out: GifFrame[] = [];
  frames.forEach((f, i) => { if (i % step === 0) out.push({ ...f }); else out[out.length - 1]!.delay += f.delay; });
  return out;
}

/** Whether a GIF has more than one frame's control block (each frame of an animation has one). */
function manyFrames(bytes: Uint8Array): boolean {
  let n = 0;
  for (let i = 0; i + 2 < bytes.length; i++) if (bytes[i] === 0x21 && bytes[i + 1] === 0xf9 && bytes[i + 2] === 4 && ++n > 1) return true;
  return false;
}

function dataUrl(gif: Uint8Array): string {
  let s = "";
  for (let i = 0; i < gif.length; i += 0x8000) s += String.fromCharCode(...gif.subarray(i, i + 0x8000));
  return `data:image/gif;base64,${btoa(s)}`;
}

/** A picture among what was pasted (a screenshot, an image copied), if any. */
export function pastedPicture(data: DataTransfer | null): File | null {
  return [...(data?.files ?? [])].find((f) => /^image\/(png|jpeg|webp|gif)$/.test(f.type)) ?? null;
}
