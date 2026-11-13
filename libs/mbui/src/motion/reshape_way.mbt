// A shape changing for its cause (reshape), worked out from what it was and what it is laid out as, nothing kept:
// where its ground sets out from, where it is drawn on its way, how far its foot moved, how far what is carried on it
// is drawn off, how far it goes. What draws an old view's shape (layer.mbt's layout_entry) and what draws a node's
// each keep their own state and step their own progress, and both work it out by these: one shape's way, whatever
// draws it. A shape is (x, y, w, h) in the terms of what it is placed in (its list's content, its scope, the window).

///|
/// Corners `r` (top left, then round it) as a box `w` by `h` draws them: each no more than half its shorter side.
fn corners_in(r : (Double, Double, Double, Double), w : Double, h : Double) -> (Double, Double, Double, Double) {
  let half = dmin(w, h) / 2.0
  (dmin(r.0, half), dmin(r.1, half), dmin(r.2, half), dmin(r.3, half))
}

///|
/// Corners `a` gone `p` of the way to `b`, each its own.
fn corners_mix(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  (a.0 + (b.0 - a.0) * p, a.1 + (b.1 - a.1) * p, a.2 + (b.2 - a.2) * p, a.3 + (b.3 - a.3) * p)
}

///|
/// Shape `g` gone `p` of the way to shape `to`, each of its edges its own: where a ground set out from `g` for a shape
/// laid out as `to` is drawn when it has gone `p` of its way.
fn shape_mix(
  g : (Double, Double, Double, Double),
  to : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  (g.0 + (to.0 - g.0) * p, g.1 + (to.1 - g.1) * p, g.2 + (to.2 - g.2) * p, g.3 + (to.3 - g.3) * p)
}

///|
/// Where a ground set out from shape `g` for shape `to` is drawn `p` of its way there, `off` from the terms its shapes
/// are in (where it is laid out in the window less where it is laid out in those terms): where it is drawn and how big.
fn ground_drawn_at(
  off : (Double, Double),
  g : (Double, Double, Double, Double),
  to : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  (
    off.0 + g.0 + (to.0 - g.0) * p,
    off.1 + g.1 + (to.1 - g.1) * p,
    g.2 + (to.2 - g.2) * p,
    g.3 + (to.3 - g.3) * p,
  )
}

///|
/// How far the foot of a shape laid out as `was` goes laid out as `now` (down: more than 0): what moved it there for
/// nothing it changes for is taken at once, as its ground sets off from its foot (reshape's `foot`).
fn foot_moved_by(was : (Double, Double, Double, Double), now : (Double, Double, Double, Double)) -> Double {
  now.1 + now.3 - (was.1 + was.3)
}

///|
/// Where a ground on its way from `g`, laid out as `was`, sets out from as what holds it moves or resizes it to `now`
/// for nothing it changes for: as far off its new shape as it was off its old, its way going on as it was.
fn shape_held(
  g : (Double, Double, Double, Double),
  was : (Double, Double, Double, Double),
  now : (Double, Double, Double, Double),
) -> (Double, Double, Double, Double) {
  (g.0 + (now.0 - was.0), g.1 + (now.1 - was.1), g.2 + (now.2 - was.2), g.3 + (now.3 - was.3))
}

///|
/// How far apart shapes `g` and `to` are, the furthest of their edges (a ground's way: as long as that).
fn shape_far(g : (Double, Double, Double, Double), to : (Double, Double, Double, Double)) -> Double {
  dmax(
    dmax((g.0 - to.0).abs(), (g.1 - to.1).abs()),
    dmax((g.0 + g.2 - to.0 - to.2).abs(), (g.1 + g.3 - to.1 - to.3).abs()),
  )
}

///|
/// How far something goes for its cause, the furthest of all it moves: `dx` across and `dy` down, `dw` wider and `dh`
/// taller, and its ground's edges as far as `ground` (shape_far; 0 for what has none of its own on the way): in
/// points, what a Move of it is as long as (Spec::over).
fn way_far(dx : Double, dy : Double, dw : Double, dh : Double, ground : Double) -> Double {
  dmax(dmax(dx.abs(), dy.abs()), dmax(dmax(dh.abs(), dw.abs()), ground))
}

///|
/// Whether a shape laid out as `was` is laid out otherwise as `now`, by more than half a point at any edge.
fn shape_changed(was : (Double, Double, Double, Double), now : (Double, Double, Double, Double)) -> Bool {
  (was.0 - now.0).abs() > 0.5 ||
  (was.1 - now.1).abs() > 0.5 ||
  (was.2 - now.2).abs() > 0.5 ||
  (was.3 - now.3).abs() > 0.5
}

///|
/// How far down a ground is drawn off its laid shape by a way to another place it was on (`carry`) as it set off anew
/// from `gy`, laid out at `was_y`, `p0` of its way gone: all of where it was drawn, if it was carried; else what was
/// left of such a way it was on (`was_carried_y`, set off before), as far as `p0` had left of it.
fn carried_y_from(
  was_carry : Bool,
  gy : Double,
  was_y : Double,
  was_carried_y : Double,
  p0 : Double,
) -> Double {
  if was_carry {
    gy - was_y
  } else {
    was_carried_y * (1.0 - p0)
  }
}

///|
/// How far over its laid out top `y` a ground set out from `gy` is drawn `p` of its way (less than 0: drawn lower), what
/// it was carried down by (`carried_y`) not counted: what stands on it moves with it so (reshaped_over).
fn ground_over(y : Double, gy : Double, carried_y : Double, p : Double) -> Double {
  (y - gy + carried_y) * (1.0 - p)
}

///|
/// How far over its laid out top `y` a ground drawn down at `drawn_y` is drawn (less than 0: drawn lower), what it was
/// carried down by (`carried_y`, as far as `p` of its corners' way has left of it) not counted: ground_over's, where
/// each of the ground's edges goes its own way (moves_for's shapes, each edge going on as fast as it went).
fn ground_over_drawn(y : Double, drawn_y : Double, carried_y : Double, p : Double) -> Double {
  y - drawn_y + carried_y * (1.0 - p)
}

///|
/// How far a node carried on a ground (`edges`: 1, its right rather than its left; 2, its foot rather than its top) is
/// drawn off where it is laid out, the ground set out from `g` for `to`, `p` of its way gone: as far from the edges of
/// the ground it keeps to as it is laid out from the shape's.
fn carried_off(
  g : (Double, Double, Double, Double),
  to : (Double, Double, Double, Double),
  p : Double,
  edges : Int,
) -> (Double, Double) {
  carried_on(shape_mix(g, to, p), to, edges)
}

///|
/// How far a node carried on a ground drawn as `drawn` (`edges` as carried_off has them) is drawn off where it is laid
/// out, the shape laid out as `to`.
fn carried_on(
  drawn : (Double, Double, Double, Double),
  to : (Double, Double, Double, Double),
  edges : Int,
) -> (Double, Double) {
  let (gx, gy, gw, gh) = drawn
  (
    if edges % 2 == 1 {
      gx + gw - to.0 - to.2
    } else {
      gx - to.0
    },
    if edges >= 2 {
      gy + gh - to.1 - to.3
    } else {
      gy - to.1
    },
  )
}

///|
/// Which edges of a shape laid out at `outer` a node laid out at `inner` in it keeps to, carried on its ground: 1 its
/// right (its middle right of the shape's), 2 its foot (its middle below the shape's), both 3, none 0 (carried_off).
fn carried_edges(inner : (Double, Double, Double, Double), outer : (Double, Double, Double, Double)) -> Int {
  (if inner.0 + inner.2 / 2.0 > outer.0 + outer.2 / 2.0 { 1 } else { 0 }) +
  (if inner.1 + inner.3 / 2.0 > outer.1 + outer.3 / 2.0 { 2 } else { 0 })
}
