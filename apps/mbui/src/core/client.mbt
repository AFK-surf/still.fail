// One UI client of the still.fail core, over whatever carries the protocol's JSON (ember docs/client-core.md,
// Protocol): `{id, call, params}` and `{id, subscribe, keyed}` out; `{id, ok|error}`, `{id, value}`, `{id, delta}`
// and `{fatal}` in. Each subscription keeps its topic's current value, deltas applied (delta.mbt), and a version that
// changes with every message for it, so a view can tell what changed since its last frame without comparing values;
// and a signal of its changes (mbui/signals) set as each comes, and as it ends: what reads the topic in a computed
// follows it from here, the core's change pushed on to it, not looked for as it is read.
// The client is the UI thread's: messages come to `receive` in order on it (native.mbt drains the engine's queue).

///|
/// A subscription to a topic: `value` is its whole current value (None until the first, and after an error until the
/// next value), `error` the core's error for it while it could not be read, `version` changes with each message.
/// `changes` is set with each message too, and once more as it ends (unsubscribed, the client reset): what read it
/// reads the topic again then, from the subscription asked anew.
pub struct Sub {
  id : Int
  topic : Json
  mut value : Json?
  mut error : Json?
  mut version : Int
  /// told by the core, while it has no value, that its value waits on a station: none of what it shows is on the device
  /// (core-ts store.ts `waits`), not the core still reading it
  mut waiting : Bool
  priv key : String
  changes : @signals.Signal[Int]
}

///|
/// The subscription read: what reads it in a computed follows its changes (Sub.changes).
pub fn Sub::followed(self : Sub) -> Sub {
  self.changes.get() |> ignore
  self
}

///|
/// What reads it told it changed: a message for it, or its end (`ended`: -1, no version of its own).
fn Sub::changed(self : Sub, ended? : Bool = false) -> Unit {
  self.changes.set(if ended { -1 } else { self.version })
}

///|
pub struct Client {
  priv send : (String) -> Unit
  /// a message with bytes beside it (a file's part going up)
  priv send_bytes : (String, Bytes) -> Unit
  priv subs : Map[Int, Sub]
  priv by_key : Map[String, Sub]
  priv calls : Map[Int, (Result[Json, Json]) -> Unit]
  /// what calls that say how they go are told before their answer (`{id, value}`), by the call's id
  priv progress : Map[Int, (Json, Bytes?) -> Unit]
  /// what of a call's values changes nothing a frame reads (Client::quiet), by the call's name; and by the id of each
  /// such call under way
  priv quiet_names : Map[String, (Json) -> Bool]
  priv quiet_calls : Map[Int, (Json) -> Bool]
  /// the calls whose answers nobody reads (Client::unread), by name; and the ids of those under way
  priv unread_names : Map[String, Bool]
  priv unread_calls : Map[Int, Bool]
  priv mut next_id : Int
  /// the bytes beside the message being taken, if any
  priv mut beside : Bytes?
  /// Changes with every message that changed something (a sub's value or error, a call's answer).
  mut version : Int
  /// The core's reason, once it has failed (`{fatal}`); cleared by `restarted`.
  mut fatal : String?
  /// Set as `fatal` is: what reads it follows it (fatal)
  fatal_said : @signals.Signal[Int]
  /// Who keeps what is awaited of the core (Client::track: mbui's effect.mb outside): a ticket for each call until
  /// its answer, each subscription until its first value (or error)
  priv mut start_wait : (String) -> Int
  priv mut end_wait : (Int) -> Unit
  /// the tickets: by call id, by subscription id
  priv call_waits : Map[Int, Int]
  priv sub_waits : Map[Int, Int]
  /// calls whose effect the core shows on a draft topic (`echo_topic`), by call id: the draft's subscription, whether
  /// the call is answered, whether the draft has changed since it was made; its ticket held until both
  priv echo_waits : Map[Int, (Int, Bool, Bool)]
  /// Told of each subscription made (its id, its topic's name, None) and of its first message (its value, or None
  /// when it could not be read): Client::time_topics
  priv mut timing : ((Int, String, Json?, Bool) -> Unit)?
  /// where the app's attention is, as told last (`client.focus`): told again to a core started anew
  /// (StillFailCore.kt `focus`), which would else take the app for out of view
  priv mut focus : Json?
  /// While the device's performance record is kept (@hostapi.perf_recording): each call's name by its id until it is
  /// answered, so what the core says of it is put to its name (Client::perf_name)
  priv perf_calls : Map[Int, String]
}

///|
/// A client whose messages go out through `send` (one JSON message each).
/// `send_bytes` sends one with bytes beside it (by default the bytes are dropped: a client that never sends any).
pub fn Client::new(
  send : (String) -> Unit,
  send_bytes? : (String, Bytes) -> Unit = fn(s, _) { send(s) },
) -> Client {
  {
    send,
    send_bytes,
    subs: {},
    by_key: {},
    calls: {},
    progress: {},
    quiet_names: {},
    quiet_calls: {},
    unread_names: {},
    unread_calls: {},
    next_id: 1,
    beside: None,
    version: 0,
    fatal: None,
    fatal_said: @signals.signal(0),
    start_wait: fn(_) { 0 },
    end_wait: fn(_) {  },
    focus: None,
    call_waits: {},
    sub_waits: {},
    echo_waits: {},
    timing: None,
    perf_calls: {},
  }
}

///|
/// What the app times of its topics (still.fail's Android app's bar_switch, BarTiming.kt `topics`): `f(id, topic,
/// None, false)` as a subscription is made and asked of the core, `f(id, topic, value, true)` as its first message is
/// taken (its value; None: an error). Nothing here reads a clock: the times are the caller's.
pub fn Client::time_topics(self : Client, f : ((Int, String, Json?, Bool) -> Unit)?) -> Unit {
  self.timing = f
}

///|
/// What is asked of the core is awaited until it is answered (a call) or first read (a subscription): `start` is told
/// what it is and gives a ticket, `end` is given the ticket back (mbui's `@ui.runtime().outside_start` and
/// `outside_end`, so a screen is not settled while it waits on the core).
pub fn Client::track(self : Client, start : (String) -> Int, end : (Int) -> Unit) -> Unit {
  self.start_wait = start
  self.end_wait = end
}

///|
fn Client::end_call_wait(self : Client, id : Int) -> Unit {
  match self.call_waits.get(id) {
    Some(t) => {
      self.call_waits.remove(id)
      (self.end_wait)(t)
    }
    None => ()
  }
}

///|
fn Client::end_sub_wait(self : Client, id : Int) -> Unit {
  match self.sub_waits.get(id) {
    Some(t) => {
      self.sub_waits.remove(id)
      (self.end_wait)(t)
    }
    None => ()
  }
}

///|
fn topic_json(topic : String, params : Map[String, Json]) -> Json {
  let m : Map[String, Json] = { "topic": Json::string(topic) }
  for k, v in params {
    m[k] = v
  }
  Json::object(m)
}

///|
/// A topic's name (its `topic`), without its params.
fn topic_name(t : Json) -> String {
  match t {
    Object(m) =>
      match m.get("topic") {
        Some(String(n)) => n
        _ => ""
      }
    _ => ""
  }
}

///|
/// An edit of a draft the core keeps (a form's), by call, and the topic that draft is read from: the call is answered
/// at once, the draft as the station has it comes after. What is asked is awaited until the draft has come too (a
/// scripted run's `answered NAME`, a screen settled), so what depends on the draft (a button it lets be pressed) is
/// there when the step after looks.
fn echo_topic(name : String) -> String? {
  match name {
    "agentEnv.form.edit" => Some("agentEnvForm")
    "profile.flow.edit" => Some("profileFlow")
    _ => None
  }
}

///|
/// The subscription to the draft an edit `name` with `params` changes (`echo_topic`: its topic, the same station and
/// form), if the client has one.
fn Client::echo_of(self : Client, name : String, params : Json) -> Sub? {
  guard echo_topic(name) is Some(topic) else { return None }
  guard params is Object(p) else { return None }
  for _, s in self.subs {
    guard s.topic is Object(t) else { continue }
    if topic_name(s.topic) == topic && t.get("station") == p.get("station") && t.get("form") == p.get("form") {
      return Some(s)
    }
  }
  None
}

///|
/// The subscription to `topic` with `params`: made (and asked of the core) the first time, the same one after that,
/// so a view can call this every frame.
pub fn Client::subscribe(
  self : Client,
  topic : String,
  params? : Map[String, Json] = {},
) -> Sub {
  let t = topic_json(topic, params)
  let key = t.stringify()
  match self.by_key.get(key) {
    Some(s) => s
    None => {
      let id = self.next_id
      self.next_id += 1
      let s = { id, topic: t, value: None, error: None, version: 0, waiting: false, key, changes: @signals.signal(0) }
      self.subs[id] = s
      self.by_key[key] = s
      self.ask(s)
      match self.timing {
        Some(f) => f(id, topic, None, false)
        None => ()
      }
      s
    }
  }
}

///|
fn Client::ask(self : Client, s : Sub) -> Unit {
  self.end_sub_wait(s.id)
  self.sub_waits[s.id] = (self.start_wait)("core: \{s.key}")
  perf_out("sub " + topic_name(s.topic))
  // keyed: lists the core keys (threads, chats…) change item by item rather than as whole lists (delta.mbt applies both)
  let m : Map[String, Json] = {
    "id": Json::number(s.id.to_double()),
    "subscribe": s.topic,
    "keyed": Json::boolean(true),
  }
  (self.send)(Json::object(m).stringify())
}

///|
/// Ends a subscription: the core stops sending it, and `subscribe` makes a new one.
pub fn Client::unsubscribe(self : Client, s : Sub) -> Unit {
  if self.subs.contains(s.id) {
    self.end_sub_wait(s.id)
    self.subs.remove(s.id)
    self.by_key.remove(s.key)
    s.changed(ended=true)
    let m : Map[String, Json] = {
      "id": Json::number(s.id.to_double()),
      "unsubscribe": Json::boolean(true),
    }
    (self.send)(Json::object(m).stringify())
  }
}

///|
/// Calls `name` with `params`; `on_done` gets its answer (`ok`) or the core's error (`{code, message, status?}`).
/// Returns the call's id. A value the call sends before its answer (how far it has got) is passed on only to a
/// `stream`'s `on_value`.
/// `bytes` go beside the call (a file's part: `station.upload.part`).
pub fn Client::call(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Int {
  if name == "client.focus" {
    self.focus = Some(params)
  }
  let id = self.next_id
  self.next_id += 1
  self.calls[id] = on_done
  if @hostapi.perf_recording() {
    self.perf_calls[id] = name
    perf_out(name)
  }
  // (one whose answer nobody reads is awaited by nothing: its answer, taken as it comes, asks for no frame)
  if self.unread_names.contains(name) {
    self.unread_calls[id] = true
  } else {
    self.call_waits[id] = (self.start_wait)("core: \{name} (call \{id})")
  }
  match self.echo_of(name, params) {
    Some(e) => self.echo_waits[id] = (e.id, false, false)
    None => ()
  }
  let m : Map[String, Json] = {
    "id": Json::number(id.to_double()),
    "call": Json::string(name),
    "params": params,
  }
  match bytes {
    Some(b) => (self.send_bytes)(Json::object(m).stringify(), b)
    None => (self.send)(Json::object(m).stringify())
  }
  id
}

///|
/// Calls `name` like `call`, for a call whose answer comes with bytes beside
/// it (a picture, a file's contents): `on_done` gets them with the answer.
pub fn Client::call_bytes(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Int {
  self.call(name, params~, on_done=fn(r) {
    match r {
      Ok(j) => on_done(Ok((j, self.beside)))
      Err(e) => on_done(Err(e))
    }
  })
}

///|
/// Calls `name` like `call`, for a call that says how it goes before its answer (`station.preview` with `stream`: an
/// answer's head, then each piece of its body with the bytes beside it): `on_value` gets each such value and the bytes
/// beside it, then `on_done` the answer. Returns the call's id (`cancel` stops it).
pub fn Client::stream(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_value~ : (Json, Bytes?) -> Unit,
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Int {
  let id = self.next_id
  self.progress[id] = on_value
  match self.quiet_names.get(name) {
    Some(f) => self.quiet_calls[id] = f
    None => ()
  }
  self.call(name, params~, bytes~, on_done=fn(r) {
    self.progress.remove(id)
    self.quiet_calls.remove(id)
    on_done(r)
  })
}

///|
/// Calls `name` like `stream`, for a call whose answer comes with bytes beside it (`station.file` with `progress`: how
/// much of the file has come, then the file): `on_done` gets them with the answer.
pub fn Client::stream_bytes(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  on_value~ : (Json, Bytes?) -> Unit,
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Int {
  self.stream(name, params~, on_value~, on_done=fn(r) {
    match r {
      Ok(j) => on_done(Ok((j, self.beside)))
      Err(e) => on_done(Err(e))
    }
  })
}

///|
/// A call that says how it goes (`stream`) stopped in the core: nothing more of it comes, its answer included.
pub fn Client::cancel(self : Client, id : Int) -> Unit {
  if self.progress.contains(id) {
    self.progress.remove(id)
    self.quiet_calls.remove(id)
    self.calls.remove(id)
    self.perf_calls.remove(id)
    self.end_call_wait(id)
    let m : Map[String, Json] = { "id": Json::number(id.to_double()), "cancel": Json::boolean(true) }
    (self.send)(Json::object(m).stringify())
  }
}

///|
/// Whether message `m` is a topic's change alone, its value or what changed of it (its first too: the runtime's wait
/// for it ended as it is taken, Runtime::outside_end being only that; no edit's draft come with it): what it changes is
/// said by its topic's signal and nothing else (Sub::changed), so it may be taken as it comes, before the frame decides
/// what it does (@ui.on_message_said). (A chat opened was built twice for its first values, taken by the frame: the
/// frame it was opened in again, or the next whole, 2026-10-30.)
pub fn Client::topic_said(self : Client, m : Map[String, Json]) -> Bool {
  if m.contains("fatal") {
    return false
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return false
  }
  match self.subs.get(id) {
    Some(s) =>
      !self.echo_waits.values().any(fn(w) { w.0 == id }) &&
      (m.contains("value") || m.contains("delta") || m.contains("error") || m.contains("waiting"))
    None => false
  }
}

///|
/// The values of a call `name` (a `stream`'s) for which `f` says true change nothing a frame reads: what takes them
/// hands them on (a decoder's frame, a sound's packet) and keeps what it counts where no build reads it as it comes. So
/// they may be taken as they come, before the frame decides what it does (Client::call_said): a stream of them builds
/// nothing (a remote screen's frames and sound, sfpages' screen_value_quiet). Said once, as the app starts.
pub fn Client::quiet(self : Client, name : String, f : (Json) -> Bool) -> Unit {
  self.quiet_names[name] = f
}

///|
/// Nobody reads the answer of a call `name` (a call told and let go: `screen.ack`): nothing awaits it (no wait of the
/// runtime's) and it changes nothing a frame reads, so it may be taken as it comes (Client::call_said). Said once, as
/// the app starts.
pub fn Client::unread(self : Client, name : String) -> Unit {
  self.unread_names[name] = true
}

///|
/// Whether message `m` is a call's alone and changes nothing a frame reads: a value of a call that says it changes
/// nothing (Client::quiet), or the answer of one whose answer nobody reads (Client::unread, its wait ended with it),
/// so it may be taken as it comes, before the frame decides what it does (@ui.on_message_said).
pub fn Client::call_said(self : Client, m : Map[String, Json]) -> Bool {
  if m.contains("fatal") {
    return false
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return false
  }
  if self.subs.contains(id) {
    return false
  }
  if m.contains("ok") || m.contains("error") {
    return self.unread_calls.contains(id) && !self.echo_waits.contains(id)
  }
  match (m.get("value"), self.quiet_calls.get(id)) {
    (Some(v), Some(f)) => self.progress.contains(id) && f(v)
    _ => false
  }
}

///|
/// One message from the core, as its JSON text. False when it is not JSON.
pub fn Client::receive(self : Client, text : String) -> Bool {
  let msg = @json.parse(text) catch { _ => return false }
  self.receive_json(msg)
  true
}

///|
/// One message from the core, and the bytes beside it if it has any.
pub fn Client::receive_json(
  self : Client,
  msg : Json,
  bytes? : Bytes? = None,
) -> Unit {
  self.beside = bytes
  self.take(msg)
  self.beside = None
}

///|
fn Client::take(self : Client, msg : Json) -> Unit {
  guard msg is Object(m) else { return }
  match m.get("fatal") {
    Some(reason) => {
      self.fatal = Some(
        match reason {
          String(s) => s
          r => r.stringify()
        },
      )
      self.fatal_said.set(@signals.untracked(fn() { self.fatal_said.get() }) + 1)
      // What was asked of this core is not answered by the next one.
      let calls = self.calls.to_array()
      self.calls.clear()
      self.unread_calls.clear()
      self.echo_waits.clear()
      for c in calls {
        self.end_call_wait(c.0)
      }
      // the subscriptions wait for the next core (restarted asks them again)
      let subs = self.sub_waits.keys().collect()
      for id in subs {
        self.end_sub_wait(id)
      }
      // (as StillFailCore.kt fails them: `core_restarted`, in the app's words; the reason is the core's own, on_failed)
      let err = Json::object({
        "code": Json::string("core_restarted"),
        "message": Json::string(restarted_text.val),
      })
      for c in calls {
        (c.1)(Err(err))
      }
      self.version += 1
      return
    }
    None => ()
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return
  }
  match self.subs.get(id) {
    Some(s) => {
      if m.get("waiting") is Some(True) && s.value is None && s.error is None {
        // (no value of it yet: what shows it shows what is to come, the core's wait for it going on)
        s.waiting = true
        self.version += 1
        s.changes.set(-2)
        return
      }
      match (m.get("value"), m.get("delta"), m.get("error")) {
        (_, _, Some(e)) => {
          // The topic could not be read: the next message is a whole value, not a delta.
          s.value = None
          s.error = Some(e)
        }
        (Some(v), _, _) => {
          s.value = Some(v)
          s.error = None
        }
        (_, Some(Array(ops)), _) =>
          match s.value {
            Some(v) => s.value = Some(apply_delta(v, ops))
            None => return
          }
        _ => return
      }
      s.waiting = false
      match self.timing {
        Some(f) if s.version == 0 => f(id, topic_name(s.topic), s.value, true)
        _ => ()
      }
      s.version += 1
      self.version += 1
      s.changed()
      self.end_sub_wait(id)
      self.draft_came(id)
    }
    None =>
      // A call's answer; a value before it says how it goes (to a `stream`'s `on_value`)
      match (m.get("ok"), m.get("error"), m.get("value")) {
        (Some(ok), _, _) => self.answer(id, Ok(ok))
        (None, Some(e), _) => self.answer(id, Err(e))
        (None, None, Some(v)) =>
          match self.progress.get(id) {
            Some(f) => {
              self.version += 1
              f(v, self.beside)
            }
            None => ()
          }
        _ => ()
      }
  }
}

///|
/// What a message of the core's is, for the performance record: `topic <name> value|delta|error|waiting` (a subscription's),
/// `answer <call>` (a call's answer), `progress <call>` (a value before it), `?` else.
pub fn Client::perf_name(self : Client, msg : Json) -> String {
  guard msg is Object(m) else { return "?" }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return if m.contains("fatal") { "fatal" } else { "?" }
  }
  match self.subs.get(id) {
    Some(s) => {
      let how = if m.contains("error") {
        "error"
      } else if m.contains("value") {
        "value"
      } else if m.contains("waiting") {
        "waiting"
      } else {
        "delta"
      }
      "topic \{topic_name(s.topic)} \{how}"
    }
    None => {
      let name = self.perf_calls.get(id).unwrap_or("?")
      if m.contains("ok") || m.contains("error") {
        self.perf_calls.remove(id)
        "answer " + name
      } else {
        "progress " + name
      }
    }
  }
}

///|
/// No call's name kept any more (the record turned off).
pub fn Client::perf_forget(self : Client) -> Unit {
  self.perf_calls.clear()
}

///|
fn Client::answer(self : Client, id : Int, r : Result[Json, Json]) -> Unit {
  self.unread_calls.remove(id)
  match self.echo_waits.get(id) {
    // (an edit answered before its draft came: awaited still, until it does; refused: nothing to come)
    Some((sub, _, false)) if r is Ok(_) => self.echo_waits[id] = (sub, true, false)
    Some(_) => {
      self.echo_waits.remove(id)
      self.end_call_wait(id)
    }
    None => self.end_call_wait(id)
  }
  match self.calls.get(id) {
    Some(f) => {
      self.calls.remove(id)
      self.version += 1
      f(r)
    }
    None => ()
  }
}

///|
/// After the core was started again (a fatal): every subscription asked of the new core, under its own id. Their
/// values stay until the new core's first value replaces them.
pub fn Client::restarted(self : Client) -> Unit {
  self.fatal = None
  self.fatal_said.set(@signals.untracked(fn() { self.fatal_said.get() }) + 1)
  let subs = self.subs.values().to_array()
  subs.sort_by_key(fn(s) { s.id })
  for s in subs {
    self.ask(s)
  }
  match self.focus {
    Some(p) => self.call("client.focus", params=p) |> ignore
    None => ()
  }
}

///|
/// Everything forgotten, as a new client: no subscription, no call waiting, ids from 1 (a Replay attached to the
/// app's client starts it so).
pub fn Client::reset(self : Client) -> Unit {
  // (what read them reads anew: their ends told)
  let ended = self.subs.values().to_array()
  self.subs.clear()
  for s in ended {
    s.changed(ended=true)
  }
  self.by_key.clear()
  self.calls.clear()
  self.progress.clear()
  self.quiet_calls.clear()
  self.unread_calls.clear()
  self.echo_waits.clear()
  self.focus = None
  self.next_id = 1
  self.beside = None
  self.version = 0
  self.fatal = None
}

///|
/// A message for the subscription `sub`: the edits of its draft answered by now are over (their tickets given back),
/// those not answered yet have seen it come.
fn Client::draft_came(self : Client, sub : Int) -> Unit {
  let over = []
  let seen = []
  for id, w in self.echo_waits {
    let (s, answered, _) = w
    if s == sub {
      if answered {
        over.push(id)
      } else {
        seen.push(id)
      }
    }
  }
  for id in seen {
    self.echo_waits[id] = (sub, false, true)
  }
  for id in over {
    self.echo_waits.remove(id)
    self.end_call_wait(id)
  }
}

///|
/// What a call in flight as the core failed says (StillFailCore.restartedText: the app's 核心已重启，请重试), set by the
/// app as it starts.
// kept across runs: the app's words, set once as it starts
pub let restarted_text : Ref[String] = { val: "The core restarted; try again" }
