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
  /// a message in for one of the run's `stations` the replay keeps itself (Replay::keep_stations): which, in `kept`
  /// (-1: none)
  mut kept : Int
}

///|
/// One of the run's `stations` subscriptions a replay keeps itself (Replay::keep_stations): its scope (canon), how
/// much of each station it says (`rank`: 2 whole, 1 whole but only those with a drive, 0 brief), its value so far
/// (its deltas applied), and when it was last given one (the replay's count of them: the latest of a rank wins).
priv struct KeptStations {
  scope : String
  rank : Int
  mut value : Json?
  mut given : Int
}

///|
// strict is never read: the strict and the lax passes give what came alike
#warnings("-unused_field")
pub struct Replay {
  priv evs : Array[Ev]
  /// a recorded ask's id: the id the app gave the same ask now; and the other way
  priv ids : Map[Int, Int]
  priv back : Map[Int, Int]
  /// a recorded subscription the app asks twice now (a chats' list whole and its first rows, a tape from before those):
  /// the other ids what comes for it goes to as well; what came for it so far (its value with its deltas); and what is
  /// to be given at the next delivery (its value so far, to the one asked after)
  priv copies : Map[Int, Array[Int]]
  priv latest : Map[Int, Json]
  priv owed : Array[Json]
  /// the recorded subscriptions that may be asked twice so (the stations, a chats' list), whose values are kept so
  priv twins : Map[Int, Bool]
  /// the first message out not yet sent again (or evs.length())
  priv mut first_out : Int
  /// the first message in not yet given (or evs.length())
  priv mut next_in : Int
  priv mut client : Client?
  priv diverged : Array[String]
  // (the moment each of them was asked, on the app's clock)
  priv diverged_at : Array[Double]
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
  /// whether a step of the script's is timed from the step before it (Replay::chain_steps: a pace pass's, its frames
  /// not the run's), else from what happened again before it
  priv mut steps_chained : Bool
  /// the clock the replay's events are timed on (a Tester's: when an ask is made again, a message given)
  priv mut clock : () -> Double
  /// the calls made since the last take_asked that the run answered (or that it did not make: a live backend answers
  /// them), by name, in the order made
  priv asked : Array[String]
  /// the calls set aside (Replay::skip)
  priv skipped : Array[String]
  /// reports the app made that the run did not (Replay::sent: its frames had them, the run's not)
  priv unasked_reports : Array[String]
  /// the run's unsubscriptions made again after messages the run had after them were given (Replay::late_unsubs)
  priv late_unsubs : Array[(String, Int, Double)]
  /// the ids the app gave its watches of `ambient` topics the run did not have (let go of as well, unasked)
  priv ambient_ids : Map[Int, Bool]
  /// what the run's app was started with (its trace's `{"env":…}`: src/stillfail's CORETRACE env)
  priv run_env : Array[(String, String)]
  /// what the run's host answered that its text recording kept (`{"textrec":…}`: TEXTREC lines, mbui's hostrec.mbt):
  /// a word's bounds, a picture's sizes; one a line
  priv run_text : Array[String]
  /// when the run's display began each frame, on the run's clock (`w` of its trace's `{"frame":T}` lines: src/stillfail's
  /// CORETRACE frame); none in a trace recorded before they were kept
  priv run_frames : Array[Double]
  /// this machine's station as the run's host said it (its trace's `{"host":{"localStation":…}}`: src/stillfail's CORETRACE host)
  priv run_local : String
  /// what the run's host gave its frames as the run began (its trace's first `{"settings":…}`: mbui's
  /// @ui.trace_settings, src/stillfail's CORETRACE settings); those after it are given again as the host's lines are
  /// (Replay::host), at their place
  priv run_settings : Json?
  /// where what the run's host said of its views goes (Replay::host)
  priv mut host_said : ((String) -> Unit)?
  /// the run's `stations` subscriptions, kept by the replay itself (Replay::keep_stations); how many of their values
  /// were given so far; each scope's value as last given to the app; the app's asks for a scope's stations now (its
  /// id: the scope)
  priv mut stations_own : Bool
  priv kept : Array[KeptStations]
  priv mut kept_given : Int
  priv scope_said : Map[String, Json]
  priv stations_asked : Map[Int, String]
}

///|
/// When a run's messages are given again (Replay::pace): `AtOnce`, as soon as what they came after has been asked
/// again; `AsRun(scale)`, also not before the clock has gone on from its anchor by the gap the run had between them
/// (in its wall clock), times `scale` (1: as the run had it; 2: twice as slow; 0.5: twice as fast). A message's anchor
/// is the latest event before it in the run that has happened again: an ask made again, a message given (Replay::
/// due_at); a trace whose asks have no wall clock (an older one) anchors to the messages in only.
#derive(Eq, Debug)
pub(all) enum Pace {
  AtOnce
  AsRun(Double)
}

///|
/// Asks that only tell the core what the app sees or keeps (where its chat's list is, a draft and what is typed in it, where it was read to,
/// where a player was left): how many and when depends on the run's timing, and what they say with it (a player's
/// place is how far it played: the frames had them, the run's or the app's). Strict or not (Replay::pace), they wait
/// nothing, none is required and one the run did not make is not where the two went apart; one made again with other
/// params is the run's next of its name, not said to differ.
let reports : Array[String] = [
  "client.focus", "client.shown", "client.reports", "chat.place", "draft.put", "drive.place", "composer.text", "composer.comment",
  // (a chats' list's window raised as it is scrolled near its foot: as the frames scrolled it)
  "chats.window",
  // (how many of a chat's last messages it opens on, told before it is asked: a run from before it never told it, and
  // a chat's topic is the same either way)
  "chat.window",
  // the core's pure calls a replay's app answers from what is kept (src/sfkept) when it has the answer, and asks the
  // tape for when not: a tape's that the app answered itself is not where the two went apart, nor one it asks of a tape
  // from before the call (sfreplay's source.mbt tells the tape of each it answered, as a report)
  "markdown", "code.ink", "history.tool", "ref.at", "ref.before", "ref.marks", "ref.words", "ref.pasted", "paste.info", "drive.check",
]

///|
/// Topics the app watches from its start whatever the person does (the device's downloads, sfbase/downloads.mbt; the
/// copies between the workspace's stations, listed with them: sfdesk transfers.mbt; the team's replies on a chat's bug
/// reports, watched with its composer: sfpages feedback_replies.mbt): a run from before the app watched one has none of it, and that is not where the two went apart; it is answered nothing (the run had none of it), and
/// let go of as it was watched.
let ambient : Array[String] = ["downloads", "driveTransfers", "chatFeedback"]

///|
/// The conversation in `log`: a trace's lines (`{"out":…}`, `{"in":…}`), or a log with them after CORETRACE. Other
/// lines are left out.
///|
/// What the app told the core in this replay, each message as a line (its kind, what it names, its params; an
/// unsubscribe by what it subscribed, a subscription's id left out): what two passes of a flow at other paces are
/// held to say alike (sfreplay's `orders`). Not the reports (`reports`: their number is the timing's by design).
// kept across runs: begun anew by each replay (Replay::parse)
let outs_said : Array[String] = []

///|
// kept across runs: begun anew by each replay (Replay::parse)
let outs_subs : Map[Int, String] = Map([])

///|
/// What the app told the core in the replay last begun, in order (outs_said).
pub fn Replay::outs(self : Replay) -> Array[String] {
  ignore(self)
  outs_said.copy()
}

///|
fn outs_note(m : Map[String, Json], kind : String) -> Unit {
  let id = match id_of(m) {
    Some(i) => i
    None => -1
  }
  match kind {
    "subscribe" => {
      let key = m.get("subscribe").map(fn(t) { canon(t) }).unwrap_or("")
      outs_subs[id] = key
      outs_said.push("sub " + key + (if m.contains("have") { " have" } else { "" }))
    }
    "unsubscribe" =>
      outs_said.push(
        "unsub " + outs_subs.get(id).unwrap_or("?") + (if m.get("keep") is Some(True) { " keep" } else { "" }),
      )
    "call" => {
      let name = name_of(m)
      if !reports.contains(name) {
        outs_said.push("call " + name + " " + canon(m.get("params").unwrap_or(Json::null())))
      }
    }
    other => outs_said.push(other + " " + name_of(m))
  }
}

///|
pub fn Replay::parse(log : String) -> Replay {
  outs_said.clear()
  outs_subs.clear()
  let evs : Array[Ev] = []
  let run_env : Array[(String, String)] = []
  let run_text : Array[String] = []
  let run_frames : Array[Double] = []
  let run_local : Ref[String] = Ref("")
  let run_settings : Ref[Json?] = Ref(None)
  for v in log.split("\n") {
    let line = v.to_owned()
    let start = match line.find("CORETRACE ") {
      Some(i) => i + 10
      None => if line.has_prefix("{") { 0 } else { continue }
    }
    let j = @json.parse(line.exact_view(start=start).to_owned()) catch {
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
        evs.push({ out: true, msg: o, bytes, wall, has_wall, done: false, at: -1.0, given: -1.0, host: false, kept: -1 })
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
        evs.push({ out: false, msg: i, bytes, wall, has_wall, done: false, at: -1.0, given: -1.0, host: false, kept: -1 })
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
        } else if m.get("settings") is Some(Object(_)) && run_settings.val is None {
          run_settings.val = Some(j)
        } else if m.get("frame") is Some(Number(_, ..)) {
          match m.get("w") {
            Some(Number(w, ..)) => run_frames.push(w)
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
          m.contains("settings") ||
          m.contains("read") {
          let (wall, has_wall) = match m.get("w") {
            Some(Number(d, ..)) => (d, true)
            _ => (0.0, false)
          }
          evs.push({ out: false, msg: j, bytes: None, wall, has_wall, done: false, at: -1.0, given: -1.0, host: true, kept: -1 })
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
                    kept: -1,
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
                    kept: -1,
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
    copies: {},
    latest: {},
    owed: [],
    twins: {},
    first_out: 0,
    next_in: 0,
    client: None,
    diverged: [],
    diverged_at: [],
    fuzzy: [],
    wall: 0.0,
    walls: [],
    pace: AtOnce,
    steps_chained: false,
    clock: fn() { 0.0 },
    seed: 0,
    asked: [],
    host_said: None,
    skipped: [],
    unasked_reports: [],
    late_unsubs: [],
    ambient_ids: {},
    run_env,
    run_text,
    run_frames,
    run_local: run_local.val,
    run_settings: run_settings.val,
    stations_own: false,
    kept: [],
    kept_given: 0,
    scope_said: {},
    stations_asked: {},
  }
  r.advance()
  r
}

///|
/// A run whose app asked the stations as whole lists (`stations {scope}`, `brief`, `drive`: a trace from before the
/// core sent them as rows, its head without sfcore's MBUI_STATION_ROWS), given to an app that asks only `stations
/// {scope}` (sfreplay's source reads its rows, a station and its parts out of that): the run's `stations` subscriptions
/// and their unsubscriptions are the replay's own, never matched to an ask of the app's. They count as made from the
/// start (they hold back nothing, none is unmade); what came for them comes in the run's order and time as any message in
/// (after what the run asked before it), kept for each (its deltas applied). A scope's value is, of those that said
/// one, the latest of the richest kind (whole, over whole with a drive only, over brief); the app's `stations {scope}`
/// is given it at once, and whole again each time it changes, until it is let go of. Said before anything is asked
/// (as the replay is made, before `attach`).
pub fn Replay::keep_stations(self : Replay) -> Unit {
  // (a kept one by the id the run gave it, while the run had it: ids are given again after a client's reset)
  self.stations_own = true
  let owner : Map[Int, Int] = Map([])
  for e in self.evs {
    guard e.msg is Object(m) && !e.host && !is_step(e.msg) else { continue }
    guard id_of(m) is Some(id) else { continue }
    if e.out {
      match kind_of(m) {
        "subscribe" if name_of(m) == "stations" => {
          let t = match m.get("subscribe") {
            Some(Object(t)) => t
            _ => {}
          }
          let rank = if t.get("brief") == Some(Json::boolean(true)) {
            0
          } else if t.get("drive") == Some(Json::boolean(true)) {
            1
          } else {
            2
          }
          owner[id] = self.kept.length()
          self.kept.push({ scope: canon(t.get("scope").unwrap_or(Json::null())), rank, value: None, given: 0 })
          e.done = true
        }
        "subscribe" | "call" => owner.remove(id)
        "unsubscribe" if owner.contains(id) => {
          e.done = true
          owner.remove(id)
        }
        _ => ()
      }
    } else {
      match owner.get(id) {
        Some(k) => e.kept = k
        None => ()
      }
    }
  }
  self.advance()
}

///|
/// The scope's value as the run's kept `stations` say it now (Replay::keep_stations): of those that said one, the
/// latest of the richest kind.
fn Replay::scope_value(self : Replay, scope : String) -> Json? {
  let mut best : KeptStations? = None
  for k in self.kept {
    if k.scope != scope || k.value is None {
      continue
    }
    best = match best {
      Some(b) if b.rank > k.rank || (b.rank == k.rank && b.given > k.given) => Some(b)
      _ => Some(k)
    }
  }
  match best {
    Some(b) => b.value
    None => None
  }
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
/// A watch let go of or an ask cancelled names it by its id, and nothing came for that: what came for the watch stays.
pub fn Replay::drop(self : Replay, text : String) -> Int {
  let gone : Array[Int] = []
  let mut n = 0
  for e in self.evs {
    if e.out && !e.done && !is_step(e.msg) && e.msg.stringify().contains(text) {
      e.done = true
      n += 1
      match e.msg {
        Object(m) =>
          match id_of(m) {
            Some(id) if !(kind_of(m) == "unsubscribe" || kind_of(m) == "cancel") => gone.push(id)
            _ => ()
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
  n
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
  // (the core's place this conversation's from now: a made-up core that had it no longer, core.mbt's serve)
  serving.val = 0
  // A reader still following a subscription can ask for it again during reset: its ask belongs to this replay.
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
  client.reset()
}

///|
/// The app's core is the engine again.
pub fn Replay::detach() -> Unit {
  serving.val = 0
  transport.val = engine_send
  wall_override.val = None
  receive_hook.val = None
}

///|
/// From now on, what came is given at `pace`. Every pass waits the same (Replay::ready): a message waits its own ask and
/// those before it that are not reports, as a report the run's frames made the app's own frames may not make again.
pub fn Replay::pace(self : Replay, pace : Pace) -> Unit {
  self.pace = pace
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
  let give = fn(msg : Json, bytes : Bytes?) {
    match to {
      Some(post) => post(msg.stringify(), bytes)
      None =>
        match self.client {
          Some(c) => c.receive_json(msg, bytes~)
          None => ()
        }
    }
  }
  let owed = self.owed.copy()
  self.owed.clear()
  for msg in owed {
    give(msg, None)
  }
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
    // (for one of the run's stations the replay keeps: kept, and its scope's value given whole to what asks it now,
    // where that changed: Replay::keep_stations)
    if e.kept >= 0 {
      let k = self.kept[e.kept]
      match e.msg {
        Object(m) =>
          match (m.get("value"), m.get("delta"), k.value) {
            (Some(v), _, _) => k.value = Some(v)
            (_, Some(Array(ops)), Some(was)) => k.value = Some(apply_delta(was, ops))
            _ => ()
          }
        _ => ()
      }
      self.kept_given += 1
      k.given = self.kept_given
      match self.scope_value(k.scope) {
        Some(v) if !(self.scope_said.get(k.scope) is Some(was) && physical_equal(was, v)) => {
          self.scope_said[k.scope] = v
          for now, scope in self.stations_asked {
            if scope == k.scope {
              let msg = Json::object({ "id": Json::number(now.to_double()), "value": v })
              match to {
                Some(post) => {
                  self.walls.push(e.wall)
                  post(msg.stringify(), None)
                }
                None => {
                  if e.wall > self.wall {
                    self.wall = e.wall
                  }
                  match self.client {
                    Some(c) => c.receive_json(msg)
                    None => ()
                  }
                }
              }
            }
          }
        }
        _ => ()
      }
      n += 1
      self.advance()
      continue
    }
    // (one asked twice now: what came so far kept, and given to the other too)
    match e.msg {
      Object(m) =>
        match id_of(m) {
          Some(then) => {
            if self.twins.contains(then) {
              match (m.get("value"), m.get("delta"), self.latest.get(then)) {
                (Some(v), _, _) => self.latest[then] = v
                (_, Some(Array(ops)), Some(was)) => self.latest[then] = apply_delta(was, ops)
                _ => ()
              }
            }
            match self.copies.get(then) {
              Some(more) =>
                for now in more {
                  let copy = m.copy()
                  copy["id"] = Json::number(now.to_double())
                  give(Json::object(copy), e.bytes)
                }
              None => ()
            }
          }
          None => ()
        }
      _ => ()
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
      None => self.diverge("came for an ask not made again: " + e.msg.stringify())
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
  let l0 = if line.has_prefix("now ") { line.exact_view(start=4).to_owned() } else { line }
  // (`=words`, words alone: the drive says the line it took as it parsed it)
  // (and without the spaces after it: the drive's line as it took it, trimmed)
  let mut l = l0.replace_all(old=" =", new=" ")
  while l.has_suffix(" ") {
    l = l.exact_view(end=l.length() - 1).to_owned()
  }
  let verb = match l.find(" ") {
    Some(k) => l.exact_view(end=k).to_owned()
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
/// When the last message in given so far was given (-inf: none yet).
pub fn Replay::last_given(self : Replay) -> Double {
  let mut most = -@double.infinity
  for e in self.evs {
    if !e.out && e.at > most {
      most = e.at
    }
  }
  most
}

///|
/// The step taken last held taken at `at` (the strict pass's first, taken once what it waited for was so): what is
/// timed from it (the run's next steps, Replay::due_at) on from there.
pub fn Replay::step_moved_to(self : Replay, at : Double) -> Unit {
  let mut i = self.evs.length() - 1
  while i >= 0 {
    let e = self.evs[i]
    if e.out && e.done && is_step(e.msg) {
      e.at = at
      return
    }
    i = i - 1
  }
}

///|
/// When the last of what the run asked before its next step not taken again, not asked here yet, was due to be asked
/// at this pace (each on from the latest event before it that happened again, by their gap in the run; a report aside,
/// Replay::sent): -inf where there is none, or at once.
pub fn Replay::asks_before_step_due(self : Replay) -> Double {
  let scale = match self.pace {
    AtOnce => return -@double.infinity
    AsRun(scale) => scale
  }
  let mut most = -@double.infinity
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if !e.out || e.done {
      continue
    }
    if is_step(e.msg) {
      break
    }
    if is_report(e.msg) || is_let_go(e.msg) || !e.has_wall {
      continue
    }
    let mut j = i - 1
    while j >= 0 {
      let a = self.evs[j]
      if a.at >= 0.0 && (a.has_wall || !a.out) {
        let gap = e.wall - a.wall
        let t = a.at + (if gap > 0.0 { gap * scale } else { 0.0 })
        if t > most {
          most = t
        }
        break
      }
      j = j - 1
    }
  }
  most
}

///|
/// Whether the run asked something before its next step not taken again that this run has not asked yet (a report
/// aside, Replay::sent): what comes before the step has not all happened again.
pub fn Replay::asks_before_step(self : Replay) -> Bool {
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done {
      if is_step(e.msg) {
        return false
      }
      if !is_report(e.msg) && !is_let_go(e.msg) {
        return true
      }
    }
  }
  false
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
/// again, a message given); one left out (skipped, dropped, a report not made) is passed over, as is a
/// message in not given yet (what may come at once in another order: its own time stands for it), as are asks with no
/// wall clock (an older trace: anchored to the messages in). None before it: at once.
fn Replay::due_at(self : Replay, i : Int) -> Double {
  let due = self.due_chained(i)
  // (never before the run's latest step taken again before it, by their gap in the run: what came after a step in the
  // run comes after it here, on the timeline from where it was taken (a first step taken later than the run's moment
  // for it, its first screen later: all after it later by as much), whatever was made again sooner meanwhile (an
  // unsubscription the run made after the step, made here before it: wide-newline's answers timed from it came 15.7 ms
  // before the tap that asked for them, its next step's moment 9.6 ms before the tap))
  match self.step_before(i) {
    Some((at, wall)) if due > -@double.infinity && due < @double.infinity && self.evs[i].has_wall => {
      let scale = match self.pace {
        AsRun(scale) => scale
        AtOnce => 1.0
      }
      let gap = self.evs[i].wall - wall
      let from_step = at + (if gap > 0.0 { gap * scale } else { 0.0 })
      if from_step > due { from_step } else { due }
    }
    _ => due
  }
}

///|
/// The run's latest step before event `i` taken again here that says its moment: when here and when in the run.
fn Replay::step_before(self : Replay, i : Int) -> (Double, Double)? {
  let mut k = i - 1
  while k >= 0 {
    let e = self.evs[k]
    if e.out && e.done && e.at >= 0.0 && e.has_wall && is_step(e.msg) {
      return Some((e.at, e.wall))
    }
    k = k - 1
  }
  None
}

///|
/// When event `i` is due by the events before it alone (due_at's, before the steps are taken into account).
fn Replay::due_chained(self : Replay, i : Int) -> Double {
  let scale = match self.pace {
    AtOnce => return -@double.infinity
    AsRun(scale) => scale
  }
  // (a step of the script's: on from the step before it as the run's script went on from it, by their gap in the
  // run, whenever what came between them was taken here: an input is the run's own moment at any frame rate, not one
  // that follows what this pace's frames took when)
  if self.steps_chained && is_step(self.evs[i].msg) {
    let mut k = i - 1
    while k >= 0 {
      let e = self.evs[k]
      if is_step(e.msg) && e.done && e.at >= 0.0 && e.has_wall && self.evs[i].has_wall {
        let gap = self.evs[i].wall - e.wall
        return e.at + (if gap > 0.0 { gap * scale } else { 0.0 })
      }
      k = k - 1
    }
    // (the first step: from the first of the run that happened again here, by their gap in the run, not from what
    // this pace's frames took last before it)
    for j in 0..<i {
      let e = self.evs[j]
      if e.at >= 0.0 && (e.has_wall || !e.out) && self.evs[i].has_wall {
        let gap = self.evs[i].wall - e.wall
        return e.at + (if gap > 0.0 { gap * scale } else { 0.0 })
      }
    }
  }
  let mut j = i - 1
  while j >= 0 {
    let e = self.evs[j]
    if e.at >= 0.0 && (e.has_wall || !e.out) {
      let gap = self.evs[i].wall - e.wall
      return e.at + (if gap > 0.0 { gap * scale } else { 0.0 })
    }
    // (a step of the script's is the run's own: timed from what happened again before it, the app's asks it has not
    // made again aside, as they may be made in that time: a draft kept while the run waited to tap; nor is anything
    // timed from one let go of not made again yet, which holds nothing back, Replay::ready)
    if e.out && !e.done && !is_report(e.msg) && !is_let_go(e.msg) && !is_step(self.evs[i].msg) {
      return @double.infinity
    }
    j = j - 1
  }
  -@double.infinity
}

///|
/// Each step of the script's timed from the step before it, by their gap in the run (Replay::due_at): for a pass whose
/// frames are not the run's (a pace pass, at a display's rate), so its inputs come at the run's moments whatever its
/// frames took when. The strict pass's frames and steps are mapped from the run together: not so.
pub fn Replay::chain_steps(self : Replay) -> Unit {
  self.steps_chained = true
}

///|
/// When the run's next step not taken again is due at this pace (Replay::due_at), +inf where there is none or it waits
/// for an ask not made again: up to when what a step set off is drawn before the next input comes (Tester::inputs_next).
pub fn Replay::next_step_at(self : Replay) -> Double {
  for i in self.first_out..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done && is_step(e.msg) {
      return self.due_at(i)
    }
  }
  @double.infinity
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
/// Whether `m` (an ask of the run's) lets go of one: what comes after it waits nothing of it, as a core sends one
/// topic's values whether or not another was let go of yet (Replay::ready); it is made again all the same by the end.
fn is_let_go(m : Json) -> Bool {
  guard m is Object(o) else { return false }
  kind_of(o) == "unsubscribe"
}

///|
/// The messages in that may come whenever their time (what they came after asked again), the first of each ask's: in
/// the run's order: up to the first ask not made again, past those that are reports; an ask's own coming
/// once it was made (an answer to an ask not made again does not).
fn Replay::ready(self : Replay) -> Array[Int] {
  let firsts : Array[Int] = []
  let seen : Array[Int] = []
  let seen_kept : Array[Int] = []
  let from = if self.first_out < self.next_in { self.first_out } else { self.next_in }
  for i in from..<self.evs.length() {
    let e = self.evs[i]
    if e.out && !e.done {
      // (a report waits nothing: the run's frames made it, the app's own frames may not, Replay::sent; nor does one
      // let go of (is_let_go): no message comes of it, and a core does not hold one topic back for another not let go
      // of yet; the coordinator of the migration, 2026-11-12)
      if !is_report(e.msg) && !is_let_go(e.msg) {
        break
      }
      continue
    }
    if e.out || e.done {
      continue
    }
    // (for one of the run's stations the replay keeps: made from the start, its own first coming, Replay::keep_stations)
    if e.kept >= 0 {
      if !seen_kept.contains(e.kept) {
        seen_kept.push(e.kept)
        firsts.push(i)
      }
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
            // (an answer to an ask not made again waits)
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
    if !e.out && !e.done && e.kept < 0 && e.msg is Object(m) && id_of(m) is Some(id) && self.ids.contains(id) {
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
/// Each of them with the moment it was asked, on the app's clock (@hostapi.now): for a flow whose strict pass is known
/// to ask them (sfreplay's strict_diverged_known), held to them and that moment.
pub fn Replay::diverged_at(self : Replay) -> Array[(Double, String)] {
  let out = []
  for i, d in self.diverged {
    out.push((self.diverged_at[i], d))
  }
  out
}

///|
fn Replay::diverge(self : Replay, text : String) -> Unit {
  self.diverged.push(text)
  self.diverged_at.push(@hostapi.now())
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
/// The run's unsubscriptions this one made after messages the run had after them were given (Replay::ready gives
/// those without waiting for it): each as made, how many came before it, and how long before it the first of them
/// came (ms on the app's clock). Said, not held to anything: a subscription kept longer than the run kept it shows here.
pub fn Replay::late_unsubs(self : Replay) -> Array[(String, Int, Double)] {
  self.late_unsubs
}

///|
/// Asks made again with other params, matched to the run's next of their kind and name.
pub fn Replay::fuzzy(self : Replay) -> Array[String] {
  self.fuzzy
}

///|
/// Whether this recording has the separate jobs summary that newer chat pages ask for.
pub fn Replay::has_jobs_summary(self : Replay) -> Bool {
  for e in self.evs {
    if !e.out {
      continue
    }
    match e.msg {
      Object(m) =>
        match m.get("subscribe") {
          Some(Object(t)) if t.get("topic") == Some(Json::string("chatJobs")) &&
            t.get("summary") == Some(Json::boolean(true)) => return true
          _ => ()
        }
      _ => ()
    }
  }
  false
}

///|
/// One message the app sends, matched to the run's.
fn Replay::out(self : Replay, text : String) -> Unit {
  let msg = @json.parse(text) catch {
    _ => {
      self.diverge(text)
      return
    }
  }
  guard msg is Object(m) else {
    self.diverge(text)
    return
  }
  let kind = kind_of(m)
  outs_note(m, kind)
  // The stations of a run whose own the replay keeps (Replay::keep_stations): asked, given the scope's value at the
  // next delivery and whole again as it changes; let go of, no more.
  if self.stations_own {
    match id_of(m) {
      Some(now) if kind == "subscribe" && name_of(m) == "stations" => {
        let scope = match m.get("subscribe") {
          Some(Object(t)) => canon(t.get("scope").unwrap_or(Json::null()))
          _ => canon(Json::null())
        }
        self.stations_asked[now] = scope
        match self.scope_said.get(scope) {
          Some(v) => self.owed.push({ "id": Json::number(now.to_double()), "value": v })
          None => ()
        }
        return
      }
      Some(now) if kind == "unsubscribe" && self.stations_asked.contains(now) => {
        self.stations_asked.remove(now)
        return
      }
      _ => ()
    }
  }
  // One asked twice now and let go of (a copy of the tape's one, given what comes for that: the changelog's page
  // left, the chats' list's card still asking its news): no ask of the run's, whose one goes on.
  match id_of(m) {
    Some(now) if kind == "unsubscribe" =>
      match self.back.get(now) {
        Some(then) if self.copies.get(then).map_or(false, fn(more) { more.contains(now) }) => {
          self.copies[then] = self.copies.get(then).unwrap_or([]).filter(fn(x) { x != now })
          self.back.remove(now)
          return
        }
        _ => ()
      }
    _ => ()
  }
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
  // A compact chat can be answered by the full chat in an older tape, and a jobs summary by the old full jobs view.
  // Prefer an exact ask above when a tape has both.
  if found < 0 && kind == "subscribe" && (name_of(m) == "chat" || name_of(m) == "chatJobs") {
    let summary = match m.get("subscribe") {
      Some(Object(t)) => name_of(m) == "chatJobs" && t.get("summary") == Some(Json::boolean(true))
      _ => false
    }
    let same_chat = sig(m, refers, ignore_compact=true, ignore_summary=summary)
    for i in self.first_out..<self.evs.length() {
      let e = self.evs[i]
      if e.out && !e.done && e.msg is Object(r) && sig(r, ref_of(r), ignore_compact=true, ignore_summary=summary) == same_chat {
        found = i
        break
      }
    }
  }
  // A chats' list asked for its first rows (`limit`) and the changelog asked for its news alone or for a tab's first
  // changes (`part`, `limit`) can be answered by the whole in an older tape.
  if found < 0 && kind == "subscribe" && twin_topic(name_of(m)) {
    let same = sig(m, refers, ignore_part=true)
    for i in self.first_out..<self.evs.length() {
      let e = self.evs[i]
      if e.out && !e.done && e.msg is Object(r) && sig(r, ref_of(r), ignore_part=true) == same {
        found = i
        break
      }
    }
  }
  // One asked after another the tape's one went to (the whole list after its first rows, or the other way): given what
  // came for it so far, and what comes for it from now on, as the first is.
  if found < 0 && kind == "subscribe" && twin_topic(name_of(m)) {
    let same = sig(m, refers, ignore_part=true)
    for i in 0..<self.evs.length() {
      let e = self.evs[i]
      match (e.out && e.done, e.msg, id_of(m)) {
        (true, Object(r), Some(now)) if kind_of(r) == "subscribe" && sig(r, ref_of(r), ignore_part=true) == same =>
          match id_of(r) {
            Some(then) if self.ids.contains(then) => {
              match self.copies.get(then) {
                Some(more) => more.push(now)
                None => self.copies[then] = [now]
              }
              self.back[now] = then
              match self.latest.get(then) {
                Some(v) => self.owed.push({ "id": Json::number(now.to_double()), "value": v })
                None => ()
              }
              return
            }
            _ => ()
          }
        _ => ()
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
    self.diverge(text)
    // (a call the run did not make is answered all the same by a live backend: a scripted run waits for it too, unless
    // nobody reads its answer, awaited by nothing there)
    if kind == "call" && !(id_of(m) is Some(now) && client.call_unread(now)) {
      self.asked.push(name_of(m))
    }
    return
  }
  let e = self.evs[found]
  e.done = true
  e.at = (self.clock)()
  // (one let go of after messages the run had after it came: how many, from how long before)
  if kind == "unsubscribe" {
    let mut n = 0
    let mut earliest = @double.infinity
    for j in (found + 1)..<self.evs.length() {
      let a = self.evs[j]
      if !a.out && a.done && a.at >= 0.0 {
        n = n + 1
        if a.at < earliest {
          earliest = a.at
        }
      }
    }
    if n > 0 {
      self.late_unsubs.push((text, n, e.at - earliest))
    }
  }
  if e.msg is Object(r) && (kind == "subscribe" || kind == "call") {
    match (id_of(r), id_of(m)) {
      (Some(then), Some(now)) => {
        self.ids[then] = now
        self.back[now] = then
        if kind == "subscribe" && twin_topic(name_of(m)) {
          self.twins[then] = true
        }
        // (one whose answer nobody reads awaited by nothing in a scripted run: no `answered` line for it, emit.mbt;
        // since #5425, client.device and the start's notify.permission)
        if kind == "call" && self.answers(then) && !client.call_unread(now) {
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
          let copy : Map[String, Json] = Map([])
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
/// Whether topic `name` is one a page may ask a part of (a chats' list's first rows; the changelog's news alone, or a
/// tab's first changes) where an older tape asked the whole, or both are asked in a run: answered by the tape's one
/// (sig's `ignore_part`; the changelog's whole holds every tab's days, read the same way, and says no `more`). And the
/// workspaces' marks, asked of the workspace shown before they were one topic whichever is (a tape without
/// MBUI_MARKS_ONE): answered by the tape's, of whichever workspace it asked them. The stations are not: a tape from
/// before their rows keeps its own (Replay::keep_stations), a newer one is held to them as to any topic.
fn twin_topic(name : String) -> Bool {
  name == "chats" || name == "changelog" || name == "workspaceMarks"
}

///|
/// What an ask is, whatever its id: its message without the id, keys in order; an unsubscription or a cancel with the
/// run's id of what it names (`refers`).
fn sig(
  m : Map[String, Json],
  refers : Int?,
  ignore_compact? : Bool = false,
  ignore_summary? : Bool = false,
  ignore_part? : Bool = false,
) -> String {
  let copy : Map[String, Json] = Map([])
  for k, v in m {
    // (asked as more of another of its subscriptions: answered whole as the tape's one is)
    if k != "id" && !(k == "from" && ignore_part && twin_topic(name_of(m))) {
      match (k, v) {
        ("subscribe", Object(t)) if ignore_part && twin_topic(name_of(m)) => {
          let asked = t.copy()
          asked.remove("limit")
          asked.remove("news")
          asked.remove("part")
          if t.get("topic") == Some(Json::string("workspaceMarks")) {
            asked.remove("workspace")
          }
          copy[k] = Json::object(asked)
        }
        ("subscribe", Object(t)) if ignore_compact && (t.get("topic") == Some(Json::string("chat")) || t.get("topic") == Some(Json::string("chatJobs"))) => {
          let chat = t.copy()
          chat.remove("compact")
          if ignore_summary && t.get("topic") == Some(Json::string("chatJobs")) {
            chat.remove("summary")
          }
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
  let asked : Map[Int, Bool] = Map([])
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
/// When the app asked the run's `n`-th call `call` here (Replay::clock; counted from the start) and when that one's
/// answer (an `ok` or an `error`) was given here: a pace pass's `answered` step, said not waited on (Flow::answered).
/// None where it is not so yet.
pub fn Replay::nth_call_at(self : Replay, call : String, n : Int) -> (Double?, Double?) {
  let mut k = 0
  let mut id = -1
  let mut asked : Double? = None
  for e in self.evs {
    guard e.msg is Object(m) && m.get("id") is Some(Number(i, ..)) else { continue }
    if id < 0 {
      if e.out && kind_of(m) == "call" && name_of(m) == call {
        k += 1
        if k == n {
          id = i.to_int()
          asked = if e.done && e.at >= 0.0 { Some(e.at) } else { None }
        }
      }
    } else if !e.out && !e.host && e.done && i.to_int() == id && (m.contains("ok") || m.contains("error")) {
      return (asked, Some(e.given))
    }
  }
  (asked, None)
}

///|
/// When the answer to the run's latest call `call` given so far was given here (the clock, Replay::clock): what a
/// test times a motion the answer starts from, as the tape has it at this pace, not as the app says it. None while
/// none is given.
pub fn Replay::given_at(self : Replay, call : String) -> Double? {
  let asked : Map[Int, Bool] = Map([])
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
/// The latest step of the run's script taken again here that says its moment: when here (this clock) and when in the
/// run (its clock): what the steps after it, and the run's frames, are timed from (Replay::due_at). None before the
/// first.
pub fn Replay::step_anchor(self : Replay) -> (Double, Double)? {
  let mut last : (Double, Double)? = None
  for e in self.evs {
    if e.out && e.done && e.at >= 0.0 && e.has_wall && is_step(e.msg) {
      last = Some((e.at, e.wall))
    }
  }
  last
}

///|
/// The run's first step taken again here that says its moment: when here and when in the run (what the run's frames
/// are timed from in the strict pass). None before it.
pub fn Replay::first_step_anchor(self : Replay) -> (Double, Double)? {
  for e in self.evs {
    if e.out && e.done && e.at >= 0.0 && e.has_wall && is_step(e.msg) {
      return Some((e.at, e.wall))
    }
  }
  None
}

///|
/// When the run's display began each frame, on the run's clock (its `{"frame":…}` lines); empty: a trace recorded
/// before they were kept, its display's frames not known.
pub fn Replay::run_frames(self : Replay) -> Array[Double] {
  self.run_frames
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
/// What the run's host gave its frames as it began (`{"settings":{…}}`: mbui's @ui.trace_settings), for a replay's
/// Tester to be made by it; None where its trace does not say (Flow::start refuses it).
pub fn Replay::settings(self : Replay) -> Json? {
  self.run_settings
}

///|
/// This machine's station as the run's host said it (Tester::set_app_said: what `local_station` says); "" where
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

