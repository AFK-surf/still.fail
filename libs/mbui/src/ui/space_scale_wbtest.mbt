///|
test "the spacing scale lists every named step once, in order, each larger than the one before" {
  let scale = space_scale()
  for i, sp in scale {
    assert_eq(sp.step(), i)
    if i > 0 {
      assert_true(sp.px() > scale[i - 1].px())
    }
  }
}

///|
/// Where a named step stands in the scale (space_scale), -1 for an `Exact` one: said for every step, so one added to
/// Space is added to the scale (space_scale_wbtest.mbt holds the two together).
fn Space::step(self : Space) -> Int {
  match self {
    S0 => 0
    SPx => 1
    S0_5 => 2
    S1 => 3
    S1_25 => 4
    S1_5 => 5
    S2 => 6
    S2_5 => 7
    S3 => 8
    S3_5 => 9
    S4 => 10
    S4_5 => 11
    S5 => 12
    S6 => 13
    S7 => 14
    S8 => 15
    S9 => 16
    S10 => 17
    S11 => 18
    S12 => 19
    S14 => 20
    S16 => 21
    S20 => 22
    S24 => 23
    S28 => 24
    S32 => 25
    S36 => 26
    S40 => 27
    S44 => 28
    S48 => 29
    S52 => 30
    S56 => 31
    S60 => 32
    S64 => 33
    S72 => 34
    S80 => 35
    S96 => 36
    Exact(_) => -1
  }
}
