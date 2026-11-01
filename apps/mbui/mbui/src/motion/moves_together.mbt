// Things of the window's tree going together from where their cause found them to where it lays them out (Motion's
// `layout` and its shapes' `reshape`, FLIP set off by what moved them, made once): at the moment what they move for
// changes, each from where it is drawn then (on a way it was on, where that has it, as fast) to where that change lays
// it out, as a way together as long as the furthest of them goes (a Move over that far: one cause, one length); drawn
// so, pressed where they are laid out. Moved by nothing they move for (a window made narrower), where they are laid out
// at once, their own ways going on from there.

///|
/// One of what goes together (MoveGroup): its node, whether its ground changes shape with it (reshape) or it only goes
/// (layout), and its ways, each in the window's terms: where it is across and down, how wide and how tall (drawn off by
/// its own way on top of what holds it going drawn off with it, as an old view's are); and where each goes as the way
/// it is on was set off.
priv struct Mover {
  v : @view.View
  reshapes : Bool
  ways : Array[NodeWay]
  to : Array[Double]
  /// let go (its node let go): going no more, its way counted for nothing
  mut gone : Bool
}

///|
/// What goes together for one cause (moves_together): its movers, the spec of their way, and the node whose timeline
/// it is on.
pub struct MoveGroup {
  priv owner : @view.View
  priv spec : Spec
  priv movers : Array[Mover]
}

///|
/// What goes together in `owner` for the cause `by` reads (any value naming that state: a button's words, a page): each
/// node said to (MoveGroup::add) goes as `spec` says (a Move by default), from the moment `by` changes. The group.
pub fn[T : Eq] moves_together(owner : @view.View, by : () -> T, spec? : Spec = move()) -> MoveGroup {
  let group = { owner, spec, movers: [] }
  // (where each stands as a change comes laid out and placed then, whatever changed it before, frame or none)
  owner.laid_before_causes()
  let first = Ref(true)
  owner.reacts(by, fn(_) {
    if first.val {
      first.val = false
      return
    }
    group.set_off()
  })
  group
}

///|
/// Node `v` going with the group, its ground changing shape with it where `reshapes` (Motion's reshape: all of its
/// ground, what it holds where its layout puts it, each of it said to go itself), else only going (Motion's layout).
pub fn MoveGroup::add(self : MoveGroup, v : @view.View, reshapes? : Bool = false) -> Unit {
  let m = { v, reshapes, ways: Array::makei(4, fn(_) { NodeWay::new(0.0) }), to: [0.0, 0.0, 0.0, 0.0], gone: false }
  self.movers.push(m)
  // (let go with its node: its ways' ends let go, it no more of the group)
  v.owns(fn() {
    m.gone = true
    for w in m.ways {
      (w.due)()
    }
    match self.movers.search_by(fn(o) { physical_equal(o, m) }) {
      Some(i) => self.movers.remove(i) |> ignore
      None => ()
    }
  })
  |> ignore
  if reshapes {
    // (its ground a rect on its way in the window, from the shape it had to the one it is laid out in; what it holds
    // where its layout puts it, each said to go itself: an old view's reshape)
    v.ground_drawn(By(fn() {
      let (x, y) = m.off()
      (x, y, m.ways[2].shown(v) - m.to[2], m.ways[3].shown(v) - m.to[3])
    }))
    |> ignore
  } else {
    // (drawn off where it is laid out as far as its way has it off where it goes in the window, on top of what holds it
    // drawn off with it, as an old view's layout draws a node going in one going: layer.mbt's dx of its node_rect)
    v.drawn_off(By(fn() { m.off() }))
    |> ignore
  }
}

///|
/// How far a mover is drawn off where it goes, in the window's terms, as it is drawn.
fn Mover::off(self : Mover) -> (Double, Double) {
  (self.ways[0].shown(self.v) - self.to[0], self.ways[1].shown(self.v) - self.to[1])
}

///|
/// What the group moves for changed: at that moment, each from where it is drawn then (on its way, where that has it)
/// to where the change lays it out, a way together as long as the furthest goes.
fn MoveGroup::set_off(self : MoveGroup) -> Unit {
  let at = self.owner.cause_at()
  let movers = self.movers.filter(fn(m) { !m.gone && m.v.alive() })
  // (where each stands in the window as the change comes: where it is laid out now (moved by nothing it moves for
  // meanwhile, too), off that as far as its way has it then; how big, as its ground is drawn)
  let from = movers.map(fn(m) {
    let (x, y, w, h) = m.v.placed_window_now()
    let laid = [x, y, w, h]
    Array::makei(4, fn(k) {
      let way = m.ways[k].way
      if way.goes_at(at) {
        laid[k] + way.value_at(at) - m.to[k]
      } else {
        laid[k]
      }
    })
  })
  // (where the change lays each out in the window, as of this moment: laid out once for all of them)
  let to = movers.map(fn(m) {
    let (x, y, w, h) = m.v.laid_window_now()
    [x, y, w, h]
  })
  // (as long as the furthest goes: the most any of them goes across or down, grows or shrinks, or, changing shape, any
  // of its edges goes: an old view's layout and reshape, layer.mbt's `far`)
  let mut far = 0.0
  for i, m in movers {
    let (f, t) = (from[i], to[i])
    let (dx, dy) = ((t[0] - f[0]).abs(), (t[1] - f[1]).abs())
    let (dw, dh) = ((t[2] - f[2]).abs(), (t[3] - f[3]).abs())
    far = dmax(far, dmax(dmax(dx, dy), dmax(dw, dh)))
    if m.reshapes {
      let right = (t[0] + t[2] - f[0] - f[2]).abs()
      let foot = (t[1] + t[3] - f[1] - f[3]).abs()
      far = dmax(far, dmax(right, foot))
    }
  }
  let spec = self.spec.over(far)
  for i, m in movers {
    for k in 0..<4 {
      // (each way in the window's terms: from where it is drawn now, as fast as it goes now, to where it is laid out)
      m.ways[k].put_at(m.v, from[i][k], to[i][k], spec, at)
      m.to[k] = to[i][k]
    }
  }
}
