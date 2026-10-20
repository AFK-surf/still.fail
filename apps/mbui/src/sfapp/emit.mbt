// An agent's message coming out of its activity's avatar (ember apps/android chat/screens/ChatMotion.kt; web
// useEmissions), one at a time: the activity folds to its avatar (Fold), the avatar hops to where the message goes
// (Float: up, slowing, then falling ever faster, stretched, stopping dead there), the message comes out of it as it
// lands, the avatar flattened by the fall and springing back (Spit), and the avatar goes on down to where the activity
// now is, which unfolds again (Return). Until its turn a message waits out of the list. With motion reduced, each pose
// at once. Messages no one watches just appear: arriving while the page is not in front or the reader has scrolled up,
// and all still waiting when that happens. Only drawn: the message is laid out (and tapped) where it is from the
// frame it comes into the list; the flying avatar is a picture over the list.

///|
priv enum Pose {
  Fold
  Float
  Spit
  Return
} derive(Eq, Show)

///|
fn Pose::ms(self : Pose) -> Double {
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
/// The same agent's next message, waiting as one comes out: the avatar drops on to it, no hop (how long).
let emit_drop_ms : Double = 280.0

///|
/// The hop: how high over the higher of its two ends, and the share of its time spent going up.
let emit_hop : Double = 34.0

///|
let emit_rise : Double = 0.42

///|
/// A message's turn: its seq and agent, its pose and how far through it (`clock`, 0 to 1, said as the pose sets out,
/// from where the pose before was declared to end); `from`, on from the same agent's message before it (where its
/// avatar is), dropping on without going home.
priv struct Turn {
  seq : Double
  agent : String
  pose : Pose
  from : (Double, Double)?
  clock : @motion.Anim
}

///|
/// A chat's messages coming out of avatars.
priv struct Emits {
  decided : Map[String, Bool]
  done : Map[String, Bool]
  /// waiting: seq, agent, its activity's folding (from when it began waiting)
  queue : Array[(Double, String, @motion.Anim)]
  mut current : Turn?
  /// where the flying avatar was last sent, for which message; where it last let one out
  mut aimed : (Double, Double)?
  mut aimed_at : Double
  mut landed : (Double, Double)?
  /// whether what comes in is watched (the page in front, the reader at its end), as last drawn
  mut watched : Bool
  /// the agent whose avatar the flying copy shows as (its activity's own hidden), "" none
  mut copied : String
  /// the flight as last worked out: how far through its pose, from where (y) to where (y), for the motion log
  mut trace : (Double, Double, Double)
  /// what it is said to move by (Ctx::moving): its turns, each pose's end known as it starts
  mover : @ui.Mover
}

///|
let emits : Map[String, Emits] = {}

///|
fn emits_of(key : String) -> Emits {
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
        watched: false,
        copied: "",
        trace: (0.0, 0.0, 0.0),
        mover: @ui.Mover::new(),
      }
      emits[key] = e
      e
    }
  }
}

///|
fn seq_s(seq : Double) -> String {
  seq.to_int64().to_string()
}

///|
/// Messages seen for the first time (ChatMotion.take): an agent's, said while the chat shows (the core's `said`),
/// while its activity shows, waits its turn to come out of it.
fn emit_take(c : @ui.Ctx, e : Emits, v : ChatView, showing : Map[String, Bool]) -> Unit {
  for m in v.messages {
    let k = seq_s(m.seq)
    if e.decided.contains(k) {
      continue
    }
    let agent = if m.author_kind == "agent" && !m.mine && !m.system { m.by.agent } else { "" }
    let goes = e.watched && m.said && agent != "" && showing.contains(agent)
    e.decided[k] = goes
    if goes {
      // its agent's activity folds from now
      e.queue.push((m.seq, agent, pose_clock(Fold.ms(), None)))
    }
  }
}

///|
/// Whether the message comes (or came) out of an avatar: it never rises in as others do.
fn emit_goes(e : Emits, seq : Double) -> Bool {
  e.decided.get(seq_s(seq)) == Some(true)
}

///|
/// Waiting its turn (or its avatar still on its way to it): not in the list yet.
fn emit_held(e : Emits, seq : Double) -> Bool {
  let k = seq_s(seq)
  if e.decided.get(k) != Some(true) || e.done.contains(k) {
    return false
  }
  match e.current {
    Some(t) if t.seq == seq && (t.pose == Spit || t.pose == Return) => false
    _ => true
  }
}

///|
fn emit_emitting(e : Emits, seq : Double) -> Bool {
  match e.current {
    Some(t) => t.seq == seq && t.pose == Spit
    None => false
  }
}

///|
/// An agent's activity folded to its avatar: from when its first message begins waiting until its last is out.
fn emit_folded(e : Emits, agent : String) -> Bool {
  match e.current {
    Some(t) if t.agent == agent => return true
    _ => ()
  }
  e.queue.iter().any(fn(q) { q.1 == agent })
}

///|
/// Its avatar away flying (its activity does not glide meanwhile).
fn emit_away(e : Emits, agent : String) -> Bool {
  match e.current {
    Some(t) => t.agent == agent && t.pose != Fold
    None => false
  }
}

///|
/// Agents whose activity must stay while their messages come out.
fn emit_keeps(e : Emits) -> Map[String, Bool] {
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
fn emit_release(e : Emits) -> Unit {
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
fn emit_next(c : @ui.Ctx, e : Emits, agent : String, at? : Double) -> Unit {
  if e.queue.length() == 0 {
    e.current = None
    return
  }
  let (seq, who, fold) = e.queue.remove(0)
  // folded already (or its agent's avatar out already): on its way; else what is left of its folding (how far its
  // folding has gone, from when it began waiting), from here: from where the turn before was declared to end, else
  // from this frame
  let float = who == agent || !fold.moving()
  let left = Fold.ms() * (1.0 - fold.get())
  e.current = Some({
    seq,
    agent: who,
    pose: if float { Float } else { Fold },
    from: None,
    clock: if float { pose_clock(Float.ms(), at) } else { pose_clock(left, at) },
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
    Some(t) => t.clock.ends()
    None => -1.0
  }
}

///|
/// How long a pose takes (Float on from the message before: only the drop).
fn pose_ms(pose : Pose, from : (Double, Double)?) -> Double {
  match pose {
    Float => if from is Some(_) { emit_drop_ms } else { Float.ms() }
    _ => pose.ms()
  }
}

///|
/// A pose's way, 0 to 1 over its length, linear: from `at` (where the pose before was declared to end), else from
/// this frame.
fn pose_clock(ms : Double, at : Double?) -> @motion.Anim {
  let a = @motion.Anim::new(0.0)
  a.animate(1.0, @motion.tween(ms, ease=Linear), start_at?=at)
  a
}

///|
/// The poses played on, a frame at a time (ChatMotion.play): each to its end, then the next; the next waiting starts
/// once none plays. Not watched, all of it at once.
fn emit_step(c : @ui.Ctx, e : Emits) -> Unit {
  if !e.watched || @ui.reduced_motion() {
    emit_release(e)
    return
  }
  if e.current is None {
    emit_next(c, e, "")
  }
  // a pose's end reached: the next pose, from its own beginning in this frame
  let was = e.current
  let mut steps = 0
  while steps < 6 {
    steps = steps + 1
    let t = match e.current {
      Some(t) => t
      None => return
    }
    if t.clock.moving() {
      break
    }
    // the next from where this one was declared to end, whichever frame sees it
    let at = t.clock.ends()
    match t.pose {
      Fold => e.current = Some({ ..t, pose: Float, clock: pose_clock(Float.ms(), Some(at)) })
      Float => e.current = Some({ ..t, pose: Spit, from: None, clock: pose_clock(Spit.ms(), Some(at)) })
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
            })
          }
          _ => e.current = Some({ ..t, pose: Return, clock: pose_clock(Return.ms(), Some(at)) })
        }
      Return => {
        e.done[seq_s(t.seq)] = true
        emit_next(c, e, t.agent, at~)
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
}

///|
/// The current pose's time, 0 to 1, linear.
fn emit_clock(c : @ui.Ctx, t : Turn) -> Double {
  ignore(c)
  t.clock.get()
}

///|
/// What is left, at `s` seconds, of a spring let go from 1 (stiffness 520, damping 14, mass 1: under-damped).
fn emit_settle(s : Double) -> Double {
  let w0 = (520.0).sqrt()
  let z = 14.0 / (2.0 * w0)
  let wd = w0 * (1.0 - z * z).sqrt()
  @math.exp(-z * w0 * s) * (@math.cos(wd * s) + z * w0 / wd * @math.sin(wd * s))
}

///|
fn emit_smooth(t : Double) -> Double {
  t * t * (3.0 - 2.0 * t)
}

///|
/// Where the flying avatar's 18 face is (its top left, in the window) and how it is scaled about its middle, or None
/// when none flies (ChatMotion.flight): between where it set out and where it is going, both as last laid out.
fn emit_flight(c : @ui.Ctx, key : String, e : Emits, agents : Array[String]) -> (Double, Double, Double, Double)? {
  let t = match e.current {
    Some(t) if t.pose != Fold => t
    _ => return None
  }
  let avatar = match @motion.measured_rect(c, "emit-avatar/" + key + "/" + t.agent) {
    Some(r) => (r.0, r.1)
    None => return None
  }
  // before the message is in the list: where its avatar will be, the first activity's place (the message comes in
  // there, the activities move down), 3 down its row as a message's avatar sits; as it comes in, where it was aimed
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
      // on from the message before it: only the drop
      let start = match t.from {
        Some(f) => f
        None => avatar
      }
      e.trace = (u, start.1, landing.1)
      let rise = if t.from is Some(_) { 0.0 } else { emit_rise }
      let top = if t.from is Some(_) { start.1 } else { dmin(start.1, landing.1) - emit_hop }
      let up = if rise > 0.0 { u / rise } else { 1.0 }
      let down = (u - rise) / (1.0 - rise)
      let y = if u < rise {
        start.1 + (top - start.1) * (1.0 - @math.pow(1.0 - up, 2.5))
      } else {
        top + (landing.1 - top) * @math.pow(dmax(down, 0.0), 2.5)
      }
      let across = if u < 0.5 { 4.0 * u * u * u } else { 1.0 - @math.pow(-2.0 * u + 2.0, 3.0) / 2.0 }
      let stretch = if u < rise { 0.07 * @math.sin(@math.PI * up) } else { 0.14 * down * down }
      Some((start.0 + (landing.0 - start.0) * across, y, 1.0 - stretch * 0.6, 1.0 + stretch))
    }
    Spit => {
      e.landed = Some(landing)
      let k = emit_settle(u * Spit.ms() / 1000.0)
      let swell = 1.0 +
        0.12 *
        (if u < 0.4 {
          emit_smooth(u / 0.4)
        } else if u < 0.75 {
          1.0 - emit_smooth((u - 0.4) / 0.35)
        } else {
          0.0
        })
      Some((landing.0, landing.1, swell * (1.0 + 0.16 * k), swell * (1.0 - 0.2 * k)))
    }
    _ => {
      let k = 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)
      Some((landing.0 + (avatar.0 - landing.0) * k, landing.1 + (avatar.1 - landing.1) * k, 1.0, 1.0))
    }
  }
}

///|
/// The flying avatar over the list (Chat.kt Flyer): the agent's picture where emit_flight has it, drawn only.
fn emit_flyer(c : @ui.Ctx, key : String, e : Emits, v : ChatView) -> Unit {
  let (x, y, sx, sy) = match emit_flight(c, key, e, v.agents.map(fn(a) { a.key })) {
    Some(f) => f
    None => return
  }
  let a = match e.current {
    Some(t) => v.agents.iter().find_first(fn(a) { a.key == t.agent })
    None => None
  }
  let (maker, runtime) = match a {
    Some(a) => (a.maker, a.runtime)
    None => ("", "")
  }
  c.layer(fn() {
    let b = c.box(tx=x, ty=y, w=Px(18.0), h=Px(18.0), fn() { agent_avatar(c, maker, runtime) })
    c.look(b, @ui.look(sx~, sy~))
    c.draw_only(b)
  })
  |> ignore
  match e.current {
    Some(t) => {
      let (u, fy, ly) = e.trace
      @motion.log_frame(c, "emit/" + seq_s(t.seq), "pose=\{t.pose} x=\{x} y=\{y} sx=\{sx} sy=\{sy} u=\{u} from=\{fy} to=\{ly}")
    }
    None => ()
  }
}

///|
/// A message coming out of its avatar (Chat.kt emitOut, 380 ms): its column from 35% about 12 in and down, unrolling
/// from its top, both on Ease.Out over the whole; its opacity in by 35% of the time.
fn emit_out(c : @ui.Ctx, i : Int, e : Emits, seq : Double) -> Unit {
  if !emit_emitting(e, seq) {
    return
  }
  let t = e.current.unwrap()
  let u = emit_clock(c, t)
  let k = @motion.Ease::Out.at(u)
  match @motion.measured_rect(c, "emit-col/" + seq_s(seq)) {
    Some((_, _, cw, ch)) => {
      let s = 0.35 + 0.65 * k
      c.look(i, @ui.look(alpha=if u < 0.35 { @motion.Ease::Out.at(u / 0.35) } else { 1.0 }, scale=s, ox=if cw > 0.0 { 12.0 / cw } else { 0.0 }, oy=if ch > 0.0 { 12.0 / ch } else { 0.0 }))
      c.cut_to_top(i, ch * k)
    }
    None => c.look(i, @ui.look(alpha=0.0))
  }
}

///|
/// Whether the app is shown (what it last told the core: `client.focus`); before it told anything, shown.
fn app_in_front() -> Bool {
  !attention.told || attention.visible
}
