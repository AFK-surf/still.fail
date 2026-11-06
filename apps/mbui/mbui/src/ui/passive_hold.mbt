// A finger can hold a non-pressing node for a tip without taking the short press or a scroll from what lies under it.
// The observer sees the same events and timeline as their owner, and takes the press only when its hold wins.

///|
priv struct PassiveHoldWatch {
  anchor : @view.View
  enabled : () -> Bool
  hold : () -> Unit
  lift : () -> Unit
  cancel : () -> Unit
}

///|
priv struct PassiveHold {
  watch : PassiveHoldWatch
  mut holder : ViewHeld
  x : Double
  y : Double
  mut held : Bool
  mut stop : () -> Unit
}

///|
// kept across runs: each watch is owned by its node; view_forget disposes the tree
let passive_holds : Map[@view.NodeId, PassiveHoldWatch] = Map([])

///|
// kept across runs: let go with its node, the finger, or view_forget
let passive_holding : Ref[PassiveHold?] = Ref(None)

///|
/// Observe a finger held on `anchor` for long_press_ms without taking its ordinary press or drag. The topmost enabled
/// observer at the down is considered after the node taking that down. If the hold wins, that node is cancelled, `hold`
/// is called, and this press is no tap; `lift` follows a release, `cancel` a move, takeover or system cancellation.
/// An observer belongs to its anchor and is removed with it. `enabled` is followed: becoming false ends this press's
/// observation, and becoming true again does not restart it.
pub fn observe_finger_hold(
  anchor : @view.View,
  enabled : () -> Bool,
  hold : () -> Unit,
  lift : () -> Unit,
  cancel : () -> Unit,
) -> Unit {
  guard anchor.alive() else { return }
  let id = anchor.id()
  let watch : PassiveHoldWatch = { anchor, enabled, hold, lift, cancel }
  passive_holds[id] = watch
  anchor.reacts(enabled, fn(on) {
    if !on {
      match passive_holding.val {
        Some(p) if p.watch.anchor.id() == id => passive_hold_cancel()
        _ => ()
      }
    }
  })
  anchor.owns(fn() {
    passive_holds.remove(id)
    match passive_holding.val {
      Some(p) if p.watch.anchor.id() == id => passive_hold_cancel()
      _ => ()
    }
  }) |> ignore
}

///|
fn passive_hold_cancel() -> Unit {
  match passive_holding.val {
    Some(p) => {
      passive_holding.val = None
      (p.stop)()
      if p.held { (p.watch.cancel)() }
    }
    None => ()
  }
}

///|
fn passive_same_holder(a : ViewHeld, b : ViewHeld?) -> Bool {
  match (a, b) {
    (Node(x), Some(Node(y))) | (Dragging(x), Some(Dragging(y))) => x == y
    (Old(i, x), Some(Old(j, y))) => i == j && x == y
    (Nowhere, Some(Nowhere)) => true
    _ => false
  }
}

///|
/// As a finger goes down, after the node it went to has seen it: its own hold at the same time has priority.
fn passive_hold_down(tree : @view.Tree, x : Double, y : Double, at : Double) -> Unit {
  passive_hold_cancel()
  guard !passive_holds.is_empty() && view_held.val is Some(holder) else { return }
  let target = match tree.target_at(x, y) {
    Pressed(id) | Dragged(id) | Hosted(id) => Some(id)
    TopRow(_) | Off(_) => return
    Nothing => None
  }
  let under = tree.under(x, y)
  // A small control may take a press outside its drawn bounds; do not observe a different anchor under that reach.
  if target is Some(id) && !under.contains(id) { return }
  let found : Ref[PassiveHoldWatch?] = Ref(None)
  for id in under {
    if Some(id) == target { found.val = None }
    match passive_holds.get(id) {
      Some(w) if @signals.untracked(w.enabled) => found.val = Some(w)
      _ => ()
    }
  }
  guard found.val is Some(watch) else { return }
  let p : PassiveHold = { watch, holder, x, y, held: false, stop: fn() {  } }
  passive_holding.val = Some(p)
  p.stop = watch.anchor.at_moment(at + long_press_ms, fn() {
    if !(passive_holding.val is Some(now) && physical_equal(now, p)) {
      return
    }
    let eligible = watch.anchor.alive() && @signals.untracked(watch.enabled) &&
      passive_same_holder(p.holder, view_held.val) &&
      (match p.holder {
        Node(id) => tree.holder() == Some(id)
        Dragging(id) => tree.holder() == Some(id) && tree.yields(id)
        Old(_, _) => {
          let c = g()
          c.down && !c.dragging && c.taken_at != c.press_at
        }
        Nowhere => true
      })
    if !eligible {
      passive_hold_cancel()
      return
    }
    // Stop the original press, but keep its ancestor claim chain: a later move can still become a scroll.
    p.held = true
    view_nothing_down.val = None
    view_held.val = Some(Nowhere)
    let previous = p.holder
    p.holder = Nowhere
    match previous {
      Node(id) => {
        tree.event(at + long_press_ms, fn() { tree.hold_lost_in(id.at) })
        tree_field_let_go(id, x, y, false)
      }
      Dragging(id) => tree.drag_at(id, Off, x, y, at + long_press_ms, finger=view_fingers[0]) |> ignore
      Old(_, _) => old_pointer_now(3, x, y, 0, 0, at + long_press_ms)
      Nowhere => ()
    }
    if passive_holding.val is Some(now) && physical_equal(now, p) && watch.anchor.alive() {
      (watch.hold)()
    }
  })
}

///|
/// The event before its normal dispatch; true if this release belongs to a hold, not a tap.
fn passive_hold_before(kind : Int, x : Double, y : Double) -> Bool {
  guard passive_holding.val is Some(p) else { return false }
  let far = (x - p.x).abs() > touch_slop() || (y - p.y).abs() > touch_slop()
  if kind == 1 && far {
    passive_hold_cancel()
    return false
  }
  if kind == 2 {
    passive_holding.val = None
    (p.stop)()
    if p.held {
      if far { (p.watch.cancel)() } else { (p.watch.lift)() }
      return true
    }
  } else if kind == 0 || kind == 3 || kind >= 4 {
    passive_hold_cancel()
  }
  false
}

///|
/// A move may be taken over even before this observer's slop; stop observing as soon as its original holder changes.
fn passive_hold_after_move() -> Unit {
  match passive_holding.val {
    Some(p) if !passive_same_holder(p.holder, view_held.val) => passive_hold_cancel()
    _ => ()
  }
}
