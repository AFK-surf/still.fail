// Sessions this machine's own Claude Code and Codex keep (station/src/read/machine.ts, GET /machine-sessions and GET
// /machine-sessions/:runtime/:id), read as the worker reads them: directories in the file system's order, a stable
// sort by when each was written, the same lines, records and words. Where the runtimes keep them (`roots`) the pool
// hands in from the station's environment (read/pool.ts).

///|
/// Enough of a first message to know it by; records read from a transcript's start; bytes from its end; the longest
/// line read (machine.ts FIRST, HEAD_RECORDS, TAIL, LINE_LIMIT).
const FIRST = 200

///|
const HEAD_RECORDS = 400

///|
const TAIL = 262144

///|
const LINE_LIMIT = 262144

///|
priv struct MachineSession {
  runtime : String
  id : String
  cwd : String
  mut title : String?
  first : String
  model : String?
  updated_at : Double
  size : Double
  mut session : String?
  path : String
}

///|
priv struct Roots {
  claude : String
  codex : String
}

///|
fn str_of(v : @jsjson.JValue?) -> String? {
  match v {
    Some(Str(s)) => Some(@jsjson.raw_text(s))
    _ => None
  }
}

///|
fn is_text(v : @jsjson.JValue?, text : String) -> Bool {
  str_of(v) == Some(text)
}

///|
fn white_trim(s : String) -> String {
  @jscase.trim_white(s)
}

///|
fn white_trim_start(s : String) -> String {
  let mut i = 0
  while i < s.length() && @jscase.is_white_space(s.unsafe_charcode_at(i)) {
    i += 1
  }
  s.view(start_offset=i).to_owned()
}

///|
fn parse_record(line : String) -> @jsjson.JValue? {
  Some(@jsjson.parse(line)) catch {
    _ => None
  }
}

///|
/// machine.ts `lines`, parsed: the records of a file's first `limit` lines.
fn records_of(host : @host.Host, path : String, limit? : Int) -> Array[@jsjson.JValue] raise {
  let args : Map[String, Json] = { "path": Json::string(path), "max": Json::number(LINE_LIMIT.to_double()) }
  if limit is Some(n) {
    args["limit"] = Json::number(n.to_double())
  }
  guard host.shell_sync("fs.lines", Json::object(args)) is Array(lines) else { return [] }
  lines.filter_map(l => if l is String(s) { parse_record(s) } else { None })
}

// ---- what was said ----

///|
/// machine.ts `injected`: context Codex adds as a person's message under a tag of its own.
fn injected(text : String) -> Bool {
  let t = white_trim_start(text)
  for tag in ["environment_context", "user_instructions", "permissions", "skills_instructions", "collaboration_mode"] {
    guard t.has_prefix("<" + tag) else { continue }
    let after = t.view(start_offset=tag.length() + 1).to_owned()
    if after == "" {
      return true
    }
    let two = after.view(end_offset=if after.length() < 2 { after.length() } else { 2 }).to_owned()
    let next = points(two)[0]
    return !@history.is_alphanumeric(next) && next != '_'
  }
  false
}

///|
/// machine.ts `notSaid`: what the runtime keeps as a person's message though it is not what they said.
fn not_said(text : String) -> Bool {
  let t = white_trim_start(text)
  t == "" ||
  [
    "<command-", "<local-command", "<system-reminder>", "<bash-", "<user-memory-input>", "Caveat: ", "This session is being continued from a previous conversation",
  ].iter().any(p => t.has_prefix(p))
}

///|
/// machine.ts `typed`: what the person typed in a part of a Codex user message.
fn typed(text : String) -> String? {
  let t = white_trim_start(text)
  if t.has_prefix("# AGENTS.md instructions") {
    return None
  }
  if !t.has_prefix("#") {
    return Some(text)
  }
  for mark in ["## My request for Codex:", "## My request:"] {
    if t.rev_find(mark) is Some(at) {
      return Some(white_trim(t.view(start_offset=at + mark.length()).to_owned()))
    }
  }
  Some(text)
}

///|
/// machine.ts `wrapped`: context Codex adds as a person's message, one tag around all of it.
fn wrapped(text : String) -> Bool {
  let t = white_trim(text)
  guard t.has_prefix("<") else { return false }
  guard t.view(start_offset=1).find(">") is Some(c) else { return false }
  let name = t.view(start_offset=1, end_offset=1 + c).to_owned()
  name != "" &&
  name.iter().all(ch => (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-') &&
  t.has_suffix("</" + name + ">")
}

///|
fn texts_of(content : @jsjson.JValue?) -> Array[String] {
  match content {
    Some(Arr(parts)) => parts.filter_map(b => str_of(jget(Some(b), "text")))
    _ => []
  }
}

///|
fn claude_said(r : @jsjson.JValue) -> Array[(Bool, String)] {
  let kind = str_of(jget(Some(r), "type")).unwrap_or("")
  let flagged = ["isMeta", "isSidechain", "isCompactSummary", "isApiErrorMessage"].iter().any(k => jget(Some(r), k) is Some(Bool(true)))
  if (kind != "user" && kind != "assistant") || flagged {
    return []
  }
  let person = kind == "user"
  let content = jget(jget(Some(r), "message"), "content")
  let texts = match content {
    Some(Str(s)) => [@jsjson.raw_text(s)]
    Some(Arr(parts)) => parts.filter_map(b => if is_text(jget(Some(b), "type"), "text") { str_of(jget(Some(b), "text")) } else { None })
    _ => []
  }
  texts.filter(t => white_trim(t) != "" && !(person && not_said(t))).map(t => (person, white_trim(t)))
}

///|
fn codex_said(r : @jsjson.JValue) -> Array[(Bool, String)] {
  let p = jget(Some(r), "payload")
  guard is_text(jget(Some(r), "type"), "response_item") && is_text(jget(p, "type"), "message") else { return [] }
  let role = str_of(jget(p, "role"))
  guard role == Some("user") || role == Some("assistant") else { return [] }
  let person = role == Some("user")
  let text = texts_of(jget(p, "content"))
    .filter_map(t => if person { typed(t) } else { Some(t) })
    .filter(t => white_trim(t) != "" && !(person && (injected(t) || wrapped(t) || not_said(t))))
    .join("\n")
  if white_trim(text) == "" {
    []
  } else {
    [(person, white_trim(text))]
  }
}

///|
/// machine.ts `codexEventSaid`: item_completed with a UserMessage or AgentMessage item, user_message, agent_message.
fn codex_event_said(r : @jsjson.JValue) -> Array[(Bool, String)] {
  guard is_text(jget(Some(r), "type"), "event_msg") else { return [] }
  let p = jget(Some(r), "payload")
  let (person, text) = match str_of(jget(p, "type")) {
    Some("user_message") =>
      (
        true,
        match str_of(jget(p, "message")) {
          Some(m) => typed(m)
          None => None
        },
      )
    Some("agent_message") => (false, str_of(jget(p, "message")))
    Some("item_completed") => {
      let item = jget(p, "item")
      let person = match str_of(jget(item, "type")) {
        Some("UserMessage") => true
        Some("AgentMessage") => false
        _ => return []
      }
      let parts = texts_of(jget(item, "content"))
      (person, Some(parts.filter_map(t => if person { typed(t) } else { Some(t) }).join("\n")))
    }
    _ => return []
  }
  guard text is Some(text) else { return [] }
  let t = white_trim(text)
  if t != "" && !(person && (wrapped(t) || not_said(t))) {
    [(person, t)]
  } else {
    []
  }
}

///|
fn has_codex_events(records : Array[@jsjson.JValue]) -> Bool {
  records.iter().any(r => codex_event_said(r).iter().any(s => s.0))
}

///|
fn said_in(runtime : String, events : Bool, r : @jsjson.JValue) -> Array[(Bool, String)] {
  if runtime == "claude" {
    claude_said(r)
  } else if events {
    codex_event_said(r)
  } else {
    codex_said(r)
  }
}

///|
/// UTF-8 of a string as Buffer.from writes it (a lone surrogate as U+FFFD).
fn utf8_of(s : String) -> Array[Int] {
  let out = []
  for c in points(s) {
    let c = if c >= 0xd800 && c <= 0xdfff { 0xfffd } else { c }
    if c < 0x80 {
      out.push(c)
    } else if c < 0x800 {
      out.push(0xc0 | (c >> 6))
      out.push(0x80 | (c & 0x3f))
    } else if c < 0x10000 {
      out.push(0xe0 | (c >> 12))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    } else {
      out.push(0xf0 | (c >> 18))
      out.push(0x80 | ((c >> 12) & 0x3f))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    }
  }
  out
}

///|
/// transcript.ts `num`: str::parse::<i64> of a few bytes, digits with a sign at most (ASCII, so its bytes are its text).
fn iso_num(b : Array[Int], from : Int, len : Int) -> Int64? {
  if from + len > b.length() || len == 0 {
    return None
  }
  let mut i = from
  let mut sign = 1L
  if b[i] == '+' || b[i] == '-' {
    sign = if b[i] == '-' { -1L } else { 1L }
    i += 1
  }
  if i >= from + len {
    return None
  }
  let mut n = 0L
  while i < from + len {
    guard b[i] >= '0' && b[i] <= '9' else { return None }
    n = n * 10L + (b[i] - '0').to_int64()
    i += 1
  }
  Some(sign * n)
}

///|
/// transcript.ts `parseIso`: milliseconds of an ISO time (YYYY-MM-DDTHH:MM:SS[.fff]), read by position.
fn parse_iso(at : String) -> Double? {
  let b = utf8_of(at)
  guard iso_num(b, 0, 4) is Some(y) &&
    iso_num(b, 5, 2) is Some(mo) &&
    iso_num(b, 8, 2) is Some(d) &&
    iso_num(b, 11, 2) is Some(h) &&
    iso_num(b, 14, 2) is Some(mi) &&
    iso_num(b, 17, 2) is Some(s) else {
    return None
  }
  let mut ms = 0L
  if b.length() > 19 && b[19] == '.' {
    let mut digits = 0
    let mut i = 20
    while i < b.length() && b[i] >= '0' && b[i] <= '9' {
      if digits < 3 {
        ms = ms * 10L + (b[i] - '0').to_int64()
        digits += 1
      }
      i += 1
    }
    while digits < 3 {
      ms = ms * 10L
      digits += 1
    }
  }
  let (yy, mm) = if mo <= 2L { (y - 1L, mo + 9L) } else { (y, mo - 3L) }
  let era = if yy >= 0L { yy / 400L } else { -((-yy + 399L) / 400L) }
  let yoe = yy - era * 400L
  let doy = (153L * mm + 2L) / 5L + d - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  let days = era * 146097L + doe - 719468L
  Some(((days * 86400L + h * 3600L + mi * 60L + s) * 1000L + ms).to_double())
}

///|
/// machine.ts `conversation`: what was said in a session's transcript, oldest first, each turn's words of the agent in
/// one message.
fn conversation(host : @host.Host, runtime : String, path : String) -> Array[(Bool, String, Double?)] raise {
  let records = records_of(host, path)
  let events = runtime == "codex" && has_codex_events(records)
  let out : Array[(Bool, String, Double?)] = []
  for r in records {
    let at = match str_of(jget(Some(r), "timestamp")) {
      Some(ts) => parse_iso(ts)
      None => None
    }
    for said in said_in(runtime, events, r) {
      let (person, text) = said
      if out.length() > 0 && !person && !out[out.length() - 1].0 {
        let last = out[out.length() - 1]
        out[out.length() - 1] = (last.0, last.1 + "\n\n" + text, last.2)
      } else {
        out.push((person, text, at))
      }
    }
  }
  out
}

// ---- the sessions ----

///|
/// machine.ts `stamp`: when a file was last written (ms) and its size.
fn stamp(host : @host.Host, path : String) -> (Double, Double)? raise {
  match host.shell_sync("fs.meta", { "path": Json::string(path) }) {
    { "size": Number(size, ..), "mtimeMs": Number(at, ..), .. } => Some((at, size))
    { "size": Number(size, ..), .. } => Some((0.0, size))
    _ => None
  }
}

///|
/// Path::extension: after the last dot of the name, unless that dot starts it.
fn extension(name : String) -> String? {
  match name.rev_find(".") {
    Some(dot) if dot > 0 => Some(name.view(start_offset=dot + 1).to_owned())
    _ => None
  }
}

///|
/// path.basename of a path joined here.
fn base_name(sep : String, path : String) -> String {
  let mut cut = -1
  for i in 0..<path.length() {
    let c = path.unsafe_charcode_at(i)
    if c == '/' || (sep == "\\" && c == '\\') {
      cut = i
    }
  }
  path.view(start_offset=cut + 1).to_owned()
}

///|
/// path.dirname of a path joined here.
fn dir_name(sep : String, path : String) -> String {
  let mut cut = -1
  for i in 0..<path.length() {
    let c = path.unsafe_charcode_at(i)
    if c == '/' || (sep == "\\" && c == '\\') {
      cut = i
    }
  }
  if cut < 0 {
    "."
  } else if cut == 0 {
    path.view(end_offset=1).to_owned()
  } else {
    path.view(end_offset=cut).to_owned()
  }
}

///|
/// machine.ts `rolloutsIn`: Codex's rollout-*.jsonl files under a directory, at any depth.
fn rollouts_in(host : @host.Host, sep : String, dir : String, out : Array[String]) -> Unit raise {
  for name in read_dir(host, dir, disk=true).unwrap_or([]) {
    let path = @nodepath.join(sep, [dir, name])
    if kind_of(host, path) == Some("dir") {
      rollouts_in(host, sep, path, out)
    } else if name.has_prefix("rollout-") && extension(name) == Some("jsonl") {
      out.push(path)
    }
  }
}

///|
/// machine.ts `rolloutOf`: a rollout file of a thread.
fn rollout_of(sep : String, path : String, id : String) -> Bool {
  let name = base_name(sep, path)
  name.has_suffix("-" + id + ".jsonl") || name.contains("-" + id + "_")
}

///|
/// machine.ts `tail`: the records in the last part of a file (whole lines only).
fn tail_records(host : @host.Host, path : String, size : Double) -> Array[@jsjson.JValue] raise {
  let from = if size > TAIL.to_double() { size - TAIL.to_double() } else { 0.0 }
  guard host.shell_sync("fs.from", { "path": Json::string(path), "from": Json::number(from) }) is String(text) else { return [] }
  let whole = if from > 0.0 {
    match text.find("\n") {
      Some(nl) => text.view(start_offset=nl + 1).to_owned()
      None => ""
    }
  } else {
    text
  }
  let lines = whole
    .split("\n")
    .map(v => {
      let l = v.to_owned()
      if l.has_suffix("\r") {
        l.view(end_offset=l.length() - 1).to_owned()
      } else {
        l
      }
    })
    .collect()
  if whole.has_suffix("\n") || whole == "" {
    ignore(lines.pop())
  }
  lines.filter_map(parse_record)
}

///|
/// machine.ts `claudeTitle`: the name given by hand, else the runtime's latest.
fn claude_title(records : Array[@jsjson.JValue]) -> String? {
  let latest = (kind : String, field : String) => {
    let mut found : @jsjson.JValue? = None
    for r in records.rev() {
      if is_text(jget(Some(r), "type"), kind) {
        found = Some(r)
        break
      }
    }
    match str_of(jget(found, field)) {
      Some(t) if white_trim(t) != "" => Some(white_trim(t))
      _ => None
    }
  }
  match latest("custom-title", "customTitle") {
    Some(t) => Some(t)
    None =>
      match latest("ai-title", "aiTitle") {
        Some(t) => Some(t)
        None => latest("summary", "summary")
      }
  }
}

///|
/// machine.ts `clip`: whitespace collapsed, at most `max` characters (and an ellipsis past them).
fn clip_to(text : String, max : Int) -> String {
  let line = @jscase.split_by(text, @jscase.is_white_space).filter(w => w != "").join(" ")
  let cps = points(line)
  if cps.length() <= max {
    return line
  }
  let out = StringBuilder::new()
  for c in cps[:max] {
    out.write_char(c.unsafe_to_char())
  }
  out.write_char('…')
  out.to_string()
}

///|
/// machine.ts `read`: a transcript as the pages list it; none when it ran nowhere or asked nothing.
fn read_session(host : @host.Host, sep : String, runtime : String, path : String, updated_at : Double, size : Double) -> MachineSession? raise {
  let head = records_of(host, path, limit=HEAD_RECORDS)
  let events = runtime == "codex" && has_codex_events(head)
  let mut first_said : String? = None
  for r in head {
    if said_in(runtime, events, r).iter().find_first(s => s.0) is Some(found) {
      first_said = Some(found.1)
      break
    }
  }
  guard first_said is Some(said) else { return None }
  let first = clip_to(said, FIRST)
  let (id, cwd) = if runtime == "claude" {
    let name = base_name(sep, path)
    let id = match name.rev_find(".") {
      Some(dot) if dot > 0 => name.view(end_offset=dot).to_owned()
      _ => name
    }
    (Some(id), head.iter().filter_map(r => str_of(jget(Some(r), "cwd"))).head())
  } else {
    guard head.iter().find_first(r => is_text(jget(Some(r), "type"), "session_meta")) is Some(found) else { return None }
    let meta = jget(Some(found), "payload")
    (str_of(jget(meta, "id")), str_of(jget(meta, "cwd")))
  }
  guard id is Some(id) && cwd is Some(cwd) else { return None }
  let records = head + tail_records(host, path, size)
  let title = if runtime == "claude" { claude_title(records) } else { None }
  let mut model : String? = None
  for r in records.rev() {
    let m = if runtime == "claude" {
      if is_text(jget(Some(r), "type"), "assistant") { jget(jget(Some(r), "message"), "model") } else { None }
    } else if is_text(jget(Some(r), "type"), "turn_context") {
      jget(jget(Some(r), "payload"), "model")
    } else {
      None
    }
    if str_of(m) is Some(name) && !name.has_prefix("<") {
      model = Some(name)
      break
    }
  }
  Some({ runtime, id, cwd, title, first, model, updated_at, size, session: None, path })
}

///|
/// machine.ts `codexNames`: the names Codex gave its threads (the latest line for an id counts).
fn codex_names(host : @host.Host, sep : String, r : Roots) -> Map[String, String] raise {
  let names : Map[String, String] = {}
  for v in records_of(host, @nodepath.join(sep, [dir_name(sep, r.codex), "session_index.jsonl"])) {
    if str_of(jget(Some(v), "id")) is Some(id) && str_of(jget(Some(v), "thread_name")) is Some(name) && white_trim(name) != "" {
      names[id] = white_trim(name)
    }
  }
  names
}

///|
fn named(s : MachineSession, names : Map[String, String]) -> MachineSession {
  if s.title is None {
    s.title = names.get(s.id)
  }
  s
}

///|
/// A stable sort, newest first (Array.prototype.sort is stable: equally recent files keep the file system's order).
fn[T] newest_first(xs : Array[(T, Double)]) -> Array[T] {
  let n = xs.length()
  let mut a = xs.copy()
  let mut width = 1
  while width < n {
    let b : Array[(T, Double)] = []
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      while i < mid || j < hi {
        if j >= hi || (i < mid && a[i].1 >= a[j].1) {
          b.push(a[i])
          i += 1
        } else {
          b.push(a[j])
          j += 1
        }
      }
      lo = hi
    }
    a = b
    width *= 2
  }
  a.map(x => x.0)
}

///|
/// machine.ts `list`: the machine's sessions, most recently written first, at most `limit`.
fn list_sessions(host : @host.Host, sep : String, r : Roots, limit : Int) -> Array[MachineSession] raise {
  let files : Array[((String, String, Double, Double), Double)] = []
  for dir in read_dir(host, r.claude, disk=true).unwrap_or([]) {
    let d = @nodepath.join(sep, [r.claude, dir])
    for file in read_dir(host, d, disk=true).unwrap_or([]) {
      let path = @nodepath.join(sep, [d, file])
      if extension(file) != Some("jsonl") {
        continue
      }
      if stamp(host, path) is Some((at, size)) {
        files.push((("claude", path, at, size), at))
      }
    }
  }
  let rollouts = []
  rollouts_in(host, sep, r.codex, rollouts)
  for path in rollouts {
    if stamp(host, path) is Some((at, size)) {
      files.push((("codex", path, at, size), at))
    }
  }
  let sorted = newest_first(files)
  let names = codex_names(host, sep, r)
  let seen : Set[String] = Set::new()
  let out = []
  for f in sorted {
    if out.length() >= limit {
      break
    }
    let (runtime, path, at, size) = f
    guard read_session(host, sep, runtime, path, at, size) is Some(s) else { continue }
    let key = s.runtime + "\u{0}" + s.id
    if seen.contains(key) {
      continue
    }
    seen.add(key)
    out.push(named(s, names))
  }
  out
}

///|
/// machine.ts `find`: one of the machine's sessions, by its runtime and id.
fn find_session(host : @host.Host, sep : String, r : Roots, runtime : String, id : String) -> MachineSession? raise {
  guard id != "" && id.iter().all(c => (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') else {
    return None
  }
  let mut path : String? = None
  if runtime == "claude" {
    for d in read_dir(host, r.claude, disk=true).unwrap_or([]) {
      let p = @nodepath.join(sep, [r.claude, d, id + ".jsonl"])
      if kind_of(host, p) == Some("file") {
        path = Some(p)
        break
      }
    }
  } else {
    let rollouts = []
    rollouts_in(host, sep, r.codex, rollouts)
    let mine = []
    for p in rollouts {
      if rollout_of(sep, p, id) && stamp(host, p) is Some((at, _)) {
        mine.push((p, at))
      }
    }
    for p in newest_first(mine) {
      if stamp(host, p) is Some((at, size)) && read_session(host, sep, runtime, p, at, size) is Some(s) && s.id == id {
        path = Some(p)
        break
      }
    }
  }
  guard path is Some(path) else { return None }
  guard stamp(host, path) is Some((at, size)) else { return None }
  match read_session(host, sep, runtime, path, at, size) {
    Some(s) if s.id == id => Some(named(s, codex_names(host, sep, r)))
    _ => None
  }
}

///|
fn text_or_null(s : String?) -> Json {
  match s {
    Some(t) => Json::string(t)
    None => Json::null()
  }
}

///|
/// A MachineSession as serde writes it, `path` left out.
fn shown_machine(s : MachineSession) -> Json {
  {
    "runtime": Json::string(s.runtime),
    "id": Json::string(s.id),
    "cwd": Json::string(s.cwd),
    "title": text_or_null(s.title),
    "first": Json::string(s.first),
    "model": text_or_null(s.model),
    "updatedAt": Json::number(s.updated_at),
    "size": Json::number(s.size),
    "session": text_or_null(s.session),
  }
}

///|
fn roots_of(args : Json) -> Roots raise {
  guard args.value("roots") is Some({ "claude": String(claude), "codex": String(codex), .. }) else {
    fail("no roots for the machine's sessions")
  }
  { claude, codex }
}

///|
/// store.ts `sessionOfRuntime`: the station's session going on with a runtime's session (the latest active of two).
fn session_of_runtime(db : @sql.Db, runtime : String, id : String) -> String? raise {
  let sql =
    #|SELECT key FROM (
    #|    SELECT key, last_active_at FROM sessions s WHERE runtime_session_id = ?2 AND runtime = ?1
    #|      AND NOT EXISTS (SELECT 1 FROM runtime_sessions r WHERE r.session_key = s.key AND r.id = ?2 AND COALESCE(r.runtime, s.original_runtime, s.runtime) != ?1)
    #|    UNION ALL SELECT s.key, s.last_active_at FROM runtime_sessions r JOIN sessions s ON s.key = r.session_key WHERE r.id = ?2 AND COALESCE(r.runtime, s.original_runtime, s.runtime) = ?1
    #|  ) ORDER BY last_active_at DESC LIMIT 1
  match one(db, sql, [Json::string(runtime), Json::string(id)]) {
    Some(row) =>
      match field(row, "key") {
        String(k) => Some(k)
        _ => None
      }
    None => None
  }
}

///|
/// GET /machine-sessions: the machine's latest 100, each with the station's session already going on with it.
pub fn machine_sessions(db : @sql.Db, host : @host.Host, sep : String, args : Json) -> Json raise {
  let found = list_sessions(host, sep, roots_of(args), 100)
  for m in found {
    m.session = session_of_runtime(db, m.runtime, m.id)
  }
  { "sessions": Json::array(found.map(shown_machine)) }
}

///|
/// The `limit` of GET /machine-sessions/:runtime/:id as str::parse::<usize> reads it (digits, a `+` before them at
/// most, no more than a u64 holds; else 200), kept to 1–1000.
fn said_limit(v : Json?) -> Int {
  let text = match v {
    Some(String(s)) => s
    Some(Number(n, ..)) if n >= 0.0 && n == n.floor() && n < 1.0e21 => n.to_int64().to_string()
    _ => return 200
  }
  let digits = if text.has_prefix("+") { text.view(start_offset=1).to_owned() } else { text }
  guard digits != "" && digits.iter().all(c => c >= '0' && c <= '9') else { return 200 }
  let mut i = 0
  while i < digits.length() - 1 && digits.unsafe_charcode_at(i) == '0' {
    i += 1
  }
  let bare = digits.view(start_offset=i).to_owned()
  if bare.length() > 20 {
    return 200
  }
  if bare.length() == 20 {
    let most = "18446744073709551615"
    for k in 0..<20 {
      let (a, b) = (bare.unsafe_charcode_at(k), most.unsafe_charcode_at(k))
      if a != b {
        if a > b {
          return 200
        }
        break
      }
    }
  }
  if bare.length() > 4 {
    return 1000
  }
  let mut n = 0
  for c in bare {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  if n < 1 {
    1
  } else if n > 1000 {
    1000
  } else {
    n
  }
}

///|
/// GET /machine-sessions/:runtime/:id: one of them to look at before going on with it, with the latest `limit` of
/// what was said.
pub fn machine_session(db : @sql.Db, host : @host.Host, sep : String, args : Json) -> Json raise {
  let runtime = match args.value("runtime") {
    Some(String(r)) => r
    Some(v) => v.stringify()
    None => "undefined"
  }
  if runtime != "claude" && runtime != "codex" {
    raise Refused(404, "no runtime \{runtime}")
  }
  let id = match args.value("id") {
    Some(String(i)) => i
    _ => ""
  }
  let limit = said_limit(args.value("limit"))
  guard find_session(host, sep, roots_of(args), runtime, id) is Some(found) else {
    let en = args.value("lang") is Some(String("en"))
    raise Refused(404, if en { "No such local session: \{id}" } else { "本机没有这个会话：\{id}" })
  }
  let said = conversation(host, runtime, found.path)
  found.session = session_of_runtime(db, runtime, found.id)
  let total = said.length()
  let from = if total > limit { total - limit } else { 0 }
  {
    "session": shown_machine(found),
    "total": Json::number(total.to_double()),
    "said": Json::array(
      said[from:]
      .iter()
      .map(s => ({
        "person": Json::boolean(s.0),
        "text": Json::string(s.1),
        "at": match s.2 {
          Some(t) => Json::number(t)
          None => Json::null()
        },
      } : Json))
      .collect(),
    ),
  }
}
