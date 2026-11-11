///|
/// The rects of the instances `a` keeps of a frame of 400 × 300 points (Damage::occlude), each x y w h kind.
fn kept(d : @damage.Damage, a : FixedArray[Double]) -> Array[(Double, Double, Double, Double, Int)] {
  let (s, n) = d.occlude(a, a.length() / 60, 400.0, 300.0)
  Array::makei(n, fn(k) { (s[k * 60], s[k * 60 + 1], s[k * 60 + 2], s[k * 60 + 3], s[k * 60 + 5].to_int()) })
}

///|
/// A sheet from the foot over rows: its top corners round.
fn sheet_over_rows() -> FixedArray[Double] {
  let a = frame([
    (0.0, 0.0, 400.0, 300.0, 0),
    (0.0, 40.0, 400.0, 50.0, 0),
    (16.0, 60.0, 100.0, 10.0, 1),
    (0.0, 140.0, 400.0, 50.0, 0),
    (16.0, 160.0, 100.0, 10.0, 1),
    (0.0, 240.0, 400.0, 50.0, 0),
    (0.0, 100.0, 400.0, 200.0, 0),
  ])
  for j in 36..<38 {
    a[6 * 60 + j] = 16.0
  }
  a
}

///|
test "what an opaque sheet covers wholly is left out, what its round corners might show kept" {
  let d = @damage.Damage::new()
  // (the rows from 140 on under it; the ground under it only in part, the row at 40 above it)
  debug_inspect(
    kept(d, sheet_over_rows()),
    content=(
      #|[
      #|  (0, 0, 400, 300, 0),
      #|  (0, 40, 400, 50, 0),
      #|  (16, 60, 100, 10, 1),
      #|  (0, 100, 400, 200, 0),
      #|]
    ),
  )
  // (a row reaching under the band its top corners curve in, kept)
  let a = sheet_over_rows()
  a[3 * 60 + 1] = 120.0
  debug_inspect(
    kept(d, a),
    content=(
      #|[
      #|  (0, 0, 400, 300, 0),
      #|  (0, 40, 400, 50, 0),
      #|  (16, 60, 100, 10, 1),
      #|  (0, 120, 400, 50, 0),
      #|  (0, 100, 400, 200, 0),
      #|]
    ),
  )
}

///|
test "nothing hidden: the frame itself" {
  let d = @damage.Damage::new()
  let a = frame([(0.0, 0.0, 100.0, 100.0, 0), (200.0, 0.0, 100.0, 100.0, 0)])
  let (s, n) = d.occlude(a, 2, 400.0, 300.0)
  assert_true(physical_equal(s, a))
  assert_eq(n, 2)
}

///|
test "a cover not wholly opaque hides nothing" {
  let d = @damage.Damage::new()
  let cases : Array[(Int, Double)] = [(11, 0.5), (32, 0.1), (53, 4.0), (22, 10.0), (7, 3.0)]
  for c in cases {
    let a = sheet_over_rows()
    a[6 * 60 + c.0] = c.1
    assert_eq(kept(d, a).length(), 7)
  }
  // (a sheet of another kind: an image, a shadow)
  let a = sheet_over_rows()
  a[6 * 60 + 5] = 4.0
  assert_eq(kept(d, a).length(), 7)
}

///|
test "a border not opaque: only what is inside it covered" {
  let d = @damage.Damage::new()
  let a = frame([(10.0, 10.0, 100.0, 100.0, 0), (0.0, 0.0, 200.0, 200.0, 0)])
  a[60 + 6] = 20.0
  a[60 + 15] = 0.5
  assert_eq(kept(d, a).length(), 2)
  a[60 + 6] = 4.0
  assert_eq(kept(d, a).length(), 1)
}

///|
test "covered only as far as its clip" {
  let d = @damage.Damage::new()
  let a = sheet_over_rows()
  a[6 * 60 + 19] = 200.0
  // (the row at 240 below the sheet's clip, seen)
  assert_eq(kept(d, a).map(fn(r) { r.1 }), [0.0, 40.0, 60.0, 240.0, 100.0])
}

///|
test "glass after what covers sees what it covers: nothing before the glass left out by what is after it" {
  let d = @damage.Damage::new()
  let a = frame([
    (0.0, 140.0, 400.0, 50.0, 0),
    (20.0, 120.0, 200.0, 100.0, 5),
    (0.0, 100.0, 400.0, 200.0, 0),
  ])
  a[60 + 20] = -1.0
  assert_eq(kept(d, a).length(), 3)
  // (covered before the glass: left out)
  let b = frame([
    (0.0, 140.0, 400.0, 50.0, 0),
    (0.0, 100.0, 400.0, 200.0, 0),
    (20.0, 120.0, 200.0, 100.0, 5),
  ])
  assert_eq(kept(d, b).map(fn(r) { r.4 }), [0, 5])
}

///|
test "a native view's hole, a stream and the pieces of shapes are never left out" {
  let d = @damage.Damage::new()
  let a = frame([
    (0.0, 140.0, 400.0, 50.0, 9),
    (0.0, 140.0, 400.0, 50.0, 4),
    (0.0, 140.0, 400.0, 50.0, 11),
    (0.0, 100.0, 400.0, 200.0, 0),
    (0.0, 0.0, 0.0, 0.0, 12),
  ])
  a[60 + 20] = @damage.stream_tex_base
  assert_eq(kept(d, a).map(fn(r) { r.4 }), [9, 4, 0, 12])
}

///|
test "a header: left out with its group's room where all its group reaches is covered, else kept" {
  let d = @damage.Damage::new()
  d.group_set(7, frame([(0.0, 0.0, 400.0, 40.0, 0), (16.0, 10.0, 100.0, 10.0, 1)]), 2)
  let head = fn(id : Int, y : Double) -> FixedArray[Double] {
    let a = frame([
      (0.0, y, 0.0, 0.0, 13),
      (0.0, 0.0, 0.0, 0.0, 0),
      (0.0, 0.0, 0.0, 0.0, 0),
      (0.0, 100.0, 400.0, 200.0, 0),
    ])
    a[12] = id.to_double()
    a[14] = 3.0
    a[16] = 0.0
    a[18] = 0.0
    a[19] = 0.0
    a
  }
  assert_eq(kept(d, head(7, 150.0)).map(fn(r) { r.4 }), [0])
  assert_eq(kept(d, head(7, 80.0)).length(), 4)
  // (one not known: kept, and what is before it seen through it)
  assert_eq(kept(d, head(8, 150.0)).length(), 4)
  // (a group holding glass: kept where seen, what is under it seen by it)
  d.group_set(9, frame([(0.0, 0.0, 400.0, 40.0, 5)]), 1)
  let a = frame([
    (0.0, 140.0, 400.0, 20.0, 0),
    (0.0, 0.0, 0.0, 0.0, 13),
    (0.0, 0.0, 0.0, 0.0, 0),
    (0.0, 100.0, 400.0, 200.0, 0),
  ])
  a[60 + 12] = 9.0
  a[60 + 14] = 2.0
  a[60 + 1] = 20.0
  for j in 16..<20 {
    a[60 + j] = 0.0
  }
  assert_eq(kept(d, a).length(), 4)
}

///|
test "an opaque fill less than an eighth of the window covers nothing" {
  let d = @damage.Damage::new()
  let a = frame([(10.0, 10.0, 20.0, 20.0, 0), (0.0, 0.0, 100.0, 100.0, 0)])
  assert_eq(kept(d, a).length(), 2)
  a[60 + 2] = 160.0
  assert_eq(kept(d, a).length(), 1)
}

///|
test "a frame that moves only its headers is left out of as all of it asked again would be" {
  // (a row's header over a list's ground, a sheet over the foot of it, the header moved under the sheet and out again,
  // a header before the sheet and one after it)
  let groups = fn(d : @damage.Damage) {
    d.group_set(7, frame([(0.0, 0.0, 400.0, 40.0, 0), (16.0, 10.0, 100.0, 10.0, 1)]), 2)
    d.group_set(8, frame([(0.0, 0.0, 400.0, 20.0, 0)]), 1)
  }
  let at = fn(y : Double, z : Double) -> FixedArray[Double] {
    let a = frame([
      (0.0, 0.0, 400.0, 300.0, 0),
      (0.0, y, 0.0, 0.0, 13),
      (0.0, 0.0, 0.0, 0.0, 0),
      (0.0, 0.0, 0.0, 0.0, 0),
      (0.0, 100.0, 400.0, 200.0, 0),
      (0.0, z, 0.0, 0.0, 13),
      (0.0, 0.0, 0.0, 0.0, 0),
    ])
    a[60 + 12] = 7.0
    a[60 + 14] = 3.0
    a[5 * 60 + 12] = 8.0
    a[5 * 60 + 14] = 2.0
    for o in [60, 5 * 60] {
      a[o + 16] = 0.0
      a[o + 17] = 0.0
      a[o + 18] = 0.0
      a[o + 19] = 0.0
    }
    a
  }
  let d = @damage.Damage::new()
  groups(d)
  let shown = fn(s : FixedArray[Double], n : Int) {
    Array::makei(n, fn(k) { (s[k * 60 + 1], s[k * 60 + 5].to_int()) })
  }
  ignore(d.occlude(at(20.0, 120.0), 7, 400.0, 300.0))
  for p in [(150.0, 120.0), (160.0, 130.0), (60.0, 150.0), (40.0, 40.0), (200.0, 10.0)] {
    let a = at(p.0, p.1)
    let fresh = @damage.Damage::new()
    groups(fresh)
    let (s0, n0) = fresh.occlude(a, 7, 400.0, 300.0)
    let moved = d.occlude_moved(a, 7, 400.0, 300.0, [1, 5]).map(fn(o) { shown(o.0, o.1) })
    assert_eq(moved, Some(shown(s0, n0)), msg="\{Repr(p)}")
  }
  // (a group set again: asked whole)
  groups(d)
  assert_true(d.occlude_moved(at(20.0, 120.0), 7, 400.0, 300.0, [1, 5]) is None)
}
