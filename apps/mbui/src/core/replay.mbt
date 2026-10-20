// A kept conversation with the core (trace.mbt) given again to the app, in place of a core: what came in is handed
// on in the order it came, each once everything the app had sent before it in the run has been sent again; the ids
// the app gives its asks now are matched to those it gave them then. So a run against a live backend is seen again
// in a Tester, frame by frame and the same every time, and a test chooses how much comes between two frames
// (`deliver`'s `at_most`: all that may, or one at a time to see each step).
//
// An ask the run never made, or one it made that the app does not make again, is where the two went apart: `diverged`
// lists the first, `waiting` says what the next message in waits for. An ask made again with other params (a time, an
// id made new each run) is matched to the next of its kind and name, and listed in `fuzzy`.

///|
priv struct Ev {
  out : Bool
  msg : Json
  bytes : Bytes?
  wall : Double
  mut done : Bool
}

///|
pub struct Replay {
  priv evs : Array[Ev]
  /// a recorded ask's id: the id the app gave the same ask now; and the other way
  priv ids : Map[Int, Int]
  priv back : Map[Int, Int]
  /// the first message out not yet sent again (or evs.length())
  priv mut first_out : Int
  /// the first message in not yet given (or evs.length())
  priv mut next_in : Int
  priv mut client : Client?
  priv diverged : Array[String]
  priv fuzzy : Array[String]
  /// the wall clock as far as the run had come by what was given: the latest of the given messages' (so the same
  /// whatever order what may come at once was given in)
  priv mut wall : Double
  /// the wall clock of each message handed to the app's queue (`deliver`'s `to`) and not received yet, oldest first
  priv walls : Array[Double]
  /// the order what may come is given in: as it came (0), or drawn from this seed (`shuffle`)
  priv mut seed : UInt
  /// the calls whose answer was given since the last take_answered, by name, in the order given
  priv answered : Array[String]
}

///|
/// The conversation in `log`: a trace's lines (`{"out":…}`, `{"in":…}`), or a log with them after CORETRACE. Other
/// lines are left out.
pub fn Replay::parse(log : String) -> Replay {
  let evs : Array[Ev] = []
  for v in log.split("\n") {
    let line = v.to_owned()
    let start = match line.find("CORETRACE ") {
      Some(i) => i + 10
      None => if line.has_prefix("{") { 0 } else { continue }
    }
    let j = @json.parse(line.view(start_offset=start).to_owned()) catch {
      _ => continue
    }
    guard j is Object(m) else { continue }
    match (m.get("out"), m.get("in")) {
      (Some(o), _) => evs.push({ out: true, msg: o, bytes: None, wall: 0.0, done: false })
      (_, Some(i)) => {
        let wall = match m.get("w") {
          Some(Number(d, ..)) => d
          _ => 0.0
        }
        let bytes = match (m.get("b"), m.get("bn")) {
          (Some(String(h)), _) => Some(unhex(h))
          // (bytes the trace left out, their length kept: as many zeros)
          (_, Some(Number(n, ..))) => Some(Bytes::new(n.to_int()))
          _ => None
        }
        evs.push({ out: false, msg: i, bytes, wall, done: false })
      }
      _ => ()
    }
  }
  let r = {
    evs,
    ids: {},
    back: {},
    first_out: 0,
    next_in: 0,
    client: None,
    diverged: [],
    fuzzy: [],
    wall: 0.0,
    walls: [],
    seed: 0,
    answered: [],
  }
  r.advance()
  r
}

///|
/// The run's calls named `call` not waited for: what the run did that a test does not do again (`migrate`: the
/// account a scripted run was given by its environment). Their answers are left out too.
pub fn Replay::skip(self : Replay, call : String) -> Unit {
  let gone : Array[Int] = []
  for e in self.evs {
    if e.out && !e.done && e.msg is Object(m) && kind_of(m) == "call" && name_of(m) == call {
      e.done = true
      match id_of(m) {
        Some(id) => gone.push(id)
        None => ()
      }
    }
  }
  for e in self.evs {
    if !e.out && !e.done && e.msg is Object(m) && id_of(m) is Some(id) && gone.contains(id) {
      e.done = true
    }
  }
  self.advance()
}

///|
/// The run's asks whose message holds `text`, and what came for them, left out: an ask the run's timing made (a list
/// off its end for a frame: `client.focus` with `"end":false`) that a test's frames need not make again. How many.
pub fn Replay::drop(self : Replay, text : String) -> Int {
  let gone : Array[Int] = []
  for e in self.evs {
    if e.out && !e.done && e.msg.stringify().contains(text) {
      e.done = true
      match e.msg {
        Object(m) =>
          match id_of(m) {
            Some(id) => gone.push(id)
            None => ()
          }
        _ => ()
      }
    }
  }
  for e in self.evs {
    if !e.out && !e.done && e.msg is Object(m) && id_of(m) is Some(id) && gone.contains(id) {
      e.done = true
    }
  }
  self.advance()
  gone.length()
}

///|
/// A client of its own over this conversation (a test of the client alone).
pub fn Replay::client(self : Replay) -> Client {
  let c = Client::new(fn(s) { self.out(s) }, send_bytes=fn(s, _) { self.out(s) })
  self.client = Some(c)
  c
}

///|
/// The app's core (`client`, `wall_ms`) is this conversation from now on, until `detach`: its client started anew.
pub fn Replay::attach(self : Replay) -> Unit {
  client.reset()
  transport.val = fn(s, _) { self.out(s) }
  wall_override.val = Some(fn() { self.wall })
  // what `deliver` handed to the app's queue is received at a frame's start (`receive`): the wall clock is its own then
  receive_hook.val = Some(fn() {
    if self.walls.length() > 0 {
      let w = self.walls.remove(0)
      if w > self.wall {
        self.wall = w
      }
    }
  })
  self.client = Some(client)
}

///|
/// The app's core is the engine again.
pub fn Replay::detach() -> Unit {
  transport.val = engine_send
  wall_override.val = None
  receive_hook.val = None
}

///|
/// What came in, handed on in its order, as long as what it came after has been sent again: at most `at_most` of
/// them (all that may, by default). How many were. With a seed (`shuffle`), what may come at once comes in an order
/// drawn from it, each ask's own messages still in theirs. `to`: each handed there (its JSON, its bytes) instead of to
/// the client at once: an app's, the app's queue (a Tester's `post` on "core"), whose next frame gives it to `receive`.
pub fn Replay::deliver(
  self : Replay,
  at_most? : Int = -1,
  to? : (String, Bytes?) -> Unit,
) -> Int {
  let mut n = 0
  while at_most < 0 || n < at_most {
    let i = self.pick()
    if i < 0 {
      break
    }
    let e = self.evs[i]
    e.done = true
    match self.live(e.msg) {
      Some(msg) => {
        match to {
          Some(post) => {
            self.walls.push(e.wall)
            post(msg.stringify(), e.bytes)
          }
          None => {
            if e.wall > self.wall {
              self.wall = e.wall
            }
            match self.client {
              Some(c) => c.receive_json(msg, bytes=e.bytes)
              None => ()
            }
          }
        }
        match self.call_answered(e.msg) {
          Some(name) => self.answered.push(name)
          None => ()
        }
        n += 1
      }
      None => self.diverged.push("came for an ask not made again: " + e.msg.stringify())
    }
    self.advance()
  }
  n
}

///|
/// The call a message in answers (its `ok` or `error`, not a stream's part or a subscription's value): its name.
fn Replay::call_answered(self : Replay, msg : Json) -> String? {
  guard msg is Object(m) && (m.contains("ok") || m.contains("error")) && id_of(m) is Some(id) else { return None }
  for e in self.evs {
    if e.out && e.msg is Object(o) && id_of(o) == Some(id) && kind_of(o) == "call" {
      return Some(name_of(o))
    }
  }
  None
}

///|
/// The calls answered since the last time asked, by name, in the order their answers were given (a scripted run's
/// `answered NAME` for each: what the step waited for there, src/sfreplay/emit.mbt).
pub fn Replay::take_answered(self : Replay) -> Array[String] {
  let a = self.answered.copy()
  self.answered.clear()
  a
}

///|
/// Whether a message in may come now (what it came after has all been sent again).
pub fn Replay::due(self : Replay) -> Bool {
  self.next_in < self.evs.length() && self.first_out >= self.next_in
}

///|
/// From now on, what may come at once (the messages in after the last ask made again, before the next one not
/// made yet) comes in an order drawn from `seed` (another seed, another order; the same, the same): answers to
/// different asks in any order, an ask's own (a subscription's values, a stream's parts) in the order they came. A
/// message with no ask (a fatal) is not passed. 0: as they came.
pub fn Replay::shuffle(self : Replay, seed : UInt) -> Unit {
  self.seed = seed
}

///|
/// The message in to give next (-1: none may come).
fn Replay::pick(self : Replay) -> Int {
  if !self.due() {
    return -1
  }
  if self.seed == 0 {
    return self.next_in
  }
  // what may come: up to the next ask not made again, or a message with no ask; of each ask its first not given
  let firsts : Array[Int] = []
  let seen : Array[Int] = []
  for i in self.next_in..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done {
      break
    }
    if e.out || e.done {
      continue
    }
    guard e.msg is Object(m) && id_of(m) is Some(id) else { break }
    if !seen.contains(id) {
      seen.push(id)
      firsts.push(i)
    }
  }
  if firsts.length() == 0 {
    return self.next_in
  }
  // xorshift32
  let mut x = self.seed
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.seed = x
  firsts[(x % firsts.length().reinterpret_as_uint()).reinterpret_as_int()]
}

///|
/// How many messages in are not handed on yet.
pub fn Replay::left(self : Replay) -> Int {
  let mut n = 0
  for e in self.evs {
    if !e.out && !e.done {
      n += 1
    }
  }
  n
}

///|
/// What the next message in waits for: the ask of the run's the app has not made again (None: nothing, or all given).
pub fn Replay::waiting(self : Replay) -> String? {
  if self.next_in < self.evs.length() && self.first_out < self.next_in {
    Some(self.evs[self.first_out].msg.stringify())
  } else {
    None
  }
}

///|
/// Where the app went apart from the run: what it sent that the run never did, what came for an ask it did not make
/// again.
pub fn Replay::diverged(self : Replay) -> Array[String] {
  self.diverged
}

///|
/// The run's asks the app has not made again (yet), in their order, the skipped ones aside: at a test's end, what the
/// run did that this one did not.
pub fn Replay::unmade(self : Replay) -> Array[String] {
  let out : Array[String] = []
  for e in self.evs {
    if e.out && !e.done {
      out.push(e.msg.stringify())
    }
  }
  out
}

///|
/// Asks made again with other params, matched to the run's next of their kind and name.
pub fn Replay::fuzzy(self : Replay) -> Array[String] {
  self.fuzzy
}

///|
/// One message the app sends, matched to the run's.
fn Replay::out(self : Replay, text : String) -> Unit {
  let msg = @json.parse(text) catch {
    _ => {
      self.diverged.push(text)
      return
    }
  }
  guard msg is Object(m) else {
    self.diverged.push(text)
    return
  }
  let kind = kind_of(m)
  // an unsubscription or a cancel names an ask by its id: the run's id for it
  let refers = match id_of(m) {
    Some(l) if kind == "unsubscribe" || kind == "cancel" => self.back.get(l)
    _ => None
  }
  let want = sig(m, refers)
  let mut found = -1
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done && e.msg is Object(r) && sig(r, ref_of(r)) == want {
      found = i
      break
    }
  }
  if found < 0 && (kind == "subscribe" || kind == "call") {
    let name = name_of(m)
    for i in self.first_out..<self.evs.length() {
      let e = self.evs[i]
      if e.out && !e.done && e.msg is Object(r) && kind_of(r) == kind && name_of(r) == name {
        found = i
        self.fuzzy.push(text)
        break
      }
    }
  }
  if found < 0 {
    self.diverged.push(text)
    return
  }
  let e = self.evs[found]
  e.done = true
  if e.msg is Object(r) && (kind == "subscribe" || kind == "call") {
    match (id_of(r), id_of(m)) {
      (Some(then), Some(now)) => {
        self.ids[then] = now
        self.back[now] = then
      }
      _ => ()
    }
  }
  self.advance()
}

///|
fn Replay::advance(self : Replay) -> Unit {
  let n = self.evs.length()
  while self.first_out < n &&
        (!self.evs[self.first_out].out || self.evs[self.first_out].done) {
    self.first_out += 1
  }
  while self.next_in < n &&
        (self.evs[self.next_in].out || self.evs[self.next_in].done) {
    self.next_in += 1
  }
}

///|
/// A message in with the id the app gives its ask now (None: an ask it did not make again). One with no id (a fatal)
/// as it is.
fn Replay::live(self : Replay, msg : Json) -> Json? {
  guard msg is Object(m) else { return Some(msg) }
  match id_of(m) {
    None => Some(msg)
    Some(then) =>
      match self.ids.get(then) {
        Some(now) => {
          let copy : Map[String, Json] = {}
          for k, v in m {
            copy[k] = if k == "id" { Json::number(now.to_double()) } else { v }
          }
          Some(Json::object(copy))
        }
        None => None
      }
  }
}

///|
fn id_of(m : Map[String, Json]) -> Int? {
  match m.get("id") {
    Some(Number(d, ..)) => Some(d.to_int())
    _ => None
  }
}

///|
/// The id an unsubscription or a cancel names, as recorded.
fn ref_of(m : Map[String, Json]) -> Int? {
  let kind = kind_of(m)
  if kind == "unsubscribe" || kind == "cancel" {
    id_of(m)
  } else {
    None
  }
}

///|
fn kind_of(m : Map[String, Json]) -> String {
  if m.contains("subscribe") {
    "subscribe"
  } else if m.contains("call") {
    "call"
  } else if m.contains("unsubscribe") {
    "unsubscribe"
  } else if m.contains("cancel") {
    "cancel"
  } else {
    "?"
  }
}

///|
/// A call's name, a subscription's topic.
fn name_of(m : Map[String, Json]) -> String {
  match (m.get("call"), m.get("subscribe")) {
    (Some(String(s)), _) => s
    (_, Some(Object(t))) =>
      match t.get("topic") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// What an ask is, whatever its id: its message without the id, keys in order; an unsubscription or a cancel with the
/// run's id of what it names (`refers`).
fn sig(m : Map[String, Json], refers : Int?) -> String {
  let copy : Map[String, Json] = {}
  for k, v in m {
    if k != "id" {
      copy[k] = v
    }
  }
  match refers {
    Some(r) => copy["id"] = Json::number(r.to_double())
    None => ()
  }
  canon(Json::object(copy))
}

///|
/// JSON's text with every object's keys in order: the same for the same value however it was made.
fn canon(j : Json) -> String {
  match j {
    Object(m) => {
      let keys = m.keys().to_array()
      keys.sort()
      let parts = keys.map(fn(k) {
        Json::string(k).stringify() + ":" + canon(m.get(k).unwrap())
      })
      "{" + parts.join(",") + "}"
    }
    Array(a) => "[" + a.map(canon).join(",") + "]"
    _ => j.stringify()
  }
}
