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
  /// the wall clock in the run as it was sent or came (`has_wall`: the trace says it; old traces say it of those in only)
  wall : Double
  has_wall : Bool
  mut done : Bool
  /// the clock (Replay::clock) when it happened again: the ask made again, the message given (-1: not yet; one left
  /// out, skipped or dropped, never)
  mut at : Double
  /// when what it was handed to took it here (a message in: the frame that takes what is posted, Replay::deliver's
  /// `taken_at`): `at` is when it was due
  mut given : Double
  /// what the run's host said of its views (`{"view":…}`, `{"still":…}`, `{"info":…}`, a player's `{"read":…}`:
  /// mbui's trace_views), the line whole: given in its place like a message in, to the Tester's host (Replay::host)
  host : Bool
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
  /// when what came is given (`pace`): at once, or at the run's own pace
  priv mut pace : Pace
  /// whether every ask of the run's before a message waits it (else only its own and those that are not reports)
  priv mut strict : Bool
  /// the clock the replay's events are timed on (a Tester's: when an ask is made again, a message given)
  priv mut clock : () -> Double
  /// the calls made since the last take_asked that the run answered (or that it did not make: a live backend answers
  /// them), by name, in the order made
  priv asked : Array[String]
  /// the calls set aside (Replay::skip)
  priv skipped : Array[String]
  /// reports the app made that the run did not (Replay::sent: its frames had them, the run's not)
  priv unasked_reports : Array[String]
  /// the ids the app gave its watches of `ambient` topics the run did not have (let go of as well, unasked)
  priv ambient_ids : Map[Int, Bool]
  /// what the run's app was started with (its trace's `{"env":…}`: src/stillfail's CORETRACE env)
  priv run_env : Array[(String, String)]
  /// what the run's host answered that its text recording kept (`{"textrec":…}`: TEXTREC lines, mbui's hostrec.mbt):
  /// a word's bounds, a picture's sizes; one a line
  priv run_text : Array[String]
  /// this machine's station as the run's host said it (its trace's `{"host":{"localStation":…}}`: src/stillfail's CORETRACE host)
  priv run_local : String
  /// where what the run's host said of its views goes (Replay::host)
  priv mut host_said : ((String) -> Unit)?
}

///|
/// When a run's messages are given again (Replay::pace): `AtOnce`, as soon as what they came after has been asked
/// again; `AsRun(scale)`, also not before the clock has gone on from its anchor by the gap the run had between them
/// (in its wall clock), times `scale` (1: as the run had it; 2: twice as slow; 0.5: twice as fast). A message's anchor
/// is the latest event before it in the run that has happened again: an ask made again, a message given (Replay::
/// due_at); a trace whose asks have no wall clock (an older one) anchors to the messages in only.
pub(all) enum Pace {
  AtOnce
  AsRun(Double)
} derive(Eq, Show)

///|
/// Asks that only tell the core what the app sees or keeps (where its chat's list is, a draft and what is typed in it, where it was read to,
/// where a player was left): how many and when depends on the run's timing, and what they say with it (a player's
/// place is how far it played: the frames had them, the run's or the app's). Strict or not (Replay::pace), they wait
/// nothing, none is required and one the run did not make is not where the two went apart; one made again with other
/// params is the run's next of its name, not said to differ.
let reports : Array[String] = [
  "client.focus", "chat.place", "draft.put", "drive.place", "composer.text", "composer.comment",
  // the core's pure calls a replay's app answers from what is kept (src/sfkept) when it has the answer, and asks the
  // tape for when not: a tape's that the app answered itself is not where the two went apart, nor one it asks of a tape
  // from before the call (sfreplay's source.mbt tells the tape of each it answered, as a report)
  "markdown", "code.ink", "history.tool", "ref.at", "ref.before", "ref.marks", "ref.pasted", "paste.info", "drive.check",
]

///|
/// Topics the app watches from its start whatever the person does (the device's downloads, sfbase/downloads.mbt; the
/// copies between the workspace's stations, listed with them: sfdesk transfers.mbt): a run from before the app watched
/// one has none of it, and that is not where the two went apart; it is answered nothing (the run had none of it), and
/// let go of as it was watched.
let ambient : Array[String] = ["downloads", "driveTransfers"]

///|
/// The conversation in `log`: a trace's lines (`{"out":…}`, `{"in":…}`), or a log with them after CORETRACE. Other
/// lines are left out.
pub fn Replay::parse(log : String) -> Replay {
  let evs : Array[Ev] = []
  let run_env : Array[(String, String)] = []
  let run_text : Array[String] = []
  let run_local : Ref[String] = Ref("")
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
      (Some(o), _) => {
        let (wall, has_wall) = match m.get("w") {
          Some(Number(d, ..)) => (d, true)
          _ => (0.0, false)
        }
        let bytes = match m.get("b") {
          Some(String(h)) => Some(@codec.from_hex(h))
          _ => None
        }
        evs.push({ out: true, msg: o, bytes, wall, has_wall, done: false, at: -1.0, given: -1.0, host: false })
      }
      (_, Some(i)) => {
        let (wall, has_wall) = match m.get("w") {
          Some(Number(d, ..)) => (d, true)
          _ => (0.0, false)
        }
        let bytes = match (m.get("b"), m.get("bn")) {
          (Some(String(h)), _) => Some(@codec.from_hex(h))
          // (bytes the trace left out, their length kept: as many zeros)
          (_, Some(Number(n, ..))) => Some(Bytes::new(n.to_int()))
          _ => None
        }
        evs.push({ out: false, msg: i, bytes, wall, has_wall, done: false, at: -1.0, given: -1.0, host: false })
      }
      _ =>
        if m.get("env") is Some(Object(vars)) {
          for k, v in vars {
            if v is String(s) {
              run_env.push((k, s))
            }
          }
        } else if m.get("host") is Some(Object(h)) {
          match h.get("localStation") {
            Some(Object(_) as v) => run_local.val = v.stringify()
            _ => ()
          }
        } else if m.get("textrec") is Some(rec) {
          run_text.push(rec.stringify())
        } else if m.contains("view") ||
          m.contains("still") ||
          m.contains("info") ||
          m.contains("site") ||
          m.contains("sitebody") ||
          m.contains("sitestate") ||
          m.contains("read") {
          let (wall, has_wall) = match m.get("w") {
            Some(Number(d, ..)) => (d, true)
            _ => (0.0, false)
          }
          evs.push({ out: false, msg: j, bytes: None, wall, has_wall, done: false, at: -1.0, given: -1.0, host: true })
        } else {
          match (m.get("step"), m.get("w")) {
            // (a step that acts, when its input was handed to the host (`"acted":true`): the step there, at that
            // moment, not where its line began, for what came meanwhile (the frames before the host took it) to come
            // before it)
            (Some(String(line)), Some(Number(wall, ..))) if m.get("acted") == Some(Json::boolean(true)) =>
              match step_of(line) {
                Some(step) => {
                  let mut k = evs.length() - 1
                  while k >= 0 {
                    if evs[k].msg is Object(o) &&
                      o.get("step") == Some(Json::string(step)) &&
                      o.get("acted") is None {
                      break
                    }
                    k = k - 1
                  }
                  if k >= 0 {
                    evs.remove(k) |> ignore
                  }
                  evs.push({
                    out: true,
                    msg: Json::object({ "step": Json::string(step), "acted": Json::boolean(true) }),
                    bytes: None,
                    wall,
                    has_wall: true,
                    done: false,
                    at: -1.0,
                    given: -1.0,
                    host: false,
                  })
                }
                None => ()
              }
            // (a step's line with the run's clock: mbui's trace_steps; a live run's own, #before's, have none)
            (Some(String(line)), Some(Number(wall, ..))) =>
              match step_of(line) {
                Some(step) =>
                  evs.push({
                    out: true,
                    msg: Json::object({ "step": Json::string(step) }),
                    bytes: None,
                    wall,
                    has_wall: true,
                    done: false,
                    at: -1.0,
                    given: -1.0,
                    host: false,
                  })
                None => ()
              }
            _ => ()
          }
        }
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
    pace: AtOnce,
    strict: true,
    clock: fn() { 0.0 },
    seed: 0,
    asked: [],
    host_said: None,
    skipped: [],
    unasked_reports: [],
    ambient_ids: {},
    run_env,
    run_text,
    run_local: run_local.val,
  }
  r.advance()
  r
}

///|
/// The run's calls named `call` not waited for: what the run did that a test does not do again (`migrate`: the
/// account a scripted run was given by its environment). Their answers are left out too.
pub fn Replay::skip(self : Replay, call : String) -> Unit {
  self.skipped.push(call)
  self.skip_where(fn(name, _) { name == call })
}

///|
/// The run's calls `which` says yes to (by their name and params) not waited for, their answers left out too: what a
/// test answers itself (the core's pure calls whose answers are kept: src/sfkept), not asking the run's core.
pub fn Replay::skip_where(self : Replay, which : (String, Json) -> Bool) -> Unit {
  let gone : Array[Int] = []
  for e in self.evs {
    if e.out &&
      !e.done &&
      e.msg is Object(m) &&
      kind_of(m) == "call" &&
      which(name_of(m), m.get("params").unwrap_or(Json::null())) {
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
    if e.out && !e.done && !is_step(e.msg) && e.msg.stringify().contains(text) {
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
/// From now on, what came is given at `pace`; `strict`: each message waits every ask of the run's before it (else its
/// own, and those before it that are not reports: a run's timing made those, another timing makes others).
pub fn Replay::pace(self : Replay, pace : Pace, strict? : Bool = true) -> Unit {
  self.pace = pace
  self.strict = strict
}

///|
/// The clock the run's pace is kept on (a Tester's `time`): when an ask is made again, when a message is given.
pub fn Replay::clock(self : Replay, clock : () -> Double) -> Unit {
  self.clock = clock
}

///|
/// What came in, handed on in its order, as long as what it came after has been sent again and (at the run's pace)
/// the clock `now` has come to it: at most `at_most` of them (all that may, by default). How many were. With a seed
/// (`shuffle`), what may come at this moment comes in an order drawn from it, each ask's own messages still in theirs.
/// `to`: each handed there (its JSON, its bytes) instead of to the client at once: an app's, the app's queue (a
/// Tester's `post` on "core"), whose next frame gives it to `receive`.
pub fn Replay::deliver(
  self : Replay,
  at_most? : Int = -1,
  now? : Double = @double.infinity,
  host_by? : Double = now,
  taken_at? : Double = now,
  to? : (String, Bytes?) -> Unit,
) -> Int {
  let mut n = 0
  while at_most < 0 || n < at_most {
    let i = self.pick(now, host_by)
    if i < 0 {
      break
    }
    let e = self.evs[i]
    // (given at a frame after it was due, it stands at its due time for what comes after it: the run's gaps kept, not
    // a frame's wait added at each, as a host's lines two to a frame would lag a frame more each two)
    let due = self.due_at(i)
    e.done = true
    let by = if e.host { host_by } else { now }
    e.at = if now < @double.infinity {
      if due > -@double.infinity && due <= by {
        due
      } else {
        now
      }
    } else {
      (self.clock)()
    }
    e.given = if now < @double.infinity { taken_at } else { (self.clock)() }
    if e.host {
      match self.host_said {
        Some(said) => said(e.msg.stringify())
        None => ()
      }
      n += 1
      self.advance()
      continue
    }
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
        n += 1
      }
      None => self.diverged.push("came for an ask not made again: " + e.msg.stringify())
    }
    self.advance()
  }
  n
}

///|
/// What the run's host said of its views (a player's state, a video's frame times, a frame kept: a trace's `view`,
/// `still` and `info` lines), each line handed to `said` in its place, once what the app asked before it has been
/// asked again (a Tester's `view_said`).
pub fn Replay::host(self : Replay, said : (String) -> Unit) -> Unit {
  self.host_said = Some(said)
}

///|
/// A scripted run's step as its trace keeps it (`{"step":LINE,"w":…}`: mbui's trace_steps, the line as its script had
/// it), as a test says it (Flow's emitted line), `now ` aside; None for what a test says only as it writes a script
/// (`answered`, `wait`) or never (`timeout`, a `shot`, a comment). What came after a step in the run waits for the
/// test to have said it (Replay::step_taken): a player's state its host told once the run was past `until 0:02 /` is
/// not given before.
pub fn step_of(line : String) -> String? {
  let l0 = if line.has_prefix("now ") { line.view(start_offset=4).to_owned() } else { line }
  // (`=words`, words alone: the drive says the line it took as it parsed it)
  // (and without the spaces after it: the drive's line as it took it, trimmed)
  let mut l = l0.replace_all(old=" =", new=" ")
  while l.has_suffix(" ") {
    l = l.view(end_offset=l.length() - 1).to_owned()
  }
  let verb = match l.find(" ") {
    Some(k) => l.view(end_offset=k).to_owned()
    None => l
  }
  if said_steps.contains(verb) {
    Some(l)
  } else {
    None
  }
}

///|
/// The steps a test says as a scripted run's (src/sfreplay/emit.mbt).
let said_steps : Array[String] = [
  "tap", "tap1", "tapxy", "hold", "type", "clear", "key", "enter", "back", "drag", "dragon", "hover", "mark", "notice",
  "paste", "pasten", "resize", "rightclick", "wheel", "log", "until", "untiln", "gone", "noticed", "nonotice", "field", "empty",
]

///|
/// Whether `m` (of the run's) is a step of its script, not an ask (step_of).
fn is_step(m : Json) -> Bool {
  m is Object(o) && o.contains("step")
}

///|
/// The run's next step not taken again (its line, step_of's), if what comes next waits for it.
pub fn Replay::next_step(self : Replay) -> String? {
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done {
      return match e.msg {
        Object(m) =>
          match m.get("step") {
            Some(String(l)) => Some(l)
            _ => None
          }
        _ => None
      }
    }
  }
  None
}

///|
/// The run's next step not taken again, when it is `line` (step_of: as the test says it), taken: what came after it
/// may come. Whether it was. Another line (a test that says a step the run did not, or in another order) leaves it
/// waiting, said by `waiting`.
pub fn Replay::step_taken(self : Replay, line : String) -> Bool {
  guard step_of(line) is Some(l) else { return false }
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done && is_step(e.msg) {
      if e.msg is Object(m) && m.get("step") == Some(Json::string(l)) {
        e.done = true
        e.at = (self.clock)()
        self.advance()
        return true
      }
      return false
    }
  }
  false
}

///|
/// The bytes the run sent beside its first call `name` whose params' `key` is `value` (a part of a file going up:
/// `station.upload.part`, `name`, `e2e-photo.jpg`; or a file of a `composer.add`'s, its run of the bytes beside it),
/// as the trace keeps them: what a test hands the app again (shared
/// in, a picture marked) for it to send the same. None where the trace has none (over scripts/trace make's MAX_BYTES).
pub fn Replay::sent_bytes(self : Replay, name : String, key : String, value : String) -> Bytes? {
  for e in self.evs {
    if e.out && e.msg is Object(m) && name_of(m) == name {
      match m.get("params") {
        Some(Object(p)) if p.get(key) == Some(Json::string(value)) => return e.bytes
        Some(Object(p)) =>
          match handed_part(p, e.bytes, fn(v) { v == value }, key) {
            Some(b) => return Some(b)
            None => ()
          }
        _ => ()
      }
    }
  }
  None
}

///|
/// A file handed to the core whole beside a call (`composer.add`'s `files`, each `blob.hostBytes: [start, length]` of
/// the bytes beside it) whose `key` passes `ok`: its bytes.
fn handed_part(p : Map[String, Json], bytes : Bytes?, ok : (String) -> Bool, key : String) -> Bytes? {
  let all = match bytes {
    Some(b) => b
    None => return None
  }
  match p.get("files") {
    Some(Array(files)) =>
      for f in files {
        match f {
          Object(o) =>
            match (o.get(key), o.get("blob")) {
              (Some(String(v)), Some(Object(b))) if ok(v) =>
                match b.get("hostBytes") {
                  Some(Array([Number(start, ..), Number(len, ..)])) => {
                    let s = start.to_int()
                    let n = len.to_int()
                    if s >= 0 && n >= 0 && s + n <= all.length() {
                      return Some(Bytes::makei(n, fn(i) { all[s + i] }))
                    }
                  }
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  None
}

///|
/// The bytes the run sent beside its first call `name` whose params' `key` begins with `prefix` (a picture the run's
/// app named as it made it, its time of day in its name: `e2e-photo-标注-`), as Replay::sent_bytes gives them.
pub fn Replay::sent_bytes_from(self : Replay, name : String, key : String, prefix : String) -> Bytes? {
  for e in self.evs {
    if e.out && e.msg is Object(m) && name_of(m) == name {
      match m.get("params") {
        Some(Object(p)) =>
          match p.get(key) {
            Some(String(v)) if v.has_prefix(prefix) => return e.bytes
            _ =>
              match handed_part(p, e.bytes, fn(v) { v.has_prefix(prefix) }, key) {
                Some(b) => return Some(b)
                None => ()
              }
          }
        _ => ()
      }
    }
  }
  None
}

///|
/// Whether the run answered the call it had as `id` (an `ok` or an `error` for it).
fn Replay::answers(self : Replay, id : Int) -> Bool {
  self.evs.iter().any(fn(e) {
    !e.out && e.msg is Object(m) && (m.contains("ok") || m.contains("error")) && id_of(m) == Some(id)
  })
}

///|
/// The calls made again since the last time asked that the run answered, by name, in the order made (a scripted
/// run's `answered NAME` for each, after the step that made it: what that step waits for, src/sfreplay/emit.mbt).
pub fn Replay::take_asked(self : Replay) -> Array[String] {
  let a = self.asked.copy()
  self.asked.clear()
  a
}

///|
/// Whether a message in may come (what it came after has been sent again), whenever its time.
pub fn Replay::due(self : Replay) -> Bool {
  self.ready().length() > 0
}

///|
/// When the next message in may come, on the clock `deliver` is given (None: none may, each waits an ask not made
/// again, or its anchor has not happened yet; at once: -inf).
pub fn Replay::next_due(self : Replay) -> Double? {
  let mut at : Double? = None
  for i in self.ready() {
    let t = self.due_at(i)
    if t == @double.infinity {
      continue
    }
    at = match at {
      Some(a) if a <= t => Some(a)
      _ => Some(t)
    }
  }
  at
}

///|
/// When message `i` may come at this pace (+inf: not until an ask before it is made again): at once; or at its anchor's
/// time on by the run's gap between them. Its anchor: the latest event before it that has happened again (an ask made
/// again, a message given); one left out (skipped, dropped; not strict, a report not made) is passed over, as is a
/// message in not given yet (what may come at once in another order: its own time stands for it), as are asks with no
/// wall clock (an older trace: anchored to the messages in). None before it: at once.
fn Replay::due_at(self : Replay, i : Int) -> Double {
  let scale = match self.pace {
    AtOnce => return -@double.infinity
    AsRun(scale) => scale
  }
  let mut j = i - 1
  while j >= 0 {
    let e = self.evs[j]
    if e.at >= 0.0 && (e.has_wall || !e.out) {
      let gap = self.evs[i].wall - e.wall
      return e.at + (if gap > 0.0 { gap * scale } else { 0.0 })
    }
    // (a step of the script's is the run's own: timed from what happened again before it, the app's asks it has not
    // made again aside, as they may be made in that time: a draft kept while the run waited to tap)
    if e.out && !e.done && !is_report(e.msg) && !is_step(self.evs[i].msg) {
      return @double.infinity
    }
    j = j - 1
  }
  -@double.infinity
}

///|
/// When the run took the step `line` (Flow's emitted line: step_of), on the clock at this pace (Replay::due_at: its
/// anchor's time on by the run's gap; at once: -inf). None: the trace has no such step (an older one, or one the test
/// does not take again where it is).
pub fn Replay::step_at(self : Replay, line : String) -> Double? {
  match self.step_index(line) {
    Some(i) => Some(self.due_at(i))
    None => None
  }
}

///|
/// The time of day in the run as it took the step `line` (its clock, `w`), when the trace has the step with it: a
/// replay's time of day set to it as the step is taken, so what the app names by the time (a picture marked, saved)
/// is named as the run's was.
pub fn Replay::step_wall(self : Replay, line : String) -> Double? {
  match self.step_index(line) {
    Some(i) if self.evs[i].has_wall => Some(self.evs[i].wall)
    _ => None
  }
}

///|
/// The run's next step not taken again, when it is `line`.
fn Replay::step_index(self : Replay, line : String) -> Int? {
  guard step_of(line) is Some(l) else { return None }
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done && is_step(e.msg) {
      return if e.msg is Object(m) && m.get("step") == Some(Json::string(l)) { Some(i) } else { None }
    }
  }
  None
}

///|
/// Whether `m` (an ask of the run's) is a report (`reports`).
fn is_report(m : Json) -> Bool {
  guard m is Object(o) else { return false }
  kind_of(o) == "call" && reports.contains(name_of(o))
}

///|
/// The messages in that may come whenever their time (what they came after asked again), the first of each ask's: in
/// the run's order: up to the first ask not made again, past those that are reports (strict or not); an ask's own coming
/// once it was made (an answer to an ask not made again does not).
fn Replay::ready(self : Replay) -> Array[Int] {
  let firsts : Array[Int] = []
  let seen : Array[Int] = []
  let from = if self.first_out < self.next_in { self.first_out } else { self.next_in }
  for i in from..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done {
      // (a report waits nothing, strict or not: the run's frames made it, the app's own frames may not, Replay::sent)
      if !is_report(e.msg) {
        break
      }
      continue
    }
    if e.out || e.done {
      continue
    }
    match e.msg {
      Object(m) =>
        match id_of(m) {
          Some(id) => {
            if seen.contains(id) {
              continue
            }
            seen.push(id)
            // (an answer to an ask not made again waits; strict, there is none here)
            if self.ids.contains(id) {
              firsts.push(i)
            }
          }
          None => {
            // a message with no ask (a fatal): in its place, after what came before it
            if firsts.length() == 0 {
              firsts.push(i)
            }
            break
          }
        }
      _ => break
    }
  }
  firsts
}

///|
/// From now on, what may come at once (the messages in due at the same moment) comes in an order drawn from `seed`
/// (another seed, another order; the same, the same): answers to different asks in any order, an ask's own (a
/// subscription's values, a stream's parts) in the order they came. A message with no ask (a fatal) is not passed. 0:
/// as they came.
pub fn Replay::shuffle(self : Replay, seed : UInt) -> Unit {
  self.seed = seed
}

///|
/// The message in to give next at `now` (-1: none may come yet).
fn Replay::pick(self : Replay, now : Double, host_by : Double) -> Int {
  let due = self.ready().filter(fn(i) { self.due_at(i) <= (if self.evs[i].host { host_by } else { now }) })
  if due.length() == 0 {
    return -1
  }
  if self.seed == 0 || due.length() == 1 {
    return due[0]
  }
  // xorshift32
  let mut x = self.seed
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.seed = x
  due[(x % due.length().reinterpret_as_uint()).reinterpret_as_int()]
}

///|
/// How many of the messages in for asks the app made are not handed on yet: at a test's end, what it asked and was
/// never answered.
pub fn Replay::unanswered(self : Replay) -> Int {
  let mut n = 0
  for e in self.evs {
    if !e.out && !e.done && e.msg is Object(m) && id_of(m) is Some(id) && self.ids.contains(id) {
      n += 1
    }
  }
  n
}

///|
/// How many messages in are not handed on yet (the answers to reports the app did not make aside: nothing is to take
/// them).
pub fn Replay::left(self : Replay) -> Int {
  let unmade_reports : Array[Int] = []
  for e in self.evs {
    if e.out && !e.done && is_report(e.msg) {
      match e.msg {
        Object(m) =>
          match id_of(m) {
            Some(id) => unmade_reports.push(id)
            None => ()
          }
        _ => ()
      }
    }
  }
  let mut n = 0
  for e in self.evs {
    if !e.out && !e.done {
      let answers_unmade = match e.msg {
        Object(m) =>
          match id_of(m) {
            Some(id) => unmade_reports.contains(id)
            None => false
          }
        _ => false
      }
      if !answers_unmade {
        n += 1
      }
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
/// The run's asks the app has not made again (yet), in their order, the skipped ones and the reports aside: at a test's
/// end, what the run did that this one did not.
pub fn Replay::unmade(self : Replay) -> Array[String] {
  let out : Array[String] = []
  for e in self.evs {
    if e.out && !e.done && !is_report(e.msg) {
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
  // A compact chat can be answered by the full chat in a tape from before it, and conversely. Prefer an exact ask
  // above when a tape has both.
  if found < 0 && kind == "subscribe" && (name_of(m) == "chat" || name_of(m) == "chatJobs") {
    let same_chat = sig(m, refers, ignore_compact=true)
    for i in self.first_out..<self.evs.length() {
      let e = self.evs[i]
      if e.out && !e.done && e.msg is Object(r) && sig(r, ref_of(r), ignore_compact=true) == same_chat {
        found = i
        break
      }
    }
  }
  if found < 0 && (kind == "subscribe" || kind == "call") {
    let name = name_of(m)
    for i in self.first_out..<self.evs.length() {
      let e = self.evs[i]
      if e.out && !e.done && e.msg is Object(r) && kind_of(r) == kind && name_of(r) == name {
        found = i
        if !(kind == "call" && reports.contains(name)) {
          self.fuzzy.push(text)
        }
        break
      }
    }
  }
  if found < 0 {
    // an ambient topic the run did not watch, watched or let go of
    match id_of(m) {
      Some(now) if kind == "subscribe" && ambient.contains(name_of(m)) => {
        self.ambient_ids[now] = true
        return
      }
      Some(now) if kind == "unsubscribe" && refers is None && self.ambient_ids.contains(now) => {
        self.ambient_ids.remove(now)
        return
      }
      _ => ()
    }
    // a report the run did not make (where the list is, whether its end shows): the app makes those as its own
    // frames have it, the run's frames otherwise (a list gliding to rows that came: its end out of view for a frame
    // here, never in the run's), so not where the two went apart; nothing waits on its answer
    if kind == "call" && reports.contains(name_of(m)) {
      self.unasked_reports.push(text)
      return
    }
    self.diverged.push(text)
    // (a call the run did not make is answered all the same by a live backend: a scripted run waits for it too)
    if kind == "call" {
      self.asked.push(name_of(m))
    }
    return
  }
  let e = self.evs[found]
  e.done = true
  e.at = (self.clock)()
  if e.msg is Object(r) && (kind == "subscribe" || kind == "call") {
    match (id_of(r), id_of(m)) {
      (Some(then), Some(now)) => {
        self.ids[then] = now
        self.back[now] = then
        if kind == "call" && self.answers(then) {
          self.asked.push(name_of(m))
        }
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
fn sig(m : Map[String, Json], refers : Int?, ignore_compact? : Bool = false) -> String {
  let copy : Map[String, Json] = {}
  for k, v in m {
    if k != "id" {
      match (k, v) {
        ("subscribe", Object(t)) if ignore_compact && (t.get("topic") == Some(Json::string("chat")) || t.get("topic") == Some(Json::string("chatJobs"))) => {
          let chat = t.copy()
          chat.remove("compact")
          copy[k] = Json::object(chat)
        }
        _ => copy[k] = v
      }
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

///|
/// How many of the run's calls `call` have had their answer (an `ok` or an `error`: a stream's end) given here: what a
/// scripted run's `answered CALL` lines count (the k-th answer from the start).
pub fn Replay::answers_given(self : Replay, call : String) -> Int {
  let asked : Map[Int, Bool] = {}
  let mut n = 0
  for e in self.evs {
    guard e.msg is Object(m) && m.get("id") is Some(Number(id, ..)) else { continue }
    if e.out {
      if kind_of(m) == "call" && name_of(m) == call {
        asked[id.to_int()] = true
      }
    } else if e.done && !e.host && asked.contains(id.to_int()) && (m.contains("ok") || m.contains("error")) {
      n += 1
    }
  }
  n
}

///|
/// When the answer to the run's latest call `call` given so far was given here (the clock, Replay::clock): what a
/// test times a motion the answer starts from, as the tape has it at this pace, not as the app says it. None while
/// none is given.
pub fn Replay::given_at(self : Replay, call : String) -> Double? {
  let asked : Map[Int, Bool] = {}
  let mut at : Double? = None
  for e in self.evs {
    guard e.msg is Object(m) && m.get("id") is Some(Number(id, ..)) else { continue }
    if e.out {
      if kind_of(m) == "call" && name_of(m) == call {
        asked[id.to_int()] = true
      }
    } else if e.done && !e.host && asked.contains(id.to_int()) && !m.contains("delta") && !m.contains("value") {
      at = Some(e.given)
    }
  }
  at
}

///|
/// When the latest message in given so far that `which` holds for (its JSON) was given here (the clock): a change a
/// subscription's topic came with, what a motion starts from as the tape has it. None while none is.
pub fn Replay::given_at_where(self : Replay, which : (Json) -> Bool) -> Double? {
  let mut at : Double? = None
  for e in self.evs {
    if !e.out && !e.host && e.done && which(e.msg) {
      at = Some(e.given)
    }
  }
  at
}

///|
/// The run's display's frame period as its host's lines measure it (a player's `info` each frame: the first of a
/// frame's lines its moment, those a frame apart and less of it the same frame's), its frames' mean spacing; None
/// where the trace has fewer than two frames of them.
pub fn Replay::frame_period(self : Replay) -> Double? {
  let frames : Array[Double] = []
  for e in self.evs {
    if e.host && e.has_wall {
      match frames.last() {
        // (two lines of one frame come within a few ms of each other)
        Some(last) if e.wall - last < 4.0 => ()
        _ => frames.push(e.wall)
      }
    }
  }
  let gaps = []
  for i in 1..<frames.length() {
    let g = frames[i] - frames[i - 1]
    // (a frame's spacing, not a pause between two showings)
    if g < 25.0 {
      gaps.push(g)
    }
  }
  if gaps.length() < 2 {
    return None
  }
  Some(gaps.fold(init=0.0, fn(a, b) { a + b }) / gaps.length().to_double())
}

///|
/// The run's display's frames as its host's lines have them, the first line of each (lines within a few ms of it the
/// same frame's): their moments on the run's clock, in order.
pub fn Replay::host_frames(self : Replay) -> Array[Double] {
  let frames : Array[Double] = []
  for e in self.evs {
    if e.host && e.has_wall {
      match frames.last() {
        Some(last) if e.wall - last < 4.0 => ()
        _ => frames.push(e.wall)
      }
    }
  }
  frames
}

///|
/// The latest host line given here: when it was due on this clock, and its moment on the run's (what maps the run's
/// frames onto this clock from then on). None while none is.
pub fn Replay::host_given(self : Replay) -> (Double, Double)? {
  let mut last : (Double, Double)? = None
  for e in self.evs {
    if e.host && e.done && e.has_wall {
      last = Some((e.at, e.wall))
    }
  }
  last
}

///|
/// The run's first event that says its moment and has happened again here: when here (this clock) and when in the
/// run (its clock), for a test's time of day to be the run's from then on (Tester::set_wall). None while none has.
pub fn Replay::first_happened(self : Replay) -> (Double, Double)? {
  for e in self.evs {
    if e.has_wall && e.done && e.at >= 0.0 {
      return Some((e.at, e.wall))
    }
  }
  None
}

///|
/// What the run's app was started with, as its trace keeps it (`{"env":…}`): for a replay's to be started the same.
pub fn Replay::env(self : Replay) -> Array[(String, String)] {
  self.run_env
}

///|
/// This machine's station as the run's host said it (Tester::set_local_station: @ui.local_station's JSON); "" where
/// its trace does not say.
pub fn Replay::local_station(self : Replay) -> String {
  self.run_local
}

///|
/// What the run's host answered that its text recording kept (TEXTREC lines, one a line), for a Tester to answer the
/// same (Tester::new's `text`); None when the run kept none.
pub fn Replay::text(self : Replay) -> String? {
  if self.run_text.is_empty() {
    None
  } else {
    Some(self.run_text.join("\n"))
  }
}
