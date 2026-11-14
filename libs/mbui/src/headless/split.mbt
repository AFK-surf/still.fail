// The split handle: a movable separator between two panes. Read out a separator (`Separator`) called by its label, with
// its range `(min, value, max)`, its value as words (`said_value(value)`), and `Increment` and `Decrement` while it is
// not disabled. Dragged along `axis` (`Horizontal`: left and right in window coordinates `d.wx`; `Vertical`: up and
// down in `d.wy`), stepped by the arrow keys along `axis` and by Home and End while focused, stepped by a screen
// reader's `Increment` and `Decrement`, and optionally reset by a double click or double tap (`reset`).

///|
/// Which way the splitter moves: `Horizontal` (dragged left/right, stepped by ← and →) or `Vertical` (dragged up/down,
/// stepped by ↑ and ↓).
#derive(Eq, Debug)
pub(all) enum SplitAxis {
  Horizontal
  Vertical
}

///|
/// A split handle as its look reads it: each a reading, followed where a binding reads it.
pub struct Split {
  priv node : @view.View
  priv now : () -> Double
  priv lo : Double
  priv hi : Double
  priv off : () -> Bool
}

///|
/// Its value now, clamped to `[min, max]`.
pub fn Split::value(self : Split) -> Double {
  split_clamp((self.now)(), self.lo, self.hi)
}

///|
/// How far along `[min, max]` it is now (`0.0` at `min`, `1.0` at `max`).
pub fn Split::part(self : Split) -> Double {
  let span = self.hi - self.lo
  if span <= 0.0 {
    0.0
  } else {
    split_clamp(((self.now)() - self.lo) / span, 0.0, 1.0)
  }
}

///|
/// Whether it is disabled: it takes no drag, no keys and no focus (as its caller says).
pub fn Split::disabled(self : Split) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is dragging/holding it now (View::pressed).
pub fn Split::dragging(self : Split) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over it now (View::pointed): a mouse's, never a finger's.
pub fn Split::hovered(self : Split) -> Bool {
  self.node.pointed()
}

///|
/// Whether it has the keyboard's focus and that shows (View::focus_shown).
pub fn Split::focus_shown(self : Split) -> Bool {
  self.node.focus_shown()
}

///|
fn split_clamp(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
fn split_snap(x : Double, lo : Double, hi : Double, step : Double) -> Double {
  let c = split_clamp(x, lo, hi)
  if step <= 0.0 {
    c
  } else {
    let steps = ((c - lo) / step).round()
    split_clamp(lo + steps * step, lo, hi)
  }
}

///|
/// The key codes a split handle answers (`ui`'s `key_code_*`).
let split_key_left : Int = 3

///|
let split_key_right : Int = 4

///|
let split_key_up : Int = 5

///|
let split_key_down : Int = 6

///|
let split_key_home : Int = 8

///|
let split_key_end : Int = 9

///|
/// A movable split handle in `parent`, called `label` (what a screen reader says), at `value` in `[min, max]` stepped
/// by `step` on arrow keys and screen-reader actions, `change` told the new value as it is dragged or stepped. `axis`
/// chooses whether dragging and arrow keys move horizontally (`d.wx`, ←/→) or vertically (`d.wy`, ↑/↓). `span` gives
/// the pixel span corresponding to `max - min` when `value` is normalized (default: `max - min`, 1 point per unit).
/// `reset` runs on a double click or double tap without dragging. `look` is given the handle's node and its `Split`
/// state. The handle's node.
#callsite(autofill(loc))
pub fn split(
  parent : @view.View,
  label : () -> String,
  value : () -> Double,
  min~ : Double,
  max~ : Double,
  step~ : Double,
  change : (Double) -> Unit,
  look : (@view.View, Split) -> Unit,
  axis? : SplitAxis = Horizontal,
  span? : () -> Double,
  reset? : () -> Unit,
  said_value? : (Double) -> String = fn(x) { x.to_string() },
  disabled? : () -> Bool = fn() { false },
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  let lo = if min <= max { min } else { max }
  let hi = if min <= max { max } else { min }
  let step_by = if step > 0.0 { step } else { (hi - lo) / 20.0 }
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let able = fn() { !disabled() }
    look(v, { node: v, now: value, lo, hi, off: disabled })
    let tell = fn(target : Double, snap : Bool) {
      if !disabled() {
        let next = if snap { split_snap(target, lo, hi, step) } else { split_clamp(target, lo, hi) }
        let cur = split_clamp(value(), lo, hi)
        if next != cur {
          change(next)
        }
      }
    }
    let start_pos = Ref(0.0)
    let start_val = Ref(0.0)
    let moved = Ref(false)
    let pos_of = fn(d : @view.Drag) {
      match axis {
        Horizontal => d.wx
        Vertical => d.wy
      }
    }
    v
    .presses(By(able))
    .focusable(By(able))
    .says(By(fn() {
      let now = split_clamp(value(), lo, hi)
      let actions : Array[@view.Action] = if disabled() { [] } else { [Increment, Decrement] }
      Some(@view.said(Separator, label=label(), value=said_value(now), range=(lo, now, hi), actions~))
    }))
    .on_drag(fn(d) {
      if disabled() {
        return
      }
      match d.kind {
        Down => {
          start_pos.val = pos_of(d)
          start_val.val = split_clamp(value(), lo, hi)
          moved.val = false
        }
        Moved => {
          let delta_px = pos_of(d) - start_pos.val
          if delta_px.abs() > 0.5 {
            moved.val = true
          }
          let px_span = match span {
            Some(f) => f()
            None => hi - lo
          }
          if px_span > 0.0 {
            let delta_val = delta_px / px_span * (hi - lo)
            tell(start_val.val + delta_val, step > 0.0)
          }
        }
        Up =>
          if moved.val {
            v.twice_forgot()
          } else if v.twice(d) && reset is Some(r) {
            r()
          }
        _ => ()
      }
    })
    .on_step(fn(by) {
      if !disabled() && step_by > 0.0 {
        let cur = split_clamp(value(), lo, hi)
        tell(cur + by.to_double() * step_by, true)
      }
    })
    .on_key(fn(k) {
      if disabled() || k.mods != 0 {
        return false
      }
      let cur = split_clamp(value(), lo, hi)
      let dec = match axis {
        Horizontal => k.code == split_key_left
        Vertical => k.code == split_key_up
      }
      let inc = match axis {
        Horizontal => k.code == split_key_right
        Vertical => k.code == split_key_down
      }
      if dec {
        tell(cur - step_by, true)
        true
      } else if inc {
        tell(cur + step_by, true)
        true
      } else if k.code == split_key_home {
        tell(lo, false)
        true
      } else if k.code == split_key_end {
        tell(hi, false)
        true
      } else {
        false
      }
    })
    |> ignore
  })
}
