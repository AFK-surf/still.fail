// A job's output in a terminal's colours (the web's TermText.tsx, as the core says its runs): for both frames.

///|
/// A terminal's 16 colours, light and dark (TermInk.kt, as the web's TermText.tsx), RRGGBBAA.
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
/// A run's colour (TermInk.kt termColor): one of the palette's by number, or #rrggbb; 0 none.
pub fn term_color(c : String, dark : Bool) -> Int64 {
  if c.has_prefix("#") && c.length() == 7 {
    let mut v = 0L
    for ch in c.view(start_offset=1) {
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
/// A job's output in its styles a line at a time (TermInk.kt termText): each run in its colours, bold, italic and
/// underlined as said; a dim one its colour (or the words') faded.
pub fn term_lines(runs : Array[Json], ink : Int64, dark : Bool) -> Array[Array[@ui.Run]] {
  let out : Array[Array[@ui.Run]] = [[]]
  for r in runs {
    let rv = Some(r)
    let fg = term_color(text(rv, "fg"), dark)
    let color = if flag(rv, "dim") { @sf.alpha(if fg != 0L { fg } else { ink }, 0.6) } else { fg }
    let bg = term_color(text(rv, "bg"), dark)
    let pieces = text(rv, "text").split("\n").map(fn(p) { p.to_owned() }).to_array()
    for k, piece in pieces {
      if k > 0 {
        out.push([])
      }
      if piece != "" {
        out[out.length() - 1].push(
          @ui.span(
            piece,
            mono=true,
            color~,
            bg~,
            weight=if flag(rv, "bold") { 600 } else { 0 },
            italic=flag(rv, "italic"),
            underline=flag(rv, "underline"),
          ),
        )
      }
    }
  }
  // (an empty line still one: a run to stand in for its words)
  out.map(fn(l) { if l.length() == 0 { [@ui.span(" ", mono=true)] } else { l } })
}


///|
/// Job `job`'s output on `station`, its last `lines` lines as the core's `jobLog` topic gives them, a line at a time:
/// in a terminal's colours where the core says them (its `runs`: term_lines, on `ink`, `dark` or not), else as words;
/// worked out once for each version of it and each ink. None while it has not been read; none where the job wrote
/// nothing.
pub fn job_output_lines(
  src : Source,
  station : String,
  job : String,
  lines : Double,
  ink : Int64,
  dark : Bool,
) -> Array[Array[@ui.Run]]? {
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "job": Json::string(job),
    "lines": Json::number(lines),
  }
  let topic = (src.topic)("jobLog", params)
  match topic.value {
    Some(Object(_)) as v =>
      Some(
        job_outputs.get(Json::object(params).stringify(), "\{topic.version} \{ink} \{dark}", fn() {
          let words = text(v, "text")
          let runs = items(v, "runs")
          if words == "" {
            []
          } else if runs.length() > 0 {
            term_lines(runs, ink, dark)
          } else {
            words.split("\n").map(fn(l) { [@ui.span(l.to_owned(), mono=true)] }).to_array()
          }
        }),
      )
    _ => None
  }
}

///|
/// Each job's output as its lines' runs (job_output_lines).
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let job_outputs : Memo[Array[Array[@ui.Run]]] = Memo::new()
