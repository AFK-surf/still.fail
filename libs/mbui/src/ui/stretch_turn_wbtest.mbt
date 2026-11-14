///|
test "a turned mark in a list stretched past its top turns about where the stretch puts it, with its rect" {
  // (a turning mark's spoke, as spokes_node draws it: a box at 100 down, 20 tall, turned about its middle; the list
  // stretched at its top: Android's at an end, the home list pulled down past its first row)
  let c = Ctx::new()
  c.ninst = 0
  c.push_inst(10.0, 100.0, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, 0xFFFFFFFFL, 1.0, 0.0, 0.0, 0.0, 0.0)
  let b = 0
  let a = c.inst
  a[b + 32] = 0.5
  a[b + 33] = 20.0
  a[b + 34] = 110.0
  let ov = stretch_amount(0.5)
  c.stretch_insts(0, c.ninst, ov, 0.0, 800.0, 0.0, 800.0)
  let mid = a[b + 1] + a[b + 3] / 2.0
  // (its rect moved down by the stretch: where it turns about with it, its middle still)
  assert_true(a[b + 1] > 100.0)
  assert_true((a[b + 34] - mid).abs() < 0.5, msg="turns about \{a[b + 34]}, its rect's middle \{mid}")
}
