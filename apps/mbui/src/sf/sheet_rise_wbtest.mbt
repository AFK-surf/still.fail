// SheetRise's two ways of working out a way from rest (sheet_below_as_before, its top's): the same curve.

///|
test "a sheet's way from rest worked out as before and by its top: the same curve, within 1e-9, on into a frame of another height" {
  for d in [40.0, 167.0, 333.0, 612.0] {
    for up in [true, false] {
      let r = SheetRise::new()
      r.risen = !up
      r.way = Some({ at: 0.0, up, u0: if up { 0.0 } else { d }, v0: 0.0, plan: d, kept: @ui.come_kept() })
      let mut t = -10.0
      while t <= @ui.move_most_ms + 20.0 {
        let before = sheet_below_as_before(up, d, t)
        let top = d - r.top_at(d, 0.0, t).0
        assert_true((before - top).abs() < 1.0e-9, msg="\{d} \{up} at \{t}: \{before} \{top}")
        // (the frame after laid out a hundredth of a point taller: by its top from there, no step)
        let next = d + 0.01 - r.top_at(d + 0.01, 0.0, t).0
        assert_true((next - before).abs() < 0.011, msg="\{d} \{up} at \{t}: \{before} then \{next}")
        t = t + 1000.0 / 120.0
      }
    }
  }
}

