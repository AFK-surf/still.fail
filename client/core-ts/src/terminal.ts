// A command's output as a terminal shows it (a job's log, `jobs.ts`): its colour and weight codes (SGR) made into runs
// of text in one style, \r and \b moving back over what a line wrote (a progress counter written again in place) and
// erasing in a line (CSI K) done, every other control sequence and control character dropped.

/// Text in one style. `fg`/`bg`: one of the 16 colours of the client's terminal palette by number (`0`…`15`, for its
/// theme), or `#rrggbb`; absent: the text's own colour, no background.
export type TermRun = { text: string; fg?: string; bg?: string; bold?: true; dim?: true; italic?: true; underline?: true };

type Style = Omit<TermRun, "text">;
type Cell = { ch: string; style: Style };

const PLAIN: Style = {};

/// The text as shown and its runs; `runs` absent when nothing in it is styled.
export function terminal(text: string): { text: string; runs?: TermRun[] } {
  const lines: Cell[][] = [];
  let line: Cell[] = [];
  let col = 0;
  let style = PLAIN;
  const put = (ch: string) => {
    while (line.length < col) line.push({ ch: " ", style: PLAIN });
    line[col++] = { ch, style };
  };
  const chars = Array.from(text);
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (c === "\n") {
      lines.push(line);
      line = [];
      col = 0;
    } else if (c === "\r") col = 0;
    else if (c === "\b") col = Math.max(0, col - 1);
    else if (c === "\t") put(c);
    else if (c === "\u001b") {
      const next = chars[i + 1];
      if (next === "[") {
        let j = i + 2;
        while (j < chars.length && !/[@-~]/.test(chars[j])) j++;
        if (j >= chars.length) break;
        const params = chars.slice(i + 2, j).join("");
        if (/^[\d;:]*$/.test(params)) {
          if (chars[j] === "m") style = sgr(style, params);
          else if (chars[j] === "K") {
            const mode = params === "" ? 0 : Number(params);
            if (mode === 0) line.length = Math.min(line.length, col);
            else if (mode === 1) for (let k = 0; k < Math.min(col + 1, line.length); k++) line[k] = { ch: " ", style: PLAIN };
            else if (mode === 2) line = [];
          }
        }
        i = j;
      } else if (next === "]" || next === "P" || next === "X" || next === "^" || next === "_") {
        // A string to its end: BEL, or ESC \.
        let j = i + 2;
        while (j < chars.length && chars[j] !== "\u0007" && !(chars[j] === "\u001b" && chars[j + 1] === "\\")) j++;
        i = chars[j] === "\u001b" ? j + 1 : j;
      } else {
        // ESC, its intermediates (ESC ( B), its final.
        let j = i + 1;
        while (j < chars.length && /[ -/]/.test(chars[j])) j++;
        i = j;
      }
    } else if (c < " " || c === "\u007f" || (c >= "\u0080" && c <= "\u009f")) continue;
    else put(c);
  }
  if (line.length > 0 || lines.length > 0) lines.push(line);

  const runs: TermRun[] = [];
  let styled = false;
  const add = (ch: string, s: Style) => {
    const last = runs.at(-1);
    if (last && (ch === "\n" || same(last, s))) last.text += ch;
    else {
      runs.push({ text: ch, ...s });
      if (s !== PLAIN) styled = true;
    }
  };
  lines.forEach((cells, n) => {
    if (n > 0) add("\n", PLAIN);
    for (const cell of cells) add(cell.ch, cell.style);
  });
  const shown = runs.map((r) => r.text).join("");
  return styled ? { text: shown, runs } : { text: shown };
}

function same(a: Style, b: Style): boolean {
  return a.fg === b.fg && a.bg === b.bg && a.bold === b.bold && a.dim === b.dim && a.italic === b.italic && a.underline === b.underline;
}

/// The style after a Select Graphic Rendition's parameters (`1;38;5;2`, `38:2::255:0:0`).
function sgr(from: Style, params: string): Style {
  const s: Style = { ...from };
  const ps = params === "" ? ["0"] : params.split(";");
  for (let i = 0; i < ps.length; i++) {
    const sub = ps[i].split(":");
    const p = sub[0] === "" ? 0 : Number(sub[0]);
    if (p === 38 || p === 48) {
      let color: string | undefined;
      if (sub.length > 1) color = extended(sub.slice(1).map(Number));
      else {
        const kind = Number(ps[i + 1]);
        const n = kind === 5 ? 1 : kind === 2 ? 3 : 0;
        color = extended(ps.slice(i + 1, i + 2 + n).map(Number));
        i += 1 + n;
      }
      if (color !== undefined) s[p === 38 ? "fg" : "bg"] = color;
      else delete s[p === 38 ? "fg" : "bg"];
    } else if (p === 0) for (const k of Object.keys(s) as (keyof Style)[]) delete s[k];
    else if (p === 1) s.bold = true;
    else if (p === 2) s.dim = true;
    else if (p === 3) s.italic = true;
    else if (p === 4) s.underline = true;
    else if (p === 22) {
      delete s.bold;
      delete s.dim;
    }
    else if (p === 23) delete s.italic;
    else if (p === 24) delete s.underline;
    else if (p >= 30 && p <= 37) s.fg = String(p - 30);
    else if (p === 39) delete s.fg;
    else if (p >= 40 && p <= 47) s.bg = String(p - 40);
    else if (p === 49) delete s.bg;
    else if (p >= 90 && p <= 97) s.fg = String(p - 90 + 8);
    else if (p >= 100 && p <= 107) s.bg = String(p - 100 + 8);
  }
  return Object.keys(s).length === 0 ? PLAIN : s;
}

/// A colour after 38/48: `5;n` (of 256) or `2;r;g;b` (in the colon form `2::r:g:b` too).
function extended(p: number[]): string | undefined {
  const byte = (n: number | undefined) => (n !== undefined && Number.isInteger(n) && n >= 0 && n <= 255 ? n : undefined);
  if (p[0] === 5) {
    const n = byte(p[1]);
    return n === undefined ? undefined : n < 16 ? String(n) : hex(...xterm(n));
  }
  if (p[0] === 2) {
    const [r, g, b] = p.slice(-3).map(byte);
    return p.length >= 4 && r !== undefined && g !== undefined && b !== undefined ? hex(r, g, b) : undefined;
  }
  return undefined;
}

/// xterm's 256 colours past the first 16: a 6×6×6 cube, then 24 greys.
function xterm(n: number): [number, number, number] {
  if (n >= 232) {
    const v = 8 + (n - 232) * 10;
    return [v, v, v];
  }
  const level = (k: number) => (k === 0 ? 0 : 55 + k * 40);
  const k = n - 16;
  return [level(Math.floor(k / 36)), level(Math.floor(k / 6) % 6), level(k % 6)];
}

const hex = (r: number, g: number, b: number) => `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
