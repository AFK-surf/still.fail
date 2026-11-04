// Things of the window's tree going together from where their cause found them to where it lays them out (Motion's
// `layout` and its shapes' `reshape`, FLIP set off by what moved them, made once): at the moment what they move for
// changes, each from where it is drawn then (on a way it was on, where that has it, as fast) to where that change lays
// it out, as a way together as long as the furthest of them goes (a Move over that far: one cause, one length); drawn
// so, pressed where they are laid out. Moved by nothing they move for (a window made narrower), where they are laid out
// at once, their own ways going on from there.

///|
/// One of what goes together (MoveGroup): its node, whether its ground changes shape with it (reshape) or it only goes
/// (layout), and its ways, in the window's terms or its scope's: where it is across and down, how wide and how tall (drawn off by
/// its own way on top of what holds it going drawn off with it, as an old view's are); and where each goes as the way
/// it is on was set off.
priv struct Mover {
  v : @view.View
  reshapes : Bool
  within : @view.View?
  ways : Array[NodeWay]
  to : Array[Double]
  /// present before a later cause; its birth has no old position to move from
  mut can_move : Bool
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
/// `within`: its place relative to this ancestor, whose own movement carries it (the old view's motion scope).
/// Its layout changing inside that ancestor is then animated once, without counting the ancestor's move again.
pub fn MoveGroup::add(self : MoveGroup, v : @view.View, reshapes? : Bool = false, within? : @view.View) -> Unit {
  let m = { v, reshapes, within, ways: Array::makei(4, fn(_) { NodeWay::new(0.0) }), to: [0.0, 0.0, 0.0, 0.0], can_move: false, gone: false }
  // A structural watcher may make this node before the group's watcher sees the same change. It has no place
  // before that change. Publish it now so ground_of's readers follow its ways, but only later causes can move it.
  self.movers.push(m)
  @signals.after_flush(fn() { m.can_move = true })
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
/// Its laid place in the group's coordinates: in the window, or relative to the ancestor carrying it.
fn Mover::place(self : Mover, before : Bool) -> Array[Double] {
  let (x, y, w, h) = if before { self.v.placed_window_now() } else { self.v.laid_window_now() }
  let (ox, oy) = match self.within {
    Some(p) => {
      let (px, py, _, _) = if before { p.placed_window_now() } else { p.laid_window_now() }
      (px, py)
    }
    None => (0.0, 0.0)
  }
  [x - ox, y - oy, w, h]
}

///|
/// The changing ground of `v` in this group, followed by what stands on it or leaves room for it. Read from the
/// same ways that paint it, so a dependent property follows its frames and stops reading the clock as it arrives.
pub fn MoveGroup::ground_of(self : MoveGroup, v : @view.View) -> (Double, Double, Double, Double) {
  match self.movers.iter().find_first(fn(m) { !m.gone && m.v.id() == v.id() && m.reshapes }) {
    Some(m) => {
      let (x, y) = m.off()
      (x, y, m.ways[2].shown(v) - m.to[2], m.ways[3].shown(v) - m.to[3])
    }
    None => (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// The difference between a member's box on its way and its laid box (x, y, width, height). For a member that
/// only moves, its changing size is the room its contents have reached, without scaling or clipping them here.
/// Contents may grow whole into that room while their neighbours make way for them.
pub fn MoveGroup::box_change(self : MoveGroup, v : @view.View) -> (Double, Double, Double, Double) {
  match self.movers.iter().find_first(fn(m) { !m.gone && m.v.id() == v.id() }) {
    Some(m) => {
      let (x, y) = m.off()
      (x, y, m.ways[2].shown(v) - m.to[2], m.ways[3].shown(v) - m.to[3])
    }
    None => (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// What the group moves for changed: at that moment, each from where it is drawn then (on its way, where that has it)
/// to where the change lays it out, a way together as long as the furthest goes.
fn MoveGroup::set_off(self : MoveGroup) -> Unit {
  let at = self.owner.cause_at()
  let movers = self.movers.filter(fn(m) { m.can_move && !m.gone && m.v.alive() })
  // (where each stands in the window as the change comes: where it is laid out now (moved by nothing it moves for
  // meanwhile, too), off that as far as its way has it then; how big, as its ground is drawn)
  let from = movers.map(fn(m) {
    let laid = m.place(true)
    Array::makei(4, fn(k) {
      let way = m.ways[k].way
      if way.goes_at(at) {
        laid[k] + way.value_at(at) - m.to[k]
      } else {
        laid[k]
      }
    })
  })
  // The same cause can replace children (pick/show/each) after this group's watcher runs. Keep where they stood
  // now, but measure the destination only once that whole change has been committed. Property pulls alone cannot
  // see children whose structure's watcher has not run yet.
  @signals.after_flush(fn() { self.set_off_from(movers, from, at) })
}

///|
fn MoveGroup::set_off_from(self : MoveGroup, before : Array[Mover], places : Array[Array[Double]], at : Double, spec? : Spec) -> Unit {
  guard self.owner.alive() else { return }
  let movers : Array[Mover] = []
  let from : Array[Array[Double]] = []
  for i, m in before {
    if !m.gone && m.v.alive() {
      movers.push(m)
      from.push(places[i])
    }
  }
  // (where the change lays each out in the window, as of this moment: laid out once for all of them)
  let to = movers.map(fn(m) { m.place(false) })
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
  let spec = spec.unwrap_or(self.spec).over(far)
  for i, m in movers {
    for k in 0..<4 {
      // (each way in the window's terms: from where it is drawn now, as fast as it goes now, to where it is laid out)
      m.ways[k].put_at(m.v, from[i][k], to[i][k], spec, at)
      m.to[k] = to[i][k]
    }
  }
}

///|
/// Continue these members from handed-over rectangles in their group's coordinates when their owner is made in
/// another place. The handover is the cause; the destination is measured after it has made all its children.
pub fn MoveGroup::arrive_from(
  self : MoveGroup,
  places : Array[(@view.View, (Double, Double, Double, Double))],
  spec~ : Spec,
) -> Unit {
  let at = self.owner.cause_at()
  let members : Array[Mover] = []
  let from : Array[Array[Double]] = []
  for (v, r) in places {
    match self.movers.iter().find_first(fn(m) { !m.gone && m.v.id() == v.id() }) {
      Some(m) => {
        members.push(m)
        from.push([r.0, r.1, r.2, r.3])
      }
      None => ()
    }
  }
  @signals.after_flush(fn() { self.set_off_from(members, from, at, spec~) })
}

///|
/// A member's window rectangle, including its own ways, at a declared moment, kept for an action handing it to
/// another owner. Its last laid rectangle and its ways survive the node being let go; a handover between frames
/// samples the same way.
pub fn MoveGroup::position(self : MoveGroup, v : @view.View) -> (Double) -> (Double, Double, Double, Double)? {
  let laid : Ref[(Double, Double, Double, Double)?] = Ref(None)
  v.reacts(fn() { v.laid_window_told() }, fn(r) { if r is Some(_) { laid.val = r } })
  let mover = self.movers.iter().find_first(fn(m) { !m.gone && m.v.id() == v.id() })
  fn(at) {
    match (laid.val, mover) {
      (Some(r), Some(m)) => {
        let x = r.0 + m.ways[0].way.value_at(at) - m.to[0]
        let y = r.1 + m.ways[1].way.value_at(at) - m.to[1]
        let w = if m.reshapes { r.2 + m.ways[2].way.value_at(at) - m.to[2] } else { r.2 }
        let h = if m.reshapes { r.3 + m.ways[3].way.value_at(at) - m.to[3] } else { r.3 }
        Some((x, y, w, h))
      }
      _ => None
    }
  }
}
