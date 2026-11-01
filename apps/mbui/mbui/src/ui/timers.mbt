// Time a view waits on, by a length it declares, on the frames' clock (docs/determinism.md): whether something has
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
let helds : Map[Int, Held] = {}

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
/// When each thing marked happened (Ctx::mark), by its id.
let marks_at : Map[Int, Double] = {}

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
    } else if w.last < 0.0 && w.off >= 0.0 && since >= w.off {
      // (on since what made it so, between the frame that saw it off and this one: one that came as that frame was
      // drawn came after it, unseen by it, which saw it off)
      w.last = since
    }
  }
  if w.last >= 0.0 {
    w.held = w.held + (self.clock - w.last)
  }
  w.last = self.clock
  // (at its wake it has held: the time added up a frame at a time comes to `ms` short by a rounding at most, and that
  // is not a frame more to wait)
  if w.held >= ms - held_slack_ms {
    w.due = -1.0
    true
  } else {
    w.due = self.clock + (ms - w.held)
    self.wake_in(ms - w.held, later~, loc~)
    false
  }
}

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
  marks_at[id] = self.clock
  // (what read it, in this build or kept, told: built again from it)
  marks_said.set(@signals.untracked(fn() { marks_said.get() }) + 1)
}

///|
/// Told as anything is marked (Ctx::mark): what asked how long ago (Ctx::within) built again.
// kept across runs: only counts on
let marks_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// Whether what `id` names was marked (Ctx::mark) less than `ms` (a declared length) ago: woken as that ends, later
/// (nothing waits on it), so what read it is built again then.
pub fn Ctx::within(self : Ctx, id : Int, ms : Double) -> Bool {
  marks_said.get() |> ignore
  match marks_at.get(id) {
    Some(at) if self.clock - at < ms => {
      // (what reads it read so till then: drawn again as it ends)
      self.wake_at_time(at + ms, later=true)
      true
    }
    _ => false
  }
}

///|
fn timers_reset() -> Unit {
  helds.clear()
  marks_at.clear()
}
