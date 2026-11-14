// The Claude Code processes' output read here, not by the station's Node (`--agents`): Node starts each process under
// its runner (station/src/agents/runner.ts) and tells this program to attach to the runner's socket, which it reads as
// station/src/agents/runner.ts `RunnerConnection` does (its messages a line of JSON each, stdout and stderr in base64,
// from where the last station acknowledged). Each line of stdout is a frame of Claude Code's stream-json, which it
// reads as station/src/agents/claude.ts does (`heard`: the live steps, the station's tools out of reach, a token asked
// for, what it does to the turn: station/mb/src/claude) and tells Node what that comes to: the runtime's events, where
// the turn stands, up to where it read. Node acknowledges each once its session took them, and only then is the line
// acknowledged to the runner, so a station that crashes reads again exactly what no session took.
//
// Node says on stdin, a line of JSON each: `wall` (its clock), `attach` (a session's runner: its socket, the turn and
// the live steps as Node knows them), `ack` (what of a session's Node took), `write` (a line to its stdin), `signal`,
// `begin` (a prompt's turn begun: `compact` for a /compact), `aborting`, `renewed`, `done` (read to the end: its runner
// may go), `detach` (let go for the next station), `freeze` and `thaw` (its lines held while the station hands over).
// It says on stdout `lines` (a session's events, its turn, up to where), `exit` (how its process ended, its last lines
// of stderr), `closed` (the runner's socket closed with no exit said), `left` (let go), `frozen` (each session's turn
// and live steps as they stand).

///|
priv struct Hosted {
  n : Int
  mut conn : Json
  /// what is written to the runner, in order (None: its side closed after)
  outq : @effect.Queue[Bytes?]
  turn : @claude.Turn
  live : @claude.Live
  calls : Array[Array[Int]]
  /// what is held of each stream's line not ended yet
  mut out_part : Bytes
  mut err_part : Bytes
  /// where each stream's next line starts, as the runner counts bytes (-1: not said yet)
  mut out_at : Int64
  mut err_at : Int64
  mut acked_out : Int64
  mut acked_err : Int64
  /// the end of the last line told Node
  mut told : Int64
  /// its lines given Node as they are (a Codex app-server's: Node reads them, `lines`), not read here as Claude Code's
  lines_only : Bool
  /// up to where of stdout the runner may give the disk back, told with each ack (runner.ts `keep`)
  mut keep : Int64?
  /// lines that came while frozen, each with where it ends
  held : Array[(Bytes, Int64)]
  mut frozen : Bool
  /// What a step writes as it goes (the model's words, its thinking, a call's input), held a while and told Node as
  /// one (`DELTAS_MS`): up to where of stdout it was read, and whether its telling is under way
  mut pending : Array[@jsjson.JValue]
  mut pending_to : Int64
  mut later : Bool
  mut left : Bool
  mut exited : Bool
  stderr : Array[String]
}

///|
priv struct Agents {
  host : @host.Host
  sessions : Map[Int, Hosted]
  /// the wall's time when Node last said it, and this clock's then
  mut wall : Double
  mut at : Int64
}

///|
fn Agents::now(self : Agents) -> Double {
  self.wall + (@host.now() - self.at).to_double()
}

///|
pub async fn serve_agents(host : @host.Host) -> Unit {
  let a : Agents = { host, sessions: Map([]), wall: 0.0, at: @host.now() }
  host.say(({ "ready": true } : Json).stringify())
  while host.line() is Some(line) {
    a.told(line)
  }
  @host.exit(0)
}

///|
fn number(v : Json?) -> Int? {
  match v {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
fn Agents::told(self : Agents, line : String) -> Unit {
  let said = @json.parse(line) catch { _ => return }
  match said {
    { "wall": Number(w, ..), .. } => {
      self.wall = w
      self.at = @host.now()
    }
    { "attach": Number(n, ..), "socket": String(socket), .. } => {
      let turn = turn_of(said.value("turn"))
      let live = match said.value("live") {
        Some(Null) | None => @claude.Live::new()
        Some(state) => @claude.Live::of_state(@jsjson.parse(state.stringify()) catch { _ => Null })
      }
      // (taken in now: what Node says of it next is had in order, whenever its socket opens)
      let h = hosted(n.to_int(), turn, live, lines_only=said.value("kind") == Some(Json::string("lines")))
      self.sessions[h.n] = h
      ignore(self.host.rt.fork(name="agent", () => self.attach(h, socket)))
    }
    _ => ()
  }
  let n = match said {
    { "ack": Number(n, ..), .. }
    | { "write": Number(n, ..), .. }
    | { "signal": Number(n, ..), .. }
    | { "begin": Number(n, ..), .. }
    | { "aborting": Number(n, ..), .. }
    | { "renewed": Number(n, ..), .. }
    | { "done": Number(n, ..), .. }
    | { "detach": Number(n, ..), .. }
    | { "thaw": Number(n, ..), .. }
    | { "keep": Number(n, ..), .. } => n.to_int()
    { "freeze": Number(id, ..), .. } => {
      let states : Map[String, Json] = {}
      let only = match said.value("only") {
        Some(Array(ns)) => ns.filter_map(x => match x { Number(k, ..) => Some(k.to_int()); _ => None })
        _ => []
      }
      for k, h in self.sessions {
        if !only.contains(k) {
          continue
        }
        // (what it holds told first: the state said next is of all it read)
        self.flush(h)
        h.frozen = true
        states[k.to_string()] = Json::object({
          "turn": turn_json(h.turn),
          "live": @json.parse(@jsjson.stringify(h.live.state())) catch { _ => Json::null() },
        })
      }
      self.host.say(({ "frozen": Json::number(id), "states": Json::object(states) } : Json).stringify())
      return
    }
    _ => return
  }
  guard self.sessions.get(n) is Some(h) else { return }
  match said {
    { "ack": _, "to": Number(to, ..), .. } => {
      let to = to.to_int64()
      if to > h.acked_out {
        h.acked_out = to
        self.ack(h)
      }
    }
    { "write": _, "line": String(text), .. } => self.write(h, text)
    { "signal": _, "name": String(signal), .. } =>
      self.send(h, { "op": "signal", "signal": Json::string(signal), "group": true })
    { "begin": _, .. } => {
      h.turn.renewed = Some(false)
      h.turn.busy = true
      if said.value("compact") is Some(True) {
        h.turn.compacting = Some(true)
        h.turn.compact_error = None
      }
    }
    { "aborting": _, .. } => h.turn.aborting = true
    { "renewed": _, .. } => h.turn.renewed = Some(true)
    { "keep": _, "at": Number(at, ..), .. } => h.keep = Some(at.to_int64())
    { "done": _, .. } => {
      self.send(h, { "op": "done" })
      self.end(h)
    }
    { "detach": _, .. } => {
      h.frozen = true
      h.left = true
      h.held.clear()
      self.end(h)
    }
    { "thaw": _, .. } => {
      h.frozen = false
      let held = h.held.copy()
      h.held.clear()
      if held.length() > 0 {
        self.heard(h, held)
      }
    }
    _ => ()
  }
}

///|
fn Agents::send(self : Agents, h : Hosted, message : Json) -> Unit {
  ignore(self)
  ignore(h.outq.try_offer(Some(@utf8.encode(message.stringify() + "\n"))))
}

///|
/// Its side of the runner's socket closed: the runner reads to there and closes it too.
fn Agents::end(self : Agents, h : Hosted) -> Unit {
  ignore(self)
  ignore(h.outq.try_offer(None))
}

///|
fn Agents::write(self : Agents, h : Hosted, text : String) -> Unit {
  let line = if text.has_suffix("\n") { text } else { text + "\n" }
  self.send(h, { "op": "write", "data": Json::string(@base64.encode(@utf8.encode(line)[:])) })
}

///|
/// What of its output was taken said to the runner, which sends a next station only the rest.
fn Agents::ack(self : Agents, h : Hosted) -> Unit {
  if h.left {
    return
  }
  let ack : Map[String, Json] = {
    "op": "ack",
    "out": Json::number(h.acked_out.to_double()),
    "err": Json::number(h.acked_err.to_double()),
  }
  if h.keep is Some(k) {
    ack["keep"] = Json::number(k.to_double())
  }
  self.send(h, Json::object(ack))
}

///|
fn hosted(n : Int, turn : @claude.Turn, live : @claude.Live, lines_only~ : Bool) -> Hosted {
  {
    n,
    lines_only,
    keep: None,
    conn: Json::null(),
    outq: @effect.Queue::unbounded(),
    turn,
    live,
    calls: [],
    out_part: b"",
    err_part: b"",
    out_at: -1L,
    err_at: -1L,
    acked_out: 0L,
    acked_err: 0L,
    told: 0L,
    held: [],
    frozen: false,
    pending: [],
    pending_to: 0L,
    later: false,
    left: false,
    exited: false,
    stderr: [],
  }
}

///|
async fn Agents::attach(self : Agents, h : Hosted, socket : String) -> Unit {
  let n = h.n
  let opened = try { Ok(self.host.shell("unix.open", { "path": Json::string(socket) })) } catch { e => Err(e) }
  guard opened is Ok(({ "id": conn, .. }, _)) else {
    self.sessions.remove(n)
    self.host.say(({ "closed": Json::number(n.to_double()) } : Json).stringify())
    return
  }
  h.conn = conn
  // (what is written to it, one at a time in order)
  ignore(
    self.host.rt.fork(name="agent write", () => {
      // (attached first: what Node said meanwhile comes after)
      ignore(self.host.shell("tcp.write", { "id": conn }, bytes=@utf8.encode(({ "op": "attach" } : Json).stringify() + "\n"))) catch {
        _ => ()
      }
      while (try { h.outq.take() } catch { _ => None }) is Some(bytes) {
        ignore(self.host.shell("tcp.write", { "id": conn }, bytes~)) catch { _ => () }
      }
      ignore(self.host.shell("tcp.end", { "id": conn })) catch { _ => () }
    }),
  )
  let mut carry = b""
  while true {
    let read = try { Ok(self.host.shell("tcp.read", { "id": conn })) } catch { e => Err(e) }
    guard read is Ok((said, Some(bytes))) && !(said is { "end": true, .. }) && bytes.length() > 0 else { break }
    carry = carry + bytes
    let mut from = 0
    for i = 0; i < carry.length(); i = i + 1 {
      if carry[i] == b'\n' {
        let message = @json.parse(@utf8.decode_lossy(carry[from:i])) catch { _ => Json::null() }
        from = i + 1
        if !h.left {
          self.message(h, message)
        }
      }
    }
    carry = carry[from:].to_bytes()
  }
  self.sessions.remove(n)
  ignore(self.host.shell("tcp.close", { "id": conn })) catch { _ => () }
  if h.left {
    self.host.say(({ "left": Json::number(n.to_double()) } : Json).stringify())
  } else if !h.exited {
    self.host.say(({ "closed": Json::number(n.to_double()) } : Json).stringify())
  } else {
    self.host.say(({ "ended": Json::number(n.to_double()) } : Json).stringify())
  }
}

///|
/// A message of the runner's.
fn Agents::message(self : Agents, h : Hosted, message : Json) -> Unit {
  match message {
    { "op": "out", "stream": String(stream), "at": Number(at, ..), "data": String(data), .. } => {
      let bytes = @base64.decode(data) catch { _ => return }
      let err = stream == "err"
      if err && h.err_at < 0L {
        h.err_at = at.to_int64()
      } else if !err && h.out_at < 0L {
        h.out_at = at.to_int64()
      }
      let all = (if err { h.err_part } else { h.out_part }) + bytes
      let lines = []
      let mut from = 0
      for i = 0; i < all.length(); i = i + 1 {
        if all[i] == b'\n' {
          let line = all[from:i].to_bytes()
          if err {
            h.err_at = h.err_at + (line.length() + 1).to_int64()
          } else {
            h.out_at = h.out_at + (line.length() + 1).to_int64()
          }
          lines.push((line, if err { h.err_at } else { h.out_at }))
          from = i + 1
        }
      }
      let rest = all[from:].to_bytes()
      if err {
        h.err_part = rest
        for l in lines {
          let text = @jscase.trim(strip_cr(@utf8.decode_lossy(l.0)))
          if text != "" {
            h.stderr.push(text.view(end_offset=if text.length() > 300 { 300 } else { text.length() }).to_string())
            while h.stderr.length() > 3 {
              ignore(h.stderr.remove(0))
            }
          }
          h.acked_err = l.1
        }
        if lines.length() > 0 && h.told <= h.acked_out {
          self.ack(h)
        }
      } else {
        h.out_part = rest
        if lines.length() == 0 {
          return
        }
        if h.frozen {
          h.held.append(lines)
        } else {
          self.heard(h, lines)
        }
      }
    }
    { "op": "exit", .. } => {
      self.flush(h)
      h.exited = true
      self.host.say(
        ({
          "exit": Json::number(h.n.to_double()),
          "code": message.value("code").unwrap_or(Json::null()),
          "signal": message.value("signal").unwrap_or(Json::null()),
          "stderr": Json::string(h.stderr.join("\n")),
        } : Json).stringify(),
      )
    }
    _ => ()
  }
}

///|
fn strip_cr(s : String) -> String {
  if s.has_suffix("\r") {
    s.view(end_offset=s.length() - 1).to_string()
  } else {
    s
  }
}

///|
/// Lines of its stdout, each with where it ends: what they say told Node, or acknowledged at once where they say
/// nothing and nothing told is waiting.
fn Agents::heard(self : Agents, h : Hosted, lines : Array[(Bytes, Int64)]) -> Unit {
  if h.lines_only {
    self.given(h, lines)
    return
  }
  let before = @jsjson.stringify(turn_json_js(h.turn))
  let events : Array[@jsjson.JValue] = []
  for l in lines {
    let text = strip_cr(@utf8.decode_lossy(l.0))
    let frame = @jsjson.parse(text) catch { _ => continue }
    for e in h.live.feed(frame, () => self.now()) {
      events.push(@jsjson.JValue::Obj([(@jsjson.units("type"), Str(@jsjson.units("live"))), (@jsjson.units("event"), e)]))
    }
    if @claude.tools_lost_in(frame, h.calls) is Some(why) {
      events.push(Obj([(@jsjson.units("type"), Str(@jsjson.units("toolsLost"))), (@jsjson.units("why"), Str(why))]))
    }
    if renew_asked(frame) is Some(id) {
      events.push(Obj([(@jsjson.units("type"), Str(@jsjson.units("renew"))), (@jsjson.units("requestId"), Str(id))]))
    }
    @claude.on_frame(
      frame,
      h.turn,
      // (a turn's start and end said with the turn as it left it)
      e => events.push(
        match e {
          Obj(fields) if e.get("type") is Some(Str(t)) && (t == @jsjson.units("turnStarted") || t == @jsjson.units("turnEnded")) =>
            Obj(fields + [(@jsjson.units("turn"), turn_json_js(h.turn))])
          _ => e
        },
      ),
      () => self.write(h, interrupt_request(self.host)),
      () => self.now(),
      m => @host.note("agents: \{m}"),
    )
  }
  let end = lines[lines.length() - 1].1
  let turn = turn_json_js(h.turn)
  let same = @jsjson.stringify(turn) == before
  // (only what steps wrote: held, told with what comes next or once DELTAS_MS is over)
  if same && events.length() > 0 && events.iter().all(is_delta) {
    merge_into(h.pending, events)
    h.pending_to = end
    h.told = end
    self.soon(h)
    return
  }
  if same && events.length() == 0 {
    if h.pending.length() > 0 {
      h.pending_to = end
      h.told = end
      return
    }
    if h.told <= h.acked_out {
      h.acked_out = end
      h.told = end
      self.ack(h)
      return
    }
  }
  let all = h.pending
  h.pending = []
  merge_into(all, events)
  h.told = end
  self.tell(h, end, turn, all)
}

///|
/// How long what steps write is held before Node is told it (it only counts how fast the model writes: sessions/live.ts
/// `counted`, the agent's last words: actor.ts `heard`).
const DELTAS_MS : Int = 200

///|
fn Agents::tell(self : Agents, h : Hosted, to : Int64, turn : @jsjson.JValue, events : Array[@jsjson.JValue]) -> Unit {
  self.host.say(
    "{\"lines\":\{h.n},\"to\":\{to},\"turn\":\{@jsjson.stringify(turn)},\"events\":\{@jsjson.stringify(Arr(events))}}",
  )
}

///|
/// What is held told Node now.
fn Agents::flush(self : Agents, h : Hosted) -> Unit {
  if h.pending.length() == 0 || h.left {
    return
  }
  let all = h.pending
  h.pending = []
  self.tell(h, h.pending_to, turn_json_js(h.turn), all)
}

///|
fn Agents::soon(self : Agents, h : Hosted) -> Unit {
  if h.later {
    return
  }
  h.later = true
  ignore(
    self.host.rt.fork(name="agent deltas", () => {
      @effect.sleep(DELTAS_MS)
      h.later = false
      self.flush(h)
    }),
  )
}

///|
fn is_delta(e : @jsjson.JValue) -> Bool {
  guard e.get("type") is Some(Str(t)) && t == @jsjson.units("live") else { return false }
  guard e.get("event") is Some(Obj(_) as ev) else { return false }
  ev.get("kind") is Some(Str(k)) && k == @jsjson.units("delta")
}

///|
/// `events` after `out`, a step's deltas one after another of the same field told as one: their words joined, or the
/// tokens a runtime counted for them added up.
fn merge_into(out : Array[@jsjson.JValue], events : Array[@jsjson.JValue]) -> Unit {
  let u = @jsjson.units
  for e in events {
    if is_delta(e) && out.last() is Some(last) && is_delta(last) {
      let a = last.get("event").unwrap()
      let b = e.get("event").unwrap()
      let tokens = (v : @jsjson.JValue) => match v.get("tokens") {
        Some(Num(n)) => Some(n)
        _ => None
      }
      let text = (v : @jsjson.JValue) => match v.get("text") {
        Some(Str(t)) => t
        _ => []
      }
      let same_step = a.get("id") is Some(Str(x)) && b.get("id") is Some(Str(y)) && x == y &&
        a.get("field") is Some(Str(f)) && b.get("field") is Some(Str(g)) && f == g
      if same_step {
        match (tokens(a), tokens(b)) {
          (None, None) => {
            out[out.length() - 1] = Obj([
              (u("type"), Str(u("live"))),
              (u("event"), Obj([(u("kind"), Str(u("delta"))), (u("id"), a.get("id").unwrap()), (u("field"), a.get("field").unwrap()), (u("text"), Str(text(a) + text(b)))])),
            ])
            continue
          }
          (Some(x), Some(y)) if text(a).length() == 0 && text(b).length() == 0 => {
            out[out.length() - 1] = Obj([
              (u("type"), Str(u("live"))),
              (u("event"), Obj([(u("kind"), Str(u("delta"))), (u("id"), a.get("id").unwrap()), (u("field"), a.get("field").unwrap()), (u("text"), Str([])), (u("tokens"), Num(x + y))])),
            ])
            continue
          }
          _ => ()
        }
      }
    }
    out.push(e)
  }
}

///|
/// A frame asking for a new token (`oauth_token_refresh`): its request's id, as `String(frame.request_id ?? "")`.
fn renew_asked(frame : @jsjson.JValue) -> Array[Int]? {
  guard frame is Obj(_) && frame.get("type") is Some(Str(t)) && t == @jsjson.units("control_request") else { return None }
  guard frame.get("request") is Some(Obj(_) as r) && r.get("subtype") is Some(Str(s)) && s == @jsjson.units("oauth_token_refresh") else {
    return None
  }
  match frame.get("request_id") {
    None | Some(Null) => Some([])
    Some(Str(s)) => Some(s)
    Some(v) => Some(@jsjson.units(@jsjson.stringify(v)))
  }
}

///|
/// claude.ts `interruptRequest`.
fn interrupt_request(host : @host.Host) -> String {
  let answered = try { Some(host.shell_sync("crypto.random", { "bytes": 16 })) } catch { _ => None }
  let hex = match answered {
    Some(String(h)) if h.length() == 32 => h
    Some({ "value": String(h), .. }) if h.length() == 32 => h
    _ => "00000000000000000000000000000000"
  }
  let id = "\{hex.view(end_offset=8)}-\{hex.view(start_offset=8, end_offset=12)}-\{hex.view(start_offset=12, end_offset=16)}-\{hex.view(start_offset=16, end_offset=20)}-\{hex.view(start_offset=20)}"
  ({ "type": "control_request", "request_id": Json::string("interrupt-\{id}"), "request": { "subtype": "interrupt" } } : Json).stringify()
}

///|
/// The turn as claude.ts `ClaudeSnapshot.turn` says it.
fn turn_json_js(t : @claude.Turn) -> @jsjson.JValue {
  let u = @jsjson.units
  let fields : Array[(Array[Int], @jsjson.JValue)] = [
    (u("busy"), Bool(t.busy)),
    (u("aborting"), Bool(t.aborting)),
    (u("authFailure"), match t.auth_failure { Some(f) => Str(f); None => Null }),
  ]
  if t.renews is Some(r) {
    fields.push((u("renews"), Bool(r)))
  }
  if t.renewed is Some(r) {
    fields.push((u("renewed"), Bool(r)))
  }
  if t.tasks is Some(tasks) {
    fields.push((u("tasks"), Obj(tasks.map(e => {
      let k = e.1
      let task : Array[(Array[Int], @jsjson.JValue)] = [
        (u("id"), Str(k.id)),
        (u("kind"), Str(u(k.kind))),
        (u("description"), Str(k.description)),
        (u("background"), Bool(k.background)),
      ]
      if k.started_at is Some(at) {
        task.push((u("startedAt"), Num(at)))
      }
      (e.0, @jsjson.JValue::Obj(task))
    }))))
  }
  if t.compacting is Some(c) {
    fields.push((u("compacting"), Bool(c)))
  }
  match t.compact_error {
    Some(e) => fields.push((u("compactError"), Str(e)))
    None => if t.compacting is Some(_) { fields.push((u("compactError"), Null)) }
  }
  Obj(fields)
}

///|
fn turn_json(t : @claude.Turn) -> Json {
  @json.parse(@jsjson.stringify(turn_json_js(t))) catch { _ => Json::null() }
}

///|
/// The turn Node said (a snapshot's, or what it read again after a crash).
fn turn_of(v : Json?) -> @claude.Turn {
  let t = @claude.Turn::new()
  guard v is Some(Object(m)) else { return t }
  let flag = (k : String) => match m.get(k) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
  let text = (k : String) => match m.get(k) {
    Some(String(s)) => Some(@jsjson.units(s))
    _ => None
  }
  t.busy = flag("busy").unwrap_or(false)
  t.aborting = flag("aborting").unwrap_or(false)
  t.auth_failure = text("authFailure")
  t.renews = flag("renews")
  t.renewed = flag("renewed")
  t.compacting = flag("compacting")
  t.compact_error = text("compactError")
  if m.get("tasks") is Some(Object(tasks)) {
    let kept = []
    for id, task in tasks {
      guard task is Object(k) else { continue }
      kept.push((@jsjson.units(id), @claude.Task::{
        id: match k.get("id") { Some(String(s)) => @jsjson.units(s); _ => @jsjson.units(id) },
        kind: match k.get("kind") { Some(String("agent")) => "agent"; _ => "command" },
        description: match k.get("description") { Some(String(s)) => @jsjson.units(s); _ => [] },
        background: k.get("background") is Some(True),
        started_at: match k.get("startedAt") { Some(Number(n, ..)) => Some(n); _ => None },
      }))
    }
    t.tasks = Some(kept)
  }
  t
}

///|
/// A Codex app-server's turn's diff, whole each time it changes: the most of what it writes, of which the station keeps
/// nothing (codex.ts `UNTOLD`, LiveFromCodex), not given Node.
const DIFF : Bytes = b"{\"method\":\"turn/diff/updated\""

///|
/// Lines given Node as they are (`lines`, their bytes after it, each with where it begins and ends), but for those it
/// keeps nothing of: acknowledged at once where none is given and nothing given is waiting.
fn Agents::given(self : Agents, h : Hosted, lines : Array[(Bytes, Int64)]) -> Unit {
  let end = lines[lines.length() - 1].1
  let kept = lines.filter(l => !(l.0.length() >= DIFF.length() && l.0[0:DIFF.length()] == DIFF[:]))
  if kept.length() == 0 && h.told <= h.acked_out {
    h.acked_out = end
    h.told = end
    self.ack(h)
    return
  }
  h.told = end
  let body = @buffer.new()
  let at = []
  for l in kept {
    let line = if l.0.length() > 0 && l.0[l.0.length() - 1] == b'\r' { l.0[0:l.0.length() - 1].to_bytes() } else { l.0 }
    let from = l.1 - (l.0.length() + 1).to_int64()
    at.push("[\{from},\{l.1},\{line.length()}]")
    body.write_bytes(line)
  }
  let bytes = body.to_bytes()
  self.host.say("{\"lines\":\{h.n},\"to\":\{end},\"at\":[\{at.join(",")}],\"bytes\":\{bytes.length()}}")
  self.host.out(bytes)
}
