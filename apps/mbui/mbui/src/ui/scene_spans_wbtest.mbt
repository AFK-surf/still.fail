// A frame put together round layers drawn again (scene_spliced) only where each lies where the frame kept it: else
// said (a fault naming the layer: a test failing there, a host told it before it goes on): 0.1.7336 trapped in
// scene_spliced, past the frame's end, as a chat's list was scrolled; what put the layer there is still to be found.

///|
test "layers drawn again where the frame kept them: put together round them" {
  // (node, at, how many, pieces at, how many, now, pieces now, drawn into)
  let ok = [(10, 0, 4, 0, 1, 5, 1, 5), (20, 6, 2, 1, 0, 1, 0, 1)]
  assert_eq(scene_spans_wrong(ok, 10, 2), None)
}

///|
test "layers drawn again not where the frame kept them: said, each way" {
  let wrong = fn(spans) { scene_spans_wrong(spans, 10, 2) is Some(_) }
  // (one begun before the one before it ends)
  assert_true(wrong([(10, 0, 6, 0, 0, 6, 0, 6), (20, 4, 2, 0, 0, 2, 0, 2)]))
  // (one past the frame's instances)
  assert_true(wrong([(10, 8, 4, 0, 0, 4, 0, 4)]))
  // (one past its pieces)
  assert_true(wrong([(10, 0, 1, 1, 3, 1, 3, 1)]))
  // (one before 0, one with fewer than none)
  assert_true(wrong([(10, -1, 0, 0, 0, 0, 0, 0)]))
  assert_true(wrong([(10, 2, -3, 0, 0, 0, 0, 0)]))
  // (one drawn into fewer than it says it drew)
  assert_true(wrong([(10, 0, 2, 0, 0, 3, 0, 2)]))
}
