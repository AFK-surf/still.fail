// A video's subtitle beside it (E01.srt for E01.mp4), read here and shown by the player over the picture: SubRip,
// WebVTT and ASS/SSA's dialogue lines (Player.kt hands the file to media3 with the film; here the app reads it, so every
// host shows it alike). Styling is left out (tags, ASS's overrides), the words and their lines kept.

///|
/// A line of a subtitle: from when to when (ms), its words (lines apart by \n).
pub(all) struct Cue {
  from : Double
  to : Double
  text : String
}

///|
/// The cues of a subtitle file `name` (its kind by its extension) in `bytes` (UTF-8, a byte order mark dropped).
pub fn parse_subtitles(name : String, bytes : Bytes) -> Array[Cue] {
  let text = @utf8.decode_lossy(bytes[:], ignore_bom=true)
  let text = text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
  match extension_of(name) {
    "ass" | "ssa" => parse_ass(text)
    _ => parse_timed(text)
  }
}

///|
/// SubRip and WebVTT: blocks apart by blank lines, each with a `from --> to` line and its words under it.
pub fn parse_timed(text : String) -> Array[Cue] {
  let out : Array[Cue] = []
  let lines = text.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    match line.find("-->") {
      Some(at) => {
        let a = line.view(end_offset=at).to_owned().trim().to_owned()
        // WebVTT's settings after the time (align:start …)
        let rest = line.view(start_offset=at + 3).to_owned().trim().to_owned()
        let b = match rest.find(" ") {
          Some(k) => rest.view(end_offset=k).to_owned()
          None => rest
        }
        i += 1
        let words : Array[String] = []
        while i < lines.length() && lines[i].trim().to_owned() != "" {
          words.push(strip_tags(lines[i]))
          i += 1
        }
        match (time_of(a), time_of(b)) {
          (Some(f), Some(t)) if words.length() > 0 =>
            out.push({ from: f, to: t, text: words.join("\n") })
          _ => ()
        }
      }
      None => i += 1
    }
  }
  out
}

///|
/// ASS/SSA: the [Events] section's Dialogue lines, read by its Format line (Start, End, Text the last field, which may
/// hold commas); {\…} overrides dropped, \N a new line, \h a space.
pub fn parse_ass(text : String) -> Array[Cue] {
  let out : Array[Cue] = []
  let mut events = false
  let mut fields : Array[String] = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
  for raw in text.split("\n") {
    let line = raw.to_owned().trim().to_owned()
    if line.has_prefix("[") {
      events = line.to_lower() == "[events]"
      continue
    }
    if !events {
      continue
    }
    if line.to_lower().has_prefix("format:") {
      fields = line
        .view(start_offset=7)
        .to_owned()
        .split(",")
        .map(fn(f) { f.to_owned().trim().to_owned().to_lower() })
        .to_array()
      continue
    }
    if !line.to_lower().has_prefix("dialogue:") {
      continue
    }
    let body = line.view(start_offset=9).to_owned()
    let n = fields.length()
    // the first n - 1 fields, then the text whole
    let parts : Array[String] = []
    let mut from = 0
    let chars = body.to_array()
    for k, ch in chars {
      if ch == ',' && parts.length() < n - 1 {
        parts.push(String::from_array(chars[from:k]).trim().to_owned())
        from = k + 1
      }
    }
    parts.push(String::from_array(chars[from:]))
    let get = fn(key : String) -> String {
      match fields.search(key) {
        Some(k) if k < parts.length() => parts[k]
        _ => ""
      }
    }
    let words = ass_words(get("text"))
    match (time_of(get("start")), time_of(get("end"))) {
      (Some(f), Some(t)) if words != "" => out.push({ from: f, to: t, text: words })
      _ => ()
    }
  }
  out.sort_by(fn(a, b) { a.from.compare(b.from) })
  out
}

///|
fn ass_words(s : String) -> String {
  let sb = StringBuilder()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '{' {
      while i < chars.length() && chars[i] != '}' {
        i += 1
      }
      i += 1
      continue
    }
    if ch == '\\' && i + 1 < chars.length() {
      match chars[i + 1] {
        'N' | 'n' => {
          sb.write_char('\n')
          i += 2
          continue
        }
        'h' => {
          sb.write_char(' ')
          i += 2
          continue
        }
        _ => ()
      }
    }
    sb.write_char(ch)
    i += 1
  }
  sb.to_string().trim().to_owned()
}

///|
/// A line's words without its tags (<i>, <font …>, WebVTT's <c.x>, <00:01.000>) and ASS-like {\an8}.
fn strip_tags(s : String) -> String {
  let sb = StringBuilder()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '<' || (ch == '{' && i + 1 < chars.length() && chars[i + 1] == '\\') {
      let close = if ch == '<' { '>' } else { '}' }
      let mut k = i + 1
      while k < chars.length() && chars[k] != close {
        k += 1
      }
      if k < chars.length() {
        i = k + 1
        continue
      }
    }
    sb.write_char(ch)
    i += 1
  }
  sb.to_string()
    .replace_all(old="&amp;", new="&")
    .replace_all(old="&lt;", new="<")
    .replace_all(old="&gt;", new=">")
    .replace_all(old="&nbsp;", new=" ")
}

///|
/// `hh:mm:ss,mmm`, `mm:ss.mmm`, `h:mm:ss.cc` (ASS's hundredths) in ms; None when it is none of them.
pub fn time_of(s : String) -> Double? {
  let s = s.trim().to_owned().replace_all(old=",", new=".")
  if s == "" {
    return None
  }
  let (whole, frac) = match s.find(".") {
    Some(k) => (s.view(end_offset=k).to_owned(), s.view(start_offset=k + 1).to_owned())
    None => (s, "")
  }
  let parts = whole.split(":").map(fn(p) { p.to_owned() }).to_array()
  if parts.length() < 2 || parts.length() > 3 {
    return None
  }
  let mut secs = 0.0
  for p in parts {
    let n = try {
      @string.parse_int(p[:])
    } catch {
      _ => return None
    }
    secs = secs * 60.0 + n.to_double()
  }
  let mut ms = secs * 1000.0
  if frac != "" {
    let n = try {
      @string.parse_int(frac[:])
    } catch {
      _ => return None
    }
    let mut scale = 1.0
    for _ in 0..<frac.length() {
      scale *= 10.0
    }
    ms += n.to_double() / scale * 1000.0
  }
  Some(ms)
}

///|
/// What is said at `ms`: the words of every cue then, one under another ("" when none).
pub fn cues_at(cues : Array[Cue], ms : Double) -> String {
  let said : Array[String] = []
  for q in cues {
    if q.from <= ms && ms < q.to {
      said.push(q.text)
    }
  }
  said.join("\n")
}
