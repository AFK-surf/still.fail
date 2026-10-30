// Time a view waits on, by a length it declares, on the frames' clock (docs/determinism.md): whether something has
// held so long (a menu opening once the pointer rests on it, a toast's time), whether something happened less than so
// long ago (letters typed together, a tip closed just now). The framework reads its clock for them; the view says only
// the length, and a wake comes at the moment a wait ends, no frames between.

///|
/// A wait: how long its condition has held, when it was last asked on (-1: off), the frame it was last asked at.
priv struct Held {
  mut held : Double
  mut last : Double
  mut used : Int
  /// when it will have held (its wake), while it runs; -1 when off or done
  mut due : Double
}

///|
let helds : Map[Int, Held] = {}

///|
/// What a wait's time added up frame by frame may fall short of its length by, from rounding, and still have held.
let held_slack_ms : Double = 0.001

///|
/// How many whole `period`s have gone from `from` to `now`, and when the next one starts: after `now`, always. A frame
/// on a period's start is in that period, though `now - from` may come out a hair short of it (1546.67 − 1016.67 is
/// 529.999…): counted from the division alone, the next start would be now itself, a wake at the moment already
/// drawn, which wakes nothing and hides every later one (Ctx::wake_at keeps the earliest).
fn periods_at(now : Double, from : Double, period : Double) -> (Int, Double) {
  let n = ((now - from) / period).floor()
  let n = if from + (n + 1.0) * period <= now { n + 1.0 } else { n }
  (n.to_int(), from + (n + 1.0) * period)
}

///|
/// When each thing marked happened (Ctx::mark), by its id.
let marks_at : Map[Int, Double] = {}

///|
/// Whether `on` has held for `ms` (a declared length), asked each frame by what waits for it; a wake at the moment it
/// will have. Not on, it starts again from nothing, unless `keep`: then it waits where it was (a toast's time, paused
/// while the pointer is over it). `key` in the scope it is asked in. `later`: what is shown does not wait for it (a
/// toast going away after its time); by default it does (a menu opening once the pointer rests).
#callsite(autofill(loc))
pub fn Ctx::held(
  self : Ctx,
  key : String,
  on : Bool,
  ms : Double,
  keep? : Bool = false,
  later? : Bool = false,
  loc~ : SourceLoc,
) -> Bool {
  let id = self.id("\u{2}after/" + key)
  let w = match helds.get(id) {
    Some(w) => w
    None => {
      if !on {
        return false
      }
      let w = { held: 0.0, last: -1.0, used: 0, due: -1.0 }
      helds[id] = w
      w
    }
  }
  w.used = self.frame_no
  built_used(fn() { w.used = g().frame_no })
  self.sweep_helds()
  if !on {
    w.last = -1.0
    w.due = -1.0
    if !keep {
      w.held = 0.0
    }
    return false
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
