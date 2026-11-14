// Each runtime's records as entries, field for field as transcript.ts makes them (`dshTimeline`, `grokTimeline`,
// `cursorTimeline`, `claudeTimeline`, `codexTimeline`), with each call's brief beside it (`withBrief`), and an entry as
// an execution history shows it before it is opened (`brief`).

///|
/// What the station says of a call taken out of a script once the script's output comes (station.transcript
/// .inScriptOutput): in the language a read is asked in, as the pool gives it (a search's: Chinese).
pub let in_script_output : Ref[String] = { val: "（结果在脚本的输出里）" }

///|
fn entry(at : String?, kind : String, text : String, tool? : String, ok? : Bool, call_id? : String, subagent? : Bool = false) -> Entry {
  { at, kind, text, tool, ok, call_id, subagent, said: None }
}

///|
/// A call entry, its brief made of its input kept beside it (`withBrief`).
fn with_brief(e : Entry, input : @jsjson.JValue?) -> Entry {
  { ..e, said: Some(brief_of(input)) }
}

///|
/// Of `text`, its first `n` code points.
fn first_chars(text : String, n : Int) -> String {
  let cs = chars(text)
  if cs.length() <= n {
    text
  } else {
    cs.view(end=n).iter().collect().join("")
  }
}

///|
/// What says what a call does, of its input (transcript.ts SAYING).
let saying : Array[String] = [
  "description", "toolSummary", "command", "cmd", "file_path", "path", "Path", "target_file", "target_directory", "DirectoryPath",
  "Directory", "SearchDirectory", "SearchPath", "notebook_path", "StartLine", "EndLine", "offset", "limit", "Target", "Replacement",
  "Content", "Overwrite", "old_string", "new_string", "pattern", "Pattern", "url", "query", "Query", "prompt", "Prompt", "station",
  "action", "name", "key", "id", "to", "chat", "title", "file", "method", "Role", "Recipient", "Message", "summary", "message",
  "recipient", "subagent_type", "TypeName", "agent_id", "brief", "task", "text", "reason", "about", "Action", "TaskId", "skill",
]

///|
let brief_chars : Int = 300

///|
let small : Int = 600

///|
fn jstr(s : String) -> @jsjson.JValue {
  Str(@jsjson.units(s))
}

///|
/// transcript.ts `briefOf`: of an object, the fields that say what it does, each cut short; anything else cut short.
fn brief_of(input : @jsjson.JValue?) -> String {
  match input {
    Some(Obj(_) as o) => {
      let kept : Array[(Array[Int], @jsjson.JValue)] = []
      for name in saying {
        match o.get(name) {
          Some(Str(s)) => kept.push((@jsjson.units(name), jstr(first_chars(@jsjson.raw_text(s), brief_chars))))
          Some(Num(n)) if !n.is_nan() && !n.is_inf() => kept.push((@jsjson.units(name), Num(n)))
          Some(Bool(b)) => kept.push((@jsjson.units(name), Bool(b)))
          Some(Arr(xs)) =>
            kept.push((
              @jsjson.units(name),
              Arr(xs.filter_map(x => if x is Str(s) { Some(jstr(first_chars(@jsjson.raw_text(s), brief_chars))) } else { None })),
            ))
          _ => ()
        }
      }
      @jsjson.stringify(Obj(kept))
    }
    Some(Str(s)) => first_chars(@jsjson.raw_text(s), brief_chars)
    Some(v) => first_chars(@jsjson.stringify(v), brief_chars)
    None => first_chars("null", brief_chars)
  }
}

///|
fn time_iso(time : @jsjson.JValue?) -> String? raise {
  match time {
    Some(Num(t)) if !t.is_nan() && !t.is_inf() => Some(date_iso(t))
    _ => None
  }
}

///|
fn dsh(r : @jsjson.JValue, out : Array[Entry]) -> Unit raise {
  let kind = string_of(get(Some(r), "type")).unwrap_or("")
  let at = time_iso(get(Some(r), "time"))
  let data = get(Some(r), "data")
  let message = match get(data, "message") {
    Some(m) => Some(m)
    None => data
  }
  if kind == "user/message" {
    guard get(get(data, "source"), "kind") is Some(Str(k)) && @jsjson.raw_text(k) == "user" else { return }
    let text = dsh_text(get(data, "content"))
    if trim(text) != "" {
      out.push(entry(at, "user", clip(text)))
    }
  } else if kind == "assistant/message" {
    guard get(message, "content") is Some(Arr(blocks)) else { return }
    for block in blocks {
      let b = Some(block)
      let t = string_of(get(b, "type"))
      let text = string_of(get(b, "text")).unwrap_or("")
      if t == Some("text") && trim(text) != "" {
        out.push(entry(at, "assistant", clip(text)))
      } else if t == Some("reasoning") && trim(text) != "" {
        out.push(entry(at, "thinking", clip(text)))
      } else if t == Some("tool-call") {
        let name = string_of(get(b, "name")).unwrap_or("")
        let raw = string_of(get(b, "arguments")).unwrap_or("")
        let (parsed, args) = parsed_args(raw)
        let input = match parsed {
          Some(v) => v
          None => jstr(raw)
        }
        let e = entry(at, "tool_call", if kept_whole(name) { args } else { clip(args) }, tool=name)
        out.push(with_brief({ ..e, call_id: string_of(get(b, "id")) }, Some(input)))
      }
    }
  } else if kind == "tool/result" {
    let e = entry(at, "tool_result", clip(dsh_text(get(message, "content"))), ok=!(get(message, "isError") is Some(Bool(true))))
    out.push({ ..e, call_id: string_of(get(message, "toolCallId")) })
  }
}

///|
/// Whether `text` starts `Failed to call <name>:` (grokTimeline's `/^Failed to call [\w.-]+:/`).
fn failed_call(text : String) -> Bool {
  let head = "Failed to call "
  guard text.has_prefix(head) else { return false }
  let mut i = head.length()
  let start = i
  while i < text.length() {
    let c = text.unsafe_charcode_at(i)
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-' {
      i += 1
    } else {
      break
    }
  }
  i > start && i < text.length() && text.unsafe_charcode_at(i) == ':'
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
      out.push(entry(None, "user", clip(text)))
    }
  } else if kind == "reasoning" {
    let text = match get(rj, "summary") {
      Some(Arr(xs)) => xs.map(s => string_of(get(Some(s), "text")).unwrap_or("")).filter(t => t != "").join("\n\n")
      _ => ""
    }
    if trim(text) != "" {
      out.push(entry(None, "thinking", clip(text)))
    }
  } else if kind == "assistant" {
    let text = match content { Some(Str(s)) => @jsjson.raw_text(s); c => dsh_text(c) }
    if trim(text) != "" {
      out.push(entry(None, "assistant", clip(text)))
    }
    if get(rj, "tool_calls") is Some(Arr(calls)) {
      for call in calls {
        let c = Some(call)
        let mut name = string_of(get(c, "name")).unwrap_or("")
        let raw = string_of(get(c, "arguments")).unwrap_or("")
        let mut input = jstr(raw)
        let args = match (try { Ok(@jsjson.parse(raw)) } catch { e => Err(e) }) {
          Ok(parsed) => {
            input = parsed
            if name == "use_tool" && get(Some(parsed), "tool_name") is Some(Str(tool)) {
              name = "mcp__" + @jsjson.raw_text(tool)
              input = match get(Some(parsed), "tool_input") { None | Some(Null) => @jsjson.JValue::Obj([]); Some(v) => v }
            }
            @jsjson.stringify_pretty(input)
          }
          Err(_) => raw
        }
        let e = entry(None, "tool_call", if kept_whole(name) { args } else { clip(args) }, tool=name)
        out.push(with_brief({ ..e, call_id: string_of(get(c, "id")) }, Some(input)))
      }
    }
  } else if kind == "tool_result" {
    let text = match content {
      Some(Str(s)) => @jsjson.raw_text(s)
      Some(c) => to_text(c)
      None => to_text(Null)
    }
    let ok = !(get(rj, "is_error") is Some(Bool(true))) && !failed_call(text)
    out.push({ ..entry(None, "tool_result", clip(text), ok~), call_id: string_of(get(rj, "tool_call_id")) })
  }
}

///|
/// `Created At: <a> \r?\n Completed At: <b>` at the start of an Antigravity call's result (cursorTimeline's `agyTimes`).
fn agy_times(text : String) -> (String, String)? {
  let field = fn(s : String, label : String) -> (String, String)? {
    guard s.has_prefix(label) else { return None }
    let mut i = label.length()
    while i < s.length() && @jscase.is_space(s.unsafe_charcode_at(i)) {
      i += 1
    }
    let start = i
    while i < s.length() && !@jscase.is_space(s.unsafe_charcode_at(i)) {
      i += 1
    }
    if i == start {
      return None
    }
    Some((s.view(start_offset=start, end_offset=i).to_owned(), s.view(start_offset=i).to_owned()))
  }
  // (`\s*` takes what spaces it can, then gives back as the pattern needs: a value is at least one non-space)
  guard field(text, "Created At:") is Some((a, rest)) else { return None }
  let rest = if rest.has_prefix("\r\n") {
    rest.view(start_offset=2).to_owned()
  } else if rest.has_prefix("\n") {
    rest.view(start_offset=1).to_owned()
  } else {
    return None
  }
  guard field(rest, "Completed At:") is Some((b, _)) else { return None }
  Some((a, b))
}

///|
fn cursor(r : @jsjson.JValue, out : Array[Entry]) -> Unit raise {
  let rj = Some(r)
  let kind = string_of(get(rj, "type")).unwrap_or("")
  let at = time_iso(get(rj, "time"))
  if kind == "user" || kind == "assistant" || kind == "thinking" {
    let text = string_of(get(rj, "text")).unwrap_or("")
    if trim(text) != "" {
      out.push(entry(at, kind, clip(text)))
    }
  } else if kind == "tool" {
    let mut name = string_of(get(rj, "name")).unwrap_or("")
    let mut input = match get(rj, "args") { None | Some(Null) => @jsjson.JValue::Obj([]); Some(v) => v }
    if name == "mcp" &&
      string_of(get(Some(input), "providerIdentifier")) is Some(provider) &&
      string_of(get(Some(input), "toolName")) is Some(tool) {
      name = "mcp__\{provider}__\{tool}"
      input = match get(Some(input), "args") { None | Some(Null) => @jsjson.JValue::Obj([]); Some(v) => v }
    }
    let args = @jsjson.stringify_pretty(input)
    let id = string_of(get(rj, "id"))
    let result_text = cursor_result(get(rj, "result"))
    let started_at = time_iso(get(rj, "startedAt"))
    let times = agy_times(result_text)
    let parse_iso = fn(s : String?) -> String? raise {
      guard s is Some(s) && s != "" && date_parse(s) is Some(ms) else { return None }
      Some(date_iso(ms))
    }
    let call_at = match started_at {
      Some(a) => Some(a)
      None =>
        match parse_iso(times.map(t => t.0)) {
          Some(a) => Some(a)
          None => at
        }
    }
    let result_at = if started_at is Some(_) {
      at
    } else {
      match parse_iso(times.map(t => t.1)) {
        Some(a) => Some(a)
        None => at
      }
    }
    let call = entry(call_at, "tool_call", if kept_whole(name) { args } else { clip(args) }, tool=name)
    out.push(with_brief({ ..call, call_id: id }, Some(input)))
    let ok = !(get(rj, "status") is Some(Str(s)) && @jsjson.raw_text(s) == "error")
    out.push({ ..entry(result_at, "tool_result", clip(result_text), ok~), call_id: id })
  }
}

///|
fn claude(r : @jsjson.JValue, out : Array[Entry]) -> Unit {
  let rj = Some(r)
  let kind = string_of(get(rj, "type")).unwrap_or("")
  let at = string_of(get(rj, "timestamp"))
  let subagent = get(rj, "isSidechain") is Some(Bool(true))
  let queued = get(rj, "attachment")
  if kind == "attachment" && get(queued, "type") is Some(Str(t)) && @jsjson.raw_text(t) == "queued_command" {
    let prompts : Array[String?] = match get(queued, "prompt") {
      Some(Str(s)) => [Some(@jsjson.raw_text(s))]
      Some(Arr(bs)) =>
        bs.map(b => if get(Some(b), "type") is Some(Str(t)) && @jsjson.raw_text(t) == "text" { string_of(get(Some(b), "text")) } else { None })
      _ => []
    }
    for t in prompts {
      if t is Some(text) && trim(text) != "" {
        out.push(entry(at, "user", clip(text), subagent~))
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
    out.push(entry(at, kind, clip(text), subagent~))
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
      Some("text") => if text_of("text") is Some(t) { out.push(entry(at, kind, clip(t), subagent~)) }
      Some("thinking") => if text_of("thinking") is Some(t) { out.push(entry(at, "thinking", clip(t), subagent~)) }
      Some("tool_use") => {
        let name = string_of(get(b, "name")).unwrap_or("")
        let input = pretty(Some(get(b, "input").unwrap_or(Null)))
        let e = entry(at, "tool_call", if kept_whole(name) { input } else { clip(input) }, tool=name, subagent~)
        out.push(with_brief({ ..e, call_id: string_of(get(b, "id")) }, get(b, "input")))
      }
      Some("tool_result") => {
        let failed = get(b, "is_error") is Some(Bool(true))
        let e = entry(at, "tool_result", clip(to_text(get(b, "content").unwrap_or(Null))), ok=!failed, subagent~)
        out.push({ ..e, call_id: string_of(get(b, "tool_use_id")) })
      }
      _ => ()
    }
  }
}

///|
fn codex(r : @jsjson.JValue, state : ReadState, out : Array[Entry]) -> Unit {
  let rj = Some(r)
  guard get(rj, "type") is Some(Str(t)) && @jsjson.raw_text(t) == "response_item" else { return }
  let p = Some(get(rj, "payload").unwrap_or(Null))
  let at = string_of(get(rj, "timestamp"))
  let kind = string_of(get(p, "type")).unwrap_or("")
  let name = string_of(get(p, "name")).unwrap_or("")
  let call_id = string_of(get(p, "call_id"))
  let call = (tool : String, id : String?, text : String) => { ..entry(at, "tool_call", text, tool~), call_id: id }
  let result = (ok : Bool, id : String?, text : String) => { ..entry(at, "tool_result", text, ok~), call_id: id }
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
        out.push(entry(at, role, clip(text)))
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
        out.push(entry(at, "thinking", clip(text)))
      }
      return
    }
    _ => ()
  }
  if kind == "custom_tool_call" && name == "exec" {
    let script = string_of(get(p, "input")).unwrap_or("")
    let (calls, only) = script_calls(script)
    if !only {
      out.push(with_brief(call("exec", call_id, clip(script)), Some(jstr(script))))
    }
    for i, c in calls {
      let (tool, args) = c
      let id = match call_id {
        None => None
        Some(cid) => if only && i == 0 { Some(cid) } else { Some("\{cid}#\{i}") }
      }
      let text = @jsjson.stringify_pretty(args)
      out.push(with_brief(call(tool, id, if is_posting(tool) { text } else { clip(text) }), Some(args)))
    }
    if !only && call_id is Some(id) && calls.length() > 0 {
      state.inner[id] = calls.length()
    }
    return
  }
  if kind == "function_call" || kind == "custom_tool_call" {
    let given = match get(p, "arguments") {
      None | Some(Null) => get(p, "input")
      Some(g) => Some(g)
    }
    let raw = match given {
      None => ""
      Some(Str(s)) => @jsjson.raw_text(s)
      Some(g) => @jsjson.stringify(g)
    }
    let (parsed, args) = parsed_args(raw)
    let input = match parsed {
      Some(v) => v
      None => jstr(raw)
    }
    out.push(with_brief(call(name, call_id, if kept_whole(name) { args } else { clip(args) }), Some(input)))
    return
  }
  if kind == "function_call_output" || kind == "custom_tool_call_output" {
    let text = to_text(get(p, "output").unwrap_or(Null))
    let mark = "Process exited with code "
    let failed = match text.find(mark) {
      Some(at) => {
        let next = at + mark.length()
        next < text.length() && text.unsafe_charcode_at(next) >= '1' && text.unsafe_charcode_at(next) <= '9'
      }
      None => false
    }
    out.push(result(!failed, call_id, clip(text)))
    let count = match call_id {
      Some(id) => state.inner.get(id).unwrap_or(0)
      None => 0
    }
    if call_id is Some(id) {
      state.inner.remove(id)
    }
    for i in 0..<count {
      out.push(result(!failed, Some("\{call_id.unwrap_or("")}#\{i}"), in_script_output.val))
    }
  }
}

// ── in brief (transcript.ts `brief`) ──

///|
/// transcript.ts `toolName`: a tool's name without the station's prefix.
fn tool_name(tool : String) -> String {
  for prefix in ["mcp__stillfail__", "stillfail__", "stillfail.", "mcp__ember__", "ember__", "ember."] {
    if tool.has_prefix(prefix) {
      return tool.view(start_offset=prefix.length()).to_owned()
    }
  }
  tool
}

///|
fn is_word(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

///|
/// `/\b(?:agentId|agent_id|conversationId)["'\s:=]+["']?([A-Za-z0-9_-]{6,})/.exec(text)?.[1]`.
fn agent_id_in(text : String) -> String? {
  let n = text.length()
  let id_char = (c : Int) => is_word(c) || c == '-'
  let sep = (c : Int) => c == '"' || c == '\'' || c == ':' || c == '=' || @jscase.is_space(c)
  for start in 0..<n {
    if start > 0 && is_word(text.unsafe_charcode_at(start - 1)) {
      continue
    }
    if !is_word(text.unsafe_charcode_at(start)) {
      continue
    }
    for name in ["agentId", "agent_id", "conversationId"] {
      guard text.view(start_offset=start).has_prefix(name) else { continue }
      let after = start + name.length()
      // the separators, as many as there are, then given back one at a time (and a quote after them) for an id of six
      let mut most = after
      while most < n && sep(text.unsafe_charcode_at(most)) {
        most += 1
      }
      let mut end_sep = most
      while end_sep > after {
        let tries = [end_sep]
        if end_sep < n && (text.unsafe_charcode_at(end_sep) == '"' || text.unsafe_charcode_at(end_sep) == '\'') {
          tries.insert(0, end_sep + 1)
        }
        for from in tries {
          let mut i = from
          while i < n && id_char(text.unsafe_charcode_at(i)) {
            i += 1
          }
          if i - from >= 6 {
            return Some(text.view(start_offset=from, end_offset=i).to_owned())
          }
        }
        end_sep -= 1
      }
    }
  }
  None
}

///|
fn ascii_low(c : Int) -> Int {
  if c >= 'A' && c <= 'Z' {
    c + 32
  } else {
    c
  }
}

///|
// A pattern is its ways from `at` in `s`: every place a match of it can end.

///|
fn lit(word : String) -> (String, Int) -> Array[Int] {
  (s, at) => {
    if at + word.length() > s.length() {
      return []
    }
    for i in 0..<word.length() {
      if ascii_low(s.unsafe_charcode_at(at + i)) != ascii_low(word.unsafe_charcode_at(i)) {
        return []
      }
    }
    [at + word.length()]
  }
}

///|
fn seq(parts : Array[(String, Int) -> Array[Int]]) -> (String, Int) -> Array[Int] {
  (s, at) => {
    let mut ends = [at]
    for p in parts {
      let next = []
      for e in ends {
        for f in p(s, e) {
          if !next.contains(f) {
            next.push(f)
          }
        }
      }
      ends = next
    }
    ends
  }
}

///|
fn alt(ways : Array[(String, Int) -> Array[Int]]) -> (String, Int) -> Array[Int] {
  (s, at) => {
    let out = []
    for w in ways {
      for e in w(s, at) {
        if !out.contains(e) {
          out.push(e)
        }
      }
    }
    out
  }
}

///|
fn opt(p : (String, Int) -> Array[Int]) -> (String, Int) -> Array[Int] {
  alt([p, (_, at) => [at]])
}

///|
/// One or more (`plus`), or none or more, of what `class` takes.
fn many(class : (Int) -> Bool, least : Int) -> (String, Int) -> Array[Int] {
  (s, at) => {
    let out = []
    let mut i = at
    while i < s.length() && class(s.unsafe_charcode_at(i)) {
      i += 1
      if i - at >= least {
        out.push(i)
      }
    }
    if least == 0 {
      out.push(at)
    }
    out
  }
}

///|
fn digits(n : Int) -> (String, Int) -> Array[Int] {
  (s, at) => {
    if at + n > s.length() {
      return []
    }
    for i in 0..<n {
      let c = s.unsafe_charcode_at(at + i)
      if c < '0' || c > '9' {
        return []
      }
    }
    [at + n]
  }
}

///|
/// transcript.ts BOILERPLATE_THOUGHT_LINE.
let boilerplate : (String, Int) -> Array[Int] = {
  let spaces = many(@jscase.is_space, 1)
  let dot = opt(lit("."))
  let through = opt(lit(" through how to approach this"))
  alt([
    seq([lit("I'm thinking"), through, dot]),
    seq([lit("I am thinking"), through, dot]),
    seq([lit("Let's think"), opt(alt([seq([spaces, lit("through"), spaces, lit("this")]), seq([spaces, lit("about"), spaces, lit("this")])])), dot]),
    seq([lit("Thinking"), opt(seq([spaces, lit("process")])), dot, opt(lit(":"))]),
    seq([lit("Thought"), spaces, lit("process"), opt(lit(":"))]),
    seq([lit("Process"), opt(lit(":"))]),
    seq([lit("Reasoning"), opt(lit(":"))]),
    seq([
      opt(seq([many(c => c >= '0' && c <= '9', 1), lit("."), many(@jscase.is_space, 0)])),
      opt(lit("**")),
      alt(["Analyze the Request", "Analysis", "Summary", "Plan", "Context", "Goal", "Steps", "Next Steps", "Approach", "Findings", "Observations"].map(lit)),
      lit(":"),
      opt(lit("**")),
    ]),
    seq([
      opt(lit("`")),
      digits(4),
      lit("-"),
      digits(2),
      lit("-"),
      digits(2),
      lit("T"),
      many(c => (c >= '0' && c <= '9') || c == ':' || c == '.', 1),
      lit("Z"),
      opt(lit("`")),
      many(c => c == ')' || c == ',' || c == '.' || c == ';' || c == ':', 0),
    ]),
  ])
}

///|
fn is_boilerplate(line : String) -> Bool {
  boilerplate(line, 0).contains(line.length())
}

///|
/// transcript.ts `brief`: an entry as an execution history shows it before it is opened, with whether anything was left
/// out.
pub fn brief(e : Entry) -> (Entry, Bool) {
  if chars(e.text).length() <= small {
    return (e, false)
  }
  if e.kind == "tool_call" {
    if ["chat_post", "chat_state", "slack_api"].contains(tool_name(e.tool.unwrap_or(""))) {
      return (e, false)
    }
    return ({ ..e, text: e.said.unwrap_or(first_chars(e.text, brief_chars)) }, true)
  }
  if e.kind == "tool_result" {
    let mut text = ""
    match (try { Ok(@jsjson.parse(e.text)) } catch { x => Err(x) }) {
      Ok(Obj(_) as v) =>
        if v.get("ok") is Some(Bool(ok)) {
          text = @jsjson.stringify(
            match v.get("ts") {
              Some(Str(ts)) => Obj([(@jsjson.units("ok"), Bool(ok)), (@jsjson.units("ts"), Str(ts))])
              _ => Obj([(@jsjson.units("ok"), Bool(ok))])
            },
          )
        }
      _ => ()
    }
    if text == "" && agent_id_in(e.text) is Some(id) {
      text = "agentId: \{id}"
    }
    return ({ ..e, text, }, true)
  }
  if e.kind == "thinking" {
    let lines = e.text.split("\n").map(l => trim(l.to_owned())).filter(l => l != "").collect()
    let first = match lines.search_by(l => !is_boilerplate(l)) {
      Some(i) => lines[i]
      None => lines.get(0).unwrap_or("")
    }
    return ({ ..e, text: first_chars(first, brief_chars) }, true)
  }
  (e, false)
}

///|
/// An entry as JSON, its fields as transcript.ts's object has them (at, kind, text, tool, ok, callId, subagent, brief).
pub fn entry_json(e : Entry, briefed : Bool) -> Json {
  let out : Map[String, Json] = {
    "at": match e.at { Some(a) => Json::string(a); None => Json::null() },
    "kind": Json::string(e.kind),
    "text": Json::string(e.text),
  }
  if e.tool is Some(t) {
    out["tool"] = Json::string(t)
  }
  if e.ok is Some(ok) {
    out["ok"] = Json::boolean(ok)
  }
  if e.call_id is Some(id) {
    out["callId"] = Json::string(id)
  }
  if e.subagent {
    out["subagent"] = Json::boolean(true)
  }
  if briefed {
    out["brief"] = Json::boolean(true)
  }
  Json::object(out)
}
