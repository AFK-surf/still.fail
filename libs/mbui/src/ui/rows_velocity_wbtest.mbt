// A second draw can arrive less than a millisecond after the last position of the previous display frame.
// Use its actual time when comparing speeds, while still detecting a real change of direction.

///|
test "rows steady: a short sample uses its actual elapsed time" {
  let seen : Array[(Double, Double, Double)] = [
    (1693.2659, 1700.0, 414.4945),
    (1707.8590, 1716.0199, 404.1831),
    (1723.3215, 1731.1915, 389.0566),
    (1731.7273, 1731.7273, 388.4719),
  ]
  let (fault, _) = rows_steady_fault(seen, 1000.0 / 60.0, set_out=-1.0, turned=-1.0e9)
  assert_true(fault is None)
}

///|
test "rows steady: a short sample still reveals a real jolt" {
  let seen : Array[(Double, Double, Double)] = [
    (1693.2659, 1700.0, 414.4945),
    (1707.8590, 1716.0199, 404.1831),
    (1723.3215, 1731.1915, 389.0566),
    (1731.7273, 1731.7273, 397.0),
  ]
  let (fault, _) = rows_steady_fault(seen, 1000.0 / 60.0, set_out=-1.0, turned=-1.0e9)
  assert_true(fault is Some(_))
}

///|
test "rows steady: a way set out between the frames takes its speed up, and a whole step in that frame is a step all the same" {
  let f = 1000.0 / 60.0
  // (the way set out in the second frame: the rows on from where they were, faster than before)
  let on : Array[(Double, Double, Double)] = [(0.0, 0.0, 600.0), (f, f, 590.8), (2.0 * f, 2.0 * f, 575.0), (3.0 * f, 3.0 * f, 556.0)]
  let (fault, _) = rows_steady_fault(on, f, set_out=1.5 * f, turned=-1.0e9)
  assert_true(fault is None)
  // (a card's whole room put on in that frame: 144 in one frame, 9 and 11 round it)
  let step : Array[(Double, Double, Double)] = [(0.0, 0.0, 584.2), (f, f, 575.0), (2.0 * f, 2.0 * f, 430.5), (3.0 * f, 3.0 * f, 419.1)]
  let (fault, _) = rows_steady_fault(step, f, set_out=1.5 * f, turned=-1.0e9)
  assert_true(fault is Some(_))
  // (the same of a row not half open, what it holds not seen: none)
  let (fault, _) = rows_steady_fault(step, f, set_out=1.5 * f, turned=-1.0e9, faint=true)
  assert_true(fault is None)
}
