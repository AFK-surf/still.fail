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
