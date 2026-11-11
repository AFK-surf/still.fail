// Time a view waits on, by a length it declares, on the frames' clock: whether something has
// held so long (a menu opening once the pointer rests on it, a toast's time), whether something happened less than so
// long ago (letters typed together, a tip closed just now). The framework reads its clock for them; the view says only
// the length, and a wake comes at the moment a wait ends, no frames between.

///|
/// A wait: how long its condition has held, when it was last asked on (-1: off), when it was last asked off (-1: never),
/// the frame it was last asked at, and the build (an owned wait's: the build that does not ask it has let it go).
priv struct Held {
  mut held : Double
  mut last : Double
  mut off : Double
  mut used : Int
  mut build : Int
  /// when it will have held (its wake), while it runs; -1 when off or done
  mut due : Double
}

///|
let helds : Map[Int, Held] = Map([])

///|
/// What a wait's time added up frame by frame may fall short of its length by, from rounding, and still have held.
let held_slack_ms : Double = 0.001

///|
/// How many whole `period`s have gone from `from` to `now`, and when the next one starts: after `now`, always. Use the
/// same origin and arithmetic to decide the current period as to schedule its wake: subtracting and dividing can round
/// either side of a period's start onto the other. Otherwise the displayed period can change before its wake, or the
/// next wake can be at the moment already drawn and hide every later one (Ctx::wake_at keeps the earliest).
fn periods_at(now : Double, from : Double, period : Double) -> (Int, Double) {
  let n = ((now - from) / period).floor()
  let n = if from + n * period > now {
    n - 1.0
  } else if from + (n + 1.0) * period <= now {
    n + 1.0
  } else {
    n
  }
  (n.to_int(), from + (n + 1.0) * period)
}

///|
/// When each thing marked happened (Ctx::mark), by its id, as a signal of its own: what asks of one (Ctx::within) is
/// told as that one is marked again, none other. One asked of and never marked holds -inf.
let marks_at : Map[Int, @signals.Signal[Double]] = Map([])

///|
/// When what `id` names was last marked (-inf: never), its signal made as it is first asked of or marked.
fn mark_of(id : Int) -> @signals.Signal[Double] {
  match marks_at.get(id) {
    Some(s) => s
    None => {
      let s = @signals.signal(@double.neg_infinity, same=fn(a, b) { a == b })
      marks_at[id] = s
      s
    }
  }
}

///|
/// Whether `on` has held for `ms` (a declared length), asked each frame by what waits for it; a wake at the moment it
/// will have. Not on, it starts again from nothing, unless `keep`: then it waits where it was (a toast's time, paused
/// while the pointer is over it). `key` in the scope it is asked in. `later`: what is shown does not wait for it (a
/// toast going away after its time); by default it does (a menu opening once the pointer rests). `since`: since when
/// `on` has been as it is, where the caller knows it (the hand's facts each since when: hand_turns.mbt), -1 not known.
/// On since a moment after the frame that last asked it on, it went off and on again between them, unseen: it holds
/// from then, from nothing. On since a moment no earlier than the frame that last asked it off, it has held from then,
/// not from this frame (a frame drawn late after the move counts the wait from the move). Else (said on since before
/// a frame that saw it off: not as it was then) it holds from this frame. `owned`: the wait is what asks it, this time
/// it is built (a trigger's, kept while its part is kept, Ctx::built_used): a build that does not ask it has let it
/// go, and the next that does begins it again, nothing of the one before it kept.
#callsite(autofill(loc))
pub fn Ctx::held(
  self : Ctx,
  key : String,
  on : Bool,
  ms : Double,
  keep? : Bool = false,
  later? : Bool = false,
  since? : Double = -1.0,
  owned? : Bool = false,
  loc~ : SourceLoc,
) -> Bool {
  let id = self.id("\u{2}after/" + key)
  let w = match helds.get(id) {
    // (an owned wait the build before did not ask: let go with what asked it, begun again)
    Some(w) if !(owned && w.build >= 0 && w.build < self.build_no - 1) => w
    _ => {
      // (off: when, so that what turns it on after can say it came between)
      let w = { held: 0.0, last: -1.0, off: if on { -1.0 } else { self.clock }, used: 0, build: -1, due: -1.0 }
      helds[id] = w
      w
    }
  }
  w.used = self.frame_no
  w.build = self.build_no
  built_used(fn() {
    w.used = g().frame_no
    w.build = g().build_no
  })
  self.sweep_helds()
  // (no `since` said, seen off and on now: since the moment its build's watch was first told of a change since it
  // was last read, not this frame's clock (the coordinator of the migration, 2026-11-11), the latest of those of the
  // watches that told it. A watch is told once till it is read: a second change told it before the build has no moment
  // here, and the wait may count from the first and end early by their distance, under a frame (the first telling asks
  // for one); said so (MOTION held_causes, wait_look) wherever more than one told it or more was set after the
  // telling, over-said rather than missed)
  // (only where it was seen off and is on now, coming on since then: one on all along is not told on again by what
  // else came)
  let since = if since >= 0.0 || !(on && w.last < 0.0 && w.off >= 0.0) {
    since
  } else if build_causes.is_empty() {
    // (told by nothing: turned by the clock alone (another wait falling due, the clock compared as it is built), this
    // frame's clock and so the rate's: said, a place to say its `since` or to be a node's)
    match wait_look.val {
      Some(f) => f("held_no_cause", loc, build_causes)
      None => ()
    }
    since
  } else {
    let mut m = build_causes[0]
    for x in build_causes {
      if x.0 > m.0 {
        m = x
      }
    }
    // (told by more than one, or more set after what told it (a watch is told once till it is read: what came after
    // the first has no moment of its own here, and may be what turned it on): said, over-said rather than missed)
    if build_causes.length() > 1 || build_told_more.val {
      match wait_look.val {
        Some(f) => f("held_causes", loc, build_causes)
        None => ()
      }
    }
    // (told as a frame began (a message a Tester's host posted, handed over then): the frame's moment, the rate's,
    // till each message is handed over as it comes)
    if m.1 == "frame" {
      match wait_look.val {
        Some(f) => f("held_frame", loc, [m])
        None => ()
      }
    }
    m.0
  }
  if !on {
    w.last = -1.0
    w.off = self.clock
    w.due = -1.0
    if !keep {
      w.held = 0.0
    }
    return false
  }
  if since >= 0.0 && since <= self.clock {
    if w.last >= 0.0 && since > w.last {
      // (off and on again since the frame that last saw it on: from nothing, from when it came on again)
      if !keep {
        w.held = 0.0
      }
      w.last = since
      w.due = -1.0
    } else if w.last < 0.0 && w.off >= 0.0 && since >= w.off {
      // (on since what made it so, between the frame that saw it off and this one: one that came as that frame was
      // drawn came after it, unseen by it, which saw it off)
      w.last = since
      w.due = -1.0
    }
  }
  if w.last >= 0.0 {
    w.held = w.held + (self.clock - w.last)
  }
  w.last = self.clock
  // Held from its wake on, and not before: what asked it in a part kept (kept_part.mbt's dues, come at their moment)
  // is built again in the frame it holds, never left as it was in a frame that, built whole, has it held (a frame drawn
  // a rounding short of its wake). Its wake set once while it waits, from the time added up a frame at a time (short
  // of `ms` by a rounding at most, and that is not a frame more to wait).
  if (w.due >= 0.0 && self.clock >= w.due) || (w.due < 0.0 && w.held >= ms - held_slack_ms) {
    w.due = -1.0
    true
  } else {
    if w.due < 0.0 {
      w.due = self.clock + dmax(ms - w.held, 1.0)
    }
    if !later && self.wake_by is None {
      self.wake_by = Some(loc)
    }
    self.wake_at_time(w.due, later~, loc~)
    false
  }
}

///|
/// What looks at a wait asked without its own `since` that counts from no cause, from a frame's moment as it began, or
/// from the latest of several (Ctx::held), where something does (a Tester's: wait_looked, MOTION held_* lines): its
/// kind, where it was asked and the moments it was told by. None on a device: nothing made or kept for it.
// kept across runs: set by each Tester as it is made, let go as its run ends
let wait_look : Ref[((String, SourceLoc, Array[(Double, String)]) -> Unit)?] = Ref(None)

///|
/// When the wait `key` (Ctx::held, asked in this scope this frame) will have held: the time of its wake, while it
/// runs; -1 when it is off (paused) or has held.
pub fn Ctx::held_due(self : Ctx, key : String) -> Double {
  match helds.get(self.id("\u{2}after/" + key)) {
    Some(w) => w.due
    None => -1.0
  }
}

///|
/// Forgets the waits not asked for a while (a widget gone).
fn Ctx::sweep_helds(self : Ctx) -> Unit {
  let frame = self.frame_no
  if frame % 120 != 0 {
    return
  }
  let old : Array[Int] = []
  helds.each(fn(id, w) { if frame - w.used > 120 { old.push(id) } })
  for id in old {
    helds.remove(id)
  }
}

///|
/// What `id` names happened now (letters typed, a tip closed): Ctx::within asks how long ago.
pub fn Ctx::mark(self : Ctx, id : Int) -> Unit {
  // (what read it, in this build or kept, told: built again from it; what read another mark not)
  mark_of(id).set(self.clock)
}

///|
/// Whether what `id` names was marked (Ctx::mark) less than `ms` (a declared length) ago: woken as that ends, later
/// (nothing waits on it), so what read it is built again then.
pub fn Ctx::within(self : Ctx, id : Int, ms : Double) -> Bool {
  let at = mark_of(id).get()
  // (its end one sum, the one it wakes at and a test's run_for comes to, start and length: the clock less the start is
  // a rounding short of the length at that very moment, 2016.6666666666665 - 1016.6666666666666 < 1000)
  if self.clock < at + ms {
    // (what reads it read so till then: drawn again as it ends)
    self.wake_at_time(at + ms, later=true)
    true
  } else {
    false
  }
}

///|
fn timers_reset() -> Unit {
  helds.clear()
  marks_at.clear()
  dues.clear()
}

///|
/// What is to be done at a moment said so (Ctx::at_moment): its moment, what (in the scope it was said in), whether what
/// is shown waits for it, and where it was said.
priv struct Due {
  at : Double
  f : () -> Unit
  later : Bool
  loc : SourceLoc
}

///|
/// What is due, by the id of the key it was said under (Ctx::at_moment).
// kept across runs: said as each is declared, let go as it is done, called off or declared anew; a run's start clears it
let dues : Map[Int, Due] = Map([])

///|
/// `f` done once at the moment `when` (the frames' clock), declared under `key` (the cause it is the moment of: "this
/// item's tap left single"; in the scope it is said in), as the first frame at or after it begins, before it is built,
/// outside any build, whatever frames come between: what is to be done at a moment said so, never found by asking a
/// wait each frame (Ctx::held). Declared again under the same key, the new moment and `f` take its place; called off
/// (Ctx::call_off), it is not done. Waited for (a wake at its moment: a test's run goes on to it), unless `later`. It
/// runs in the scope it was said in (Ctx::on_press's in_said_scope). The View's own: View::at_moment.
#callsite(autofill(loc))
pub fn Ctx::at_moment(self : Ctx, key : String, when : Double, f : () -> Unit, later? : Bool = false, loc~ : SourceLoc) -> Unit {
  dues[self.id("\u{2}due/" + key)] = { at: when, f: self.in_said_scope(f), later, loc }
  self.wake_at_time(when, later~, loc~)
}

///|
/// What was declared under `key` (Ctx::at_moment, in the scope it is said in) ended, not done: whether it was still to
/// come (a second tap calling off the first's moment: it was).
pub fn Ctx::call_off(self : Ctx, key : String) -> Bool {
  let id = self.id("\u{2}due/" + key)
  let was = dues.contains(id)
  dues.remove(id)
  was
}

///|
/// A frame begins: what was due by its time done, in the order of their moments, each once (what one does may declare
/// or call off others: those it calls off are not done); the wake of each still to come said again (this frame's wakes
/// begin from none).
fn Ctx::dues_frame_start(self : Ctx) -> Unit {
  if dues.is_empty() {
    return
  }
  let now = self.clock
  let due : Array[(Int, Due)] = []
  dues.each(fn(id, d) { if d.at <= now { due.push((id, d)) } })
  due.sort_by(fn(a, b) { a.1.at.compare(b.1.at) })
  for p in due {
    let (id, d) = p
    // (still the one declared under its key: not called off, nor declared anew, by what ran before it)
    match dues.get(id) {
      Some(now_d) if physical_equal(now_d, d) => {
        dues.remove(id)
        run_press(Some(d.f))
      }
      _ => ()
    }
  }
  dues.each(fn(_, d) { self.wake_at_time(d.at, later=d.later, loc=d.loc) })
}
