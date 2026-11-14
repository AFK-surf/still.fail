// What Claude Code's stream-json frames do to a session, as station/src/agents/claude.ts (`onFrame`, `toolsLostIn`)
// and station/src/agents/live.ts (`LiveFromClaude`) say: where its turn stands, its tasks, the live steps a device is
// shown, the station's tools out of reach. Frames are read as JSON.parse reads them and what is said of them written
// as JSON.stringify writes it (station/jsjson), so what is told Node is what the TypeScript made of the same lines.
// What needs the TypeScript's regular expressions (a failure's reason, whether a tool's error says it was out of reach)
// is left to Node with the text it is of (`classify`, `lostIf`).

///|
using @jsjson {type JValue}

///|
type J = JValue

///|
fn u(s : String) -> Array[Int] {
  @jsjson.units(s)
}

///|
fn jstr(s : String) -> J {
  Str(u(s))
}

///|
fn field(v : J?, name : String) -> J? {
  match v {
    Some(Obj(_) as o) => o.get(name)
    _ => None
  }
}

///|
/// A string's code units (`typeof v === "string"`).
fn text_of(v : J?) -> Array[Int]? {
  match v {
    Some(Str(s)) => Some(s)
    _ => None
  }
}

///|
fn is_str(v : J?, s : String) -> Bool {
  text_of(v) is Some(t) && t == u(s)
}

///|
fn is_true(v : J?) -> Bool {
  v is Some(Bool(true))
}

///|
/// `Number.isInteger(v)`.
fn integer(v : J?) -> Double? {
  match v {
    Some(Num(d)) if !d.is_nan() && !d.is_inf() && d == d.floor() => Some(d)
    _ => None
  }
}

///|
fn obj(fields : Array[(String, J)]) -> J {
  Obj(fields.map(f => (u(f.0), f.1)))
}

///|
/// At most `n` characters (live.ts `chars`: Array.from, a lone surrogate one).
pub fn chars(text : Array[Int], n : Int) -> Array[Int] {
  if text.length() <= n {
    return text
  }
  let out = []
  let mut count = 0
  let mut i = 0
  while i < text.length() && count < n {
    let c = text[i]
    if c >= 0xd800 && c <= 0xdbff && i + 1 < text.length() && text[i + 1] >= 0xdc00 && text[i + 1] <= 0xdfff {
      out.push(c)
      out.push(text[i + 1])
      i += 2
    } else {
      out.push(c)
      i += 1
    }
    count += 1
  }
  out
}

///|
fn has_prefix(s : Array[Int], p : String) -> Bool {
  let q = u(p)
  s.length() >= q.length() && s[0:q.length()].to_array() == q
}

///|
fn join_units(parts : Array[Array[Int]], sep : Array[Int]) -> Array[Int] {
  let out = []
  for i, p in parts {
    if i > 0 {
      out.append(sep)
    }
    out.append(p)
  }
  out
}

///|
/// A JavaScript number as `${n}` says it.
fn number_text(d : Double) -> Array[Int] {
  u(@jsjson.stringify(Num(d)))
}

///|
/// A task it runs, as claude.ts `Task` keeps it.
pub(all) struct Task {
  id : Array[Int]
  kind : String
  description : Array[Int]
  background : Bool
  started_at : Double?
}

///|
/// Where its turn stands (claude.ts `Turn`).
pub(all) struct Turn {
  mut busy : Bool
  mut aborting : Bool
  mut auth_failure : Array[Int]?
  mut closed : Bool
  mut renews : Bool?
  mut renewed : Bool?
  /// by id, as the object keeps them (Object.values' order: `ordered`)
  mut tasks : Array[(Array[Int], Task)]?
  mut compacting : Bool?
  mut compact_error : Array[Int]?
}

///|
pub fn Turn::new() -> Turn {
  {
    busy: false,
    aborting: false,
    auth_failure: None,
    closed: false,
    renews: None,
    renewed: None,
    tasks: None,
    compacting: None,
    compact_error: None,
  }
}

///|
/// An array index's number, which JavaScript orders before the other keys of an object.
fn index_key(key : Array[Int]) -> Double? {
  if key.length() == 0 || key.length() > 10 || (key.length() > 1 && key[0] == 0x30) {
    return None
  }
  let mut v = 0.0
  for c in key {
    if c < 0x30 || c > 0x39 {
      return None
    }
    v = v * 10.0 + (c - 0x30).to_double()
  }
  if v < 4294967295.0 { Some(v) } else { None }
}

///|
/// An object's entries in the order JavaScript gives them: array indices first, ascending, then as they were put.
fn ordered(entries : Array[(Array[Int], Task)]) -> Array[(Array[Int], Task)] {
  let indexed = entries.filter(e => index_key(e.0) is Some(_))
  indexed.sort_by((a, b) => index_key(a.0).unwrap().compare(index_key(b.0).unwrap()))
  indexed + entries.filter(e => index_key(e.0) is None)
}

///|
/// `{ ...tasks, [id]: task }`: in its place where it was there, else after the rest.
fn put(entries : Array[(Array[Int], Task)], id : Array[Int], task : Task) -> Array[(Array[Int], Task)] {
  let out = ordered(entries)
  for i, e in out {
    if e.0 == id {
      out[i] = (id, task)
      return out
    }
  }
  out.push((id, task))
  out
}

///|
/// claude.ts `backgroundOf`: what of its tasks runs in the background.
pub fn background_of(turn : Turn) -> J {
  let out = []
  for e in ordered(turn.tasks.unwrap_or([])) {
    let t = e.1
    if !t.background {
      continue
    }
    let fields : Array[(String, J)] = [("id", Str(t.id)), ("kind", jstr(t.kind)), ("description", Str(t.description))]
    if t.started_at is Some(at) {
      fields.push(("startedAt", Num(at)))
    }
    out.push(obj(fields))
  }
  Arr(out)
}

///|
/// claude.ts `RENEW_ATTEMPTS`.
const RENEW_ATTEMPTS : Double = 2.0

///|
/// What a frame does to the turn (claude.ts `onFrame`): events said with `emit`, `interrupt` how an authentication
/// failure stops the turn, `now` the time a task starts, `note` what is logged.
pub fn on_frame(
  frame : J,
  turn : Turn,
  emit : (J) -> Unit,
  interrupt : () -> Unit,
  now : () -> Double,
  note : (String) -> Unit,
) -> Unit {
  let before = @jsjson.stringify(background_of(turn))
  frame_does(frame, turn, emit, interrupt, now, note)
  let tasks = background_of(turn)
  if @jsjson.stringify(tasks) != before {
    emit(obj([("type", jstr("live")), ("event", obj([("kind", jstr("tasks")), ("tasks", tasks)]))]))
  }
}

///|
fn frame_does(
  frame : J,
  turn : Turn,
  emit : (J) -> Unit,
  interrupt : () -> Unit,
  now : () -> Double,
  note : (String) -> Unit,
) -> Unit {
  let f = Some(frame)
  let kind = text_of(field(f, "type")).unwrap_or([])
  let subtype = text_of(field(f, "subtype")).unwrap_or([])
  let system = kind == u("system")
  if kind == u("control_response") && is_str(field(field(f, "response"), "subtype"), "error") {
    note("claude refused a control request")
  }
  if system && subtype == u("init") {
    let was = turn.busy
    turn.busy = true
    if !was {
      emit(obj([("type", jstr("turnStarted"))]))
    }
  } else if system && subtype == u("api_retry") {
    let status = integer(field(f, "error_status")).unwrap_or(0.0)
    let attempt = integer(field(f, "attempt")).unwrap_or(1.0)
    let renewing = status == 401.0 && turn.renews == Some(true) && turn.renewed != Some(true) && attempt <= RENEW_ATTEMPTS
    if (status == 401.0 || status == 403.0) && turn.auth_failure is None && !renewing {
      let error = match field(f, "error") {
        None => u("authentication failed")
        Some(Str(s)) => s
        Some(v) => u(@jsjson.stringify(v))
      }
      turn.auth_failure = Some(number_text(status) + [0x20] + error)
      interrupt()
      turn.aborting = true
    }
  } else if system &&
    subtype == u("task_started") &&
    text_of(field(f, "task_id")) is Some(id) &&
    !is_true(field(f, "owned_by_subagent")) {
    let description = text_of(field(f, "description")).unwrap_or([])
    let task = {
      id,
      kind: if is_str(field(f, "task_type"), "local_agent") { "agent" } else { "command" },
      description,
      background: is_true(field(f, "is_backgrounded")),
      started_at: Some(now()),
    }
    turn.tasks = Some(put(turn.tasks.unwrap_or([]), id, task))
  } else if system &&
    (subtype == u("task_notification") || subtype == u("task_updated")) &&
    text_of(field(f, "task_id")) is Some(id) &&
    turn.tasks is Some(tasks) &&
    tasks.iter().find_first(e => e.0 == id) is Some((_, task)) {
    let notified = subtype == u("task_notification")
    let status = if notified { field(f, "status") } else { field(field(f, "patch"), "status") }
    let rest = ordered(tasks).filter(e => e.0 != id)
    let ended = ["completed", "failed", "killed", "stopped"].iter().any(s => is_str(status, s))
    if notified || ended {
      turn.tasks = Some(rest)
    } else if is_true(field(field(f, "patch"), "is_backgrounded")) {
      turn.tasks = Some(put(rest, id, { ..task, background: true }))
    }
  } else if system && subtype == u("status") && turn.compacting == Some(true) && is_str(field(f, "compact_result"), "failed") {
    turn.compact_error = match text_of(field(f, "compact_error")) {
      Some(e) if e.length() > 0 => Some(e)
      _ => Some(u("compaction failed"))
    }
  } else if system && subtype == u("compact_boundary") {
    emit(obj([("type", jstr("compacted"))]))
  } else if kind == u("result") {
    let errors = match field(f, "errors") {
      Some(Arr(all)) =>
        all.filter_map(e => match e {
          Str(s) if @jscase.trim(@jsjson.raw_text(s)) != "" => Some(s)
          _ => None
        })
      _ => []
    }
    let text = match text_of(field(f, "result")) {
      Some(r) if @jscase.trim(@jsjson.raw_text(r)) != "" => r
      _ => if errors.length() > 0 { join_units(errors, [0x0a]) } else { subtype }
    }
    let outcome = if turn.auth_failure is Some(failure) {
      // (refused or auth: claude.ts `refused`, Node's to say)
      obj([("kind", jstr("failed")), ("auth", Str(failure))])
    } else if turn.aborting {
      obj([("kind", jstr("aborted"))])
    } else if is_true(field(f, "is_error")) {
      obj([("kind", jstr("failed")), ("classify", Str(text))])
    } else if turn.compact_error is Some(e) && e.length() > 0 {
      obj([("kind", jstr("failed")), ("reason", jstr("other")), ("message", Str(chars(e, 1000)))])
    } else {
      obj([("kind", jstr("completed"))])
    }
    turn.busy = false
    turn.aborting = false
    turn.auth_failure = None
    turn.renewed = Some(false)
    turn.compacting = Some(false)
    turn.compact_error = None
    if turn.tasks is Some(tasks) {
      turn.tasks = Some(ordered(tasks).filter(e => e.1.background))
    }
    emit(obj([("type", jstr("turnEnded")), ("outcome", outcome)]))
  }
}

///|
/// The station's calls of its own tools not answered yet, and what a frame says of those tools out of reach
/// (claude.ts `toolsLostIn`): a server that failed as the turn started, or a call's error saying so.
pub fn tools_lost_in(frame : J, calls : Array[Array[Int]]) -> Array[Int]? {
  let f = Some(frame)
  let kind = field(f, "type")
  let content = match field(field(f, "message"), "content") {
    Some(Arr(c)) => c
    _ => []
  }
  if is_str(kind, "system") && is_str(field(f, "subtype"), "init") && field(f, "mcp_servers") is Some(Arr(servers)) {
    let server = servers.iter().find_first(s => is_str(field(Some(s), "name"), "stillfail"))
    if server is Some(s) && is_str(field(Some(s), "status"), "failed") {
      return Some(u("the stillfail MCP server failed to connect"))
    }
  } else if is_str(kind, "assistant") {
    for c in content {
      let cc = Some(c)
      if is_str(field(cc, "type"), "tool_use") &&
        text_of(field(cc, "id")) is Some(id) &&
        text_of(field(cc, "name")) is Some(name) &&
        has_prefix(name, "mcp__stillfail__") &&
        !calls.contains(id) {
        calls.push(id)
      }
    }
  } else if is_str(kind, "user") {
    for c in content {
      let cc = Some(c)
      if !is_str(field(cc, "type"), "tool_result") {
        continue
      }
      let deleted = match text_of(field(cc, "tool_use_id")) {
        Some(id) =>
          match calls.search(id) {
            Some(at) => {
              calls.remove(at) |> ignore
              true
            }
            None => false
          }
        None => false
      }
      if !deleted || !is_true(field(cc, "is_error")) {
        continue
      }
      let text = match field(cc, "content") {
        Some(Str(s)) => s
        Some(Arr(parts)) => join_units(parts.map(x => text_of(field(Some(x), "text")).unwrap_or([])), [0x0a])
        _ => []
      }
      if unreachable(text) {
        return Some(chars(text, 300))
      }
    }
  }
  None
}

///|
/// A content block of the model's response being said (live.ts `Block`).
pub(all) struct Block {
  id : Array[Int]
  step : String
  tool : Array[Int]?
  mut input : Array[Int]?
  subagent : Array[Int]?
}

///|
/// Claude Code's partial messages as live steps (live.ts `LiveFromClaude`).
pub(all) struct Live {
  mut message : Array[Int]
  /// by index, as a Map keeps them
  mut blocks : Array[(Int, Block)]
  mut tools : Array[Array[Int]]
}

///|
pub fn Live::new() -> Live {
  { message: [], blocks: [], tools: [] }
}

///|
/// live.ts `INPUT_MOST`.
const INPUT_MOST : Int = 262144

///|
fn start(id : Array[Int], step : String, tool : Array[Int]?, input : Array[Int]?, parent : Array[Int]?) -> J {
  let fields : Array[(String, J)] = [("kind", jstr("start")), ("id", Str(id)), ("step", jstr(step))]
  if tool is Some(t) {
    fields.push(("tool", Str(t)))
  }
  if input is Some(i) {
    fields.push(("input", Str(i)))
  }
  if parent is Some(p) {
    fields.push(("subagent", Bool(true)))
    fields.push(("parent", Str(p)))
  }
  obj(fields)
}

///|
fn non_empty(v : J?) -> Array[Int]? {
  match v {
    Some(Str(s)) if s.length() > 0 => Some(s)
    _ => None
  }
}

///|
fn Live::block(self : Live, index : Int) -> Block? {
  for b in self.blocks {
    if b.0 == index {
      return Some(b.1)
    }
  }
  None
}

///|
/// The live steps a frame says (live.ts `feed`); `now` names a message that says no id.
pub fn Live::feed(self : Live, frame : J, now : () -> Double) -> Array[J] {
  let out = []
  let f = Some(frame)
  let kind = text_of(field(f, "type")).unwrap_or([])
  let phase = (p : String) => obj([("kind", jstr("phase")), ("phase", jstr(p))])
  if kind == u("system") && is_str(field(f, "subtype"), "status") && is_str(field(f, "status"), "requesting") {
    out.push(phase("requesting"))
  } else if kind == u("stream_event") {
    let e = match field(f, "event") {
      None | Some(Null) => None
      some => some
    }
    let parent = non_empty(field(f, "parent_tool_use_id"))
    let event = text_of(field(e, "type")).unwrap_or([])
    if event == u("message_stop") && parent is None {
      out.push(phase("working"))
    }
    let index = match integer(field(e, "index")) {
      Some(i) => i.to_int()
      None => -1
    }
    if event == u("message_start") {
      self.message = match text_of(field(field(e, "message"), "id")) {
        Some(id) => id
        None => number_text(now())
      }
      self.blocks = []
      if parent is None {
        out.push(phase("responding"))
      }
    } else if event == u("content_block_start") {
      let b = field(e, "content_block")
      let step = match text_of(field(b, "type")) {
        Some(t) if t == u("text") => "text"
        Some(t) if t == u("thinking") => "thinking"
        Some(t) if t == u("tool_use") => "tool"
        _ => return out
      }
      let id = match text_of(field(b, "id")) {
        Some(id) if step == "tool" => id
        _ => self.message + u(":") + number_text(index.to_double())
      }
      let tool = if step == "tool" { Some(text_of(field(b, "name")).unwrap_or(u("tool"))) } else { None }
      if step == "tool" && !self.tools.contains(id) {
        self.tools.push(id)
      }
      out.push(start(id, step, tool, None, parent))
      let block = { id, step, tool, input: if tool is Some(_) { Some([]) } else { None }, subagent: parent }
      let mut placed = false
      for i, kept in self.blocks {
        if kept.0 == index {
          self.blocks[i] = (index, block)
          placed = true
          break
        }
      }
      if !placed {
        self.blocks.push((index, block))
      }
    } else if event == u("content_block_delta") {
      guard self.block(index) is Some(block) else { return out }
      let d = field(e, "delta")
      let delta = (name : String, text : Array[Int]) => obj([
        ("kind", jstr("delta")),
        ("id", Str(block.id)),
        ("field", jstr(name)),
        ("text", Str(text)),
      ])
      match text_of(field(d, "type")) {
        Some(t) if t == u("text_delta") =>
          if non_empty(field(d, "text")) is Some(text) {
            out.push(delta("text", text))
          }
        Some(t) if t == u("thinking_delta") =>
          if non_empty(field(d, "thinking")) is Some(text) {
            out.push(delta("text", text))
          } else if field(d, "estimated_tokens") is Some(Num(n)) && n > 0.0 {
            out.push(obj([("kind", jstr("delta")), ("id", Str(block.id)), ("field", jstr("text")), ("text", Str([])), ("tokens", Num(n))]))
          }
        Some(t) if t == u("input_json_delta") =>
          if non_empty(field(d, "partial_json")) is Some(partial) {
            if block.input is Some(input) && input.length() < INPUT_MOST {
              block.input = Some(input + partial)
            }
            out.push(delta("input", partial))
          }
        _ => ()
      }
    } else if event == u("content_block_stop") {
      if self.block(index) is Some(block) {
        if block.step != "tool" {
          out.push(obj([("kind", jstr("end")), ("id", Str(block.id))]))
        } else if block.input is Some(input) && input.length() > 0 {
          out.push(start(block.id, "tool", block.tool, Some(input), block.subagent))
        }
      }
    }
  } else if kind == u("user") {
    let content = match field(field(f, "message"), "content") {
      Some(Arr(c)) => c
      _ => []
    }
    for c in content {
      let cc = Some(c)
      let id = text_of(field(cc, "tool_use_id")).unwrap_or([])
      guard is_str(field(cc, "type"), "tool_result") && self.tools.contains(id) else { continue }
      let text = match field(cc, "content") {
        Some(Str(s)) => s
        Some(Arr(parts)) => join_units(parts.map(x => text_of(field(Some(x), "text")).unwrap_or([])), [0x0a])
        _ => []
      }
      if text.length() > 0 {
        out.push(obj([("kind", jstr("delta")), ("id", Str(id)), ("field", jstr("output")), ("text", Str(chars(text, 8000)))]))
      }
      out.push(obj([("kind", jstr("end")), ("id", Str(id))]))
      match self.tools.search(id) {
        Some(at) => self.tools.remove(at) |> ignore
        None => ()
      }
    }
  }
  out
}

///|
/// What it keeps between frames (live.ts `state`), as JSON.
pub fn Live::state(self : Live) -> J {
  let blocks = self.blocks.map(b => {
    let k = b.1
    let fields : Array[(String, J)] = [("id", Str(k.id)), ("step", jstr(k.step))]
    if k.tool is Some(t) {
      fields.push(("tool", Str(t)))
    }
    if k.input is Some(i) {
      fields.push(("input", Str(i)))
    }
    if k.subagent is Some(s) {
      fields.push(("subagent", Str(s)))
    }
    (Arr([Num(b.0.to_double()), obj(fields)]) : J)
  })
  obj([("message", Str(self.message)), ("blocks", Arr(blocks)), ("tools", Arr(self.tools.map(t => Str(t))))])
}

///|
/// The live state a snapshot said (live.ts's constructor).
pub fn Live::of_state(state : J) -> Live {
  let s = Some(state)
  let blocks = match field(s, "blocks") {
    Some(Arr(all)) =>
      all.filter_map(e => match e {
        Arr([Num(i), Obj(_) as b]) => {
          let bb = Some(b)
          Some((i.to_int(), {
            id: text_of(field(bb, "id")).unwrap_or([]),
            step: if is_str(field(bb, "step"), "tool") { "tool" } else if is_str(field(bb, "step"), "thinking") { "thinking" } else { "text" },
            tool: text_of(field(bb, "tool")),
            input: text_of(field(bb, "input")),
            subagent: text_of(field(bb, "subagent")),
          }))
        }
        _ => None
      })
    _ => []
  }
  let tools = match field(s, "tools") {
    Some(Arr(all)) => all.filter_map(t => text_of(Some(t)))
    _ => []
  }
  { message: text_of(field(s, "message")).unwrap_or([]), blocks, tools }
}

///|
/// runtime.ts `unreachable`: its words, ASCII letters in either case (a regular expression's `i` folds no other letter
/// to one of those).
pub fn unreachable(text : Array[Int]) -> Bool {
  let lower = text.map(c => if c >= 0x41 && c <= 0x5a { c + 32 } else { c })
  [
    "econnrefused", "econnreset", "unable to connect", "is not connected", "fetch failed", "socket hang up", "connection refused",
    "failed to connect to mcp server",
  ].iter().any(w => contains(lower, u(w)))
}

///|
fn contains(s : Array[Int], w : Array[Int]) -> Bool {
  if w.length() == 0 {
    return true
  }
  for i = 0; i + w.length() <= s.length(); i = i + 1 {
    let mut j = 0
    while j < w.length() && s[i + j] == w[j] {
      j += 1
    }
    if j == w.length() {
      return true
    }
  }
  false
}
