// An agent's message coming out of its activity's avatar (ember apps/android chat/screens/ChatMotion.kt; web
// useEmissions), one at a time: the activity folds to its avatar (Fold), the avatar glides to where the message goes
// (Float), the message comes out of it as it is there (Spit), and the avatar glides on to where the activity now is,
// which unfolds again (Return). One way from its activity and back, no hop (the user, 2026-10-31: 「整个头像运动需要流
// 畅且符合逻辑，并且不要有突变」, then 「不要跳跃了」): each glide sets out from rest where the one before left the
// avatar and comes to rest where it goes, so it never jumps, stops dead or starts at speed. Until its turn a message
// waits out of the list. With motion reduced, each pose at once. Messages no one watches just appear: arriving while
// the page is not in front or the reader has scrolled up, and all still waiting when that happens. Only drawn: the
// message is laid out (and tapped) where it is from the frame it comes into the list; the flying avatar is a picture
// over the list.

///|
pub(all) enum Pose {
  Fold
  Float
  Spit
  Return
} derive(Eq, Show)

///|
pub fn Pose::ms(self : Pose) -> Double {
  match self {
    Fold => 170.0
    Float => 440.0
    Spit => 380.0
    Return => 320.0
  }
}

///|
/// What is left of a message's coming out once it shows in the list (it comes out as the avatar lands: Spit), to the
/// avatar home again (Return): its activity stays till then (ChatMotion.keeps), its turn's linger counted after.
pub let emit_out_ms : Double = Spit.ms() + Return.ms()

///|
/// The same agent's next message, waiting as one comes out: the avatar glides on to it from the one before, not
/// going home first (how long).
pub let emit_drop_ms : Double = 280.0

///|
/// A message's turn: its seq and agent, its pose and how far through it (`clock`, 0 to 1, said as the pose sets out,
/// from where the pose before was declared to end); `from`, on from the same agent's message before it (that
/// message's emit_places key), dropping on without going home. A row rebuilt since is found by that key, never by
/// a point left by a picture of an earlier message.
pub(all) struct Turn {
  seq : Double
  /// its message's ts: its row's key (Entry::id's `m:` and it)
  ts : String
  agent : String
  pose : Pose
  from : String?
  /// the previous landing at the handover cause, used only while `from` has no placed node
  from_at : (Double, Double)?
  clock : @motion.Way
  /// how long its clock is (ms)
  span : Double
  /// its way stretched as it goes (a Float waiting for words sent to land, emit_step): how far it was, how fast it went
  /// on and how fast it ends, over its clock (0 to 1: emit_clock); None: the clock itself
  warp : (Double, Double, Double)?
  /// the glide's length has been chosen from the endpoints available at its start; an underway glide is never retimed
  timed : Bool
}

///|
/// A chat's messages coming out of avatars.
pub(all) struct Emits {
  decided : Map[String, Bool]
  done : Map[String, Bool]
  /// waiting: seq, its message's ts (its row's key: Turn's), agent, its activity's folding (from when it began waiting)
  queue : Array[(Double, String, String, @motion.Way)]
  mut current : Turn?
  /// when each agent's last message came out of its avatar, as its poses declared it to end (not the frame that saw
  /// it end): its line's lingering counted from there (chat_play)
  ended : Map[String, Double]
  /// this message's endpoint at its Float or Spit deadline, for this seq alone: a fallback while its row is
  /// absent. Drawing never writes it. A new turn or release clears it.
  mut aimed : (Double, Double)?
  mut aimed_at : Double
  /// whether what comes in is watched (the page in front, the reader at its end), as last drawn
  mut watched : Bool
  /// the agent whose avatar the flying copy shows as (its activity's own hidden), "" none
  mut copied : String
  /// what it is said to move by (Ctx::moving): its turns, each pose's end known as it starts
  mover : @ui.Mover
  /// a message's coming in held for words sent from here on their way (emit_step): till their declared landing (-1:
  /// none)
  mut held_until : Double
  /// the newest message's seq as its list was first taken (or given whole): none to that come out of an avatar
  mut floor : Double
  /// the first row of what was sent from here not in the chat yet (the outbox's, under the messages), as last built
  /// ("" none): a message coming in comes in over it
  mut out_key : String
  /// the chat's messages' list as last taken (emit_take) and what reads its changes: each come decided as it comes
  mut taken : (@rows.TopicList, @rows.ListReader)?
  /// each message out of an avatar coming out (its seq's): its words' way in, 0 to 1 over emit_out_ms_most from the
  /// avatar landing on it (emit_out)
  out_at : Map[String, @motion.Way]
  /// how many times it changed, as a signal (Emits::changed): what reads it (a message's row, an activity's:
  /// Emits::read) is built again as it does, kept or not (mbui's kept_nodes.mbt)
  said : @signals.Signal[Int]
}

///|
/// It changed (a message come to wait, a pose on to the next, one let go, where it flies from or lands): what read it
/// is told.
pub fn Emits::changed(self : Emits) -> Unit {
  self.said.set(@signals.untracked(fn() { self.said.get() }) + 1)
}

///|
/// What is built from it reads it so (its fields read as they are): built again as it changes.
pub fn Emits::read(self : Emits) -> Unit {
  self.said.get() |> ignore
}

///|
pub let emits : Map[String, Emits] = {}

///|
pub fn emits_of(key : String) -> Emits {
  match emits.get(key) {
    Some(e) => e
    None => {
      let e = {
        decided: {},
        done: {},
        queue: [],
        current: None,
        ended: {},
        aimed: None,
        aimed_at: -1.0,
        watched: false,
        copied: "",
        mover: @ui.Mover::new(),
        held_until: -1.0,
        out_key: "",
        floor: -1.0e300,
        taken: None,
        out_at: {},
        said: @signals.signal(0),
      }
      emits[key] = e
      e
    }
  }
}

///|
pub fn seq_s(seq : Double) -> String {
  seq.to_int64().to_string()
}

///|
/// Messages seen for the first time (ChatMotion.take): an agent's, said while the chat shows (the core's `said`),
/// while its activity shows, waits its turn to come out of it. Only those come since it last took them are looked at
/// (its list's changes: rows' TopicList), a chat's all of them only the first time: a long chat holds thousands.
pub fn emit_take(c : @ui.Ctx, e : Emits, v : ChatView, showing : Map[String, Bool]) -> Unit {
  let rows = v.messages.rows
  // (the messages come since they were last taken: those of a list not taken yet all of them, once)
  let came : Array[Int] = []
  match e.taken {
    Some((was, reader)) if physical_equal(was, rows) =>
      for ch in reader.changes() {
        // (those come before it carried to where they are after it)
        let mut j = 0
        while j < came.length() {
          match @rows.index_after([ch], came[j]) {
            Some(i) => {
              came[j] = i
              j += 1
            }
            None => came.remove(j) |> ignore
          }
        }
        match ch {
          Inserted(at, n, _) =>
            for i in at..<(at + n) {
              came.push(i)
            }
          Set(at, _) => came.push(at)
          Whole(_) => {
            came.clear()
            e.floor = last_seq(v)
          }
          Removed(_, _, _) | Moved(_, _, _, _) => ()
        }
      }
    _ => {
      match e.taken {
        Some((_, reader)) => reader.let_go()
        None => ()
      }
      e.taken = Some((rows, rows.reader()))
      // (what it holds as it is first taken: in it before, none of it to come out of an avatar; nothing of it read)
      e.floor = last_seq(v)
    }
  }
  let decided = e.decided.length()
  let n = v.messages.length()
  for i in came {
    // (where one come then is now: past its end, taken out since)
    guard i < n else { continue }
    // (one not said while the chat shows comes of no avatar: decided off its row, no Message made of it, as a chat's
    // first take is of all of them, a long chat's thousands)
    let r = v.messages.row(i)
    if r.seq <= e.floor {
      continue
    }
    let k = seq_s(r.seq)
    if e.decided.contains(k) {
      continue
    }
    if !r.said {
      e.decided[k] = false
      continue
    }
    let m = r.message()
    let agent = if m.author_kind == "agent" && !m.mine && !m.system { m.by.agent } else { "" }
    let goes = e.watched && m.said && agent != "" && showing.contains(agent)
    e.decided[k] = goes
    // its agent's turn over already, no avatar to come out of: it comes in where it is, its words a glyph at a time
    // from now as they would out of one (emit_out), not grown in as a row (the user, 2026-10-31: 「为啥第二条是弹出来的」)
    if !goes && e.watched && m.said && agent != "" {
      e.out_at[k] = pose_clock(emit_out_ms_most, Some(emit_moment(c)))
    }
    if goes {
      // its agent's activity folds from now
      e.queue.push((m.seq, m.ts, agent, pose_clock(Fold.ms(), Some(emit_moment(c)))))
    }
  }
  if e.decided.length() != decided {
    e.changed()
  }
}

///|
/// Whether an agent's message comes in with no avatar to come out of, its words a glyph at a time (emit_take): its row
/// opens where it is, what it holds not grown in.
pub fn emit_words_only(e : Emits, seq : Double) -> Bool {
  e.read()
  e.decided.get(seq_s(seq)) == Some(false) && e.out_at.contains(seq_s(seq))
}

///|
/// Whether the message comes (or came) out of an avatar: it never rises in as others do.
pub fn emit_goes(e : Emits, seq : Double) -> Bool {
  e.read()
  e.decided.get(seq_s(seq)) == Some(true)
}

///|
/// Waiting its turn: not in the list yet. From when its avatar sets out for it (Float) it is, not drawn till it comes
/// out (emit_awaited): laid out where it comes in, the rows round it making room for it as the avatar goes there, and
/// the avatar going where it is, not where it is guessed to come (the user, 2026-10-29: 「你头像跳完瞬移就不是突变？」).
pub fn emit_held(e : Emits, seq : Double) -> Bool {
  e.read()
  let k = seq_s(seq)
  if e.decided.get(k) != Some(true) || e.done.contains(k) {
    return false
  }
  match e.current {
    Some(t) if t.seq == seq && t.pose != Fold => false
    _ => true
  }
}

///|
/// The messages waiting their turn (emit_held), by their seqs: those queued and the one under way, a few.
pub fn emit_held_seqs(e : Emits) -> Array[Double] {
  e.read()
  let out = []
  for q in e.queue {
    if emit_held(e, q.0) {
      out.push(q.0)
    }
  }
  match e.current {
    Some(t) if emit_held(e, t.seq) && !out.contains(t.seq) => out.push(t.seq)
    _ => ()
  }
  out
}

///|
/// In the list where it comes in, its avatar on its way to it (Float): not drawn yet.
pub fn emit_awaited(e : Emits, seq : Double) -> Bool {
  e.read()
  match e.current {
    Some(t) => t.seq == seq && t.pose == Float
    None => false
  }
}

///|
pub fn emit_emitting(e : Emits, seq : Double) -> Bool {
  e.read()
  match e.current {
    Some(t) => t.seq == seq && t.pose == Spit
    None => false
  }
}

///|
/// An agent's activity folded to its avatar: from when its first message begins waiting until its last is out.
pub fn emit_folded(e : Emits, agent : String) -> Bool {
  e.read()
  match e.current {
    Some(t) if t.agent == agent => return true
    _ => ()
  }
  e.queue.iter().any(fn(q) { q.2 == agent })
}

///|
/// Agents whose activity must stay while their messages come out.
pub fn emit_keeps(e : Emits) -> Map[String, Bool] {
  e.read()
  let out : Map[String, Bool] = {}
  for q in e.queue {
    out[q.2] = true
  }
  match e.current {
    Some(t) => out[t.agent] = true
    None => ()
  }
  out
}

///|
/// Everything waiting or coming out shows at once, where it is.
pub fn emit_release(e : Emits) -> Unit {
  if e.queue.length() > 0 || e.current is Some(_) || e.copied != "" {
    e.changed()
  }
  for q in e.queue {
    e.done[seq_s(q.0)] = true
  }
  match e.current {
    Some(t) => e.done[seq_s(t.seq)] = true
    None => ()
  }
  e.queue.clear()
  e.current = None
  e.copied = ""
  e.aimed = None
  e.aimed_at = -1.0
}

///|
pub fn emit_next(c : @ui.Ctx, e : Emits, agent : String, at? : Double) -> Unit {
  emit_next_placed(c, e, agent, "", fn(_) { None }, emit_moment(c), at?)
}

///|
fn emit_next_placed(
  c : @ui.Ctx,
  e : Emits,
  agent : String,
  key : String,
  place : (String) -> (Double, Double, Double, Double)?,
  now : Double,
  at? : Double,
) -> Unit {
  let at = at.unwrap_or(emit_moment(c))
  match e.current {
    Some(t) => e.ended[t.agent] = t.clock.end()
    None => ()
  }
  e.aimed = None
  e.aimed_at = -1.0
  if e.queue.length() == 0 {
    e.current = None
    return
  }
  let (seq, ts, who, fold) = e.queue.remove(0)
  // folded already (its folding at the end it declared, or its agent's avatar out already): on its way; else what is
  // left of its folding (how far its folding has gone, from when it began waiting), from here: from where the turn
  // before was declared to end, else from this frame
  let float = who == agent || at >= fold.end()
  let left = dmax(fold.end() - at, 0.0)
  let turn : Turn = {
    seq,
    ts,
    agent: who,
    pose: if float { Float } else { Fold },
    from: None,
    from_at: None,
    clock: if float { pose_clock(Float.ms(), Some(at)) } else { pose_clock(left, Some(at)) },
    span: if float { Float.ms() } else { left },
    warp: None,
    timed: false,
  }
  // Choose the route before publishing the new phase: the phase may itself mount its landing row.
  e.current = Some(if float { emit_start_float(key, turn, place, now) } else { turn })
  // said once as a turn sets out: it moves until its poses are played (Emits::rest_at)
  c.moving(e.mover, e as &@ui.Moving)
  e.changed()
}

///|
/// When what plays is at rest: the end of the pose under way (each pose's end known as it starts; at that frame the
/// next pose starts, its own end known then), none playing: at rest.
impl @ui.Moving for Emits with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  match self.current {
    Some(t) => dmax(t.clock.end(), self.held_until)
    None => -1.0
  }
}

///|
/// How long a glide takes from its endpoints at its cause: the distance-scaled Float, Return or same-agent drop
/// (Spit here denotes emit_drop_ms). Unknown endpoints use the pose's usual length.
fn emit_way_ms(pose : Pose, from : (Double, Double)?, to : (Double, Double)?) -> Double {
  let usual = if pose == Spit { emit_drop_ms } else { pose.ms() }
  match (from, to) {
    (Some(a), Some(b)) => {
      let far = dmax((b.0 - a.0).abs(), (b.1 - a.1).abs())
      (usual * @ui.move_ms(far) / @ui.move_ms(emit_way_points)).round()
    }
    _ => usual
  }
}

///|
/// Choose a Float's duration once, from the scene that exists at its cause. Publishing the Float can mount its
/// destination, but that later registration must not revise the duration already chosen. When the cause is being
/// caught up late, its old geometry is unavailable, so the pose keeps its usual duration.
fn emit_start_float(
  key : String,
  t : Turn,
  place : (String) -> (Double, Double, Double, Double)?,
  now : Double,
) -> Turn {
  let start = t.clock.end() - t.span
  let span = if now <= start {
    let from = match t.from {
      Some(k) => match place(k) {
        Some(r) => Some((r.0, r.1 + 3.0))
        None => t.from_at
      }
      None => place("emit-avatar/" + key + "/" + t.agent).map(fn(r) { (r.0, r.1) })
    }
    let to = place("emit-landing/" + key + "/" + seq_s(t.seq)).map(fn(r) { (r.0, r.1 + 3.0) })
    emit_way_ms(if t.from is Some(_) { Spit } else { Float }, from, to)
  } else {
    t.span
  }
  { ..t, clock: pose_clock(span, Some(start)), span, timed: true }
}

///|
/// The avatar's usual way home (points): what Return's length is of.
let emit_way_points : Double = 100.0

///|
/// How long a pose takes (Float on from the message before: only the drop).
pub fn pose_ms(pose : Pose, from : String?) -> Double {
  match pose {
    Float => if from is Some(_) { emit_drop_ms } else { Float.ms() }
    _ => pose.ms()
  }
}

///|
/// A pose's way, 0 to 1 over its length, linear: from `at` (where the pose before was declared to end), else from
/// the current input's cause.
pub fn pose_clock(ms : Double, at : Double?) -> @motion.Way {
  let a = @motion.Way::new(0.0)
  a.go(1.0, @motion.tween(ms, ease=Linear), at=at.unwrap_or(emit_moment(@ui.current())))
  a
}

///|
/// The input or declared deadline being handled, even before a frame's Ctx has
/// received its display time. A sampled picture never advances this clock.
fn emit_moment(c : @ui.Ctx) -> Double {
  @ui.tree_cause().unwrap_or(c.moment())
}

///|
/// Advance the poses at an input or their declared deadline: each to its end, then the next; the next waiting starts
/// once none plays. They take one turn among what changes the list's height (`turns`, ChatMotion.start): the first
/// waiting starts as it comes, from then, and it is over once none is left. Not watched, all of it at once.
/// `sending`: words sent from here on their way (flight.mbt): their declared landing, or -2 while their row is not laid
/// out yet (-1: none). What is sent goes first: a message comes into the list (Spit) once they have landed, as the list
/// does not follow its end while they fly; the avatar on its way then takes till their landing to come down.
/// `place` reads one placement prepared at this cause by the owner; it must not lay out per lookup. With no causal
/// source (the old frame-built entry), geometry is unknown: fixed phase durations and no saved endpoint. An old
/// drawing may still sample its measured boxes, but those past boxes cannot set a phase's handover or duration.
/// `one_phase`: publish each phase before its owner asks again after that change is told. Rows unhidden by Float
/// must exist before the next handover asks where they are, even when several phases are already due on return.
pub fn emit_step(
  c : @ui.Ctx,
  key : String,
  e : Emits,
  agents : Array[String],
  turns : Turns,
  sending : Double,
  place? : (String) -> (Double, Double, Double, Double)? = fn(_) { None },
  one_phase? : Bool = false,
  at? : Double,
) -> Unit {
  // (what of it is read as it is built, as it was: what reads it told where it changed, Emits::changed)
  let was_shown = (e.current, e.copied, e.held_until, e.done.length(), e.queue.length())
  // the words of what came out all in: drawn as laid out from here, what showed them built again (emit_out)
  let now = at.unwrap_or(emit_moment(c))
  let all_in = e.out_at.iter().filter(fn(o) { now >= o.1.end() }).map(fn(o) { o.0 }).collect()
  for k in all_in {
    e.out_at.remove(k)
  }
  if all_in.length() > 0 {
    e.changed()
  }
  // (and the frame their last comes in at built, they let go then: as their rows ask, emit_out)
  for _, way in e.out_at {
    c.wake_in(dmax(way.end() - now, 0.0))
  }
  if !e.watched || @ui.reduced_motion() {
    emit_release(e)
    if turns.emits_held() {
      turns.over(c, Emits, turns.moment(c))
    }
    return
  }
  let starting = e.current is None
  if starting {
    if e.queue.length() == 0 {
      return
    }
    if !turns.emitting() {
      turns.emits_at(c, now)
    }
    emit_next_placed(c, e, "", key, place, now, at=turns.started_at(emits_turn))
  }
  // a pose's end reached: the next pose, from its own beginning in this frame
  let was = e.current
  let mut steps = 0
  let most = if one_phase { if starting { 0 } else { 1 } } else { 6 }
  while steps < most {
    steps = steps + 1
    // (none left: still on to say no copy flies, its activity's avatar back)
    let t = match e.current {
      Some(t) => t
      None => break
    }
    // the avatar on its way while words sent from here land after it would: its way the rest of it until they land,
    // so it comes down as they do (not there before them, waiting)
    let t = match t.pose {
      Float if sending >= 0.0 && sending > t.clock.end() && sending != e.held_until && now < t.clock.end() => {
        // (its clock is linear: how far it is says when now is on it) going on from where it is at the speed it has,
        // to come down at its own end speed when they land: no step in its speed (Turn's warp)
        let u = emit_clock_at(t, now)
        let rate = turn_rate(t, now)
        let long = sending - now
        let way = pose_clock(long, Some(now))
        let most = 3.0 * (1.0 - u)
        let end_rate = 1.0 / t.span
        e.held_until = sending
        let warp = Some((u, dmin(rate * long, most), dmin(end_rate * long, most)))
        let t = { ..t, clock: way, span: long, warp }
        e.current = Some(t)
        c.moving(e.mover, e as &@ui.Moving)
        t
      }
      _ => t
    }
    // (a pose goes on till the end it declared as it set out)
    if now < t.clock.end() {
      break
    }
    // the next from where this one was declared to end, whichever frame sees it
    let at = t.clock.end()
    match t.pose {
      Fold => {
        let next = { ..t, pose: Float, clock: pose_clock(Float.ms(), Some(at)), span: Float.ms(), warp: None, timed: false }
        e.current = Some(emit_start_float(key, next, place, now))
      }
      Float => {
        // (held till words sent from here land, as their way declared: built again then, their flight's end read by
        // nothing)
        if sending == -2.0 || sending > at {
          if sending > e.held_until {
            e.held_until = sending
            c.moving(e.mover, e as &@ui.Moving)
          }
          if sending >= 0.0 {
            c.wake_in(dmax(sending - now, 0.0))
          }
          break
        }
        let at = dmax(at, e.held_until)
        e.held_until = -1.0
        // The same endpoint selection as the picture, including its fallback if the row is absent. This cause
        // keeps it for this seq; a missing endpoint never retains another message's point.
        e.aimed = emit_landing_by(key, e, t, agents, place)
        e.aimed_at = t.seq
        e.out_at[seq_s(t.seq)] = pose_clock(emit_out_ms_most, Some(at))
        let clock = pose_clock(Spit.ms(), Some(at))
        e.current = Some({ ..t, pose: Spit, from: None, from_at: None, clock, span: Spit.ms(), warp: None, timed: true })
      }
      Spit =>
        match e.queue.get(0) {
          // the same agent's next message is waiting: the avatar drops on to it from here, not going home to hop
          Some(next) if next.2 == t.agent => {
            let from_at = emit_landing_by(key, e, t, agents, place)
            e.queue.remove(0) |> ignore
            e.done[seq_s(t.seq)] = true
            let next_turn : Turn = {
              seq: next.0,
              ts: next.1,
              agent: next.2,
              pose: Float,
              from: Some("emit-landing/" + key + "/" + seq_s(t.seq)),
              from_at,
              clock: pose_clock(emit_drop_ms, Some(at)),
              span: emit_drop_ms,
              warp: None,
              timed: false,
            }
            e.current = Some(emit_start_float(key, next_turn, place, now))
            e.aimed = None
            e.aimed_at = -1.0
          }
          _ => {
            // Both ends belong to this phase's cause, not to whichever pictures happened to sample Spit.
            let landed = emit_landing_by(key, e, t, agents, place)
            let home = place("emit-avatar/" + key + "/" + t.agent).map(fn(r) { (r.0, r.1) })
            let span = emit_way_ms(Return, landed, home)
            e.aimed = landed
            e.aimed_at = t.seq
            e.current = Some({ ..t, pose: Return, clock: pose_clock(span, Some(at)), span, warp: None, timed: true })
          }
        }
      Return => {
        e.done[seq_s(t.seq)] = true
        emit_next_placed(c, e, t.agent, key, place, now, at~)
        // none left: their turn is over where this one was declared to end
        if e.current is None {
          turns.over(c, Emits, at)
        }
      }
    }
  }
  e.copied = match e.current {
    Some(t) if t.pose != Fold => t.agent
    _ => ""
  }
  // a pose ended here: what plays now says so (its end known as it starts)
  match (was, e.current) {
    (Some(a), Some(b)) if a.pose != b.pose || a.seq != b.seq => c.moving(e.mover, e as &@ui.Moving)
    _ => ()
  }
  let (current, copied, held, done, queue) = was_shown
  if !physical_equal(current, e.current) ||
    copied != e.copied ||
    held != e.held_until ||
    done != e.done.length() ||
    queue != e.queue.length() {
    e.changed()
  }
}

///|
/// How far through its pose, 0 to 1: its clock, or (stretched as it went: Turn's warp) a cubic from where it was at
/// the speed it had to its end at the speed it ends at.
pub fn emit_clock(c : @ui.Ctx, t : Turn) -> Double {
  ignore(c)
  let s = t.clock.get()
  match t.warp {
    Some((u0, m0, m1)) => hermite(u0, m0, 1.0, m1, s)
    None => s
  }
}

///|
/// A flight's linear share at its exact picture or cause moment. The pose's Way owns its deadline; unlike a
/// general Way's whole-ms motion sample, the flight's geometry and its interrupted velocity use fractional ms.
fn turn_share_at(t : Turn, at : Double) -> Double {
  let start = t.clock.starts_at()
  if t.span <= 0.0 || start < 0.0 {
    return 1.0
  }
  dmax(0.0, dmin(1.0, (at - start) / t.span))
}

///|
/// Where a flight is at its picture or change's cause, including a stretch already said of it.
fn emit_clock_at(t : Turn, at : Double) -> Double {
  let s = turn_share_at(t, at)
  match t.warp {
    Some((u0, m0, m1)) => hermite(u0, m0, 1.0, m1, s)
    None => s
  }
}

///|
fn turn_rate(t : Turn, at : Double) -> Double {
  match t.warp {
    Some((u0, m0, m1)) => hermite_slope(u0, m0, 1.0, m1, turn_share_at(t, at)) / t.span
    None => 1.0 / t.span
  }
}

///|
/// The cubic from `p0` going at `m0` to `p1` going at `m1`, at `s` (0 to 1; speeds over the whole of it).
fn hermite(p0 : Double, m0 : Double, p1 : Double, m1 : Double, s : Double) -> Double {
  let s2 = s * s
  let s3 = s2 * s
  (2.0 * s3 - 3.0 * s2 + 1.0) * p0 +
  (s3 - 2.0 * s2 + s) * m0 +
  (-2.0 * s3 + 3.0 * s2) * p1 +
  (s3 - s2) * m1
}

///|
/// Its speed at `s` (over the whole of it).
fn hermite_slope(p0 : Double, m0 : Double, p1 : Double, m1 : Double, s : Double) -> Double {
  let s2 = s * s
  (6.0 * s2 - 6.0 * s) * p0 +
  (3.0 * s2 - 4.0 * s + 1.0) * m0 +
  (-6.0 * s2 + 6.0 * s) * p1 +
  (3.0 * s2 - 2.0 * s) * m1
}

///|
/// The route's landing from one set of places: a known row, this seq's causal fallback, then the first activity or
/// outbox. Both the phase handover and its pictures use this choice, including when no landing row can be found.
fn emit_landing_by(
  key : String,
  e : Emits,
  t : Turn,
  agents : Array[String],
  place : (String) -> (Double, Double, Double, Double)?,
) -> (Double, Double)? {
  // before the message is in the list: where its avatar will be, the first activity's place (the message comes in
  // there, the activities move down), or over what was sent from here not in the chat yet (the outbox's rows, under
  // the messages: it comes in over them), 3 down its row as a message's avatar sits; as it comes in, where it was
  // aimed
  match place("emit-landing/" + key + "/" + seq_s(t.seq)) {
    Some(r) => return Some((r.0, r.1 + 3.0))
    None => ()
  }
  match e.aimed {
    Some(a) if e.aimed_at == t.seq && t.pose != Float => return Some(a)
    _ => ()
  }
  // (the activities' avatars sit 3 down their rows, as a message's does)
  let mut first : (Double, Double)? = None
  for a in agents {
    match place("emit-avatar/" + key + "/" + a) {
      Some(r) =>
        match first {
          Some(f) if f.1 <= r.1 => ()
          _ => first = Some((r.0, r.1))
        }
      None => ()
    }
  }
  if e.out_key != "" {
    match (place("emit-out/" + key + "/" + e.out_key), place("emit-avatar/" + key + "/" + t.agent)) {
      (Some(r), Some(avatar)) => {
        let y = r.1 + 3.0
        match first {
          Some(f) if f.1 <= y => ()
          _ => first = Some((avatar.0, y))
        }
      }
      _ => ()
    }
  }
  first
}

///|
/// Where the flying avatar's 18 face is (its top left, in the window) and how it is scaled about its middle, or None
/// when none flies (ChatMotion.flight): between the places read in this picture. This samples the declared phase;
/// it never records a landing, starts another phase or changes its duration.
pub fn emit_flight_by(
  key : String,
  e : Emits,
  agents : Array[String],
  place : (String) -> (Double, Double, Double, Double)?,
  at : Double,
) -> (Double, Double, Double, Double)? {
  e.read()
  let t = match e.current {
    Some(t) if t.pose != Fold => t
    _ => return None
  }
  let avatar = match place("emit-avatar/" + key + "/" + t.agent) {
    Some(r) => (r.0, r.1)
    None => return None
  }
  guard emit_landing_by(key, e, t, agents, place) is Some(landing) else { return None }
  let u = emit_clock_at(t, at)
  match t.pose {
    Float => {
      // from its activity's avatar, or on from the message before it (where it was)
      let start = match t.from {
        Some(k) => {
          // The previous row may have left the window. Its handover point belongs to this route, not to an
          // earlier agent's sample. With neither endpoint, there is no copy; never restart at the activity.
          match place(k) {
            Some(r) => (r.0, r.1 + 3.0)
            None => match t.from_at { Some(p) => p; None => return None }
          }
        }
        None => avatar
      }
      // The answer opens above the activity. That part of the trip is already moved by the list's common
      // height curve; carry it whole, and glide only the remaining distance (other activities between them).
      // Easing toward the moving landing again made an empty room appear before its avatar followed it.
      let opened = match t.from {
        None => emit_rooms.get("emit-landing/" + key + "/" + seq_s(t.seq)).bind(fn(f) { f() }).unwrap_or(0.0)
        Some(_) => 0.0
      }
      let y = landing.1 + hermite(start.1 - landing.1 - opened, 0.0, 0.0, 0.0, u)
      Some((hermite(start.0, 0.0, landing.0, 0.0, u), y, 1.0, 1.0))
    }
    Spit => Some((landing.0, landing.1, 1.0, 1.0))
    _ =>
      // home from where it let the message out
      Some((hermite(landing.0, 0.0, avatar.0, 0.0, u), hermite(landing.1, 0.0, avatar.1, 0.0, u), 1.0, 1.0))
  }
}

///|
/// The same flight sampled against the placed endpoints by an old caller or a check. This observes placement;
/// it does not lay out, publish geometry or advance phases. The retained flyer passes the picture's Laid directly.
pub fn emit_flight(c : @ui.Ctx, key : String, e : Emits, agents : Array[String], at? : Double) -> (Double, Double, Double, Double)? {
  emit_flight_by(key, e, agents, fn(k) { emit_place(c, k) }, at.unwrap_or(emit_moment(c)))
}

///|
/// A message coming out of its avatar as it lands: its head (name, time) sliding out of the avatar beside it, its
/// words a glyph at a time, in the order they read but each a little before or after its turn (the user, 2026-10-31:
/// 「有没有那种每个字独立动的动效」「整体按顺序，局部扰动」), each fading in as it rises into place, a little more or
/// less than the next. Its words never scaled.
pub fn emit_out(c : @ui.Ctx, col : Int, head : Int, e : Emits, seq : Double) -> Unit {
  e.read()
  if emit_awaited(e, seq) {
    c.look(col, @ui.look(alpha=0.0))
    return
  }
  let way = match e.out_at.get(seq_s(seq)) {
    Some(way) => way
    None => return
  }
  // (built again as they are all in: emit_step lets them go then)
  c.wake_in(dmax(way.end() - c.moment(), 0.0))
  // (how far on from its coming out, read as it is painted)
  let since = fn() { way.get() * emit_out_ms_most }
  c.look_by(head, fn() {
    let k = @ui.Ease::Out.at(dmin(since() / emit_head_ms, 1.0))
    @ui.look(alpha=k, dx=-emit_out_slide * (1.0 - k))
  })
  // (what is not words, a list's mark, a quote's bar, a code block's ground, comes with the glyph after it: the first
  // of its line, Ctx::glyphs_by)
  let salt = seq.to_int64().to_int()
  let key = "emit-col/" + seq_s(seq)
  c.glyphs_by(col, fn(at) {
    match @motion.measured_rect(c, key) {
      Some(r) => glyph_out(since(), at, r, salt)
      None => { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
    }
  })
}

///|
/// A glyph of a message (`at`; `col`: the message's words' box in the window, `salt`: which message), `ms` after it
/// came out. What shows of the message is read in order, a line at a time and along each line (each line
/// emit_line_ms, less where more lines show: all of them within emit_screen_ms), each glyph a little before or after
/// its turn (up to half of emit_glyph_jitter); then over emit_glyph_ms faded in as it rises into place. What is out
/// of view is there at once (the user, 2026-10-31: 「应该屏幕外面不一样，在屏幕里面你不一样能他妈行吗」, then
/// 「让它出快点」). Its size as it is (「单字不用尺寸动效吧，用淡入」).
fn glyph_out(ms : Double, at : @ui.GlyphAt, col : (Double, Double, Double, Double), salt : Int) -> @ui.GlyphLook {
  let still : @ui.GlyphLook = { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
  let (x0, y0, w, h) = col
  // what shows of it, in lines; out of it, there at once
  let shown_top = dmax(at.top, y0)
  let shown_foot = dmin(at.foot, y0 + h)
  if at.y + at.h <= shown_top || at.y >= shown_foot {
    return still
  }
  let lines = dmax((shown_foot - shown_top) / emit_line_points, 1.0)
  let line_ms = dmin(emit_line_ms, emit_screen_ms / lines)
  // how far into what shows it is read: its line, and along it
  let read = dmax(at.y - shown_top, 0.0) / emit_line_points +
    (if w > 0.0 { dmax(dmin((at.x - x0) / w, 1.0), 0.0) } else { 0.0 })
  glyph_in(ms, read * line_ms, at.index, salt)
}

///|
/// One glyph arriving, shared by an agent's message and its activity. `turn` is when its place in reading order
/// would come; its own little variation, fade and rise are the same in either place.
pub fn glyph_in(ms : Double, turn : Double, index : Int, salt : Int) -> @ui.GlyphLook {
  let still : @ui.GlyphLook = { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
  let (j0, j1) = (glyph_noise(index, salt), glyph_noise(index, salt + 7919))
  let start = dmax(turn + (j0 - 0.5) * emit_glyph_jitter, 0.0)
  let p = (ms - start) / emit_glyph_ms
  if p <= 0.0 {
    return { alpha: 0.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
  }
  if p >= 1.0 {
    return still
  }
  let rise = emit_glyph_rise * (0.7 + 0.6 * j1)
  { alpha: @ui.Ease::Out.at(dmin(p / 0.7, 1.0)), dx: 0.0, dy: rise * (1.0 - @ui.Ease::Out.at(p)), scale: 1.0, sx: 1.0 }
}

///|
/// One glyph giving way to its successor in the next activity. It fades away before its successor rises and fades in,
/// so the two do not overlap. `turn` is a gentle reading-order bias; each place varies its timing and its rise.
pub fn glyph_change(ms : Double, turn : Double, index : Int, salt : Int, incoming : Bool) -> @ui.GlyphLook {
  let start = turn * 0.25 + glyph_change_line_ms * glyph_noise(index, salt) * 0.75
  let duration = emit_glyph_ms * (0.8 + 0.4 * glyph_noise(index, salt + 7919))
  let p = dmax(dmin((ms - start) / duration, 1.0), 0.0)
  let rise = emit_glyph_rise * (0.7 + 0.6 * glyph_noise(index, salt + 15838))
  if incoming {
    let q = @ui.Ease::Out.at(dmax(p * 2.0 - 1.0, 0.0))
    { alpha: q, dx: 0.0, dy: rise * (1.0 - q), scale: 1.0, sx: 1.0 }
  } else {
    let q = @ui.Ease::Leave.at(dmin(p * 2.0, 1.0))
    { alpha: 1.0 - q, dx: 0.0, dy: -rise * 0.25 * q, scale: 1.0, sx: 1.0 }
  }
}

///|
/// A number from 0 to 1 for glyph `i` of message `salt`, the same each time (a hash: no chance in it).
fn glyph_noise(i : Int, salt : Int) -> Double {
  let mut h = (i * 374761393 + salt * 668265263).to_uint()
  h = (h ^ (h >> 13)) * 1274126177U
  h = h ^ (h >> 16)
  (h & 0xFFFFU).reinterpret_as_int().to_double() / 65535.0
}

///|
/// A message's words coming out: how long a line's reading takes, the most all that shows of it takes (its lines' share
/// then shorter), a line's height for that (points), how far before or after its turn each glyph may be, how long each
/// takes, and how far each rises.
let emit_line_ms : Double = 120.0

///|
/// One visible line's reading and the last glyph's arrival, including its variation.
pub let glyph_line_ms : Double = emit_line_ms

///|
pub let glyph_line_in_ms : Double = emit_line_ms + emit_glyph_jitter / 2.0 + emit_glyph_ms

///|
/// The span over which the glyphs in an activity begin changing.
pub let glyph_change_line_ms : Double = emit_line_ms

///|
/// The last visible glyph's change, including the largest variation in its speed.
pub let glyph_change_in_ms : Double = glyph_change_line_ms + emit_glyph_ms * 1.2

///|
let emit_screen_ms : Double = 500.0

///|
let emit_line_points : Double = 22.0

///|
let emit_glyph_jitter : Double = 50.0

///|
let emit_glyph_ms : Double = 220.0

///|
let emit_glyph_rise : Double = 6.0

///|
/// The head's sliding out (ms); how long it all takes at most.
let emit_head_ms : Double = 260.0

///|
let emit_out_ms_most : Double = emit_screen_ms + emit_line_ms + emit_glyph_jitter / 2.0 + emit_glyph_ms

///|
/// How far a message's head slides out of the avatar (points).
let emit_out_slide : Double = 10.0

///|
/// Where what a message flies between is laid out, by its key ("emit-avatar/…", "emit-landing/…", "emit-out/…"), for
/// the nodes of a list in the window's tree (what they lay out read as they are, each while it lives); an old view's
/// measured as it is drawn (@motion.measure).
/// A row mounting or leaving also tells readers: its flying copy must stop using a disposed node, and a new node
/// registered under the same key supplies the endpoint from then on.
pub let emit_places : @sf.LiveMap[String, EmitAt] = @sf.LiveMap::new()

///|
/// The retained endpoint, owned by its node; a row rebuilt under the same message key replaces this handle.
pub(all) struct EmitAt {
  node : @view.View
  dy : Double
}

///|
/// This picture's endpoint, including the list's drawing offsets. No signal is published from this read.
pub fn emit_place_drawn(laid : @view.Laid, key : String) -> (Double, Double, Double, Double)? {
  emit_places.get(key).bind(fn(p) { laid.drawn(p.node).map(fn(r) { (r.0, r.1 + p.dy, r.2, r.3) }) })
}

///|
/// A phase's endpoint from the owner's one placement at this cause. The caller prepares that placement once before
/// reading any key. Look up the registration afterwards: layout may have replaced or released the row. The lookup
/// itself never samples a clock or lays out; absent, hidden, unplaced or foreign nodes have no causal point.
pub fn emit_place_now(owner : @view.View, key : String) -> (Double, Double, Double, Double)? {
  @signals.untracked(fn() {
    guard owner.alive() && emit_places.get(key) is Some(now) && physical_equal(now.node.tree, owner.tree) &&
      now.node.alive() && !now.node.shown_nowhere() else { return None }
    let r = now.node.placed_window_now(drawing=true)
    if r.2 > 0.0 && r.3 > 0.0 { Some((r.0, r.1 + now.dy, r.2, r.3)) } else { None }
  })
}

///|
/// The list room opening under a landing, in the same frame as emit_places. It is already a displacement of the
/// avatar's destination, and must not be eased again. Registered and released with the node that owns the place.
pub let emit_rooms : @sf.LiveMap[String, () -> Double?] = @sf.LiveMap::new()

///|
/// Where the node or old view kept as `key` is laid out, in the window: x, y, w, h (None while none is).
pub fn emit_place(c : @ui.Ctx, key : String) -> (Double, Double, Double, Double)? {
  match emit_places.get(key) {
    Some(p) => {
      guard p.node.alive() && !p.node.shown_nowhere() else { return None }
      let r = p.node.placed_window_now(drawing=true)
      if r.2 > 0.0 && r.3 > 0.0 { Some((r.0, r.1 + p.dy, r.2, r.3)) } else { None }
    }
    None => @motion.measured_rect(c, key)
  }
}

///|
/// How far through its head's sliding out of the avatar a message coming out is at moment `at` (emit_out's: 0 to 1,
/// eased), None while it is not coming out; 0 while it waits in the list for its avatar (emit_awaited). `at` read
/// only while it comes out.
pub fn emit_head_at(e : Emits, seq : Double, at : () -> Double) -> Double? {
  e.read()
  if emit_awaited(e, seq) {
    return Some(0.0)
  }
  match e.out_at.get(seq_s(seq)) {
    Some(way) => {
      let since = dmax(at() - way.starts_at(), 0.0)
      Some(@ui.Ease::Out.at(dmin(since / emit_head_ms, 1.0)))
    }
    None => None
  }
}

///|
/// How far a message's head slides out of the avatar (points), all of it at 0 (emit_head_at).
pub let emit_head_slide : Double = emit_out_slide

///|
/// When a message coming out of its avatar began coming out (emit_out's), while it does; None else. What draws its
/// glyphs by the time (View::glyphs_by) works them out from it (emit_glyph_out).
pub fn emit_out_from(e : Emits, seq : Double) -> Double? {
  e.read()
  e.out_at.get(seq_s(seq)).map(fn(way) { way.starts_at() })
}

///|
/// A glyph `g` of a message coming out of its avatar (emit_out's glyph_out, for a node of the window's tree), at
/// moment `at`, `from` when it began coming out (emit_out_from), its words' box `col` in the window, `seq` which message.
pub fn emit_glyph_out(
  seq : Double,
  from : Double,
  at : Double,
  g : @view.GlyphAt,
  col : (Double, Double, Double, Double),
) -> @view.GlyphLook {
  let l = glyph_out(dmax(at - from, 0.0), { index: g.index, x: g.x, y: g.y, h: g.h, top: g.top, foot: g.foot }, col, seq.to_int64().to_int())
  { alpha: l.alpha, dx: l.dx, dy: l.dy, scale: l.scale, sx: l.sx }
}

///|
/// The newest of chat `v`'s messages' seq, the least there is where it has none (its messages kept in seq's order).
fn last_seq(v : ChatView) -> Double {
  let n = v.messages.length()
  if n > 0 { v.messages.seq_at(n - 1) } else { -1.0e300 }
}

///|
/// When agent `agent`'s last message came out of its avatar, as declared (-1: none yet).
pub fn emit_ended(e : Emits, agent : String) -> Double {
  e.ended.get(agent).unwrap_or(-1.0)
}
