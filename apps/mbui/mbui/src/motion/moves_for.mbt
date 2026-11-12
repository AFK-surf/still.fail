// What moves for one cause in the window's tree (Motion's `layout` and `reshape`, FLIP set off by what moved them,
// made once), as an old view's layout and reshape with the same `by` move, worked out by the same functions
// (reshape_way.mbt): at the moment what they move for changes, each from where the tree drew it then (on a way it
// was on, where that has it) to where that change lays it out, on ways as long as the furthest of them goes (a Move
// over that far: one cause, one length). A shape's ground goes from the shape it showed to the one it is laid out
// in, its corners with it, what it holds laid out as it ends at once; a part goes from where it was drawn to its
// place. Drawn so, pressed where they are laid out; read as they are drawn (the clock while they go, none after
// their declared end), nothing built or laid out again for them. Moved by nothing they move for (a window made
// narrower, a keyboard), where they are laid out at once, their own ways going on from there.

///|
/// A shape of what moves for a cause (Moves::reshapes): its node, whether it goes from where it was with what it
/// holds (`carry`, read as it sets off) and whether it changes shape from its foot; its ground's ways in the window
/// (where it is across and down, how wide and how tall, each going on as fast as it went as it is set off again) and
/// where they went; its corners' way (0 → 1) from the corners it set out from; whether it went with what it holds and
/// how far down a way with what it holds had it (reshape_way's carried_y_from).
priv struct Shape {
  v : @view.View
  carry : () -> Bool
  foot : Bool
  ways : Array[NodeWay]
  mut to : (Double, Double, Double, Double)
  round : NodeWay
  mut from_r : (Double, Double, Double, Double)
  mut carrying : Bool
  mut carried_y : Double
}

///|
/// A part of what moves for a cause (Moves::moves_with): its node, how far off its place it is drawn across and down
/// (each a way to 0), and the shape it is carried on, new in it as that set off with what it holds, with the edges of
/// it it keeps to (reshape_way's carried_edges), told as that is said (at its cause's moment, once it is laid out).
priv struct Part {
  v : @view.View
  x : NodeWay
  y : NodeWay
  ride : @signals.Signal[(Shape, Int)?]
}

///|
/// Whether two rides on a shape (Part's `ride`) are the same: on the same shape by the same edges, or on none.
fn same_ride(a : (Shape, Int)?, b : (Shape, Int)?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some((s, e)), Some((t, f))) => physical_equal(s, t) && e == f
    _ => false
  }
}

///|
/// What moves in the window's tree for one cause (moves_for): its owner, its shapes and its parts.
pub struct Moves {
  priv owner : @view.View
  priv shapes : Array[Shape]
  priv parts : Array[Part]
}

///|
/// What moves in `owner` for the cause `by` reads (any value naming that state: a button's words, a page, whether a
/// composer is open): each shape and part said of it (Moves::reshapes, Moves::moves_with) goes as `spec` says (a Move
/// by default), from the moment `by` changes, from where the tree drew it then. `spec_of`: how it goes by what the cause
/// changed from and to (a composer opened on one clock, gone to another page on another), in place of `spec`;
/// `carry_of`: whether a shape that may go from where it was with what it holds (Moves::reshapes' `carry`) does, by the
/// same (every change, where none is said). What moves for it.
pub fn[T : Eq] moves_for(
  owner : @view.View,
  by : () -> T,
  spec? : Spec = moved(),
  spec_of? : (T, T) -> Spec,
  carry_of? : (T, T) -> Bool,
) -> Moves {
  let m = { owner, shapes: [], parts: [] }
  // (where each stands as a change comes laid out and placed then, whatever changed it before, frame or none)
  owner.laid_before_causes()
  // (done first with what `by` is as it is made, none of it said yet, nothing drawn: nothing goes; each change after it
  // with what it changed from, its own)
  let from : Ref[T?] = Ref(None)
  owner.reacts(by, fn(now) {
    let (way, carries) = match from.val {
      Some(was) =>
        (
          match spec_of {
            Some(f) => f(was, now)
            None => spec
          },
          match carry_of {
            Some(f) => f(was, now)
            None => true
          },
        )
      None => (spec, true)
    }
    from.val = Some(now)
    m.set_off(way, carries)
  })
  m
}

///|
/// Node `v`'s ground changes shape for the cause (an old view's reshape with the same `by`): as it changes, what `v`
/// holds is laid out as it ends at once, and its ground (its colour, glass, shadow, edge and corners) goes from the
/// shape it was drawn in to the one it is laid out in, carrying on from wherever it had got to (View::ground_drawn).
/// `carry` (read as it changes: laid out for another place, a composer gone to another page): it goes from where it
/// was with what it holds, a part new to it then (one never drawn before) carried on its ground, as far from its
/// nearer edges as it is laid out, until it is there. `foot`: it changes shape from its foot, what moved its foot as it
/// changed for nothing it changes for (a keyboard coming as it opens) taken at once, by its ground and by the parts
/// that move for the cause, only their growing up from the foot on its way.
pub fn Moves::reshapes(
  self : Moves,
  v : @view.View,
  carry? : () -> Bool = fn() { false },
  foot? : Bool = false,
) -> Unit {
  let s : Shape = {
    v,
    carry,
    foot,
    ways: Array::makei(4, fn(_) { NodeWay::new(0.0) }),
    to: (0.0, 0.0, 0.0, 0.0),
    round: NodeWay::new(1.0),
    from_r: (0.0, 0.0, 0.0, 0.0),
    carrying: false,
    carried_y: 0.0,
  }
  self.shapes.push(s)
  // (let go with its node: its way's end let go, it no more of what moves)
  v.owns(fn() {
    for w in s.ways {
      (w.due)()
    }
    (s.round.due)()
    match self.shapes.search_by(fn(o) { physical_equal(o, s) }) {
      Some(i) => self.shapes.remove(i) |> ignore
      None => ()
    }
  })
  |> ignore
  v.ground_drawn(By(fn() { s.drawn() })) |> ignore
}

///|
/// Node `v` goes for the cause (an old view's layout with the same `by`): as it changes, from where it was drawn to
/// where the change lays it out, what it holds with it (View::drawn_off). Nothing cuts it on its way: drawn whole.
pub fn Moves::moves_with(self : Moves, v : @view.View) -> Unit {
  let p : Part = { v, x: NodeWay::new(0.0), y: NodeWay::new(0.0), ride: @signals.signal(None, same=same_ride) }
  self.parts.push(p)
  // (made for a change while a shape it is in goes with what it holds, after that set off: carried on its ground, by
  // the edges of it it is nearer as the change lays it out, worked out at that change's moment once it is laid out)
  let at = self.owner.cause_at()
  match self.shapes.iter().find_first(fn(s) { s.carrying && s.round.way.goes_at(at) && held_in(v, s.v) }) {
    Some(s) =>
      v.at_moment(at, fn() { p.ride.set(Some((s, carried_edges(v.laid_window_now(), s.to)))) }) |> ignore
    None => ()
  }
  // (let go with its node: its ways' ends let go, it no more of what moves)
  v.owns(fn() {
    (p.x.due)()
    (p.y.due)()
    match self.parts.search_by(fn(o) { physical_equal(o, p) }) {
      Some(i) => self.parts.remove(i) |> ignore
      None => ()
    }
  })
  |> ignore
  v.drawn_off(By(fn() { p.off() })) |> ignore
}

///|
/// How far over its laid out top the ground of the first of its shapes is drawn now, on its way from the shape it had
/// (less than 0 while it is drawn lower: growing up to it), read as it is drawn: what stands on it moves with it so, in
/// the same frame (an old view's reshaped_over). 0 at rest, and while it goes from where it was with what it holds
/// (`carry`: to another place, not another shape there).
pub fn Moves::ground_over(self : Moves) -> Double {
  guard self.shapes.get(0) is Some(s) else { return 0.0 }
  if s.carrying || !s.goes() {
    0.0
  } else {
    ground_over_drawn(s.to.1, s.ways[1].shown(s.v), s.carried_y, s.round.shown(s.v))
  }
}

///|
/// Whether all it set off for its cause is where it went: its declared end come (each way's end a moment of its
/// node's timeline), followed: told as it sets off and at that moment, nothing watched meanwhile. Never set off: it is.
pub fn Moves::over(self : Moves) -> Bool {
  self.shapes.iter().all(fn(s) { !s.goes() }) &&
  self.parts.iter().all(fn(p) { !p.x.goes(p.v) && !p.y.goes(p.v) })
}

///|
/// How a shape's ground is drawn now: on its way, from the shape it set out from to the one it went to, as round as
/// it goes from the corners it set out from to those it is said to have; as it is laid out once it is there.
fn Shape::drawn(self : Shape) -> @view.GroundShape {
  if !self.goes() {
    return @view.ground_as_laid
  }
  let to = self.to
  let (x, y, w, h) = self.shown()
  let to_r = corners_in(@signals.untracked(fn() { self.v.corners_said() }), to.2, to.3)
  let p = self.round.shown(self.v)
  { dx: x - to.0, dy: y - to.1, dw: w - to.2, dh: h - to.3, corners: Some(corners_mix(self.from_r, to_r, p)) }
}

///|
/// Whether its ground is on its way (its edges or its corners), followed: told as it sets off and at each way's end.
fn Shape::goes(self : Shape) -> Bool {
  // (each read: what reads it told at whichever ends last)
  let edges = self.ways.map(fn(w) { w.goes(self.v) })
  self.round.goes(self.v) || edges.iter().any(fn(g) { g })
}

///|
/// Where its ground is drawn now in the window: each edge where its way has it.
fn Shape::shown(self : Shape) -> (Double, Double, Double, Double) {
  (self.ways[0].shown(self.v), self.ways[1].shown(self.v), self.ways[2].shown(self.v), self.ways[3].shown(self.v))
}

///|
/// Whether its ground was on its way at moment `at` (its edges or its corners).
fn Shape::goes_at(self : Shape, at : Double) -> Bool {
  self.round.way.goes_at(at) || self.ways.iter().any(fn(w) { w.way.goes_at(at) })
}

///|
/// Where its ground was drawn at moment `at` in the window, its ways' (laid out as they went to, `to`).
fn Shape::at(self : Shape, at : Double) -> (Double, Double, Double, Double) {
  let k = fn(i : Int) { self.ways[i].way.value_at(at) }
  (k(0), k(1), k(2), k(3))
}

///|
/// How far a part is drawn off its place now: on the ground it is carried on while that is on its way, else on its
/// own ways.
fn Part::off(self : Part) -> (Double, Double) {
  match self.ride.get() {
    Some((s, e)) => if s.goes() { return carried_on(s.shown(), s.to, e) }
    None => ()
  }
  (self.x.shown(self.v), self.y.shown(self.v))
}

///|
/// Whether node `v` is in node `of` (or is it).
fn held_in(v : @view.View, of : @view.View) -> Bool {
  let mut at = Some(v)
  while true {
    match at {
      Some(n) => {
        if n.id() == of.id() {
          return true
        }
        at = n.parent()
      }
      None => return false
    }
  }
  false
}

///|
/// What it moves for changed: at that moment, each shape from the shape it was drawn in and each part from where it
/// was drawn (on its way, where that has it) to where the change lays it out, as an old view's layout and reshape
/// set off in the frame their cause changed (layer.mbt's layout_entry, by the same functions), on ways as long as the
/// furthest goes. What was never drawn has nowhere to go from: where it is laid out (carried on a shape going with what
/// it holds, if it is in one).
fn Moves::set_off(self : Moves, spec : Spec, carries : Bool) -> Unit {
  let at = self.owner.cause_at()
  let shapes = self.shapes.filter(fn(s) { s.v.alive() && s.v.was_placed() })
  let parts = self.parts.filter(fn(p) { p.v.alive() })
  // (where each stood in the window as the change came, and where the change lays it out, as of this moment: laid out
  // once for all of them)
  let shapes_at = shapes.map(fn(s) { (s.v.placed_window_now(), s.v.laid_window_now()) })
  let parts_at = parts.map(fn(p) {
    if p.v.was_placed() {
      Some((p.v.placed_window_now(), p.v.laid_window_now()))
    } else {
      None
    }
  })
  let mut most = 0.0
  // shapes first: what moved a foot for nothing it changes for, which the parts take at once (reshape's `foot`)
  let mut foot = 0.0
  let set : Array[(Shape, (Double, Double, Double, Double), (Double, Double, Double, Double))] = []
  for i, s in shapes {
    let (placed, laid) = shapes_at[i]
    let carry = carries && @signals.untracked(s.carry)
    // (where its ground was drawn as the change came: as far off where it stood as its ways had it off where they
    // went, moved since by what holds it; how far its corners had got)
    let p0 = s.round.way.value_at(at)
    let (gx, gy, gw, gh) = if s.goes_at(at) { shape_held(s.at(at), s.to, placed) } else { placed }
    let moved = if s.foot && !carry { foot_moved_by(placed, laid) } else { 0.0 }
    let g = (gx, gy + moved, gw, gh)
    let far = way_far(
      placed.0 - laid.0,
      placed.1 - laid.1,
      laid.2 - placed.2,
      laid.3 - placed.3,
      shape_far(g, laid),
    )
    if !shape_changed(placed, laid) {
      // (what holds it moved or resized it, or nothing: its way going on as it was, as far off its new shape)
      continue
    }
    most = dmax(most, far)
    if s.foot && !carry {
      foot = moved
    }
    let wr = corners_in(@signals.untracked(fn() { s.v.corners_drawn() }), placed.2, placed.3)
    s.from_r = corners_mix(s.from_r, wr, p0)
    // (what was carried down by a way with what it holds: kept out of what stands on it is told, ground_over)
    s.carried_y = carried_y_from(s.carrying, gy, placed.1, s.carried_y, p0)
    s.carrying = carry
    set.push((s, g, laid))
  }
  // parts: from where each was drawn as the change came (its offset then and where it stood) to its place
  let moving : Array[(Part, Double, Double)] = []
  for i, p in parts {
    match parts_at[i] {
      None => {
        // (never drawn: where it is laid out, carried on the ground of the shape it is in should that go with what
        // it holds)
        let mut ride = None
        for e in set {
          let (s, _, laid) = e
          if s.carrying && held_in(p.v, s.v) {
            ride = Some((s, carried_edges(p.v.laid_window_now(), laid)))
            break
          }
        }
        p.ride.set(ride)
      }
      Some((placed, laid)) => {
        p.ride.set(None)
        let ox = p.x.way.value_at(at)
        let oy = p.y.way.value_at(at)
        let dx = placed.0 - laid.0
        let dy = placed.1 - laid.1
        let far = way_far(ox + dx, oy + dy + foot, laid.2 - placed.2, laid.3 - placed.3, 0.0)
        if dx.abs() <= 0.5 && dy.abs() <= 0.5 {
          // (not moved: its own way going on as it was)
          continue
        }
        most = dmax(most, far)
        moving.push((p, ox + dx, oy + (dy + foot)))
      }
    }
  }
  // (as long as the furthest goes: a Move said for one way as long as that, any other spec as it is)
  let spec = if spec.way_said() { spec } else { spec.over(most) }
  for e in set {
    let (s, g, laid) = e
    // (each edge from where it was drawn, as fast as it went then, to where it is laid out; its corners from none of
    // their way)
    let from = [g.0, g.1, g.2, g.3]
    let to = [laid.0, laid.1, laid.2, laid.3]
    // (where it goes said before its ways are: what reads them reads it with them)
    s.to = laid
    for k in 0..<4 {
      s.ways[k].put_at(s.v, from[k], to[k], spec, at)
    }
    s.round.go_from(s.v, 0.0, 1.0, spec, at)
  }
  for m in moving {
    let (p, fx, fy) = m
    p.x.put_at(p.v, fx, 0.0, spec, at)
    p.y.put_at(p.v, fy, 0.0, spec, at)
  }
}
