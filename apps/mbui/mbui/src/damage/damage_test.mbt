///|
/// Instances as scene.mbt paints them: each a rect of `kind`, opaque white, clipped to all of a 400 × 300 window.
fn frame(rects : Array[(Double, Double, Double, Double, Int)]) -> FixedArray[Double] {
  let a = FixedArray::make(rects.length() * 60, 0.0)
  for k, r in rects {
    let o = k * 60
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
/// The parts of a 400 × 300 window where each of `a`'s instances changed.
fn parts_of(a : FixedArray[Double], captures? : Array[(Double, Double, Double, Double)] = []) -> Array[(Double, Double, Double, Double)] {
  let p = @damage.Parts::new()
  for k in 0..<(a.length() / 60) {
    p.add(p.reach_of(a, k, k + 1))
  }
  p.take(400.0, 300.0, captures)
}

///|
test "nothing said: no part; the whole said: all of it, and why" {
  let p = @damage.Parts::new()
  inspect(p.take(400.0, 300.0, []), content="[]")
  p.add((10.0, 10.0, 20.0, 20.0))
  p.whole(1)
  inspect(p.take(400.0, 300.0, []), content="[(0, 0, -1, -1)]")
  inspect(p.why(), content="1")
  inspect(p.take(400.0, 300.0, []), content="[]")
  inspect(p.why(), content="0")
}

///|
test "an instance: its rect, its edge's reach round it" {
  inspect(parts_of(frame([(100.0, 50.0, 20.0, 10.0, 0)])), content="[(98, 48, 24, 14)]")
}

///|
test "where it was and where it is, near: one part" {
  let p = @damage.Parts::new()
  p.add(p.reach_of(frame([(100.0, 50.0, 20.0, 10.0, 0)]), 0, 1))
  p.add(p.reach_of(frame([(130.0, 50.0, 20.0, 10.0, 0)]), 0, 1))
  inspect(p.take(400.0, 300.0, []), content="[(98, 48, 54, 14)]")
}

///|
test "more than half the window: whole" {
  inspect(parts_of(frame([(0.0, 0.0, 300.0, 300.0, 0)])), content="[(0, 0, -1, -1)]")
}

///|
test "in its clip, and in the window" {
  let a = frame([(100.0, 50.0, 200.0, 100.0, 0)])
  a[16] = 120.0
  a[17] = 60.0
  a[18] = 140.0
  a[19] = 70.0
  inspect(parts_of(a), content="[(118, 58, 24, 14)]")
  inspect(parts_of(frame([(-10.0, -10.0, 20.0, 20.0, 0)])), content="[(0, 0, 12, 12)]")
}

///|
test "turned: the circle about its point, its clip turned with it not cut by" {
  let a = frame([(100.0, 100.0, 20.0, 20.0, 0)])
  a[32] = 0.6
  a[33] = 110.0
  a[34] = 110.0
  a[16] = 105.0
  a[17] = 105.0
  a[18] = 115.0
  a[19] = 115.0
  // (half its diagonal grown by the edge's reach: 12 √2)
  inspect(parts_of(a), content="[(93.02943725152286, 93.02943725152286, 33.94112549695427, 33.94112549695427)]")
  // its clip where it is drawn (35): cut by it
  a[35] = 1.0
  inspect(parts_of(a), content="[(103, 103, 14, 14)]")
}

///|
test "a shadow: its blur's reach" {
  let a = frame([(100.0, 100.0, 20.0, 20.0, 2)])
  a[7] = 4.0
  // (3 sigma, 2 more, the edge's 2)
  inspect(parts_of(a), content="[(84, 84, 52, 52)]")
}

///|
test "pieces of shapes reach nothing of their own: their band holds them" {
  let a = frame([(50.0, 50.0, 30.0, 8.0, 11), (0.0, 0.0, 0.0, 0.0, 12)])
  a[12] = 0.0
  a[13] = 1.0
  inspect(parts_of(a), content="[(48, 48, 34, 12)]")
}

///|
test "a stream's picture, a native view's hole" {
  let a = frame([(10.0, 10.0, 20.0, 20.0, 4), (40.0, 10.0, 20.0, 20.0, 9)])
  a[20] = @damage.stream_tex_base + 3.0
  a[80] = @damage.view_tex_base + 3.0
  inspect(@damage.shows_stream(a, 0), content="true")
  inspect(@damage.shows_stream(a, 1), content="false")
}

///|
test "glass: the part reaching what its capture copies takes all of that in" {
  // frosted glass (5), blur 4, its capture -1; a dot that changed under its margin, outside the glass
  let g = frame([(100.0, 20.0, 80.0, 20.0, 5)])
  g[7] = 4.0
  g[20] = -1.0
  let captures = match @damage.capture_of(g, 0) {
    Some((_, r)) => [r]
    None => []
  }
  // (the glass's rect, 3 sigma, 2, and the edge's 2 round it: 84 … 196, 4 … 56; the dot's 188 … 196)
  inspect(captures, content="[(84, 4, 196, 56)]")
  inspect(parts_of(frame([(190.0, 10.0, 4.0, 4.0, 0)]), captures~), content="[(84, 4, 112, 52)]")
  // far from it: only the dot
  inspect(parts_of(frame([(300.0, 200.0, 4.0, 4.0, 0)]), captures~), content="[(298, 198, 8, 8)]")
  // no glass, or glass of no capture of its own
  inspect(@damage.capture_of(frame([(0.0, 0.0, 4.0, 4.0, 0)]), 0), content="None")
}

///|
test "parts far apart: each its own, up to four; near: one" {
  let a = frame([
    (10.0, 10.0, 4.0, 4.0, 0),
    (300.0, 10.0, 4.0, 4.0, 0),
    (10.0, 200.0, 4.0, 4.0, 0),
    (300.0, 200.0, 4.0, 4.0, 0),
    (200.0, 100.0, 4.0, 4.0, 0),
    (20.0, 10.0, 4.0, 4.0, 0),
  ])
  // (the dot at 20 near the one at 10: one part; five left, the pair whose rect grows least merged)
  inspect(parts_of(a), content="[(8, 8, 18, 198), (298, 8, 8, 8), (298, 198, 8, 8), (198, 98, 8, 8)]")
}

///|
test "the work counted: each instance reached, each rect said" {
  let p = @damage.Parts::new()
  let a = frame([(10.0, 10.0, 4.0, 4.0, 0), (20.0, 10.0, 4.0, 4.0, 0), (30.0, 10.0, 4.0, 4.0, 0)])
  p.add(p.reach_of(a, 0, 3))
  // (an empty rect said is no work)
  p.add(@damage.nowhere)
  inspect(p.work(), content="4")
  inspect(@damage.union((0.0, 0.0, 1.0, 1.0), @damage.nowhere), content="(0, 0, 1, 1)")
}

///|
test "an old view's instances compared: what differs drawn again where it was and is, the rest not" {
  let before = frame([(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 20.0, 20.0, 0), (300.0, 200.0, 20.0, 20.0, 0)])
  // the one in the middle moved: it alone
  let moved = frame([(0.0, 0.0, 400.0, 300.0, 0), (40.0, 10.0, 20.0, 20.0, 0), (300.0, 200.0, 20.0, 20.0, 0)])
  let p = @damage.Parts::new()
  p.add_changed(before, 3, moved, 3)
  let parts = p.take(400.0, 300.0, [])
  assert_eq(parts.length(), 1)
  let (x, _, w, _) = parts[0]
  assert_true(x < 10.0 && x + w > 60.0 && w < 60.0, msg="\{parts}")
  // nothing differs: nothing
  p.add_changed(before, 3, before, 3)
  assert_eq(p.take(400.0, 300.0, []), [])
  // one more at its end: that one
  let more = frame([(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 20.0, 20.0, 0), (300.0, 200.0, 20.0, 20.0, 0), (100.0, 100.0, 10.0, 10.0, 0)])
  p.add_changed(before, 3, more, 4)
  let parts = p.take(400.0, 300.0, [])
  assert_eq(parts.length(), 1)
  assert_true(parts[0].2 < 20.0, msg="\{parts}")
  // a shape's piece differs: all of it
  let piece = frame([(0.0, 0.0, 400.0, 300.0, 0), (10.0, 10.0, 20.0, 20.0, 12), (300.0, 200.0, 20.0, 20.0, 0)])
  p.add_changed(before, 3, piece, 3)
  assert_eq(p.take(400.0, 300.0, []), [(0.0, 0.0, -1.0, -1.0)])
}
