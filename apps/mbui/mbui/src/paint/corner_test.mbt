// A linked corner worked out from the roots given alone: the window's corner and the ranges as said, nothing read of
// where it is asked.

///|
let ranges : @paint.CornerFit = { least: 6.0, most: 34.0, near: 4.0, far: 16.0 }

///|
test "a linked corner from the roots given: the window's corner changing, it follows; too far in, or no window corner, alone" {
  let edge : @paint.CornerOf = Follow(Window, 6.0, 34.0)
  let mac : @paint.CornerRoots = { window: 16.0, fit: Some(ranges), zoom: 1.0 }
  let full : @paint.CornerRoots = { window: 0.0, fit: Some(ranges), zoom: 1.0 }
  assert_eq(edge.radius(mac), @paint.concentric(16.0, 6.0))
  assert_eq((edge.follows(mac), edge.inset(mac), edge.source(mac)), (true, Some(6.0), Some(16.0)))
  assert_eq(edge.radius(full), 34.0)
  assert_eq((edge.follows(full), edge.inset(full), edge.source(full)), (false, None, Some(0.0)))
  // (one following that, 6 in again: as the chain has it under each)
  let inner : @paint.CornerOf = Follow(edge, 6.0, 10.0)
  assert_eq(inner.radius(full), @paint.concentric(34.0, 6.0))
  assert_eq(inner.radius(mac), @paint.concentric(@paint.concentric(16.0, 6.0), 6.0))
  // (no ranges: any corner, any place)
  let deep : @paint.CornerOf = Follow(Window, 14.0, 34.0)
  let none : @paint.CornerRoots = { window: 16.0, fit: None, zoom: 1.0 }
  assert_eq(deep.radius(none), @paint.concentric(16.0, 14.0))
}

///|
test "a linked window corner is judged by its visible size after content zoom" {
  let edge : @paint.CornerOf = Follow(Window, 6.0, 28.0)
  let enlarged : @paint.CornerRoots = { window: 8.0, fit: Some(ranges), zoom: 2.0 }
  assert_true(edge.follows(enlarged))
  assert_eq(edge.radius(enlarged), @paint.concentric(8.0, 6.0))
  // The same small logical corner without magnification remains below the theme's minimum.
  assert_false(edge.follows({ ..enlarged, zoom: 1.0 }))
}
