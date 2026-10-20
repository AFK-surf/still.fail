// A folder's names as a viewer reads them: in their numbers' order, and the subtitle beside a video.

/** Names with their numbers compared as numbers: E2 before E10 (the playlist's order, as the station lists them). */
export function compareNatural(a: string, b: string): number {
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
}

/**
 * The subtitle beside a video, of the names in its folder: `E01.srt` (or `E01.mp4.srt`) first, then one with a tag
 * (`E01.zh.srt`); .srt before .vtt before .ass. None: null.
 */
export function sideSubtitle(video: string, names: readonly string[]): string | null {
  const exts = ["srt", "vtt", "ass", "ssa"];
  const stem = video.includes(".") ? video.slice(0, video.lastIndexOf(".")) : video;
  const stems = [...new Set([video, stem])];
  let best: { name: string; score: number[] } | null = null;
  for (const name of names) {
    const lower = name.toLowerCase();
    const found = stems.find((s) => lower.startsWith(`${s.toLowerCase()}.`));
    if (found === undefined) continue;
    const ext = lower.slice(lower.lastIndexOf(".") + 1);
    const rank = exts.indexOf(ext);
    if (rank < 0) continue;
    const tag = name.slice(found.length);
    const score = [tag.length === ext.length + 1 ? 0 : 1, found === video ? 0 : 1, rank, tag.length];
    if (!best || before(score, best.score) || (!before(best.score, score) && name < best.name)) best = { name, score };
  }
  return best?.name ?? null;
}

/** Whether one score comes before another, its first differing number the smaller. */
function before(a: readonly number[], b: readonly number[]): boolean {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i]! < b[i]!;
  return false;
}
