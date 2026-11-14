// Two versions of one file of the agents' memory made apart, put together (share/memory.ts): what each station of a
// workspace computes alike from the same two versions, so they come to one without a station to decide.
//
// - With the version both were made from (`base`): a three-way merge by lines, as `git merge-file` makes one, where a
//   place both changed keeps both, the newer's lines first (git's `union`): a line a station's agent added is never
//   lost, and an agent that reads the file tidies what came twice.
// - Without one (two stations that kept the memory apart before it was shared): MEMORY.md's lines both, each once, a
//   line only one of them had marked with that station's name (`[ccvm] `), since nothing tells whether it is of that
//   machine alone; another file is the newer's, the other kept beside it (`conflictPath`) for an agent to merge.

/// The most lines a side of a merge may have past what the two share at their start and end: beyond it no merge is
/// tried (the newer is kept and the other beside it).
const MOST_LINES = 3000;

/// Whether `bytes` are text a merge by lines may read: UTF-8 with no NUL.
export function isText(bytes: Buffer): boolean {
  if (bytes.includes(0)) return false;
  return Buffer.from(bytes.toString("utf8"), "utf8").equals(bytes);
}

/// The pairs of lines `a` and `b` have alike (indexes, both rising), a longest such sequence; null when the lines that
/// differ are too many to compare.
export function matches(a: string[], b: string[]): [number, number][] | null {
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start++;
  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) endA--, endB--;
  const n = endA - start;
  const m = endB - start;
  if (n > MOST_LINES || m > MOST_LINES) return null;
  const out: [number, number][] = [];
  for (let i = 0; i < start; i++) out.push([i, i]);
  if (n > 0 && m > 0) {
    // lcs[i][j]: the longest of a[start+i..endA) and b[start+j..endB).
    const width = m + 1;
    const lcs = new Uint16Array((n + 1) * width);
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        lcs[i * width + j] = a[start + i] === b[start + j] ? lcs[(i + 1) * width + j + 1]! + 1 : Math.max(lcs[(i + 1) * width + j]!, lcs[i * width + j + 1]!);
      }
    }
    let i = 0;
    let j = 0;
    while (i < n && j < m) {
      if (a[start + i] === b[start + j]) {
        out.push([start + i, start + j]);
        i++, j++;
      } else if (lcs[(i + 1) * width + j]! >= lcs[i * width + j + 1]!) i++;
      else j++;
    }
  }
  for (let k = 0; endA + k < a.length; k++) out.push([endA + k, endB + k]);
  return out;
}

const same = (a: string[], b: string[]) => a.length === b.length && a.every((x, i) => x === b[i]);

/// `newer` and `older` made from `base`, merged by lines: what one changed and the other did not is taken, a place both
/// changed apart keeps both, the newer's first. Null when they are too far apart to compare.
export function merge3(base: string, newer: string, older: string): string | null {
  const b = base.split("\n");
  const w = newer.split("\n");
  const l = older.split("\n");
  const bw = matches(b, w);
  const bl = matches(b, l);
  if (bw === null || bl === null) return null;
  const inW = new Map(bw);
  const inL = new Map(bl);
  const out: string[] = [];
  let [pb, pw, pl] = [0, 0, 0];
  const chunk = (eb: number, ew: number, el: number) => {
    const cb = b.slice(pb, eb);
    const cw = w.slice(pw, ew);
    const cl = l.slice(pl, el);
    if (same(cw, cb)) out.push(...cl);
    else if (same(cl, cb) || same(cw, cl)) out.push(...cw);
    else out.push(...cw, ...cl);
  };
  for (let i = 0; i < b.length; i++) {
    const iw = inW.get(i);
    const il = inL.get(i);
    if (iw === undefined || il === undefined || iw < pw || il < pl) continue;
    chunk(i, iw, il);
    out.push(b[i]!);
    [pb, pw, pl] = [i + 1, iw + 1, il + 1];
  }
  chunk(b.length, w.length, l.length);
  return out.join("\n");
}

/// A bullet's or a line's mark of the station it came from, as `marked` writes it: `- [ccvm] …`.
const MARK = /^(\s*(?:[-*+]|\d+\.)\s+|)\[[^\]\n]{1,80}\] /;
const unmarked = (line: string) => line.replace(MARK, "$1");
/// A line worth marking: one that says something (not blank, not a heading, not the front matter's fence).
const says = (line: string) => line.trim() !== "" && !line.trimStart().startsWith("#") && line.trim() !== "---";
const marked = (line: string, station: string) => {
  if (!says(line) || unmarked(line) !== line) return line;
  const lead = /^(\s*(?:[-*+]|\d+\.)\s+|)/.exec(line)![0];
  return `${lead}[${station}] ${line.slice(lead.length)}`;
};

/// Two MEMORY.md kept apart (no version both were made from) as one: their lines in the newer's order, the other's
/// woven in after the line before them there, each line once. A line only one had is marked with that one's station
/// (`newerName`, `olderName`; null: not marked, a version of the shared memory, not a station's own of before).
export function unionLines(newer: string, older: string, newerName: string | null, olderName: string | null): string {
  const w = newer.split("\n");
  const l = older.split("\n");
  const pairs = matches(w.map(unmarked), l.map(unmarked)) ?? [];
  const out: string[] = [];
  let [pw, pl] = [0, 0];
  const take = (ew: number, el: number) => {
    for (const line of w.slice(pw, ew)) out.push(newerName === null ? line : marked(line, newerName));
    for (const line of l.slice(pl, el)) out.push(olderName === null ? line : marked(line, olderName));
  };
  for (const [iw, il] of pairs) {
    take(iw, il);
    // Had by both: no station's alone, so unmarked.
    out.push(unmarked(w[iw]!));
    [pw, pl] = [iw + 1, il + 1];
  }
  take(w.length, l.length);
  return out.join("\n");
}

/// Where a station's version of `path` is kept beside it when it could not be merged: `SKILL.md` →
/// `SKILL.conflict-<station>.md` (as the shared skills keep one, share/index.ts).
export function conflictPath(path: string, station: string): string {
  const slash = path.lastIndexOf("/");
  const dir = path.slice(0, slash + 1);
  const name = path.slice(slash + 1);
  const dot = name.lastIndexOf(".");
  const tag = stationTag(station);
  return dot > 0 ? `${dir}${name.slice(0, dot)}.conflict-${tag}${name.slice(dot)}` : `${dir}${name}.conflict-${tag}`;
}

/// A station's name as a part of a file's or a skill's name: letters, digits, `_` and `-` alone.
export const stationTag = (station: string): string => station.replace(/[^\p{L}\p{N}_-]+/gu, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "station";

/// Whether two versions made apart with none both came from are of one file still (a skill two stations each kept on):
/// half the lines of the shorter, at least, the other has too, in order, past their front matter (which every skill's
/// starts alike).
export function alike(a: string, b: string): boolean {
  const body = (t: string) => t.replace(/^---\n[\s\S]*?\n---\n?/, "");
  const la = body(a).split("\n");
  const lb = body(b).split("\n");
  const pairs = matches(la, lb);
  if (pairs === null) return false;
  const said = pairs.filter(([i]) => la[i]!.trim() !== "").length;
  const least = Math.min(la.filter((l) => l.trim() !== "").length, lb.filter((l) => l.trim() !== "").length);
  return least > 0 && said * 2 >= least;
}
