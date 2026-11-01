// A room opening on what it holds and closing on it as a node of the window's tree (reveal's `middle`, made once): as tall as its share of what it holds is laid out, from the moment what opens or closes it changes, its way
// as long as a move as far as what it holds is tall then (a Move per point of it); what it holds kept in its middle, as
// big as it is open and faded in from half open, about the middle of what it draws, cut at both ends softly; all of
// it, as tall as it is, once it is open; none of it pressed or read out once it is closing or shut.

///|
/// What `make` makes in a room in `parent` that opens as `open` says it is and closes as it says it is not (each from
/// where it is at that moment, its way as long as a Move as far as what it holds is laid out tall then), still as it is
/// made: as tall as its share of what it holds comes to (View::opens: the same layout's, whatever its words or width
/// come to meanwhile), what it holds in its middle (row_held_look: as big as it is open about the middle of what it
/// draws, coming in from half open), cut at its top and foot softly (View::cuts_softly); as tall as what it holds once
/// it is open; nothing tall once it is shut. Taking no press and read out as nothing from the moment it closes. The
/// room's node.
pub fn reveal_node(parent : @view.View, open : () -> Bool, make : (@view.View) -> Unit) -> @view.View {
  let way = NodeWay::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
  parent.box(fn(room) {
    // (as tall as it is laid out, whatever room it has: what is past its room cut)
    let held = room.box(fn(h) {
      h.shrink(Is(0.0)) |> ignore
      make(h)
    })
    let shown = fn() { way.shown(room) }
    room.reacts(open, fn(o) {
      // (how far it goes: what it holds is laid out tall at this moment, the way's length said once, not followed)
      way.go(room, if o { 1.0 } else { 0.0 }, move().per_unit(held.laid_size().1))
    })
    room
    .opens(By(fn() {
      let k = shown()
      if k >= 1.0 {
        None
      } else {
        Some(if k > 0.0 { k } else { 0.0 })
      }
    }))
    .clips(By(fn() { shown() < 1.0 }))
    .cuts_softly(By(fn() { shown() < 1.0 }))
    .presses(By(fn() { open() }))
    .hides(By(fn() { !open() }))
    |> ignore
    held
    .scale(By(fn() {
      let k = shown()
      if k < 0.0 {
        0.0
      } else if k > 1.0 {
        1.0
      } else {
        k
      }
    }), about=Drawn)
    .alpha(By(fn() {
      let k = shown()
      if k >= 1.0 {
        1.0
      } else {
        let a = (k - @ui.row_gone_at) / (1.0 - @ui.row_gone_at)
        if a > 0.0 {
          a
        } else {
          0.0
        }
      }
    }))
    |> ignore
  })
}

///|
/// A way a node's look goes (Way), from the moment of its cause, drawn where it is at the moment it is drawn while it
/// goes: what reads it told as it ends, as the node is; let go with the node.
priv struct NodeWay {
  way : Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
}

///|
fn NodeWay::new(v : Double) -> NodeWay {
  { way: Way::new(v), ended: @signals.signal(0), due: fn() {  } }
}

///|
/// Off to `to` as `spec` says from `n`'s cause's moment, from where it is then (as fast as it goes then); its end a
/// moment of `n`'s, what reads it told then.
fn NodeWay::go(self : NodeWay, n : @view.View, to : Double, spec : Spec) -> Unit {
  if self.way.target() == to {
    return
  }
  (self.due)()
  self.way.go(to, spec, at=n.cause_at())
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(@signals.untracked(fn() { self.ended.get() }) + 1) })
  } else {
    fn() {  }
  }
}

///|
/// On a way from `from` to `to` as `spec` says from the moment `at` (a cause's), as fast as it went at that moment on
/// the way it was on (its place carried over into the new terms: `from`), its end a moment of `n`'s.
fn NodeWay::put_at(self : NodeWay, n : @view.View, from : Double, to : Double, spec : Spec, at : Double) -> Unit {
  (self.due)()
  let (_, v) = self.way.at(at)
  self.way.put(from)
  self.way.go(to, spec, at~, velocity=v)
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(@signals.untracked(fn() { self.ended.get() }) + 1) })
  } else {
    fn() {  }
  }
}

///|
/// Where it is as `n` is drawn: at the moment it is drawn at while it goes, where it went once it is there.
fn NodeWay::shown(self : NodeWay, n : @view.View) -> Double {
  self.way.said()
  self.ended.get() |> ignore
  if self.way.goes_at(n.logic_at()) {
    self.way.value_at(n.drawn_at())
  } else {
    self.way.target()
  }
}
