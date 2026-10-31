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
/// from where the pose before was declared to end); `from`, on from the same agent's message before it (where its
/// avatar is), dropping on without going home.
pub(all) struct Turn {
  seq : Double
  agent : String
  pose : Pose
  from : (Double, Double)?
  clock : @motion.Anim
  /// how long its clock is (ms)
  span : Double
  /// its way stretched as it goes (a Float waiting for words sent to land, emit_step): how far it was, how fast it went
  /// on and how fast it ends, over its clock (0 to 1: emit_clock); None: the clock itself
  warp : (Double, Double, Double)?
}

///|
/// A chat's messages coming out of avatars.
pub(all) struct Emits {
  decided : Map[String, Bool]
  done : Map[String, Bool]
  /// waiting: seq, agent, its activity's folding (from when it began waiting)
  queue : Array[(Double, String, @motion.Anim)]
  mut current : Turn?
  /// where the flying avatar was last sent, for which message; where it last let one out
  mut aimed : (Double, Double)?
  mut aimed_at : Double
  mut landed : (Double, Double)?
  /// where the flying avatar's activity's avatar was last drawn: where it goes home to (Return)
  mut home : (Double, Double)?
  /// whether what comes in is watched (the page in front, the reader at its end), as last drawn
  mut watched : Bool
  /// the agent whose avatar the flying copy shows as (its activity's own hidden), "" none
  mut copied : String
  /// the flight as last worked out: how far through its pose, from where (y) to where (y), for the motion log
  mut trace : (Double, Double, Double)
  /// what it is said to move by (Ctx::moving): its turns, each pose's end known as it starts
  mover : @ui.Mover
  /// a message's coming in held for words sent from here on their way (emit_step): till their declared landing (-1:
  /// none)
  mut held_until : Double
  /// the first row of what was sent from here not in the chat yet (the outbox's, under the messages), as last built
  /// ("" none): a message coming in comes in over it
  mut out_key : String
  /// the chat's messages as last taken (emit_take), each decided: the same version again holds none new
  mut taken : Array[Message]
  /// each message out of an avatar coming out (its seq's): its words' way in, 0 to 1 over emit_out_ms_most from the
  /// avatar landing on it (emit_out)
  out_at : Map[String, @motion.Anim]
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
        aimed: None,
        aimed_at: -1.0,
        landed: None,
        home: None,
        watched: false,
        copied: "",
        trace: (0.0, 0.0, 0.0),
        mover: @ui.Mover::new(),
        held_until: -1.0,
        out_key: "",
        taken: [],
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
/// while its activity shows, waits its turn to come out of it. Looked through once for each version of the chat
/// (view_of_chat), not each frame: a long chat holds thousands.
pub fn emit_take(c : @ui.Ctx, e : Emits, v : ChatView, showing : Map[String, Bool]) -> Unit {
  if physical_equal(v.messages, e.taken) {
    return
  }
  e.taken = v.messages
  let decided = e.decided.length()
  for m in v.messages {
    let k = seq_s(m.seq)
    if e.decided.contains(k) {
      continue
    }
    let agent = if m.author_kind == "agent" && !m.mine && !m.system { m.by.agent } else { "" }
    let goes = e.watched && m.said && agent != "" && showing.contains(agent)
    e.decided[k] = goes
    // its agent's turn over already, no avatar to come out of: it comes in where it is, its words a glyph at a time
    // from now as they would out of one (emit_out), not grown in as a row (the user, 2026-10-31: 「为啥第二条是弹出来的」)
    if !goes && e.watched && m.said && agent != "" {
      e.out_at[k] = pose_clock(emit_out_ms_most, Some(c.moment()))
    }
    if goes {
      // its agent's activity folds from now
      e.queue.push((m.seq, agent, pose_clock(Fold.ms(), None)))
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
  e.queue.iter().any(fn(q) { q.1 == agent })
}

///|
/// Agents whose activity must stay while their messages come out.
pub fn emit_keeps(e : Emits) -> Map[String, Bool] {
  e.read()
  let out : Map[String, Bool] = {}
  for q in e.queue {
    out[q.1] = true
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
}

///|
pub fn emit_next(c : @ui.Ctx, e : Emits, agent : String, at? : Double) -> Unit {
  e.changed()
  if e.queue.length() == 0 {
    e.current = None
    return
  }
  let (seq, who, fold) = e.queue.remove(0)
  // folded already (its folding at the end it declared, or its agent's avatar out already): on its way; else what is
  // left of its folding (how far its folding has gone, from when it began waiting), from here: from where the turn
  // before was declared to end, else from this frame
  let float = who == agent || fold.over()
  let left = Fold.ms() * (1.0 - fold.get())
  e.current = Some({
    seq,
    agent: who,
    pose: if float { Float } else { Fold },
    from: None,
    clock: if float { pose_clock(Float.ms(), at) } else { pose_clock(left, at) },
    span: if float { Float.ms() } else { left },
    warp: None,
  })
  // said once as a turn sets out: it moves until its poses are played (Emits::rest_at)
  c.moving(e.mover, e as &@ui.Moving)
}

///|
/// When what plays is at rest: the end of the pose under way (each pose's end known as it starts; at that frame the
/// next pose starts, its own end known then), none playing: at rest.
impl @ui.Moving for Emits with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  match self.current {
    Some(t) => dmax(t.clock.ends(), self.held_until)
    None => -1.0
  }
}

///|
/// How long the avatar takes home (Return) from where it let the message out to its activity's avatar: as Return's
/// over its usual way (emit_way_points, a row or two), longer or shorter as a Move of it is (@ui.move_ms: the further the
/// longer, not in proportion). The hop (Float) is a hop's, over its own height above the higher of its ends; the drop
/// and the folding, a row's.
fn return_ms(e : Emits) -> Double {
  match (e.landed, e.home) {
    (Some(l), Some(h)) => {
      let far = dmax((h.0 - l.0).abs(), (h.1 - l.1).abs())
      (Return.ms() * @ui.move_ms(far) / @ui.move_ms(emit_way_points)).round()
    }
    _ => Return.ms()
  }
}

///|
/// The avatar's usual way home (points): what Return's length is of.
let emit_way_points : Double = 100.0

///|
/// How long a pose takes (Float on from the message before: only the drop).
pub fn pose_ms(pose : Pose, from : (Double, Double)?) -> Double {
  match pose {
    Float => if from is Some(_) { emit_drop_ms } else { Float.ms() }
    _ => pose.ms()
  }
}

///|
/// A pose's way, 0 to 1 over its length, linear: from `at` (where the pose before was declared to end), else from
/// this frame.
pub fn pose_clock(ms : Double, at : Double?) -> @motion.Anim {
  let a = @motion.Anim::new(0.0)
  a.animate(1.0, @motion.tween(ms, ease=Linear), start_at?=at)
  a
}

///|
/// The poses played on, a frame at a time (ChatMotion.play): each to its end, then the next; the next waiting starts
/// once none plays. They take one turn among what changes the list's height (`turns`, ChatMotion.start): the first
/// waiting starts as it comes, from then, and it is over once none is left. Not watched, all of it at once.
/// `sending`: words sent from here on their way (flight.mbt): their declared landing, or -2 while their row is not laid
/// out yet (-1: none). What is sent goes first: a message comes into the list (Spit) once they have landed, as the list
/// does not follow its end while they fly; the avatar on its way then takes till their landing to come down.
pub fn emit_step(c : @ui.Ctx, e : Emits, turns : Turns, sending : Double) -> Unit {
  // (what of it is read as it is built, as it was: what reads it told where it changed, Emits::changed)
  let was_shown = (e.current, e.copied, e.held_until, e.done.length(), e.queue.length())
  // the words of what came out all in: drawn as laid out from here, what showed them built again (emit_out)
  let now = c.moment()
  let all_in = e.out_at.iter().filter(fn(o) { now >= o.1.ends() }).map(fn(o) { o.0 }).collect()
  for k in all_in {
    e.out_at.remove(k)
  }
  if all_in.length() > 0 {
    e.changed()
  }
  if !e.watched || @ui.reduced_motion() {
    emit_release(e)
    turns.over(c, Emits, turns.moment(c))
    return
  }
  if e.current is None {
    if e.queue.length() == 0 {
      return
    }
    if !turns.emitting() {
      turns.emits(c)
      return
    }
    emit_next(c, e, "", at=turns.started_at(emits_turn))
  }
  // a pose's end reached: the next pose, from its own beginning in this frame
  let was = e.current
  let mut steps = 0
  while steps < 6 {
    steps = steps + 1
    // (none left: still on to say no copy flies, its activity's avatar back)
    let t = match e.current {
      Some(t) => t
      None => break
    }
    // the avatar on its way while words sent from here land after it would: its way the rest of it until they land,
    // so it comes down as they do (not there before them, waiting)
    let t = match t.pose {
      Float if sending >= 0.0 && sending > t.clock.ends() && sending != e.held_until && !t.clock.over() => {
        // (its clock is linear: how far it is says when now is on it) going on from where it is at the speed it has,
        // to come down at its own end speed when they land: no step in its speed (Turn's warp)
        let s = t.clock.get()
        let now = t.clock.ends() - (1.0 - s) * t.span
        let u = emit_clock(c, t)
        let rate = turn_rate(t)
        let way = @motion.Anim::new(0.0)
        let long = sending - now
        way.animate(1.0, @motion.tween(long, ease=Linear), start_at=now)
        let most = 3.0 * (1.0 - u)
        let end_rate = 1.0 / pose_ms(Float, t.from)
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
    if !t.clock.over() {
      break
    }
    // the next from where this one was declared to end, whichever frame sees it
    let at = t.clock.ends()
    match t.pose {
      Fold =>
        e.current = Some({ ..t, pose: Float, clock: pose_clock(Float.ms(), Some(at)), span: Float.ms(), warp: None })
      Float => {
        if sending != -1.0 {
          if sending > e.held_until {
            e.held_until = sending
            c.moving(e.mover, e as &@ui.Moving)
          }
          break
        }
        let at = dmax(at, e.held_until)
        e.held_until = -1.0
        e.out_at[seq_s(t.seq)] = pose_clock(emit_out_ms_most, Some(at))
        let clock = pose_clock(Spit.ms(), Some(at))
        e.current = Some({ ..t, pose: Spit, from: None, clock, span: Spit.ms(), warp: None })
      }
      Spit =>
        match (e.queue.get(0), e.landed) {
          // the same agent's next message is waiting: the avatar drops on to it from here, not going home to hop
          (Some(next), Some(l)) if next.1 == t.agent => {
            e.queue.remove(0) |> ignore
            e.done[seq_s(t.seq)] = true
            e.current = Some({
              seq: next.0,
              agent: next.1,
              pose: Float,
              from: Some(l),
              clock: pose_clock(emit_drop_ms, Some(at)),
              span: emit_drop_ms,
              warp: None,
            })
          }
          _ => {
            let span = return_ms(e)
            e.current = Some({ ..t, pose: Return, clock: pose_clock(span, Some(at)), span, warp: None })
          }
        }
      Return => {
        e.done[seq_s(t.seq)] = true
        emit_next(c, e, t.agent, at~)
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
/// How fast it goes through its pose now (a share a ms).
fn turn_rate(t : Turn) -> Double {
  match t.warp {
    Some((u0, m0, m1)) => hermite_slope(u0, m0, 1.0, m1, t.clock.get()) / t.span
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
/// Where the flying avatar's 18 face is (its top left, in the window) and how it is scaled about its middle, or None
/// when none flies (ChatMotion.flight): between where it set out and where it is going, both as last laid out.
pub fn emit_flight(c : @ui.Ctx, key : String, e : Emits, agents : Array[String]) -> (Double, Double, Double, Double)? {
  e.read()
  let t = match e.current {
    Some(t) if t.pose != Fold => t
    _ => return None
  }
  let avatar = match @motion.measured_rect(c, "emit-avatar/" + key + "/" + t.agent) {
    Some(r) => (r.0, r.1)
    None => return None
  }
  e.home = Some(avatar)
  // before the message is in the list: where its avatar will be, the first activity's place (the message comes in
  // there, the activities move down), or over what was sent from here not in the chat yet (the outbox's rows, under
  // the messages: it comes in over them), 3 down its row as a message's avatar sits; as it comes in, where it was
  // aimed
  let known = match @motion.measured_rect(c, "emit-landing/" + key + "/" + seq_s(t.seq)) {
    Some(r) => Some((r.0, r.1 + 3.0))
    None => None
  }
  let held = match e.aimed {
    Some(a) if e.aimed_at == t.seq && t.pose != Float => Some(a)
    _ => None
  }
  // (the activities' avatars sit 3 down their rows, as a message's does)
  let mut first : (Double, Double)? = None
  for a in agents {
    match @motion.measured_rect(c, "emit-avatar/" + key + "/" + a) {
      Some(r) =>
        match first {
          Some(f) if f.1 <= r.1 => ()
          _ => first = Some((r.0, r.1))
        }
      None => ()
    }
  }
  if e.out_key != "" {
    match @motion.measured_rect(c, "emit-out/" + key + "/" + e.out_key) {
      Some(r) => {
        let y = r.1 + 3.0
        match first {
          Some(f) if f.1 <= y => ()
          _ => first = Some((avatar.0, y))
        }
      }
      None => ()
    }
  }
  let landing = match (known, held, first) {
    (Some(k), _, _) => k
    (None, Some(h), _) => h
    (None, None, Some(f)) => f
    _ => return None
  }
  e.aimed = Some(landing)
  e.aimed_at = t.seq
  let u = emit_clock(c, t)
  e.trace = (u, avatar.1, landing.1)
  match t.pose {
    Float => {
      // from its activity's avatar, or on from the message before it (where it was)
      let start = match t.from {
        Some(f) => f
        None => avatar
      }
      e.trace = (u, start.1, landing.1)
      Some((hermite(start.0, 0.0, landing.0, 0.0, u), hermite(start.1, 0.0, landing.1, 0.0, u), 1.0, 1.0))
    }
    Spit => {
      e.landed = Some(landing)
      Some((landing.0, landing.1, 1.0, 1.0))
    }
    _ =>
      // home from where it let the message out
      Some((hermite(landing.0, 0.0, avatar.0, 0.0, u), hermite(landing.1, 0.0, avatar.1, 0.0, u), 1.0, 1.0))
  }
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
  c.wake_in(dmax(way.ends() - c.moment(), 0.0))
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
      None => { alpha: 1.0, dy: 0.0, scale: 1.0 }
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
  let still : @ui.GlyphLook = { alpha: 1.0, dy: 0.0, scale: 1.0 }
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
  let (j0, j1) = (glyph_noise(at.index, salt), glyph_noise(at.index, salt + 7919))
  let start = dmax(read * line_ms + (j0 - 0.5) * emit_glyph_jitter, 0.0)
  let p = (ms - start) / emit_glyph_ms
  if p <= 0.0 {
    return { alpha: 0.0, dy: 0.0, scale: 1.0 }
  }
  if p >= 1.0 {
    return still
  }
  let rise = emit_glyph_rise * (0.7 + 0.6 * j1)
  { alpha: @ui.Ease::Out.at(dmin(p / 0.7, 1.0)), dy: rise * (1.0 - @ui.Ease::Out.at(p)), scale: 1.0 }
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
