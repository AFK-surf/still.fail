
///|
test "sp_from: the size words are said at to be drawn as sp_at draws them, its way back at every scale" {
  for scale in [1.0, 1.15, 1.3, 1.5, 1.8, 2.0, 2.5] {
    for v in [6.0, 8.0, 11.0, 13.0, 15.0, 17.0, 22.0, 30.0, 44.8, 120.0] {
      let back = sp_from(scale, sp_at(scale, v))
      assert_true((back - v).abs() < 1.0e-9, msg="\{scale} \{v}: \{back}")
    }
  }
}
