// The faces a device's pages are set in (docs/fonts.md): three places, each its own choice (`prefs.set {fonts: {…}}`):
// ui, the app's own words; text, what people and agents wrote (messages, the composer); code. None chosen: the app's
// own face (text: as ui). Beside the system's: the faces still.fail keeps in the releases bucket (scripts/fonts.py makes
// them, fonts/<id>/<version>/), and on a computer one installed there (`local:<family>`, the page lists them).
import { current } from "./i18n.ts";

export const PLACES = ["ui", "text", "code"] as const;
// Not util.ts's isObject: the web reads this file itself (its demo, its stories), under its stricter settings.
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
export type Place = (typeof PLACES)[number];

/// A face's file for the Android app: a weight (0: one variable file for all), gzipped, its size so and the hash of it
/// unzipped.
type File = { weight: number; file: string; bytes: number; sha256: string };
type Entry = { id: string; version: string; zh: string; en: string; mono: boolean; family: string; files: File[]; preview?: string };

/// What scripts/fonts.py made and put (its output, as printed).
const FACES: Entry[] = [
  { id: "inter", version: "4.001", zh: "Inter", en: "Inter", mono: false, family: "SF Inter", preview: "preview-194fa287.ttf", files: [
    { weight: 0, file: "var.ttf.gz", bytes: 457818, sha256: "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031" },
  ] },
  { id: "noto-sans-sc", version: "2.004", zh: "思源黑体", en: "Noto Sans SC", mono: false, family: "SF Noto Sans SC", preview: "preview-f0494178.ttf", files: [
    { weight: 0, file: "var.ttf.gz", bytes: 11276563, sha256: "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da" },
  ] },
  { id: "noto-serif-sc", version: "2.003", zh: "思源宋体", en: "Noto Serif SC", mono: false, family: "SF Noto Serif SC", preview: "preview-001bbedf.ttf", files: [
    { weight: 0, file: "var.ttf.gz", bytes: 15454579, sha256: "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9" },
  ] },
  { id: "lxgw-wenkai", version: "1.530", zh: "霞鹜文楷", en: "LXGW WenKai", mono: false, family: "SF LXGW WenKai", preview: "preview-d3505af4.ttf", files: [
    { weight: 400, file: "400.ttf.gz", bytes: 12904482, sha256: "2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b" },
    { weight: 500, file: "500.ttf.gz", bytes: 13272430, sha256: "f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a" },
  ] },
  { id: "jetbrains-mono", version: "2.211", zh: "JetBrains Mono", en: "JetBrains Mono", mono: true, family: "SF JetBrains Mono", preview: "preview-ee73078f.ttf", files: [
    { weight: 0, file: "var.ttf.gz", bytes: 90579, sha256: "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda" },
  ] },
  { id: "fira-code", version: "5.002", zh: "Fira Code", en: "Fira Code", mono: true, family: "SF Fira Code", preview: "preview-555be27a.ttf", files: [
    { weight: 0, file: "var.ttf.gz", bytes: 137151, sha256: "9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb" },
  ] },
  { id: "maple-mono", version: "7.9", zh: "Maple Mono", en: "Maple Mono", mono: true, family: "SF Maple Mono CN", preview: "preview-cffdf246.ttf", files: [
    { weight: 400, file: "400.ttf.gz", bytes: 8352545, sha256: "0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085" },
    { weight: 600, file: "600.ttf.gz", bytes: 8438132, sha256: "96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677" },
  ] },
];

/// A family installed on the device, as the page names it.
const LOCAL = "local:";
const LOCAL_MAX = 120;

let origin = "";

/// Where the faces are fetched from: the cloud's (its /releases/), set as the core starts.
export function setOrigin(cloud: string): void {
  origin = cloud.replace(/\/+$/, "");
}

/// Where this device keeps a face's file, by its hash, as a file the app's host reads there itself (font-files.ts):
/// set as the core starts; none before (and on the web, whose pages fetch the faces themselves).
let keptAt: (sha256: string) => string | null = () => null;

export function setKeptAt(at: (sha256: string) => string | null): void {
  keptAt = at;
}

/// A choice as kept: a face there is, or one of the device's; anything else is none.
function known(v: unknown): string | null {
  if (typeof v !== "string") return null;
  if (v.startsWith(LOCAL)) return v.length > LOCAL.length && v.length <= LOCAL_MAX ? v : null;
  return FACES.some((f) => f.id === v) ? v : null;
}

/// What is kept (`fonts`): each place's face, only those known.
export function choicesOf(v: unknown): Record<Place, string | null> {
  const r = isObject(v) ? v : {};
  return { ui: known(r.ui), text: known(r.text), code: known(r.code) };
}

/// What is kept as it goes out: the places chosen.
export function chosen(v: unknown): Record<string, string> {
  return Object.fromEntries(Object.entries(choicesOf(v)).filter(([, id]) => id !== null)) as Record<string, string>;
}

/// A change to what is kept: what is said changes (null: back to none), the rest stays; what is not known is an error.
export function put(kept: unknown, patch: Record<string, unknown>): Record<string, string> | string {
  const now = choicesOf(kept);
  for (const [place, v] of Object.entries(patch)) {
    if (!(PLACES as readonly string[]).includes(place)) return place;
    if (v !== null && known(v) === null) return place;
    now[place as Place] = v === null ? null : (v as string);
  }
  return chosen(now);
}

function face(e: Entry): Record<string, unknown> {
  const base = `${origin}/releases/fonts/${e.id}/${e.version}`;
  return {
    id: e.id,
    name: current() === "zh" ? e.zh : e.en,
    mono: e.mono,
    family: e.family,
    css: `${base}/font.css`,
    ...(e.preview ? { preview: `${base}/${e.preview}` } : {}),
    files: e.files.map((f) => ({ weight: f.weight, url: `${base}/${f.file}`, bytes: f.bytes, sha256: f.sha256 })),
    bytes: e.files.reduce((n, f) => n + f.bytes, 0),
  };
}

/// A face still.fail keeps, by its id, as a device fetches it: each file's address, size and hash, and its preview's.
export type FaceFiles = { files: { weight: number; url: string; bytes: number; sha256: string }[]; bytes: number; preview?: string };

export function faceOf(id: string): FaceFiles | null {
  const e = FACES.find((f) => f.id === id);
  if (!e) return null;
  const f = face(e);
  return { files: f.files as FaceFiles["files"], bytes: f.bytes as number, ...(typeof f.preview === "string" ? { preview: f.preview } : {}) };
}

const OWN = { id: "", name: "", mono: false, family: "", files: [], bytes: 0 };

function resolve(id: string | null, place: Place): Record<string, unknown> {
  if (id?.startsWith(LOCAL)) {
    const family = id.slice(LOCAL.length);
    return { id, name: family, mono: place === "code", family, files: [], bytes: 0 };
  }
  const e = FACES.find((f) => f.id === id);
  if (!e) return { ...OWN, mono: place === "code" };
  // a place's: each file where this device keeps it, so the app sets its pages in it as it starts, asking nothing
  const f = face(e);
  const files = (f.files as Record<string, unknown>[]).map((file) => {
    const path = keptAt(file.sha256 as string);
    return path === null ? file : { ...file, path };
  });
  return { ...f, files };
}

/// The faces as they go out (`faces`): each place's, whole (text, none chosen: as ui; each file's `path` where the
/// device keeps it), and every face there is.
export function shown(kept: unknown): Record<string, unknown> {
  const c = choicesOf(kept);
  const ui = resolve(c.ui, "ui");
  return {
    ui,
    text: c.text === null ? ui : resolve(c.text, "text"),
    code: resolve(c.code, "code"),
    list: FACES.map(face),
  };
}
