// A job's output in a terminal's colours (as the core says its runs): for both frames.

///|
/// A terminal's 16 colours, light and dark, RRGGBBAA.
// kept across runs: a table, never written
let term_light : Array[Int64] = [
  0x000000FFL, 0xCD3131FFL, 0x00BC00FFL, 0x949800FFL, 0x0451A5FFL, 0xBC05BCFFL, 0x0598BCFFL, 0x555555FFL, 0x666666FFL,
  0xCD3131FFL, 0x14CE14FFL, 0xB5BA00FFL, 0x0451A5FFL, 0xBC05BCFFL, 0x0598BCFFL, 0xA5A5A5FFL,
]

///|
// kept across runs: a table, never written
let term_dark : Array[Int64] = [
  0x6E6E6EFFL, 0xCD3131FFL, 0x0DBC79FFL, 0xE5E510FFL, 0x2472C8FFL, 0xBC3FBCFFL, 0x11A8CDFFL, 0xE5E5E5FFL, 0x8A8A8AFFL,
  0xF14C4CFFL, 0x23D18BFFL, 0xF5F543FFL, 0x3B8EEAFFL, 0xD670D6FFL, 0x29B8DBFFL, 0xE5E5E5FFL,
]

///|
/// A run's colour: one of the palette's by number, or #rrggbb; 0 none.
pub fn term_color(c : String, dark : Bool) -> Int64 {
  if c.has_prefix("#") && c.length() == 7 {
    let mut v = 0L
    for ch in c.exact_view(start=1) {
      let d = match ch {
        '0'..='9' => ch.to_int() - '0'.to_int()
        'a'..='f' => ch.to_int() - 'a'.to_int() + 10
        'A'..='F' => ch.to_int() - 'A'.to_int() + 10
        _ => return 0L
      }
      v = v * 16L + d.to_int64()
    }
    return (v << 8) | 0xFFL
  }
  let mut n = 0
  if c == "" {
    return 0L
  }
  for ch in c {
    if ch < '0' || ch > '9' {
      return 0L
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  if n > 15 {
    0L
  } else if dark {
    term_dark[n]
  } else {
    term_light[n]
  }
}

///|
/// A line of a job's output in its styles: each run in its colours, bold, italic and underlined as said; a dim one its
/// colour (or the words') faded; an empty line a run to stand in for its words.
pub fn term_line(runs : Array[Json], ink : Int64, dark : Bool) -> Array[@ui.Run] {
  let out : Array[@ui.Run] = []
  for r in runs {
    let rv = Some(r)
    let words = text(rv, "text")
    if words == "" {
      continue
    }
    let fg = term_color(text(rv, "fg"), dark)
    let color = if flag(rv, "dim") { @sf.alpha(if fg != 0L { fg } else { ink }, 0.6) } else { fg }
    let bg = term_color(text(rv, "bg"), dark)
    out.push(
      @ui.span(
        words,
        mono=true,
        color~,
        bg~,
        weight=if flag(rv, "bold") { 600 } else { 0 },
        italic=flag(rv, "italic"),
        underline=flag(rv, "underline"),
      ),
    )
  }
  if out.length() == 0 {
    [@ui.span(" ", mono=true)]
  } else {
    out
  }
}

///|
/// A line of a job's output as it is drawn: its number (the core's `n`, the key it is drawn by), the line as the core
/// gave it (the same JSON while it is unchanged: the core's keyed ops keep it), its runs (term_line).
pub(all) struct TermLine {
  n : Int
  line : Json
  runs : Array[@ui.Run]
}

///|
/// A job's output a line at a time, the oldest first.
pub(all) struct TermLines {
  lines : Array[TermLine]
}

///|
/// The line numbered `n`, if it is there: where its numbers, one after another, put it, else looked for.
pub fn TermLines::at(self : TermLines, n : Int) -> TermLine? {
  guard self.lines.length() > 0 else { return None }
  let i = n - self.lines[0].n
  if i >= 0 && i < self.lines.length() && self.lines[i].n == n {
    return Some(self.lines[i])
  }
  for l in self.lines {
    if l.n == n {
      return Some(l)
    }
  }
  None
}

///|
/// Job `job`'s output on `station`, its last `lines` lines as the core's `jobLog` topic gives them, each by its number,
/// in a terminal's colours (job_output_of), held for the station's jobs (hold). None while it has not been read.
pub fn job_output_lines(
  src : Source,
  station : String,
  job : String,
  lines : Double,
  ink : Int64,
  dark : Bool,
) -> TermLines? {
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "job": Json::string(job),
    "lines": Json::number(lines),
  }
  guard hold(src, jobs_scope(station), "jobLog", params).get().value is Some(Object(_)) else { return None }
  Some(job_output_of(src, params, ink, dark))
}

///|
/// The core's `jobLog` asked with `params` a line at a time, each by its number, in a terminal's colours (term_line, on
/// `ink`, `dark` or not). Each line's runs are worked out as it comes and kept while it is the same line (the same JSON:
/// the core's keyed ops keep a line they do not touch), so a line more works out that line alone (a computed for each
/// output and ink: derived.mbt). Read where the topic is held.
pub fn job_output_of(src : Source, params : Map[String, Json], ink : Int64, dark : Bool) -> TermLines {
  let key = Json::object(params).stringify() + "\u{1}" + ink.to_string() + "\u{1}" + dark.to_string()
  job_outputs.read(src, key, fn(was) {
    let v = src.topic("jobLog", params).get().value
    let made = items(v, "lines").map(fn(l) {
      let n = number(Some(l), "n").to_int()
      match was.bind(fn(w) { w.at(n) }) {
        Some(t) if physical_equal(t.line, l) => t
        _ => { n, line: l, runs: term_line(items(Some(l), "runs"), ink, dark) }
      }
    })
    { lines: made }
  })
}

///|
/// Each job's output as its lines (job_output_of), by the ink they were coloured on.
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let job_outputs : Kept[TermLines] = Kept::new()
