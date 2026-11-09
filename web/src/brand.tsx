import { useDark } from "./theme.ts";
import * as css from "./brand.css.ts";
import { NAME } from "./channel.ts";
// still.fail's brand, from web/public (design/brand/README.md): the mark (the face: the black one on light, the white
// one on dark), the wordmark and the illustrations. Mark and wordmark have -dark twins, picked by the page's 外观 like the
// rest of the app; the illustrations switch themselves.

const BASE = import.meta.env.BASE_URL;

// On the test channel (app.youdid.wtf) the name is its own, drawn the same way.
const OWN = NAME !== "still.fail";
// Each drawing's size, in still.fail's: youdid.wtf's y goes below the line, its drawing taller at the same scale.
const WORDMARK = OWN ? { name: "wordmark-beta", width: 393.41, height: 79.39 } : { name: "wordmark", width: 255.16, height: 63.13 };
const WORD_HEIGHT = 63.13;

/** A light asset and its -dark twin, as the page's 外观 has it. */
function Themed({ name, width, height, alt = "", className }: { name: string; width: number; height: number; alt?: string; className?: string | undefined }) {
  const dark = useDark();
  return <img className={className} src={`${BASE}${name}${dark ? "-dark" : ""}.svg`} alt={alt} width={width} height={height} />;
}

/** The mark, the face on its rounded square. */
export function Mark({ size, className }: { size: number; className?: string }) {
  return <Themed name="mark" width={size} height={size} className={className} />;
}

/** The name, still.fail (youdid.wtf on the test channel), `size` high as still.fail is drawn. */
export function Wordmark({ size = 22, className }: { size?: number; className?: string }) {
  const k = size / WORD_HEIGHT;
  return <Themed name={WORDMARK.name} width={Math.round(WORDMARK.width * k)} height={Math.round(WORDMARK.height * k)} alt={NAME} className={className} />;
}

type Illus = "new-chat" | "no-station" | "station-offline" | "sign-in" | "no-profile" | "no-connect";
const ILLUS_SIZE: Record<Illus, [number, number]> = {
  "new-chat": [320, 160], "no-station": [320, 160], "station-offline": [320, 160], "sign-in": [360, 200],
  "no-profile": [320, 160], "no-connect": [320, 160],
};

/**
 * The scenes, fetched and decoded as the app starts and kept: the first page to show one (a new chat) draws it in its
 * first frame, instead of an empty box that fills a moment later.
 */
const illustrationUrl = (name: Illus) => `${BASE}illus-${name}.svg`;
const decoded = (Object.keys(ILLUS_SIZE) as Illus[]).map((name) => {
  const img = new Image();
  img.src = illustrationUrl(name);
  void img.decode().catch(() => {});
  return img;
});
void decoded;

/** A scene beside text that says the same, hence no alt. */
export function Illustration({ name, ...marks }: { name: Illus; "data-made-leave"?: string }) {
  const [width, height] = ILLUS_SIZE[name];
  return <img className={css.illus} src={illustrationUrl(name)} alt="" width={width} height={height} decoding="sync" {...marks} />;
}
