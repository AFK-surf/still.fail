// A runtime's transcript records as timeline entries (station/src/read/transcript.ts `timelineOf`): Claude Code's,
// Codex's (its code mode's scripts read for their calls), DeepSeek Harness's, Grok Build's, and the station's own for
// Cursor, Devin, Hermes and Antigravity; each record read as JSON.parse reads it (station/mb src/jsjson), what it says
// written as JSON.stringify writes it.

///|
/// An entry (transcript.ts `TimelineEntry`), of it what a search reads.
pub(all) struct Entry {
  at : String?
  kind : String
  text : String
  tool : String?
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
fn dsh(r : @jsjson.JValue, out : Array[Entry]) -> Unit raise {
  let kind = string_of(get(Some(r), "type")).unwrap_or("")
  let at = time_at(r)
  let data = get(Some(r), "data")
  let message = match get(data, "message") {
    Some(m) => Some(m)
    None => data
  }
  if kind == "user/message" {
    guard string_of(get(get(data, "source"), "kind")) == Some("user") else { return }
    let text = dsh_text(get(data, "content"))
    if trim(text) != "" {
      out.push({ at, kind: "user", text: clip(text), tool: None })
    }
  } else if kind == "assistant/message" {
    guard get(message, "content") is Some(Arr(blocks)) else { return }
    for block in blocks {
      let b = Some(block)
      let t = string_of(get(b, "type"))
      let text = string_of(get(b, "text")).unwrap_or("")
      if t == Some("text") && trim(text) != "" {
        out.push({ at, kind: "assistant", text: clip(text), tool: None })
      } else if t == Some("reasoning") && trim(text) != "" {
        out.push({ at, kind: "thinking", text: clip(text), tool: None })
      } else if t == Some("tool-call") {
        let name = string_of(get(b, "name")).unwrap_or("")
        let (_, args) = parsed_args(string_of(get(b, "arguments")).unwrap_or(""))
        out.push({ at, kind: "tool_call", text: if kept_whole(name) { args } else { clip(args) }, tool: Some(name) })
      }
    }
  } else if kind == "tool/result" {
    out.push({ at, kind: "tool_result", text: clip(dsh_text(get(message, "content"))), tool: None })
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
fn grok(r : @jsjson.JValue, out : Array[Entry]) -> Unit {
  let rj = Some(r)
  let kind = string_of(get(rj, "type")).unwrap_or("")
  let content = get(rj, "content")
  if kind == "user" {
    if get(rj, "synthetic_reason") is Some(_) || get(rj, "prompt_index") is None {
      return
    }
    let text = grok_query(match content { Some(Str(s)) => @jsjson.raw_text(s); c => dsh_text(c) })
    if trim(text) != "" {
      out.push({ at: None, kind: "user", text: clip(text), tool: None })
    }
  } else if kind == "reasoning" {
    let text = match get(rj, "summary") {
      Some(Arr(xs)) => xs.map(s => string_of(get(Some(s), "text")).unwrap_or("")).filter(t => t != "").join("\n\n")
      _ => ""
    }
    if trim(text) != "" {
      out.push({ at: None, kind: "thinking", text: clip(text), tool: None })
    }
  } else if kind == "assistant" {
    let text = match content { Some(Str(s)) => @jsjson.raw_text(s); c => dsh_text(c) }
    if trim(text) != "" {
      out.push({ at: None, kind: "assistant", text: clip(text), tool: None })
    }
    if get(rj, "tool_calls") is Some(Arr(calls)) {
      for call in calls {
        let c = Some(call)
        let mut name = string_of(get(c, "name")).unwrap_or("")
        let raw = string_of(get(c, "arguments")).unwrap_or("")
        let args = match (try { Ok(@jsjson.parse(raw)) } catch { e => Err(e) }) {
          Ok(input) => {
            let mut input = input
            if name == "use_tool" && string_of(get(Some(input), "tool_name")) is Some(tool) {
              name = "mcp__" + tool
              input = get(Some(input), "tool_input").unwrap_or(Obj([]))
            }
            @jsjson.stringify_pretty(input)
          }
          Err(_) => raw
        }
        out.push({ at: None, kind: "tool_call", text: if kept_whole(name) { args } else { clip(args) }, tool: Some(name) })
      }
    }
  } else if kind == "tool_result" {
    let text = match content {
      Some(Str(s)) => @jsjson.raw_text(s)
      Some(c) => to_text(c)
      None => to_text(Null)
    }
    out.push({ at: None, kind: "tool_result", text: clip(text), tool: None })
  }
}

///|
fn cursor(r : @jsjson.JValue, out : Array[Entry]) -> Unit raise {
  let rj = Some(r)
  let kind = string_of(get(rj, "type")).unwrap_or("")
  let at = time_at(r)
  if kind == "user" || kind == "assistant" || kind == "thinking" {
    let text = string_of(get(rj, "text")).unwrap_or("")
    if trim(text) != "" {
      out.push({ at, kind, text: clip(text), tool: None })
    }
  } else if kind == "tool" {
    let mut name = string_of(get(rj, "name")).unwrap_or("")
    let mut input = get(rj, "args").unwrap_or(Obj([]))
    if name == "mcp" &&
      string_of(get(Some(input), "providerIdentifier")) is Some(provider) &&
      string_of(get(Some(input), "toolName")) is Some(tool) {
      name = "mcp__\{provider}__\{tool}"
      input = get(Some(input), "args").unwrap_or(Obj([]))
    }
    let args = @jsjson.stringify_pretty(input)
    out.push({ at, kind: "tool_call", text: if kept_whole(name) { args } else { clip(args) }, tool: Some(name) })
    out.push({ at, kind: "tool_result", text: clip(cursor_result(get(rj, "result"))), tool: None })
  }
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
fn claude(r : @jsjson.JValue, out : Array[Entry]) -> Unit {
  let rj = Some(r)
  let kind = string_of(get(rj, "type")).unwrap_or("")
  let at = string_of(get(rj, "timestamp"))
  let queued = get(rj, "attachment")
  if kind == "attachment" && string_of(get(queued, "type")) == Some("queued_command") {
    let prompts : Array[String?] = match get(queued, "prompt") {
      Some(Str(s)) => [Some(@jsjson.raw_text(s))]
      Some(Arr(bs)) =>
        bs.map(b => if string_of(get(Some(b), "type")) == Some("text") { string_of(get(Some(b), "text")) } else { None })
      _ => []
    }
    for t in prompts {
      if t is Some(text) && trim(text) != "" {
        out.push({ at, kind: "user", text: clip(text), tool: None })
      }
    }
    return
  }
  if (kind != "user" && kind != "assistant") || get(rj, "isMeta") is Some(Bool(true)) {
    return
  }
  let content = get(get(rj, "message"), "content")
  if content is Some(Str(s)) {
    let text = @jsjson.raw_text(s)
    if kind == "user" && claude_command(text) {
      return
    }
    out.push({ at, kind, text: clip(text), tool: None })
    return
  }
  guard content is Some(Arr(blocks)) else { return }
  for block in blocks {
    let b = Some(block)
    let text_of = (k : String) => match string_of(get(b, k)) {
      Some(t) if t != "" => Some(t)
      _ => None
    }
    match string_of(get(b, "type")) {
      Some("text") => if text_of("text") is Some(t) { out.push({ at, kind, text: clip(t), tool: None }) }
      Some("thinking") => if text_of("thinking") is Some(t) { out.push({ at, kind: "thinking", text: clip(t), tool: None }) }
      Some("tool_use") => {
        let name = string_of(get(b, "name")).unwrap_or("")
        let input = pretty(Some(get(b, "input").unwrap_or(Null)))
        out.push({ at, kind: "tool_call", text: if kept_whole(name) { input } else { clip(input) }, tool: Some(name) })
      }
      Some("tool_result") =>
        out.push({ at, kind: "tool_result", text: clip(to_text(get(b, "content").unwrap_or(Null))), tool: None })
      _ => ()
    }
  }
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

///|
/// What the station says of a call taken out of a script when the script's output comes (station.transcript
/// .inScriptOutput, in the worker's language).
let in_script_output : String = "（结果在脚本的输出里）"

///|
fn codex(r : @jsjson.JValue, state : ReadState, out : Array[Entry]) -> Unit {
  let rj = Some(r)
  guard string_of(get(rj, "type")) == Some("response_item") else { return }
  let p = Some(get(rj, "payload").unwrap_or(Null))
  let at = string_of(get(rj, "timestamp"))
  let kind = string_of(get(p, "type")).unwrap_or("")
  let name = string_of(get(p, "name")).unwrap_or("")
  let call_id = string_of(get(p, "call_id"))
  let call = (tool : String, text : String) => { at, kind: "tool_call", text, tool: Some(tool) }
  match kind {
    "message" => {
      let role = string_of(get(p, "role")).unwrap_or("")
      if role != "user" && role != "assistant" {
        return
      }
      let content = get(p, "content").unwrap_or(Null)
      let text = if role == "user" { typed_parts(Some(content)) } else { to_text(content) }
      if role == "user" && injected(text) {
        return
      }
      if trim(text) != "" {
        out.push({ at, kind: role, text: clip(text), tool: None })
      }
      return
    }
    "reasoning" => {
      let chosen = match get(p, "content") {
        Some(Arr(xs)) if xs.length() > 0 => @jsjson.JValue::Arr(xs)
        _ => get(p, "summary").unwrap_or(@jsjson.JValue::Arr([]))
      }
      let text = to_text(chosen)
      if trim(text) != "" {
        out.push({ at, kind: "thinking", text: clip(text), tool: None })
      }
      return
    }
    _ => ()
  }
  if kind == "custom_tool_call" && name == "exec" {
    let script = string_of(get(p, "input")).unwrap_or("")
    let (calls, only) = script_calls(script)
    if !only {
      out.push(call("exec", clip(script)))
    }
    for c in calls {
      let (tool, args) = c
      let text = @jsjson.stringify_pretty(args)
      out.push(call(tool, if is_posting(tool) { text } else { clip(text) }))
    }
    if !only && call_id is Some(id) && calls.length() > 0 {
      state.inner[id] = calls.length()
    }
    return
  }
  if kind == "function_call" || kind == "custom_tool_call" {
    let given = match get(p, "arguments") {
      Some(g) => Some(g)
      None => get(p, "input")
    }
    let raw = match given {
      None => ""
      Some(Str(s)) => @jsjson.raw_text(s)
      Some(g) => @jsjson.stringify(g)
    }
    let (_, args) = parsed_args(raw)
    out.push(call(name, if kept_whole(name) { args } else { clip(args) }))
    return
  }
  if kind == "function_call_output" || kind == "custom_tool_call_output" {
    let text = to_text(get(p, "output").unwrap_or(Null))
    out.push({ at, kind: "tool_result", text: clip(text), tool: None })
    let count = match call_id {
      Some(id) => state.inner.get(id).unwrap_or(0)
      None => 0
    }
    if call_id is Some(id) {
      state.inner.remove(id)
    }
    for _ in 0..<count {
      out.push({ at, kind: "tool_result", text: in_script_output, tool: None })
    }
  }
}
