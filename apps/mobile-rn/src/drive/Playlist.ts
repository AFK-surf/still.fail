// What plays after what in a folder of a drive, and which subtitle goes with a video (drive/Playlist.kt, zdrive's
// Playlist.kt and SideSubtitles.kt): plain functions over names.

const isDigit = (c: string) => /\p{Nd}/u.test(c);

/** The playable names of a folder in the order a person would watch them: numbers as numbers (E2 before E10). */
export function playlistOf(names: readonly string[], playable: (name: string) => boolean): string[] {
  return [...new Set(names.filter(playable))].sort(compareNatural);
}

/** What follows `current` in `list`, or null at its end; one missing from the list still has a place by its name. */
export function nextIn(current: string, list: readonly string[]): string | null {
  const at = list.indexOf(current);
  return at >= 0 ? (list[at + 1] ?? null) : (list.find((it) => compareNatural(it, current) > 0) ?? null);
}

/** Kotlin's String.compareTo: by UTF-16 unit, the difference where they part, else of their lengths. */
function compareTo(a: string, b: string): number {
  const n = Math.min(a.length, b.length);
  for (let k = 0; k < n; k++) {
    const d = a.charCodeAt(k) - b.charCodeAt(k);
    if (d !== 0) return d;
  }
  return a.length - b.length;
}

/** Names with their numbers compared as numbers: `E2` before `E10`. */
export function compareNatural(a: string, b: string): number {
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const ca = a[i]!;
    const cb = b[j]!;
    if (isDigit(ca) && isDigit(cb)) {
      const startA = i;
      const startB = j;
      while (i < a.length && isDigit(a[i]!)) i++;
      while (j < b.length && isDigit(b[j]!)) j++;
      const numA = a.substring(startA, i).replace(/^0+/, "");
      const numB = b.substring(startB, j).replace(/^0+/, "");
      if (numA.length !== numB.length) return numA.length - numB.length;
      const digits = compareTo(numA, numB);
      if (digits !== 0) return digits;
    } else {
      const chars = ca.toLowerCase().charCodeAt(0) - cb.toLowerCase().charCodeAt(0);
      if (chars !== 0) return chars;
      i++;
      j++;
    }
  }
  const rest = (a.length - i) - (b.length - j);
  return rest !== 0 ? rest : compareTo(a, b);
}

/** Best first: `.srt` is what such files usually come with. */
const SUBTITLE_EXTENSIONS = ["srt", "vtt", "ass", "ssa"];

interface Candidate { name: string; exact: boolean; full: boolean; rank: number; tag: string }

/**
 * The subtitle for the video `base`, out of the names beside it: `<base>.<ext>` or `<stem>.<ext>` (E01.srt for E01.mp4)
 * first, then one with a tag between (`E01.zh.srt`), the whole name winning a tie.
 */
export function pickSubtitle(base: string, names: readonly string[]): string | null {
  const dot = base.lastIndexOf(".");
  const stems = [...new Set([base, dot >= 0 ? base.substring(0, dot) : base])];
  const candidates: Candidate[] = [];
  for (const name of names) {
    const stem = stems.find((it) => name.toLowerCase().startsWith(`${it}.`.toLowerCase()));
    if (stem === undefined) continue;
    const extension = name.substring(name.lastIndexOf(".") + 1).toLowerCase();
    const rank = SUBTITLE_EXTENSIONS.indexOf(extension);
    if (rank < 0) continue;
    const tag = name.substring(stem.length);
    candidates.push({ name, exact: tag.length === extension.length + 1, full: stem === base, rank, tag });
  }
  const order = (x: Candidate, y: Candidate) =>
    Number(!x.exact) - Number(!y.exact) || Number(!x.full) - Number(!y.full) || x.rank - y.rank || compareTo(x.tag, y.tag);
  let best: Candidate | null = null;
  for (const c of candidates) if (best === null || order(c, best) < 0) best = c;
  return best?.name ?? null;
}

/** A speed as it is shown: 1×, 1.5×, 0.75×. */
export function speedLabel(speed: number): string {
  return `${String(speed)}×`;
}

const pad2 = (n: number) => String(n).padStart(2, "0");

/** `m:ss`, or `h:mm:ss` past an hour. */
export function clock(ms: number): string {
  const total = Math.trunc((Math.max(0, ms) + 500) / 1000);
  const h = Math.trunc(total / 3600);
  const m = Math.trunc((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${h}:${pad2(m)}:${pad2(s)}` : `${m}:${pad2(s)}`;
}
