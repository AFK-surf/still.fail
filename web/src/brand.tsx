import { useDark } from "./theme.ts";
// ember's brand, from web/public (see the brand package's brand.md): the station
// buddy mark, the lockup and the illustrations. Marks and lockup have -dark twins,
// picked by the OS theme like the rest of the app; the illustrations switch themselves.

const BASE = import.meta.env.BASE_URL;

/** A light asset and its -dark twin, as the page's 外观 has it. */
function Themed({ name, width, height, alt = "", className }: { name: string; width: number; height: number; alt?: string; className?: string | undefined }) {
  const dark = useDark();
  return <img className={className} src={`${BASE}${name}${dark ? "-dark" : ""}.svg`} alt={alt} width={width} height={height} />;
}

/** The buddy: the simplified 16-grid drawing up to 16 px, the full one from 22 px. */
export function Mark({ size, className }: { size: number; className?: string }) {
  return <Themed name={size <= 16 ? "mark-16" : "mark"} width={size} height={size} className={className} />;
}

/** Buddy and name; 132 × 30 at the smallest. */
export function Lockup({ height = 30, alt = "ember" }: { height?: number; alt?: string }) {
  return <Themed name="lockup" width={Math.round((height * 264) / 60)} height={height} alt={alt} className="brand-lockup" />;
}

type Illus = "new-chat" | "no-station" | "station-offline" | "sign-in";
const ILLUS_SIZE: Record<Illus, [number, number]> = {
  "new-chat": [320, 160], "no-station": [320, 160], "station-offline": [320, 160], "sign-in": [360, 200],
};

/** A scene beside text that says the same, hence no alt. */
export function Illustration({ name }: { name: Illus }) {
  const [width, height] = ILLUS_SIZE[name];
  return <img className="illus" src={`${BASE}illus-${name}.svg`} alt="" width={width} height={height} />;
}
