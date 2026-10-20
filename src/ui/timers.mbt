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
}

///|
let helds : Map[Int, Held] = {}

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
      let w = { held: 0.0, last: -1.0, used: 0 }
      helds[id] = w
      w
    }
  }
  w.used = self.frame_no
  self.sweep_helds()
  if !on {
    w.last = -1.0
    if !keep {
      w.held = 0.0
    }
    return false
  }
  if w.last >= 0.0 {
    w.held = w.held + (self.now - w.last)
  }
  w.last = self.now
  if w.held >= ms {
    true
  } else {
    self.wake_in(ms - w.held, later~, loc~)
    false
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
  marks_at[id] = self.now
}

///|
/// Whether what `id` names was marked (Ctx::mark) less than `ms` (a declared length) ago. Nothing is woken when that
/// ends: what asks it asks at a frame of its own (the next letter typed, the next tip hovered).
pub fn Ctx::within(self : Ctx, id : Int, ms : Double) -> Bool {
  match marks_at.get(id) {
    Some(at) => self.now - at < ms
    None => false
  }
}

///|
fn timers_reset() -> Unit {
  helds.clear()
  marks_at.clear()
}
