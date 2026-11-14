// A runtime's transcript records as timeline entries (station/src/read/transcript.ts `timelineOf`): Claude Code's,
// Codex's (its code mode's scripts read for their calls), DeepSeek Harness's, Grok Build's, and the station's own for
// Cursor, Devin, Hermes and Antigravity; each record read as JSON.parse reads it (station/mb src/jsjson), what it says
// written as JSON.stringify writes it.

///|
/// An entry (transcript.ts `TimelineEntry`): `said`, a call's brief made of its whole input (transcript.ts `briefs`).
pub(all) struct Entry {
  at : String?
  kind : String
  text : String
  tool : String?
  ok : Bool?
  call_id : String?
  subagent : Bool
  said : String?
}

///|
/// What reading keeps between lines (transcript.ts `ReadState`): calls taken out of a script still running.
pub struct ReadState {
  priv inner : Map[String, Int]
}

///|
pub fn ReadState::new() -> ReadState {
  { inner: Map([]) }
}

///|
/// A reading's state from what a mark or a snapshot kept of it (`new Map(inner)`).
fn ReadState::of(pairs : Array[(String, Int)]) -> ReadState {
  let inner = Map([])
  for p in pairs {
    inner[p.0] = p.1
  }
  { inner, }
}

///|
/// What it keeps, in its order (`[...state.inner]`).
fn ReadState::pairs(self : ReadState) -> Array[(String, Int)] {
  self.inner.iter().collect()
}

///|
let max_text : Int = 4000

///|
fn get(v : @jsjson.JValue?, key : String) -> @jsjson.JValue? {
  match v {
    Some(Obj(_) as o) => o.get(key)
    _ => None
  }
}

///|
fn string_of(v : @jsjson.JValue?) -> String? {
  match v {
    Some(Str(s)) => Some(@jsjson.raw_text(s))
    _ => None
  }
}

///|
fn is_str(v : @jsjson.JValue?) -> Bool {
  v is Some(Str(_))
}

///|
fn trim(s : String) -> String {
  @jscase.trim_white(s)
}

///|
/// The code points of `s` (Array.from: a pair of surrogates one, a lone one one), as strings.
fn chars(s : String) -> Array[String] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_charcode_at(i)
    let w = if c >= 0xd800 && c <= 0xdbff && i + 1 < n && s.unsafe_charcode_at(i + 1) >= 0xdc00 &&
      s.unsafe_charcode_at(i + 1) <= 0xdfff {
      2
    } else {
      1
    }
    out.push(s.view(start_offset=i, end_offset=i + w).to_owned())
    i += w
  }
  out
}

///|
/// transcript.ts `clip`.
fn clip(text : String) -> String {
  let cs = chars(text)
  if cs.length() > max_text {
    cs.view(end=max_text).iter().collect().join("") + "\n… (\{cs.length() - max_text} more characters)"
  } else {
    text
  }
}

///|
fn pretty(v : @jsjson.JValue?) -> String {
  match v {
    Some(j) => @jsjson.stringify_pretty(j)
    None => "null"
  }
}

///|
/// transcript.ts `toText`.
fn to_text(v : @jsjson.JValue) -> String {
  match v {
    Str(s) => @jsjson.raw_text(s)
    Arr(items) =>
      items
      .map(item => {
        if get(Some(item), "type") is Some(Str(t)) && @jsjson.raw_text(t) == "image" {
          return "[image]"
        }
        match get(Some(item), "text") {
          Some(Str(t)) => @jsjson.raw_text(t)
          Some(t) => @jsjson.stringify(t)
          None => to_text(item)
        }
      })
      .join("\n")
    v => @jsjson.stringify_pretty(v)
  }
}

///|
fn is_posting(tool : String) -> Bool {
  tool == "mcp__stillfail__chat_post" || tool == "mcp__ember__chat_post"
}

///|
fn kept_whole(tool : String) -> Bool {
  is_posting(tool) || tool == "TodoWrite" || tool == "update_plan" || tool == "TaskCreate" || tool == "TaskUpdate"
}

///|
/// `new Date(time).toISOString()` of a finite number; raises as it throws past the dates JavaScript has.
pub fn date_iso(time : Double) -> String raise {
  let t = if time < 0.0 { -(-time).floor() } else { time.floor() }
  if t.abs() > 8.64e15 {
    fail("Invalid time value")
  }
  let ms = t.to_int64()
  let day = 86_400_000L
  let days = if ms >= 0L { ms / day } else { -((-ms + day - 1L) / day) }
  let rest = ms - days * day
  let z = days + 719_468L
  let era = if z >= 0L { z / 146_097L } else { (z - 146_096L) / 146_097L }
  let doe = z - era * 146_097L
  let yoe = (doe - doe / 1460L + doe / 36_524L - doe / 146_096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let y = yoe + era * 400L + (if m <= 2L { 1L } else { 0L })
  let pad = (n : Int64, w : Int) => {
    let s = n.to_string()
    "0".repeat(if w > s.length() { w - s.length() } else { 0 }) + s
  }
  let year = if y >= 0L && y <= 9999L {
    pad(y, 4)
  } else if y < 0L {
    "-" + pad(-y, 6)
  } else {
    "+" + pad(y, 6)
  }
  "\{year}-\{pad(m, 2)}-\{pad(d, 2)}T\{pad(rest / 3_600_000L, 2)}:\{pad(rest / 60_000L % 60L, 2)}:\{pad(rest / 1000L % 60L, 2)}.\{pad(rest % 1000L, 3)}Z"
}

///|
fn time_at(r : @jsjson.JValue) -> String? raise {
  match get(Some(r), "time") {
    Some(Num(t)) if !t.is_nan() && !t.is_inf() => Some(date_iso(t))
    _ => None
  }
}

///|
/// transcript.ts `timelineOf`: a record's entries, read on from `state`.
pub fn timeline_of(runtime : String, record : @jsjson.JValue, state : ReadState, out : Array[Entry]) -> Unit raise {
  match runtime {
    "claude" => claude(record, out)
    "dsh" => dsh(record, out)
    "grok" => grok(record, out)
    "cursor" | "devin" | "hermes" | "agy" => cursor(record, out)
    _ => codex(record, state, out)
  }
}

///|
fn dsh_text(content : @jsjson.JValue?) -> String {
  match content {
    Some(Arr(parts)) =>
      parts
      .map(c => if get(Some(c), "type") is Some(Str(t)) && @jsjson.raw_text(t) == "image" {
        "[image]"
      } else {
        string_of(get(Some(c), "text")).unwrap_or("")
      })
      .filter(t => t != "")
      .join("\n")
    _ => ""
  }
}

///|
/// A call's arguments given as text: parsed (and written pretty) when they are JSON, as they are when not.
fn parsed_args(raw : String) -> (@jsjson.JValue?, String) {
  match (try { Ok(@jsjson.parse(raw)) } catch { e => Err(e) }) {
    Ok(v) => (Some(v), @jsjson.stringify_pretty(v))
    Err(_) => (None, raw)
  }
}

///|
/// transcript.ts `grokQuery`: what is inside a `<user_query>` around the whole.
fn grok_query(text : String) -> String {
  let n = text.length()
  let mut s = 0
  while s < n && @jscase.is_space(text.unsafe_charcode_at(s)) {
    s += 1
  }
  let mut e = n
  while e > s && @jscase.is_space(text.unsafe_charcode_at(e - 1)) {
    e -= 1
  }
  let open = "<user_query>"
  let close = "</user_query>"
  let inner = text.view(start_offset=s, end_offset=e).to_owned()
  guard inner.has_prefix(open) && inner.has_suffix(close) && inner.length() >= open.length() + close.length() else {
    return text
  }
  let mut body = inner.view(start_offset=open.length(), end_offset=inner.length() - close.length()).to_owned()
  if body.has_prefix("\n") {
    body = body.view(start_offset=1).to_owned()
  }
  // (lazily matched: a newline before the close is not kept, but the close must be the last one)
  if body.has_suffix("\n") {
    body = body.view(end_offset=body.length() - 1).to_owned()
  }
  body
}

///|
/// transcript.ts `cursorResult`.
fn cursor_result(result : @jsjson.JValue?) -> String {
  let mut r = result
  if result is Some(Str(s)) {
    let text = @jsjson.raw_text(s)
    match (try { Ok(@jsjson.parse(text)) } catch { e => Err(e) }) {
      Ok(v) => r = Some(v)
      Err(_) => return text
    }
  }
  let v = match get(r, "value") {
    Some(v) => Some(v)
    None => r
  }
  if is_str(get(v, "stdout")) || is_str(get(v, "stderr")) {
    return [string_of(get(v, "stdout")).unwrap_or(""), string_of(get(v, "stderr")).unwrap_or("")].filter(t => t != "").join(
      "\n",
    )
  }
  if get(v, "content") is Some(Arr(content)) {
    return content
      .map(c => match string_of(get(get(Some(c), "text"), "text")) {
        Some(t) => t
        None => string_of(get(Some(c), "text")).unwrap_or("")
      })
      .filter(t => t != "")
      .join("\n")
  }
  match r {
    None | Some(Null) => ""
    Some(Str(s)) => @jsjson.raw_text(s)
    Some(x) => @jsjson.stringify_pretty(x)
  }
}

///|
/// Whether `content` starts, after white space, with a command Claude Code ran itself or what it printed.
fn claude_command(content : String) -> Bool {
  let mut i = 0
  while i < content.length() && @jscase.is_space(content.unsafe_charcode_at(i)) {
    i += 1
  }
  let rest = content.view(start_offset=i).to_owned()
  ["<command-name>", "<local-command-stdout>", "<local-command-caveat>"].iter().any(t => rest.has_prefix(t))
}

///|
fn trim_start(s : String) -> String {
  let mut i = 0
  while i < s.length() && @jscase.is_white_space(s.unsafe_charcode_at(i)) {
    i += 1
  }
  s.view(start_offset=i).to_owned()
}

///|
/// transcript.ts `injected`.
fn injected(text : String) -> Bool {
  let t = trim_start(text)
  ["environment_context", "user_instructions", "permissions", "skills_instructions", "collaboration_mode"]
  .iter()
  .any(tag => {
    if !t.has_prefix("<" + tag) {
      return false
    }
    let next = chars(t.view(start_offset=tag.length() + 1).to_owned())
    match next.get(0) {
      None => true
      Some(c) => !is_alphanumeric(code_of(c)) && c != "_"
    }
  })
}

///|
fn code_of(c : String) -> Int {
  if c.length() == 2 {
    0x10000 + ((c.unsafe_charcode_at(0) - 0xd800) << 10) + (c.unsafe_charcode_at(1) - 0xdc00)
  } else {
    c.unsafe_charcode_at(0)
  }
}

///|
/// transcript.ts `typed`.
fn typed(text : String) -> String? {
  let t = trim_start(text)
  if t.has_prefix("# AGENTS.md instructions") {
    return None
  }
  if !t.has_prefix("#") {
    return Some(text)
  }
  for mark in ["## My request for Codex:", "## My request:"] {
    if t.rev_find(mark) is Some(at) {
      return Some(trim(t.view(start_offset=at + mark.length()).to_owned()))
    }
  }
  Some(text)
}

///|
/// transcript.ts `wrapped`.
fn wrapped(text : String) -> Bool {
  let t = trim(text)
  if !t.has_prefix("<") {
    return false
  }
  guard t.view(start_offset=1).find(">") is Some(c) else { return false }
  let close = c + 1
  let name = t.view(start_offset=1, end_offset=close).to_owned()
  name != "" &&
  name.iter().all(ch => (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-') &&
  t.has_suffix("</\{name}>")
}

///|
/// transcript.ts `typedParts`.
fn typed_parts(content : @jsjson.JValue?) -> String {
  match content {
    Some(Str(s)) => @jsjson.raw_text(s)
    Some(Arr(blocks)) =>
      blocks
      .filter_map(b => string_of(get(Some(b), "text")))
      .filter_map(typed)
      .filter(t => trim(t) != "" && !injected(t) && !wrapped(t))
      .join("\n")
    _ => ""
  }
}
