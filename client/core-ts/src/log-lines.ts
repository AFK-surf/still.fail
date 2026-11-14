// A job's log a line at a time (the `jobLog` topic, jobs.ts `log`), each line with a number of its own that stays
// its own as the log grows: the topic's lines are keyed by it (collections.ts), so a line more goes out as that line,
// the first gone where the log was at its most a drop, the last written again a patch. The station gives no numbers:
// it sends its log's last lines whole each time the log grows (station/src/read/jobs.ts `tail`, 64 KB of its end at
// most), so they are given here, where the link keeps what it said last (station/link.ts `logKey`): by where the lines
// it says now overlap those it said before (`firstNumber`), the first line's number kept beside them (`Logged.from`).
import { type TermRun, terminalLines } from "./terminal.ts";

/// A line of a job's log as it goes out: its number (`n`) and its runs of one style.
export type LogLine = { n: number; runs: TermRun[] };

/// A job's log as the link's memory keeps it: as its station said it last, and the number its first line has.
export type Logged = { text: string; outputAt: unknown; from: number };

/// The latest few logs' lines as shown (terminal.ts), by their text: what numbers a log as it comes (`logged`) and what
/// shows it (jobs.ts `log`) work out each once.
const KEPT = 8;
const kept = new Map<string, TermRun[][]>();

/// `text`'s lines as a terminal shows them, each its runs (terminal.ts `terminalLines`); read-only, as kept.
export function linesOf(text: string): TermRun[][] {
  const had = kept.get(text);
  if (had !== undefined) {
    kept.delete(text);
    kept.set(text, had);
    return had;
  }
  const lines = terminalLines(text);
  kept.set(text, lines);
  if (kept.size > KEPT) kept.delete(kept.keys().next().value!);
  return lines;
}

const words = (line: TermRun[]) => line.map((r) => r.text).join("");
const same = (a: TermRun[], b: TermRun[]) => a.length === b.length && JSON.stringify(a) === JSON.stringify(b);
/// What the station reads of a log beginning within a line (its last 64 KB from wherever they begin) leaves of it: its
/// words from there, a character cut through made U+FFFD by its decoding.
const cutOf = (whole: TermRun[], cut: TermRun[]) => {
  const w = words(cut).replace(/^�+/, "");
  return w !== "" && words(whole).endsWith(w);
};

/// The number the first of `next`'s lines has, given the lines said before of the same log (`old`, its first line's
/// number `from`; none: the first read). Where the old lines from some line on are the new ones' first, those keep
/// their numbers and the rest count on from them, the most of them kept that can be: one line each the same, but for
/// the first of the new, which may be what is left of the old one where the station's read begins inside it, and the
/// last of the old, which may have been written again (a progress bar's, \r) or finished since, and goes on with its
/// number; where all that overlaps is that last line, it is the same, or begun as it was. None overlapping (the log
/// begun again, or all of it new), the new lines are numbered on from the last old one.
export function firstNumber(old: { from: number; lines: TermRun[][] } | null, next: TermRun[][]): number {
  if (old === null) return 0;
  const was = old.lines;
  const n = was.length;
  for (let i = 0; i < n; i++) {
    const k = n - i;
    if (next.length < k) continue;
    let ok = true;
    for (let j = 0; j < k && ok; j++) {
      const a = was[i + j]!;
      const b = next[j]!;
      if (same(a, b)) continue;
      if (k === 1) ok = words(a) !== "" && words(b).startsWith(words(a));
      else if (j === k - 1) continue;
      else ok = j === 0 && cutOf(a, b);
    }
    if (ok) return old.from + i;
  }
  return old.from + n;
}

/// What the link keeps of a job's log as its station says it now (`text`, `outputAt`), after what it kept of it before
/// (`was`: a `Logged`, one kept by a core before numbers, without its `from`, or none).
export function logged(was: unknown, text: string, outputAt: unknown): Logged {
  const before = was !== null && typeof was === "object" && typeof (was as Logged).text === "string" ? (was as Logged) : null;
  const old = before === null ? null : { from: typeof before.from === "number" ? before.from : 0, lines: linesOf(before.text) };
  return { text, outputAt, from: firstNumber(old, linesOf(text)) };
}
