///|
/// Instances as scene.mbt paints them: each a rect of `kind`, opaque white, clipped to all of a 400 × 300 window.
fn frame(rects : Array[(Double, Double, Double, Double, Int)]) -> FixedArray[Double] {
  let a = FixedArray::make(rects.length() * 56, 0.0)
  for k, r in rects {
    let o = k * 56
    let (x, y, w, h, kind) = r
    a[o] = x
    a[o + 1] = y
    a[o + 2] = w
    a[o + 3] = h
    a[o + 5] = kind.to_double()
    for j in 8..<12 {
      a[o + j] = 1.0
    }
    a[o + 16] = 0.0
    a[o + 17] = 0.0
    a[o + 18] = 1.0e9
    a[o + 19] = 1.0e9
  }
  a
}

///|
fn copy(a : FixedArray[Double]) -> FixedArray[Double] {
  let b = FixedArray::make(a.length(), 0.0)
  a.blit_to(b, len=a.length())
  b
}

///|
/// A damage that has seen `a`.
fn seen(a : FixedArray[Double]) -> @damage.Damage {
  let d = @damage.Damage::new()
  ignore(d.next(a, a.length() / 56, 400.0, 300.0, 2.0, 1.0, 1.0, 1.0))
  d
}

///|
fn next(d : @damage.Damage, a : FixedArray[Double]) -> Array[(Double, Double, Double, Double)] {
  d.next(a, a.length() / 56, 400.0, 300.0, 2.0, 1.0, 1.0, 1.0)
}

///|
test "the first frame whole, the same again none" {
  let a = frame([(10.0, 10.0, 20.0, 20.0, 0)])
  let d = @damage.Damage::new()
  inspect(next(d, a), content="[(0, 0, -1, -1)]")
  inspect(next(d, a), content="[]")
  d.forget()
  inspect(next(d, a), content="[(0, 0, -1, -1)]")
}

///|
test "an instance that changed: where it is, its edge's reach round it" {
  let a = frame([(0.0, 0.0, 400.0, 300.0, 0), (100.0, 50.0, 20.0, 10.0, 0)])
  let d = seen(a)
  let b = copy(a)
  b[56 + 8] = 0.5
  inspect(next(d, b), content="[(98, 48, 24, 14)]")
}

///|
test "moved: where it was and where it is" {
  let a = frame([(0.0, 0.0, 400.0, 300.0, 0), (100.0, 50.0, 20.0, 10.0, 0)])
  let d = seen(a)
  let b = copy(a)
  b[56] = 130.0
  inspect(next(d, b), content="[(98, 48, 54, 14)]")
}

///|
test "another window, scale or ground: whole" {
  let a = frame([(10.0, 10.0, 20.0, 20.0, 0)])
  let d = seen(a)
  inspect(d.next(a, 1, 401.0, 300.0, 2.0, 1.0, 1.0, 1.0), content="[(0, 0, -1, -1)]")
  inspect(d.next(a, 1, 401.0, 300.0, 3.0, 1.0, 1.0, 1.0), content="[(0, 0, -1, -1)]")
  inspect(d.next(a, 1, 401.0, 300.0, 3.0, 0.0, 1.0, 1.0), content="[(0, 0, -1, -1)]")
  inspect(d.next(a, 1, 401.0, 300.0, 3.0, 0.0, 1.0, 1.0), content="[]")
}

///|
test "another number of instances: the same from the start and the end kept, what is between drawn again" {
  // a ground, a caret shown between two words, then hidden again
  let a = frame([(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 40.0, 16.0, 1), (60.0, 10.0, 40.0, 16.0, 1)])
  let d = seen(a)
  let b = frame([
    (0.0, 0.0, 400.0, 300.0, 0),
    (10.0, 10.0, 40.0, 16.0, 1),
    (52.0, 10.0, 2.0, 16.0, 0),
    (60.0, 10.0, 40.0, 16.0, 1),
  ])
  inspect(next(d, b), content="[(50, 8, 6, 20)]")
  inspect(next(d, a), content="[(50, 8, 6, 20)]")
  // a word longer at the end
  let c = frame([(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 40.0, 16.0, 1), (60.0, 10.0, 40.0, 16.0, 1), (100.0, 10.0, 8.0, 16.0, 1)])
  inspect(next(d, c), content="[(98, 8, 12, 20)]")
}

///|
test "more than half the window: whole" {
  let a = frame([(0.0, 0.0, 300.0, 300.0, 0)])
  let d = seen(a)
  let b = copy(a)
  b[8] = 0.0
  inspect(next(d, b), content="[(0, 0, -1, -1)]")
}

///|
test "in its clip, and in the window" {
  let a = frame([(100.0, 50.0, 200.0, 100.0, 0)])
  a[16] = 120.0
  a[17] = 60.0
  a[18] = 140.0
  a[19] = 70.0
  let d = seen(a)
  let b = copy(a)
  b[8] = 0.0
  inspect(next(d, b), content="[(118, 58, 24, 14)]")
  let c = frame([(-10.0, -10.0, 20.0, 20.0, 0)])
  let d = seen(c)
  let e = copy(c)
  e[8] = 0.0
  inspect(next(d, e), content="[(0, 0, 12, 12)]")
}

///|
test "turned: the circle about its point, its clip turned with it not cut by" {
  let a = frame([(100.0, 100.0, 20.0, 20.0, 0)])
  a[32] = 0.5
  a[33] = 110.0
  a[34] = 110.0
  a[16] = 105.0
  a[17] = 105.0
  a[18] = 115.0
  a[19] = 115.0
  let d = seen(a)
  let b = copy(a)
  b[32] = 0.6
  // (half its diagonal grown by the edge's reach: 12 √2)
  inspect(next(d, b), content="[(93.02943725152286, 93.02943725152286, 33.94112549695427, 33.94112549695427)]")
  // its clip where it is drawn (35): cut by it
  let c = copy(a)
  c[35] = 1.0
  let d = seen(c)
  let e = copy(c)
  e[32] = 0.6
  inspect(next(d, e), content="[(103, 103, 14, 14)]")
}

///|
test "a shadow: its blur's reach" {
  let a = frame([(100.0, 100.0, 20.0, 20.0, 2)])
  a[7] = 4.0
  let d = seen(a)
  let b = copy(a)
  b[8] = 0.0
  // (3 sigma, 2 more, the edge's 2)
  inspect(next(d, b), content="[(84, 84, 52, 52)]")
}

///|
test "a band whose pieces changed, the band the same" {
  // a band (11) of pieces 7 and 8 (the second piece instance's), then two piece instances (12)
  let a = frame([(50.0, 50.0, 30.0, 8.0, 11), (0.0, 0.0, 0.0, 0.0, 12), (0.0, 0.0, 0.0, 0.0, 12)])
  a[12] = 7.0
  a[13] = 2.0
  let d = seen(a)
  // a piece of the first piece instance: no band of it drawn
  let b = copy(a)
  b[56 + 0] = 0.25
  inspect(next(d, b), content="[]")
  // the band's
  let c = copy(b)
  c[112 + 8] = 0.25
  inspect(next(d, c), content="[(48, 48, 34, 12)]")
}

///|
test "a stream's picture: drawn again each frame" {
  let a = frame([(10.0, 10.0, 20.0, 20.0, 4)])
  a[20] = @damage.stream_tex_base + 3.0
  let d = seen(a)
  inspect(next(d, a), content="[(8, 8, 24, 24)]")
  // a native view's hole: as its numbers say
  let b = copy(a)
  b[20] = @damage.view_tex_base + 3.0
  let d = seen(b)
  inspect(next(d, b), content="[]")
}

///|
test "glass: the part reaching what its capture copies takes all of that in" {
  // frosted glass (5) over a ground, blur 4, its capture -1; a dot that changed under its margin, outside the glass
  let a = frame([(0.0, 0.0, 400.0, 300.0, 0), (200.0, 10.0, 4.0, 4.0, 0), (100.0, 20.0, 80.0, 20.0, 5)])
  a[112 + 7] = 4.0
  a[112 + 20] = -1.0
  let d = seen(a)
  let b = copy(a)
  b[56] = 190.0
  // (the glass's rect, 3 sigma, 2, and the edge's 2 round it: 84 … 196, 4 … 56; the dot's 188 … 206)
  inspect(next(d, b), content="[(84, 4, 122, 52)]")
  // far from it: only the dot
  let c = frame([(0.0, 0.0, 400.0, 300.0, 0), (300.0, 200.0, 4.0, 4.0, 0), (100.0, 20.0, 80.0, 20.0, 5)])
  c[112 + 7] = 4.0
  c[112 + 20] = -1.0
  let d = seen(c)
  let e = copy(c)
  e[56 + 8] = 0.0
  inspect(next(d, e), content="[(298, 198, 8, 8)]")
}

///|
test "parts far apart: each its own, up to four; near: one" {
  let a = frame([
    (0.0, 0.0, 400.0, 300.0, 0),
    (10.0, 10.0, 4.0, 4.0, 0),
    (300.0, 10.0, 4.0, 4.0, 0),
    (10.0, 200.0, 4.0, 4.0, 0),
    (300.0, 200.0, 4.0, 4.0, 0),
    (200.0, 100.0, 4.0, 4.0, 0),
    (20.0, 10.0, 4.0, 4.0, 0),
  ])
  let d = seen(a)
  let b = copy(a)
  for k in 1..<7 {
    b[k * 56 + 8] = 0.0
  }
  // (the dot at 20 near the one at 10: one part; five left, the pair whose rect grows least merged)
  inspect(
    next(d, b),
    content="[(8, 8, 18, 198), (298, 8, 8, 8), (298, 198, 8, 8), (198, 98, 8, 8)]",
  )
}

///|
test "another number of instances, two changes far apart: each its own, what is between kept" {
  // a dot near the top that changes colour, rows between, and a caret shown at the foot
  let rows = [(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 4.0, 4.0, 0)]
  for k in 0..<20 {
    rows.push((20.0, 30.0 + k.to_double() * 10.0, 100.0, 8.0, 1))
  }
  let a = frame(rows)
  let d = seen(a)
  let more = rows.copy()
  more.push((300.0, 280.0, 2.0, 12.0, 0))
  let b = frame(more)
  b[56 + 8] = 0.0
  inspect(next(d, b), content="[(8, 8, 8, 8), (298, 278, 6, 16)]")
}

///|
test "a list scrolled, a row more: each row where it was and where it is, one part, what is beside it kept" {
  // rows moved up 3 points with one more come in at the foot, none of them the same as any before, and a dot drawn
  // among them that stays
  let rows = [(0.0, 0.0, 400.0, 300.0, 0)]
  let moved = [(0.0, 0.0, 400.0, 300.0, 0)]
  for k in 0..<21 {
    if k < 20 {
      rows.push((20.0, 30.0 + k.to_double() * 10.0, 100.0, 8.0, 1))
    }
    moved.push((20.0, 27.0 + k.to_double() * 10.0, 100.0, 8.0, 1))
    if k == 9 {
      rows.push((300.0, 150.0, 4.0, 4.0, 0))
      moved.push((300.0, 150.0, 4.0, 4.0, 0))
    }
  }
  let d = seen(frame(rows))
  inspect(next(d, frame(moved)), content="[(18, 25, 104, 212)]")
}
